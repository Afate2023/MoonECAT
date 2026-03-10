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
    vendor_id: 0x0002U,
    product_code: 0x04D2U,
    revision: 0x0001U,
    serial: 0x1234U,
    identification: 0U,
  }
  let r2 : @runtime.SlaveReport = {
    position: 0,
    station_address: 0x1001U,
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
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
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
      configured_address: 0x1001U,
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
      configured_address: 0x1002U,
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
      configured_address: 0x1001U,
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
      configured_address: 0x1001U,
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
      configured_address: 0x1001U,
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
      configured_address: 0x1001U,
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
      configured_address: 0x1001U,
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
      configured_address: 0x1001U,
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
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
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
      configured_address: 0x1001U,
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
      configured_address: 0x1001U,
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
test "validate: matches by position even when expected order differs" {
  let scan : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        vendor_id: 0x0002U,
        product_code: 0x04D2U,
        revision: 0x0001U,
        serial: 0x1234U,
        identification: 0U,
      },
      {
        position: 1,
        station_address: 0x1002U,
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
      configured_address: 0x1002U,
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
      configured_address: 0x1001U,
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
      configured_address: 0x1002U,
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
    total_expected: 1,
    total_found: 1,
    results: [@runtime.Ok],
    all_ok: true,
  }
  let text = report.format()
  assert_true(text.contains("PASS"))
  assert_true(text.contains("[OK]"))
}

///|
test "ValidateReport format shows FAIL with details" {
  let report : @runtime.ValidateReport = {
    total_expected: 2,
    total_found: 1,
    results: [@runtime.Ok, @runtime.Missing(position=1)],
    all_ok: false,
  }
  let text = report.format()
  assert_true(text.contains("FAIL"))
  assert_true(text.contains("[MISSING]"))
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
    validation: { total_expected: 0, total_found: 0, results: [], all_ok: true },
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
    validation: { total_expected: 2, total_found: 2, results: [], all_ok: true },
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
      configured_address: 0x1001U,
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
