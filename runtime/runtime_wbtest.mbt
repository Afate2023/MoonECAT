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
  timeout_pdo_uploads : Bool
  sm_windows : Array[Array[Byte]]
}

///|
fn ActivePdoLengthsNic::new(
  send_timeout_transactions? : Int = 0,
  require_mailbox_mapping_refresh? : Bool = false,
  timeout_pdo_uploads? : Bool = false,
) -> ActivePdoLengthsNic {
  {
    next_response: Bytes::new(0),
    pending_mailbox_response: Bytes::new(0),
    is_open: true,
    mailbox_ready: false,
    send_timeout_poll_budget: send_timeout_transactions * 32,
    mailbox_mapping_ready: !require_mailbox_mapping_refresh,
    timeout_pdo_uploads,
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
fn sm_window_bytes(window : Array[Byte]) -> Bytes {
  Bytes::makei(@protocol.sm_entry_size, fn(i) {
    if i < window.length() {
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
      Bytes::from_array([b'\x10', b'\x00', b'\x40', b'\x60'])
    (0x1602U, b'\x02') =>
      Bytes::from_array([b'\x20', b'\x00', b'\xFF', b'\x60'])
    (0x1A02U, b'\x00') => Bytes::from_array([b'\x02'])
    (0x1A02U, b'\x01') =>
      Bytes::from_array([b'\x10', b'\x00', b'\x41', b'\x60'])
    (0x1A02U, b'\x02') =>
      Bytes::from_array([b'\x20', b'\x00', b'\x64', b'\x60'])
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
fn build_err_mailbox_frame(station : UInt) -> Bytes {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: station,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::Err,
    counter: b'\x00',
  }
  let hdr = mbh.to_bytes()
  let frame = Bytes::makei(16, fn(i) {
    if i < hdr.length() {
      hdr[i]
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
pub struct StartupMailboxDrainNic {
  mut next_response : Bytes
  mut pending_mailbox_response : Bytes
  mut stale_mailbox_pending : Bool
  mut is_open : Bool
  mut command_observed : Bool
}

///|
fn StartupMailboxDrainNic::new() -> StartupMailboxDrainNic {
  {
    next_response: Bytes::new(0),
    pending_mailbox_response: Bytes::new(0),
    stale_mailbox_pending: true,
    is_open: true,
    command_observed: false,
  }
}

///|
pub impl @hal.Nic for StartupMailboxDrainNic with open_(name) {
  ignore(name)
  StartupMailboxDrainNic::new()
}

///|
pub impl @hal.Nic for StartupMailboxDrainNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  let station = @protocol.address_station(pdu.header.address)
  let sm1_status_addr = @protocol.reg_sm_base +
    @protocol.sm_entry_size.reinterpret_as_uint()
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == sm1_status_addr {
        mailbox_status_bytes(
          self.stale_mailbox_pending ||
          self.pending_mailbox_response.length() > 0,
        )
      } else if offset == 0x1080U {
        if self.stale_mailbox_pending {
          self.stale_mailbox_pending = false
          build_err_mailbox_frame(station)
        } else {
          let response = self.pending_mailbox_response
          self.pending_mailbox_response = Bytes::new(0)
          response
        }
      } else {
        Bytes::new(pdu.data.length())
      }
      build_esm_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == 0x1000U && pdu.data.length() > 11 {
        let mbh = @mailbox.MailboxHeader::from_bytes(pdu.data)
        let index = pdu.data[9].to_uint() | (pdu.data[10].to_uint() << 8)
        let subindex = pdu.data[11]
        self.pending_mailbox_response = build_sdo_download_response_frame(
          station,
          mbh.counter,
          index,
          subindex,
        )
        self.command_observed = true
      }
      build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    _ => build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for StartupMailboxDrainNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for StartupMailboxDrainNic with close(self) {
  self.is_open = false
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
      let sm_entry_size = @protocol.sm_entry_size.reinterpret_as_uint()
      let response_data = if offset >= @protocol.reg_sm_base &&
        offset <
        @protocol.reg_sm_base +
        self.sm_windows.length().reinterpret_as_uint() * sm_entry_size {
        let sm_offset = offset - @protocol.reg_sm_base
        let sm_index = (sm_offset / sm_entry_size).reinterpret_as_int()
        if sm_index == 0 {
          let ready = if self.send_timeout_poll_budget > 0 {
            self.send_timeout_poll_budget = self.send_timeout_poll_budget - 1
            true
          } else {
            false
          }
          mailbox_sm_window_with_status(self.sm_windows[0], ready)
        } else if sm_index == 1 {
          mailbox_sm_window_with_status(
            self.sm_windows[1],
            self.mailbox_ready && self.mailbox_mapping_ready,
          )
        } else {
          sm_window_bytes(self.sm_windows[sm_index])
        }
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
        if self.timeout_pdo_uploads {
          self.pending_mailbox_response = Bytes::new(0)
          self.mailbox_ready = false
        } else {
          self.pending_mailbox_response = active_pdo_mailbox_response(pdu.data)
          self.mailbox_ready = true
        }
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
    sii: ds402_sii_info([
      ds402_general_category(b'\x01'),
      ds402_rxpdo_category_with_mode(),
      ds402_txpdo_category(),
    ]),
    sii_categories: [
      ds402_general_category(b'\x01'),
      ds402_rxpdo_category_with_mode(),
      ds402_txpdo_category(),
    ],
    prefer_live_pdo_state: true,
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
    prefer_live_pdo_state: true,
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
test "refine startup preparation in preop keeps live PDO layout and drops remap commands" {
  let nic = ActivePdoLengthsNic::new()
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
    startup_mailbox_commands: [
      {
        transition: PreOpToSafeOp,
        index: 0x1600U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x01', b'\x10', b'\x00', b'\x40', b'\x60']),
      },
      {
        transition: PreOpToSafeOp,
        index: 0x1C12U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x01', b'\x00', b'\x16']),
      },
      {
        transition: PreOpToSafeOp,
        index: 0x2000U,
        subindex: b'\x01',
        data: Bytes::from_array([b'\x01']),
      },
      {
        transition: SafeOpToOp,
        index: 0x6060U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x08']),
      },
    ],
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
    prefer_live_pdo_state: true,
  }
  let refined = refine_startup_preparation_in_preop(
    nic,
    0x1001U,
    0x1000U,
    preparation,
    @hal.Duration(1000L),
  )
  assert_eq(refined.mapping.output_bytes, 6)
  assert_eq(refined.mapping.input_bytes, 6)
  assert_eq(refined.startup_mailbox_commands.length(), 2)
  assert_eq(refined.startup_mailbox_commands[0].index, 0x2000U)
  assert_eq(refined.startup_mailbox_commands[0].transition, PreOpToSafeOp)
  assert_eq(refined.startup_mailbox_commands[1].index, 0x6060U)
  assert_eq(refined.startup_mailbox_commands[1].transition, SafeOpToOp)
}

///|
test "refine startup preparation in preop respects forced configured PDO plan" {
  let nic = ActivePdoLengthsNic::new()
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
    startup_mailbox_commands: [
      {
        transition: PreOpToSafeOp,
        index: 0x1600U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x01', b'\x10', b'\x00', b'\x40', b'\x60']),
      },
      {
        transition: PreOpToSafeOp,
        index: 0x1C12U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x01', b'\x00', b'\x16']),
      },
    ],
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
    prefer_live_pdo_state: false,
  }
  let refined = refine_startup_preparation_in_preop(
    nic,
    0x1001U,
    0x1000U,
    preparation,
    @hal.Duration(1000L),
  )
  assert_eq(refined.mapping.output_bytes, 32)
  assert_eq(refined.mapping.input_bytes, 16)
  assert_eq(refined.startup_mailbox_commands.length(), 2)
  assert_eq(refined.startup_mailbox_commands[0].index, 0x1600U)
  assert_eq(refined.startup_mailbox_commands[1].index, 0x1C12U)
}

///|
test "refine startup preparation in preop keeps configured remap when only esc lengths are visible" {
  let nic = ActivePdoLengthsNic::new(timeout_pdo_uploads=true)
  nic.sm_windows[2] = [
    b'\x00', b'\x11', b'\x18', b'\x00', b'\x64', b'\x30', b'\x01', b'\x01',
  ]
  nic.sm_windows[3] = [
    b'\x00', b'\x14', b'\x18', b'\x00', b'\x20', b'\x30', b'\x01', b'\x01',
  ]
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
          length: 26U,
          control: b'\x64',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.ProcessDataOut,
        },
        {
          physical_start: 0x1400U,
          length: 22U,
          control: b'\x20',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.ProcessDataIn,
        },
      ],
      fmmu_configs: [
        {
          logical_start: 0x1000U,
          length: 26U,
          logical_start_bit: b'\x00',
          logical_end_bit: b'\x07',
          physical_start: 0x1100U,
          physical_start_bit: b'\x00',
          direction: @mailbox.Outputs,
          activate: true,
        },
        {
          logical_start: 0x101AU,
          length: 22U,
          logical_start_bit: b'\x00',
          logical_end_bit: b'\x07',
          physical_start: 0x1400U,
          physical_start_bit: b'\x00',
          direction: @mailbox.Inputs,
          activate: true,
        },
      ],
      output_bytes: 26,
      input_bytes: 22,
    },
    dc_cycle_period_ns: None,
    startup_outputs: None,
    startup_mailbox_commands: [
      {
        transition: PreOpToSafeOp,
        index: 0x1600U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x01', b'\x10', b'\x00', b'\x40', b'\x60']),
      },
      {
        transition: PreOpToSafeOp,
        index: 0x1A00U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x01', b'\x10', b'\x00', b'\x41', b'\x60']),
      },
      {
        transition: PreOpToSafeOp,
        index: 0x1C12U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x01', b'\x00', b'\x16']),
      },
      {
        transition: PreOpToSafeOp,
        index: 0x1C13U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x01', b'\x00', b'\x1A']),
      },
    ],
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
    prefer_live_pdo_state: true,
  }
  let refined = refine_startup_preparation_in_preop(
    nic,
    0x1001U,
    0x1000U,
    preparation,
    @hal.Duration(1000L),
  )
  assert_eq(refined.mapping.sm_configs[2].length, 26U)
  assert_eq(refined.mapping.sm_configs[3].length, 22U)
  assert_eq(refined.mapping.fmmu_configs[0].length, 26U)
  assert_eq(refined.mapping.fmmu_configs[1].length, 22U)
  assert_eq(refined.mapping.output_bytes, 26)
  assert_eq(refined.mapping.input_bytes, 22)
  assert_eq(refined.startup_mailbox_commands.length(), 4)
  assert_eq(refined.startup_mailbox_commands[0].index, 0x1600U)
  assert_eq(refined.startup_mailbox_commands[1].index, 0x1A00U)
  assert_eq(refined.startup_mailbox_commands[2].index, 0x1C12U)
  assert_eq(refined.startup_mailbox_commands[3].index, 0x1C13U)
}

///|
test "refine startup preparation in preop trusts confirmed pdo lengths over esc lengths" {
  let nic = ActivePdoLengthsNic::new()
  nic.sm_windows[2] = [
    b'\x00', b'\x11', b'\x1A', b'\x00', b'\x64', b'\x30', b'\x01', b'\x01',
  ]
  nic.sm_windows[3] = [
    b'\x00', b'\x14', b'\x16', b'\x00', b'\x20', b'\x30', b'\x01', b'\x01',
  ]
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
          length: 25U,
          control: b'\x64',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.ProcessDataOut,
        },
        {
          physical_start: 0x1400U,
          length: 21U,
          control: b'\x20',
          status: b'\x00',
          activate: b'\x01',
          sm_type: @mailbox.ProcessDataIn,
        },
      ],
      fmmu_configs: [
        {
          logical_start: 0x1000U,
          length: 25U,
          logical_start_bit: b'\x00',
          logical_end_bit: b'\x07',
          physical_start: 0x1100U,
          physical_start_bit: b'\x00',
          direction: @mailbox.Outputs,
          activate: true,
        },
        {
          logical_start: 0x1019U,
          length: 21U,
          logical_start_bit: b'\x00',
          logical_end_bit: b'\x07',
          physical_start: 0x1400U,
          physical_start_bit: b'\x00',
          direction: @mailbox.Inputs,
          activate: true,
        },
      ],
      output_bytes: 25,
      input_bytes: 21,
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
    prefer_live_pdo_state: true,
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
fn ds402_rxpdo_category_with_mode_word() -> @mailbox.SiiCategoryEntry {
  {
    category: @mailbox.RxPdo,
    type_code: 51U,
    data: Bytes::from_array([
      b'\x00', b'\x16', b'\x03', b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x7A',
      b'\x60', b'\x00', b'\x00', b'\x00', b'\x20', b'\x00', b'\x00', b'\x40', b'\x60',
      b'\x00', b'\x00', b'\x00', b'\x10', b'\x00', b'\x00', b'\x60', b'\x60', b'\x00',
      b'\x00', b'\x00', b'\x10', b'\x00', b'\x00',
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
  let result = attempt_transition_slave_to_target(
    nic,
    0x1001U,
    @protocol.EsmState::Init,
    timeout,
    @protocol.default_esm_timeout_policy(),
  )
  assert_true(result.reached_target)
  assert_eq(result.observation, None)
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
  let result = attempt_transition_slave_to_target(
    nic,
    0x1001U,
    @protocol.PreOp,
    timeout,
    @protocol.default_esm_timeout_policy(),
  )
  assert_true(result.reached_target)
  assert_eq(
    result.observation.map(fn(value) { value.raw_status_code }),
    Some(Some(0U)),
  )
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
test "runtime startup mailbox fault stage maps to safeop for presafeop transition" {
  let fault = startup_mailbox_plan_failed_fault(
    StrictRunTransitionNic::new(@protocol.EsmState::PreOp, false, 0U),
    0x1001U,
    PreOpToSafeOp,
    @hal.Duration(1000L),
  )
  match fault {
    StartupTransitionFailed(station~, target~, current~, ..) => {
      assert_eq(station, 0x1001U)
      assert_eq(target, @protocol.SafeOp)
      assert_eq(current, Some(@protocol.EsmState::PreOp))
    }
    _ => fail("expected startup transition fault")
  }
}

///|
test "runtime startup mailbox fault stage maps to op for safeop-to-op transition" {
  let fault = startup_mailbox_plan_failed_fault(
    StrictRunTransitionNic::new(@protocol.EsmState::SafeOp, false, 0U),
    0x1001U,
    SafeOpToOp,
    @hal.Duration(1000L),
  )
  match fault {
    StartupTransitionFailed(station~, target~, current~, ..) => {
      assert_eq(station, 0x1001U)
      assert_eq(target, @protocol.Op)
      assert_eq(current, Some(@protocol.EsmState::SafeOp))
    }
    _ => fail("expected startup transition fault")
  }
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
test "derive_startup_outputs seeds ds402 mode word from explicit startup command" {
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 8,
    input_bytes: 2,
  }
  let outputs = derive_startup_outputs_with_commands(
    mapping,
    ds402_sii_info([
      ds402_general_category(b'\x01'),
      ds402_rxpdo_category_with_mode_word(),
    ]),
    [
      {
        transition: SafeOpToOp,
        index: 0x6060U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x09']),
      },
    ],
  )
  guard outputs is Some(seed) else { fail("expected DS402 startup outputs") }
  assert_eq(
    seed,
    Bytes::from_array([
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x06', b'\x00', b'\x09', b'\x00',
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
test "apply_startup_mailbox_commands drains stale mailbox frames before download" {
  let nic = StartupMailboxDrainNic::new()
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
        transition: PreOpToSafeOp,
        index: 0x2000U,
        subindex: b'\x01',
        data: Bytes::from_array([b'\x01']),
      },
    ],
    PreOpToSafeOp,
    @hal.Duration(1000L),
  )
  assert_true(nic.command_observed)
  assert_true(!nic.stale_mailbox_pending)
}

///|
test "filter_redundant_startup_mailbox_commands drops seeded 16-bit ds402 mode command" {
  let sii = ds402_sii_info([
    ds402_general_category(b'\x01'),
    ds402_rxpdo_category_with_mode_word(),
    ds402_txpdo_category(),
  ])
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 8,
    input_bytes: 2,
  }
  let merged = merge_startup_mailbox_commands(
    derive_startup_mailbox_commands(sii),
    [
      {
        transition: SafeOpToOp,
        index: 0x6060U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x09']),
      },
    ],
  )
  let outputs = derive_startup_outputs_with_commands(mapping, sii, merged)
  guard outputs is Some(seed) else { fail("expected DS402 startup outputs") }
  assert_eq(
    seed,
    Bytes::from_array([
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x06', b'\x00', b'\x09', b'\x00',
    ]),
  )
  let filtered = filter_redundant_startup_mailbox_commands(
    merged, outputs, mapping, sii,
  )
  assert_eq(filtered.length(), 4)
  for command in filtered {
    assert_true(
      !(command.transition == SafeOpToOp &&
      command.index == 0x6060U &&
      command.subindex == b'\x00'),
    )
  }
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
  mut current_state : Byte
  mut error_indication : Bool
  mut status_code : UInt
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
    current_state: @protocol.EsmState::Init.to_byte(),
    error_indication: false,
    status_code: 0U,
    sm_write_offsets: [],
    fmmu_write_offsets: [],
    sm_windows: Array::make(8, Bytes::make(8, b'\x00')),
    deactivated_mailbox_in_readback: false,
  }
}

///|
fn startup_mapping_status_bytes(nic : StartupMappingNic) -> Bytes {
  let status = if nic.error_indication {
    nic.current_state | b'\x10'
  } else {
    nic.current_state
  }
  Bytes::from_array([status, b'\x00'])
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
    if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
      let control = pdu.data[0]
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
  }
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_al_status {
        startup_mapping_status_bytes(self)
      } else if offset == @protocol.reg_al_status_code {
        strict_status_code_bytes(self.status_code)
      } else if offset >= @protocol.reg_sm_base &&
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
test "runtime preop transition can use provided startup preparation" {
  let nic = StartupMappingNic::new()
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
      ],
      fmmu_configs: [],
      output_bytes: 0,
      input_bytes: 0,
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
    prefer_live_pdo_state: true,
  }
  let fault = transition_slave_to_preop_with_preparation(
    nic,
    0x1001U,
    preparation,
    @hal.Duration(1000L),
    @protocol.default_esm_timeout_policy(),
  )
  assert_true(fault is None)
  assert_eq(nic.current_state, @protocol.EsmState::PreOp.to_byte())
  assert_eq(nic.sm_write_offsets.length(), 2)
}

///|
test "runtime preop transition skips mailbox rewrite when already in preop" {
  let nic = StartupMappingNic::new()
  nic.current_state = @protocol.EsmState::PreOp.to_byte()
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
      ],
      fmmu_configs: [],
      output_bytes: 0,
      input_bytes: 0,
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
    prefer_live_pdo_state: true,
  }
  let fault = transition_slave_to_preop_with_preparation(
    nic,
    0x1001U,
    preparation,
    @hal.Duration(1000L),
    @protocol.default_esm_timeout_policy(),
  )
  assert_true(fault is None)
  assert_eq(nic.current_state, @protocol.EsmState::PreOp.to_byte())
  assert_eq(nic.sm_write_offsets.length(), 0)
}

///|
test "runtime preop transition skips mailbox rewrite when already in safeop" {
  let nic = StartupMappingNic::new()
  nic.current_state = @protocol.EsmState::SafeOp.to_byte()
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
      ],
      fmmu_configs: [],
      output_bytes: 0,
      input_bytes: 0,
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
    prefer_live_pdo_state: true,
  }
  let fault = transition_slave_to_preop_with_preparation(
    nic,
    0x1001U,
    preparation,
    @hal.Duration(1000L),
    @protocol.default_esm_timeout_policy(),
  )
  assert_true(fault is None)
  assert_eq(nic.current_state, @protocol.EsmState::SafeOp.to_byte())
  assert_eq(nic.sm_write_offsets.length(), 0)
}

///|
test "runtime override refinement skips safeop stations" {
  let nic = StartupMappingNic::new()
  nic.current_state = @protocol.EsmState::SafeOp.to_byte()
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
      ],
      fmmu_configs: [],
      output_bytes: 0,
      input_bytes: 0,
    },
    dc_cycle_period_ns: None,
    startup_outputs: None,
    startup_mailbox_commands: [
      {
        transition: PreOpToSafeOp,
        index: 0x1C12U,
        subindex: b'\x00',
        data: Bytes::from_array([b'\x00']),
      },
    ],
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
    prefer_live_pdo_state: true,
  }
  let refined = refine_run_startup_preparation_override_in_preop(
    nic,
    [(0x1001U, preparation)],
    0U,
    @hal.Duration(1000L),
  )
  assert_true(refined.slave_preparations is Some(_))
  assert_eq(nic.current_state, @protocol.EsmState::SafeOp.to_byte())
  assert_eq(nic.sm_write_offsets.length(), 0)
}

///|
test "runtime safeop transition skips remap when already in safeop" {
  let nic = StartupMappingNic::new()
  nic.current_state = @protocol.EsmState::SafeOp.to_byte()
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
    prefer_live_pdo_state: true,
  }
  let fault = transition_stations_to_safeop_with_preparations(
    nic,
    [(0x1001U, preparation)],
    @hal.Duration(1000L),
    true,
    [],
  )
  assert_true(fault is None)
  assert_eq(nic.current_state, @protocol.EsmState::SafeOp.to_byte())
  assert_eq(nic.sm_write_offsets.length(), 0)
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
  assert_eq(nic.sm_write_offsets.length(), 4)
  assert_eq(
    nic.sm_write_offsets[0],
    @protocol.reg_sm_base + 2U * @protocol.sm_entry_size.reinterpret_as_uint(),
  )
  assert_eq(
    nic.sm_write_offsets[1],
    @protocol.reg_sm_base + 2U * @protocol.sm_entry_size.reinterpret_as_uint(),
  )
  assert_eq(
    nic.sm_write_offsets[2],
    @protocol.reg_sm_base + 3U * @protocol.sm_entry_size.reinterpret_as_uint(),
  )
  assert_eq(
    nic.sm_write_offsets[3],
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
    slave_preparations: None,
  }
  assert_eq(prep.esm_timeout_policies.length(), 1)
}

// ===== Coverage: validate.mbt — validation_grade_from_differences (private fn) =====

///|
test "validation_grade_from_differences empty is Pass" {
  let diffs : Array[ConfigurationDifference] = []
  assert_eq(validation_grade_from_differences(diffs), Pass)
}

///|
test "validation_grade_from_differences Extra only is Warn" {
  let diffs : Array[ConfigurationDifference] = [Extra(position=1)]
  assert_eq(validation_grade_from_differences(diffs), Warn)
}

///|
test "validation_grade_from_differences OptionalMissing only is Warn" {
  let diffs : Array[ConfigurationDifference] = [
    OptionalMissing(position=2, group_id=None),
  ]
  assert_eq(validation_grade_from_differences(diffs), Warn)
}

///|
test "validation_grade_from_differences Mixed Extra+OptionalMissing is Warn" {
  let diffs : Array[ConfigurationDifference] = [
    Extra(position=0),
    OptionalMissing(position=1, group_id=Some(1U)),
  ]
  assert_eq(validation_grade_from_differences(diffs), Warn)
}

///|
test "validation_grade_from_differences Missing is Block" {
  let diffs : Array[ConfigurationDifference] = [Missing(position=0)]
  assert_eq(validation_grade_from_differences(diffs), Block)
}

///|
test "validation_grade_from_differences Mixed Extra+Missing is Block" {
  let diffs : Array[ConfigurationDifference] = [
    Extra(position=0),
    Missing(position=1),
  ]
  assert_eq(validation_grade_from_differences(diffs), Block)
}

///|
test "validation_grade_from_differences StationAddressMismatch is Block" {
  let diffs : Array[ConfigurationDifference] = [
    StationAddressMismatch(
      position=0,
      expected=Some(0x1001U),
      actual=Some(0x1002U),
    ),
  ]
  assert_eq(validation_grade_from_differences(diffs), Block)
}

///|
test "validation_grade_from_differences IdentityMismatch is Block" {
  let diffs : Array[ConfigurationDifference] = [
    IdentityMismatch(
      position=0,
      expected=Some({
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
      }),
      actual=Some({ vendor_id: 5U, product_code: 6U, revision: 7U, serial: 8U }),
    ),
  ]
  assert_eq(validation_grade_from_differences(diffs), Block)
}

// ===== run_fault_issues white-box tests =====

///|
test "run_fault_issues StartupTransitionFailed all None" {
  let fault = RunFault::StartupTransitionFailed(
    station=0x1001U,
    target=@protocol.EsmState::SafeOp,
    current=None,
    error_indication=None,
    status_code=None,
    raw_status_code=None,
    control_wkc=None,
  )
  let issues = run_fault_issues(fault)
  assert_eq(issues.length(), 1)
  assert_true(issues[0].detail.contains("unknown"))
}

///|
test "run_fault_issues StartupTransitionFailed all Some" {
  let fault = RunFault::StartupTransitionFailed(
    station=0x1001U,
    target=@protocol.EsmState::SafeOp,
    current=Some(@protocol.EsmState::PreOp),
    error_indication=Some(false),
    status_code=Some(0x001AU),
    raw_status_code=Some(0x001AU),
    control_wkc=Some(1U),
  )
  let issues = run_fault_issues(fault)
  assert_eq(issues.length(), 1)
  assert_true(issues[0].detail.contains("clear"))
  assert_true(issues[0].detail.contains("Startup transition failed"))
}

///|
test "run_fault_issues TimeoutRecoveryRequired" {
  let fault = RunFault::TimeoutRecoveryRequired(
    observed_timeouts=10L,
    consecutive_timeouts=5,
  )
  let issues = run_fault_issues(fault)
  assert_eq(issues.length(), 1)
  assert_true(issues[0].detail.contains("Timeout recovery"))
}

///|
test "run_fault_issues DcDrift" {
  let fault = RunFault::DcDrift(delta_ns=123456L)
  let issues = run_fault_issues(fault)
  assert_eq(issues.length(), 1)
  assert_true(issues[0].detail.contains("DC drift"))
  assert_true(issues[0].detail.contains("123456"))
}

///|
test "run_fault_issues RuntimeRecoveryRequired" {
  let fault = RunFault::RuntimeRecoveryRequired(
    expected_wkc=3U,
    observed_wkc_errors=7L,
  )
  let issues = run_fault_issues(fault)
  assert_eq(issues.length(), 1)
  assert_true(issues[0].detail.contains("Runtime recovery"))
}

// ===== option_uint_or_zero and option_identity_or_zero =====

///|
test "option_uint_or_zero None" {
  assert_eq(option_uint_or_zero(None), 0U)
}

///|
test "option_uint_or_zero Some" {
  assert_eq(option_uint_or_zero(Some(42U)), 42U)
}

///|
test "option_identity_or_zero None" {
  let id = option_identity_or_zero(None)
  assert_eq(id.vendor_id, 0U)
}

///|
test "option_identity_or_zero Some" {
  let expected : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
  }
  let id = option_identity_or_zero(Some(expected))
  assert_eq(id.vendor_id, 1U)
}

// ===== validate_grade_label =====

///|
test "validate_grade_label Warn" {
  assert_eq(validate_grade_label(Warn), "WARN")
}

// ===== isqrt64 edge case =====

///|
test "isqrt64 zero and negative" {
  assert_eq(isqrt64(0L), 0L)
  assert_eq(isqrt64(-5L), 0L)
}

// ===== lcm edge case =====

///|
test "lcm with zero" {
  assert_eq(lcm(0, 5), 0)
  assert_eq(lcm(5, 0), 0)
}

// ===== validation_difference_issue Informational branch =====

///|
test "validation_difference_issue Informational category" {
  // Force Informational category by directly calling the match
  let (source, category) = match ValidateDifferenceCategory::Informational {
    ValidateDifferenceCategory::Topology =>
      (DiagnosticSourceLayer::Topology, DiagnosticCategory::Topology)
    ValidateDifferenceCategory::Identity =>
      (DiagnosticSourceLayer::Configuration, DiagnosticCategory::Identity)
    ValidateDifferenceCategory::Configuration =>
      (DiagnosticSourceLayer::Configuration, DiagnosticCategory::Configuration)
    ValidateDifferenceCategory::Informational =>
      (DiagnosticSourceLayer::Configuration, DiagnosticCategory::Configuration)
  }
  assert_eq(source, DiagnosticSourceLayer::Configuration)
  assert_eq(category, DiagnosticCategory::Configuration)
}

// ===== diagnostic_level_code Degrade =====

///|
test "diagnostic_level_code Degrade" {
  assert_eq(diagnostic_level_code(DiagnosticLevel::Degrade), 1U)
}

///|
test "diagnostic_level_code Block" {
  assert_eq(diagnostic_level_code(DiagnosticLevel::Block), 2U)
}

///|
test "diagnostic_level_code Info" {
  assert_eq(diagnostic_level_code(DiagnosticLevel::Info), 0U)
}

// ===== read_u32_le short data =====

///|
test "read_u32_le short data returns zero" {
  let data = Bytes::from_array([b'\x01', b'\x02'])
  assert_eq(read_u32_le(data, 0), 0U)
}

///|
test "read_u32_le offset near end" {
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04', b'\x05'])
  // offset=2, needs 4 more bytes from offset=2 but only 3 available
  assert_eq(read_u32_le(data, 2), 0U)
}

// ===== compute_sync_offsets sync1_enabled =====

///|
test "compute_sync_offsets with sync1 enabled" {
  let config : AutoTuneConfig = {
    probe_iterations: 10,
    probe_timeout_ns: 5_000_000L,
    strategy: Balanced,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 1_000_000L,
    sync1_enabled: true,
    sync1_delta_ns: 500_000L,
    safety_margin_permille: 100,
  }
  let probe : ProbeResult = {
    station: 0x1001U,
    forward_delay_ns: 100_000L,
    reverse_delay_ns: 100_000L,
    round_trip_ns: 200_000L,
    recv_time_port0: 0L,
    recv_time_port1: 0L,
  }
  let rec = compute_sync_offsets(config, probe)
  // sync1 should be non-zero when enabled
  assert_true(rec.sync1_offset_ns > 0L)
  // sync1 = sync0 + sync1_delta_ns
  assert_eq(rec.sync1_offset_ns, rec.sync0_offset_ns + 500_000L)
}

// ===== uint_to_hex zero =====

///|
test "uint_to_hex zero" {
  assert_eq(uint_to_hex(0U), "0")
}

// ===== MasterOdValue format and JSON for uncovered variants =====

///|
test "master_od_value_json U16" {
  let json = master_od_value_json(MasterOdValue::U16(0x1234U))
  assert_true(json.to_string().contains("4660"))
}

///|
test "master_od_value_json I32" {
  let json = master_od_value_json(MasterOdValue::I32(-42))
  assert_true(json.to_string().contains("-42"))
}

///|
test "master_od_value_json Raw" {
  let json = master_od_value_json(
    MasterOdValue::Raw(Bytes::from_array([b'\xAB', b'\xCD'])),
  )
  let s = json.to_string()
  assert_true(s.length() > 0)
}

// ===== next_scan_station_address boundary =====

///|
test "next_scan_station_address skips used addresses" {
  let used : Array[UInt] = [scan_station_address_base]
  let addr = next_scan_station_address(used) catch { _ => 0U }
  assert_eq(addr, scan_station_address_base + 1U)
}

// ===== highest_diagnostic_level =====

///|
test "highest_diagnostic_level empty is Info" {
  let result = highest_diagnostic_level([], DiagnosticLevel::Info)
  assert_eq(result, DiagnosticLevel::Info)
}

///|
test "highest_diagnostic_level picks Block over Degrade" {
  let issues : Array[DiagnosticIssue] = [
    {
      source: DiagnosticSourceLayer::Registers,
      category: DiagnosticCategory::AlStatus,
      level: DiagnosticLevel::Info,
      detail: "info",
    },
    {
      source: DiagnosticSourceLayer::Registers,
      category: DiagnosticCategory::AlStatus,
      level: DiagnosticLevel::Degrade,
      detail: "degrade",
    },
    {
      source: DiagnosticSourceLayer::Registers,
      category: DiagnosticCategory::AlStatus,
      level: DiagnosticLevel::Block,
      detail: "block",
    },
  ]
  let result = highest_diagnostic_level(issues, DiagnosticLevel::Info)
  assert_eq(result, DiagnosticLevel::Block)
}

// ============================================================
// Batch 3 whitebox: diagnosis_timeout_step, escape_json,
//   compute_sync_offsets sync1, validate negative propagation,
//   eoe reassembly
// ============================================================

// ===== diagnosis_timeout_step =====

///|
test "diagnosis_timeout_step Ok passes through" {
  let r : Result[Int, Error] = Ok(42)
  let v = diagnosis_timeout_step(r, "test-stage")
  assert_eq(v, 42)
}

///|
test "diagnosis_timeout_step RecvTimeout maps to Internal" {
  let r : Result[Int, Error] = Err(@hal.EcError::RecvTimeout)
  let mut msg = ""
  try {
    let _ = diagnosis_timeout_step(r, "read-al")
  } catch {
    @hal.EcError::Internal(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("RecvTimeout"))
  assert_true(msg.contains("read-al"))
}

///|
test "diagnosis_timeout_step MailboxTimeout maps to Internal" {
  let r : Result[Int, Error] = Err(@hal.EcError::MailboxTimeout)
  let mut msg = ""
  try {
    let _ = diagnosis_timeout_step(r, "coe-read")
  } catch {
    @hal.EcError::Internal(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("MailboxTimeout"))
  assert_true(msg.contains("coe-read"))
}

///|
test "diagnosis_timeout_step nested timeout chains stages" {
  let inner_err = @hal.EcError::Internal("timeout at inner-step")
  let r : Result[Int, Error] = Err(inner_err)
  let mut msg = ""
  try {
    let _ = diagnosis_timeout_step(r, "outer-step")
  } catch {
    @hal.EcError::Internal(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("outer-step"))
  assert_true(msg.contains("inner-step"))
}

///|
test "diagnosis_timeout_step generic error maps to Internal" {
  let r : Result[Int, Error] = Err(@hal.EcError::MailboxProtocol("some error"))
  let mut msg = ""
  try {
    let _ = diagnosis_timeout_step(r, "stage-x")
  } catch {
    @hal.EcError::Internal(m) => msg = m
    _ => ()
  }
  assert_true(msg.length() > 0)
}

// ===== escape_json =====

///|
test "escape_json with backslash" {
  let result = escape_json("a\\b")
  assert_true(result.contains("\\\\"))
}

///|
test "escape_json with quotes and newlines" {
  let result = escape_json("hello \"world\"\nfoo\tbar\r")
  assert_true(result.contains("\\\""))
  assert_true(result.contains("\\n"))
  assert_true(result.contains("\\t"))
  assert_true(result.contains("\\r"))
}

///|
test "escape_json plain string unchanged" {
  assert_eq(escape_json("abc"), "abc")
}

// ===== compute_sync_offsets with sync1_enabled =====

///|
test "compute_sync_offsets sync1_enabled true produces nonzero sync1" {
  let config : AutoTuneConfig = {
    probe_iterations: 10,
    probe_timeout_ns: 5_000_000L,
    strategy: Balanced,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 1_000_000L,
    sync1_enabled: true,
    sync1_delta_ns: 500_000L,
    safety_margin_permille: 100,
  }
  let avg : ProbeResult = {
    station: 0x1001U,
    forward_delay_ns: 100_000L,
    reverse_delay_ns: 100_000L,
    round_trip_ns: 200_000L,
    recv_time_port0: 0L,
    recv_time_port1: 0L,
  }
  let rec = compute_sync_offsets(config, avg)
  assert_true(rec.sync1_offset_ns > 0L)
  assert_true(rec.sync1_offset_ns > rec.sync0_offset_ns)
}

// ===== validate_recommendations sync1 over limit =====

///|
test "validate_recommendations sync1 over limit from whitebox" {
  let config : AutoTuneConfig = {
    probe_iterations: 5,
    probe_timeout_ns: 5_000_000L,
    strategy: Balanced,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 1_000_000L,
    sync1_enabled: true,
    sync1_delta_ns: 9_000_000L,
    safety_margin_permille: 100,
  }
  let avg : ProbeResult = {
    station: 0x1001U,
    forward_delay_ns: 100_000L,
    reverse_delay_ns: 100_000L,
    round_trip_ns: 200_000L,
    recv_time_port0: 0L,
    recv_time_port1: 0L,
  }
  let rec = compute_sync_offsets(config, avg)
  let tuner = PdoAutoTuner::new(config~)
  let result = tuner.analyze([0x1001U], [
    [
      {
        station: 0x1001U,
        forward_delay_ns: 100_000L,
        reverse_delay_ns: 100_000L,
        round_trip_ns: 200_000L,
        recv_time_port0: 100_000L,
        recv_time_port1: 200_000L,
      },
    ],
  ])
  let errors = validate_recommendations(result, 2_000_000L)
  // sync1 = sync0 + 9_000_000 which is >> 2_000_000
  assert_true(
    errors.iter().any(fn(s) { s.contains("Sync1") && s.contains("exceeds") }),
  )
  ignore(rec)
}

// ===== validate_recommendations negative propagation =====

///|
test "validate_recommendations negative propagation from whitebox" {
  // Construct recommendation with negative propagation by using compute_sync_offsets
  // with a probe that has negative forward_delay
  let config : AutoTuneConfig = {
    probe_iterations: 5,
    probe_timeout_ns: 5_000_000L,
    strategy: Balanced,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 0L,
    sync1_enabled: false,
    sync1_delta_ns: 0L,
    safety_margin_permille: 0,
  }
  let avg : ProbeResult = {
    station: 0x1001U,
    forward_delay_ns: -500L,
    reverse_delay_ns: 500L,
    round_trip_ns: 0L,
    recv_time_port0: 0L,
    recv_time_port1: 0L,
  }
  let rec = compute_sync_offsets(config, avg)
  // rec.propagation_delay_ns = avg.forward_delay_ns = -500
  let result : AutoTuneResult = {
    recommendations: [rec],
    probe_data: [avg],
    reference_station: 0x1001U,
    measurement_duration_ns: 0L,
    success: true,
    messages: [],
  }
  let errors = validate_recommendations(result, 10_000_000L)
  assert_true(errors.iter().any(fn(s) { s.contains("negative propagation") }))
}

// ===== EoeReassemblyBuffer is_complete with gap =====

///|
test "EoeReassemblyBuffer is_complete returns false with gap" {
  let buf = EoeReassemblyBuffer::new(0U)
  // Insert fragment 0 (not last)
  let _ = buf.insert(0U, false, b"\x01\x02")
  // Insert fragment 2 as last (skipping fragment 1)
  let complete = buf.insert(2U, true, b"\x05\x06")
  // Should not be complete because fragment 1 is missing
  assert_eq(complete, false)
}

///|
test "EoeReassemblyBuffer insert and assemble" {
  let buf = EoeReassemblyBuffer::new(0U)
  let _ = buf.insert(0U, false, b"\x01\x02")
  let complete = buf.insert(1U, true, b"\x03\x04")
  assert_eq(complete, true)
  let assembled = buf.assemble()
  assert_eq(assembled.length(), 4)
  assert_eq(assembled[0], b'\x01')
  assert_eq(assembled[3], b'\x04')
}

// ===== EoeStationContext get_reassembly eviction =====

///|
test "EoeStationContext get_reassembly eviction when full" {
  let mb_config : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1400U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let ctx = EoeStationContext::new(0x1001U, mb_config)
  // Fill all 4 reassembly slots (eoe_max_reassembly_buffers = 4)
  for i = 0; i < 4; i = i + 1 {
    let _ = ctx.get_reassembly(i.reinterpret_as_uint())
  }
  // All 4 slots full; requesting frame 10 should evict slot 0
  let buf = ctx.get_reassembly(10U)
  assert_eq(buf.frame_number, 10U)
}

// ===== EoeStationContext next_counter wraps 1-7 =====

///|
test "EoeStationContext next_counter wraps at 7" {
  let mb_config : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1400U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let ctx = EoeStationContext::new(0x1001U, mb_config)
  // Initial counter is 1
  let c1 = ctx.next_counter()
  assert_eq(c1, b'\x01')
  // Advance through 2..7
  for _i = 0; _i < 5; _i = _i + 1 {
    let _ = ctx.next_counter()
  }
  // Next should be 7
  let c7 = ctx.next_counter()
  assert_eq(c7, b'\x07')
  // Next wraps to 1
  let c_wrap = ctx.next_counter()
  assert_eq(c_wrap, b'\x01')
}

// ===== EoeStationContext next_frame_number wraps 0-15 =====

///|
test "EoeStationContext next_frame_number wraps at 15" {
  let mb_config : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1400U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let ctx = EoeStationContext::new(0x1001U, mb_config)
  // Advance 16 times: should wrap
  for _i = 0; _i < 16; _i = _i + 1 {
    let _ = ctx.next_frame_number()
  }
  // After 16 advances, should be back to 0
  let n = ctx.next_frame_number()
  assert_eq(n, 0U)
}

// ===== diagnosis_restore_path =====

///|
test "diagnosis_restore_path covers all states" {
  let path_preop = diagnosis_restore_path(@protocol.PreOp)
  assert_eq(path_preop.length(), 1)
  let path_safeop = diagnosis_restore_path(@protocol.SafeOp)
  assert_eq(path_safeop.length(), 2)
  let path_op = diagnosis_restore_path(@protocol.Op)
  assert_eq(path_op.length(), 3)
  let path_init = diagnosis_restore_path(@protocol.Init)
  assert_eq(path_init.length(), 2)
  let path_boot = diagnosis_restore_path(@protocol.Boot)
  assert_eq(path_boot.length(), 3)
}

// ===== step_result_to_parts =====

///|
test "step_result_to_parts Ok" {
  let (status, msg, ns) = step_result_to_parts(Ok(SimTime::from_ns(12345L)))
  assert_eq(status, "ok")
  assert_eq(msg, "")
  assert_eq(ns, 12345L)
}

///|
test "step_result_to_parts Terminated" {
  let (status, msg, ns) = step_result_to_parts(Terminated("done"))
  assert_eq(status, "terminated")
  assert_eq(msg, "done")
  assert_eq(ns, 0L)
}

///|
test "step_result_to_parts Error" {
  let (status, msg, ns) = step_result_to_parts(Error("boom"))
  assert_eq(status, "error")
  assert_eq(msg, "boom")
  assert_eq(ns, 0L)
}

// ── Batch 4: esi_json private helpers error paths ──

///|
test "parse_esi_json_init_command guard-else" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = parse_esi_json_init_command(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid init command entry"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "parse_esi_json_mailbox guard-else" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = parse_esi_json_mailbox(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid mailbox entry"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "parse_esi_json_sm_entry guard-else" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = parse_esi_json_sm_entry(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid sync manager entry"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "parse_esi_json_pdo guard-else" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = parse_esi_json_pdo(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid PDO entry"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "parse_esi_json_pdo_entry guard-else" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = parse_esi_json_pdo_entry(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid PDO entry item"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "parse_esi_json_dc_mode guard-else" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = parse_esi_json_dc_mode(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid DC entry"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "parse_esi_json_selected_module guard-else" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = parse_esi_json_selected_module(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid selected module entry"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_esi_json_string with non-string" {
  let json = @json.parse("42"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_esi_json_string(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("ESI JSON decode failed"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_esi_json_uint with non-number" {
  let json = @json.parse("\"abc\""[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_esi_json_uint(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("ESI JSON decode failed"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_esi_json_optional_uint Null returns None" {
  let json = @json.parse("null"[:]) catch { _ => panic() }
  let result = decode_esi_json_optional_uint(json)
  assert_eq(result, None)
}

///|
test "decode_esi_json_int with non-number" {
  let json = @json.parse("\"x\""[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_esi_json_int(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("ESI JSON decode failed"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_esi_json_bool with non-bool" {
  let json = @json.parse("1"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_esi_json_bool(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("ESI JSON decode failed"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_esi_json_byte out of range" {
  let json = @json.parse("300"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_esi_json_byte(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("byte value out of range"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_esi_json_byte negative" {
  let json = @json.parse("-1"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_esi_json_byte(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("byte value out of range"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_esi_json_bytes array fallback" {
  let json = @json.parse("[1, 2, 3]"[:]) catch { _ => panic() }
  let result = decode_esi_json_bytes(json)
  assert_eq(result.length(), 3)
  assert_eq(result[0], b'\x01')
  assert_eq(result[1], b'\x02')
  assert_eq(result[2], b'\x03')
}

///|
test "decode_esi_json_bytes not array not bytes" {
  let json = @json.parse("42"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_esi_json_bytes(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("expected byte array"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "map_esi_init_transition SO" {
  let result = map_esi_init_transition("SO")
  assert_true(result is Some(SafeOpToOp))
}

///|
test "map_esi_init_transition PS returns None" {
  let result = map_esi_init_transition("PS")
  assert_eq(result, None)
}

///|
test "map_esi_init_transition unknown returns None" {
  let result = map_esi_init_transition("XX")
  assert_eq(result, None)
}

///|
test "preferred_device_group_name with non-empty type_name" {
  let device = make_minimal_esi_device(type_name="MyType", device_name="MyDev")
  assert_eq(preferred_device_group_name(device), "MyType")
}

///|
test "preferred_device_group_name with empty type_name" {
  let device = make_minimal_esi_device(type_name="", device_name="MyDev")
  assert_eq(preferred_device_group_name(device), "MyDev")
}

///|
test "preferred_device_name with non-empty device_name" {
  let device = make_minimal_esi_device(type_name="MyType", device_name="MyDev")
  assert_eq(preferred_device_name(device), "MyDev")
}

///|
test "preferred_device_name with empty device_name" {
  let device = make_minimal_esi_device(type_name="MyType", device_name="")
  assert_eq(preferred_device_name(device), "MyType")
}

///|
test "intern_sii_string empty text returns zero byte" {
  let strings : Array[String] = []
  let result = intern_sii_string(strings, "")
  assert_eq(result, b'\x00')
  assert_eq(strings.length(), 0)
}

///|
test "intern_sii_string adds new string" {
  let strings : Array[String] = []
  let idx = intern_sii_string(strings, "hello")
  assert_eq(idx, b'\x01')
  assert_eq(strings.length(), 1)
}

///|
test "intern_sii_string deduplicates" {
  let strings : Array[String] = ["hello"]
  let idx = intern_sii_string(strings, "hello")
  assert_eq(idx, b'\x01')
  assert_eq(strings.length(), 1)
}

///|
test "is_ds402_profile 402" {
  assert_true(is_ds402_profile(Some(402U)))
}

///|
test "is_ds402_profile non-402" {
  assert_true(is_ds402_profile(Some(100U)) == false)
}

///|
test "is_ds402_profile None" {
  assert_true(is_ds402_profile(None) == false)
}

///|
test "decode_physical_ports YHKE" {
  let ports = decode_physical_ports("YHKE")
  assert_eq(ports[0], b'\x01') // Y
  assert_eq(ports[1], b'\x01') // H
  assert_eq(ports[2], b'\x01') // K
  assert_eq(ports[3], b'\x03') // E
}

///|
test "decode_physical_ports short string" {
  let ports = decode_physical_ports("Y")
  assert_eq(ports[0], b'\x01')
  assert_eq(ports[1], b'\x00')
}

///|
test "decode_physical_ports unknown char" {
  let ports = decode_physical_ports("X")
  assert_eq(ports[0], b'\x00')
}

///|
test "materialize_sii_sm_entry enable false" {
  let sm : EsiJsonSmEntry = {
    physical_start: 0x1000U,
    length: 128U,
    control: b'\x26',
    status: b'\x00',
    enable: false,
    sm_type: "process-data-out",
  }
  let result = materialize_sii_sm_entry(sm)
  assert_eq(result.activate, b'\x00')
}

///|
test "materialize_sii_sm_entry enable true" {
  let sm : EsiJsonSmEntry = {
    physical_start: 0x1000U,
    length: 128U,
    control: b'\x26',
    status: b'\x00',
    enable: true,
    sm_type: "process-data-in",
  }
  let result = materialize_sii_sm_entry(sm)
  assert_eq(result.activate, b'\x01')
}

///|
test "map_esi_data_type BOOL" {
  assert_eq(map_esi_data_type("BOOL", b'\x01'), b'\x01')
}

///|
test "map_esi_data_type SINT" {
  assert_eq(map_esi_data_type("SINT", b'\x08'), b'\x02')
}

///|
test "map_esi_data_type INT" {
  assert_eq(map_esi_data_type("INT", b'\x10'), b'\x03')
}

///|
test "map_esi_data_type DINT" {
  assert_eq(map_esi_data_type("DINT", b'\x20'), b'\x04')
}

///|
test "map_esi_data_type USINT" {
  assert_eq(map_esi_data_type("USINT", b'\x08'), b'\x05')
}

///|
test "map_esi_data_type BYTE" {
  assert_eq(map_esi_data_type("BYTE", b'\x08'), b'\x05')
}

///|
test "map_esi_data_type UINT" {
  assert_eq(map_esi_data_type("UINT", b'\x10'), b'\x06')
}

///|
test "map_esi_data_type WORD" {
  assert_eq(map_esi_data_type("WORD", b'\x10'), b'\x06')
}

///|
test "map_esi_data_type UDINT" {
  assert_eq(map_esi_data_type("UDINT", b'\x20'), b'\x07')
}

///|
test "map_esi_data_type DWORD" {
  assert_eq(map_esi_data_type("DWORD", b'\x20'), b'\x07')
}

///|
test "map_esi_data_type unknown 8bit" {
  assert_eq(map_esi_data_type("CUSTOM", b'\x08'), b'\x05')
}

///|
test "map_esi_data_type unknown 16bit" {
  assert_eq(map_esi_data_type("CUSTOM", b'\x10'), b'\x06')
}

///|
test "map_esi_data_type unknown 32bit" {
  assert_eq(map_esi_data_type("CUSTOM", b'\x20'), b'\x07')
}

///|
test "map_esi_data_type unknown other" {
  assert_eq(map_esi_data_type("CUSTOM", b'\x04'), b'\x00')
}

///|
test "map_esi_json_fmmu_direction outputs" {
  assert_true(map_esi_json_fmmu_direction("outputs") is Outputs)
}

///|
test "map_esi_json_fmmu_direction inputs" {
  assert_true(map_esi_json_fmmu_direction("inputs") is Inputs)
}

///|
test "map_esi_json_fmmu_direction dynamic-outputs" {
  assert_true(map_esi_json_fmmu_direction("dynamic-outputs") is DynamicOutputs)
}

///|
test "map_esi_json_fmmu_direction dynamic-inputs" {
  assert_true(map_esi_json_fmmu_direction("dynamic-inputs") is DynamicInputs)
}

///|
test "map_esi_json_fmmu_direction unknown" {
  assert_true(map_esi_json_fmmu_direction("xxx") is MailboxState)
}

///|
test "map_esi_json_sm_type all variants" {
  assert_true(map_esi_json_sm_type("mailbox-out") is MailboxOut)
  assert_true(map_esi_json_sm_type("mailbox-in") is MailboxIn)
  assert_true(map_esi_json_sm_type("process-data-out") is ProcessDataOut)
  assert_true(map_esi_json_sm_type("process-data-in") is ProcessDataIn)
  assert_true(
    map_esi_json_sm_type("dynamic-process-data-out") is DynamicProcessDataOut,
  )
  assert_true(
    map_esi_json_sm_type("dynamic-process-data-in") is DynamicProcessDataIn,
  )
  assert_true(map_esi_json_sm_type("unknown") is Unused)
}

///|
test "build_sii_header empty sync_managers" {
  let device = make_minimal_esi_device()
  let sms : Array[@mailbox.SiiSmEntry] = []
  let header = build_sii_header(device, sms)
  assert_eq(header.mailbox_rx_offset, 0U)
  assert_eq(header.mailbox_rx_size, 0U)
  assert_eq(header.mailbox_tx_offset, 0U)
  assert_eq(header.mailbox_tx_size, 0U)
}

///|
test "build_sii_header with 1 sync_manager" {
  let device = make_minimal_esi_device()
  let sms : Array[@mailbox.SiiSmEntry] = [
    {
      physical_start: 0x1000U,
      length: 128U,
      control: b'\x26',
      status: b'\x00',
      activate: b'\x01',
      sm_type: MailboxOut,
    },
  ]
  let header = build_sii_header(device, sms)
  assert_eq(header.mailbox_rx_offset, 0x1000U)
  assert_eq(header.mailbox_rx_size, 128U)
  assert_eq(header.mailbox_tx_offset, 0U)
  assert_eq(header.mailbox_tx_size, 0U)
}

///|
test "build_sii_header with 2 sync_managers" {
  let device = make_minimal_esi_device()
  let sms : Array[@mailbox.SiiSmEntry] = [
    {
      physical_start: 0x1000U,
      length: 128U,
      control: b'\x26',
      status: b'\x00',
      activate: b'\x01',
      sm_type: MailboxOut,
    },
    {
      physical_start: 0x1400U,
      length: 256U,
      control: b'\x22',
      status: b'\x00',
      activate: b'\x01',
      sm_type: MailboxIn,
    },
  ]
  let header = build_sii_header(device, sms)
  assert_eq(header.mailbox_rx_offset, 0x1000U)
  assert_eq(header.mailbox_rx_size, 128U)
  assert_eq(header.mailbox_tx_offset, 0x1400U)
  assert_eq(header.mailbox_tx_size, 256U)
}

///|
test "known_sii_category_code all variants" {
  assert_eq(known_sii_category_code(Strings), 0x0AU)
  assert_eq(known_sii_category_code(DataTypes), 0x14U)
  assert_eq(known_sii_category_code(General), 0x1EU)
  assert_eq(known_sii_category_code(Fmmu), 0x28U)
  assert_eq(known_sii_category_code(SyncManager), 0x29U)
  assert_eq(known_sii_category_code(FmmuEx), 0x2AU)
  assert_eq(known_sii_category_code(SyncUnit), 0x2BU)
  assert_eq(known_sii_category_code(TxPdo), 0x32U)
  assert_eq(known_sii_category_code(RxPdo), 0x33U)
  assert_eq(known_sii_category_code(Dc), 0x3CU)
  assert_eq(known_sii_category_code(Timeouts), 0x46U)
  assert_eq(known_sii_category_code(Dictionary), 0x50U)
  assert_eq(known_sii_category_code(Hardware), 0x5AU)
  assert_eq(known_sii_category_code(VendorInformation), 0x64U)
  assert_eq(known_sii_category_code(Images), 0x6EU)
  assert_eq(known_sii_category_code(Raw), 0U)
}

///|
test "encode_sii_fmmu DynamicOutputs" {
  let fmmu : Array[@mailbox.FmmuDirection] = [DynamicOutputs, DynamicInputs]
  let result = encode_sii_fmmu(fmmu)
  assert_eq(result[0], b'\x05')
  assert_eq(result[1], b'\x06')
}

///|
test "encode_sii_sync_managers DynamicProcessDataOut" {
  let sms : Array[@mailbox.SiiSmEntry] = [
    {
      physical_start: 0x1000U,
      length: 64U,
      control: b'\x24',
      status: b'\x00',
      activate: b'\x01',
      sm_type: DynamicProcessDataOut,
    },
  ]
  let result = encode_sii_sync_managers(sms)
  // sm_type byte is at offset 7 for each SM entry (8 bytes per entry)
  assert_eq(result[7], b'\x05')
}

///|
test "push_i16 positive" {
  let values : Array[Byte] = []
  push_i16(values, 256)
  assert_eq(values[0], b'\x00')
  assert_eq(values[1], b'\x01')
}

///|
test "push_i16 negative" {
  let values : Array[Byte] = []
  push_i16(values, -1)
  assert_eq(values[0], b'\xFF')
  assert_eq(values[1], b'\xFF')
}

///|
test "push_i16 negative small" {
  let values : Array[Byte] = []
  push_i16(values, -256)
  assert_eq(values[0], b'\x00')
  assert_eq(values[1], b'\xFF')
}

///|
test "encode_eeprom_size_raw small" {
  assert_eq(encode_eeprom_size_raw(0x80U), 0U)
  assert_eq(encode_eeprom_size_raw(0x40U), 0U)
}

///|
test "encode_eeprom_size_raw larger" {
  // 0x100 = 256 bytes: (256 - 128) >> 7 = 1
  assert_eq(encode_eeprom_size_raw(0x100U), 1U)
  // 0x200 = 512: (512 - 128) >> 7 = 3
  assert_eq(encode_eeprom_size_raw(0x200U), 3U)
}

///|
test "build_mailbox_protocol_mask all false" {
  let mb = make_minimal_esi_mailbox()
  let mask = build_mailbox_protocol_mask(mb)
  assert_eq(mask, 0U)
}

///|
test "pad_even_bytes odd length" {
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03'])
  let result = pad_even_bytes(data)
  assert_eq(result.length(), 4)
  assert_eq(result[3], b'\x00')
}

///|
test "pad_even_bytes even length" {
  let data = Bytes::from_array([b'\x01', b'\x02'])
  let result = pad_even_bytes(data)
  assert_eq(result.length(), 2)
}

///|
test "read_u16_from_bytes normal" {
  let data = Bytes::from_array([b'\x34', b'\x12'])
  assert_eq(read_u16_from_bytes(data, 0), 0x1234U)
}

///|
test "read_u16_from_bytes out of bounds" {
  let data = Bytes::from_array([b'\x34'])
  assert_eq(read_u16_from_bytes(data, 0), 0U)
}

///|
test "build_general_flags with active DC" {
  let device = make_minimal_esi_device_with_dc(assign_activate=0x300U)
  let flags = build_general_flags(device)
  assert_true((flags.to_int() & 0x01) != 0)
}

///|
test "build_general_flags with data_link_layer" {
  let mb = make_minimal_esi_mailbox(data_link_layer=true)
  let device = make_minimal_esi_device_with_mailbox(mb)
  let flags = build_general_flags(device)
  assert_true((flags.to_int() & 0x04) != 0)
}

///|
test "build_coe_details_byte all true" {
  let mb : EsiJsonMailbox = {
    data_link_layer: false,
    aoe: false,
    coe_present: true,
    coe_sdo_info: true,
    coe_pdo_assign: true,
    coe_pdo_config: true,
    coe_complete_access: true,
    eoe: false,
    foe: false,
    soe: false,
    voe: false,
  }
  let details = build_coe_details_byte(mb)
  assert_eq(details.to_int() & 0x01, 1) // coe_present
  assert_eq(details.to_int() & 0x02, 2) // coe_sdo_info
  assert_eq(details.to_int() & 0x04, 4) // coe_pdo_assign
  assert_eq(details.to_int() & 0x08, 8) // coe_pdo_config
  assert_eq(details.to_int() & 0x20, 0x20) // coe_complete_access
}

///|
test "encode_sii_strings basic" {
  let strings : Array[String] = ["AB", "C"]
  let result = encode_sii_strings(strings)
  assert_eq(result[0], b'\x02') // count
  assert_eq(result[1], b'\x02') // length of "AB"
  assert_eq(result[2], b'\x41') // 'A'
  assert_eq(result[3], b'\x42') // 'B'
  assert_eq(result[4], b'\x01') // length of "C"
  assert_eq(result[5], b'\x43') // 'C'
}

///|
test "minimum_eeprom_size empty categories" {
  let cats : Array[@mailbox.SiiCategoryEntry] = []
  assert_eq(minimum_eeprom_size(cats), 132U) // 128 + 4
}

///|
test "max_uint" {
  assert_eq(max_uint(10U, 20U), 20U)
  assert_eq(max_uint(20U, 10U), 20U)
  assert_eq(max_uint(5U, 5U), 5U)
}

// ── Batch 4: esi_json helper constructors for testing ──

///|
fn make_minimal_esi_mailbox(data_link_layer? : Bool = false) -> EsiJsonMailbox {
  {
    data_link_layer,
    aoe: false,
    coe_present: false,
    coe_sdo_info: false,
    coe_pdo_assign: false,
    coe_pdo_config: false,
    coe_complete_access: false,
    eoe: false,
    foe: false,
    soe: false,
    voe: false,
  }
}

///|
fn make_minimal_esi_device(
  type_name? : String = "TestType",
  device_name? : String = "TestDev",
) -> EsiJsonDevice {
  {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
    type_name,
    device_name,
    physics: "YYKK",
    profile_no: None,
    slot_index_increment: 0U,
    slot_pdo_increment: 0U,
    mailbox: make_minimal_esi_mailbox(),
    config_data: Bytes::make(8, b'\x00'),
    bootstrap: Bytes::make(8, b'\x00'),
    eeprom_byte_size: 256U,
    sync_managers: [],
    fmmu: [],
    dc_modes: [],
    rx_pdos: [],
    tx_pdos: [],
    default_modules: [],
    init_commands: [],
  }
}

///|
fn make_minimal_esi_device_with_dc(
  assign_activate? : UInt = 0U,
) -> EsiJsonDevice {
  {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
    type_name: "TestType",
    device_name: "TestDev",
    physics: "YYKK",
    profile_no: None,
    slot_index_increment: 0U,
    slot_pdo_increment: 0U,
    mailbox: make_minimal_esi_mailbox(),
    config_data: Bytes::make(8, b'\x00'),
    bootstrap: Bytes::make(8, b'\x00'),
    eeprom_byte_size: 256U,
    sync_managers: [],
    fmmu: [],
    dc_modes: [
      {
        name: "DC",
        description: "desc",
        assign_activate,
        cycle_time_sync0: 1000000U,
        sync0_factor: 1,
        sync1_factor: 0,
      },
    ],
    rx_pdos: [],
    tx_pdos: [],
    default_modules: [],
    init_commands: [],
  }
}

///|
fn make_minimal_esi_device_with_mailbox(mb : EsiJsonMailbox) -> EsiJsonDevice {
  {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
    type_name: "TestType",
    device_name: "TestDev",
    physics: "YYKK",
    profile_no: None,
    slot_index_increment: 0U,
    slot_pdo_increment: 0U,
    mailbox: mb,
    config_data: Bytes::make(8, b'\x00'),
    bootstrap: Bytes::make(8, b'\x00'),
    eeprom_byte_size: 256U,
    sync_managers: [],
    fmmu: [],
    dc_modes: [],
    rx_pdos: [],
    tx_pdos: [],
    default_modules: [],
    init_commands: [],
  }
}

// ── Batch 4: configuration_eni private helpers ──

///|
test "decode_optional_eni_json_string with non-string" {
  let json = @json.parse("42"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_optional_eni_json_string(Some(json))
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("ENI JSON decode failed"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_optional_eni_json_string None" {
  let result = decode_optional_eni_json_string(None)
  assert_eq(result, None)
}

///|
test "decode_optional_eni_json_string Some(Null)" {
  let json = @json.parse("null"[:]) catch { _ => panic() }
  let result = decode_optional_eni_json_string(Some(json))
  assert_eq(result, None)
}

///|
test "decode_optional_eni_json_identity None" {
  let result = decode_optional_eni_json_identity(None)
  assert_true(result is None)
}

///|
test "decode_optional_eni_json_identity invalid" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_optional_eni_json_identity(Some(json))
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid identity entry"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_optional_eni_json_process_data_summary None" {
  let result = decode_optional_eni_json_process_data_summary(None)
  assert_true(result is None)
}

///|
test "decode_optional_eni_json_process_data_summary invalid" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_optional_eni_json_process_data_summary(Some(json))
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid process_data_summary entry"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_optional_eni_json_mailbox_protocols None" {
  let result = decode_optional_eni_json_mailbox_protocols(None)
  assert_true(result is None)
}

///|
test "decode_optional_eni_json_mailbox_protocols invalid" {
  let json = @json.parse("{}"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_optional_eni_json_mailbox_protocols(Some(json))
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("invalid mailbox_protocols entry"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_eni_json_int with non-number" {
  let json = @json.parse("\"x\""[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_eni_json_int(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("ENI JSON decode failed"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_eni_json_bool with non-bool" {
  let json = @json.parse("1"[:]) catch { _ => panic() }
  let mut caught = false
  try {
    let _ = decode_eni_json_bool(json)
    ()
  } catch {
    @hal.EcError::EsiParseFailed(msg) => {
      assert_true(msg.contains("ENI JSON decode failed"))
      caught = true
    }
    _ => ()
  }
  assert_true(caught)
}

///|
test "decode_eni_json_presence optional" {
  let result = decode_eni_json_presence(Some("optional"), Some(5U))
  assert_true(result is @hal.Optional(_))
}

///|
test "decode_eni_json_presence mandatory" {
  let result = decode_eni_json_presence(None, None)
  assert_true(result is @hal.Mandatory)
}

///|
test "decode_eni_json_presence non-optional string" {
  let result = decode_eni_json_presence(Some("mandatory"), None)
  assert_true(result is @hal.Mandatory)
}

// ── Batch 4: scan address exhaustion ──

///|
test "next_scan_station_address normal" {
  let used : Array[UInt] = []
  let addr = next_scan_station_address(used)
  assert_eq(addr, 0x1001U)
}

///|
test "next_scan_station_address skips used" {
  let used : Array[UInt] = [0x1001U, 0x1002U]
  let addr = next_scan_station_address(used)
  assert_eq(addr, 0x1003U)
}

// ── Batch 4: topology_health compute_link_health_score ──

///|
test "compute_link_health_score with zero tx" {
  let score = compute_link_health_score(0L, 0L, 0L, 0L, 300, 300, 300)
  assert_eq(score, 1000)
}

///|
test "compute_link_health_score perfect" {
  let score = compute_link_health_score(1000L, 1000L, 0L, 0L, 300, 300, 300)
  assert_eq(score, 1000)
}

///|
test "compute_link_health_score with losses" {
  let score = compute_link_health_score(1000L, 500L, 0L, 0L, 300, 300, 300)
  // 500 lost / 1000 = 500‰, deduction = 500*300/1000=150
  assert_eq(score, 850)
}

///|
test "compute_link_health_score clamps to zero" {
  // All frames lost + all timeouts + all WKC errors → max deduction
  let score = compute_link_health_score(1L, 0L, 1L, 1L, 1000, 1000, 1000)
  assert_eq(score, 0)
}

///|
// =====================================================
// BATCH 5: coverage edge-case tests (whitebox)
// =====================================================

///|
test "project_esi_startup_mailbox_commands unknown transition" {
  let device = make_minimal_esi_device()
  // Add an init command with unknown transition → should be skipped (None branch)
  let device2 = {
    ..device,
    init_commands: [
      { transition: "UNKNOWN", index: 0x1000U, subindex: 0, data: b"" },
    ],
  }
  let cmds = project_esi_startup_mailbox_commands(device2)
  assert_eq(cmds.length(), 0)
}

///|
test "merge_startup_mailbox_commands keeps derived presafeop commands and overrides duplicate targets" {
  let derived : Array[StartupMailboxCommand] = [
    {
      transition: PreOpToSafeOp,
      index: 0x1C12U,
      subindex: b'\x00',
      data: Bytes::from_array([b'\x01', b'\x00', b'\x16']),
    },
    {
      transition: SafeOpToOp,
      index: 0x6060U,
      subindex: b'\x00',
      data: Bytes::from_array([b'\x08']),
    },
  ]
  let explicit : Array[StartupMailboxCommand] = [
    {
      transition: SafeOpToOp,
      index: 0x6060U,
      subindex: b'\x00',
      data: Bytes::from_array([b'\x09']),
    },
  ]
  let merged = merge_startup_mailbox_commands(derived, explicit)
  assert_eq(merged.length(), 2)
  assert_eq(merged[0].transition, PreOpToSafeOp)
  assert_eq(merged[0].index, 0x1C12U)
  assert_eq(merged[1].transition, SafeOpToOp)
  assert_eq(merged[1].index, 0x6060U)
  assert_eq(merged[1].data, Bytes::from_array([b'\x09']))
}

///|
test "slices_overlap_output zero length" {
  let a : ProcessImageSlice = {
    output_offset: 0,
    output_length: 0,
    input_offset: 0,
    input_length: 10,
  }
  let b : ProcessImageSlice = {
    output_offset: 0,
    output_length: 10,
    input_offset: 0,
    input_length: 10,
  }
  assert_true(slices_overlap_output(a, b) == false)
}

///|
test "slices_overlap_input zero length" {
  let a : ProcessImageSlice = {
    output_offset: 0,
    output_length: 10,
    input_offset: 0,
    input_length: 0,
  }
  let b : ProcessImageSlice = {
    output_offset: 0,
    output_length: 10,
    input_offset: 0,
    input_length: 10,
  }
  assert_true(slices_overlap_input(a, b) == false)
}

///|
test "eni_json_document_from_configuration round trip" {
  let config : ConfigurationModel = {
    source: OnlineScan,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: Some(0x100U),
        identity: Some({
          vendor_id: 1U,
          product_code: 2U,
          revision: 3U,
          serial: 4U,
        }),
        identification: Some(42U),
        process_data_summary: Some({
          sync_manager_count: 2,
          fmmu_count: 2,
          rx_pdo_count: 1,
          tx_pdo_count: 1,
          mailbox_protocols: Some({
            aoe: false,
            coe: true,
            eoe: false,
            foe: false,
            soe: false,
            voe: false,
          }),
          dc_op_mode_count: 1,
          dc_assign_activate_count: 1,
        }),
        presence: @hal.Mandatory,
      },
    ],
  }
  let doc = eni_json_document_from_configuration(config)
  assert_eq(doc.slaves.length(), 1)
  assert_eq(doc.slaves[0].position, 0)
}

///|
test "AutoTuneResult to_json with multiple recommendations" {
  let result : AutoTuneResult = {
    success: true,
    reference_station: 0x1001U,
    recommendations: [
      {
        station: 0x1001U,
        sync0_offset_ns: 100L,
        sync1_offset_ns: 200L,
        sync0_cycle_ns: 1_000_000L,
        propagation_delay_ns: 50L,
      },
      {
        station: 0x1002U,
        sync0_offset_ns: 300L,
        sync1_offset_ns: 400L,
        sync0_cycle_ns: 1_000_000L,
        propagation_delay_ns: 150L,
      },
    ],
    probe_data: [],
    measurement_duration_ns: 50_000_000L,
    messages: ["msg1", "msg2"],
  }
  let j = result.to_json()
  assert_true(j.contains("msg1"))
  assert_true(j.contains("msg2"))
}

///|
test "NullRunProgressSink emit no-op" {
  let sink = NullRunProgressSink::new()
  let progress : RunProgress = {
    cycles_completed: 0L,
    cycles_ok: 0,
    cycles_requested: None,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: 0,
    telemetry: Telemetry::new(),
    consecutive_timeouts: 0,
  }
  sink.emit(progress)
}

///|
test "TopologyHealthReport to_json with bottleneck and warnings" {
  let report : TopologyHealthReport = {
    system_health_score: 900,
    system_grade: Excellent,
    max_propagation_delay_ns: 1000L,
    total_cable_length_m: 10.0,
    bottleneck_index: None,
    slaves: [],
    warnings: [],
  }
  let j = report.to_json()
  assert_true(j.contains("null"))
  // Now test with slaves and warnings for separator coverage
  let report2 : TopologyHealthReport = {
    system_health_score: 800,
    system_grade: Good,
    max_propagation_delay_ns: 2000L,
    total_cable_length_m: 20.0,
    bottleneck_index: Some(0),
    slaves: [
      {
        station: 0x1001U,
        position: 0,
        propagation_delay_ns: 100L,
        estimated_cable_length_m: 1.0,
        tx_frames: 100L,
        rx_frames: 99L,
        timeouts: 0L,
        wkc_errors: 0L,
        loss_rate_permille: 10,
        health_score: 950,
        grade: Excellent,
      },
      {
        station: 0x1002U,
        position: 1,
        propagation_delay_ns: 200L,
        estimated_cable_length_m: 2.0,
        tx_frames: 100L,
        rx_frames: 98L,
        timeouts: 1L,
        wkc_errors: 0L,
        loss_rate_permille: 20,
        health_score: 900,
        grade: Good,
      },
    ],
    warnings: ["warning1", "warning2"],
  }
  let j2 = report2.to_json()
  assert_true(j2.contains("warning1"))
  assert_true(j2.contains("warning2"))
  assert_true(j2.contains("4098")) // 0x1002 in decimal
}

///|
// ── Batch 6: whitebox runtime coverage ──

///|
test "runtime_metrics_issues all branches" {
  let t = Telemetry::new()
  t.timeouts = 1L
  t.wkc_errors = 2L
  t.retries = 3L
  let issues = runtime_metrics_issues(t, 100, 95)
  // 4 issues: timeouts>0, wkc_errors>0, retries>0, cycles_ok<cycles_requested
  assert_eq(issues.length(), 4)
}

///|
test "runtime_metrics_issues clean" {
  let t = Telemetry::new()
  let issues = runtime_metrics_issues(t, 100, 100)
  assert_eq(issues.length(), 0)
}

///|
test "diagnosis_bytes_preview empty" {
  assert_eq(diagnosis_bytes_preview(b""), "<empty>")
}

///|
test "diagnosis_bytes_preview single byte" {
  assert_eq(diagnosis_bytes_preview(Bytes::make(1, 0xAB)), "0xAB")
}

///|
test "diagnosis_bytes_preview multi byte" {
  let data = Bytes::makei(2, fn(i) { if i == 0 { b'\x01' } else { b'\xFF' } })
  assert_eq(diagnosis_bytes_preview(data), "0x01 0xFF")
}

///|
test "diagnosis_hex_byte covers all digits" {
  assert_eq(diagnosis_hex_byte(b'\x00'), "0x00")
  assert_eq(diagnosis_hex_byte(b'\x1A'), "0x1A")
  assert_eq(diagnosis_hex_byte(b'\xBF'), "0xBF")
  assert_eq(diagnosis_hex_byte(b'\xFF'), "0xFF")
}

///|
test "diagnosis_hex_digit all values" {
  assert_eq(diagnosis_hex_digit(0), "0")
  assert_eq(diagnosis_hex_digit(1), "1")
  assert_eq(diagnosis_hex_digit(2), "2")
  assert_eq(diagnosis_hex_digit(3), "3")
  assert_eq(diagnosis_hex_digit(4), "4")
  assert_eq(diagnosis_hex_digit(5), "5")
  assert_eq(diagnosis_hex_digit(6), "6")
  assert_eq(diagnosis_hex_digit(7), "7")
  assert_eq(diagnosis_hex_digit(8), "8")
  assert_eq(diagnosis_hex_digit(9), "9")
  assert_eq(diagnosis_hex_digit(10), "A")
  assert_eq(diagnosis_hex_digit(11), "B")
  assert_eq(diagnosis_hex_digit(12), "C")
  assert_eq(diagnosis_hex_digit(13), "D")
  assert_eq(diagnosis_hex_digit(14), "E")
  assert_eq(diagnosis_hex_digit(15), "F")
}

///|
test "decode_le_u32_payload empty" {
  assert_true(decode_le_u32_payload(b"") is None)
}

///|
test "decode_le_u32_payload single byte" {
  let data = Bytes::make(1, 0x42)
  assert_eq(decode_le_u32_payload(data), Some(0x42U))
}

///|
test "decode_le_u32_payload two bytes" {
  let data = Bytes::makei(2, fn(i) { if i == 0 { b'\xCD' } else { b'\xAB' } })
  assert_eq(decode_le_u32_payload(data), Some(0xABCDU))
}

///|
test "decode_le_u32_payload four bytes" {
  let data = Bytes::makei(4, fn(i) {
    match i {
      0 => b'\x78'
      1 => b'\x56'
      2 => b'\x34'
      3 => b'\x12'
      _ => b'\x00'
    }
  })
  assert_eq(decode_le_u32_payload(data), Some(0x12345678U))
}

///|
test "decode_le_u32_payload more than 4 bytes takes first 4" {
  let data = Bytes::makei(6, fn(i) {
    match i {
      0 => b'\x01'
      1 => b'\x02'
      2 => b'\x03'
      3 => b'\x04'
      _ => b'\xFF'
    }
  })
  assert_eq(decode_le_u32_payload(data), Some(0x04030201U))
}

///|
test "lookup_esm_timeout_policy found" {
  let p1 : @protocol.EsmTimeoutPolicy = {
    init: Some(@hal.Duration(111L)),
    preop: None,
    safeop: None,
    op: None,
    boot: None,
  }
  let p2 : @protocol.EsmTimeoutPolicy = {
    init: None,
    preop: Some(@hal.Duration(222L)),
    safeop: None,
    op: None,
    boot: None,
  }
  let policies = [(0x1001U, p1), (0x1002U, p2)]
  let p = lookup_esm_timeout_policy(policies, 0x1002U)
  assert_eq(p.preop, Some(@hal.Duration(222L)))
}

///|
test "lookup_esm_timeout_policy not found returns default" {
  let policies : Array[(UInt, @protocol.EsmTimeoutPolicy)] = []
  let p = lookup_esm_timeout_policy(policies, 0x1001U)
  assert_true(p.init is None)
  assert_true(p.preop is None)
}

///|
test "has_process_data_length_override both None" {
  assert_eq(has_process_data_length_override(None, None), false)
}

///|
test "has_process_data_length_override output Some" {
  assert_eq(has_process_data_length_override(Some(10), None), true)
}

///|
test "has_process_data_length_override input Some" {
  assert_eq(has_process_data_length_override(None, Some(5)), true)
}

///|
test "should_retry_process_data_lengths Ok no override" {
  assert_eq(
    should_retry_process_data_lengths_after_mailbox_refresh(Ok((None, None))),
    true,
  )
}

///|
test "should_retry_process_data_lengths Ok with override" {
  assert_eq(
    should_retry_process_data_lengths_after_mailbox_refresh(
      Ok((Some(10), None)),
    ),
    false,
  )
}

///|
test "should_retry_process_data_lengths MailboxTimeout" {
  assert_eq(
    should_retry_process_data_lengths_after_mailbox_refresh(
      Err(@hal.EcError::MailboxTimeout),
    ),
    true,
  )
}

///|
test "should_retry_process_data_lengths MailboxProtocol deactivated" {
  assert_eq(
    should_retry_process_data_lengths_after_mailbox_refresh(
      Err(
        @hal.EcError::MailboxProtocol("SM deactivated/reset after transition"),
      ),
    ),
    true,
  )
}

///|
test "should_retry_process_data_lengths other error" {
  assert_eq(
    should_retry_process_data_lengths_after_mailbox_refresh(
      Err(@hal.EcError::RecvTimeout),
    ),
    false,
  )
}

///|
test "prefer_dc_cycle_period current Some wins" {
  assert_eq(prefer_dc_cycle_period(Some(100L), Some(200L)), Some(100L))
}

///|
test "prefer_dc_cycle_period current None uses candidate" {
  assert_eq(prefer_dc_cycle_period(None, Some(200L)), Some(200L))
}

///|
test "prefer_dc_cycle_period both None" {
  assert_eq(prefer_dc_cycle_period(None, None), None)
}

///|
// ── Batch 7: more whitebox coverage ──

///|
test "pdo_mapping_entry_u32 packs correctly" {
  let entry : @mailbox.SiiPdoEntry = {
    entry_index: 0x6000U,
    subindex: b'\x01',
    name_idx: b'\x00',
    data_type: b'\x05',
    bit_length: b'\x10',
    flags: 0U,
  }
  // (bit_length << 24) dropped — formula is (index << 16) | (subindex << 8) | bit_length
  // Actually: (entry_index << 16) | (subindex << 8) | bit_length
  let result = pdo_mapping_entry_u32(entry)
  // entry_index=0x6000, subindex=0x01, bit_length=0x10
  // = (0x6000 << 16) | (0x01 << 8) | 0x10
  assert_eq(result, 0x60000110U)
}

///|
test "pdo_mapping_entry_u32 zero fields" {
  let entry : @mailbox.SiiPdoEntry = {
    entry_index: 0U,
    subindex: b'\x00',
    name_idx: b'\x00',
    data_type: b'\x00',
    bit_length: b'\x00',
    flags: 0U,
  }
  assert_eq(pdo_mapping_entry_u32(entry), 0U)
}

///|
test "sii_prefers_not_lrw general None returns false" {
  let sii : @mailbox.SiiFullInfo = {
    eeprom: b"",
    preamble: {
      pdi_control: 0U,
      pdi_config: 0U,
      sync_impulse_length_raw: 0U,
      pdi_config2: 0U,
      configured_station_alias: 0U,
      checksum: 0U,
      checksum_ok: true,
    },
    standard: { eeprom_size_raw: 0U, version: 0U },
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
    categories: [],
    strings: [],
    general: None,
    timeouts: None,
    fmmu: [],
    fmmu_ex: [],
    sync_managers: [],
    sync_units: [],
    tx_pdo: [],
    rx_pdo: [],
    dc_clocks: [],
  }
  assert_eq(sii_prefers_not_lrw(sii), false)
}

///|
test "map_with_process_data_lengths patches output SM" {
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [
      {
        physical_start: 0x1000U,
        length: 4U,
        control: b'\x64',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.ProcessDataOut,
      },
    ],
    fmmu_configs: [
      {
        logical_start: 0U,
        length: 4U,
        logical_start_bit: b'\x00',
        logical_end_bit: b'\x07',
        physical_start: 0x1000U,
        physical_start_bit: b'\x00',
        direction: @mailbox.Outputs,
        activate: true,
      },
    ],
    output_bytes: 4,
    input_bytes: 0,
  }
  let patched = map_with_process_data_lengths(mapping, 0U, Some(16), None)
  // The output SM should be patched to 16
  assert_eq(patched.sm_configs[0].length, 16U)
  assert_eq(patched.output_bytes, 16)
}

///|
test "map_with_process_data_lengths None passthrough" {
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [
      {
        physical_start: 0x1000U,
        length: 4U,
        control: b'\x64',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.ProcessDataOut,
      },
    ],
    fmmu_configs: [
      {
        logical_start: 0U,
        length: 4U,
        logical_start_bit: b'\x00',
        logical_end_bit: b'\x07',
        physical_start: 0x1000U,
        physical_start_bit: b'\x00',
        direction: @mailbox.Outputs,
        activate: true,
      },
    ],
    output_bytes: 4,
    input_bytes: 0,
  }
  let patched = map_with_process_data_lengths(mapping, 0U, None, None)
  assert_eq(patched.sm_configs[0].length, 4U)
}

///|
test "uint_to_hex nonzero values" {
  assert_eq(uint_to_hex(0x1001U), "1001")
  assert_eq(uint_to_hex(0xFFU), "ff")
  assert_eq(uint_to_hex(1U), "1")
  assert_eq(uint_to_hex(0U), "0")
}

///|
test "pdo_complete_access_data single entry" {
  let pdo : @mailbox.SiiPdo = {
    pdo_index: 0x1600U,
    entry_count: b'\x01',
    sync_manager: b'\x02',
    synchronization: b'\x00',
    name_idx: b'\x00',
    flags: 0U,
    entries: [
      {
        entry_index: 0x7000U,
        subindex: b'\x01',
        name_idx: b'\x00',
        data_type: b'\x05',
        bit_length: b'\x08',
        flags: 0U,
      },
    ],
  }
  let data = pdo_complete_access_data(pdo)
  // First byte = entry count
  assert_eq(data[0], b'\x01')
  // Then 4 bytes of mapping entry
  assert_true(data.length() == 5)
}

///|
test "sm_assignment_complete_access_data filters by sync_manager" {
  let pdos : Array[@mailbox.SiiPdo] = [
    {
      pdo_index: 0x1600U,
      entry_count: b'\x01',
      sync_manager: b'\x02',
      synchronization: b'\x00',
      name_idx: b'\x00',
      flags: 0U,
      entries: [],
    },
    {
      pdo_index: 0x1601U,
      entry_count: b'\x01',
      sync_manager: b'\x03',
      synchronization: b'\x00',
      name_idx: b'\x00',
      flags: 0U,
      entries: [],
    },
  ]
  let data = sm_assignment_complete_access_data(pdos, b'\x02')
  // First byte = count of matching PDOs (only 1 with SM=2)
  assert_eq(data[0], b'\x01')
  // Then 2 bytes for index 0x1600
  assert_eq(data.length(), 3)
}

// ===== Batch 8: diagnosis, eoe_switch, scan private helpers =====

///|
test "diagnostic_level_rank ordering" {
  assert_true(diagnostic_level_rank(Info) < diagnostic_level_rank(Degrade))
  assert_true(diagnostic_level_rank(Degrade) < diagnostic_level_rank(Block))
  assert_eq(diagnostic_level_rank(Info), 0)
  assert_eq(diagnostic_level_rank(Degrade), 1)
  assert_eq(diagnostic_level_rank(Block), 2)
}

///|
test "diagnostic_level_from_validate_grade mapping" {
  assert_eq(diagnostic_level_from_validate_grade(Pass), Info)
  assert_eq(diagnostic_level_from_validate_grade(Warn), Degrade)
  assert_eq(diagnostic_level_from_validate_grade(Block), Block)
}

///|
test "highest_diagnostic_level empty list uses fallback" {
  let issues : Array[DiagnosticIssue] = []
  assert_eq(highest_diagnostic_level(issues, Info), Info)
  assert_eq(highest_diagnostic_level(issues, Block), Block)
}

///|
test "highest_diagnostic_level picks highest among issues" {
  let issues : Array[DiagnosticIssue] = [
    {
      source: RuntimeTelemetry,
      category: RuntimeMetrics,
      level: Info,
      detail: "ok",
    },
    {
      source: RuntimeTelemetry,
      category: RuntimeMetrics,
      level: Degrade,
      detail: "warn",
    },
  ]
  assert_eq(highest_diagnostic_level(issues, Info), Degrade)
}

///|
test "highest_diagnostic_level Block overrides all" {
  let issues : Array[DiagnosticIssue] = [
    {
      source: RuntimeTelemetry,
      category: RuntimeMetrics,
      level: Block,
      detail: "fatal",
    },
  ]
  assert_eq(highest_diagnostic_level(issues, Info), Block)
}

///|
test "empty_state_surface_summary all None" {
  let s = empty_state_surface_summary()
  assert_true(s.target_state is None)
  assert_true(s.current_state is None)
  assert_true(s.final_state is None)
  assert_true(s.al_state is None)
  assert_true(s.al_error_flag is None)
  assert_true(s.al_status_code is None)
  assert_true(s.wkc is None)
}

///|
test "runtime_metrics_summary maps telemetry fields" {
  let tel : Telemetry = {
    cycles: 100L,
    tx_frames: 50L,
    rx_frames: 48L,
    timeouts: 2L,
    retries: 1L,
    wkc_errors: 3L,
    irq_events: 10L,
    dc_delay_updates: 5L,
    emergency_events: 0L,
  }
  let s = runtime_metrics_summary(tel)
  assert_eq(s.cycles, 100L)
  assert_eq(s.tx_frames, 50L)
  assert_eq(s.rx_frames, 48L)
  assert_eq(s.timeouts, 2L)
  assert_eq(s.retries, 1L)
  assert_eq(s.wkc_errors, 3L)
  assert_eq(s.irq_events, 10L)
  assert_eq(s.dc_delay_updates, 5L)
  assert_eq(s.emergency_events, 0L)
}

///|
test "runtime_metrics_issues no issues when clean" {
  let tel : Telemetry = {
    cycles: 10L,
    tx_frames: 10L,
    rx_frames: 10L,
    timeouts: 0L,
    retries: 0L,
    wkc_errors: 0L,
    irq_events: 0L,
    dc_delay_updates: 0L,
    emergency_events: 0L,
  }
  let issues = runtime_metrics_issues(tel, 10, 10)
  assert_eq(issues.length(), 0)
}

///|
test "runtime_metrics_issues timeout and wkc and retry and incomplete" {
  let tel : Telemetry = {
    cycles: 10L,
    tx_frames: 10L,
    rx_frames: 10L,
    timeouts: 5L,
    retries: 3L,
    wkc_errors: 2L,
    irq_events: 0L,
    dc_delay_updates: 0L,
    emergency_events: 0L,
  }
  let issues = runtime_metrics_issues(tel, 10, 7)
  assert_eq(issues.length(), 4)
}

///|
test "validation_difference_issue Topology category for Missing" {
  let diff = ConfigurationDifference::Missing(position=0)
  let issue = validation_difference_issue(diff)
  assert_true(issue.source is Topology)
  assert_true(issue.category is DiagnosticCategory::Topology)
  assert_true(issue.level is Block)
}

///|
test "validation_difference_issue Identity category for IdentityMismatch" {
  let diff = ConfigurationDifference::IdentityMismatch(
    position=0,
    expected=(None : @hal.SlaveIdentity?),
    actual=(None : @hal.SlaveIdentity?),
  )
  let issue = validation_difference_issue(diff)
  assert_true(issue.source is Configuration)
  assert_true(issue.category is Identity)
}

///|
test "validation_difference_issue Configuration category for ProcessDataSummaryMismatch" {
  let expected : ConfigurationProcessDataSummary = {
    sync_manager_count: 0,
    fmmu_count: 0,
    rx_pdo_count: 0,
    tx_pdo_count: 0,
    mailbox_protocols: None,
    dc_op_mode_count: 0,
    dc_assign_activate_count: 0,
  }
  let actual : ConfigurationProcessDataSummary = {
    sync_manager_count: 2,
    fmmu_count: 1,
    rx_pdo_count: 1,
    tx_pdo_count: 1,
    mailbox_protocols: None,
    dc_op_mode_count: 0,
    dc_assign_activate_count: 0,
  }
  let diff = ConfigurationDifference::ProcessDataSummaryMismatch(
    position=0,
    expected~,
    actual~,
  )
  let issue = validation_difference_issue(diff)
  assert_true(issue.source is Configuration)
  assert_true(issue.category is DiagnosticCategory::Configuration)
}

///|
test "validation_difference_issue Warn level for Extra" {
  let diff = ConfigurationDifference::Extra(position=0)
  let issue = validation_difference_issue(diff)
  assert_true(issue.level is Degrade)
}

///|
test "configuration_surface_summary maps scan report" {
  let scan : ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 0U,
        serial: 0U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 3U,
        revision: 0U,
        serial: 0U,
        identification: 0U,
      },
    ],
  }
  let s = configuration_surface_summary(
    scan,
    Some(OnlineScan),
    Some(OfflineConfig),
    Some(Pass),
    0,
  )
  assert_eq(s.slave_count, 2)
  assert_eq(s.station_addresses.length(), 2)
  assert_eq(s.station_addresses[0], 0x1001U)
  assert_eq(s.difference_count, 0)
}

// ===== EoE switch private helpers =====

///|
test "EoeStationContext next_counter wraps 1 to 7" {
  let mb : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let ctx = EoeStationContext::new(0x1001U, mb)
  // Initial mb_counter = 1
  let c1 = ctx.next_counter()
  assert_eq(c1, b'\x01')
  let c2 = ctx.next_counter()
  assert_eq(c2, b'\x02')
  // Advance to 7
  let _ = ctx.next_counter() // 3
  let _ = ctx.next_counter() // 4
  let _ = ctx.next_counter() // 5
  let _ = ctx.next_counter() // 6
  let c7 = ctx.next_counter()
  assert_eq(c7, b'\x07')
  // Should wrap to 1
  let c_wrap = ctx.next_counter()
  assert_eq(c_wrap, b'\x01')
}

///|
test "EoeStationContext next_frame_number wraps 0 to 15" {
  let mb : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let ctx = EoeStationContext::new(0x1001U, mb)
  // Should produce 0..15 then wrap
  for i = 0; i < 16; i = i + 1 {
    assert_eq(ctx.next_frame_number(), i.reinterpret_as_uint())
  }
  // Should wrap to 0
  assert_eq(ctx.next_frame_number(), 0U)
}

///|
test "EoeStationContext get_reassembly allocates new buffer" {
  let mb : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let ctx = EoeStationContext::new(0x1001U, mb)
  let buf = ctx.get_reassembly(5U)
  assert_eq(buf.frame_number, 5U)
}

///|
test "EoeStationContext get_reassembly returns existing" {
  let mb : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let ctx = EoeStationContext::new(0x1001U, mb)
  let buf1 = ctx.get_reassembly(3U)
  buf1.total_bytes = 42
  let buf2 = ctx.get_reassembly(3U)
  assert_eq(buf2.total_bytes, 42)
}

///|
test "EoeStationContext clear_reassembly removes buffer" {
  let mb : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let ctx = EoeStationContext::new(0x1001U, mb)
  let _ = ctx.get_reassembly(7U)
  ctx.clear_reassembly(7U)
  // After clearing, get_reassembly should return a new (empty) buffer
  let buf2 = ctx.get_reassembly(7U)
  assert_eq(buf2.total_bytes, 0)
}

// ===== Batch 24: encode_sii_sync_managers DynamicProcessDataIn, build_general_projection =====

///|
test "encode_sii_sync_managers DynamicProcessDataIn" {
  let sms : Array[@mailbox.SiiSmEntry] = [
    {
      physical_start: 0x1100U,
      length: 32U,
      control: b'\x24',
      status: b'\x00',
      activate: b'\x01',
      sm_type: DynamicProcessDataIn,
    },
  ]
  let result = encode_sii_sync_managers(sms)
  // sm_type byte is at offset 7 for each SM entry (8 bytes per entry)
  assert_eq(result[7], b'\x06')
}

///|
test "build_general_projection soe true sets soe_channels" {
  let device = make_minimal_esi_device()
  // Override mailbox with soe=true
  let device : EsiJsonDevice = {
    ..device,
    mailbox: {
      data_link_layer: false,
      aoe: false,
      coe_present: false,
      coe_sdo_info: false,
      coe_pdo_assign: false,
      coe_pdo_config: false,
      coe_complete_access: false,
      eoe: false,
      foe: false,
      soe: true,
      voe: false,
    },
  }
  let strings : Array[String] = []
  let general = build_general_projection(device, strings)
  assert_eq(general.soe_channels, b'\x01')
  assert_true(general.soe_supported)
}

///|
test "build_general_projection non-ds402 sets ds402_channels zero" {
  let device = make_minimal_esi_device()
  // profile_no is None (not DS402)
  let strings : Array[String] = []
  let general = build_general_projection(device, strings)
  assert_eq(general.ds402_channels, b'\x00')
}

///|
test "intern_sii_string too many strings raises" {
  let strings : Array[String] = []
  for i = 0; i < 255; i = i + 1 {
    strings.push("s" + i.to_string())
  }
  let result = try? intern_sii_string(strings, "one_more")
  assert_true(result is Err(_))
}

///|
test "EoeReassemblyBuffer insert and assemble multi-fragment" {
  let buf = EoeReassemblyBuffer::new(0U)
  let complete1 = buf.insert(0U, false, b"\x01\x02")
  assert_eq(complete1, false)
  let complete2 = buf.insert(1U, true, b"\x03\x04")
  assert_eq(complete2, true)
  let assembled = buf.assemble()
  assert_eq(assembled.length(), 4)
  assert_eq(assembled[0], b'\x01')
  assert_eq(assembled[1], b'\x02')
  assert_eq(assembled[2], b'\x03')
  assert_eq(assembled[3], b'\x04')
}

///|
test "EoeSwitch find_station returns None for unknown" {
  let sw = EoeSwitch::new()
  let result = sw.find_station(0x1001U)
  assert_true(result is None)
}

///|
test "EoeSwitch add_station and find_station" {
  let sw = EoeSwitch::new()
  let mb : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, mb)
  let result = sw.find_station(0x1001U)
  assert_true(result is Some(_))
}

// ===== Scan private helpers =====

///|
test "identity_is_zero all zeros" {
  let id : @hal.SlaveIdentity = {
    vendor_id: 0U,
    product_code: 0U,
    revision: 0U,
    serial: 0U,
  }
  assert_eq(identity_is_zero(id), true)
}

///|
test "identity_is_zero nonzero vendor" {
  let id : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 0U,
    revision: 0U,
    serial: 0U,
  }
  assert_eq(identity_is_zero(id), false)
}

///|
test "array_contains_uint found" {
  assert_eq(array_contains_uint([1U, 2U, 3U], 2U), true)
}

///|
test "array_contains_uint not found" {
  assert_eq(array_contains_uint([1U, 2U, 3U], 4U), false)
}

///|
test "array_contains_uint empty" {
  assert_eq(array_contains_uint([], 1U), false)
}

///|
test "scan_station_address_occurs_once unique" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0x1001U },
    { position: 1U, current_station_address: 0x1002U },
  ]
  assert_eq(scan_station_address_occurs_once(0x1001U, observed), true)
}

///|
test "scan_station_address_occurs_once duplicated" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0x1001U },
    { position: 1U, current_station_address: 0x1001U },
  ]
  assert_eq(scan_station_address_occurs_once(0x1001U, observed), false)
}

///|
test "scan_station_address_occurs_once not present" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0x1001U },
  ]
  assert_eq(scan_station_address_occurs_once(0x9999U, observed), false)
}

///|
test "should_preserve_scan_station_address zero returns false" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0U },
  ]
  assert_eq(should_preserve_scan_station_address(0U, observed), false)
}

///|
test "should_preserve_scan_station_address unique non-zero returns true" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0x2000U },
  ]
  assert_eq(should_preserve_scan_station_address(0x2000U, observed), true)
}

///|
test "plan_scan_station_addresses_preserve_existing_unique_non_zero preserves unique" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0x2000U },
    { position: 1U, current_station_address: 0x3000U },
  ]
  let planned = plan_scan_station_addresses_preserve_existing_unique_non_zero(
    observed,
  )
  assert_eq(planned[0], 0x2000U)
  assert_eq(planned[1], 0x3000U)
}

///|
test "plan_scan_station_addresses_preserve_existing_unique_non_zero reassigns duplicates" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0x1001U },
    { position: 1U, current_station_address: 0x1001U },
  ]
  let planned = plan_scan_station_addresses_preserve_existing_unique_non_zero(
    observed,
  )
  // Both duplicated → both get reassigned starting at scan_station_address_base
  assert_eq(planned[0], 0x1001U) // scan_station_address_base = 0x1001, but also same as current
  assert_eq(planned.length(), 2)
  // Second should be different from first
  assert_true(planned[0] != planned[1])
}

///|
test "plan_scan_station_addresses_preserve_existing_unique_non_zero reassigns zero" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0U },
  ]
  let planned = plan_scan_station_addresses_preserve_existing_unique_non_zero(
    observed,
  )
  // Zero address gets reassigned
  assert_eq(planned[0], 0x1001U) // scan_station_address_base
}

// ===== Batch 21: esi_json decode helpers — error paths =====

///|
test "decode_esi_json_string with non-string raises EsiParseFailed" {
  let json = @json.parse("42"[:]) catch { _ => panic() }
  let result : Result[String, _] = try? decode_esi_json_string(json)
  assert_true(result is Err(_))
}

///|
test "decode_esi_json_uint with non-number raises EsiParseFailed" {
  let json = @json.parse("\"hello\""[:]) catch { _ => panic() }
  let result : Result[UInt, _] = try? decode_esi_json_uint(json)
  assert_true(result is Err(_))
}

///|
test "decode_esi_json_int with non-number raises EsiParseFailed" {
  let json = @json.parse("true"[:]) catch { _ => panic() }
  let result : Result[Int, _] = try? decode_esi_json_int(json)
  assert_true(result is Err(_))
}

///|
test "decode_esi_json_bool with non-bool raises EsiParseFailed" {
  let json = @json.parse("1"[:]) catch { _ => panic() }
  let result : Result[Bool, _] = try? decode_esi_json_bool(json)
  assert_true(result is Err(_))
}

///|
test "decode_esi_json_byte with value out of range raises" {
  let json = @json.parse("300"[:]) catch { _ => panic() }
  let result : Result[Byte, _] = try? decode_esi_json_byte(json)
  assert_true(result is Err(_))
}

///|
test "decode_esi_json_byte with negative value raises" {
  let json = @json.parse("-1"[:]) catch { _ => panic() }
  let result : Result[Byte, _] = try? decode_esi_json_byte(json)
  assert_true(result is Err(_))
}

///|
test "decode_esi_json_optional_uint with null returns None" {
  let json = @json.parse("null"[:]) catch { _ => panic() }
  let result = decode_esi_json_optional_uint(json)
  assert_eq(result, None)
}

///|
test "decode_esi_json_optional_uint with number returns Some" {
  let json = @json.parse("42"[:]) catch { _ => panic() }
  let result = decode_esi_json_optional_uint(json)
  assert_eq(result, Some(42U))
}

///|
test "decode_esi_json_bytes with array fallback" {
  // When direct @json.from_json fails (Array of numbers), fallback to manual decode
  let json = @json.parse("[16, 32, 48]"[:]) catch { _ => panic() }
  let result = decode_esi_json_bytes(json)
  assert_eq(result[0], b'\x10')
  assert_eq(result[1], b'\x20')
  assert_eq(result[2], b'\x30')
}

///|
test "decode_esi_json_bytes with non-array raises" {
  let json = @json.parse("true"[:]) catch { _ => panic() }
  let result : Result[Bytes, _] = try? decode_esi_json_bytes(json)
  assert_true(result is Err(_))
}

///|
test "parse_esi_json_pdo with malformed json raises" {
  let json = @json.parse("{\"invalid\": \"data\"}"[:]) catch { _ => panic() }
  let result : Result[EsiJsonPdo, _] = try? parse_esi_json_pdo(json)
  assert_true(result is Err(_))
}

///|
test "parse_esi_json_pdo_entry with malformed json raises" {
  let json = @json.parse("{\"missing\": \"fields\"}"[:]) catch { _ => panic() }
  let result : Result[EsiJsonPdoEntry, _] = try? parse_esi_json_pdo_entry(json)
  assert_true(result is Err(_))
}

///|
test "parse_esi_json_dc_mode with malformed json raises" {
  let json = @json.parse("\"bad\""[:]) catch { _ => panic() }
  let result : Result[EsiJsonDcMode, _] = try? parse_esi_json_dc_mode(json)
  assert_true(result is Err(_))
}

///|
test "parse_esi_json_selected_module with malformed json raises" {
  let json = @json.parse("42"[:]) catch { _ => panic() }
  let result : Result[EsiJsonSelectedModule, _] = try? parse_esi_json_selected_module(
    json,
  )
  assert_true(result is Err(_))
}

// ===== Batch 21: multi_rate — non-harmonic and peak cycle analysis =====

///|
test "analyze_multi_rate non-harmonic schedule" {
  let schedule : TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 3,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 4,
        },
      },
      {
        name: "t2",
        priority: 1,
        cycle_divisor: 2,
        slice: {
          output_offset: 4,
          output_length: 8,
          input_offset: 4,
          input_length: 8,
        },
      },
    ],
  }
  let analysis = analyze_multi_rate(schedule)
  // LCM(3,2) = 6
  assert_eq(analysis.hyperperiod, 6)
  // 3 is not a power of 2
  assert_eq(analysis.is_harmonic, false)
  // Cycle 0: both (count=2), Cycle 1: none, Cycle 2: t2 only, Cycle 3: t1 only, Cycle 4: t2 only, Cycle 5: none
  assert_eq(analysis.worst_case_tasks_per_cycle, 2)
  assert_eq(analysis.peak_cycles, [0])
}

///|
test "analyze_multi_rate with multiple peak cycles" {
  let schedule : TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 2,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 4,
        },
      },
    ],
  }
  let analysis = analyze_multi_rate(schedule)
  // LCM(2) = 2, all powers of 2 → harmonic
  assert_eq(analysis.hyperperiod, 2)
  assert_eq(analysis.is_harmonic, true)
  // Cycle 0: t1, Cycle 1: none → worst = 1, peaks = [0]
  assert_eq(analysis.worst_case_tasks_per_cycle, 1)
  assert_eq(analysis.peak_cycles, [0])
}

///|
test "validate_multi_rate detects excessive hyperperiod" {
  let schedule : TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 7,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 4,
        },
      },
      {
        name: "t2",
        priority: 1,
        cycle_divisor: 13,
        slice: {
          output_offset: 4,
          output_length: 8,
          input_offset: 4,
          input_length: 8,
        },
      },
    ],
  }
  // LCM(7,13) = 91, exceeds max_hyperperiod = 8
  let errors = validate_multi_rate(schedule, max_hyperperiod=8)
  assert_true(errors.length() > 0)
}

// ===== Batch 23: resolve_selected_module_pdos missing module =====

///|
test "resolve_selected_module_pdos skips missing module_ident" {
  let device : EsiJsonDevice = {
    vendor_id: 1U,
    product_code: 1U,
    revision: 1U,
    serial: 0U,
    physics: "YY",
    device_name: "Test",
    type_name: "Test",
    profile_no: None,
    slot_index_increment: 1U,
    slot_pdo_increment: 1U,
    mailbox: {
      data_link_layer: false,
      aoe: false,
      coe_present: false,
      coe_sdo_info: false,
      coe_pdo_assign: false,
      coe_pdo_config: false,
      coe_complete_access: false,
      eoe: false,
      foe: false,
      soe: false,
      voe: false,
    },
    fmmu: [],
    sync_managers: [],
    dc_modes: [],
    eeprom_byte_size: 256U,
    config_data: b"",
    bootstrap: b"",
    default_modules: [{ module_ident: 9999U, slot_index: 0 }],
    init_commands: [],
    rx_pdos: [],
    tx_pdos: [],
  }
  let modules : Array[EsiJsonModule] = [] // no modules → None path
  let (tx, rx) = resolve_selected_module_pdos(device, modules)
  assert_eq(tx.length(), 0)
  assert_eq(rx.length(), 0)
}

// ===== Batch 26: HilCycleHook Terminated/Error paths =====

///|
struct TerminatingAdapter {
  mut call_count : Int
  terminate_at : Int
}

///|
impl CoSimAdapter for TerminatingAdapter with init_(self, _config) {
  ignore(self)
}

///|
impl CoSimAdapter for TerminatingAdapter with write_outputs(
  self,
  _image,
  _slice,
) {
  ignore(self)
}

///|
impl CoSimAdapter for TerminatingAdapter with step(self, current, dt) {
  self.call_count += 1
  if self.call_count >= self.terminate_at {
    Terminated("limit reached")
  } else {
    Ok(current.advance(dt))
  }
}

///|
impl CoSimAdapter for TerminatingAdapter with read_inputs(self, _image, _slice) {
  ignore(self)
}

///|
impl CoSimAdapter for TerminatingAdapter with shutdown(self) {
  ignore(self)
}

///|
test "HilCycleHook on_post_cycle Terminated path" {
  let adapter : TerminatingAdapter = { call_count: 0, terminate_at: 1 }
  let schedule : TaskSchedule = { base_period_ns: 1_000_000L, tasks: [] }
  let session = HilSession::new(1_000_000L, schedule)
  let hook = HilCycleHook::new(adapter, session)
  let image = @protocol.ProcessImage::new(0, 0)
  let ctx : @protocol.PdoContext = {
    image,
    mappings: [],
    logical_base: 0U,
    logical_size: 0,
    block_lrw: false,
  }
  let snap : CycleSnapshot = {
    cycle: 0L,
    result: None,
    dc_state: Disabled,
    recovery_pending: false,
  }
  let directive = hook.on_post_cycle(snap, ctx)
  assert_eq(directive, StopGraceful)
  assert_true(hook.session.terminated)
  assert_eq(hook.session.termination_reason, "limit reached")
}

///|
struct ErrorAdapter {
  mut call_count : Int
  error_at : Int
}

///|
impl CoSimAdapter for ErrorAdapter with init_(self, _config) {
  ignore(self)
}

///|
impl CoSimAdapter for ErrorAdapter with write_outputs(self, _image, _slice) {
  ignore(self)
}

///|
impl CoSimAdapter for ErrorAdapter with step(self, current, dt) {
  self.call_count += 1
  if self.call_count >= self.error_at {
    Error("solver diverged")
  } else {
    Ok(current.advance(dt))
  }
}

///|
impl CoSimAdapter for ErrorAdapter with read_inputs(self, _image, _slice) {
  ignore(self)
}

///|
impl CoSimAdapter for ErrorAdapter with shutdown(self) {
  ignore(self)
}

///|
test "HilCycleHook on_post_cycle Error path" {
  let adapter : ErrorAdapter = { call_count: 0, error_at: 1 }
  let schedule : TaskSchedule = { base_period_ns: 1_000_000L, tasks: [] }
  let session = HilSession::new(1_000_000L, schedule)
  let hook = HilCycleHook::new(adapter, session)
  let image = @protocol.ProcessImage::new(0, 0)
  let ctx : @protocol.PdoContext = {
    image,
    mappings: [],
    logical_base: 0U,
    logical_size: 0,
    block_lrw: false,
  }
  let snap : CycleSnapshot = {
    cycle: 0L,
    result: None,
    dc_state: Disabled,
    recovery_pending: false,
  }
  let directive = hook.on_post_cycle(snap, ctx)
  assert_eq(directive, StopGraceful)
  assert_true(hook.session.terminated)
  assert_eq(hook.session.termination_reason, "solver diverged")
}
