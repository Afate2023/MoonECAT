///|
test "verdict_to_diagnostic_level maps Pass and Warn to Info" {
  assert_eq(@runtime.verdict_to_diagnostic_level(@runtime.Pass), @runtime.Info)
  assert_eq(
    @runtime.verdict_to_diagnostic_level(@runtime.Warn("w")),
    @runtime.Info,
  )
}

///|
test "verdict_to_diagnostic_level maps Fail to Degrade and Block to Block" {
  assert_eq(
    @runtime.verdict_to_diagnostic_level(@runtime.Fail("f")),
    @runtime.Degrade,
  )
  assert_eq(
    @runtime.verdict_to_diagnostic_level(@runtime.Block("b")),
    @runtime.Block,
  )
}

///|
test "monitor_result_to_issue returns None for Pass" {
  let r : @runtime.MonitorResult = { name: "test", verdict: @runtime.Pass }
  assert_true(@runtime.monitor_result_to_issue(r) is None)
}

///|
test "monitor_result_to_issue converts Warn to Info issue" {
  let r : @runtime.MonitorResult = {
    name: "timeout",
    verdict: @runtime.Warn("high"),
  }
  guard @runtime.monitor_result_to_issue(r) is Some(issue) else {
    fail("expected Some")
  }
  assert_eq(issue.source, @runtime.Monitor)
  assert_eq(issue.category, @runtime.MonitorVerdict)
  assert_eq(issue.level, @runtime.Info)
  assert_true(issue.detail.contains("timeout"))
  assert_true(issue.detail.contains("high"))
}

///|
test "monitor_result_to_issue converts Fail to Degrade issue" {
  let r : @runtime.MonitorResult = {
    name: "wkc",
    verdict: @runtime.Fail("threshold"),
  }
  guard @runtime.monitor_result_to_issue(r) is Some(issue) else {
    fail("expected Some")
  }
  assert_eq(issue.level, @runtime.Degrade)
  assert_eq(issue.source, @runtime.Monitor)
}

///|
test "monitor_result_to_issue converts Block to Block issue" {
  let r : @runtime.MonitorResult = {
    name: "startup",
    verdict: @runtime.Block("fatal"),
  }
  guard @runtime.monitor_result_to_issue(r) is Some(issue) else {
    fail("expected Some")
  }
  assert_eq(issue.level, @runtime.Block)
  assert_true(issue.detail.contains("fatal"))
}

///|
test "enrich_surface_with_monitors appends monitor issues" {
  let surface : @runtime.DiagnosticSurface = {
    station_address: None,
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
    overall_level: @runtime.Info,
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
  let results : Array[@runtime.MonitorResult] = [
    { name: "a", verdict: @runtime.Pass },
    { name: "b", verdict: @runtime.Fail("bad") },
    { name: "c", verdict: @runtime.Warn("ok") },
  ]
  let verdict = @runtime.worst_verdict(results)
  let enriched = @runtime.enrich_surface_with_monitors(
    surface, results, verdict,
  )
  // Pass is filtered out, Fail and Warn become issues
  assert_eq(enriched.issues.length(), 2)
  assert_eq(enriched.overall_level, @runtime.Degrade)
  guard enriched.monitor_verdicts is Some(vs) else {
    fail("expected monitor_verdicts")
  }
  assert_eq(vs.length(), 3)
  guard enriched.overall_verdict is Some(v) else {
    fail("expected overall_verdict")
  }
  assert_eq(v, @runtime.Fail("bad"))
}

///|
test "enrich_surface_with_monitors preserves existing issues" {
  let existing_issue : @runtime.DiagnosticIssue = {
    source: @runtime.Registers,
    category: @runtime.AlStatus,
    level: @runtime.Block,
    detail: "pre-existing",
  }
  let surface : @runtime.DiagnosticSurface = {
    station_address: None,
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
    issues: [existing_issue],
    overall_level: @runtime.Block,
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
  let results : Array[@runtime.MonitorResult] = [
    { name: "a", verdict: @runtime.Pass },
  ]
  let enriched = @runtime.enrich_surface_with_monitors(
    surface,
    results,
    @runtime.Pass,
  )
  // Original issue preserved, no new issues from Pass
  assert_eq(enriched.issues.length(), 1)
  assert_eq(enriched.issues[0].detail, "pre-existing")
  assert_eq(enriched.overall_level, @runtime.Block)
}

///|
test "enrich_surface_with_fingerprint attaches fingerprint" {
  let surface : @runtime.DiagnosticSurface = {
    station_address: None,
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
    overall_level: @runtime.Info,
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
  let fp : @runtime.TopologyFingerprint = {
    slave_count: 3,
    identity_hash: 12345L,
  }
  let enriched = @runtime.enrich_surface_with_fingerprint(surface, fp)
  guard enriched.topology_fingerprint is Some(f) else {
    fail("expected fingerprint")
  }
  assert_eq(f.slave_count, 3)
  assert_eq(f.identity_hash, 12345L)
}

///|
test "factory functions set new fields to None by default" {
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
    al_state: None,
    al_error_flag: None,
    al_status_code: None,
    error_register: b'\x00',
    diagnosis_counter: None,
  })
  assert_true(surface.monitor_verdicts is None)
  assert_true(surface.overall_verdict is None)
  assert_true(surface.topology_fingerprint is None)
}

///|
test "enrich_surface_with_monitors escalates overall_level" {
  let surface : @runtime.DiagnosticSurface = {
    station_address: None,
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
    overall_level: @runtime.Info,
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
  let results : Array[@runtime.MonitorResult] = [
    { name: "fatal", verdict: @runtime.Block("shutdown") },
  ]
  let enriched = @runtime.enrich_surface_with_monitors(
    surface,
    results,
    @runtime.Block("shutdown"),
  )
  assert_eq(enriched.overall_level, @runtime.Block)
  assert_eq(enriched.issues.length(), 1)
  assert_eq(enriched.issues[0].level, @runtime.Block)
}
