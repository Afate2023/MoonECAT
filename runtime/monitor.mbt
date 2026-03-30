///|
/// Monitor: consecutive timeout threshold.
/// Emits Fail when consecutive_timeouts >= max, Warn when > 0.
pub fn monitor_consecutive_timeouts(rt : Runtime) -> MonitorResult {
  let name = "consecutive_timeouts"
  if rt.consecutive_timeouts >= rt.max_consecutive_timeouts {
    {
      name,
      verdict: Fail(
        "consecutive timeouts " +
        rt.consecutive_timeouts.to_string() +
        " >= threshold " +
        rt.max_consecutive_timeouts.to_string(),
      ),
    }
  } else if rt.consecutive_timeouts > 0 {
    {
      name,
      verdict: Warn(
        "consecutive timeouts " + rt.consecutive_timeouts.to_string(),
      ),
    }
  } else {
    { name, verdict: Pass }
  }
}

///|
/// Monitor: WKC error threshold.
/// Emits Fail when consecutive_wkc_errors >= max, Warn when > 0.
pub fn monitor_wkc_errors(rt : Runtime) -> MonitorResult {
  let name = "wkc_errors"
  if rt.consecutive_wkc_errors >= rt.max_wkc_errors {
    {
      name,
      verdict: Fail(
        "consecutive WKC errors " +
        rt.consecutive_wkc_errors.to_string() +
        " >= threshold " +
        rt.max_wkc_errors.to_string(),
      ),
    }
  } else if rt.consecutive_wkc_errors > 0 {
    {
      name,
      verdict: Warn(
        "consecutive WKC errors " + rt.consecutive_wkc_errors.to_string(),
      ),
    }
  } else {
    { name, verdict: Pass }
  }
}

///|
/// Monitor: DC drift detection.
/// Emits Fail when dc_state is Drifting.
pub fn monitor_dc_drift(rt : Runtime) -> MonitorResult {
  let name = "dc_drift"
  match rt.dc_state {
    Drifting(delta_ns) =>
      {
        name,
        verdict: Fail("DC drift detected: delta_ns=" + delta_ns.to_string()),
      }
    _ => { name, verdict: Pass }
  }
}

///|
/// Monitor: startup state verification.
/// Emits Block when runtime is in Error state, Warn when not Running.
pub fn monitor_startup_state(rt : Runtime) -> MonitorResult {
  let name = "startup_state"
  match rt.state {
    Error(e) =>
      { name, verdict: Block("runtime in error state: " + e.to_string()) }
    Running(_) => { name, verdict: Pass }
    Idle => { name, verdict: Warn("runtime is idle, not yet started") }
    Scanning => { name, verdict: Warn("runtime is scanning") }
    Configuring => { name, verdict: Warn("runtime is configuring") }
    Stopping => { name, verdict: Warn("runtime is stopping") }
  }
}

///|
/// Monitor: PDO configuration readiness.
/// Emits Block when PDO context is not configured,
/// Warn when expected_wkc is zero.
pub fn monitor_pdo_configured(rt : Runtime) -> MonitorResult {
  let name = "pdo_configured"
  match rt.pdo_ctx {
    None => { name, verdict: Block("PDO context not configured") }
    Some(_) =>
      if rt.expected_wkc == 0U {
        { name, verdict: Warn("expected WKC is zero") }
      } else {
        { name, verdict: Pass }
      }
  }
}

///|
/// Monitor: cycle success rate.
/// Emits Fail when wkc_errors / cycles exceeds threshold.
pub fn monitor_cycle_success_rate(
  rt : Runtime,
  min_success_ratio_pct : Int,
) -> MonitorResult {
  let name = "cycle_success_rate"
  if rt.telemetry.cycles == 0L {
    return { name, verdict: Pass }
  }
  let total = rt.telemetry.cycles
  let errors = rt.telemetry.wkc_errors + rt.telemetry.timeouts
  let success_pct = ((total - errors) * 100L / total).to_int()
  if success_pct < min_success_ratio_pct {
    {
      name,
      verdict: Fail(
        "success rate " +
        success_pct.to_string() +
        "% < " +
        min_success_ratio_pct.to_string() +
        "%",
      ),
    }
  } else {
    { name, verdict: Pass }
  }
}

///|
/// Run all built-in monitors against the current runtime state.
/// Returns individual results plus the aggregate worst verdict.
pub fn run_monitors(rt : Runtime) -> (Array[MonitorResult], Verdict) {
  let results = [
    monitor_consecutive_timeouts(rt),
    monitor_wkc_errors(rt),
    monitor_dc_drift(rt),
    monitor_startup_state(rt),
    monitor_pdo_configured(rt),
    monitor_cycle_success_rate(rt, 80),
  ]
  let worst = worst_verdict(results)
  (results, worst)
}
