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
  if not(self.is_open) {
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
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for SiiIdentityNic with close(self) {
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
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  data.length()
}

///|
pub impl @hal.Nic for TimeoutNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
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
  assert_true(not(rt.needs_recovery()))
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
  t.reset()
  assert_eq(t.cycles, 0L)
  assert_eq(t.tx_frames, 0L)
  assert_eq(t.rx_frames, 0L)
  assert_eq(t.timeouts, 0L)
  assert_eq(t.retries, 0L)
  assert_eq(t.wkc_errors, 0L)
  assert_eq(t.dc_delay_updates, 0L)
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
  assert_true(
    not(@protocol.EsmState::Init.can_transition(@protocol.EsmState::Op)),
  )
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
    telemetry: @runtime.Telemetry::new(),
    final_phase: @runtime.Done,
  }
  let text = report.format()
  assert_true(text.contains("MoonECAT Run Report"))
  assert_true(text.contains("Slaves found: 0"))
  assert_true(text.contains("Validation: PASS"))
  assert_true(text.contains("0/0 OK"))
  assert_true(text.contains("Phase: Done"))
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
    telemetry: tel,
    final_phase: @runtime.Done,
  }
  let text = report.format()
  assert_true(text.contains("Slaves found: 2"))
  assert_true(text.contains("97/100 OK"))
  assert_true(text.contains("tx=100"))
  assert_true(text.contains("timeouts=2"))
  assert_true(text.contains("irq_events=4"))
  assert_true(text.contains("dc_delay_updates=2"))
  assert_true(text.contains("wkc_errors=3"))
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
test "run with empty bus skips ESM broadcasts" {
  let nic = RejectEmptyBusTransitionNic::new()
  let config = @hal.MasterConfig::default()
  let expected : Array[@hal.SlaveConfig] = []
  let ctx : @protocol.PdoContext = {
    image: @protocol.ProcessImage::new(0, 0),
    mappings: [],
    logical_base: 0U,
    logical_size: 0,
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
  assert_eq(nic.state_transition_attempts, 0)
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
