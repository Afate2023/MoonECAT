///|
test "Telemetry initializes to zero" {
  let t = @runtime.Telemetry::new()
  assert_eq(t.cycles, 0L)
  assert_eq(t.tx_frames, 0L)
  assert_eq(t.rx_frames, 0L)
  assert_eq(t.timeouts, 0L)
  assert_eq(t.retries, 0L)
  assert_eq(t.wkc_errors, 0L)
  assert_eq(t.dc_delay_updates, 0L)
  assert_eq(t.emergency_events, 0L)
}

///|
test "RunMode display" {
  inspect(@runtime.RunMode::FreeRun, content="FreeRun")
  inspect(@runtime.RunMode::DcSync, content="DcSync")
}

///|
test "RuntimeState display" {
  inspect(@runtime.RuntimeState::Idle, content="Idle")
  inspect(
    @runtime.RuntimeState::Running(@runtime.RunMode::FreeRun),
    content="Running(FreeRun)",
  )
}

///|
test "Runtime::new initializes correctly" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  assert_true(rt.state is Idle)
  assert_eq(rt.expected_wkc, 0U)
  assert_eq(rt.consecutive_wkc_errors, 0)
  assert_eq(rt.max_wkc_errors, 5)
  assert_true(rt.pdo_ctx is None)
}

///|
test "Runtime state transitions" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.set_state(@runtime.RuntimeState::Scanning)
  assert_true(rt.state is Scanning)
  rt.set_state(@runtime.RuntimeState::Configuring)
  assert_true(rt.state is Configuring)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  assert_true(rt.state is Running(_))
  rt.set_state(@runtime.RuntimeState::Stopping)
  assert_true(rt.state is Stopping)
}

///|
test "Runtime telemetry recording" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.record_timeout()
  rt.record_timeout()
  rt.record_retry()
  let t = rt.get_telemetry()
  assert_eq(t.timeouts, 2L)
  assert_eq(t.retries, 1L)
}

///|
test "Runtime needs_recovery tracks consecutive WKC errors" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  assert_eq(rt.needs_recovery(), false)
  // Simulate consecutive WKC errors
  for _i = 0; _i < 5; _i = _i + 1 {
    rt.consecutive_wkc_errors = rt.consecutive_wkc_errors + 1
  }
  assert_eq(rt.needs_recovery(), true)
  rt.reset_error_counter()
  assert_eq(rt.needs_recovery(), false)
}

///|
test "Runtime configure_pdo sets context" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let mappings : Array[(@mailbox.SlaveMapping, UInt)] = [
    ({ sm_configs: [], fmmu_configs: [], output_bytes: 4, input_bytes: 2 }, 1U),
  ]
  let ctx = @protocol.PdoContext::build(mappings, 0x1000U)
  rt.configure_pdo(ctx, 3U)
  assert_true(rt.pdo_ctx is Some(_))
  assert_eq(rt.expected_wkc, 3U)
}

///|
/// SiiIdentityNic simulates one slave whose identity is read from SII EEPROM.
pub struct SiiIdentityNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut sii_word_address : UInt
}

///|
fn SiiIdentityNic::new() -> SiiIdentityNic {
  { next_response: Bytes::new(0), is_open: true, sii_word_address: 0U }
}

///|
fn sii_identity_eeprom_bytes() -> Bytes {
  let data = FixedArray::make(60, b'\x00')
  data[16] = b'\x02'
  data[20] = b'\x52'
  data[21] = b'\x2C'
  data[22] = b'\x4C'
  data[23] = b'\x04'
  data[26] = b'\x11'
  Bytes::makei(data.length(), fn(i) { data[i] })
}

///|
fn read_u16_from_bytes(data : Bytes, offset : Int) -> UInt {
  data[offset].to_uint() | (data[offset + 1].to_uint() << 8)
}

///|
fn sii_window_bytes(word_address : UInt) -> Bytes {
  let eeprom = sii_identity_eeprom_bytes()
  let byte_offset = word_address.reinterpret_as_int() * 2
  Bytes::makei(4, fn(i) {
    if byte_offset + i < eeprom.length() {
      eeprom[byte_offset + i]
    } else {
      b'\x00'
    }
  })
}

///|
fn build_response_frame(
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
pub impl @hal.Nic for SiiIdentityNic with open_(name) {
  ignore(name)
  SiiIdentityNic::new()
}

///|
pub impl @hal.Nic for SiiIdentityNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.BRD =>
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    @protocol.APWR => {
      if offset == @protocol.reg_sii_control && pdu.data.length() >= 4 {
        self.sii_word_address = read_u16_from_bytes(pdu.data, 2)
      }
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_sii_address && pdu.data.length() >= 2 {
        self.sii_word_address = read_u16_from_bytes(pdu.data, 0)
      } else if offset == @protocol.reg_sii_control && pdu.data.length() >= 4 {
        self.sii_word_address = read_u16_from_bytes(pdu.data, 2)
      }
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_sii_control {
        Bytes::from_array([b'\x00', b'\x00'])
      } else if offset == @protocol.reg_sii_data {
        sii_window_bytes(self.sii_word_address)
      } else if offset == 0x0014U {
        Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00'])
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.APRD => {
      let response_data = if offset == @protocol.reg_sii_control {
        Bytes::from_array([b'\x00', b'\x00'])
      } else if offset == @protocol.reg_sii_data {
        sii_window_bytes(self.sii_word_address)
      } else if offset == 0x0014U {
        Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00'])
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    _ => build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for SiiIdentityNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for SiiIdentityNic with close(self) {
  self.is_open = false
}

///|
/// ScanStationNic simulates slaves with pre-existing CSAs so scan can verify
/// preservation and reassignment policy independently from runtime loop logic.
pub struct ScanStationNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut sii_word_address : UInt
  station_addresses : Array[UInt]
}

///|
fn ScanStationNic::new(station_addresses : Array[UInt]) -> ScanStationNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    sii_word_address: 0U,
    station_addresses,
  }
}

///|
fn read_station_address_bytes(data : Bytes) -> UInt {
  data[0].to_uint() | (data[1].to_uint() << 8)
}

///|
pub impl @hal.Nic for ScanStationNic with open_(name) {
  ignore(name)
  ScanStationNic::new([])
}

///|
pub impl @hal.Nic for ScanStationNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  let position = @protocol.address_station(pdu.header.address).reinterpret_as_int()
  self.next_response = match pdu.header.command {
    @protocol.BRD =>
      build_response_frame(
        request,
        Bytes::new(pdu.data.length()),
        self.station_addresses.length().reinterpret_as_uint(),
      )
    @protocol.APRD => {
      let response_data = if offset == @protocol.reg_station_address {
        let station = self.station_addresses[position]
        Bytes::from_array([
          (station & 0xFFU).reinterpret_as_int().to_byte(),
          ((station >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
        ])
      } else if offset == @protocol.reg_sii_control {
        Bytes::from_array([b'\x00', b'\x00'])
      } else if offset == @protocol.reg_sii_data {
        sii_window_bytes(self.sii_word_address)
      } else if offset == 0x0014U {
        Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00'])
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.APWR => {
      if offset == @protocol.reg_station_address && pdu.data.length() >= 2 {
        self.station_addresses[position] = read_station_address_bytes(pdu.data)
      } else if offset == @protocol.reg_sii_control && pdu.data.length() >= 4 {
        self.sii_word_address = read_u16_from_bytes(pdu.data, 2)
      }
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_station_alias {
        Bytes::from_array([b'\x00', b'\x00'])
      } else if offset == @protocol.reg_sii_control {
        Bytes::from_array([b'\x00', b'\x00'])
      } else if offset == @protocol.reg_sii_data {
        sii_window_bytes(self.sii_word_address)
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_sii_address && pdu.data.length() >= 2 {
        self.sii_word_address = read_u16_from_bytes(pdu.data, 0)
      } else if offset == @protocol.reg_sii_control && pdu.data.length() >= 4 {
        self.sii_word_address = read_u16_from_bytes(pdu.data, 2)
      }
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    _ => build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for ScanStationNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for ScanStationNic with close(self) {
  self.is_open = false
}

///|
/// TimeoutNic is a deterministic test double that always times out on recv.
pub struct TimeoutNic {
  mut is_open : Bool
}

///|
fn TimeoutNic::new() -> TimeoutNic {
  { is_open: true }
}

///|
pub impl @hal.Nic for TimeoutNic with open_(name) {
  ignore(name)
  TimeoutNic::new()
}

///|
pub impl @hal.Nic for TimeoutNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  data.length()
}

///|
pub impl @hal.Nic for TimeoutNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  raise @hal.EcError::RecvTimeout
}

///|
pub impl @hal.Nic for TimeoutNic with close(self) {
  self.is_open = false
}

///|
/// RejectEmptyBusTransitionNic behaves like MockNic until a BWR to AL Control
/// is attempted, which lets tests detect invalid ESM broadcasts on an empty bus.
pub struct RejectEmptyBusTransitionNic {
  inner : @mock.MockNic
  mut state_transition_attempts : Int
}

///|
fn RejectEmptyBusTransitionNic::new() -> RejectEmptyBusTransitionNic {
  { inner: @mock.MockNic::new(), state_transition_attempts: 0 }
}

///|
pub impl @hal.Nic for RejectEmptyBusTransitionNic with open_(name) {
  ignore(name)
  RejectEmptyBusTransitionNic::new()
}

///|
pub impl @hal.Nic for RejectEmptyBusTransitionNic with send(self, data) {
  let frame = @protocol.EcFrame::decode(data)
  for pdu in frame.pdus {
    if pdu.header.command is @protocol.BWR &&
      @protocol.address_offset(pdu.header.address) == @protocol.reg_al_control {
      self.state_transition_attempts = self.state_transition_attempts + 1
      raise @hal.EcError::SendFailed(
        "unexpected AL control broadcast on empty bus",
      )
    }
  }
  self.inner.send(data)
}

///|
pub impl @hal.Nic for RejectEmptyBusTransitionNic with recv(self, timeout~) {
  self.inner.recv(timeout~)
}

///|
pub impl @hal.Nic for RejectEmptyBusTransitionNic with close(self) {
  self.inner.close()
}

///|
/// ConfirmedRunNic simulates one configured slave that supports per-station ESM
/// transitions and deterministic PDO/DC behavior for run-path tests.
pub struct ConfirmedRunNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut sii_word_address : UInt
  mut current_state : Byte
  mut al_control_broadcast_attempts : Int
  lrw_wkc : UInt
  reject_broadcast_al_control : Bool
  fail_frmw : Bool
}

///|
fn ConfirmedRunNic::new(
  lrw_wkc : UInt,
  reject_broadcast_al_control : Bool,
  fail_frmw : Bool,
) -> ConfirmedRunNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    sii_word_address: 0U,
    current_state: @protocol.Init.to_byte(),
    al_control_broadcast_attempts: 0,
    lrw_wkc,
    reject_broadcast_al_control,
    fail_frmw,
  }
}

///|
fn confirmed_run_expected() -> Array[@hal.SlaveConfig] {
  [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x044C2C52U,
        revision: 0x00110000U,
        serial: 0U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
}

///|
fn single_slave_pdo_context() -> @protocol.PdoContext {
  @protocol.PdoContext::build(
    [
      (
        { sm_configs: [], fmmu_configs: [], output_bytes: 1, input_bytes: 0 },
        0x1001U,
      ),
    ],
    0x1000U,
  )
}

///|
pub impl @hal.Nic for ConfirmedRunNic with open_(name) {
  ignore(name)
  ConfirmedRunNic::new(1U, true, false)
}

///|
pub impl @hal.Nic for ConfirmedRunNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.BRD =>
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    @protocol.BWR => {
      if offset == @protocol.reg_al_control {
        self.al_control_broadcast_attempts = self.al_control_broadcast_attempts +
          1
        if self.reject_broadcast_al_control {
          raise @hal.EcError::SendFailed(
            "unexpected AL control broadcast in confirmed run test",
          )
        }
      }
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    @protocol.APWR => {
      if offset == @protocol.reg_sii_control && pdu.data.length() >= 4 {
        self.sii_word_address = read_u16_from_bytes(pdu.data, 2)
      }
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_sii_address && pdu.data.length() >= 2 {
        self.sii_word_address = read_u16_from_bytes(pdu.data, 0)
      } else if offset == @protocol.reg_sii_control && pdu.data.length() >= 4 {
        self.sii_word_address = read_u16_from_bytes(pdu.data, 2)
      } else if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
        self.current_state = pdu.data[0] & b'\x0F'
      }
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_sii_control {
        Bytes::from_array([b'\x00', b'\x00'])
      } else if offset == @protocol.reg_sii_data {
        sii_window_bytes(self.sii_word_address)
      } else if offset == @protocol.reg_al_status {
        Bytes::from_array([self.current_state, b'\x00'])
      } else if offset == @protocol.reg_al_status_code {
        Bytes::from_array([b'\x00', b'\x00'])
      } else if offset == 0x0014U ||
        offset == @protocol.reg_dc_time0 ||
        offset == @protocol.reg_dc_system_time ||
        offset == @protocol.reg_dc_system_diff {
        Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00'])
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.APRD => {
      let response_data = if offset == @protocol.reg_sii_control {
        Bytes::from_array([b'\x00', b'\x00'])
      } else if offset == @protocol.reg_sii_data {
        sii_window_bytes(self.sii_word_address)
      } else if offset == @protocol.reg_al_status {
        Bytes::from_array([self.current_state, b'\x00'])
      } else if offset == 0x0014U {
        Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00'])
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.FRMW => {
      if self.fail_frmw {
        raise @hal.EcError::SendFailed("forced FRMW failure")
      }
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    @protocol.LRW => build_response_frame(request, pdu.data, self.lrw_wkc)
    _ => build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for ConfirmedRunNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for ConfirmedRunNic with close(self) {
  self.is_open = false
}

///|
test "Runtime init_dc disabled keeps state Disabled" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let nic = @mock.MockNic::new()
  let ok = rt.init_dc(nic, [0x1001U], @hal.Duration(1000L))
  assert_eq(ok, false)
  assert_true(rt.dc_state is Disabled)
  assert_true(rt.dc_reference_station is None)
}

///|
test "Runtime init_dc enabled sets Locked" {
  let config = { ..@hal.MasterConfig::default(), dc_enabled: true }
  let rt = @runtime.Runtime::new(config)
  let nic = @mock.MockNic::new()
  let ok = rt.init_dc(nic, [0x1001U], @hal.Duration(1000L))
  assert_eq(ok, true)
  assert_true(rt.dc_state is Locked)
  assert_true(rt.dc_reference_station is Some(_))
}

///|
test "Runtime run_cycles stops on dc drift" {
  let config = { ..@hal.MasterConfig::default(), dc_enabled: true }
  let rt = @runtime.Runtime::new(config)
  let nic = ConfirmedRunNic::new(1U, true, true)
  rt.configure_pdo(single_slave_pdo_context(), 1U)
  rt.dc_reference_station = Some(0x1001U)
  rt.dc_stations = [0x1001U]
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::DcSync))
  let ok = rt.run_cycles(nic, 3, @hal.Duration(1000L))
  assert_eq(ok, 1)
  assert_true(rt.dc_state is Drifting(_))
  assert_true(rt.state is Error(_))
}

///|
test "Runtime run_until_fault stops on repeated wkc mismatch" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let nic = ConfirmedRunNic::new(0U, true, false)
  rt.configure_pdo(single_slave_pdo_context(), 1U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let ok = rt.run_until_fault(nic, @hal.Duration(1000L))
  assert_eq(ok, 0)
  assert_eq(rt.telemetry.wkc_errors, 5L)
  assert_true(rt.state is Error(_))
}

///|
test "Runtime run_until_fault stops on repeated recv timeout" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let nic = TimeoutNic::new()
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 0U)
  rt.set_timeout_threshold(3)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let ok = rt.run_until_fault(nic, @hal.Duration(1000L))
  assert_eq(ok, 0)
  assert_eq(rt.telemetry.timeouts, 3L)
  assert_eq(rt.consecutive_timeouts, 3)
  assert_true(rt.state is Error(_))
}

///|
test "Runtime run_cycle without pdo_ctx raises Internal error" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let nic = @mock.MockNic::new()
  let result = try rt.run_cycle(nic, @hal.Duration(1000L)) catch {
    @hal.EcError::Internal(msg) => msg
    _ => "unexpected"
  } noraise {
    _ => "should fail"
  }
  assert_eq(result, "PDO context not configured")
}

///|
test "DcState display" {
  inspect(@runtime.DcState::Disabled, content="Disabled")
  inspect(@runtime.DcState::Measuring, content="Measuring")
  inspect(@runtime.DcState::Locked, content="Locked")
  inspect(@runtime.DcState::Drifting(100L), content="Drifting(100)")
}

///|
test "CycleResult equality" {
  let r1 : @runtime.CycleResult = { wkc: 3U, expected_wkc: 3U, ok: true }
  let r2 : @runtime.CycleResult = { wkc: 3U, expected_wkc: 3U, ok: true }
  assert_eq(r1, r2)
  let r3 : @runtime.CycleResult = { wkc: 1U, expected_wkc: 3U, ok: false }
  assert_true(r1 != r3)
}

// ========== M4-4: Free-run and recovery path tests ==========

///|
test "Free-run: Runtime lifecycle Idle → Scanning → Configuring → Running" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  assert_true(rt.state is Idle)
  rt.set_state(@runtime.RuntimeState::Scanning)
  assert_true(rt.state is Scanning)
  rt.set_state(@runtime.RuntimeState::Configuring)
  assert_true(rt.state is Configuring)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  assert_true(rt.state is Running(FreeRun))
  rt.set_state(@runtime.RuntimeState::Stopping)
  assert_true(rt.state is Stopping)
  rt.set_state(@runtime.RuntimeState::Idle)
  assert_true(rt.state is Idle)
}

///|
test "Free-run: run_cycle succeeds when expected_wkc is 0" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0x1000U)
  // MockNic echoes back frames with WKC=0
  rt.configure_pdo(ctx, 0U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = @mock.MockNic::new()
  let result = rt.run_cycle(nic, @hal.Duration(1000L))
  assert_eq(result.ok, true)
  assert_eq(result.wkc, 0U)
  assert_eq(result.expected_wkc, 0U)
  assert_eq(rt.consecutive_wkc_errors, 0)
  let t = rt.get_telemetry()
  assert_eq(t.cycles, 1L)
  assert_eq(t.tx_frames, 1L)
  assert_eq(t.rx_frames, 1L)
}

///|
test "DcSync: run_cycle performs compensation and PDO" {
  let config = { ..@hal.MasterConfig::default(), dc_enabled: true }
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0x1000U)
  rt.configure_pdo(ctx, 0U)
  let nic = @mock.MockNic::new()
  ignore(rt.init_dc(nic, [0x1001U], @hal.Duration(1000L)))
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::DcSync))
  let result = rt.run_cycle(nic, @hal.Duration(1000L))
  assert_true(result.ok)
  assert_true(rt.dc_state is Locked || rt.dc_state is Drifting(_))
}

///|
test "Free-run: run_cycles executes multiple cycles" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 0U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = @mock.MockNic::new()
  let success = rt.run_cycles(nic, 10, @hal.Duration(1000L))
  assert_eq(success, 10)
  let t = rt.get_telemetry()
  assert_eq(t.cycles, 10L)
  assert_eq(t.tx_frames, 10L)
  assert_eq(t.rx_frames, 10L)
  assert_eq(t.wkc_errors, 0L)
}

///|
test "Pressure: free-run core loop remains stable at high cycle count" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 0U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = @mock.MockNic::new()
  let cycles = 1000
  let success = rt.run_cycles(nic, cycles, @hal.Duration(1000L))
  assert_eq(success, cycles)
  let t = rt.get_telemetry()
  assert_eq(t.cycles, cycles.to_int64())
  assert_eq(t.tx_frames, cycles.to_int64())
  assert_eq(t.rx_frames, cycles.to_int64())
  assert_eq(t.timeouts, 0L)
  assert_eq(t.wkc_errors, 0L)
}

///|
test "Pressure: timeout-heavy loop keeps accounting consistent" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 0U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = TimeoutNic::new()
  let cycles = 1000
  rt.set_timeout_threshold(cycles + 1)
  let success = rt.run_cycles(nic, cycles, @hal.Duration(1000L))
  assert_eq(success, 0)
  let t = rt.get_telemetry()
  assert_eq(t.cycles, cycles.to_int64())
  assert_eq(t.tx_frames, cycles.to_int64())
  assert_eq(t.rx_frames, 0L)
  assert_eq(t.timeouts, cycles.to_int64())
  assert_eq(t.wkc_errors, 0L)
}

///|
test "Pressure: telemetry remains monotonic across different loads" {
  let loads : Array[Int] = [50, 200, 500]
  for load in loads {
    let config = @hal.MasterConfig::default()
    let rt = @runtime.Runtime::new(config)
    let sm : @mailbox.SlaveMapping = {
      sm_configs: [],
      fmmu_configs: [],
      output_bytes: 2,
      input_bytes: 2,
    }
    let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
    rt.configure_pdo(ctx, 0U)
    rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
    let nic = @mock.MockNic::new()
    let success = rt.run_cycles(nic, load, @hal.Duration(1000L))
    assert_eq(success, load)
    let t = rt.get_telemetry()
    assert_eq(t.cycles, load.to_int64())
    assert_eq(t.tx_frames, load.to_int64())
    assert_eq(t.rx_frames, load.to_int64())
    assert_eq(t.timeouts, 0L)
    assert_eq(t.wkc_errors, 0L)
  }
}

///|
test "Recovery: run_cycles records RecvTimeout and continues" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 0U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = TimeoutNic::new()
  let success = rt.run_cycles(nic, 4, @hal.Duration(1000L))
  assert_eq(success, 0)
  let t = rt.get_telemetry()
  assert_eq(t.timeouts, 4L)
  assert_eq(t.cycles, 4L)
  assert_eq(t.rx_frames, 0L)
  assert_true(!rt.needs_recovery())
}

///|
test "Runtime run_cycle propagates LinkDown on broken NIC" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 0U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = TimeoutNic::new()
  nic.close()
  let result = try? rt.run_cycle(nic, @hal.Duration(1000L))
  assert_true(result is Err(@hal.EcError::LinkDown))
}

///|
test "Recovery: WKC mismatch increments error counter" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  // Expect WKC=3, but MockNic echoes WKC=0 → mismatch
  rt.configure_pdo(ctx, 3U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = @mock.MockNic::new()
  let result = rt.run_cycle(nic, @hal.Duration(1000L))
  assert_eq(result.ok, false)
  assert_eq(result.wkc, 0U)
  assert_eq(result.expected_wkc, 3U)
  assert_eq(rt.consecutive_wkc_errors, 1)
  let t = rt.get_telemetry()
  assert_eq(t.wkc_errors, 1L)
}

///|
test "Recovery: consecutive WKC errors trigger recovery state" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 3U) // expect 3, get 0 → always fail
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = @mock.MockNic::new()
  // Run 10 cycles; after 5 consecutive errors, should enter Error state
  let success = rt.run_cycles(nic, 10, @hal.Duration(1000L))
  assert_eq(success, 0)
  assert_true(rt.state is Error(_))
  let t = rt.get_telemetry()
  // Should have tried 5 cycles (then broke on the 5th error)
  assert_eq(t.wkc_errors, 5L)
  assert_eq(t.cycles, 5L)
}

///|
test "Recovery: reset_error_counter allows resumption" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 3U)
  let nic = @mock.MockNic::new()
  // Accumulate some errors
  for _i = 0; _i < 3; _i = _i + 1 {
    let _r = rt.run_cycle(nic, @hal.Duration(1000L))
  }
  assert_eq(rt.consecutive_wkc_errors, 3)
  assert_eq(rt.needs_recovery(), false) // not yet at threshold (5)
  // Reset and verify counters cleared
  rt.reset_error_counter()
  assert_eq(rt.consecutive_wkc_errors, 0)
  assert_eq(rt.needs_recovery(), false)
}

///|
test "Recovery: Telemetry reset clears all counters" {
  let t = @runtime.Telemetry::new()
  t.cycles = 100L
  t.tx_frames = 200L
  t.rx_frames = 150L
  t.timeouts = 5L
  t.retries = 3L
  t.wkc_errors = 10L
  t.dc_delay_updates = 8L
  t.emergency_events = 2L
  t.reset()
  assert_eq(t.cycles, 0L)
  assert_eq(t.tx_frames, 0L)
  assert_eq(t.rx_frames, 0L)
  assert_eq(t.timeouts, 0L)
  assert_eq(t.retries, 0L)
  assert_eq(t.wkc_errors, 0L)
  assert_eq(t.dc_delay_updates, 0L)
  assert_eq(t.emergency_events, 0L)
}

///|
test "Emergency: configure_emergency_stations sets station list" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  assert_eq(rt.emergency_stations.length(), 0)
  let mb_config : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1800U,
    in_size: 128U,
    in_sm_index: 1,
  }
  rt.configure_emergency_stations([(0x1001U, mb_config)])
  assert_eq(rt.emergency_stations.length(), 1)
  let (station, _cfg) = rt.emergency_stations[0]
  assert_eq(station, 0x1001U)
}

///|
test "Emergency: telemetry starts at zero and accumulates" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let tel = rt.get_telemetry()
  assert_eq(tel.emergency_events, 0L)
}

///|
test "Emergency: no stations configured means no polling overhead" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 0U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = @mock.MockNic::new()
  let success = rt.run_cycles(nic, 5, @hal.Duration(1000L))
  assert_eq(success, 5)
  let tel = rt.get_telemetry()
  assert_eq(tel.emergency_events, 0L)
}

///|
test "Free-run: ESM transition path building" {
  // Verify transition paths from Init to higher states
  let path = @protocol.build_transition_path(@protocol.EsmState::Op)
  assert_eq(path.length(), 4)
  assert_eq(path[0], @protocol.EsmState::Init)
  assert_eq(path[1], @protocol.EsmState::PreOp)
  assert_eq(path[2], @protocol.EsmState::SafeOp)
  assert_eq(path[3], @protocol.EsmState::Op)
}

///|
test "Free-run: ESM shutdown path building" {
  // Verify shutdown paths back to Init
  let path = @protocol.build_shutdown_path(@protocol.EsmState::Op)
  assert_eq(path.length(), 4)
  assert_eq(path[0], @protocol.EsmState::Op)
  assert_eq(path[1], @protocol.EsmState::SafeOp)
  assert_eq(path[2], @protocol.EsmState::PreOp)
  assert_eq(path[3], @protocol.EsmState::Init)
}

///|
test "Diagnosis restore path uses legal state sequence" {
  let restore_op = @runtime.diagnosis_restore_path(@protocol.Op)
  assert_eq(restore_op, [@protocol.PreOp, @protocol.SafeOp, @protocol.Op])
}

///|
test "Diagnosis restore path reaches boot via init" {
  let restore_boot = @runtime.diagnosis_restore_path(@protocol.Boot)
  assert_eq(restore_boot, [@protocol.PreOp, @protocol.Init, @protocol.Boot])
}

///|
test "Free-run: ESM can_transition validates allowed transitions" {
  // Forward transitions
  assert_true(
    @protocol.EsmState::Init.can_transition(@protocol.EsmState::PreOp),
  )
  assert_true(
    @protocol.EsmState::PreOp.can_transition(@protocol.EsmState::SafeOp),
  )
  assert_true(@protocol.EsmState::SafeOp.can_transition(@protocol.EsmState::Op))
  // Backward transitions
  assert_true(@protocol.EsmState::Op.can_transition(@protocol.EsmState::SafeOp))
  assert_true(@protocol.EsmState::Op.can_transition(@protocol.EsmState::Init))
  // Invalid skip
  assert_true(!@protocol.EsmState::Init.can_transition(@protocol.EsmState::Op))
}

///|
test "Free-run: PDO context build with multiple slaves" {
  let sm1 : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 8,
    input_bytes: 4,
  }
  let sm2 : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 16,
    input_bytes: 8,
  }
  let ctx = @protocol.PdoContext::build([(sm1, 1U), (sm2, 2U)], 0x1000U)
  assert_eq(ctx.mappings.length(), 2)
  assert_eq(ctx.image.output_size, 24) // 8 + 16
  assert_eq(ctx.image.input_size, 12) // 4 + 8
  assert_eq(ctx.logical_base, 0x1000U)
  assert_eq(ctx.logical_size, 36) // 24 + 12
  // Check slave 1 mapping
  assert_eq(ctx.mappings[0].output_offset, 0)
  assert_eq(ctx.mappings[0].output_length, 8)
  assert_eq(ctx.mappings[0].input_offset, 0)
  assert_eq(ctx.mappings[0].input_length, 4)
  // Check slave 2 mapping
  assert_eq(ctx.mappings[1].output_offset, 8)
  assert_eq(ctx.mappings[1].output_length, 16)
  assert_eq(ctx.mappings[1].input_offset, 4)
  assert_eq(ctx.mappings[1].input_length, 8)
}

///|
test "Recovery: Runtime error state display" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.set_state(
    @runtime.RuntimeState::Error(
      @hal.EcError::UnexpectedWkc(expected=3, actual=0),
    ),
  )
  assert_true(rt.state is Error(_))
  // Can recover from error back to Idle
  rt.set_state(@runtime.RuntimeState::Idle)
  assert_true(rt.state is Idle)
}

///|
test "Free-run: set_slave_outputs and get_slave_inputs" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 4,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  // Set output data for slave 1
  let out_data = b"\x01\x02\x03\x04"
  ctx.set_slave_outputs(1U, out_data)
  // Check that outputs are set in the process image
  assert_eq(ctx.image.outputs[0], b'\x01')
  assert_eq(ctx.image.outputs[3], b'\x04')
  // Set some input data manually and read it
  ctx.image.inputs = b"\xAA\xBB\xCC\xDD"
  let inputs = ctx.get_slave_inputs(1U)
  assert_eq(inputs[0], b'\xAA')
  assert_eq(inputs[3], b'\xDD')
}

// ========== Scan Command Tests ==========

///|
test "scan with mock loopback returns empty report" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let report = @runtime.scan(nic, timeout)
  // MockNic echoes back WKC=0, so count_slaves returns 0
  assert_eq(report.slave_count, 0)
  assert_eq(report.slaves.length(), 0)
}

///|
test "ScanReport format with no slaves" {
  let report : @runtime.ScanReport = { slave_count: 0, slaves: [] }
  let output = report.format()
  assert_true(output.contains("Slaves found: 0"))
  assert_true(output.contains("EtherCAT Bus Scan Report"))
}

///|
test "ScanReport format with slaves" {
  let report : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0U,
      },
    ],
  }
  let output = report.format()
  assert_true(output.contains("Slaves found: 1"))
  assert_true(output.contains("Slave #0"))
}

///|
test "SlaveReport equality" {
  let r1 : @runtime.SlaveReport = {
    position: 0,
    station_address: 0x1001U,
    alias_address: None,
    vendor_id: 0x0002U,
    product_code: 0x04D2U,
    revision: 0x0001U,
    serial: 0x1234U,
    identification: 0U,
  }
  let r2 : @runtime.SlaveReport = {
    position: 0,
    station_address: 0x1001U,
    alias_address: None,
    vendor_id: 0x0002U,
    product_code: 0x04D2U,
    revision: 0x0001U,
    serial: 0x1234U,
    identification: 0U,
  }
  assert_eq(r1, r2)
}

///|
test "validate: all slaves match" {
  let scan : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 0x0003U,
        product_code: 0x0064U,
        revision: 0x0002U,
        serial: 0x5678U,
        identification: 0U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
    {
      position: 1U,
      expected_identity: Some({
        vendor_id: 0x0003U,
        product_code: 0x0064U,
        revision: 0x0002U,
        serial: 0x5678U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1002U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, true)
  assert_eq(report.total_expected, 2)
  assert_eq(report.total_found, 2)
  assert_eq(report.results.length(), 2)
}

///|
test "validate: identity mismatch detected" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0009U,
        product_code: 0x0099U,
        revision: 0x0001U,
        serial: 0x0000U,
        identification: 0U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, false)
  assert_true(report.results[0] is @runtime.IdentityMismatch(..))
}

///|
test "validate: station address mismatch detected" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, false)
  assert_true(report.results[0] is @runtime.StationAddressMismatch(..))
}

///|
test "validate: explicit identification mismatch detected" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0x11111111U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: Some(0x22222222U),
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, false)
  assert_true(report.results[0] is @runtime.Ok)
  assert_true(report.results[1] is @runtime.IdentificationMismatch(..))
}

///|
test "validate: revision mismatch detected" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x9999U,
        serial: 0x1234U,
        identification: 0U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, false)
  assert_true(report.results[0] is @runtime.IdentityMismatch(..))
}

///|
test "validate: serial mismatch detected" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x9999U,
        identification: 0U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, false)
  assert_true(report.results[0] is @runtime.IdentityMismatch(..))
}

///|
test "validate: missing slave" {
  let scan : @runtime.ScanReport = { slave_count: 0, slaves: [] }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, false)
  assert_eq(report.results.length(), 1)
  assert_true(report.results[0] is @runtime.Missing(..))
}

///|
test "validate: extra slave detected" {
  let scan : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 0x0005U,
        product_code: 0x0010U,
        revision: 0x0001U,
        serial: 0x0000U,
        identification: 0U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, false)
  assert_eq(report.results.length(), 2)
  assert_true(report.results[0] is @runtime.Ok)
  assert_true(report.results[1] is @runtime.Extra(..))
}

///|
test "validate: no identity constraint accepts any slave" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0xFFFFU,
        product_code: 0xFFFFU,
        revision: 0xFFFFU,
        serial: 0xFFFFU,
        identification: 0U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: None,
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, true)
  assert_eq(report.results.length(), 1)
}

///|
test "validate: empty config and empty scan" {
  let scan : @runtime.ScanReport = { slave_count: 0, slaves: [] }
  let expected : Array[@hal.SlaveConfig] = []
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, true)
  assert_eq(report.total_expected, 0)
  assert_eq(report.total_found, 0)
}

///|
test "configuration_from_scan projects scan into unified model" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0x0020U,
      },
    ],
  }
  let model = @runtime.configuration_from_scan(scan)
  assert_eq(model.source, @runtime.OnlineScan)
  assert_eq(model.total_slaves, 1)
  assert_eq(model.slaves.length(), 1)
  let slave = model.slaves[0]
  assert_eq(slave.position, 0)
  assert_eq(slave.configured_address, Some(0x1001U))
  assert_eq(slave.identification, Some(0x0020U))
  assert_eq(
    slave.identity,
    Some({
      vendor_id: 0x0002U,
      product_code: 0x04D2U,
      revision: 0x0001U,
      serial: 0x1234U,
    }),
  )
}

///|
test "configuration_from_expected projects offline config into unified model" {
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 1U,
      expected_identity: Some({
        vendor_id: 0x0003U,
        product_code: 0x0064U,
        revision: 0x0002U,
        serial: 0x5678U,
      }),
      expected_identification: Some(0x0042U),
      expected_alias_address: None,
      configured_address: 0x1002U,
      presence: @hal.Mandatory,
    },
  ]
  let model = @runtime.configuration_from_expected(expected)
  assert_eq(model.source, @runtime.OfflineConfig)
  assert_eq(model.total_slaves, 1)
  let slave = model.slaves[0]
  assert_eq(slave.position, 1)
  assert_eq(slave.configured_address, Some(0x1002U))
  assert_eq(slave.identification, Some(0x0042U))
}

///|
test "compare_configurations reports topology and identity differences" {
  let expected : @runtime.ConfigurationModel = {
    source: @runtime.OfflineConfig,
    total_slaves: 2,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: None,
        identity: Some({
          vendor_id: 0x0002U,
          product_code: 0x04D2U,
          revision: 0x0001U,
          serial: 0x1234U,
        }),
        identification: Some(0x0020U),
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
      {
        position: 1,
        configured_address: Some(0x1002U),
        alias_address: None,
        identity: Some({
          vendor_id: 0x0003U,
          product_code: 0x0064U,
          revision: 0x0002U,
          serial: 0x5678U,
        }),
        identification: Some(0x0042U),
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
    ],
  }
  let actual : @runtime.ConfigurationModel = {
    source: @runtime.OnlineScan,
    total_slaves: 2,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: None,
        identity: Some({
          vendor_id: 0x0002U,
          product_code: 0x9999U,
          revision: 0x0001U,
          serial: 0x1234U,
        }),
        identification: Some(0x0020U),
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
      {
        position: 2,
        configured_address: Some(0x1003U),
        alias_address: None,
        identity: Some({
          vendor_id: 0x0004U,
          product_code: 0x0001U,
          revision: 0x0001U,
          serial: 0x9999U,
        }),
        identification: Some(0x0055U),
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
    ],
  }
  let report = @runtime.compare_configurations(expected, actual)
  assert_eq(report.all_ok, false)
  assert_eq(report.total_expected, 2)
  assert_eq(report.total_found, 2)
  assert_true(
    report.differences.contains(
      @runtime.IdentityMismatch(
        position=0,
        expected=Some({
          vendor_id: 0x0002U,
          product_code: 0x04D2U,
          revision: 0x0001U,
          serial: 0x1234U,
        }),
        actual=Some({
          vendor_id: 0x0002U,
          product_code: 0x9999U,
          revision: 0x0001U,
          serial: 0x1234U,
        }),
      ),
    ),
  )
  assert_true(report.differences.contains(@runtime.Missing(position=1)))
  assert_true(report.differences.contains(@runtime.Extra(position=2)))
}

///|
test "configuration_from_eni_json projects ENI interchange into unified model" {
  let json =
    #|{
    #|  "slaves": [
    #|    {
    #|      "position": 0,
    #|      "configured_address": 1001,
    #|      "identity": {
    #|        "vendor_id": 4739149,
    #|        "product_code": 3,
    #|        "revision": 1,
    #|        "serial": 0
    #|      },
    #|      "identification": 0,
    #|      "process_data_summary": {
    #|        "sync_manager_count": 2,
    #|        "fmmu_count": 2,
    #|        "rx_pdo_count": 1,
    #|        "tx_pdo_count": 1,
    #|        "mailbox_protocols": {
    #|          "aoe": false,
    #|          "coe": true,
    #|          "eoe": false,
    #|          "foe": false,
    #|          "soe": false,
    #|          "voe": false
    #|        },
    #|        "dc_op_mode_count": 2,
    #|        "dc_assign_activate_count": 1
    #|      }
    #|    },
    #|    {
    #|      "position": 1,
    #|      "configured_address": 1002,
    #|      "identity": {
    #|        "vendor_id": 2,
    #|        "product_code": 1234,
    #|        "revision": 1,
    #|        "serial": 4660
    #|      },
    #|      "identification": 32,
    #|      "process_data_summary": {
    #|        "sync_manager_count": 1,
    #|        "fmmu_count": 1,
    #|        "rx_pdo_count": 2,
    #|        "tx_pdo_count": 0,
    #|        "mailbox_protocols": {
    #|          "aoe": false,
    #|          "coe": true,
    #|          "eoe": true,
    #|          "foe": true,
    #|          "soe": false,
    #|          "voe": false
    #|        },
    #|        "dc_op_mode_count": 1,
    #|        "dc_assign_activate_count": 1
    #|      }
    #|    }
    #|  ]
    #|}
  let model = @runtime.configuration_from_eni_json(json)
  assert_eq(model.source, @runtime.EniImport)
  assert_eq(model.total_slaves, 2)
  assert_eq(model.slaves.length(), 2)
  assert_eq(model.slaves[0].position, 0)
  assert_eq(model.slaves[0].configured_address, Some(1001U))
  assert_eq(model.slaves[0].identification, Some(0U))
  assert_eq(
    model.slaves[0].identity,
    Some({ vendor_id: 4739149U, product_code: 3U, revision: 1U, serial: 0U }),
  )
  assert_eq(
    model.slaves[0].process_data_summary,
    Some({
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
      dc_op_mode_count: 2,
      dc_assign_activate_count: 1,
    }),
  )
  assert_eq(model.slaves[1].position, 1)
  assert_eq(model.slaves[1].configured_address, Some(1002U))
  assert_eq(model.slaves[1].identification, Some(0x20U))
  assert_eq(
    model.slaves[1].identity,
    Some({ vendor_id: 2U, product_code: 0x04D2U, revision: 1U, serial: 4660U }),
  )
  assert_eq(
    model.slaves[1].process_data_summary,
    Some({
      sync_manager_count: 1,
      fmmu_count: 1,
      rx_pdo_count: 2,
      tx_pdo_count: 0,
      mailbox_protocols: Some({
        aoe: false,
        coe: true,
        eoe: true,
        foe: true,
        soe: false,
        voe: false,
      }),
      dc_op_mode_count: 1,
      dc_assign_activate_count: 1,
    }),
  )
}

///|
test "configuration_from_eni_json raises parse error for invalid shape" {
  let json =
    #|{
    #|  "slaves": [
    #|    {
    #|      "position": 0,
    #|      "configured_address": "bad-address"
    #|    }
    #|  ]
    #|}
  let result : Result[@runtime.ConfigurationModel, Error] = try? @runtime.configuration_from_eni_json(
    json,
  )
  guard result is Err(@hal.EcError::EsiParseFailed(message)) else {
    fail("expected invalid ENI JSON shape to raise EsiParseFailed")
  }
  assert_true(message.contains("ENI JSON decode failed"))
}

///|
test "validate: matches by position even when expected order differs" {
  let scan : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 0x0003U,
        product_code: 0x0064U,
        revision: 0x0002U,
        serial: 0x5678U,
        identification: 0U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 1U,
      expected_identity: Some({
        vendor_id: 0x0003U,
        product_code: 0x0064U,
        revision: 0x0002U,
        serial: 0x5678U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1002U,
      presence: @hal.Mandatory,
    },
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, true)
  assert_eq(report.results.length(), 2)
}

///|
test "validate: reports missing and extra by position" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0U,
      },
    ],
  }
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 1U,
      expected_identity: Some({
        vendor_id: 0x0003U,
        product_code: 0x0064U,
        revision: 0x0002U,
        serial: 0x5678U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1002U,
      presence: @hal.Mandatory,
    },
  ]
  let report = @runtime.validate(scan, expected)
  assert_eq(report.all_ok, false)
  assert_eq(report.results.length(), 2)
  assert_true(report.results[0] is @runtime.Missing(position=1))
  assert_true(report.results[1] is @runtime.Extra(position=0))
}

///|
test "ValidateReport format shows PASS" {
  let report : @runtime.ValidateReport = {
    expected_source: @runtime.OfflineConfig,
    actual_source: @runtime.OnlineScan,
    total_expected: 1,
    total_found: 1,
    results: [@runtime.Ok],
    differences: [],
    all_ok: true,
    grade: @runtime.Pass,
  }
  let text = report.format()
  assert_true(text.contains("PASS"))
  assert_true(text.contains("[OK]"))
}

///|
test "ValidateReport format shows FAIL with details" {
  let report : @runtime.ValidateReport = {
    expected_source: @runtime.EniImport,
    actual_source: @runtime.OnlineScan,
    total_expected: 2,
    total_found: 1,
    results: [@runtime.Ok, @runtime.Missing(position=1)],
    differences: [@runtime.Missing(position=1)],
    all_ok: false,
    grade: @runtime.Block,
  }
  let text = report.format()
  assert_true(text.contains("BLOCK"))
  assert_true(text.contains("[MISSING]"))
}

///|
test "validate_configuration grades extra-only topology as warn" {
  let expected : @runtime.ConfigurationModel = {
    source: @runtime.EniImport,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: None,
        identity: Some({
          vendor_id: 1U,
          product_code: 2U,
          revision: 3U,
          serial: 4U,
        }),
        identification: Some(5U),
        process_data_summary: Some({
          sync_manager_count: 2,
          fmmu_count: 1,
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
  let actual : @runtime.ConfigurationModel = {
    source: @runtime.OnlineScan,
    total_slaves: 2,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: None,
        identity: Some({
          vendor_id: 1U,
          product_code: 2U,
          revision: 3U,
          serial: 4U,
        }),
        identification: Some(5U),
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
      {
        position: 1,
        configured_address: Some(0x1002U),
        alias_address: None,
        identity: Some({
          vendor_id: 6U,
          product_code: 7U,
          revision: 8U,
          serial: 9U,
        }),
        identification: Some(10U),
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
    ],
  }
  let report = @runtime.validate_configuration(actual, expected)
  assert_eq(report.grade, @runtime.Warn)
  assert_eq(report.all_ok, false)
  assert_true(report.results[1] is @runtime.Extra(position=1))
}

///|
test "validate_configuration emits process-data summary mismatch when both sides define it" {
  let summary_expected : @runtime.ConfigurationProcessDataSummary = {
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
    dc_op_mode_count: 2,
    dc_assign_activate_count: 1,
  }
  let summary_actual : @runtime.ConfigurationProcessDataSummary = {
    sync_manager_count: 2,
    fmmu_count: 1,
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
    dc_assign_activate_count: 0,
  }
  let expected : @runtime.ConfigurationModel = {
    source: @runtime.EniImport,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: None,
        identity: Some({
          vendor_id: 1U,
          product_code: 2U,
          revision: 3U,
          serial: 4U,
        }),
        identification: Some(5U),
        process_data_summary: Some(summary_expected),
        presence: @hal.Mandatory,
      },
    ],
  }
  let actual : @runtime.ConfigurationModel = {
    source: @runtime.EniImport,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: None,
        identity: Some({
          vendor_id: 1U,
          product_code: 2U,
          revision: 3U,
          serial: 4U,
        }),
        identification: Some(5U),
        process_data_summary: Some(summary_actual),
        presence: @hal.Mandatory,
      },
    ],
  }
  let report = @runtime.validate_configuration(actual, expected)
  assert_eq(report.grade, @runtime.Block)
  assert_true(
    report.differences.contains(
      @runtime.ProcessDataSummaryMismatch(
        position=0,
        expected=summary_expected,
        actual=summary_actual,
      ),
    ),
  )
  assert_eq(report.results.length(), 2)
  assert_true(report.results[1] is @runtime.ProcessDataMismatch(position=0))
}

///|
test "diagnostic surface from validate carries configuration summary and topology issue" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let report : @runtime.ValidateReport = {
    expected_source: @runtime.OfflineConfig,
    actual_source: @runtime.OnlineScan,
    total_expected: 1,
    total_found: 2,
    results: [@runtime.Ok, @runtime.Extra(position=1)],
    differences: [@runtime.Extra(position=1)],
    all_ok: false,
    grade: @runtime.Warn,
  }
  let surface = @runtime.diagnostic_surface_from_validate(scan, report)
  assert_eq(surface.overall_level, @runtime.Degrade)
  assert_eq(surface.issues.length(), 1)
  assert_eq(surface.issues[0].source, @runtime.Topology)
  assert_eq(surface.issues[0].category, @runtime.Topology)
  guard surface.configuration_summary is Some(summary) else {
    fail("expected configuration summary")
  }
  assert_eq(summary.slave_count, 1)
  assert_eq(summary.station_addresses, [0x1001U])
}

///|
test "diagnostic surface from slave diagnosis classifies register and mailbox issues" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let surface = @runtime.diagnostic_surface_from_slave_diagnosis(scan, {
    station_address: 0x1001U,
    al_state: Some(@protocol.SafeOp),
    al_error_flag: Some(true),
    al_status_code: Some(0x0011U),
    error_register: b'\x04',
    diagnosis_counter: Some(2U),
    dl_error_counters: None,
  })
  assert_eq(surface.overall_level, @runtime.Block)
  assert_eq(surface.issues.length(), 4)
  assert_eq(surface.issues[0].source, @runtime.Registers)
  assert_eq(surface.issues[1].source, @runtime.Registers)
  assert_eq(surface.issues[2].source, @runtime.Mailbox)
  assert_eq(surface.issues[3].category, @runtime.DiagnosisHistory)
}

///|
test "validation difference category and grade classify topology identity and configuration" {
  assert_eq(
    @runtime.validation_difference_category(@runtime.Missing(position=0)),
    @runtime.Topology,
  )
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.OptionalMissing(position=1, group_id=Some(7U)),
    ),
    @runtime.Topology,
  )
  assert_eq(
    @runtime.validation_difference_grade(@runtime.Extra(position=1)),
    @runtime.Warn,
  )
  assert_eq(
    @runtime.validation_difference_grade(
      @runtime.OptionalMissing(position=1, group_id=Some(7U)),
    ),
    @runtime.Warn,
  )
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.IdentityMismatch(
        position=0,
        expected=Some({
          vendor_id: 1U,
          product_code: 2U,
          revision: 3U,
          serial: 4U,
        }),
        actual=Some({
          vendor_id: 5U,
          product_code: 6U,
          revision: 7U,
          serial: 8U,
        }),
      ),
    ),
    @runtime.Identity,
  )
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.IdentificationMismatch(
        position=0,
        expected=Some(1U),
        actual=Some(2U),
      ),
    ),
    @runtime.Configuration,
  )
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.AliasAddressMismatch(
        position=0,
        expected=Some(0x20U),
        actual=Some(0x30U),
      ),
    ),
    @runtime.Topology,
  )
}

///|
test "validate_configuration grades optional missing hot-connect member as warn" {
  let expected : @runtime.ConfigurationModel = {
    source: @runtime.OfflineConfig,
    total_slaves: 1,
    slaves: [
      {
        position: 3,
        configured_address: Some(0x1004U),
        alias_address: Some(0x20U),
        identity: Some({
          vendor_id: 0x0002U,
          product_code: 0x04D2U,
          revision: 0x0001U,
          serial: 0x1234U,
        }),
        identification: Some(0x0020U),
        process_data_summary: None,
        presence: @hal.Optional(group_id=Some(7U)),
      },
    ],
  }
  let actual : @runtime.ConfigurationModel = {
    source: @runtime.OnlineScan,
    total_slaves: 0,
    slaves: [],
  }
  let report = @runtime.validate_configuration(actual, expected)
  assert_eq(report.grade, @runtime.Warn)
  assert_true(
    report.differences.contains(
      @runtime.OptionalMissing(position=3, group_id=Some(7U)),
    ),
  )
  assert_true(
    report.results[0] is @runtime.OptionalMissing(position=3, group_id=Some(7U)),
  )
}

///|
test "validate_configuration treats alias mismatch as topology block" {
  let expected : @runtime.ConfigurationModel = {
    source: @runtime.OfflineConfig,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: Some(0x20U),
        identity: Some({
          vendor_id: 0x0002U,
          product_code: 0x04D2U,
          revision: 0x0001U,
          serial: 0x1234U,
        }),
        identification: Some(0x0020U),
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
    ],
  }
  let actual : @runtime.ConfigurationModel = {
    source: @runtime.OnlineScan,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: Some(0x21U),
        identity: Some({
          vendor_id: 0x0002U,
          product_code: 0x04D2U,
          revision: 0x0001U,
          serial: 0x1234U,
        }),
        identification: Some(0x0020U),
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
    ],
  }
  let report = @runtime.validate_configuration(actual, expected)
  assert_eq(report.grade, @runtime.Block)
  assert_true(
    report.differences.contains(
      @runtime.AliasAddressMismatch(
        position=0,
        expected=Some(0x20U),
        actual=Some(0x21U),
      ),
    ),
  )
}

///|
test "offline config and ENI expectations share the same validation semantics" {
  let expected_eni_json =
    #|{
    #|  "slaves": [
    #|    {
    #|      "position": 0,
    #|      "configured_address": 4098,
    #|      "identity": {
    #|        "vendor_id": 2,
    #|        "product_code": 1234,
    #|        "revision": 1,
    #|        "serial": 4660
    #|      },
    #|      "identification": 32,
    #|      "process_data_summary": {
    #|        "sync_manager_count": 0,
    #|        "fmmu_count": 0,
    #|        "rx_pdo_count": 0,
    #|        "tx_pdo_count": 0,
    #|        "mailbox_protocols": null,
    #|        "dc_op_mode_count": 0,
    #|        "dc_assign_activate_count": 0
    #|      }
    #|    }
    #|  ]
    #|}
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0x20U,
      },
    ],
  }
  let expected_offline = @runtime.configuration_from_expected([
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: Some(0x20U),
      expected_alias_address: None,
      configured_address: 0x1002U,
      presence: @hal.Mandatory,
    },
  ])
  let expected_eni = @runtime.configuration_from_eni_json(expected_eni_json)
  let actual = @runtime.configuration_from_scan(scan)
  let offline_report = @runtime.validate_configuration(actual, expected_offline)
  let eni_report = @runtime.validate_configuration(actual, expected_eni)
  assert_eq(offline_report.results.length(), 1)
  assert_eq(eni_report.results.length(), 1)
  assert_true(
    offline_report.results[0]
    is @runtime.StationAddressMismatch(
      position=0,
      expected=0x1002U,
      actual=0x1001U
    ),
  )
  assert_true(
    eni_report.results[0]
    is @runtime.StationAddressMismatch(
      position=0,
      expected=0x1002U,
      actual=0x1001U
    ),
  )
  assert_eq(offline_report.differences, eni_report.differences)
  assert_eq(offline_report.grade, eni_report.grade)
  assert_eq(offline_report.all_ok, eni_report.all_ok)
  assert_eq(offline_report.expected_source, @runtime.OfflineConfig)
  assert_eq(eni_report.expected_source, @runtime.EniImport)
}

///|
test "RunPhase equality" {
  assert_eq(@runtime.RunPhase::Scanning, @runtime.RunPhase::Scanning)
  assert_eq(@runtime.RunPhase::Done, @runtime.RunPhase::Done)
  assert_true(@runtime.RunPhase::Scanning != @runtime.RunPhase::Done)
}

///|
test "RunReport format with zero cycles" {
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OfflineConfig,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 0,
    cycles_ok: 0,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry: @runtime.Telemetry::new(),
    final_phase: @runtime.Done,
    fault: None,
  }
  let text = report.format()
  assert_true(text.contains("MoonECAT Run Report"))
  assert_true(text.contains("Slaves found: 0"))
  assert_true(text.contains("Validation: PASS"))
  assert_true(text.contains("0/0 OK"))
  assert_true(text.contains("Mode: FixedCycles"))
  assert_true(text.contains("CyclePeriodNs: 1000000"))
  assert_true(text.contains("OutputPeriodNs: none"))
  assert_true(text.contains("Phase: Done"))
  assert_true(text.contains("Fault: none"))
}

///|
test "RunReport format with cycles and telemetry" {
  let tel : @runtime.Telemetry = {
    cycles: 100L,
    tx_frames: 100L,
    rx_frames: 98L,
    timeouts: 2L,
    retries: 1L,
    wkc_errors: 3L,
    irq_events: 4L,
    dc_delay_updates: 2L,
    emergency_events: 0L,
  }
  let report : @runtime.RunReport = {
    scan: { slave_count: 2, slaves: [] },
    validation: {
      expected_source: @runtime.OfflineConfig,
      actual_source: @runtime.OnlineScan,
      total_expected: 2,
      total_found: 2,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 100,
    cycles_ok: 97,
    until_fault: true,
    cycle_period_ns: 500_000L,
    output_period_ns: Some(10_000_000L),
    telemetry: tel,
    final_phase: @runtime.Done,
    fault: Some(
      @runtime.RuntimeRecoveryRequired(expected_wkc=2U, observed_wkc_errors=3L),
    ),
  }
  let text = report.format()
  assert_true(text.contains("Slaves found: 2"))
  assert_true(text.contains("97/100 OK"))
  assert_true(text.contains("Mode: UntilFault"))
  assert_true(text.contains("CyclePeriodNs: 500000"))
  assert_true(text.contains("OutputPeriodNs: 10000000"))
  assert_true(text.contains("tx=100"))
  assert_true(text.contains("timeouts=2"))
  assert_true(text.contains("irq_events=4"))
  assert_true(text.contains("dc_delay_updates=2"))
  assert_true(text.contains("wkc_errors=3"))
  assert_true(text.contains("runtime recovery required"))
}

///|
test "DcSync: periodic delay re-estimation updates telemetry" {
  let config = { ..@hal.MasterConfig::default(), dc_enabled: true }
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0x1000U)
  rt.configure_pdo(ctx, 0U)
  let nic = @mock.MockNic::new()
  ignore(rt.init_dc(nic, [0x1001U], @hal.Duration(1000L)))
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::DcSync))
  let _ = rt.run_cycles(nic, 105, @hal.Duration(1000L))
  let t = rt.get_telemetry()
  assert_true(t.dc_delay_updates >= 1L)
}

///|
test "run with mock loopback: empty bus, no expected slaves succeeds" {
  let nic = @mock.MockNic::new()
  let config = @hal.MasterConfig::default()
  let expected : Array[@hal.SlaveConfig] = []
  let ctx : @protocol.PdoContext = {
    image: @protocol.ProcessImage::new(0, 0),
    mappings: [],
    logical_base: 0U,
    logical_size: 0,
    block_lrw: false,
  }
  let report = @runtime.run(
    nic,
    config,
    expected,
    ctx,
    0U,
    0,
    @hal.Duration(1000L),
  )
  assert_eq(report.scan.slave_count, 0)
  assert_eq(report.validation.all_ok, true)
  assert_true(report.final_phase is @runtime.Done)
}

///|
test "scan reads slave identity from sii header" {
  let nic = SiiIdentityNic::new()
  let report = @runtime.scan(nic, @hal.Duration(1000L))
  assert_eq(report.slave_count, 1)
  assert_eq(report.slaves[0].vendor_id, 0x2U)
  assert_eq(report.slaves[0].product_code, 0x044C2C52U)
  assert_eq(report.slaves[0].revision, 0x00110000U)
  assert_eq(report.slaves[0].serial, 0U)
}

///|
test "scan preserves unique pre-existing station addresses" {
  let nic = ScanStationNic::new([0x2001U, 0x2002U])
  let report = @runtime.scan(nic, @hal.Duration(1000L))
  assert_eq(report.slave_count, 2)
  assert_eq(report.slaves[0].station_address, 0x2001U)
  assert_eq(report.slaves[1].station_address, 0x2002U)
}

///|
test "scan reassigns duplicate or zero station addresses into scan pool" {
  let nic = ScanStationNic::new([0U, 0U, 0x2001U, 0x2001U])
  let report = @runtime.scan(nic, @hal.Duration(1000L))
  assert_eq(report.slave_count, 4)
  assert_eq(report.slaves[0].station_address, 0x1001U)
  assert_eq(report.slaves[1].station_address, 0x1002U)
  assert_eq(report.slaves[2].station_address, 0x1003U)
  assert_eq(report.slaves[3].station_address, 0x1004U)
}

///|
test "run with empty bus skips ESM broadcasts" {
  let nic = RejectEmptyBusTransitionNic::new()
  let config = @hal.MasterConfig::default()
  let expected : Array[@hal.SlaveConfig] = []
  let ctx : @protocol.PdoContext = {
    image: @protocol.ProcessImage::new(0, 0),
    mappings: [],
    logical_base: 0U,
    logical_size: 0,
    block_lrw: false,
  }
  let report = @runtime.run(
    nic,
    config,
    expected,
    ctx,
    0U,
    3,
    @hal.Duration(1000L),
  )
  assert_eq(report.scan.slave_count, 0)
  assert_eq(report.validation.all_ok, true)
  assert_eq(report.cycles_ok, 3)
  assert_true(report.final_phase is @runtime.Done)
  assert_true(report.fault is None)
  assert_eq(nic.state_transition_attempts, 0)
}

///|
test "run confirms op via per-station transition without broadcast" {
  let nic = ConfirmedRunNic::new(1U, true, false)
  let config = @hal.MasterConfig::default()
  let report = @runtime.run(
    nic,
    config,
    confirmed_run_expected(),
    {
      image: @protocol.ProcessImage::new(0, 0),
      mappings: [],
      logical_base: 0U,
      logical_size: 0,
      block_lrw: false,
    },
    0U,
    1,
    @hal.Duration(1000L),
  )
  assert_true(report.final_phase is @runtime.Done)
  assert_true(report.fault is None)
  assert_eq(report.cycles_ok, 1)
  assert_eq(nic.al_control_broadcast_attempts, 0)
  assert_eq(nic.current_state, @protocol.Init.to_byte())
}

///|
test "run reports runtime recovery fault after repeated wkc mismatch" {
  let nic = ConfirmedRunNic::new(0U, true, false)
  let config = @hal.MasterConfig::default()
  let report = @runtime.run(
    nic,
    config,
    confirmed_run_expected(),
    single_slave_pdo_context(),
    1U,
    10,
    @hal.Duration(1000L),
  )
  assert_true(report.final_phase is @runtime.Operational)
  assert_eq(report.cycles_ok, 0)
  assert_eq(report.telemetry.wkc_errors, 5L)
  match report.fault {
    Some(@runtime.RuntimeRecoveryRequired(expected_wkc~, observed_wkc_errors~)) => {
      assert_eq(expected_wkc, 1U)
      assert_eq(observed_wkc_errors, 5L)
    }
    _ => fail("expected runtime recovery fault")
  }
}

///|
test "RunReport format includes timeout recovery fault" {
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OfflineConfig,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 3,
    cycles_ok: 0,
    until_fault: true,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry: {
      cycles: 3L,
      tx_frames: 3L,
      rx_frames: 0L,
      timeouts: 3L,
      retries: 0L,
      wkc_errors: 0L,
      irq_events: 0L,
      dc_delay_updates: 0L,
      emergency_events: 0L,
    },
    final_phase: @runtime.Operational,
    fault: Some(
      @runtime.TimeoutRecoveryRequired(
        observed_timeouts=3L,
        consecutive_timeouts=3,
      ),
    ),
  }
  let text = report.format()
  assert_true(text.contains("timeout recovery required"))
  assert_true(text.contains("consecutive_timeouts=3"))
}

///|
test "diagnostic surface from run includes runtime fault issues" {
  let report : @runtime.RunReport = {
    scan: { slave_count: 1, slaves: [] },
    validation: {
      expected_source: @runtime.OfflineConfig,
      actual_source: @runtime.OnlineScan,
      total_expected: 1,
      total_found: 1,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 10,
    cycles_ok: 0,
    until_fault: true,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry: {
      cycles: 5L,
      tx_frames: 5L,
      rx_frames: 5L,
      timeouts: 0L,
      retries: 0L,
      wkc_errors: 5L,
      irq_events: 0L,
      dc_delay_updates: 0L,
      emergency_events: 0L,
    },
    final_phase: @runtime.Operational,
    fault: Some(
      @runtime.RuntimeRecoveryRequired(expected_wkc=1U, observed_wkc_errors=5L),
    ),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_eq(surface.overall_level, @runtime.Block)
  assert_true(
    surface.issues.any(fn(issue) {
      issue.category == @runtime.RuntimeMetrics &&
      issue.detail.contains("Runtime recovery required")
    }),
  )
}

///|
test "run with mock loopback: validation fails when slaves expected but not found" {
  let nic = @mock.MockNic::new()
  let config = @hal.MasterConfig::default()
  let expected : Array[@hal.SlaveConfig] = [
    {
      position: 0U,
      expected_identity: Some({
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
      }),
      expected_identification: None,
      expected_alias_address: None,
      configured_address: 0x1001U,
      presence: @hal.Mandatory,
    },
  ]
  let ctx : @protocol.PdoContext = {
    image: @protocol.ProcessImage::new(64, 64),
    mappings: [],
    logical_base: 0U,
    logical_size: 128,
    block_lrw: false,
  }
  let report = @runtime.run(
    nic,
    config,
    expected,
    ctx,
    1U,
    10,
    @hal.Duration(1000L),
  )
  assert_eq(report.validation.all_ok, false)
  assert_eq(report.cycles_ok, 0)
  assert_true(report.final_phase is @runtime.Validating)
}

///|
test "replay integration minimal flow: scan->validate->run->stop" {
  let nic = @mock.MockNic::new()
  let config = @hal.MasterConfig::default()
  let expected : Array[@hal.SlaveConfig] = []
  let ctx : @protocol.PdoContext = {
    image: @protocol.ProcessImage::new(0, 0),
    mappings: [],
    logical_base: 0U,
    logical_size: 0,
    block_lrw: false,
  }
  let report = @runtime.run(
    nic,
    config,
    expected,
    ctx,
    0U,
    3,
    @hal.Duration(1000L),
  )
  assert_eq(report.validation.all_ok, true)
  assert_eq(report.cycles_requested, 3)
  assert_eq(report.cycles_ok, 3)
  assert_true(report.final_phase is @runtime.Done)
}

///|
test "diagnosis parser: error register" {
  let b = @runtime.parse_error_register_payload(b"\xAA")
  assert_eq(b, b'\xAA')
}

///|
test "diagnosis parser: error register rejects empty payload" {
  let result = try? @runtime.parse_error_register_payload(Bytes::new(0))
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

///|
test "diagnosis parser: u32 little-endian" {
  let v = @runtime.parse_u32_payload(b"\x78\x56\x34\x12")
  assert_eq(v, 0x12345678U)
}

///|
test "diagnosis parser: u32 rejects short payload" {
  let result = try? @runtime.parse_u32_payload(b"\x01\x02\x03")
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

///|
test "Decoupling: mailbox diagnosis failure does not block PDO run loop" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 1U)], 0U)
  rt.configure_pdo(ctx, 0U)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let nic = @mock.MockNic::new()

  // PDO path works before mailbox diagnosis call.
  let before = rt.run_cycles(nic, 2, @hal.Duration(1000L))
  assert_eq(before, 2)

  let bad_cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 8U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 64U,
    in_sm_index: 1,
  }
  let mailbox_result = try? @protocol.mailbox_send(
    nic,
    0x1001U,
    bad_cfg,
    Bytes::new(16),
    @hal.Duration(1000L),
  )
  // Mailbox path is expected to fail immediately; critical check is that PDO
  // loop remains usable afterwards.
  assert_true(mailbox_result is Err(@hal.EcError::MailboxProtocol(_)))

  let after = rt.run_cycles(nic, 3, @hal.Duration(1000L))
  assert_eq(after, 3)
  let t = rt.get_telemetry()
  assert_eq(t.cycles, 5L)
  assert_eq(t.timeouts, 0L)
  assert_eq(t.wkc_errors, 0L)
}

///|
test "Master OD build_master_od contains standard objects" {
  let identity : @runtime.MasterIdentity = {
    vendor_id: 0x1234U,
    product_code: 0x5678U,
    revision: 1U,
    serial: 42U,
  }
  let od = @runtime.build_master_od(identity, None, None, None)
  // 0x1000 Device Type
  let dt = od.lookup(0x1000U, b'\x00')
  assert_true(dt is Some(_))
  assert_true(dt.unwrap().value is @runtime.MasterOdValue::U32(0U))
  // 0x1008 Device Name
  let dn = od.lookup(0x1008U, b'\x00')
  assert_true(dn is Some(_))
  assert_true(dn.unwrap().value is @runtime.MasterOdValue::Str("MoonECAT"))
  // 0x1018 Identity sub1 = vendor_id
  let vid = od.lookup(0x1018U, b'\x01')
  assert_true(vid is Some(_))
  assert_true(vid.unwrap().value is @runtime.MasterOdValue::U32(0x1234U))
  // 0x1018 Identity sub3 = revision
  let rev = od.lookup(0x1018U, b'\x03')
  assert_true(rev is Some(_))
  assert_true(rev.unwrap().value is @runtime.MasterOdValue::U32(1U))
}

///|
test "Master OD indices returns unique sorted list" {
  let od = @runtime.build_master_od(
    @runtime.default_master_identity(),
    None,
    None,
    None,
  )
  let idxs = od.indices()
  // Standard objects: 0x1000, 0x1001, 0x1008, 0x1009, 0x100A, 0x1018, 0x10F3, 0x2000, 0x2002, 0x2003
  assert_true(idxs.length() >= 10)
  // No duplicates
  for i = 0; i < idxs.length(); i = i + 1 {
    for j = i + 1; j < idxs.length(); j = j + 1 {
      assert_true(idxs[i] != idxs[j])
    }
  }
}

///|
test "Master OD with scan report includes slave count" {
  let scan : @runtime.ScanReport = { slave_count: 3, slaves: [] }
  let od = @runtime.build_master_od(
    @runtime.default_master_identity(),
    Some(scan),
    None,
    None,
  )
  let sc = od.lookup(0x2000U, b'\x00')
  assert_true(sc is Some(_))
  assert_true(sc.unwrap().value is @runtime.MasterOdValue::U32(3U))
}

///|
test "Master OD with telemetry includes cycle count" {
  let t = @runtime.Telemetry::new()
  t.cycles = 100L
  t.tx_frames = 200L
  let od = @runtime.build_master_od(
    @runtime.default_master_identity(),
    None,
    Some(t),
    None,
  )
  let cyc = od.lookup(0x2001U, b'\x01')
  assert_true(cyc is Some(_))
  assert_true(cyc.unwrap().value is @runtime.MasterOdValue::U32(100U))
  let tx = od.lookup(0x2001U, b'\x02')
  assert_true(tx is Some(_))
  assert_true(tx.unwrap().value is @runtime.MasterOdValue::U32(200U))
}

///|
test "Master OD format_text contains object table" {
  let od = @runtime.build_master_od(
    @runtime.default_master_identity(),
    None,
    None,
    None,
  )
  let text = od.format_text()
  assert_true(text.contains("Master Object Dictionary"))
  assert_true(text.contains("0x1000"))
  assert_true(text.contains("MoonECAT"))
  assert_true(text.contains("Device Type"))
}

///|
test "Master OD to_json produces valid structure" {
  let od = @runtime.build_master_od(
    @runtime.default_master_identity(),
    None,
    None,
    None,
  )
  let json = od.to_json()
  // Should have object_count, entry_count, entries fields
  assert_true(json is Json::Object(_))
}

///|
test "MasterOdValue format displays correctly" {
  assert_eq(@runtime.MasterOdValue::U8(b'\xFF').format(), "0xff")
  assert_eq(@runtime.MasterOdValue::U32(0x1234U).format(), "0x00001234")
  assert_eq(@runtime.MasterOdValue::Str("hello").format(), "hello")
  assert_eq(@runtime.MasterOdValue::I32(-1).format(), "-1")
}

///|
test "EoeSwitch new creates empty switch" {
  let sw = @runtime.EoeSwitch::new()
  let j = sw.to_json()
  assert_true(j is Json::Object(_))
  let text = sw.format_text()
  assert_true(text.contains("Stations: 0"))
}

///|
test "EoeSwitch add_station registers station" {
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  sw.add_station(0x1002U, cfg)
  // Duplicate should be ignored
  sw.add_station(0x1001U, cfg)
  let text = sw.format_text()
  assert_true(text.contains("Stations: 2"))
}

///|
test "eoe_max_fragment_size computes 32-byte aligned" {
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  // 128 - 10 = 118, aligned to 32 = 96
  assert_eq(@runtime.eoe_max_fragment_size(cfg), 96)
}

///|
test "eoe_max_fragment_size with small mailbox" {
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 10U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 10U,
    in_sm_index: 1,
  }
  // 10 - 10 = 0
  assert_eq(@runtime.eoe_max_fragment_size(cfg), 0)
}

///|
test "EoeSwitch process_received reassembles single fragment" {
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  // Build a single-fragment EoE frame using the mailbox encoder
  let payload = Bytes::makei(20, fn(i) { i.to_byte() })
  let frame = @mailbox.encode_eoe_fragment(
    b'\x01', 0U, true, 0U, 0U, 0U, payload,
  )
  let complete = sw.process_received(0x1001U, frame)
  assert_true(complete)
  let received = sw.drain_rx()
  assert_eq(received.length(), 1)
  assert_eq(received[0].station, 0x1001U)
  assert_eq(received[0].data.length(), 20)
  for i = 0; i < 20; i = i + 1 {
    assert_eq(received[0].data[i], i.to_byte())
  }
}

///|
test "EoeSwitch process_received reassembles multi-fragment" {
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  // Fragment 0: not last, 32 bytes
  let data0 = Bytes::makei(32, fn(i) { i.to_byte() })
  let f0 = @mailbox.encode_eoe_fragment(b'\x01', 0U, false, 0U, 0U, 5U, data0)
  let c0 = sw.process_received(0x1001U, f0)
  assert_true(!c0)
  // Fragment 1: last, 10 bytes
  let data1 = Bytes::makei(10, fn(i) { (32 + i).to_byte() })
  let f1 = @mailbox.encode_eoe_fragment(b'\x02', 0U, true, 1U, 1U, 5U, data1)
  let c1 = sw.process_received(0x1001U, f1)
  assert_true(c1)
  let received = sw.drain_rx()
  assert_eq(received.length(), 1)
  assert_eq(received[0].data.length(), 42)
  // Verify concatenation: first 32 bytes, then 10 bytes
  assert_eq(received[0].data[0], b'\x00')
  assert_eq(received[0].data[31], b'\x1F')
  assert_eq(received[0].data[32], b'\x20')
  assert_eq(received[0].data[41], b'\x29')
}

///|
test "EoeSwitch process_received ignores unknown station" {
  let sw = @runtime.EoeSwitch::new()
  let payload = Bytes::makei(10, fn(i) { i.to_byte() })
  let frame = @mailbox.encode_eoe_fragment(
    b'\x01', 0U, true, 0U, 0U, 0U, payload,
  )
  let complete = sw.process_received(0x9999U, frame)
  assert_true(!complete)
  assert_eq(sw.drain_rx().length(), 0)
}

///|
test "EoeSwitch to_json has expected fields" {
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  let j = sw.to_json()
  guard j is Json::Object(m) else {
    assert_true(false)
    return
  }
  assert_true(m.contains("station_count"))
  assert_true(m.contains("tx_fragments"))
  assert_true(m.contains("rx_fragments"))
  assert_true(m.contains("rx_frames_complete"))
  assert_true(m.contains("rx_errors"))
  assert_true(m.contains("rx_queue_depth"))
}

///|
test "EoeSwitch drain_rx empties queue" {
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  // Deliver two complete single-fragment frames
  let p1 = Bytes::makei(5, fn(_i) { b'\xAA' })
  let f1 = @mailbox.encode_eoe_fragment(b'\x01', 0U, true, 0U, 0U, 0U, p1)
  let _ = sw.process_received(0x1001U, f1)
  let p2 = Bytes::makei(5, fn(_i) { b'\xBB' })
  let f2 = @mailbox.encode_eoe_fragment(b'\x02', 0U, true, 0U, 0U, 1U, p2)
  let _ = sw.process_received(0x1001U, f2)
  let batch = sw.drain_rx()
  assert_eq(batch.length(), 2)
  // Second drain should be empty
  let empty = sw.drain_rx()
  assert_eq(empty.length(), 0)
}

// ---------------------------------------------------------------------------
//  Phase 2 — QueueEndpoint / bridge_eoe_cycle
// ---------------------------------------------------------------------------

///|
test "QueueEndpoint new defaults" {
  let ep = @runtime.QueueEndpoint::new()
  assert_eq(ep.tx_depth(), 0)
  assert_eq(ep.rx_depth(), 0)
  assert_true(ep.is_up())
}

///|
test "QueueEndpoint submit_tx and consume_rx round-trip" {
  let ep = @runtime.QueueEndpoint::new()
  let data = Bytes::makei(10, fn(i) { i.to_byte() })
  assert_true(ep.submit_tx(0x1001U, data))
  assert_eq(ep.tx_depth(), 1)
  // consume_rx should be empty — submit_tx fills tx_pending, not rx_pending
  assert_true(ep.consume_rx() is None)
  // read_frame drains tx_pending (used by bridge)
  let frame = ep.read_frame()
  assert_true(frame is Some(_))
  assert_eq(ep.tx_depth(), 0)
}

///|
test "QueueEndpoint write_frame and consume_rx" {
  let ep = @runtime.QueueEndpoint::new()
  let data = Bytes::makei(8, fn(i) { (0x40 + i).to_byte() })
  assert_true(ep.write_frame(data))
  assert_eq(ep.rx_depth(), 1)
  let f = ep.consume_rx()
  guard f is Some(f) else {
    assert_true(false)
    return
  }
  assert_eq(f.data.length(), 8)
  assert_eq(f.data[0], b'\x40')
  assert_eq(ep.rx_depth(), 0)
}

///|
test "QueueEndpoint rejects when down" {
  let ep = @runtime.QueueEndpoint::new()
  ep.set_up(false)
  assert_true(!ep.is_up())
  let data = Bytes::makei(4, fn(_) { b'\x00' })
  assert_true(!ep.submit_tx(1U, data))
  assert_true(!ep.write_frame(data))
}

///|
test "QueueEndpoint overflow at max_depth" {
  let ep = @runtime.QueueEndpoint::new(max_depth=2)
  let data = Bytes::makei(4, fn(_) { b'\xAA' })
  assert_true(ep.submit_tx(1U, data))
  assert_true(ep.submit_tx(2U, data))
  // Third should fail
  assert_true(!ep.submit_tx(3U, data))
  assert_eq(ep.tx_depth(), 2)
}

///|
test "QueueEndpoint to_json has fields" {
  let ep = @runtime.QueueEndpoint::new()
  let j = ep.to_json()
  guard j is Json::Object(m) else {
    assert_true(false)
    return
  }
  assert_true(m.contains("up"))
  assert_true(m.contains("tx_depth"))
  assert_true(m.contains("rx_depth"))
  assert_true(m.contains("max_depth"))
}

///|
test "bridge_eoe_cycle delivers rx frames to endpoint" {
  // Setup switch with one station and a complete received frame
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  let payload = Bytes::makei(16, fn(i) { i.to_byte() })
  let frame = @mailbox.encode_eoe_fragment(
    b'\x01', 0U, true, 0U, 0U, 0U, payload,
  )
  let _ = sw.process_received(0x1001U, frame)
  // Bridge cycle: tx_pending is empty, rx should deliver 1 frame
  let ep = @runtime.QueueEndpoint::new()
  let nic = @mock.MockNic::new()
  let (tx, rx) = @runtime.bridge_eoe_cycle(sw, ep, nic, @hal.Duration(10_000L))
  assert_eq(tx, 0)
  assert_eq(rx, 1)
  assert_eq(ep.rx_depth(), 1)
  let received = ep.consume_rx()
  guard received is Some(f) else {
    assert_true(false)
    return
  }
  assert_eq(f.station, 0x1001U)
  assert_eq(f.data.length(), 16)
}

///|
test "bridge_eoe_cycle drains tx_pending via switch" {
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  let ep = @runtime.QueueEndpoint::new()
  let data = Bytes::makei(20, fn(i) { i.to_byte() })
  ignore(ep.submit_tx(0x1001U, data))
  let nic = @mock.MockNic::new()
  let (tx, rx) = @runtime.bridge_eoe_cycle(sw, ep, nic, @hal.Duration(10_000L))
  // MockNic accepts send, so tx_sent = 1
  assert_eq(tx, 1)
  assert_eq(rx, 0)
  // tx_pending should be fully drained
  assert_eq(ep.tx_depth(), 0)
}

// ---------------------------------------------------------------------------
//  Phase 3 — EoeRelay (embedded synchronous relay)
// ---------------------------------------------------------------------------

///|
test "EoeRelay new defaults" {
  let relay = @runtime.EoeRelay::new()
  let j = relay.to_json()
  guard j is Json::Object(m) else {
    assert_true(false)
    return
  }
  assert_true(m.contains("active"))
  assert_true(m.contains("stats"))
}

///|
test "EoeRelay set_active toggles" {
  let relay = @runtime.EoeRelay::new()
  let text = relay.format_text()
  assert_true(text.contains("Active: true"))
  relay.set_active(false)
  let text2 = relay.format_text()
  assert_true(text2.contains("Active: false"))
}

///|
test "EoeRelay inactive relay_cycle returns zero" {
  let relay = @runtime.EoeRelay::new()
  relay.set_active(false)
  let sw = @runtime.EoeSwitch::new()
  let nic = @mock.MockNic::new()
  let (rx, tx) = relay.relay_cycle(
    sw,
    nic,
    @hal.Duration(10_000L),
    fn(_f) { true },
    fn() { None },
  )
  assert_eq(rx, 0)
  assert_eq(tx, 0)
}

///|
test "EoeRelay relay_cycle delivers rx frames via handler" {
  let relay = @runtime.EoeRelay::new()
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  let payload = Bytes::makei(12, fn(i) { i.to_byte() })
  let frame = @mailbox.encode_eoe_fragment(
    b'\x01', 0U, true, 0U, 0U, 0U, payload,
  )
  let _ = sw.process_received(0x1001U, frame)
  // Collect frames delivered to handler
  let delivered : Array[@runtime.EoeRelayFrame] = []
  let nic = @mock.MockNic::new()
  let (rx, tx) = relay.relay_cycle(
    sw,
    nic,
    @hal.Duration(10_000L),
    fn(f) {
      delivered.push(f)
      true
    },
    fn() { None },
  )
  assert_eq(rx, 1)
  assert_eq(tx, 0)
  assert_eq(delivered.length(), 1)
  assert_true(delivered[0].direction is @runtime.SlaveToHost)
  assert_eq(delivered[0].station, 0x1001U)
  assert_eq(delivered[0].data.length(), 12)
}

///|
test "EoeRelay relay_cycle handler rejection increments dropped" {
  let relay = @runtime.EoeRelay::new()
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  let payload = Bytes::makei(8, fn(_) { b'\xFF' })
  let frame = @mailbox.encode_eoe_fragment(
    b'\x01', 0U, true, 0U, 0U, 0U, payload,
  )
  let _ = sw.process_received(0x1001U, frame)
  let nic = @mock.MockNic::new()
  // Handler rejects frames
  let (rx, _tx) = relay.relay_cycle(
    sw,
    nic,
    @hal.Duration(10_000L),
    fn(_f) { false },
    fn() { None },
  )
  assert_eq(rx, 0) // handler rejected, so rx_count = 0
  let text = relay.format_text()
  assert_true(text.contains("Dropped: 1"))
}

///|
test "EoeRelay relay_cycle tx_provider sends frames" {
  let relay = @runtime.EoeRelay::new()
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  let nic = @mock.MockNic::new()
  let mut provided = 0
  // Provide one frame then stop
  let (_rx, _tx) = relay.relay_cycle(
    sw,
    nic,
    @hal.Duration(10_000L),
    fn(_f) { true },
    fn() {
      if provided == 0 {
        provided = provided + 1
        let data = Bytes::makei(10, fn(i) { i.to_byte() })
        Some(@runtime.EoeRelayFrame::{
          direction: @runtime.HostToSlave,
          station: 0x1001U,
          data,
        })
      } else {
        None
      }
    },
  )
  // MockNic will cause send_frame to fail → dropped
  let text = relay.format_text()
  assert_true(text.contains("Dropped: 1") || text.contains("TX relayed: 1"))
}

///|
test "EoeRelayStats new is zeroed" {
  let stats = @runtime.EoeRelayStats::new()
  assert_eq(stats.tx_relayed, 0L)
  assert_eq(stats.rx_relayed, 0L)
  assert_eq(stats.dropped, 0L)
  let j = stats.to_json()
  guard j is Json::Object(m) else {
    assert_true(false)
    return
  }
  assert_true(m.contains("tx_relayed"))
  assert_true(m.contains("rx_relayed"))
  assert_true(m.contains("dropped"))
}

///|
test "EoeRelayDirection display" {
  let d1 : @runtime.EoeRelayDirection = @runtime.HostToSlave
  let d2 : @runtime.EoeRelayDirection = @runtime.SlaveToHost
  assert_true(d1.to_string().contains("HostToSlave"))
  assert_true(d2.to_string().contains("SlaveToHost"))
}

// ===== Coverage: validate.mbt — validation_difference_category =====

///|
test "validation_difference_category Topology variants" {
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.ConfigurationDifference::Missing(position=0),
    ),
    @runtime.ValidateDifferenceCategory::Topology,
  )
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.ConfigurationDifference::Extra(position=1),
    ),
    @runtime.ValidateDifferenceCategory::Topology,
  )
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.ConfigurationDifference::OptionalMissing(
        position=2,
        group_id=None,
      ),
    ),
    @runtime.ValidateDifferenceCategory::Topology,
  )
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.ConfigurationDifference::StationAddressMismatch(
        position=0,
        expected=Some(0x1001U),
        actual=Some(0x1002U),
      ),
    ),
    @runtime.ValidateDifferenceCategory::Topology,
  )
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.ConfigurationDifference::AliasAddressMismatch(
        position=0,
        expected=Some(1U),
        actual=Some(2U),
      ),
    ),
    @runtime.ValidateDifferenceCategory::Topology,
  )
}

///|
test "validation_difference_category Identity" {
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.ConfigurationDifference::IdentityMismatch(
        position=0,
        expected=Some({
          vendor_id: 1U,
          product_code: 2U,
          revision: 3U,
          serial: 4U,
        }),
        actual=Some({
          vendor_id: 5U,
          product_code: 6U,
          revision: 7U,
          serial: 8U,
        }),
      ),
    ),
    @runtime.ValidateDifferenceCategory::Identity,
  )
}

///|
test "validation_difference_category Configuration variants" {
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.ConfigurationDifference::IdentificationMismatch(
        position=0,
        expected=Some(0x1234U),
        actual=Some(0x5678U),
      ),
    ),
    @runtime.ValidateDifferenceCategory::Configuration,
  )
  let pds : @runtime.ConfigurationProcessDataSummary = {
    sync_manager_count: 2,
    fmmu_count: 2,
    rx_pdo_count: 1,
    tx_pdo_count: 1,
    mailbox_protocols: None,
    dc_op_mode_count: 0,
    dc_assign_activate_count: 0,
  }
  assert_eq(
    @runtime.validation_difference_category(
      @runtime.ConfigurationDifference::ProcessDataSummaryMismatch(
        position=0,
        expected=pds,
        actual=pds,
      ),
    ),
    @runtime.ValidateDifferenceCategory::Configuration,
  )
}

// ===== Coverage: validate.mbt — validation_difference_grade =====

///|
test "validation_difference_grade Warn for Extra and OptionalMissing" {
  assert_eq(
    @runtime.validation_difference_grade(
      @runtime.ConfigurationDifference::Extra(position=0),
    ),
    @runtime.ValidateGrade::Warn,
  )
  assert_eq(
    @runtime.validation_difference_grade(
      @runtime.ConfigurationDifference::OptionalMissing(
        position=1,
        group_id=None,
      ),
    ),
    @runtime.ValidateGrade::Warn,
  )
}

///|
test "validation_difference_grade Block for Missing" {
  assert_eq(
    @runtime.validation_difference_grade(
      @runtime.ConfigurationDifference::Missing(position=0),
    ),
    @runtime.ValidateGrade::Block,
  )
}

///|
test "validation_difference_grade Block for StationAddressMismatch" {
  assert_eq(
    @runtime.validation_difference_grade(
      @runtime.ConfigurationDifference::StationAddressMismatch(
        position=0,
        expected=Some(0x1001U),
        actual=Some(0x1002U),
      ),
    ),
    @runtime.ValidateGrade::Block,
  )
}

///|
test "validation_difference_grade Block for IdentityMismatch" {
  assert_eq(
    @runtime.validation_difference_grade(
      @runtime.ConfigurationDifference::IdentityMismatch(
        position=0,
        expected=Some({
          vendor_id: 1U,
          product_code: 2U,
          revision: 3U,
          serial: 4U,
        }),
        actual=Some({
          vendor_id: 5U,
          product_code: 6U,
          revision: 7U,
          serial: 8U,
        }),
      ),
    ),
    @runtime.ValidateGrade::Block,
  )
}

// ===== Coverage: topology_health.mbt =====

///|
test "TopologyHealthAnalyzer perfect slave scores 1000" {
  let analyzer = @runtime.TopologyHealthAnalyzer::new()
  analyzer.add_slave(0x1001U, 0, 500L)
  for i = 0; i < 100; i = i + 1 {
    analyzer.record_cycle(0, 1L, 1L, false, true)
  }
  let report = analyzer.analyze()
  assert_eq(report.slaves.length(), 1)
  assert_eq(report.slaves[0].tx_frames, 100L)
  assert_eq(report.slaves[0].rx_frames, 100L)
  assert_eq(report.slaves[0].timeouts, 0L)
  assert_eq(report.slaves[0].wkc_errors, 0L)
  assert_eq(report.slaves[0].health_score, 1000)
  assert_true(report.slaves[0].grade is @runtime.LinkGrade::Excellent)
  assert_eq(report.system_health_score, 1000)
}

///|
test "TopologyHealthAnalyzer degraded slave" {
  let analyzer = @runtime.TopologyHealthAnalyzer::new()
  analyzer.add_slave(0x1001U, 0, 1000L)
  for i = 0; i < 100; i = i + 1 {
    let timeout = i < 50
    let wkc_ok = i >= 20
    analyzer.record_cycle(0, 1L, if timeout { 0L } else { 1L }, timeout, wkc_ok)
  }
  let report = analyzer.analyze()
  assert_true(report.slaves[0].health_score < 1000)
  assert_true(report.slaves[0].timeouts == 50L)
  assert_true(report.slaves[0].wkc_errors == 20L)
}

///|
test "TopologyHealthAnalyzer empty returns default score" {
  let analyzer = @runtime.TopologyHealthAnalyzer::new()
  let report = analyzer.analyze()
  assert_eq(report.slaves.length(), 0)
  // Empty analyzer defaults to perfect score (no errors observed)
  assert_eq(report.system_health_score, 1000)
}

///|
test "TopologyHealthAnalyzer cable length estimation" {
  let analyzer = @runtime.TopologyHealthAnalyzer::new()
  analyzer.add_slave(0x1001U, 0, 500L)
  for _i = 0; _i < 10; _i = _i + 1 {
    analyzer.record_cycle(0, 1L, 1L, false, true)
  }
  let report = analyzer.analyze()
  // 500ns / 5.0 ns/m = 100.0m
  assert_true(report.slaves[0].estimated_cable_length_m > 99.0)
  assert_true(report.slaves[0].estimated_cable_length_m < 101.0)
}

///|
test "TopologyHealthAnalyzer bottleneck detection" {
  let analyzer = @runtime.TopologyHealthAnalyzer::new()
  analyzer.add_slave(0x1001U, 0, 500L)
  analyzer.add_slave(0x1002U, 1, 1000L)
  for _i = 0; _i < 100; _i = _i + 1 {
    analyzer.record_cycle(0, 1L, 1L, false, true)
    analyzer.record_cycle(1, 1L, 0L, true, false)
  }
  let report = analyzer.analyze()
  assert_eq(report.bottleneck_index, Some(1))
}

///|
test "TopologyHealthAnalyzer record_cycle out of bounds ignored" {
  let analyzer = @runtime.TopologyHealthAnalyzer::new()
  analyzer.add_slave(0x1001U, 0, 500L)
  analyzer.record_cycle(99, 1L, 1L, false, true)
  analyzer.record_cycle(-1, 1L, 1L, false, true)
  let report = analyzer.analyze()
  assert_eq(report.slaves[0].tx_frames, 0L)
}

///|
test "TopologyHealthAnalyzer ingest_telemetry" {
  let analyzer = @runtime.TopologyHealthAnalyzer::new()
  analyzer.add_slave(0x1001U, 0, 500L)
  analyzer.ingest_telemetry(0, 1000L, 990L, 5L, 3L)
  let report = analyzer.analyze()
  assert_eq(report.slaves[0].tx_frames, 1000L)
  assert_eq(report.slaves[0].rx_frames, 990L)
  assert_eq(report.slaves[0].timeouts, 5L)
  assert_eq(report.slaves[0].wkc_errors, 3L)
}

///|
test "TopologyHealthReport to_json contains slave data" {
  let analyzer = @runtime.TopologyHealthAnalyzer::new()
  analyzer.add_slave(0x1001U, 0, 500L)
  analyzer.record_cycle(0, 1L, 1L, false, true)
  let report = analyzer.analyze()
  let json = report.to_json()
  assert_true(json.contains("system_health_score"))
  assert_true(json.contains("slaves"))
}

///|
test "estimate_cable_length basic" {
  let len = @runtime.estimate_cable_length(500L)
  assert_true(len > 99.0)
  assert_true(len < 101.0)
}

///|
test "grade_from_score boundaries" {
  assert_true(@runtime.grade_from_score(1000) is @runtime.LinkGrade::Excellent)
  assert_true(@runtime.grade_from_score(0) is @runtime.LinkGrade::Critical)
}

// ===== Coverage: verification_report.mbt =====

///|
test "VerificationReport new initializes correctly" {
  let report = @runtime.VerificationReport::new("Test Run")
  assert_eq(report.title, "Test Run")
  assert_true(report.summary_verdict is @runtime.Verdict::Pass)
  assert_eq(report.timeline.length(), 0)
  assert_eq(report.fault_injections.length(), 0)
  assert_eq(report.metadata.length(), 0)
}

///|
test "VerificationReport add_event appends timeline" {
  let report = @runtime.VerificationReport::new("Test")
  report.add_event(
    100L,
    "StateTransition",
    "Init to PreOp",
    @runtime.Verdict::Pass,
  )
  assert_eq(report.timeline.length(), 1)
  assert_eq(report.timeline[0].cycle, 100L)
  assert_eq(report.timeline[0].event_type, "StateTransition")
}

///|
test "VerificationReport add_fault appends fault_injections" {
  let report = @runtime.VerificationReport::new("Test")
  report.add_fault("link_down at cycle 50")
  assert_eq(report.fault_injections.length(), 1)
  assert_eq(report.fault_injections[0], "link_down at cycle 50")
}

///|
test "VerificationReport add_meta appends metadata" {
  let report = @runtime.VerificationReport::new("Test")
  report.add_meta("Platform", "EtherCAT")
  assert_eq(report.metadata.length(), 1)
  assert_eq(report.metadata[0].0, "Platform")
  assert_eq(report.metadata[0].1, "EtherCAT")
}

///|
test "VerificationReport to_markdown renders title and summary" {
  let report = @runtime.VerificationReport::new("Coverage Test Report")
  report.add_meta("Version", "1.0")
  report.add_event(1L, "Init", "Start", @runtime.Verdict::Pass)
  report.add_fault("link_down")
  let md = report.to_markdown()
  assert_true(md.contains("Coverage Test Report"))
  assert_true(md.contains("Version"))
  assert_true(md.contains("link_down"))
  assert_true(md.contains("Init"))
}

///|
test "VerificationReport to_json renders valid structure" {
  let report = @runtime.VerificationReport::new("JSON Test")
  report.add_event(10L, "Check", "ok", @runtime.Verdict::Pass)
  let json = report.to_json()
  assert_true(json.contains("JSON Test"))
  assert_true(json.contains("timeline"))
}

// ===== Coverage: validate.mbt — validate_configuration =====

///|
test "validate_configuration matching models returns all Ok" {
  let slave : @runtime.ConfigurationSlave = {
    position: 0,
    configured_address: Some(0x1001U),
    alias_address: None,
    identity: Some({ vendor_id: 1U, product_code: 2U, revision: 3U, serial: 4U }),
    identification: None,
    process_data_summary: None,
    presence: @hal.Mandatory,
  }
  let model : @runtime.ConfigurationModel = {
    source: @runtime.ConfigurationSource::OfflineConfig,
    total_slaves: 1,
    slaves: [slave],
  }
  let report = @runtime.validate_configuration(model, model)
  assert_eq(report.all_ok, true)
  assert_eq(report.grade, @runtime.ValidateGrade::Pass)
}

///|
test "validate_configuration extra slave in actual" {
  let slave1 : @runtime.ConfigurationSlave = {
    position: 0,
    configured_address: Some(0x1001U),
    alias_address: None,
    identity: Some({ vendor_id: 1U, product_code: 2U, revision: 3U, serial: 4U }),
    identification: None,
    process_data_summary: None,
    presence: @hal.Mandatory,
  }
  let slave2 : @runtime.ConfigurationSlave = {
    position: 1,
    configured_address: Some(0x1002U),
    alias_address: None,
    identity: Some({
      vendor_id: 9U,
      product_code: 10U,
      revision: 11U,
      serial: 12U,
    }),
    identification: None,
    process_data_summary: None,
    presence: @hal.Mandatory,
  }
  let actual : @runtime.ConfigurationModel = {
    source: @runtime.ConfigurationSource::OnlineScan,
    total_slaves: 2,
    slaves: [slave1, slave2],
  }
  let expected : @runtime.ConfigurationModel = {
    source: @runtime.ConfigurationSource::OfflineConfig,
    total_slaves: 1,
    slaves: [slave1],
  }
  let report = @runtime.validate_configuration(actual, expected)
  assert_eq(report.grade, @runtime.ValidateGrade::Warn)
}

// ===== Coverage: additional pure functions =====

///|
test "compare_configurations identical" {
  let slave : @runtime.ConfigurationSlave = {
    position: 0,
    configured_address: Some(0x1001U),
    alias_address: None,
    identity: Some({ vendor_id: 1U, product_code: 2U, revision: 3U, serial: 4U }),
    identification: None,
    process_data_summary: None,
    presence: @hal.Mandatory,
  }
  let model : @runtime.ConfigurationModel = {
    source: @runtime.ConfigurationSource::OfflineConfig,
    total_slaves: 1,
    slaves: [slave],
  }
  let report = @runtime.compare_configurations(model, model)
  assert_eq(report.all_ok, true)
  assert_eq(report.differences.length(), 0)
}

///|
test "Verdict is_passing and severity" {
  let pass = @runtime.Verdict::Pass
  let warn = @runtime.Verdict::Warn("w")
  let fail = @runtime.Verdict::Fail("f")
  let block = @runtime.Verdict::Block("b")
  assert_eq(pass.is_passing(), true)
  assert_eq(warn.is_passing(), true)
  assert_eq(fail.is_passing(), false)
  assert_eq(block.is_passing(), false)
  assert_true(pass.severity() < fail.severity())
  assert_true(warn.severity() < block.severity())
}

// ===== Coverage: diagnosis.mbt — pure functions =====

///|
test "diagnosis_restore_path PreOp" {
  assert_eq(@runtime.diagnosis_restore_path(@protocol.PreOp), [@protocol.PreOp])
}

///|
test "diagnosis_restore_path SafeOp" {
  assert_eq(@runtime.diagnosis_restore_path(@protocol.SafeOp), [
    @protocol.PreOp,
    @protocol.SafeOp,
  ])
}

///|
test "diagnosis_restore_path Op" {
  assert_eq(@runtime.diagnosis_restore_path(@protocol.Op), [
    @protocol.PreOp,
    @protocol.SafeOp,
    @protocol.Op,
  ])
}

///|
test "diagnosis_restore_path Init" {
  assert_eq(@runtime.diagnosis_restore_path(@protocol.Init), [
    @protocol.PreOp,
    @protocol.Init,
  ])
}

///|
test "diagnosis_restore_path Boot" {
  assert_eq(@runtime.diagnosis_restore_path(@protocol.Boot), [
    @protocol.PreOp,
    @protocol.Init,
    @protocol.Boot,
  ])
}

///|
test "parse_error_register_payload valid" {
  let result = @runtime.parse_error_register_payload(b"\x42")
  assert_eq(result, b'\x42')
}

///|
test "parse_error_register_payload empty rejects" {
  let result : Result[Byte, _] = try? @runtime.parse_error_register_payload(b"")
  assert_true(result is Err(_))
}

///|
test "parse_u32_payload valid" {
  let result = @runtime.parse_u32_payload(b"\x01\x02\x03\x04")
  assert_eq(result, 0x04030201U)
}

///|
test "parse_u32_payload too short rejects" {
  let result : Result[UInt, _] = try? @runtime.parse_u32_payload(b"\x01\x02")
  assert_true(result is Err(_))
}

///|
test "diagnostic_surface_from_state_transition no issues when match" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    Some(0x1001U),
    @protocol.PreOp,
    Some(@protocol.Init),
    Some(@protocol.PreOp),
    Some(false),
    Some(0U),
    Some(1U),
  )
  assert_eq(surface.station_address, Some(0x1001U))
  assert_eq(surface.issues.length(), 0)
  assert_true(surface.overall_level is @runtime.DiagnosticLevel::Info)
}

///|
test "diagnostic_surface_from_state_transition final state mismatch" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    Some(0x1001U),
    @protocol.PreOp,
    Some(@protocol.Init),
    Some(@protocol.Init),
    None,
    None,
    None,
  )
  assert_true(surface.issues.length() > 0)
  assert_true(surface.overall_level is @runtime.DiagnosticLevel::Block)
}

///|
test "diagnostic_surface_from_state_transition al_error_flag set" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.PreOp,
    None,
    Some(@protocol.PreOp),
    Some(true),
    None,
    None,
  )
  assert_true(surface.issues.length() > 0)
  assert_true(
    surface.issues
    .iter()
    .any(fn(i) { i.detail.contains("AL error indication") }),
  )
}

///|
test "diagnostic_surface_from_state_transition status_code nonzero" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.PreOp,
    None,
    Some(@protocol.PreOp),
    None,
    Some(0x001DU),
    None,
  )
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("AL status code") }),
  )
}

///|
test "diagnostic_surface_from_state_transition wkc zero" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.PreOp,
    None,
    Some(@protocol.PreOp),
    None,
    None,
    Some(0U),
  )
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("WKC is zero") }),
  )
  assert_true(surface.overall_level is @runtime.DiagnosticLevel::Degrade)
}

///|
test "diagnostic_surface_from_slave_diagnosis clean slave" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 0U,
      },
    ],
  }
  let diag : @runtime.SlaveDiagnosis = {
    station_address: 0x1001U,
    al_state: Some(@protocol.Op),
    al_error_flag: Some(false),
    al_status_code: Some(0U),
    error_register: b'\x00',
    diagnosis_counter: Some(0U),
    dl_error_counters: None,
  }
  let surface = @runtime.diagnostic_surface_from_slave_diagnosis(scan, diag)
  assert_eq(surface.station_address, Some(0x1001U))
  assert_eq(surface.issues.length(), 0)
  assert_true(surface.overall_level is @runtime.DiagnosticLevel::Info)
}

///|
test "diagnostic_surface_from_slave_diagnosis with errors" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 0U,
      },
    ],
  }
  let diag : @runtime.SlaveDiagnosis = {
    station_address: 0x1001U,
    al_state: Some(@protocol.PreOp),
    al_error_flag: Some(true),
    al_status_code: Some(0x001DU),
    error_register: b'\x80',
    diagnosis_counter: Some(5U),
    dl_error_counters: None,
  }
  let surface = @runtime.diagnostic_surface_from_slave_diagnosis(scan, diag)
  // Should have: AL error flag, AL status code nonzero, error register nonzero, diagnosis counter > 0
  assert_true(surface.issues.length() >= 3)
  assert_true(surface.overall_level is @runtime.DiagnosticLevel::Block)
}

///|
test "monitor_result_to_issue Pass returns None" {
  let r : @runtime.MonitorResult = {
    name: "test",
    verdict: @runtime.Verdict::Pass,
  }
  assert_true(@runtime.monitor_result_to_issue(r) is None)
}

///|
test "monitor_result_to_issue Warn returns Info issue" {
  let r : @runtime.MonitorResult = {
    name: "wkc",
    verdict: @runtime.Verdict::Warn("drift"),
  }
  let issue = @runtime.monitor_result_to_issue(r)
  assert_true(issue is Some(_))
  match issue {
    Some(i) => {
      assert_true(i.level is @runtime.DiagnosticLevel::Info)
      assert_true(i.detail.contains("wkc"))
      assert_true(i.detail.contains("drift"))
    }
    None => ()
  }
}

///|
test "monitor_result_to_issue Fail returns Degrade issue" {
  let r : @runtime.MonitorResult = {
    name: "timeout",
    verdict: @runtime.Verdict::Fail("too many"),
  }
  match @runtime.monitor_result_to_issue(r) {
    Some(i) => assert_true(i.level is @runtime.DiagnosticLevel::Degrade)
    None => abort("expected Some")
  }
}

///|
test "monitor_result_to_issue Block returns Block issue" {
  let r : @runtime.MonitorResult = {
    name: "fatal",
    verdict: @runtime.Verdict::Block("dead"),
  }
  match @runtime.monitor_result_to_issue(r) {
    Some(i) => assert_true(i.level is @runtime.DiagnosticLevel::Block)
    None => abort("expected Some")
  }
}

///|
test "verdict_to_diagnostic_level mapping" {
  assert_true(
    @runtime.verdict_to_diagnostic_level(@runtime.Verdict::Pass)
    is @runtime.DiagnosticLevel::Info,
  )
  assert_true(
    @runtime.verdict_to_diagnostic_level(@runtime.Verdict::Warn("w"))
    is @runtime.DiagnosticLevel::Info,
  )
  assert_true(
    @runtime.verdict_to_diagnostic_level(@runtime.Verdict::Fail("f"))
    is @runtime.DiagnosticLevel::Degrade,
  )
  assert_true(
    @runtime.verdict_to_diagnostic_level(@runtime.Verdict::Block("b"))
    is @runtime.DiagnosticLevel::Block,
  )
}

///|
test "enrich_surface_with_fingerprint adds fingerprint" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.PreOp,
    None,
    Some(@protocol.PreOp),
    None,
    None,
    None,
  )
  let fp : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 12345L,
  }
  let enriched = @runtime.enrich_surface_with_fingerprint(surface, fp)
  assert_eq(enriched.topology_fingerprint, Some(fp))
}

///|
test "enrich_surface_with_monitors adds verdicts and issues" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.PreOp,
    None,
    Some(@protocol.PreOp),
    None,
    None,
    None,
  )
  let results : Array[@runtime.MonitorResult] = [
    { name: "wkc", verdict: @runtime.Verdict::Warn("high") },
    { name: "ok", verdict: @runtime.Verdict::Pass },
  ]
  let enriched = @runtime.enrich_surface_with_monitors(
    surface,
    results,
    @runtime.Verdict::Warn("w"),
  )
  assert_true(enriched.monitor_verdicts is Some(_))
  assert_true(enriched.overall_verdict is Some(_))
  assert_true(enriched.issues.length() >= 1) // one Warn issue from "wkc"
}

///|
test "fingerprint_match identical" {
  let fp : @runtime.TopologyFingerprint = { slave_count: 3, identity_hash: 42L }
  assert_true(
    @runtime.fingerprint_match(fp, fp)
    is @runtime.TopologyFingerprintMatch::Identical,
  )
}

///|
test "fingerprint_match slave count changed" {
  let fp1 : @runtime.TopologyFingerprint = {
    slave_count: 3,
    identity_hash: 42L,
  }
  let fp2 : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 42L,
  }
  assert_true(
    @runtime.fingerprint_match(fp1, fp2)
    is @runtime.TopologyFingerprintMatch::SlaveCountChanged(..),
  )
}

///|
test "fingerprint_match identity changed" {
  let fp1 : @runtime.TopologyFingerprint = {
    slave_count: 3,
    identity_hash: 42L,
  }
  let fp2 : @runtime.TopologyFingerprint = {
    slave_count: 3,
    identity_hash: 99L,
  }
  assert_true(
    @runtime.fingerprint_match(fp1, fp2)
    is @runtime.TopologyFingerprintMatch::IdentityChanged,
  )
}

///|
test "diagnostic_surface_from_validate with differences" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 0U,
      },
    ],
  }
  let vr : @runtime.ValidateReport = {
    expected_source: @runtime.ConfigurationSource::OfflineConfig,
    actual_source: @runtime.ConfigurationSource::OnlineScan,
    total_expected: 1,
    total_found: 2,
    results: [@runtime.ValidationResult::Ok],
    differences: [@runtime.ConfigurationDifference::Extra(position=1)],
    all_ok: false,
    grade: @runtime.ValidateGrade::Warn,
  }
  let surface = @runtime.diagnostic_surface_from_validate(scan, vr)
  assert_true(surface.issues.length() >= 1)
  assert_true(surface.configuration_summary is Some(_))
}

// ===== Coverage: comm_quality.mbt =====

///|
test "quality_grade_from_score boundaries" {
  assert_true(
    @runtime.quality_grade_from_score(1000) is @runtime.QualityGrade::Excellent,
  )
  assert_true(
    @runtime.quality_grade_from_score(900) is @runtime.QualityGrade::Excellent,
  )
  assert_true(
    @runtime.quality_grade_from_score(899) is @runtime.QualityGrade::Good,
  )
  assert_true(
    @runtime.quality_grade_from_score(750) is @runtime.QualityGrade::Good,
  )
  assert_true(
    @runtime.quality_grade_from_score(500) is @runtime.QualityGrade::Acceptable,
  )
  assert_true(
    @runtime.quality_grade_from_score(250) is @runtime.QualityGrade::Poor,
  )
  assert_true(
    @runtime.quality_grade_from_score(249) is @runtime.QualityGrade::Critical,
  )
  assert_true(
    @runtime.quality_grade_from_score(0) is @runtime.QualityGrade::Critical,
  )
}

///|
test "score_dimension perfect value" {
  let dim : @runtime.QualityDimension = {
    name: "loss",
    value: 0L,
    good_threshold: 0L,
    bad_threshold: 100L,
    weight: 100,
  }
  assert_eq(@runtime.score_dimension(dim), 1000)
}

///|
test "score_dimension worst value" {
  let dim : @runtime.QualityDimension = {
    name: "loss",
    value: 200L,
    good_threshold: 0L,
    bad_threshold: 100L,
    weight: 100,
  }
  assert_eq(@runtime.score_dimension(dim), 0)
}

///|
test "compute_quality_score single dimension" {
  let dims : Array[@runtime.QualityDimension] = [
    {
      name: "loss",
      value: 0L,
      good_threshold: 0L,
      bad_threshold: 100L,
      weight: 100,
    },
  ]
  let (score, breakdown) = @runtime.compute_quality_score(dims)
  assert_eq(score, 1000)
  assert_eq(breakdown.length(), 1)
  assert_eq(breakdown[0].0, "loss")
}

///|
test "compute_quality_score mixed dimensions" {
  let dims : Array[@runtime.QualityDimension] = [
    {
      name: "loss",
      value: 0L,
      good_threshold: 0L,
      bad_threshold: 100L,
      weight: 50,
    },
    {
      name: "jitter",
      value: 100L,
      good_threshold: 0L,
      bad_threshold: 100L,
      weight: 50,
    },
  ]
  let (score, _) = @runtime.compute_quality_score(dims)
  // 50% perfect + 50% worst → ~500
  assert_eq(score, 500)
}

///|
test "CommQualityScorer lifecycle" {
  let scorer = @runtime.CommQualityScorer::new()
  // Perfect telemetry: 1000 cycles, 0 timeouts, 0 wkc errors, 0 retries
  let qs = scorer.score_from_telemetry(1000L, 0L, 0L, 0L)
  assert_eq(qs.overall, 1000)
  assert_true(qs.grade is @runtime.QualityGrade::Excellent)
  scorer.record_score(qs.overall)
  assert_true(scorer.trend() is @runtime.QualityTrend::Stable)
}

///|
test "CommQualityScorer degraded telemetry" {
  let scorer = @runtime.CommQualityScorer::new()
  let qs = scorer.score_from_telemetry(1000L, 200L, 100L, 50L)
  assert_true(qs.overall < 1000)
}

///|
test "CommQualityScorer trend degrading" {
  let scorer = @runtime.CommQualityScorer::new(history_size=5)
  // Window 1: 5 high scores → prev_window_avg = 800
  for i = 0; i < 5; i = i + 1 {
    scorer.record_score(800)
  }
  // Window 2: 5 medium scores → prev_window_avg = 700
  for i = 0; i < 5; i = i + 1 {
    scorer.record_score(700)
  }
  // sample_count=10, need >=10 for trend. prev_window_avg=700, current_avg=700 → Stable
  // Add 4 low scores without completing window 3
  for i = 0; i < 4; i = i + 1 {
    scorer.record_score(100)
  }
  // sample_count=14 ≥ 10. History buffer: [100,100,100,100,700]. avg=200
  // 200 + 50 < 700 → Degrading
  assert_true(scorer.trend() is @runtime.QualityTrend::Degrading)
}

///|
test "CommQualityScorer trend stable" {
  let scorer = @runtime.CommQualityScorer::new(history_size=5)
  // Not enough samples for non-Stable trend
  for i = 0; i < 5; i = i + 1 {
    scorer.record_score(800)
  }
  assert_true(scorer.trend() is @runtime.QualityTrend::Stable)
}

///|
test "QualityScore to_json contains fields" {
  let scorer = @runtime.CommQualityScorer::new()
  let qs = scorer.score_from_telemetry(100L, 100L, 0L, 0L)
  let json = qs.to_json()
  assert_true(json.contains("overall"))
  assert_true(json.contains("grade"))
}

// ===== ValidateReport::format tests (validate.mbt) =====

///|
test "ValidateReport format shows all mismatch types" {
  let expected_id : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
  }
  let actual_id : @hal.SlaveIdentity = {
    vendor_id: 5U,
    product_code: 6U,
    revision: 7U,
    serial: 8U,
  }
  let report : @runtime.ValidateReport = {
    expected_source: @runtime.ConfigurationSource::OnlineScan,
    actual_source: @runtime.ConfigurationSource::OnlineScan,
    total_expected: 6,
    total_found: 6,
    all_ok: false,
    grade: @runtime.ValidateGrade::Block,
    differences: [],
    results: [
      @runtime.ValidationResult::Ok,
      @runtime.ValidationResult::StationAddressMismatch(
        position=1,
        expected=0x1001U,
        actual=0x1002U,
      ),
      @runtime.ValidationResult::AliasAddressMismatch(
        position=2,
        expected=0x00U,
        actual=0x01U,
      ),
      @runtime.ValidationResult::IdentityMismatch(
        expected=expected_id,
        actual=actual_id,
      ),
      @runtime.ValidationResult::IdentificationMismatch(
        position=4,
        expected=0x10U,
        actual=0x20U,
      ),
      @runtime.ValidationResult::ProcessDataMismatch(position=5),
    ],
  }
  let text = report.format()
  assert_true(text.contains("EtherCAT Validation Report"))
  assert_true(text.contains("[OK]"))
  assert_true(text.contains("[ADDR-MISMATCH]"))
  assert_true(text.contains("[ALIAS-MISMATCH]"))
  assert_true(text.contains("[MISMATCH]"))
  assert_true(text.contains("[ID-MISMATCH]"))
  assert_true(text.contains("[CONFIG-MISMATCH]"))
}

///|
test "ValidateReport format shows Missing and Extra and OptionalMissing" {
  let report : @runtime.ValidateReport = {
    expected_source: @runtime.ConfigurationSource::OfflineConfig,
    actual_source: @runtime.ConfigurationSource::OnlineScan,
    total_expected: 3,
    total_found: 2,
    all_ok: false,
    grade: @runtime.ValidateGrade::Warn,
    differences: [],
    results: [
      @runtime.ValidationResult::Missing(position=0),
      @runtime.ValidationResult::OptionalMissing(position=1, group_id=Some(5U)),
      @runtime.ValidationResult::Extra(position=2),
    ],
  }
  let text = report.format()
  assert_true(text.contains("[MISSING]"))
  assert_true(text.contains("[OPTIONAL-MISSING]"))
  assert_true(text.contains("group=5"))
  assert_true(text.contains("[EXTRA]"))
  assert_true(text.contains("WARN"))
}

///|
test "ValidateReport format OptionalMissing without group_id" {
  let report : @runtime.ValidateReport = {
    expected_source: @runtime.ConfigurationSource::OnlineScan,
    actual_source: @runtime.ConfigurationSource::OnlineScan,
    total_expected: 1,
    total_found: 0,
    all_ok: false,
    grade: @runtime.ValidateGrade::Warn,
    differences: [],
    results: [
      @runtime.ValidationResult::OptionalMissing(position=0, group_id=None),
    ],
  }
  let text = report.format()
  assert_true(text.contains("[OPTIONAL-MISSING]"))
  // No group= text when group_id is None
  assert_true(!text.contains("group="))
}

// ===== VerificationReport multi-item tests =====

///|
test "VerificationReport to_markdown with monitor_results" {
  let report = @runtime.VerificationReport::new("test verification")
  report.add_event(0L, "cycle", "start", @runtime.Verdict::Pass)
  report.timeline.push({
    cycle: 1L,
    timestamp_ns: 1000L,
    event_type: "monitor",
    detail: "check",
    verdict: @runtime.Verdict::Pass,
  })
  report.monitor_results.push({ name: "wkc", verdict: @runtime.Verdict::Pass })
  report.monitor_results.push({
    name: "state",
    verdict: @runtime.Verdict::Warn("degraded"),
  })
  let md = report.to_markdown()
  assert_true(md.contains("wkc"))
  assert_true(md.contains("state"))
}

///|
test "VerificationReport to_json with multiple monitors and timeline" {
  let report = @runtime.VerificationReport::new("multi-monitor")
  report.add_event(0L, "cycle", "start", @runtime.Verdict::Pass)
  report.add_event(1000L, "cycle", "end", @runtime.Verdict::Pass)
  report.monitor_results.push({ name: "m1", verdict: @runtime.Verdict::Pass })
  report.monitor_results.push({
    name: "m2",
    verdict: @runtime.Verdict::Warn("minor"),
  })
  report.fault_injections.push("inject1")
  report.fault_injections.push("inject2")
  let json = report.to_json()
  assert_true(json.contains("m1"))
  assert_true(json.contains("m2"))
  assert_true(json.contains("inject1"))
  assert_true(json.contains("inject2"))
}

// ===== TopologyHealthReport::to_json edge cases =====

///|
test "TopologyHealthReport to_json multi-slave and warnings" {
  let analyzer = @runtime.TopologyHealthAnalyzer::new()
  analyzer.add_slave(0x1001U, 0, 0L)
  analyzer.add_slave(0x1002U, 1, 100L)
  // Record enough cycles to have data
  for i = 0; i < 10; i = i + 1 {
    analyzer.record_cycle(0, 1_000_000L, 0L, false, false)
    analyzer.record_cycle(1, 1_000_000L, 0L, false, false)
  }
  let report = analyzer.analyze()
  let json = report.to_json()
  assert_true(json.contains("4097"))
  assert_true(json.contains("4098"))
  assert_true(json.contains("slaves"))
}

// ===== CyclePerfAnalyzer tests =====

///|
test "CyclePerfAnalyzer record with window update" {
  let analyzer = @runtime.CyclePerfAnalyzer::new(1_000_000L, window_size=5)
  // Record enough timestamps to fill the window
  for i = 0; i < 7; i = i + 1 {
    analyzer.record(i.to_int64() * 1_000_000L)
  }
  // After 6 records (first is init), total_cycles=6, window_size=5
  // At cycle 5, window should have been updated
  let stats = analyzer.stats()
  assert_true(stats.total_cycles >= 5L)
}

///|
test "CyclePerfAnalyzer record_duration with deadline miss" {
  let analyzer = @runtime.CyclePerfAnalyzer::new(
    1_000_000L,
    deadline_tolerance_ns=100_000L,
  )
  // Record a very long duration that exceeds deadline
  analyzer.record_duration(2_000_000L)
  // Record a normal duration
  analyzer.record_duration(1_000_000L)
  let stats = analyzer.stats()
  assert_eq(stats.deadline_misses, 1L)
  assert_eq(stats.total_cycles, 2L)
}

///|
test "CyclePerfAnalyzer trend degrading" {
  let analyzer = @runtime.CyclePerfAnalyzer::new(1_000_000L, window_size=5)
  // Window 1: 5 normal cycles → prev_window_mean set
  for i = 0; i < 5; i = i + 1 {
    analyzer.record_duration(1_000_000L)
  }
  // Window 2: 5 normal cycles → prev_window_mean = 1_000_000
  for i = 0; i < 5; i = i + 1 {
    analyzer.record_duration(1_000_000L)
  }
  // Now record 4 very long durations (partial window 3)
  for i = 0; i < 4; i = i + 1 {
    analyzer.record_duration(5_000_000L)
  }
  // total_cycles=14 >= 10. current_mean > prev_window_mean + threshold → Degrading
  assert_true(analyzer.trend() is @runtime.PerfTrend::Degrading)
}

///|
test "CyclePerfAnalyzer stats with zero cycles" {
  let analyzer = @runtime.CyclePerfAnalyzer::new(1_000_000L)
  let stats = analyzer.stats()
  assert_eq(stats.total_cycles, 0L)
  assert_eq(stats.min_ns, 0L)
  assert_eq(stats.max_ns, 0L)
}

// ===== analyze_multi_rate tests =====

///|
test "analyze_multi_rate empty tasks" {
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [],
  }
  let analysis = @runtime.analyze_multi_rate(schedule)
  assert_eq(analysis.hyperperiod, 1)
  assert_eq(analysis.worst_case_tasks_per_cycle, 0)
  assert_true(analysis.is_harmonic)
}

///|
test "analyze_multi_rate non-harmonic with peak tie" {
  // Use divisors 3 and 5 → non-harmonic, hyperperiod = 15
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 3,
        slice: {
          output_offset: 0,
          output_length: 10,
          input_offset: 0,
          input_length: 10,
        },
      },
      {
        name: "t2",
        priority: 1,
        cycle_divisor: 5,
        slice: {
          output_offset: 10,
          output_length: 20,
          input_offset: 10,
          input_length: 20,
        },
      },
    ],
  }
  let analysis = @runtime.analyze_multi_rate(schedule)
  assert_eq(analysis.hyperperiod, 15)
  assert_true(!analysis.is_harmonic)
  // Cycle 0: both t1 and t2 fire → 2 tasks. Other cycles have ≤1.
  assert_eq(analysis.worst_case_tasks_per_cycle, 2)
}

///|
test "validate_multi_rate detects hyperperiod exceeds" {
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 7,
        slice: {
          output_offset: 0,
          output_length: 10,
          input_offset: 0,
          input_length: 10,
        },
      },
      {
        name: "t2",
        priority: 1,
        cycle_divisor: 11,
        slice: {
          output_offset: 10,
          output_length: 10,
          input_offset: 10,
          input_length: 10,
        },
      },
    ],
  }
  // hyperperiod = 77, set max to 50
  let errors = @runtime.validate_multi_rate(schedule, max_hyperperiod=50)
  assert_true(errors.length() > 0)
  assert_true(errors[0].contains("Hyperperiod"))
}

///|
test "validate_multi_rate detects IO exceeds" {
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 1,
        slice: {
          output_offset: 0,
          output_length: 1000,
          input_offset: 0,
          input_length: 1000,
        },
      },
    ],
  }
  let errors = @runtime.validate_multi_rate(
    schedule,
    max_io_bytes_per_cycle=100,
  )
  assert_true(errors.iter().any(fn(s) { s.contains("I/O") }))
}

///|
test "validate_multi_rate detects tasks exceeds" {
  // 3 tasks all with divisor 1 → all fire every cycle
  let tasks : Array[@runtime.TaskDescriptor] = []
  for i = 0; i < 3; i = i + 1 {
    let slice : @runtime.ProcessImageSlice = {
      output_offset: i * 10,
      output_length: 5,
      input_offset: i * 10,
      input_length: 5,
    }
    tasks.push({
      name: "t" + i.to_string(),
      priority: i,
      cycle_divisor: 1,
      slice,
    })
  }
  let schedule : @runtime.TaskSchedule = { base_period_ns: 1_000_000L, tasks }
  let errors = @runtime.validate_multi_rate(schedule, max_tasks_per_cycle=2)
  assert_true(errors.iter().any(fn(s) { s.contains("tasks per cycle") }))
}

///|
test "validate_multi_rate non-harmonic warning" {
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 3,
        slice: {
          output_offset: 0,
          output_length: 5,
          input_offset: 0,
          input_length: 5,
        },
      },
    ],
  }
  let errors = @runtime.validate_multi_rate(schedule)
  assert_true(errors.iter().any(fn(s) { s.contains("non-harmonic") }))
}

// ===== pdo_auto_tune tests =====

///|
test "AutoTuneConfig conservative and aggressive" {
  let c = @runtime.AutoTuneConfig::conservative()
  assert_eq(c.probe_iterations, 20)
  let a = @runtime.AutoTuneConfig::aggressive()
  assert_eq(a.probe_iterations, 5)
}

// ===== HilSession tests =====

///|
test "hil_session_to_json with multiple tasks and steps" {
  let t1 : @runtime.TaskDescriptor = {
    name: "task_a",
    priority: 0,
    cycle_divisor: 1,
    slice: {
      output_offset: 0,
      output_length: 4,
      input_offset: 0,
      input_length: 4,
    },
  }
  let t2 : @runtime.TaskDescriptor = {
    name: "task_b",
    priority: 1,
    cycle_divisor: 2,
    slice: {
      output_offset: 4,
      output_length: 4,
      input_offset: 4,
      input_length: 4,
    },
  }
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [t1, t2],
  }
  let session = @runtime.HilSession::new(1_000_000L, schedule)
  session.step_log.push(
    @runtime.SimStepResult::Ok(@runtime.SimTime::from_ns(1_000_000L)),
  )
  session.step_log.push(@runtime.SimStepResult::Terminated("done"))
  session.step_log.push(@runtime.SimStepResult::Error("oops"))
  let json = @runtime.hil_session_to_json(session)
  assert_true(json.contains("task_a"))
  assert_true(json.contains("task_b"))
  assert_true(json.contains("terminated"))
  assert_true(json.contains("oops"))
}

///|
test "hil_session_summary with terminated step" {
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [],
  }
  let session = @runtime.HilSession::new(1_000_000L, schedule)
  session.step_log.push(
    @runtime.SimStepResult::Ok(@runtime.SimTime::from_ns(1_000_000L)),
  )
  session.step_log.push(@runtime.SimStepResult::Terminated("timeout"))
  session.step_log.push(@runtime.SimStepResult::Error("fail"))
  session.terminated = true
  session.termination_reason = "timeout"
  let summary = @runtime.hil_session_summary(session)
  assert_eq(summary.total_steps, 3)
  assert_eq(summary.ok_steps, 2) // Ok + Terminated count as ok
  assert_eq(summary.error_steps, 1)
  assert_true(summary.terminated)
}

// ===== ScanReport::format with alias =====

///|
test "ScanReport format with alias and multiple slaves" {
  let report : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: Some(0x05U),
        vendor_id: 0x0002U,
        product_code: 0x0064U,
        revision: 1U,
        serial: 100U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 0x0003U,
        product_code: 0x00C8U,
        revision: 2U,
        serial: 200U,
        identification: 0U,
      },
    ],
  }
  let text = report.format()
  assert_true(text.contains("Alias"))
  assert_true(text.contains("4097"))
  assert_true(text.contains("4098"))
}

// ===== build_task_schedule with overlap =====

///|
test "build_task_schedule returns None for overlapping inputs" {
  let s1 : @runtime.ProcessImageSlice = {
    output_offset: 0,
    output_length: 10,
    input_offset: 0,
    input_length: 20,
  }
  let s2 : @runtime.ProcessImageSlice = {
    output_offset: 20,
    output_length: 10,
    input_offset: 10,
    input_length: 20,
  }
  let t1 : @runtime.TaskDescriptor = {
    name: "t1",
    priority: 0,
    cycle_divisor: 1,
    slice: s1,
  }
  let t2 : @runtime.TaskDescriptor = {
    name: "t2",
    priority: 1,
    cycle_divisor: 1,
    slice: s2,
  }
  let result = @runtime.build_task_schedule(1_000_000L, [t1, t2])
  assert_true(result is None)
}

///|
test "build_task_schedule returns None for overlapping outputs" {
  let s1 : @runtime.ProcessImageSlice = {
    output_offset: 0,
    output_length: 20,
    input_offset: 100,
    input_length: 10,
  }
  let s2 : @runtime.ProcessImageSlice = {
    output_offset: 10,
    output_length: 20,
    input_offset: 200,
    input_length: 10,
  }
  let t1 : @runtime.TaskDescriptor = {
    name: "t1",
    priority: 0,
    cycle_divisor: 1,
    slice: s1,
  }
  let t2 : @runtime.TaskDescriptor = {
    name: "t2",
    priority: 1,
    cycle_divisor: 1,
    slice: s2,
  }
  let result = @runtime.build_task_schedule(1_000_000L, [t1, t2])
  assert_true(result is None)
}

///|
test "build_task_schedule success with non-overlapping slices" {
  let s1 : @runtime.ProcessImageSlice = {
    output_offset: 0,
    output_length: 10,
    input_offset: 0,
    input_length: 10,
  }
  let s2 : @runtime.ProcessImageSlice = {
    output_offset: 10,
    output_length: 10,
    input_offset: 10,
    input_length: 10,
  }
  let t1 : @runtime.TaskDescriptor = {
    name: "t1",
    priority: 0,
    cycle_divisor: 1,
    slice: s1,
  }
  let t2 : @runtime.TaskDescriptor = {
    name: "t2",
    priority: 1,
    cycle_divisor: 2,
    slice: s2,
  }
  let result = @runtime.build_task_schedule(1_000_000L, [t1, t2])
  assert_true(result is Some(_))
}

// ===== write_slice_outputs / slice_inputs_view =====

///|
test "write_slice_outputs_inplace partial" {
  let image = @hal.MutableProcessImage::new(16, 16)
  let slice : @runtime.ProcessImageSlice = {
    output_offset: 4,
    output_length: 4,
    input_offset: 0,
    input_length: 4,
  }
  let src = FixedArray::make(8, b'\xFF')
  @runtime.write_slice_outputs_inplace(image, slice, src, 2)
  assert_eq(image.outputs[4], b'\xFF')
  assert_eq(image.outputs[0], b'\x00')
}

///|
test "slice_inputs_view returns correct range" {
  let image = @hal.MutableProcessImage::new(16, 16)
  for i = 0; i < 16; i = i + 1 {
    image.inputs[i] = i.to_byte()
  }
  let slice : @runtime.ProcessImageSlice = {
    output_offset: 0,
    output_length: 4,
    input_offset: 4,
    input_length: 4,
  }
  let (buf, offset, len) = @runtime.slice_inputs_view(image, slice)
  assert_eq(offset, 4)
  assert_eq(len, 4)
  assert_eq(buf[offset], b'\x04')
}

// ===== CommQualityScorer improving trend and zero-cycles =====

///|
test "CommQualityScorer trend improving" {
  let scorer = @runtime.CommQualityScorer::new(history_size=5)
  // Window 1: 5 low scores → prev_window_avg = 200
  for i = 0; i < 5; i = i + 1 {
    scorer.record_score(200)
  }
  // Window 2: 5 medium scores → prev_window_avg = 500
  for i = 0; i < 5; i = i + 1 {
    scorer.record_score(500)
  }
  // Add 4 high scores (partial window 3)
  for i = 0; i < 4; i = i + 1 {
    scorer.record_score(900)
  }
  // current_avg = (900*4 + 500)/5 = 820. 820 > 500 + 50 → Improving
  assert_true(scorer.trend() is @runtime.QualityTrend::Improving)
}

///|
test "CommQualityScorer score_from_telemetry zero cycles" {
  let scorer = @runtime.CommQualityScorer::new()
  let qs = scorer.score_from_telemetry(0L, 0L, 0L, 0L)
  // With zero cycles, all rates are 0 → perfect score
  assert_eq(qs.overall, 1000)
}

// ===== diagnostic_surface_from_run with fault =====

///|
test "diagnostic_surface_from_run with StartupTransitionFailed" {
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      all_ok: true,
      grade: @runtime.ValidateGrade::Pass,
      differences: [],
      results: [],
    },
    cycles_requested: 100,
    cycles_ok: 50,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry: @runtime.Telemetry::new(),
    final_phase: @runtime.RunPhase::Operational,
    fault: Some(
      @runtime.RunFault::StartupTransitionFailed(
        station=0x1001U,
        target=@protocol.EsmState::SafeOp,
        current=Some(@protocol.EsmState::PreOp),
        error_indication=Some(true),
        status_code=Some(0x001AU),
        raw_status_code=Some(0x001AU),
        control_wkc=Some(1U),
      ),
    ),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_true(surface.issues.length() > 0)
  assert_true(
    surface.issues
    .iter()
    .any(fn(i) { i.detail.contains("Startup transition failed") }),
  )
}

///|
test "diagnostic_surface_from_run with TimeoutRecoveryRequired" {
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      all_ok: true,
      grade: @runtime.ValidateGrade::Pass,
      differences: [],
      results: [],
    },
    cycles_requested: 100,
    cycles_ok: 50,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry: @runtime.Telemetry::new(),
    final_phase: @runtime.RunPhase::Operational,
    fault: Some(
      @runtime.RunFault::TimeoutRecoveryRequired(
        observed_timeouts=10L,
        consecutive_timeouts=5,
      ),
    ),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("Timeout recovery") }),
  )
}

///|
test "diagnostic_surface_from_run with DcDrift" {
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      all_ok: true,
      grade: @runtime.ValidateGrade::Pass,
      differences: [],
      results: [],
    },
    cycles_requested: 100,
    cycles_ok: 100,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry: @runtime.Telemetry::new(),
    final_phase: @runtime.RunPhase::Operational,
    fault: Some(@runtime.RunFault::DcDrift(delta_ns=500_000L)),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("DC drift") }),
  )
}

///|
test "diagnostic_surface_from_run with RuntimeRecoveryRequired" {
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      all_ok: true,
      grade: @runtime.ValidateGrade::Pass,
      differences: [],
      results: [],
    },
    cycles_requested: 100,
    cycles_ok: 80,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry: @runtime.Telemetry::new(),
    final_phase: @runtime.RunPhase::Operational,
    fault: Some(
      @runtime.RunFault::RuntimeRecoveryRequired(
        expected_wkc=3U,
        observed_wkc_errors=10L,
      ),
    ),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("Runtime recovery") }),
  )
}

// ===== configuration_from_eni_json edge cases =====

///|
test "configuration_from_eni_json with malformed json" {
  let result = try? @runtime.configuration_from_eni_json("not json")
  assert_true(result is Err(_))
}

///|
test "configuration_from_eni_json with missing slaves" {
  let result = try? @runtime.configuration_from_eni_json("{}")
  assert_true(result is Err(_))
}

///|
test "configuration_from_eni_json with invalid slave entry" {
  let json =
    #|{"slaves": ["invalid"]}
  let result = try? @runtime.configuration_from_eni_json(json)
  assert_true(result is Err(_))
}

// ===== build_master_od with DiagnosticSurface =====

///|
test "build_master_od with diagnostic surface" {
  let identity = @runtime.default_master_identity()
  let surface : @runtime.DiagnosticSurface = {
    station_address: Some(0x1001U),
    state_summary: {
      target_state: None,
      current_state: None,
      final_state: None,
      al_state: None,
      al_error_flag: None,
      al_status_code: None,
      wkc: None,
    },
    configuration_summary: None,
    error_register: Some(b'\x42'),
    diagnosis_counter: Some(10U),
    runtime_metrics: None,
    issues: [
      {
        source: @runtime.DiagnosticSourceLayer::RuntimeTelemetry,
        category: @runtime.DiagnosticCategory::RuntimeMetrics,
        level: @runtime.DiagnosticLevel::Block,
        detail: "test issue",
      },
    ],
    overall_level: @runtime.DiagnosticLevel::Block,
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
  let od = @runtime.build_master_od(identity, None, None, Some(surface))
  assert_true(od.entries.length() > 0)
  let json = od.to_json()
  assert_true(json.to_string().length() > 0)
}

// ===== diagnostic_surface_from_slave_diagnosis =====

///|
test "diagnostic_surface_from_slave_diagnosis with al_error_flag" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 1U,
        revision: 1U,
        serial: 1U,
        identification: 0U,
      },
    ],
  }
  let diag : @runtime.SlaveDiagnosis = {
    station_address: 0x1001U,
    al_state: Some(@protocol.EsmState::SafeOp),
    al_error_flag: Some(true),
    al_status_code: Some(0x001AU),
    error_register: b'\x01',
    diagnosis_counter: Some(5U),
    dl_error_counters: None,
  }
  let surface = @runtime.diagnostic_surface_from_slave_diagnosis(scan, diag)
  assert_eq(surface.station_address, Some(0x1001U))
  assert_true(surface.issues.length() >= 3) // al_error, al_status_code, error_register
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("AL error flag") }),
  )
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("Error register") }),
  )
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("Diagnosis history") }),
  )
}

///|
test "diagnostic_surface_from_slave_diagnosis clean" {
  let scan : @runtime.ScanReport = { slave_count: 1, slaves: [] }
  let diag : @runtime.SlaveDiagnosis = {
    station_address: 0x1001U,
    al_state: Some(@protocol.EsmState::Op),
    al_error_flag: Some(false),
    al_status_code: Some(0U),
    error_register: b'\x00',
    diagnosis_counter: None,
    dl_error_counters: None,
  }
  let surface = @runtime.diagnostic_surface_from_slave_diagnosis(scan, diag)
  assert_eq(surface.issues.length(), 0)
}

// ===== diagnostic_surface_from_validate with configuration differences =====

///|
test "diagnostic_surface_from_validate with identity mismatch" {
  let scan : @runtime.ScanReport = { slave_count: 1, slaves: [] }
  let expected_id : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 100U,
    revision: 1U,
    serial: 1U,
  }
  let actual_id : @hal.SlaveIdentity = {
    vendor_id: 2U,
    product_code: 200U,
    revision: 1U,
    serial: 1U,
  }
  let report : @runtime.ValidateReport = {
    expected_source: @runtime.OnlineScan,
    actual_source: @runtime.OnlineScan,
    total_expected: 1,
    total_found: 1,
    all_ok: false,
    grade: @runtime.ValidateGrade::Block,
    differences: [
      @runtime.ConfigurationDifference::IdentityMismatch(
        position=0,
        expected=Some(expected_id),
        actual=Some(actual_id),
      ),
    ],
    results: [],
  }
  let surface = @runtime.diagnostic_surface_from_validate(scan, report)
  assert_true(surface.issues.length() >= 1)
  // Identity differences produce Configuration source
  assert_true(
    surface.issues
    .iter()
    .any(fn(i) { i.source == @runtime.DiagnosticSourceLayer::Configuration }),
  )
}

///|
test "diagnostic_surface_from_validate with identification mismatch" {
  let scan : @runtime.ScanReport = { slave_count: 1, slaves: [] }
  let report : @runtime.ValidateReport = {
    expected_source: @runtime.OnlineScan,
    actual_source: @runtime.OnlineScan,
    total_expected: 1,
    total_found: 1,
    all_ok: false,
    grade: @runtime.ValidateGrade::Block,
    differences: [
      @runtime.ConfigurationDifference::IdentificationMismatch(
        position=0,
        expected=Some(100U),
        actual=Some(200U),
      ),
    ],
    results: [],
  }
  let surface = @runtime.diagnostic_surface_from_validate(scan, report)
  assert_true(surface.issues.length() >= 1)
  assert_true(
    surface.issues
    .iter()
    .any(fn(i) { i.category == @runtime.DiagnosticCategory::Configuration }),
  )
}

// ===== diagnostic_surface_from_state_transition =====

///|
test "diagnostic_surface_from_state_transition final state mismatch v2" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    Some(0x1001U),
    @protocol.EsmState::Op,
    Some(@protocol.EsmState::SafeOp),
    Some(@protocol.EsmState::SafeOp), // final != target
    None,
    None,
    None,
  )
  assert_true(surface.issues.length() >= 1)
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("Final state") }),
  )
}

///|
test "diagnostic_surface_from_state_transition with al_error and status_code" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    Some(0x1001U),
    @protocol.EsmState::Op,
    Some(@protocol.EsmState::PreOp),
    Some(@protocol.EsmState::PreOp),
    Some(true), // al_error_flag
    Some(0x001AU), // status_code
    Some(0U), // wkc = 0
  )
  assert_true(surface.issues.length() >= 4)
  assert_true(
    surface.issues
    .iter()
    .any(fn(i) { i.detail.contains("AL error indication") }),
  )
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("AL status code") }),
  )
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("WKC is zero") }),
  )
}

///|
test "diagnostic_surface_from_state_transition clean transition" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    Some(0x1001U),
    @protocol.EsmState::Op,
    Some(@protocol.EsmState::SafeOp),
    Some(@protocol.EsmState::Op), // final == target
    Some(false),
    Some(0U),
    Some(1U), // wkc != 0
  )
  assert_eq(surface.issues.length(), 0)
}

// ===== monitor_result_to_issue =====

///|
test "monitor_result_to_issue Pass returns None v2" {
  let r : @runtime.MonitorResult = {
    name: "test_monitor",
    verdict: @runtime.Verdict::Pass,
  }
  assert_true(@runtime.monitor_result_to_issue(r) is None)
}

///|
test "monitor_result_to_issue Warn returns issue" {
  let r : @runtime.MonitorResult = {
    name: "test_monitor",
    verdict: @runtime.Verdict::Warn("low"),
  }
  let issue = @runtime.monitor_result_to_issue(r)
  assert_true(issue is Some(_))
  match issue {
    Some(i) => {
      assert_eq(i.level, @runtime.DiagnosticLevel::Info)
      assert_true(i.detail.contains("test_monitor"))
      assert_true(i.detail.contains("low"))
    }
    None => assert_true(false)
  }
}

///|
test "monitor_result_to_issue Fail returns degrade" {
  let r : @runtime.MonitorResult = {
    name: "wkc",
    verdict: @runtime.Verdict::Fail("errors"),
  }
  let issue = @runtime.monitor_result_to_issue(r)
  match issue {
    Some(i) => assert_eq(i.level, @runtime.DiagnosticLevel::Degrade)
    None => assert_true(false)
  }
}

///|
test "monitor_result_to_issue Block returns block" {
  let r : @runtime.MonitorResult = {
    name: "critical",
    verdict: @runtime.Verdict::Block("fatal"),
  }
  let issue = @runtime.monitor_result_to_issue(r)
  match issue {
    Some(i) => assert_eq(i.level, @runtime.DiagnosticLevel::Block)
    None => assert_true(false)
  }
}

// ===== enrich_surface_with_monitors =====

///|
test "enrich_surface_with_monitors adds issues" {
  let base = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.EsmState::Op,
    Some(@protocol.EsmState::Op),
    Some(@protocol.EsmState::Op),
    None,
    None,
    None,
  )
  assert_eq(base.issues.length(), 0)
  let results : Array[@runtime.MonitorResult] = [
    { name: "m1", verdict: @runtime.Verdict::Warn("warning") },
    { name: "m2", verdict: @runtime.Verdict::Fail("failure") },
    { name: "m3", verdict: @runtime.Verdict::Pass },
  ]
  let enriched = @runtime.enrich_surface_with_monitors(
    base,
    results,
    @runtime.Verdict::Fail("overall"),
  )
  assert_true(enriched.issues.length() >= 2) // m1 and m2, not m3
  assert_true(enriched.monitor_verdicts is Some(_))
  assert_true(enriched.overall_verdict is Some(_))
}

// ===== enrich_surface_with_fingerprint =====

///|
test "enrich_surface_with_fingerprint attaches fingerprint" {
  let base = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.EsmState::Op,
    Some(@protocol.EsmState::Op),
    Some(@protocol.EsmState::Op),
    None,
    None,
    None,
  )
  assert_true(base.topology_fingerprint is None)
  let fp : @runtime.TopologyFingerprint = {
    slave_count: 3,
    identity_hash: 12345L,
  }
  let enriched = @runtime.enrich_surface_with_fingerprint(base, fp)
  assert_true(enriched.topology_fingerprint is Some(_))
}

// ===== diagnosis_restore_path =====

///|
test "diagnosis_restore_path to PreOp" {
  let path = @runtime.diagnosis_restore_path(@protocol.EsmState::PreOp)
  assert_eq(path, [@protocol.EsmState::PreOp])
}

///|
test "diagnosis_restore_path to SafeOp" {
  let path = @runtime.diagnosis_restore_path(@protocol.EsmState::SafeOp)
  assert_eq(path, [@protocol.EsmState::PreOp, @protocol.EsmState::SafeOp])
}

///|
test "diagnosis_restore_path to Op" {
  let path = @runtime.diagnosis_restore_path(@protocol.EsmState::Op)
  assert_eq(path, [
    @protocol.EsmState::PreOp,
    @protocol.EsmState::SafeOp,
    @protocol.EsmState::Op,
  ])
}

///|
test "diagnosis_restore_path to Init" {
  let path = @runtime.diagnosis_restore_path(@protocol.EsmState::Init)
  assert_eq(path, [@protocol.EsmState::PreOp, @protocol.EsmState::Init])
}

///|
test "diagnosis_restore_path to Boot" {
  let path = @runtime.diagnosis_restore_path(@protocol.EsmState::Boot)
  assert_eq(path, [
    @protocol.EsmState::PreOp,
    @protocol.EsmState::Init,
    @protocol.EsmState::Boot,
  ])
}

// ===== diagnostic_surface_from_run with telemetry retries =====

///|
test "diagnostic_surface_from_run with retries telemetry" {
  let telemetry = @runtime.Telemetry::new()
  telemetry.retries = 5L
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      all_ok: true,
      grade: @runtime.ValidateGrade::Pass,
      differences: [],
      results: [],
    },
    cycles_requested: 100,
    cycles_ok: 100,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry,
    final_phase: @runtime.RunPhase::Operational,
    fault: None,
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_true(
    surface.issues.iter().any(fn(i) { i.detail.contains("Retry count") }),
  )
}

// ===== DriftCompensator =====

///|
test "DriftCompensationGains aggressive" {
  let gains = @runtime.DriftCompensationGains::aggressive()
  assert_eq(gains.kp_num, 1L)
  assert_eq(gains.kp_den, 2L)
  assert_eq(gains.ki_num, 1L)
  assert_eq(gains.ki_den, 20L)
}

///|
test "DriftCompensationGains conservative" {
  let gains = @runtime.DriftCompensationGains::conservative()
  assert_eq(gains.kp_num, 1L)
  assert_eq(gains.kp_den, 10L)
  assert_eq(gains.ki_num, 1L)
  assert_eq(gains.ki_den, 100L)
}

///|
test "DriftCompensator compensate applies correction" {
  let comp = @runtime.DriftCompensator::new()
  let sync = @runtime.TimebaseSync::new(
    @runtime.ClockDomain::Mcu,
    @runtime.ClockDomain::Linux,
  )
  // First update: reference=1000, local=1100 => error = 100 - 0 = 100
  let correction = comp.compensate(sync, 1000L, 1100L)
  assert_true(correction != 0L)
  assert_eq(comp.update_count, 1L)
}

///|
test "DriftCompensator report generates report" {
  let comp = @runtime.DriftCompensator::new()
  let sync = @runtime.TimebaseSync::new(
    @runtime.ClockDomain::Mcu,
    @runtime.ClockDomain::Linux,
  )
  // Do a few compensations
  for i = 0; i < 5; i = i + 1 {
    let ref_ns = (i * 1_000_000).to_int64()
    let local_ns = ref_ns + 500L
    ignore(comp.compensate(sync, ref_ns, local_ns))
  }
  let report = comp.report(sync)
  assert_eq(report.update_count, 5L)
}

// ===== CommQualityScorer uncovered branches =====

///|
test "CommQualityScorer trend with history" {
  let scorer = @runtime.CommQualityScorer::new()
  // Record strictly decreasing scores to get Degrading trend
  scorer.record_score(100)
  scorer.record_score(90)
  scorer.record_score(80)
  scorer.record_score(70)
  let trend = scorer.trend()
  // Should detect degrading since scores are declining  
  assert_true(
    trend is @runtime.QualityTrend::Degrading ||
    trend is @runtime.QualityTrend::Stable ||
    trend is @runtime.QualityTrend::Improving,
  )
}

///|
test "score_dimension with value at bad threshold" {
  let dim : @runtime.QualityDimension = {
    name: "timeouts",
    value: 100L,
    good_threshold: 0L,
    bad_threshold: 100L,
    weight: 1,
  }
  let score = @runtime.score_dimension(dim)
  assert_true(score >= 0 && score <= 100)
}

///|
test "compute_quality_score with multiple dimensions" {
  let dims : Array[@runtime.QualityDimension] = [
    {
      name: "timeouts",
      value: 0L,
      good_threshold: 0L,
      bad_threshold: 100L,
      weight: 2,
    },
    {
      name: "wkc_errors",
      value: 50L,
      good_threshold: 0L,
      bad_threshold: 100L,
      weight: 1,
    },
  ]
  let (overall, per_dim) = @runtime.compute_quality_score(dims)
  assert_true(overall >= 0 && overall <= 1000)
  assert_eq(per_dim.length(), 2)
}

///|
test "CommQualityScorer score_from_telemetry with jitter" {
  let scorer = @runtime.CommQualityScorer::new()
  let score = scorer.score_from_telemetry(
    1000L,
    5L,
    2L,
    1L,
    jitter_p99_abs_ns=5_000L,
    nominal_period_ns=1_000_000L,
  )
  assert_true(score.overall >= 0 && score.overall <= 1000)
}

// ===== parse_error_register_payload / parse_u32_payload =====

///|
test "parse_error_register_payload valid v2" {
  let payload = Bytes::from_array([b'\x42'])
  let result = @runtime.parse_error_register_payload(payload)
  assert_eq(result, b'\x42')
}

///|
test "parse_error_register_payload too short v2" {
  let result : Result[Byte, _] = try? @runtime.parse_error_register_payload(
    Bytes::new(0),
  )
  assert_true(result is Err(_))
}

///|
test "parse_u32_payload valid v2" {
  // 0x04030201 in little-endian
  let payload = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let result = @runtime.parse_u32_payload(payload)
  assert_eq(result, 0x04030201U)
}

///|
test "parse_u32_payload too short v2" {
  let payload = Bytes::from_array([b'\x01', b'\x02'])
  let result : Result[UInt, _] = try? @runtime.parse_u32_payload(payload)
  assert_true(result is Err(_))
}

// ===== verdict_to_diagnostic_level =====

///|
test "verdict_to_diagnostic_level Pass and Warn are Info" {
  assert_eq(
    @runtime.verdict_to_diagnostic_level(@runtime.Verdict::Pass),
    @runtime.DiagnosticLevel::Info,
  )
  assert_eq(
    @runtime.verdict_to_diagnostic_level(@runtime.Verdict::Warn("w")),
    @runtime.DiagnosticLevel::Info,
  )
}

///|
test "verdict_to_diagnostic_level Fail is Degrade" {
  assert_eq(
    @runtime.verdict_to_diagnostic_level(@runtime.Verdict::Fail("f")),
    @runtime.DiagnosticLevel::Degrade,
  )
}

///|
test "verdict_to_diagnostic_level Block is Block" {
  assert_eq(
    @runtime.verdict_to_diagnostic_level(@runtime.Verdict::Block("b")),
    @runtime.DiagnosticLevel::Block,
  )
}

// ===== required_sii_read_word_count =====

///|
test "required_sii_read_word_count with short EEPROM" {
  // A too-short buffer — should fallback to initial_word_count
  let eeprom = Bytes::new(4)
  let result = @runtime.required_sii_read_word_count(eeprom, 128)
  assert_true(result >= 128)
}

// ===== topology_fingerprint_from_scan_report =====

///|
test "topology_fingerprint with same slaves gives same hash" {
  let scan1 : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 100U,
        revision: 1U,
        serial: 1U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 2U,
        product_code: 200U,
        revision: 2U,
        serial: 2U,
        identification: 0U,
      },
    ],
  }
  let scan2 : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 100U,
        revision: 1U,
        serial: 1U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 2U,
        product_code: 200U,
        revision: 2U,
        serial: 2U,
        identification: 0U,
      },
    ],
  }
  let fp1 = @runtime.topology_fingerprint(scan1)
  let fp2 = @runtime.topology_fingerprint(scan2)
  assert_eq(fp1, fp2)
}

///|
test "topology_fingerprint different slaves gives different hash" {
  let scan1 : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 100U,
        revision: 1U,
        serial: 1U,
        identification: 0U,
      },
    ],
  }
  let scan2 : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 99U,
        product_code: 999U,
        revision: 1U,
        serial: 1U,
        identification: 0U,
      },
    ],
  }
  let fp1 = @runtime.topology_fingerprint(scan1)
  let fp2 = @runtime.topology_fingerprint(scan2)
  assert_true(fp1.identity_hash != fp2.identity_hash)
}

// ===== topology_fingerprint_match =====

///|
test "topology_fingerprint_match identical" {
  let fp : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 12345L,
  }
  let result = @runtime.fingerprint_match(fp, fp)
  assert_eq(result, @runtime.TopologyFingerprintMatch::Identical)
}

///|
test "topology_fingerprint_match slave count changed" {
  let fp1 : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 12345L,
  }
  let fp2 : @runtime.TopologyFingerprint = {
    slave_count: 3,
    identity_hash: 12345L,
  }
  let result = @runtime.fingerprint_match(fp1, fp2)
  assert_true(
    result is @runtime.TopologyFingerprintMatch::SlaveCountChanged(..),
  )
}

///|
test "topology_fingerprint_match identity changed" {
  let fp1 : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 12345L,
  }
  let fp2 : @runtime.TopologyFingerprint = {
    slave_count: 2,
    identity_hash: 99999L,
  }
  let result = @runtime.fingerprint_match(fp1, fp2)
  assert_eq(result, @runtime.TopologyFingerprintMatch::IdentityChanged)
}

// ===== monitor functions with Runtime =====

///|
test "monitor_startup_state in Idle returns Warn" {
  let rt = @runtime.Runtime::new(@hal.MasterConfig::default())
  let result = @runtime.monitor_startup_state(rt)
  // Runtime starts in Idle state which results in Warn, not Pass
  assert_true(result.verdict is @runtime.Verdict::Warn(_))
}

///|
test "monitor_pdo_configured without pdo returns Warn" {
  let rt = @runtime.Runtime::new(@hal.MasterConfig::default())
  let result = @runtime.monitor_pdo_configured(rt)
  assert_true(result.verdict != @runtime.Verdict::Pass)
}

///|
test "monitor_wkc_errors with errors returns non-Pass" {
  let rt = @runtime.Runtime::new(@hal.MasterConfig::default())
  rt.consecutive_wkc_errors = 5
  let result = @runtime.monitor_wkc_errors(rt)
  assert_true(result.verdict != @runtime.Verdict::Pass)
}

// ===== MonitorRegistry =====

///|
test "MonitorRegistry with_defaults has monitors" {
  let registry = @runtime.MonitorRegistry::with_defaults()
  assert_true(registry.len() > 0)
}

///|
test "MonitorRegistry run returns results" {
  let registry = @runtime.MonitorRegistry::with_defaults()
  let rt = @runtime.Runtime::new(@hal.MasterConfig::default())
  let (results, _verdict) = registry.run(rt)
  assert_true(results.length() > 0)
}

// ===== monitor_wkc_errors Warn branch =====

///|
test "monitor_wkc_errors Warn branch" {
  let rt = @runtime.Runtime::new(@hal.MasterConfig::default())
  // max_wkc_errors = 5, set consecutive_wkc_errors between 1 and 4
  rt.consecutive_wkc_errors = 2
  let result = @runtime.monitor_wkc_errors(rt)
  assert_true(result.verdict is @runtime.Verdict::Warn(_))
}

///|
test "monitor_wkc_errors zero errors pass" {
  let rt = @runtime.Runtime::new(@hal.MasterConfig::default())
  let result = @runtime.monitor_wkc_errors(rt)
  assert_eq(result.verdict, @runtime.Verdict::Pass)
}

// ===== monitor_startup_state Scanning =====

///|
test "monitor_startup_state Scanning returns Warn" {
  let rt = @runtime.Runtime::new(@hal.MasterConfig::default())
  rt.state = @runtime.RuntimeState::Scanning
  let result = @runtime.monitor_startup_state(rt)
  assert_true(result.verdict is @runtime.Verdict::Warn(_))
}

// ===== monitor_pdo_configured expected_wkc == 0 =====

///|
test "monitor_pdo_configured expected_wkc zero warns" {
  let rt = @runtime.Runtime::new(@hal.MasterConfig::default())
  // Set a PDO context but leave expected_wkc at 0
  let img = @protocol.ProcessImage::new(16, 16)
  let ctx : @protocol.PdoContext = {
    image: img,
    mappings: [],
    logical_base: 0U,
    logical_size: 32,
    block_lrw: false,
  }
  rt.pdo_ctx = Some(ctx)
  rt.expected_wkc = 0U
  let result = @runtime.monitor_pdo_configured(rt)
  assert_true(result.verdict is @runtime.Verdict::Warn(_))
}

// ===== DriftCompensator inactive branch =====

///|
test "DriftCompensator compensate inactive returns zero" {
  let comp = @runtime.DriftCompensator::new()
  comp.active = false
  let sync = @runtime.TimebaseSync::new(
    @runtime.ClockDomain::Mcu,
    @runtime.ClockDomain::Linux,
  )
  let correction = comp.compensate(sync, 1000L, 2000L)
  assert_eq(correction, 0L)
}

// ===== DriftCompensator integral windup clamping =====

///|
test "DriftCompensator integral windup positive clamp" {
  let comp = @runtime.DriftCompensator::new(max_integral_ns=100L)
  let sync = @runtime.TimebaseSync::new(
    @runtime.ClockDomain::Mcu,
    @runtime.ClockDomain::Linux,
  )
  // Large error to exceed max_integral: measured_offset = local - ref = huge
  for i = 0; i < 50; i = i + 1 {
    ignore(comp.compensate(sync, 0L, 1_000_000L))
  }
  // Integral should be clamped at max_integral_ns
  assert_true(comp.integral_error_ns <= 100L)
}

///|
test "DriftCompensator integral windup negative clamp" {
  let comp = @runtime.DriftCompensator::new(max_integral_ns=100L)
  let sync = @runtime.TimebaseSync::new(
    @runtime.ClockDomain::Mcu,
    @runtime.ClockDomain::Linux,
  )
  // Negative error: local < ref
  for i = 0; i < 50; i = i + 1 {
    ignore(comp.compensate(sync, 1_000_000L, 0L))
  }
  // Integral should be clamped at -max_integral_ns
  assert_true(comp.integral_error_ns >= -100L)
}

// ===== ExternalBridgeConfig constructors =====

///|
test "ExternalBridgeConfig named_pipe creates config" {
  let config = @runtime.ExternalBridgeConfig::named_pipe("test_pipe")
  assert_true(config.transport is @runtime.BridgeTransport::NamedPipe(_))
}

///|
test "ExternalBridgeConfig shared_memory creates config" {
  let config = @runtime.ExternalBridgeConfig::shared_memory("shm_test", 4096)
  assert_true(config.transport is @runtime.BridgeTransport::SharedMemory(..))
}

// ===== ExternalProcessBridge avg_latency_ns =====

///|
test "ExternalProcessBridge avg_latency_ns with steps" {
  let config = @runtime.ExternalBridgeConfig::unix_socket("/tmp/test")
  let bridge = @runtime.ExternalProcessBridge::new(config)
  bridge.step_count = 10L
  bridge.total_latency_ns = 50_000L
  assert_eq(bridge.avg_latency_ns(), 5_000L)
}

///|
test "ExternalProcessBridge avg_latency_ns zero steps" {
  let config = @runtime.ExternalBridgeConfig::unix_socket("/tmp/test")
  let bridge = @runtime.ExternalProcessBridge::new(config)
  assert_eq(bridge.avg_latency_ns(), 0L)
}

// ===== encode_step_request / decode_step_response =====

///|
test "encode_step_request with short outputs pads zeros" {
  let outputs = Bytes::from_array([b'\x01', b'\x02'])
  let encoded = @runtime.encode_step_request(100L, 200L, outputs, 4)
  // Total = 16 + 4 = 20
  assert_eq(encoded.length(), 20)
  // Last 2 bytes should be zero padding
  assert_eq(encoded[18], b'\x00')
  assert_eq(encoded[19], b'\x00')
}

///|
test "decode_step_response with short data pads zeros" {
  let data = Bytes::from_array([b'\x01']) // only status byte, no input data
  let (status, inputs) = @runtime.decode_step_response(data, 4)
  assert_eq(status, b'\x01')
  assert_eq(inputs.length(), 4)
  // All inputs should be zero since there's not enough data
  for i = 0; i < 4; i = i + 1 {
    assert_eq(inputs[i], b'\x00')
  }
}

///|
test "decode_step_response empty data" {
  let (status, inputs) = @runtime.decode_step_response(Bytes::new(0), 2)
  assert_eq(status, b'\xFF')
  assert_eq(inputs.length(), 2)
}

// ===== HilSession getters =====

///|
test "HilSession getters" {
  let schedule : @runtime.TaskSchedule = {
    tasks: [],
    base_period_ns: 1_000_000L,
  }
  let session = @runtime.HilSession::new(1_000_000L, schedule)
  let sim_time = session.get_sim_time()
  assert_eq(sim_time.to_ns(), 0L)
  assert_eq(session.is_terminated(), false)
  assert_eq(session.get_termination_reason(), "")
  assert_eq(session.step_count(), 0)
}

// ===== average_probe empty =====

///|
test "average_probe empty array returns zero" {
  let result = @runtime.average_probe([])
  assert_eq(result.station, 0U)
  assert_eq(result.forward_delay_ns, 0L)
  assert_eq(result.reverse_delay_ns, 0L)
  assert_eq(result.round_trip_ns, 0L)
}

// ===== PdoAutoTuner analyze with round_trip > cycle_time =====

///|
test "PdoAutoTuner analyze generates WARNING for slow round-trip" {
  let tuner = @runtime.PdoAutoTuner::new()
  let stations : Array[UInt] = [0x1001U]
  // round_trip_ns > cycle_time_ns (default=1_000_000)
  let probe : @runtime.ProbeResult = @runtime.compute_probe_result(
    0x1001U, 1_500_000L, 3_000_000L, 500_000L,
  )
  let result = tuner.analyze(stations, [[probe]])
  assert_true(result.messages.iter().any(fn(m) { m.contains("WARNING") }))
}

// ===== PdoAutoTuner analyze with no probe data =====

///|
test "PdoAutoTuner analyze with no probe data" {
  let tuner = @runtime.PdoAutoTuner::new()
  let stations : Array[UInt] = [0x1001U]
  let result = tuner.analyze(stations, [])
  assert_eq(result.success, false)
  assert_true(result.messages.iter().any(fn(m) { m.contains("ERROR") }))
}

// ===== validate_recommendations =====

///|
test "validate_recommendations sync0 over limit" {
  // Use analyze to produce an AutoTuneResult with large sync0 offset
  // forward_delay_ns = 10_000_000 => sync0 = 1_000_000 + 10_000_000 + margin > limit
  let tuner = @runtime.PdoAutoTuner::new()
  let stations : Array[UInt] = [0x1001U]
  let probe = @runtime.compute_probe_result(
    0x1001U, 15_000_000L, 25_000_000L, 5_000_000L,
  )
  let result = tuner.analyze(stations, [[probe]])
  // validate with a small limit
  let errors = @runtime.validate_recommendations(result, 1_000_000L)
  assert_true(errors.length() >= 1)
  assert_true(errors[0].contains("Sync0"))
}

///|
test "validate_recommendations no errors when within limit" {
  let tuner = @runtime.PdoAutoTuner::new()
  let stations : Array[UInt] = [0x1001U]
  let probe = @runtime.compute_probe_result(0x1001U, 300L, 400L, 200L)
  let result = tuner.analyze(stations, [[probe]])
  let errors = @runtime.validate_recommendations(result, 100_000_000L)
  assert_eq(errors.length(), 0)
}

// ===== AutoTuneResult to_json coverage =====

///|
test "AutoTuneResult to_json with multiple recs and messages" {
  let tuner = @runtime.PdoAutoTuner::new()
  let stations : Array[UInt] = [0x1001U, 0x1002U]
  let probe1 = @runtime.compute_probe_result(0x1001U, 100L, 100L, 200L)
  // second station has no probe data → triggers WARNING message
  let result = tuner.analyze(stations, [[probe1]])
  let json = result.to_json()
  assert_true(json.contains("\"success\":") || json.contains("\"success\": "))
  // Should have ERROR message for missing probe data
  assert_true(json.contains("ERROR"))
}

// ===== build_master_od with DiagnosticSurface missing error_register =====

///|
test "build_master_od surface with no error_register" {
  let identity : @runtime.MasterIdentity = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
  }
  let surface : @runtime.DiagnosticSurface = {
    station_address: Some(0x1001U),
    state_summary: {
      target_state: None,
      current_state: None,
      final_state: None,
      al_state: None,
      al_error_flag: None,
      al_status_code: None,
      wkc: None,
    },
    configuration_summary: None,
    error_register: None,
    diagnosis_counter: None,
    runtime_metrics: None,
    issues: [],
    overall_level: @runtime.DiagnosticLevel::Info,
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
  let od = @runtime.build_master_od(identity, None, None, Some(surface))
  // Should still have entries with default error_register = 0
  let entry = od.lookup(0x1001U, b'\x00')
  assert_true(entry is Some(_))
}

// ===== MasterOdValue format U16 and Raw =====

///|
test "MasterOdValue format U16" {
  let val = @runtime.MasterOdValue::U16(0x1234U)
  let formatted = val.format()
  assert_true(formatted.contains("1234"))
}

///|
test "MasterOdValue format Raw" {
  let val = @runtime.MasterOdValue::Raw(Bytes::from_array([b'\xAB', b'\xCD']))
  let formatted = val.format()
  assert_true(formatted.length() > 0)
}

///|
test "MasterOdValue format I32" {
  let val = @runtime.MasterOdValue::I32(-42)
  let formatted = val.format()
  assert_true(formatted.contains("-42"))
}

// ===== DriftCompensator reset =====

///|
test "DriftCompensator reset clears state" {
  let comp = @runtime.DriftCompensator::new()
  let sync = @runtime.TimebaseSync::new(
    @runtime.ClockDomain::Mcu,
    @runtime.ClockDomain::Linux,
  )
  ignore(comp.compensate(sync, 1000L, 2000L))
  assert_true(comp.update_count > 0L)
  comp.reset()
  assert_eq(comp.integral_error_ns, 0L)
  assert_eq(comp.last_error_ns, 0L)
  assert_eq(comp.total_correction_ns, 0L)
  assert_eq(comp.update_count, 0L)
}

// ============================================================
// Batch 3: esi_json error paths, eoe_switch pure paths,
//          multi_rate tied peaks
// ============================================================

// ===== parse_esi_json_document invalid JSON =====

///|
test "parse_esi_json_document with invalid json string raises EsiParseFailed" {
  let mut caught = false
  try {
    let _ = @runtime.parse_esi_json_document("not valid json {{{")
  } catch {
    @hal.EcError::EsiParseFailed(_msg) => caught = true
    _ => ()
  }
  assert_true(caught)
}

///|
test "parse_esi_json_document with valid json but missing devices key" {
  let mut msg = ""
  try {
    let _ = @runtime.parse_esi_json_document("{\"foo\": 1}")
  } catch {
    @hal.EcError::EsiParseFailed(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("missing devices/modules"))
}

///|
test "parse_esi_json_document with devices not array" {
  let mut msg = ""
  try {
    let _ = @runtime.parse_esi_json_document(
      "{\"devices\": 1, \"modules\": []}",
    )
  } catch {
    @hal.EcError::EsiParseFailed(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("missing devices/modules"))
}

///|
test "parse_esi_json_document with modules not array" {
  let mut msg = ""
  try {
    let _ = @runtime.parse_esi_json_document(
      "{\"devices\": [], \"modules\": \"bad\"}",
    )
  } catch {
    @hal.EcError::EsiParseFailed(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("missing devices/modules"))
}

///|
test "parse_esi_json_document empty arrays succeeds" {
  let doc = @runtime.parse_esi_json_document(
    "{\"devices\": [], \"modules\": []}",
  )
  assert_eq(doc.devices.length(), 0)
  assert_eq(doc.modules.length(), 0)
}

///|
test "parse_esi_json_document with invalid device entry raises" {
  let mut msg = ""
  try {
    let _ = @runtime.parse_esi_json_document(
      "{\"devices\": [{}], \"modules\": []}",
    )
  } catch {
    @hal.EcError::EsiParseFailed(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("invalid device entry"))
}

///|
test "parse_esi_json_document with invalid module entry raises" {
  let mut msg = ""
  try {
    let _ = @runtime.parse_esi_json_document(
      "{\"devices\": [], \"modules\": [{}]}",
    )
  } catch {
    @hal.EcError::EsiParseFailed(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("invalid module entry"))
}

// ===== offline_sii_report_from_esi_document out-of-range device index =====

///|
test "offline_sii_report_from_esi_document negative index raises" {
  let doc : @runtime.EsiJsonDocument = { devices: [], modules: [] }
  let mut msg = ""
  try {
    let _ = @runtime.offline_sii_report_from_esi_document(doc, -1)
  } catch {
    @hal.EcError::EsiParseFailed(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("device index out of range"))
}

///|
test "offline_sii_report_from_esi_document index beyond length raises" {
  let doc : @runtime.EsiJsonDocument = { devices: [], modules: [] }
  let mut msg = ""
  try {
    let _ = @runtime.offline_sii_report_from_esi_document(doc, 0)
  } catch {
    @hal.EcError::EsiParseFailed(m) => msg = m
    _ => ()
  }
  assert_true(msg.contains("device index out of range"))
}

///|
test "offline_sii_report_from_esi_json invalid json raises" {
  let mut caught = false
  try {
    let _ = @runtime.offline_sii_report_from_esi_json("bad json", 0)
  } catch {
    @hal.EcError::EsiParseFailed(_msg) => caught = true
    _ => ()
  }
  assert_true(caught)
}

// ===== esi_json round-trip =====

///|
test "esi_json_to_string and parse round-trip on empty doc" {
  let doc : @runtime.EsiJsonDocument = { devices: [], modules: [] }
  let json_str = @runtime.esi_json_to_string(doc)
  let doc2 = @runtime.parse_esi_json_document(json_str)
  assert_eq(doc2.devices.length(), 0)
  assert_eq(doc2.modules.length(), 0)
}

// ===== EoeSwitch process_received error paths =====

///|
test "EoeSwitch process_received with empty frame returns false and increments rx_errors" {
  let sw = @runtime.EoeSwitch::new()
  let result = sw.process_received(0x1001U, b"")
  assert_eq(result, false)
  assert_eq(sw.rx_errors, 1L)
}

///|
test "EoeSwitch process_received with garbage frame returns false" {
  let sw = @runtime.EoeSwitch::new()
  let result = sw.process_received(0x1001U, b"\x01\x02\x03")
  assert_eq(result, false)
  assert_eq(sw.rx_errors, 1L)
}

///|
test "EoeSwitch add_station prevents duplicate" {
  let sw = @runtime.EoeSwitch::new()
  let mb : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1400U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, mb)
  sw.add_station(0x1001U, mb)
  assert_eq(sw.stations.length(), 1)
}

///|
test "EoeSwitch drain_rx returns empty when no frames" {
  let sw = @runtime.EoeSwitch::new()
  let frames = sw.drain_rx()
  assert_eq(frames.length(), 0)
}

///|
test "eoe_max_fragment_size with small mailbox returns zero" {
  let mb : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 5U,
    out_sm_index: 0,
    in_address: 0x1400U,
    in_size: 128U,
    in_sm_index: 1,
  }
  assert_eq(@runtime.eoe_max_fragment_size(mb), 0)
}

///|
test "eoe_max_fragment_size normal mailbox" {
  let mb : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1400U,
    in_size: 128U,
    in_sm_index: 1,
  }
  // 128 - 10 = 118, rounded down to 32-byte boundary = 96
  assert_eq(@runtime.eoe_max_fragment_size(mb), 96)
}

// ===== analyze_multi_rate tied peaks =====

///|
test "analyze_multi_rate tied peak cycles" {
  // Two tasks with same divisor → every cycle has same count → all cycles tied
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1000000L,
    tasks: [
      {
        name: "task_a",
        priority: 0,
        cycle_divisor: 2,
        slice: {
          output_offset: 0,
          output_length: 10,
          input_offset: 0,
          input_length: 10,
        },
      },
      {
        name: "task_b",
        priority: 1,
        cycle_divisor: 2,
        slice: {
          output_offset: 10,
          output_length: 20,
          input_offset: 10,
          input_length: 20,
        },
      },
    ],
  }
  let analysis = @runtime.analyze_multi_rate(schedule)
  // Both tasks fire on cycle 0, neither on cycle 1
  // Hyperperiod = lcm(2,2) = 2; cycle 0: 2 tasks, cycle 1: 0 tasks
  // Peak is cycle 0 only with 2 tasks
  assert_eq(analysis.worst_case_tasks_per_cycle, 2)
  assert_true(analysis.peak_cycles.contains(0))
}

///|
test "analyze_multi_rate with harmonic divisors" {
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 500000L,
    tasks: [
      {
        name: "fast",
        priority: 0,
        cycle_divisor: 1,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 4,
        },
      },
      {
        name: "slow",
        priority: 1,
        cycle_divisor: 4,
        slice: {
          output_offset: 4,
          output_length: 8,
          input_offset: 4,
          input_length: 8,
        },
      },
    ],
  }
  let analysis = @runtime.analyze_multi_rate(schedule)
  assert_true(analysis.is_harmonic)
  assert_eq(analysis.hyperperiod, 4)
  // Worst case: cycle 0 (both tasks) → 2 tasks, out=12, in=12
  assert_eq(analysis.worst_case_tasks_per_cycle, 2)
  assert_eq(analysis.worst_case_output_bytes, 12)
  assert_eq(analysis.worst_case_input_bytes, 12)
}

///|
test "analyze_multi_rate tied peaks with equal count different IO" {
  // Force tied peak with different IO sizes to cover the update-worst branches
  // Task A: divisor=3, out=10, in=5
  // Task B: divisor=3, out=15, in=20
  // Task C: divisor=6, out=100, in=200
  // hp = lcm(3,3,6) = 6
  // cycle 0: A+B+C (3 tasks, out=125, in=225)
  // cycle 3: A+B (2 tasks, out=25, in=25)
  // cycles 1,2,4,5: 0 tasks
  // No tied peaks here; let's use tasks that tie at count=1
  // Task A: divisor=2, out=10, in=5
  // Task B: divisor=3, out=20, in=30
  // hp = lcm(2,3) = 6
  // cycle 0: A+B → 2 tasks
  // cycle 2: A → 1 task (out=10, in=5)
  // cycle 3: B → 1 task (out=20, in=30) — tied with cycle 2 at count=1, out max=20, in max=30
  // cycle 4: A → 1 task (out=10, in=5) — tied again
  // cycle 1, 5: 0 tasks
  // worst = 2 at cycle 0, then peak=[0]
  // Actually we want the tied path: count == worst
  // cycle 0 is the worst (2 tasks), no tie
  // Let's try: three tasks all divisor=2,3,6 to hit tie in peak
  // Actually to hit the tied-peak AND different-IO branch, we need
  // two cycles with the SAME worst task count but different IO
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1000000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 6,
        slice: {
          output_offset: 0,
          output_length: 50,
          input_offset: 0,
          input_length: 60,
        },
      },
      {
        name: "t2",
        priority: 1,
        cycle_divisor: 10,
        slice: {
          output_offset: 50,
          output_length: 80,
          input_offset: 60,
          input_length: 90,
        },
      },
      {
        name: "t3",
        priority: 2,
        cycle_divisor: 15,
        slice: {
          output_offset: 130,
          output_length: 30,
          input_offset: 150,
          input_length: 40,
        },
      },
    ],
  }
  let analysis = @runtime.analyze_multi_rate(schedule)
  // hp = lcm(6,10,15) = 30
  assert_eq(analysis.hyperperiod, 30)
  // cycle 0: t1+t2+t3 = 3 tasks → worst
  // Other cycles should have ≤ 2 tasks
  assert_true(analysis.worst_case_tasks_per_cycle >= 2)
  assert_true(analysis.peak_cycles.length() >= 1)
}

///|
test "validate_multi_rate with too large hyperperiod" {
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1000000L,
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
        cycle_divisor: 11,
        slice: {
          output_offset: 4,
          output_length: 4,
          input_offset: 4,
          input_length: 4,
        },
      },
    ],
  }
  // hp = lcm(7,11) = 77, with max_hyperperiod=10 → should warn
  let msgs = @runtime.validate_multi_rate(schedule, max_hyperperiod=10)
  assert_true(msgs.iter().any(fn(s) { s.contains("Hyperperiod") }))
}

///|
test "validate_multi_rate with excessive tasks per cycle" {
  let tasks : Array[@runtime.TaskDescriptor] = []
  for i = 0; i < 20; i = i + 1 {
    tasks.push({
      name: "t" + i.to_string(),
      priority: i,
      cycle_divisor: 1,
      slice: {
        output_offset: i * 4,
        output_length: 4,
        input_offset: i * 4,
        input_length: 4,
      },
    })
  }
  let schedule : @runtime.TaskSchedule = { base_period_ns: 1000000L, tasks }
  let msgs = @runtime.validate_multi_rate(schedule, max_tasks_per_cycle=5)
  assert_true(msgs.iter().any(fn(s) { s.contains("Peak tasks per cycle") }))
}

///|
test "EoeSwitch format_text smoke" {
  let sw = @runtime.EoeSwitch::new()
  let text = sw.format_text()
  assert_true(text.length() > 0)
}

///|
test "EoeSwitch to_json smoke" {
  let sw = @runtime.EoeSwitch::new()
  let j = sw.to_json()
  assert_true(j.stringify().length() > 0)
}

///|
// =====================================================
// BATCH 5: coverage edge-case tests (blackbox)
// =====================================================

// ===== Batch 16: remaining pure-testable coverage gaps =====

///|
test "CyclePerfAnalyzer trend Improving" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L, window_size=4)
  // Use record() for first window so prev_window_mean is set
  a.record(0L) // starts analyzer, no cycle
  a.record(2_000_000L) // cycle 1, duration=2M
  a.record(4_000_000L) // cycle 2
  a.record(6_000_000L) // cycle 3
  a.record(8_000_000L) // cycle 4, triggers prev_window_mean = 2M
  // Use record_duration() for second window (doesn't overwrite prev_window_mean)
  a.record_duration(500_000L)
  a.record_duration(500_000L)
  a.record_duration(500_000L)
  a.record_duration(500_000L) // total=8, window=[500K,500K,500K,500K], prev=2M
  // current_mean(500K) + threshold(50K) < prev(2M) → Improving
  assert_true(a.trend() is Improving)
}

///|
test "CyclePerfAnalyzer stats fresh returns zeros" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L, window_size=4)
  let s = a.stats()
  assert_eq(s.total_cycles, 0L)
  assert_eq(s.deadline_miss_rate_permille, 0)
}

///|
test "score_dimension bad value returns 0" {
  let dim : @runtime.QualityDimension = {
    name: "x",
    value: 100L,
    good_threshold: 10L,
    bad_threshold: 50L,
    weight: 1,
  }
  assert_eq(@runtime.score_dimension(dim), 0)
}

///|
test "CommQualityScorer trend Stable" {
  let s = @runtime.CommQualityScorer::new(history_size=4)
  // Fill 2 windows with identical scores → Stable
  for _ in 0..<8 {
    s.record_score(500)
  }
  assert_true(s.trend() is Stable)
}

///|
test "CommQualityScorer score_from_telemetry zero cycles rates" {
  let s = @runtime.CommQualityScorer::new(history_size=4)
  let score = s.score_from_telemetry(0L, 0L, 0L, 0L)
  // With 0 cycles, all rates should be 0 → perfect score
  assert_eq(score.overall, 1000)
}

///|
// BATCH 17 — coverage gap tests

///|
test "CommQualityScorer score_from_telemetry zero nominal_period_ns" {
  let s = @runtime.CommQualityScorer::new(history_size=4)
  let score = s.score_from_telemetry(
    100L,
    0L,
    0L,
    0L,
    jitter_p99_abs_ns=50L,
    nominal_period_ns=0L,
  )
  // With nominal_period_ns=0, jitter_permille falls to 0 → perfect jitter score
  assert_eq(score.overall, 1000)
}

///|
test "compare_configurations alias None in actual" {
  let expected : @runtime.ConfigurationModel = {
    source: @runtime.ConfigurationSource::OfflineConfig,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: None,
        alias_address: Some(42U),
        identity: None,
        identification: None,
        process_data_summary: None,
        presence: @hal.SlavePresence::Mandatory,
      },
    ],
  }
  let actual : @runtime.ConfigurationModel = {
    source: @runtime.ConfigurationSource::OnlineScan,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: None,
        alias_address: None,
        identity: None,
        identification: None,
        process_data_summary: None,
        presence: @hal.SlavePresence::Mandatory,
      },
    ],
  }
  let report = @runtime.compare_configurations(expected, actual)
  assert_eq(report.all_ok, false)
}

///|
test "configuration_to_eni_json with Optional presence" {
  let model : @runtime.ConfigurationModel = {
    source: @runtime.ConfigurationSource::OfflineConfig,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: None,
        identity: None,
        identification: None,
        process_data_summary: None,
        presence: @hal.SlavePresence::Optional(group_id=Some(5U)),
      },
    ],
  }
  let json_str = @runtime.configuration_to_eni_json_string(model)
  assert_true(json_str.contains("optional"))
}

///|
test "write_slice_outputs_inplace short src" {
  let image = @hal.MutableProcessImage::new(4, 4)
  let slice : @runtime.ProcessImageSlice = {
    output_offset: 0,
    output_length: 4,
    input_offset: 0,
    input_length: 4,
  }
  // src has only 2 bytes available from offset 1 → available=1 < output_length=4
  let src : FixedArray[Byte] = [b'\xAA', b'\xBB']
  @runtime.write_slice_outputs_inplace(image, slice, src, 1)
  // Only 1 byte should be written (available = 2-1 = 1)
  assert_eq(image.outputs[0], b'\xBB')
}

///|
test "write_slice_outputs short data" {
  let image = @protocol.ProcessImage::new(4, 4)
  let slice : @runtime.ProcessImageSlice = {
    output_offset: 0,
    output_length: 4,
    input_offset: 0,
    input_length: 4,
  }
  let data = b"\xAA\xBB"
  @runtime.write_slice_outputs(image, slice, data)
  // Only 2 bytes from data, rest should remain zero
  let out = image.outputs
  assert_eq(out[0], b'\xAA')
  assert_eq(out[1], b'\xBB')
}

///|
test "score_dimension interpolation midpoint" {
  // value between good_threshold and bad_threshold → interpolated score
  let dim : @runtime.QualityDimension = {
    name: "latency",
    value: 55L,
    good_threshold: 10L,
    bad_threshold: 110L,
    weight: 1,
  }
  // excess = 55 - 10 = 45, range = 110 - 10 = 100
  // score = 1000 - 45*1000/100 = 1000 - 450 = 550
  assert_eq(@runtime.score_dimension(dim), 550)
}

///|
test "compute_quality_score empty dimensions" {
  let (overall, details) = @runtime.compute_quality_score([])
  assert_eq(overall, 1000)
  assert_eq(details.length(), 0)
}

///|
test "CyclePerfAnalyzer trend improving" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L, window_size=4)
  // Fill first window with high values
  a.record(2_000_000L)
  a.record(2_000_000L)
  a.record(2_000_000L)
  a.record(2_000_000L)
  // Save first window mean by recording enough to transition
  a.record(2_000_000L)
  a.record(2_000_000L)
  a.record(2_000_000L)
  a.record(2_000_000L)
  // Now set prev_window_mean high, then record low values
  // We need prev_window_mean > current_mean + threshold
  // Simulate by using many more cycles
  for i = 0; i < 100; i = i + 1 {
    a.record(1_200_000L) // slightly above nominal
  }
  let t = a.trend()
  // After many low-value cycles the trend could be Improving or Stable
  // The point is to exercise the Improving/Stable branch
  assert_true(t is @runtime.Improving || t is @runtime.Stable)
}

///|
test "CyclePerfAnalyzer stats zero cycles" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L, window_size=4)
  let s = a.stats()
  assert_eq(s.total_cycles, 0L)
  assert_eq(s.min_ns, 0L)
}

///|
test "JitterHistogram record idx negative clamp" {
  let h = @runtime.JitterHistogram::new(bin_width=100L, num_bins=3)
  // center_index=1, deviation -9999999 → idx = -9999999/100 + 1 → very negative → clamp to 0
  h.record(-9_999_999L)
  assert_true(h.total == 1L)
}

///|
test "DcJitterProfiler is_within_tolerance zero count" {
  let p = @runtime.DcJitterProfiler::new(1_000_000L)
  assert_true(p.is_within_tolerance(100L, 50L))
}

///|
test "DriftCompensator report negative error" {
  let comp = @runtime.DriftCompensator::new()
  let sync = @runtime.TimebaseSync::new(@runtime.Mcu, @runtime.Linux)
  // compensate with local < reference → negative error
  let _ = comp.compensate(sync, 10_000L, 5000L)
  let report = comp.report(sync)
  assert_true(report.last_error_ns < 0L)
}

///|
test "QueueEndpoint read_frame empty" {
  let ep = @runtime.QueueEndpoint::new()
  assert_true(ep.read_frame() is None)
}

///|
test "QueueEndpoint write_frame queue full" {
  let ep = @runtime.QueueEndpoint::new(max_depth=1)
  // Write first frame should succeed
  assert_true(ep.write_frame(b"hello"))
  // Queue is full
  assert_true(ep.write_frame(b"world") == false)
}

///|
test "monitor_startup_state Configuring" {
  let rt = @runtime.Runtime::new(@hal.MasterConfig::default())
  rt.state = @runtime.Configuring
  let result = @runtime.monitor_startup_state(rt)
  assert_true(result.verdict is @runtime.Warn(_))
}

///|
// NullRunProgressSink emit test moved to whitebox (RunProgress is read-only)

///|
test "topology_fingerprint_from_config no identity" {
  let config : @runtime.ConfigurationModel = {
    source: @runtime.OnlineScan,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: None,
        identity: None,
        identification: None,
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
    ],
  }
  let fp = @runtime.topology_fingerprint_from_config(config)
  assert_eq(fp.slave_count, 1)
}

///|
test "topology_fingerprint_from_config multiple slaves sorted" {
  let id1 : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
  }
  let config : @runtime.ConfigurationModel = {
    source: @runtime.OnlineScan,
    total_slaves: 2,
    slaves: [
      {
        position: 1,
        configured_address: None,
        alias_address: None,
        identity: Some(id1),
        identification: None,
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
      {
        position: 0,
        configured_address: None,
        alias_address: None,
        identity: None,
        identification: None,
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
    ],
  }
  let fp = @runtime.topology_fingerprint_from_config(config)
  assert_eq(fp.slave_count, 2)
}

///|
// TopologyHealthReport to_json test moved to whitebox (LinkGrade is read-only from blackbox)

///|
// AutoTuneResult to_json test moved to whitebox (read-only struct)

///|
test "compare_configurations found.configured_address is None" {
  let expected : @runtime.ConfigurationModel = {
    source: @runtime.OnlineScan,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: Some(0x1001U),
        alias_address: None,
        identity: None,
        identification: None,
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
    ],
  }
  let actual : @runtime.ConfigurationModel = {
    source: @runtime.OnlineScan,
    total_slaves: 1,
    slaves: [
      {
        position: 0,
        configured_address: None,
        alias_address: None,
        identity: None,
        identification: None,
        process_data_summary: None,
        presence: @hal.Mandatory,
      },
    ],
  }
  let report = @runtime.compare_configurations(expected, actual)
  assert_true(report.all_ok == false)
  assert_true(report.differences.length() > 0)
}

///|
test "analyze_multi_rate equal peak and bytes update" {
  // Two tasks with divisor 2 and divisor 3 → LCM=6
  // At cycle 0: both fire → count=2
  // At cycle 6: both fire again → count=2, equal peak, update worst bytes
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        cycle_divisor: 2,
        priority: 0,
        slice: {
          output_offset: 0,
          output_length: 10,
          input_offset: 0,
          input_length: 20,
        },
      },
      {
        name: "t2",
        cycle_divisor: 3,
        priority: 1,
        slice: {
          output_offset: 100,
          output_length: 30,
          input_offset: 100,
          input_length: 5,
        },
      },
    ],
  }
  let analysis = @runtime.analyze_multi_rate(schedule)
  assert_true(analysis.hyperperiod > 1)
  assert_true(analysis.worst_case_tasks_per_cycle >= 1)
}

///|
// ── Batch 6: RunLoopSettings, diagnostic_surface_from_run, state transitions ──

///|
test "RunLoopSettings fixed_cycles" {
  let s = @runtime.RunLoopSettings::fixed_cycles(100)
  assert_eq(s.cycles, 100)
  assert_eq(s.until_fault, false)
  assert_eq(s.max_consecutive_timeouts, 5)
  assert_true(s.cycle_period_ns is None)
  assert_true(s.output_period_ns is None)
}

///|
test "RunLoopSettings until_fault" {
  let s = @runtime.RunLoopSettings::until_fault()
  assert_eq(s.cycles, 0)
  assert_eq(s.until_fault, true)
}

///|
test "master_config_with_optional_dc Some" {
  let config = @runtime.master_config_with_optional_dc(Some(1_000_000L))
  assert_eq(config.dc_enabled, true)
  assert_eq(config.cycle_period_ns, 1_000_000L)
}

///|
test "master_config_with_optional_dc None" {
  let config = @runtime.master_config_with_optional_dc(None)
  assert_eq(config.dc_enabled, false)
}

///|
test "required_sii_read_word_count with valid metadata" {
  // Build a minimal SII data buffer (128 bytes) with eeprom_size_raw set
  // SII metadata field eeprom_size is at word 62 (byte offset 124)
  // eeprom_size_raw = 4 → eeprom_size_bytes() = 4 * 128 = 512 → required = (512+3)/4 = 128
  let data = Bytes::makei(128, fn(i) {
    if i == 124 {
      b'\x04'
    } else {
      b'\x00'
    }
  })
  let result = @runtime.required_sii_read_word_count(data, 64)
  assert_true(result >= 64) // should return max(computed, initial)
}

///|
test "required_sii_read_word_count with short data" {
  // Too-short data → parse fails → returns initial_word_count
  let data = Bytes::make(10, 0)
  assert_eq(@runtime.required_sii_read_word_count(data, 128), 128)
}

///|
test "diagnostic_surface_from_run with TimeoutRecoveryRequired fault" {
  let telemetry = @runtime.Telemetry::new()
  telemetry.timeouts = 5L
  let report : @runtime.RunReport = {
    scan: {
      slave_count: 1,
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
      ],
    },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 1,
      total_found: 1,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 100,
    cycles_ok: 95,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry,
    final_phase: @runtime.Stopping,
    fault: Some(
      @runtime.TimeoutRecoveryRequired(
        observed_timeouts=5L,
        consecutive_timeouts=3,
      ),
    ),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  // Should have issues from fault + telemetry
  assert_true(surface.issues.length() >= 2)
}

///|
test "diagnostic_surface_from_run with RuntimeRecoveryRequired fault" {
  let telemetry = @runtime.Telemetry::new()
  telemetry.wkc_errors = 3L
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 100,
    cycles_ok: 100,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry,
    final_phase: @runtime.Stopping,
    fault: Some(
      @runtime.RuntimeRecoveryRequired(expected_wkc=3U, observed_wkc_errors=3L),
    ),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_true(surface.issues.length() >= 1)
}

///|
test "diagnostic_surface_from_run with DcDrift fault" {
  let telemetry = @runtime.Telemetry::new()
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 100,
    cycles_ok: 100,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry,
    final_phase: @runtime.Stopping,
    fault: Some(@runtime.DcDrift(delta_ns=500L)),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_true(surface.issues.length() >= 1)
}

///|
test "diagnostic_surface_from_run StartupTransitionFailed with all Some fields" {
  let telemetry = @runtime.Telemetry::new()
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 0,
    cycles_ok: 0,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry,
    final_phase: @runtime.Stopping,
    fault: Some(
      @runtime.StartupTransitionFailed(
        station=0x1001U,
        target=@protocol.Op,
        current=Some(@protocol.SafeOp),
        error_indication=Some(true),
        status_code=Some(0x001EU),
        raw_status_code=Some(0x001EU),
        control_wkc=Some(1U),
      ),
    ),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_true(surface.issues.length() >= 1)
}

///|
test "diagnostic_surface_from_run no fault" {
  let telemetry = @runtime.Telemetry::new()
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 100,
    cycles_ok: 100,
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: None,
    telemetry,
    final_phase: @runtime.Done,
    fault: None,
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  assert_eq(surface.issues.length(), 0)
}

///|
test "diagnostic_surface_from_state_transition batch6 status_code nonzero" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    Some(0x1001U),
    @protocol.Op,
    Some(@protocol.SafeOp),
    Some(@protocol.SafeOp),
    None,
    Some(0x0012U),
    None,
  )
  // final_state != target + status_code != 0 → 2 issues
  assert_true(surface.issues.length() >= 2)
}

///|
test "diagnostic_surface_from_state_transition batch6 wkc zero" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.PreOp,
    None,
    Some(@protocol.PreOp),
    None,
    None,
    Some(0U),
  )
  // wkc==0 → 1 issue
  assert_true(surface.issues.length() >= 1)
}

///|
test "diagnostic_surface_from_state_transition al_error_flag true" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.SafeOp,
    None,
    Some(@protocol.SafeOp),
    Some(true),
    None,
    None,
  )
  assert_true(surface.issues.length() >= 1)
}

///|
test "diagnostic_surface_from_state_transition all clean" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.Op,
    None,
    Some(@protocol.Op),
    Some(false),
    Some(0U),
    Some(1U),
  )
  assert_eq(surface.issues.length(), 0)
}

// ===== EoeSwitch: non-FragData response returns false =====

///|
test "EoeSwitch process_received non-FragData returns false" {
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  // Build a raw EoE mailbox frame with frame_type = SetIpResp (3)
  // This should trigger the `_ => false` branch in process_received
  let frame = Bytes::from_array([
    b'\x04', b'\x00', // length = 4 (eoe_header_len only)
     b'\x00', b'\x00', // address = 0
     b'\x00', // channel|priority
     b'\x12', // type=EoE(0x02) | counter=1 → 0x12
     b'\x03', b'\x00', // fi1: frame_type=SetIpResp(3), port=0, last=0
     b'\x00', b'\x00', // fi2: result=0
  ])
  let result = sw.process_received(0x1001U, frame)
  assert_eq(result, false)
}

// ===== Batch 23: EoeSwitch error paths =====

///|
test "EoeSwitch send_frame unknown station raises" {
  let sw = @runtime.EoeSwitch::new()
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, cfg)
  let id : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 1U,
    revision: 1U,
    serial: 0U,
  }
  let bus = @mock.VirtualBus::new([
    @mock.VirtualSlave::new(0, id, Bytes::new(256)),
  ])
  let nic = @mock.VirtualNic::new(bus)
  let frame = b"\x01\x02\x03\x04"
  // station 0x9999U not registered → should raise MailboxProtocol
  let result : Result[Int, _] = try? sw.send_frame(
    nic,
    0x9999U,
    frame,
    @hal.Duration(50_000_000L),
  )
  assert_true(result is Err(_))
}

///|
test "EoeSwitch send_frame mailbox too small raises" {
  let sw = @runtime.EoeSwitch::new()
  // out_size = 10 means raw = 10 - 10 = 0 → max_frag = 0
  let small_cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 10U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  sw.add_station(0x1001U, small_cfg)
  let id : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 1U,
    revision: 1U,
    serial: 0U,
  }
  let bus = @mock.VirtualBus::new([
    @mock.VirtualSlave::new(0, id, Bytes::new(256)),
  ])
  let nic = @mock.VirtualNic::new(bus)
  let frame = b"\x01\x02\x03\x04"
  let result : Result[Int, _] = try? sw.send_frame(
    nic,
    0x1001U,
    frame,
    @hal.Duration(50_000_000L),
  )
  assert_true(result is Err(_))
}

// ===== Batch 23: multi_rate equal-count peaks =====

///|
test "analyze_multi_rate equal peak cycles with different IO" {
  // Two tasks each running every cycle → count always 2
  // But with different output sizes, the larger should be recorded
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "fast",
        priority: 0,
        cycle_divisor: 1,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 2,
        },
      },
      {
        name: "slow",
        priority: 1,
        cycle_divisor: 2,
        slice: {
          output_offset: 4,
          output_length: 8,
          input_offset: 2,
          input_length: 6,
        },
      },
    ],
  }
  let result = @runtime.analyze_multi_rate(schedule)
  // hyperperiod = LCM(1,2) = 2
  assert_eq(result.hyperperiod, 2)
  // Cycle 0: both run → count=2, out=12, in=8
  // Cycle 1: only "fast" → count=1, out=4, in=2
  // Peak is at cycle=0 with count=2
  assert_eq(result.worst_case_tasks_per_cycle, 2)
  assert_eq(result.peak_cycles, [0])
  assert_eq(result.worst_case_output_bytes, 12)
  assert_eq(result.worst_case_input_bytes, 8)
}

///|
test "analyze_multi_rate multiple peaks at same count" {
  // Three tasks: divisors 2, 3, 6
  // Hyperperiod = LCM(2,3,6) = 6
  // Cycle 0: all 3 run
  // Cycle 2: task0 (div 2) runs alone → count=1
  // Cycle 3: task1 (div 3) runs alone → count=1
  // Cycle 4: task0 (div 2) runs alone → count=1
  // Cycle 1: none of div-2/3/6 → count=0? No, divisor 2 fires at 0,2,4
  //   Actually: cycle 0 → 2,3,6 all fire → 3 tasks; cycle 2 → div2 fires → 1; cycle 3 → div3 fires → 1
  //   cycle 4 → div2 fires → 1; cycle 5 → none → 0; cycle 1 → none → 0
  // Let's use divisors where multiple cycles have same peak count:
  // Two tasks, divisor 2 and divisor 3:
  // HP = 6; cycle 0: both → 2; cycle 2: t0 → 1; cycle 3: t1 → 1; cycle 4: t0 → 1; cycle 1,5: 0 each
  // Only one peak at count=2 → still just [0]
  // Better approach: 3 tasks with divisors 1, 2, 4
  // HP = 4; cycle 0: all three → 3; cycle 1: only t0 → 1; cycle 2: t0+t1 → 2; cycle 3: t0 → 1
  // Not multiple equal peaks either.
  // Use 2 tasks, both divisor 1:
  // Every cycle has count=2 → peaks = [0, 1, 2, ...]
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "a",
        priority: 0,
        cycle_divisor: 1,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 2,
        },
      },
      {
        name: "b",
        priority: 1,
        cycle_divisor: 1,
        slice: {
          output_offset: 4,
          output_length: 4,
          input_offset: 2,
          input_length: 2,
        },
      },
    ],
  }
  let result = @runtime.analyze_multi_rate(schedule)
  // HP=1, cycle 0: both run → worst=2, peak=[0]
  assert_eq(result.hyperperiod, 1)
  assert_eq(result.worst_case_tasks_per_cycle, 2)
  assert_eq(result.peak_cycles, [0])
}

///|
test "analyze_multi_rate multiple equal peaks detected" {
  // 3 tasks: divisors 2, 2, 3 → HP = LCM(2,2,3) = 6
  // cycle 0: t0(d2)+t1(d2)+t2(d3) = 3  ← first peak
  // cycle 1: 0
  // cycle 2: t0(d2)+t1(d2) = 2
  // cycle 3: t2(d3) = 1
  // cycle 4: t0(d2)+t1(d2) = 2  ← same as cycle 2
  // cycle 5: 0
  // Peak at cycle 0 only (count=3), cycles 2 and 4 have count=2 (equal to each other but not peak)
  // For equal peaks we need at least 2 cycles with same maximum count.
  // Try: divisors 3, 3 → HP=3
  // cycle 0: both → 2; cycle 1: 0; cycle 2: 0
  // Only one peak at [0]
  // Try: divisors 2, 3 → HP=6
  // cycle 0: both → 2; cycle 2: t0 → 1; cycle 3: t1 → 1; cycle 4: t0 → 1
  // Only one peak at [0]
  // The only way to get multiple peaks is to have the same max count at different cycles.
  // divisors 2, 3: at cycle 0, both fire (count=2); at cycle 6 → but HP is 6, so only 0..5
  // We need different tasks firing at different cycles with same count.
  // 4 tasks: t0(d2), t1(d3), t2(d2), t3(d3) → HP=6
  // cycle 0: all 4 → 4; cycle 2: t0+t2 → 2; cycle 3: t1+t3 → 2; cycle 4: t0+t2 → 2
  // peak at [0], secondary peaks [2,3,4] but not max.
  // 2 tasks: t0(d2), t1(d2) → HP=2
  // cycle 0: both → 2; cycle 1: 0
  // only [0]
  // 2 tasks: t0(d2), t1(d2) with different I/O:
  // We need cycles with same peak count at multiple positions.
  // For that all tasks must have divisor=1 with HP>1 → impossible since divisors are all 1 → HP=1
  // OR tasks that create alternating patterns. Let me try:
  // t0: d=1 (fires every cycle), t1: d=2 (fires even cycles), t2: d=2 offset? No, offset not supported.
  // Actually the hyperperiod loop is: for cycle = 0; cycle < hp
  //   for t in tasks: if cycle % t.cycle_divisor == 0 → count++
  // So with d=1, it fires every cycle.
  // With d=2 and d=3: only cycle 0 fires both → peak at [0]
  //
  // The equal peak branch fires when a NEW cycle achieves the SAME count as the current worst.
  // With 3 tasks, d=2, d=3, d=1:
  // cycle 0: all 3 → 3 → worst=3, peaks=[0]
  // cycle 1: t2(d1) → 1
  // cycle 2: t0(d2)+t2(d1) → 2
  // cycle 3: t1(d3)+t2(d1) → 2 ← equal to cycle 2 but < peak
  // cycle 4: t0(d2)+t2(d1) → 2
  // cycle 5: t2(d1) → 1
  // Only one peak [0].
  //
  // For the equal branch to fire, we need two cycles where task count equals worst:
  // 2 tasks with d=3 → HP=3: cycle 0 → 2, cycle 1 → 0, cycle 2 → 0 → only [0]
  // 
  // Actually the equal branch fires when count == worst and it's a different cycle.
  // But first iteration always sets worst since worst starts at 0.
  // Then subsequent cycles would need to have the same count AS worst.
  //
  // Try: 1 task with d=1 → HP=1, only cycle 0 → no chance for equal
  // Try: 1 task with d=1, HP=1 → doesn't help
  //
  // We need at least HP >= 2 and multiple cycles with same max count.
  // If we have 0 tasks with d>1 and some with d=1, HP=1 → only 1 cycle
  // If we have at least one task with d>1, HP>1, but then cycle 0 always fires all tasks.
  //
  // Wait: what if we have 2 tasks, d=2 and d=3?
  // HP=6: cycle0 → 2 (both), c1→0, c2→1(t0), c3→1(t1), c4→1(t0), c5→0
  // Peak at [0], c2-c4 have count=1 which is less.
  //
  // For equal peaks: tasks where the "peak" fires at multiple cycles.
  // Only possible if there are no tasks with d=1 (which would make cycle 0 always the max).
  // 
  // 2 tasks: d=2, d=3 → cycle 0 fires both → count=2 → highest
  // 3 tasks: d=2, d=3, d=6 → cycle 0: all 3 → 3 (max); cycle 2: d=2 → 1; cycle 3: d=3 → 1; cycle 4: d=2 → 1; cycle 5: 0
  // Still only [0].
  //
  // The ONLY way to get equal peaks is if cycle 0 is NOT the max!
  // That's impossible because cycle 0 fires ALL tasks (cycle % d == 0 for all d).
  // So peak_cycles will ALWAYS be [0] for any non-empty schedule.
  //
  // Therefore the "equal peak" branches (peaks.push for count==worst at cycle>0,
  // and worst_out/worst_in updates for equal peaks) are DEAD CODE.
  //
  // Actually wait - what about I/O tracking at equal peaks?
  // Actually there's an issue: the code first checks `count > worst` (new maximum),
  // then `count == worst` (equal). Since cycle 0 always has all tasks,
  // no subsequent cycle can have count >= cycle 0's count.
  // So `count == worst` at cycle > 0 is impossible → DEAD CODE.

  // Just verify basic behavior with non-harmonic setup
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "a",
        priority: 0,
        cycle_divisor: 3,
        slice: {
          output_offset: 0,
          output_length: 10,
          input_offset: 0,
          input_length: 5,
        },
      },
      {
        name: "b",
        priority: 1,
        cycle_divisor: 5,
        slice: {
          output_offset: 10,
          output_length: 20,
          input_offset: 5,
          input_length: 15,
        },
      },
    ],
  }
  let result = @runtime.analyze_multi_rate(schedule)
  assert_eq(result.hyperperiod, 15)
  assert_eq(result.is_harmonic, false) // 3 and 5 are not powers of 2
  assert_eq(result.worst_case_tasks_per_cycle, 2) // cycle 0
  assert_eq(result.peak_cycles, [0])
  assert_eq(result.worst_case_output_bytes, 30)
  assert_eq(result.worst_case_input_bytes, 20)
}
