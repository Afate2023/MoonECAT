///|
test "Verdict severity ordering" {
  assert_eq(@runtime.Verdict::Pass.severity(), 0)
  assert_eq(@runtime.Verdict::Warn("w").severity(), 1)
  assert_eq(@runtime.Verdict::Fail("f").severity(), 2)
  assert_eq(@runtime.Verdict::Block("b").severity(), 3)
}

///|
test "Verdict::is_passing" {
  assert_true(@runtime.Verdict::Pass.is_passing())
  assert_true(@runtime.Verdict::Warn("w").is_passing())
  assert_true(!@runtime.Verdict::Fail("f").is_passing())
  assert_true(!@runtime.Verdict::Block("b").is_passing())
}

///|
test "worst_verdict selects highest severity" {
  let r1 : @runtime.MonitorResult = {
    name: "a",
    verdict: @runtime.Verdict::Pass,
  }
  let r2 : @runtime.MonitorResult = {
    name: "b",
    verdict: @runtime.Verdict::Warn("w"),
  }
  let r3 : @runtime.MonitorResult = {
    name: "c",
    verdict: @runtime.Verdict::Pass,
  }
  assert_true(@runtime.worst_verdict([r1, r2, r3]) is Warn(_))
  let r4 : @runtime.MonitorResult = {
    name: "a",
    verdict: @runtime.Verdict::Pass,
  }
  let r5 : @runtime.MonitorResult = {
    name: "b",
    verdict: @runtime.Verdict::Fail("f"),
  }
  let r6 : @runtime.MonitorResult = {
    name: "c",
    verdict: @runtime.Verdict::Block("b"),
  }
  assert_true(@runtime.worst_verdict([r4, r5, r6]) is Block(_))
}

///|
test "worst_verdict empty results returns Pass" {
  let results : Array[@runtime.MonitorResult] = []
  assert_eq(@runtime.worst_verdict(results), @runtime.Verdict::Pass)
}

///|
test "monitor_consecutive_timeouts: pass when zero" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let r = @runtime.monitor_consecutive_timeouts(rt)
  assert_eq(r.name, "consecutive_timeouts")
  assert_eq(r.verdict, @runtime.Verdict::Pass)
}

///|
test "monitor_consecutive_timeouts: warn when partial" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.record_timeout()
  rt.record_timeout()
  let r = @runtime.monitor_consecutive_timeouts(rt)
  assert_true(r.verdict is Warn(_))
}

///|
test "monitor_consecutive_timeouts: fail when threshold reached" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  // default max_consecutive_timeouts = 5
  for _i = 0; _i < 5; _i = _i + 1 {
    rt.record_timeout()
  }
  let r = @runtime.monitor_consecutive_timeouts(rt)
  assert_true(r.verdict is Fail(_))
}

///|
test "monitor_wkc_errors: pass when zero" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let r = @runtime.monitor_wkc_errors(rt)
  assert_eq(r.verdict, @runtime.Verdict::Pass)
}

///|
test "monitor_wkc_errors: fail when threshold reached" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  // Simulate consecutive WKC errors by directly setting the counter
  rt.consecutive_wkc_errors = 5
  let r = @runtime.monitor_wkc_errors(rt)
  assert_true(r.verdict is Fail(_))
}

///|
test "monitor_dc_drift: pass when disabled" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let r = @runtime.monitor_dc_drift(rt)
  assert_eq(r.verdict, @runtime.Verdict::Pass)
}

///|
test "monitor_dc_drift: fail when drifting" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.dc_state = @hil.DcState::Drifting(42L)
  let r = @runtime.monitor_dc_drift(rt)
  assert_true(r.verdict is Fail(_))
}

///|
test "monitor_startup_state: pass when running" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  let r = @runtime.monitor_startup_state(rt)
  assert_eq(r.verdict, @runtime.Verdict::Pass)
}

///|
test "monitor_startup_state: block when error" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.set_state(@runtime.RuntimeState::Error(@hal.EcError::RecvTimeout))
  let r = @runtime.monitor_startup_state(rt)
  assert_true(r.verdict is Block(_))
}

///|
test "monitor_startup_state: warn when idle" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let r = @runtime.monitor_startup_state(rt)
  assert_true(r.verdict is Warn(_))
}

///|
test "monitor_pdo_configured: block when not configured" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let r = @runtime.monitor_pdo_configured(rt)
  assert_true(r.verdict is Block(_))
}

///|
test "monitor_cycle_success_rate: pass when no cycles" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  let r = @runtime.monitor_cycle_success_rate(rt, 80)
  assert_eq(r.verdict, @runtime.Verdict::Pass)
}

///|
test "monitor_cycle_success_rate: fail when below threshold" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.telemetry.cycles = 10L
  rt.telemetry.wkc_errors = 5L
  rt.telemetry.timeouts = 3L
  // success = (10 - 8) / 10 = 20% < 80%
  let r = @runtime.monitor_cycle_success_rate(rt, 80)
  assert_true(r.verdict is Fail(_))
}

///|
test "monitor_cycle_success_rate: pass when above threshold" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.telemetry.cycles = 100L
  rt.telemetry.wkc_errors = 2L
  rt.telemetry.timeouts = 1L
  // success = (100 - 3) / 100 = 97% >= 80%
  let r = @runtime.monitor_cycle_success_rate(rt, 80)
  assert_eq(r.verdict, @runtime.Verdict::Pass)
}

///|
test "run_monitors returns all results and worst verdict" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  // Idle state with no PDO → worst should be Block (pdo_configured)
  let (results, worst) = @runtime.run_monitors(rt)
  assert_eq(results.length(), 6)
  assert_true(worst is Block(_))
}

///|
test "run_monitors all pass in healthy running state" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.set_state(@runtime.RuntimeState::Running(@runtime.RunMode::FreeRun))
  // Configure a dummy PDO context
  let ctx = @protocol.PdoContext::build([], 0x1000U)
  rt.configure_pdo(ctx, 3U)
  let (results, worst) = @runtime.run_monitors(rt)
  assert_eq(results.length(), 6)
  assert_eq(worst, @runtime.Verdict::Pass)
}

// ===== Batch 16: monitor_startup_state Stopping =====

///|
test "monitor_startup_state Stopping yields Warn" {
  let config = @hal.MasterConfig::default()
  let rt = @runtime.Runtime::new(config)
  rt.set_state(@runtime.RuntimeState::Stopping)
  let r = @runtime.monitor_startup_state(rt)
  assert_true(r.verdict is Warn(_))
}
