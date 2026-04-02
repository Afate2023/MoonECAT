///|
test "scan station address strategy seam keeps twincat path replaceable" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0U },
    { position: 1U, current_station_address: 0x2001U },
    { position: 2U, current_station_address: 0x2001U },
  ]
  let preserved = plan_scan_station_addresses_with_strategy(
    observed,
    PreserveExistingUniqueNonZero,
  )
  let twincat = plan_scan_station_addresses_with_strategy(
    observed,
    TwinCATCompatible,
  )
  assert_eq(preserved, [0x1001U, 0x1002U, 0x1003U])
  assert_eq(twincat, preserved)
}

///|
fn build_esm_response_frame(
  request : @protocol.EcFrame,
  data : Bytes,
  wkc : UInt,
) -> Bytes {
  let request_pdu = request.pdus[0]
  (
    {
      dst_mac: request.src_mac,
      src_mac: request.dst_mac,
      pdus: [
        {
          header: {
            command: request_pdu.header.command,
            index: request_pdu.header.index,
            address: request_pdu.header.address,
            len_flags: data.length().reinterpret_as_uint(),
            irq: request_pdu.header.irq,
          },
          data,
          wkc,
        },
      ],
    } : @protocol.EcFrame).encode()
}

///|
pub struct StrictRunTransitionNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut current_state : Byte
  mut error_indication : Bool
  mut status_code : UInt
  control_writes : Array[Byte]
}

///|
fn StrictRunTransitionNic::new(
  current_state : @protocol.EsmState,
  error_indication : Bool,
  status_code : UInt,
) -> StrictRunTransitionNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    current_state: current_state.to_byte(),
    error_indication,
    status_code,
    control_writes: [],
  }
}

///|
fn strict_status_bytes(nic : StrictRunTransitionNic) -> Bytes {
  let status = if nic.error_indication {
    nic.current_state | b'\x10'
  } else {
    nic.current_state
  }
  Bytes::from_array([status, b'\x00'])
}

///|
fn strict_status_code_bytes(status_code : UInt) -> Bytes {
  Bytes::from_array([
    (status_code & 0xFFU).reinterpret_as_int().to_byte(),
    ((status_code >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
  ])
}

///|
test "runtime required sii read word count expands to eeprom metadata size" {
  let bytes = Bytes::makei(128, fn(i) {
    match i {
      124 => b'\x0F'
      125 => b'\x00'
      126 => b'\x01'
      127 => b'\x00'
      _ => b'\x00'
    }
  })
  assert_eq(required_sii_read_word_count(bytes, 128), 512)
  assert_eq(required_sii_read_word_count(bytes, 600), 600)
}

///|
pub struct ActivePdoLengthsNic {
  mut next_response : Bytes
  mut pending_mailbox_response : Bytes
  mut is_open : Bool
  mut mailbox_ready : Bool
  mut send_timeout_poll_budget : Int
  mut mailbox_mapping_ready : Bool
  sm_windows : Array[Array[Byte]]
}

///|
fn ActivePdoLengthsNic::new(
  send_timeout_transactions? : Int = 0,
  require_mailbox_mapping_refresh? : Bool = false,
) -> ActivePdoLengthsNic {
  {
    next_response: Bytes::new(0),
    pending_mailbox_response: Bytes::new(0),
    is_open: true,
    mailbox_ready: false,
    send_timeout_poll_budget: send_timeout_transactions * 32,
    mailbox_mapping_ready: !require_mailbox_mapping_refresh,
    sm_windows: Array::makei(8, fn(_i) { Array::make(8, b'\x00') }),
  }
}

///|
fn mailbox_status_bytes(ready : Bool) -> Bytes {
  Bytes::makei(8, fn(i) {
    if i == 5 {
      if ready {
        b'\x08'
      } else {
        b'\x00'
      }
    } else {
      b'\x00'
    }
  })
}

///|
fn mailbox_sm_window_with_status(window : Array[Byte], ready : Bool) -> Bytes {
  Bytes::makei(@protocol.sm_entry_size, fn(i) {
    if i == 5 {
      if ready {
        b'\x08'
      } else {
        b'\x00'
      }
    } else if i < window.length() {
      window[i]
    } else {
      b'\x00'
    }
  })
}

///|
fn response_payload_for_object(
  index : UInt,
  subindex : Byte,
) -> Bytes raise @hal.EcError {
  match (index, subindex) {
    (0x1C12U, b'\x00') => Bytes::from_array([b'\x01'])
    (0x1C12U, b'\x01') => Bytes::from_array([b'\x02', b'\x16'])
    (0x1C13U, b'\x00') => Bytes::from_array([b'\x01'])
    (0x1C13U, b'\x01') => Bytes::from_array([b'\x02', b'\x1A'])
    (0x1602U, b'\x00') => Bytes::from_array([b'\x02'])
    (0x1602U, b'\x01') =>
      Bytes::from_array([b'\x60', b'\x40', b'\x00', b'\x10'])
    (0x1602U, b'\x02') =>
      Bytes::from_array([b'\x60', b'\xFF', b'\x00', b'\x20'])
    (0x1A02U, b'\x00') => Bytes::from_array([b'\x02'])
    (0x1A02U, b'\x01') =>
      Bytes::from_array([b'\x60', b'\x41', b'\x00', b'\x10'])
    (0x1A02U, b'\x02') =>
      Bytes::from_array([b'\x60', b'\x64', b'\x00', b'\x20'])
    _ => raise @hal.EcError::SdoAbort(0x06090011U)
  }
}

///|
fn build_sdo_upload_response_frame(
  station : UInt,
  counter : Byte,
  index : UInt,
  subindex : Byte,
  payload : Bytes,
) -> Bytes {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: station,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  let n_unused = 4 - payload.length()
  let command = b'\x43' | (n_unused.to_byte() << 2)
  let frame = Bytes::makei(16, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00'
    } else if i == 7 {
      b'\x30'
    } else if i == 8 {
      command
    } else if i == 9 {
      (index & 0xFFU).to_byte()
    } else if i == 10 {
      ((index >> 8) & 0xFFU).to_byte()
    } else if i == 11 {
      subindex
    } else if i < 12 + payload.length() {
      payload[i - 12]
    } else {
      b'\x00'
    }
  })
  Bytes::makei(128, fn(i) {
    if i < frame.length() {
      frame[i]
    } else {
      b'\x00'
    }
  })
}

///|
fn active_pdo_mailbox_response(data : Bytes) -> Bytes raise @hal.EcError {
  let mbh = @mailbox.MailboxHeader::from_bytes(data)
  let index = data[9].to_uint() | (data[10].to_uint() << 8)
  let subindex = data[11]
  let payload = response_payload_for_object(index, subindex)
  build_sdo_upload_response_frame(
    0x1001U,
    mbh.counter,
    index,
    subindex,
    payload,
  )
}

///|
fn build_sdo_download_response_frame(
  station : UInt,
  counter : Byte,
  index : UInt,
  subindex : Byte,
) -> Bytes {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: station,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  let frame = Bytes::makei(16, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00'
    } else if i == 7 {
      b'\x30'
    } else if i == 8 {
      b'\x60'
    } else if i == 9 {
      (index & 0xFFU).to_byte()
    } else if i == 10 {
      ((index >> 8) & 0xFFU).to_byte()
    } else if i == 11 {
      subindex
    } else {
      b'\x00'
    }
  })
  Bytes::makei(128, fn(i) {
    if i < frame.length() {
      frame[i]
    } else {
      b'\x00'
    }
  })
}

///|
pub impl @hal.Nic for ActivePdoLengthsNic with open_(name) {
  ignore(name)
  ActivePdoLengthsNic::new()
}

///|
pub impl @hal.Nic for ActivePdoLengthsNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  let station = @protocol.address_station(pdu.header.address)
  let sm0_status_addr = @protocol.reg_sm_base
  let sm1_status_addr = @protocol.reg_sm_base +
    @protocol.sm_entry_size.reinterpret_as_uint()
  if pdu.header.command is @protocol.FPWR {
    let sm_entry_size = @protocol.sm_entry_size.reinterpret_as_uint()
    if offset >= @protocol.reg_sm_base &&
      offset < @protocol.reg_sm_base + 8U * sm_entry_size {
      let sm_offset = offset - @protocol.reg_sm_base
      let sm_index = (sm_offset / sm_entry_size).reinterpret_as_int()
      if sm_index >= 0 && sm_index < self.sm_windows.length() {
        let intra_offset = (sm_offset % sm_entry_size).reinterpret_as_int()
        let window = self.sm_windows[sm_index]
        let mut i = 0
        while i < pdu.data.length() && intra_offset + i < window.length() {
          window[intra_offset + i] = pdu.data[i]
          i = i + 1
        }
        self.sm_windows[sm_index] = window
      }
    }
  }
  self.next_response = match pdu.header.command {
    @protocol.BRD =>
      build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    @protocol.APRD => {
      let response_data = if offset == @protocol.reg_station_address {
        Bytes::from_array([b'\x01', b'\x10'])
      } else {
        Bytes::new(pdu.data.length())
      }
      build_esm_response_frame(request, response_data, 1U)
    }
    @protocol.FPRD => {
      let response_data = if offset == sm0_status_addr {
        let ready = if self.send_timeout_poll_budget > 0 {
          self.send_timeout_poll_budget = self.send_timeout_poll_budget - 1
          true
        } else {
          false
        }
        mailbox_sm_window_with_status(self.sm_windows[0], ready)
      } else if offset == sm1_status_addr {
        mailbox_sm_window_with_status(
          self.sm_windows[1],
          self.mailbox_ready && self.mailbox_mapping_ready,
        )
      } else if offset == @protocol.reg_al_status {
        Bytes::from_array([@protocol.PreOp.to_byte(), b'\x00'])
      } else if offset == 0x1080U {
        if self.mailbox_mapping_ready {
          self.mailbox_ready = false
          self.pending_mailbox_response
        } else {
          Bytes::new(pdu.data.length())
        }
      } else {
        Bytes::new(pdu.data.length())
      }
      build_esm_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if station == 0x1001U &&
        (
          offset == @protocol.reg_sm_base ||
          offset ==
          @protocol.reg_sm_base + @protocol.sm_entry_size.reinterpret_as_uint()
        ) {
        self.mailbox_mapping_ready = true
      }
      if offset == 0x1000U && self.mailbox_mapping_ready {
        self.pending_mailbox_response = active_pdo_mailbox_response(pdu.data)
        self.mailbox_ready = true
      }
      build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    _ => build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for ActivePdoLengthsNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for ActivePdoLengthsNic with close(self) {
  self.is_open = false
}

///|
test "active process data lengths in preop use object mapping lengths" {
  let nic = ActivePdoLengthsNic::new()
  let mailbox_config : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let lengths = active_process_data_lengths_in_preop(
    nic,
    0x1001U,
    mailbox_config,
    @hal.Duration(1000L),
  )
  assert_eq(lengths, (Some(6), Some(6)))
}

///|
test "refine startup preparation in preop retries transient mailbox timeout" {
  let nic = ActivePdoLengthsNic::new(send_timeout_transactions=1)
  let preparation : SlaveStartupPreparation = {
    mapping: {
      sm_configs: [
        {
          physical_start: 0x1000U,
          length: 128U,
          control: b'\x26',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.MailboxOut,
        },
        {
          physical_start: 0x1080U,
          length: 128U,
          control: b'\x22',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.MailboxIn,
        },
        {
          physical_start: 0x1100U,
          length: 32U,
          control: b'\x64',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.ProcessDataOut,
        },
        {
          physical_start: 0x1200U,
          length: 16U,
          control: b'\x20',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.ProcessDataIn,
        },
      ],
      fmmu_configs: [
        {
          logical_start: 0x1000U,
          length: 32U,
          logical_start_bit: b'\x00',
          logical_end_bit: b'\x07',
          physical_start: 0x1100U,
          physical_start_bit: b'\x00',
          direction: @mailbox.Outputs,
          activate: true,
        },
        {
          logical_start: 0x1020U,
          length: 16U,
          logical_start_bit: b'\x00',
          logical_end_bit: b'\x07',
          physical_start: 0x1200U,
          physical_start_bit: b'\x00',
          direction: @mailbox.Inputs,
          activate: true,
        },
      ],
      output_bytes: 32,
      input_bytes: 16,
    },
    dc_cycle_period_ns: None,
    startup_outputs: None,
    startup_mailbox_commands: [],
    mailbox_config: {
      out_address: 0x1000U,
      out_size: 128U,
      out_sm_index: 0,
      in_address: 0x1080U,
      in_size: 128U,
      in_sm_index: 1,
    },
    sii: ds402_sii_info([]),
    sii_categories: [],
  }
  let refined = refine_startup_preparation_in_preop(
    nic,
    0x1001U,
    0x1000U,
    preparation,
    @hal.Duration(1000L),
  )
  assert_eq(refined.mapping.sm_configs[2].length, 6U)
  assert_eq(refined.mapping.sm_configs[3].length, 6U)
  assert_eq(refined.mapping.fmmu_configs[0].length, 6U)
  assert_eq(refined.mapping.fmmu_configs[1].length, 6U)
  assert_eq(refined.mapping.output_bytes, 6)
  assert_eq(refined.mapping.input_bytes, 6)
}

///|
test "process data length refresh fallback only handles mailbox bootstrap failures" {
  assert_true(
    should_retry_process_data_lengths_after_mailbox_refresh(Ok((None, None))),
  )
  assert_true(
    should_retry_process_data_lengths_after_mailbox_refresh(
      Err(@hal.EcError::MailboxTimeout),
    ),
  )
  assert_true(
    should_retry_process_data_lengths_after_mailbox_refresh(
      Err(
        @hal.EcError::MailboxProtocol(
          "input mailbox SyncManager is deactivated/reset: start=0x0",
        ),
      ),
    ),
  )
  assert_true(
    !should_retry_process_data_lengths_after_mailbox_refresh(
      Ok((Some(6), None)),
    ),
  )
  assert_true(
    !should_retry_process_data_lengths_after_mailbox_refresh(
      Err(@hal.EcError::SdoAbort(0x06090011U)),
    ),
  )
}

///|
test "refine startup preparation in preop refreshes mailbox mapping before retry" {
  let nic = ActivePdoLengthsNic::new(require_mailbox_mapping_refresh=true)
  let preparation : SlaveStartupPreparation = {
    mapping: {
      sm_configs: [
        {
          physical_start: 0x1000U,
          length: 128U,
          control: b'\x26',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.MailboxOut,
        },
        {
          physical_start: 0x1080U,
          length: 128U,
          control: b'\x22',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.MailboxIn,
        },
        {
          physical_start: 0x1100U,
          length: 32U,
          control: b'\x64',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.ProcessDataOut,
        },
        {
          physical_start: 0x1200U,
          length: 16U,
          control: b'\x20',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.ProcessDataIn,
        },
      ],
      fmmu_configs: [
        {
          logical_start: 0x1000U,
          length: 32U,
          logical_start_bit: b'\x00',
          logical_end_bit: b'\x07',
          physical_start: 0x1100U,
          physical_start_bit: b'\x00',
          direction: @mailbox.Outputs,
          activate: true,
        },
        {
          logical_start: 0x1020U,
          length: 16U,
          logical_start_bit: b'\x00',
          logical_end_bit: b'\x07',
          physical_start: 0x1200U,
          physical_start_bit: b'\x00',
          direction: @mailbox.Inputs,
          activate: true,
        },
      ],
      output_bytes: 32,
      input_bytes: 16,
    },
    dc_cycle_period_ns: None,
    startup_outputs: None,
    startup_mailbox_commands: [],
    mailbox_config: {
      out_address: 0x1000U,
      out_size: 128U,
      out_sm_index: 0,
      in_address: 0x1080U,
      in_size: 128U,
      in_sm_index: 1,
    },
    sii: ds402_sii_info([]),
    sii_categories: [],
  }
  let refined = refine_startup_preparation_in_preop(
    nic,
    0x1001U,
    0x1000U,
    preparation,
    @hal.Duration(1000L),
  )
  assert_eq(refined.mapping.sm_configs[2].length, 6U)
  assert_eq(refined.mapping.sm_configs[3].length, 6U)
  assert_eq(refined.mapping.fmmu_configs[0].length, 6U)
  assert_eq(refined.mapping.fmmu_configs[1].length, 6U)
  assert_eq(refined.mapping.output_bytes, 6)
  assert_eq(refined.mapping.input_bytes, 6)
}

///|
fn ds402_general_category(ds402_channels : Byte) -> @mailbox.SiiCategoryEntry {
  let payload = Array::make(20, b'\x00')
  payload[5] = b'\x0C'
  payload[9] = ds402_channels
  {
    category: @mailbox.General,
    type_code: 30U,
    data: Bytes::from_array(payload),
  }
}

///|
fn ds402_rxpdo_category_with_leading_target() -> @mailbox.SiiCategoryEntry {
  {
    category: @mailbox.RxPdo,
    type_code: 51U,
    data: Bytes::from_array([
      b'\x00', b'\x16', b'\x02', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x7A',
      b'\x60', b'\x00', b'\x00', b'\x00', b'\x20', b'\x00', b'\x00', b'\x40', b'\x60',
      b'\x00', b'\x00', b'\x00', b'\x10', b'\x00', b'\x00',
    ]),
  }
}

///|
fn ds402_rxpdo_category_with_mode() -> @mailbox.SiiCategoryEntry {
  {
    category: @mailbox.RxPdo,
    type_code: 51U,
    data: Bytes::from_array([
      b'\x00', b'\x16', b'\x03', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x7A',
      b'\x60', b'\x00', b'\x00', b'\x00', b'\x20', b'\x00', b'\x00', b'\x40', b'\x60',
      b'\x00', b'\x00', b'\x00', b'\x10', b'\x00', b'\x00', b'\x60', b'\x60', b'\x00',
      b'\x00', b'\x00', b'\x08', b'\x00', b'\x00',
    ]),
  }
}

///|
fn ds402_txpdo_category() -> @mailbox.SiiCategoryEntry {
  {
    category: @mailbox.TxPdo,
    type_code: 50U,
    data: Bytes::from_array([
      b'\x00', b'\x1A', b'\x02', b'\x03', b'\x00', b'\x00', b'\x00', b'\x00', b'\x41',
      b'\x60', b'\x00', b'\x00', b'\x00', b'\x10', b'\x00', b'\x00', b'\x64', b'\x60',
      b'\x00', b'\x00', b'\x00', b'\x20', b'\x00', b'\x00',
    ]),
  }
}

///|
fn ds402_sii_info(
  categories : Array[@mailbox.SiiCategoryEntry],
) -> @mailbox.SiiFullInfo {
  let mut general : @mailbox.SiiGeneral? = None
  for entry in categories {
    if entry.category == @mailbox.General {
      general = Some(
        @mailbox.parse_sii_general(entry.data) catch {
          _ => panic()
        },
      )
      break
    }
  }
  let rx_pdo : Array[@mailbox.SiiPdo] = []
  let tx_pdo : Array[@mailbox.SiiPdo] = []
  for entry in categories {
    if entry.category == @mailbox.RxPdo {
      for pdo in @mailbox.parse_sii_pdo(entry.data) {
        rx_pdo.push(pdo)
      }
    }
    if entry.category == @mailbox.TxPdo {
      for pdo in @mailbox.parse_sii_pdo(entry.data) {
        tx_pdo.push(pdo)
      }
    }
  }
  {
    eeprom: Bytes::new(128),
    preamble: {
      pdi_control: 0U,
      pdi_config: 0U,
      sync_impulse_length_raw: 0U,
      pdi_config2: 0U,
      configured_station_alias: 0U,
      checksum: 0U,
      checksum_ok: true,
    },
    standard: { eeprom_size_raw: 0U, version: 1U },
    header: {
      vendor_id: 0U,
      product_code: 0U,
      revision: 0U,
      serial: 0U,
      bootstrap_rx_offset: 0U,
      bootstrap_rx_size: 0U,
      bootstrap_tx_offset: 0U,
      bootstrap_tx_size: 0U,
      mailbox_rx_offset: 0U,
      mailbox_rx_size: 0U,
      mailbox_tx_offset: 0U,
      mailbox_tx_size: 0U,
      mailbox_protocols: 0U,
      firmware_version: 0U,
      hardware_version: 0U,
      production_date_raw: 0U,
      pdi_control_1: b'\x00',
      esc_config_b0: b'\x00',
      pdi_config_1: 0U,
      pdi_config_1_ext: 0U,
      esc_config_b4: 0U,
      esc_config_b5: 0U,
      esc_config_b6: 0U,
      checksum_b: 0U,
      esc_config_b_present: false,
    },
    categories,
    strings: [],
    general,
    timeouts: None,
    fmmu: [],
    fmmu_ex: [],
    sync_managers: [],
    sync_units: [],
    tx_pdo,
    rx_pdo,
    dc_clocks: [],
  }
}

///|
pub impl @hal.Nic for StrictRunTransitionNic with open_(name) {
  ignore(name)
  StrictRunTransitionNic::new(@protocol.EsmState::Init, false, 0U)
}

///|
pub impl @hal.Nic for StrictRunTransitionNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_al_status {
        strict_status_bytes(self)
      } else if offset == @protocol.reg_al_status_code {
        strict_status_code_bytes(self.status_code)
      } else {
        Bytes::new(pdu.data.length())
      }
      build_esm_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
        let control = pdu.data[0]
        self.control_writes.push(control)
        let requested_state = control & b'\x0F'
        let acknowledge = (control & b'\x10') != b'\x00'
        if acknowledge {
          self.error_indication = false
          self.status_code = 0U
        }
        if requested_state != self.current_state {
          let current = @protocol.EsmState::from_byte(self.current_state)
          let target = @protocol.EsmState::from_byte(requested_state)
          if current.can_transition(target) {
            self.current_state = requested_state
            self.error_indication = false
            self.status_code = 0U
          } else {
            self.error_indication = true
            self.status_code = 0x0011U
          }
        }
      }
      build_esm_response_frame(request, strict_status_bytes(self), 1U)
    }
    _ => build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for StrictRunTransitionNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for StrictRunTransitionNic with close(self) {
  self.is_open = false
}

///|
pub struct Ds402OpNeedsShutdownControlwordNic {
  mut next_response : Bytes
  mut pending_mailbox_response : Bytes
  mut is_open : Bool
  mut current_state : Byte
  mut op_request_pending : Bool
  mut mailbox_ready : Bool
  mut observed_shutdown_seed : Bool
  mut observed_mode_seed : Bool
}

///|
fn Ds402OpNeedsShutdownControlwordNic::new() -> Ds402OpNeedsShutdownControlwordNic {
  {
    next_response: Bytes::new(0),
    pending_mailbox_response: Bytes::new(0),
    is_open: true,
    current_state: @protocol.EsmState::SafeOp.to_byte(),
    op_request_pending: false,
    mailbox_ready: false,
    observed_shutdown_seed: false,
    observed_mode_seed: false,
  }
}

///|
fn ds402_op_status_bytes(nic : Ds402OpNeedsShutdownControlwordNic) -> Bytes {
  Bytes::from_array([nic.current_state, b'\x00'])
}

///|
pub impl @hal.Nic for Ds402OpNeedsShutdownControlwordNic with open_(name) {
  ignore(name)
  Ds402OpNeedsShutdownControlwordNic::new()
}

///|
pub impl @hal.Nic for Ds402OpNeedsShutdownControlwordNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  let sm0_status_addr = @protocol.reg_sm_base
  let sm1_status_addr = @protocol.reg_sm_base +
    @protocol.sm_entry_size.reinterpret_as_uint()
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_al_status {
        ds402_op_status_bytes(self)
      } else if offset == sm0_status_addr {
        mailbox_status_bytes(false)
      } else if offset == sm1_status_addr {
        mailbox_status_bytes(self.mailbox_ready)
      } else if offset == 0x1080U {
        self.mailbox_ready = false
        self.pending_mailbox_response
      } else {
        Bytes::new(pdu.data.length())
      }
      build_esm_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == 0x1000U {
        let mbh = @mailbox.MailboxHeader::from_bytes(pdu.data)
        if pdu.data.length() > 11 {
          let index = pdu.data[9].to_uint() | (pdu.data[10].to_uint() << 8)
          let subindex = pdu.data[11]
          if index == 0x6060U &&
            subindex == b'\x00' &&
            pdu.data.length() > 12 &&
            pdu.data[12] == b'\x08' {
            self.observed_mode_seed = true
          }
          self.pending_mailbox_response = build_sdo_download_response_frame(
            0x1001U,
            mbh.counter,
            index,
            subindex,
          )
          self.mailbox_ready = true
        }
      }
      if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
        let requested_state = pdu.data[0] & b'\x0F'
        let current = @protocol.EsmState::from_byte(self.current_state)
        let target = @protocol.EsmState::from_byte(requested_state)
        if current == @protocol.EsmState::SafeOp &&
          target == @protocol.EsmState::Op {
          self.op_request_pending = true
        } else if current.can_transition(target) {
          self.current_state = requested_state
        }
      }
      build_esm_response_frame(request, ds402_op_status_bytes(self), 1U)
    }
    @protocol.LRW | @protocol.LWR => {
      if pdu.data.length() >= 6 &&
        pdu.data[4] == b'\x06' &&
        pdu.data[5] == b'\x00' {
        self.observed_shutdown_seed = true
      }
      if self.op_request_pending &&
        self.observed_shutdown_seed &&
        self.observed_mode_seed {
        self.current_state = @protocol.EsmState::Op.to_byte()
        self.op_request_pending = false
      }
      build_esm_response_frame(request, pdu.data, 1U)
    }
    _ => build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for Ds402OpNeedsShutdownControlwordNic with recv(
  self,
  timeout~,
) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for Ds402OpNeedsShutdownControlwordNic with close(self) {
  self.is_open = false
}

///|
test "runtime startup transition recovers SafeOp configuration error to init" {
  let nic = StrictRunTransitionNic::new(
    @protocol.EsmState::SafeOp,
    true,
    0x0016U,
  )
  let timeout = @hal.Duration(1000L)
  let ok = attempt_transition_slave_to_target(
    nic,
    0x1001U,
    @protocol.EsmState::Init,
    timeout,
    @protocol.default_esm_timeout_policy(),
  )
  assert_true(ok)
  assert_eq(nic.control_writes.length(), 2)
  assert_eq(
    nic.control_writes[0],
    @protocol.EsmState::SafeOp.to_byte() | b'\x10',
  )
  assert_eq(nic.control_writes[1] & b'\x0F', @protocol.EsmState::Init.to_byte())
}

///|
test "runtime startup transition rolls PreOp configuration error back to init" {
  let nic = StrictRunTransitionNic::new(
    @protocol.EsmState::PreOp,
    true,
    0x001EU,
  )
  let timeout = @hal.Duration(1000L)
  let ok = attempt_transition_slave_to_target(
    nic,
    0x1001U,
    @protocol.PreOp,
    timeout,
    @protocol.default_esm_timeout_policy(),
  )
  assert_true(ok)
  assert_eq(nic.control_writes.length(), 3)
  assert_eq(
    nic.control_writes[0],
    @protocol.EsmState::PreOp.to_byte() | b'\x10',
  )
  assert_eq(nic.control_writes[1] & b'\x0F', @protocol.EsmState::Init.to_byte())
  assert_eq(
    nic.control_writes[2] & b'\x0F',
    @protocol.EsmState::PreOp.to_byte(),
  )
}

///|
test "runtime operational startup steps preconfigure dc before op" {
  let steps = build_operational_startup_steps(true, true)
  assert_eq(steps.length(), 5)
  assert_eq(steps[0], TransitionToSafeOp)
  assert_eq(steps[1], DcPreconfigure)
  assert_eq(steps[2], WarmupProcessData)
  assert_eq(steps[3], ValidateSmWatchdog)
  assert_eq(steps[4], TransitionToOp)
}

///|
test "runtime operational startup steps omit dc and warmup when not needed" {
  let steps = build_operational_startup_steps(false, false)
  assert_eq(steps, [TransitionToSafeOp, ValidateSmWatchdog, TransitionToOp])
}

///|
test "runtime startup recovery rolls back init for preop configuration faults" {
  assert_eq(
    classify_startup_recovery_strategy(
      Some(@protocol.EsmState::PreOp),
      @protocol.EsmState::Op,
      Some(0x0016U),
    ),
    RollbackToInit,
  )
  assert_eq(
    classify_startup_recovery_strategy(
      Some(@protocol.EsmState::PreOp),
      @protocol.EsmState::SafeOp,
      Some(0x001DU),
    ),
    RollbackToInit,
  )
}

///|
test "runtime startup recovery keeps safeop for op-entry readiness faults" {
  assert_eq(
    classify_startup_recovery_strategy(
      Some(@protocol.EsmState::SafeOp),
      @protocol.EsmState::Op,
      Some(0x001BU),
    ),
    HoldSafeOp,
  )
  assert_eq(
    classify_startup_recovery_strategy(
      Some(@protocol.EsmState::SafeOp),
      @protocol.EsmState::Op,
      Some(0x002DU),
    ),
    HoldSafeOp,
  )
}

///|
test "runtime startup recovery retries unknown transient faults" {
  assert_eq(
    classify_startup_recovery_strategy(
      Some(@protocol.EsmState::PreOp),
      @protocol.EsmState::SafeOp,
      Some(0x0011U),
    ),
    RetryTargetPath,
  )
  assert_eq(
    classify_startup_recovery_strategy(None, @protocol.EsmState::Op, None),
    RetryTargetPath,
  )
}

///|
test "derive_startup_outputs seeds ds402 shutdown controlword at mapped offset" {
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 6,
    input_bytes: 2,
  }
  let outputs = derive_startup_outputs(
    mapping,
    ds402_sii_info([
      ds402_general_category(b'\x01'),
      ds402_rxpdo_category_with_leading_target(),
    ]),
  )
  guard outputs is Some(seed) else { fail("expected DS402 startup outputs") }
  assert_eq(
    seed,
    Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00', b'\x06', b'\x00']),
  )
}

///|
test "derive_startup_outputs seeds ds402 mode byte when available" {
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 7,
    input_bytes: 2,
  }
  let outputs = derive_startup_outputs(
    mapping,
    ds402_sii_info([
      ds402_general_category(b'\x01'),
      ds402_rxpdo_category_with_mode(),
    ]),
  )
  guard outputs is Some(seed) else { fail("expected DS402 startup outputs") }
  assert_eq(
    seed,
    Bytes::from_array([
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x06', b'\x00', b'\x08',
    ]),
  )
}

///|
test "derive_startup_mailbox_commands emits ds402 safeop-to-op mode command" {
  let commands = derive_startup_mailbox_commands(
    ds402_sii_info([
      ds402_general_category(b'\x01'),
      ds402_rxpdo_category_with_mode(),
      ds402_txpdo_category(),
    ]),
  )
  assert_eq(commands.length(), 5)
  assert_eq(commands[0].transition, PreOpToSafeOp)
  assert_eq(commands[0].index, 0x1600U)
  assert_eq(
    commands[0].data,
    Bytes::from_array([
      b'\x03', b'\x20', b'\x00', b'\x7A', b'\x60', b'\x10', b'\x00', b'\x40', b'\x60',
      b'\x08', b'\x00', b'\x60', b'\x60',
    ]),
  )
  assert_eq(commands[1].transition, PreOpToSafeOp)
  assert_eq(commands[1].index, 0x1A00U)
  assert_eq(
    commands[1].data,
    Bytes::from_array([
      b'\x02', b'\x10', b'\x00', b'\x41', b'\x60', b'\x20', b'\x00', b'\x64', b'\x60',
    ]),
  )
  assert_eq(commands[2].transition, PreOpToSafeOp)
  assert_eq(commands[2].index, 0x1C12U)
  assert_eq(commands[2].data, Bytes::from_array([b'\x01', b'\x00', b'\x16']))
  assert_eq(commands[3].transition, PreOpToSafeOp)
  assert_eq(commands[3].index, 0x1C13U)
  assert_eq(commands[3].data, Bytes::from_array([b'\x01', b'\x00', b'\x1A']))
  assert_eq(commands[4].transition, SafeOpToOp)
  assert_eq(commands[4].index, 0x6060U)
  assert_eq(commands[4].subindex, b'\x00')
  assert_eq(commands[4].data, Bytes::from_array([b'\x08']))
}

///|
test "apply_startup_mailbox_commands writes ds402 mode through mailbox sdo" {
  let nic = Ds402OpNeedsShutdownControlwordNic::new()
  apply_startup_mailbox_commands(
    nic,
    0x1001U,
    {
      out_address: 0x1000U,
      out_size: 128U,
      out_sm_index: 0,
      in_address: 0x1080U,
      in_size: 128U,
      in_sm_index: 1,
    },
    [
      {
        transition: SafeOpToOp,
        index: 0x6060U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x08']),
      },
    ],
    SafeOpToOp,
    @hal.Duration(1000L),
  )
  assert_true(nic.observed_mode_seed)
}

///|
test "runtime op transition reaches op when ds402 startup outputs are preseeded" {
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 7,
    input_bytes: 2,
  }
  let outputs = derive_startup_outputs(
    mapping,
    ds402_sii_info([
      ds402_general_category(b'\x01'),
      ds402_rxpdo_category_with_mode(),
    ]),
  )
  guard outputs is Some(seed) else { fail("expected DS402 startup outputs") }
  let pdo_ctx = @protocol.PdoContext::build([(mapping, 0x1001U)], 0x1000U)
  pdo_ctx.set_slave_outputs(0x1001U, seed)
  let nic = Ds402OpNeedsShutdownControlwordNic::new()
  apply_startup_mailbox_commands(
    nic,
    0x1001U,
    {
      out_address: 0x1000U,
      out_size: 128U,
      out_sm_index: 0,
      in_address: 0x1080U,
      in_size: 128U,
      in_sm_index: 1,
    },
    derive_startup_mailbox_commands(
      ds402_sii_info([
        ds402_general_category(b'\x01'),
        ds402_rxpdo_category_with_mode(),
      ]),
    ),
    SafeOpToOp,
    @hal.Duration(1000L),
  )
  let fault = transition_slave_to_op_with_process_data(
    nic,
    0x1001U,
    pdo_ctx,
    @hal.Duration(1000L),
  )
  assert_true(fault is None)
  assert_true(nic.observed_shutdown_seed)
  assert_true(nic.observed_mode_seed)
  assert_eq(nic.current_state, @protocol.EsmState::Op.to_byte())
}

///|
pub struct StartupMappingNic {
  mut next_response : Bytes
  mut is_open : Bool
  sm_write_offsets : Array[UInt]
  fmmu_write_offsets : Array[UInt]
  sm_windows : Array[Bytes]
  mut deactivated_mailbox_in_readback : Bool
}

///|
fn StartupMappingNic::new() -> StartupMappingNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    sm_write_offsets: [],
    fmmu_write_offsets: [],
    sm_windows: Array::make(8, Bytes::make(8, b'\x00')),
    deactivated_mailbox_in_readback: false,
  }
}

///|
pub impl @hal.Nic for StartupMappingNic with open_(name) {
  ignore(name)
  StartupMappingNic::new()
}

///|
pub impl @hal.Nic for StartupMappingNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  if pdu.header.command is @protocol.FPWR {
    if offset >= @protocol.reg_sm_base &&
      offset <
      @protocol.reg_sm_base + 8U * @protocol.sm_entry_size.reinterpret_as_uint() {
      self.sm_write_offsets.push(offset)
      let sm_index = ((offset - @protocol.reg_sm_base) /
      @protocol.sm_entry_size.reinterpret_as_uint()).reinterpret_as_int()
      if sm_index >= 0 && sm_index < self.sm_windows.length() {
        self.sm_windows[sm_index] = pdu.data
      }
    }
    if offset >= @protocol.reg_fmmu_base &&
      offset <
      @protocol.reg_fmmu_base +
      8U * @protocol.fmmu_entry_size.reinterpret_as_uint() {
      self.fmmu_write_offsets.push(offset)
    }
  }
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset >= @protocol.reg_sm_base &&
        offset <
        @protocol.reg_sm_base +
        8U * @protocol.sm_entry_size.reinterpret_as_uint() {
        let sm_index = ((offset - @protocol.reg_sm_base) /
        @protocol.sm_entry_size.reinterpret_as_uint()).reinterpret_as_int()
        if sm_index == 1 && self.deactivated_mailbox_in_readback {
          Bytes::from_array([
            b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x30', b'\x02', b'\x01',
          ])
        } else if sm_index >= 0 && sm_index < self.sm_windows.length() {
          self.sm_windows[sm_index]
        } else {
          Bytes::new(pdu.data.length())
        }
      } else {
        Bytes::new(pdu.data.length())
      }
      build_esm_response_frame(request, response_data, 1U)
    }
    _ => build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for StartupMappingNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for StartupMappingNic with close(self) {
  self.is_open = false
}

///|
test "runtime mailbox mapping writes only mailbox sync managers" {
  let nic = StartupMappingNic::new()
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [
      {
        physical_start: 0x1000U,
        length: 128U,
        control: b'\x26',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.MailboxOut,
      },
      {
        physical_start: 0x1080U,
        length: 128U,
        control: b'\x22',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.MailboxIn,
      },
      {
        physical_start: 0x1100U,
        length: 32U,
        control: b'\x24',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.ProcessDataOut,
      },
      {
        physical_start: 0x1200U,
        length: 16U,
        control: b'\x20',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.ProcessDataIn,
      },
    ],
    fmmu_configs: [
      {
        logical_start: 0x1000U,
        length: 32U,
        logical_start_bit: b'\x00',
        logical_end_bit: b'\x07',
        physical_start: 0x1100U,
        physical_start_bit: b'\x00',
        direction: @mailbox.Outputs,
        activate: true,
      },
    ],
    output_bytes: 32,
    input_bytes: 16,
  }
  ignore(write_mailbox_mapping(nic, 0x1001U, mapping, @hal.Duration(1000L)))
  assert_eq(nic.sm_write_offsets.length(), 2)
  assert_eq(nic.sm_write_offsets[0], @protocol.reg_sm_base)
  assert_eq(
    nic.sm_write_offsets[1],
    @protocol.reg_sm_base + @protocol.sm_entry_size.reinterpret_as_uint(),
  )
  assert_eq(nic.fmmu_write_offsets.length(), 0)
}

///|
test "runtime mailbox mapping reports immediate readback mismatch" {
  let nic = StartupMappingNic::new()
  nic.deactivated_mailbox_in_readback = true
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [
      {
        physical_start: 0x1000U,
        length: 128U,
        control: b'\x26',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.MailboxOut,
      },
      {
        physical_start: 0x1080U,
        length: 128U,
        control: b'\x22',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.MailboxIn,
      },
    ],
    fmmu_configs: [],
    output_bytes: 0,
    input_bytes: 0,
  }
  let result = try? write_mailbox_mapping(
    nic,
    0x1001U,
    mapping,
    @hal.Duration(1000L),
  )
  match result {
    Err(@hal.EcError::MailboxProtocol(message)) => {
      assert_true(message.contains("readback mismatch"))
      assert_true(message.contains("SM1"))
      assert_true(message.contains("expected=0x"))
      assert_true(message.contains(" actual=0x"))
    }
    _ => fail("expected MailboxProtocol for mailbox readback mismatch")
  }
}

///|
test "runtime process-data mapping writes only process sync managers and fmmu" {
  let nic = StartupMappingNic::new()
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [
      {
        physical_start: 0x1000U,
        length: 128U,
        control: b'\x26',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.MailboxOut,
      },
      {
        physical_start: 0x1080U,
        length: 128U,
        control: b'\x22',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.MailboxIn,
      },
      {
        physical_start: 0x1100U,
        length: 32U,
        control: b'\x24',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.ProcessDataOut,
      },
      {
        physical_start: 0x1200U,
        length: 16U,
        control: b'\x20',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.ProcessDataIn,
      },
    ],
    fmmu_configs: [
      {
        logical_start: 0x1000U,
        length: 32U,
        logical_start_bit: b'\x00',
        logical_end_bit: b'\x07',
        physical_start: 0x1100U,
        physical_start_bit: b'\x00',
        direction: @mailbox.Outputs,
        activate: true,
      },
    ],
    output_bytes: 32,
    input_bytes: 16,
  }
  ignore(
    write_process_data_mapping(nic, 0x1001U, mapping, @hal.Duration(1000L)),
  )
  assert_eq(nic.sm_write_offsets.length(), 2)
  assert_eq(
    nic.sm_write_offsets[0],
    @protocol.reg_sm_base + 2U * @protocol.sm_entry_size.reinterpret_as_uint(),
  )
  assert_eq(
    nic.sm_write_offsets[1],
    @protocol.reg_sm_base + 3U * @protocol.sm_entry_size.reinterpret_as_uint(),
  )
  assert_eq(nic.fmmu_write_offsets.length(), 1)
  assert_eq(nic.fmmu_write_offsets[0], @protocol.reg_fmmu_base)
}

///|
test "SmWatchdogValidation struct construction and equality" {
  let config : @protocol.SmWatchdogConfig = {
    divider: 0x09C2U,
    pdi_time: 0x03E8U,
    pdata_time: 0x03E8U,
    pdata_status: true,
    pdata_counter: 0U,
  }
  let v1 : SmWatchdogValidation = {
    station: 0x1001U,
    config,
    watchdog_active: true,
  }
  let v2 : SmWatchdogValidation = {
    station: 0x1001U,
    config,
    watchdog_active: true,
  }
  assert_eq(v1, v2)
  assert_eq(v1.watchdog_active, true)
}

///|
test "SmWatchdogValidation inactive when pdata_status false" {
  let config : @protocol.SmWatchdogConfig = {
    divider: 0x09C2U,
    pdi_time: 0U,
    pdata_time: 0U,
    pdata_status: false,
    pdata_counter: 0U,
  }
  let v : SmWatchdogValidation = {
    station: 0x1001U,
    config,
    watchdog_active: false,
  }
  assert_eq(v.watchdog_active, false)
  assert_eq(v.config.pdata_status, false)
}

///|
test "lookup_esm_timeout_policy returns matching policy" {
  let policy : @protocol.EsmTimeoutPolicy = {
    init: Some(@hal.Duration(1_000_000_000L)),
    preop: Some(@hal.Duration(2_000_000_000L)),
    safeop: None,
    op: Some(@hal.Duration(5_000_000_000L)),
    boot: None,
  }
  let policies : Array[(UInt, @protocol.EsmTimeoutPolicy)] = [(0x1001U, policy)]
  let found = lookup_esm_timeout_policy(policies, 0x1001U)
  assert_eq(found, policy)
}

///|
test "lookup_esm_timeout_policy returns default when not found" {
  let policies : Array[(UInt, @protocol.EsmTimeoutPolicy)] = []
  let found = lookup_esm_timeout_policy(policies, 0x1001U)
  assert_eq(found, @protocol.default_esm_timeout_policy())
}

///|
test "RunStartupPreparation includes esm_timeout_policies field" {
  let prep : RunStartupPreparation = {
    pdo_ctx: @protocol.PdoContext::build([], 0U),
    expected_wkc: 0U,
    dc_cycle_period_ns: None,
    startup_mailbox_plans: [],
    esm_timeout_policies: [(0x1001U, @protocol.default_esm_timeout_policy())],
  }
  assert_eq(prep.esm_timeout_policies.length(), 1)
}
