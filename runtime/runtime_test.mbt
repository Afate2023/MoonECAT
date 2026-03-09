///|
test "Telemetry initializes to zero" {
  let t = @runtime.Telemetry::new()
  assert_eq(t.cycles, 0L)
  assert_eq(t.tx_frames, 0L)
  assert_eq(t.rx_frames, 0L)
  assert_eq(t.timeouts, 0L)
  assert_eq(t.retries, 0L)
  assert_eq(t.wkc_errors, 0L)
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
