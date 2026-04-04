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
    dl_error_counters: None,
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

// ===== Batch 12: diagnosis.mbt pub function coverage =====

///|
test "parse_error_register_payload valid" {
  let payload = b"\xAB"
  let result = @runtime.parse_error_register_payload(payload)
  assert_eq(result, b'\xAB')
}

///|
test "parse_error_register_payload too short" {
  let result : Result[Byte, _] = try
    @runtime.parse_error_register_payload(b"") |> Ok
  catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "parse_u32_payload valid" {
  // 0x04030201 in little-endian
  let payload = b"\x01\x02\x03\x04"
  let result = @runtime.parse_u32_payload(payload)
  assert_eq(result, 0x04030201U)
}

///|
test "parse_u32_payload too short" {
  let result : Result[UInt, _] = try
    @runtime.parse_u32_payload(b"\x01\x02\x03") |> Ok
  catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

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
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let diag : @runtime.SlaveDiagnosis = {
    station_address: 0x1001U,
    al_state: Some(@protocol.SafeOp),
    al_error_flag: Some(true),
    al_status_code: Some(0x001AU),
    error_register: b'\x42',
    diagnosis_counter: Some(5U),
    dl_error_counters: None,
  }
  let surface = @runtime.diagnostic_surface_from_slave_diagnosis(scan, diag)
  assert_eq(surface.station_address, Some(0x1001U))
  // Should have 4 issues: al_error_flag, al_status_code, error_register, diagnosis_counter
  assert_eq(surface.issues.length(), 4)
  assert_eq(surface.issues[0].level, @runtime.Block) // al_error_flag
  assert_eq(surface.issues[1].level, @runtime.Block) // al_status_code
  assert_eq(surface.issues[2].level, @runtime.Degrade) // error_register
  assert_eq(surface.issues[3].level, @runtime.Info) // diagnosis_counter
  assert_eq(surface.overall_level, @runtime.Block)
  assert_eq(surface.error_register, Some(b'\x42'))
  assert_eq(surface.diagnosis_counter, Some(5U))
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
        identification: 5U,
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
  assert_eq(surface.issues.length(), 0)
  assert_eq(surface.overall_level, @runtime.Info)
}

///|
test "diagnostic_surface_from_validate produces issues from differences" {
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
    expected_source: @runtime.EniImport,
    actual_source: @runtime.OnlineScan,
    total_expected: 1,
    total_found: 0,
    results: [@runtime.Missing(position=0)],
    differences: [@runtime.ConfigurationDifference::Missing(position=0)],
    all_ok: false,
    grade: @runtime.Block,
  }
  let surface = @runtime.diagnostic_surface_from_validate(scan, report)
  assert_eq(surface.issues.length(), 1)
  assert_eq(surface.overall_level, @runtime.Block)
  guard surface.configuration_summary is Some(cs) else {
    fail("expected configuration_summary")
  }
  assert_eq(cs.slave_count, 1)
  assert_eq(cs.difference_count, 1)
}

///|
test "diagnostic_surface_from_run includes telemetry and fault issues" {
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
  let telemetry : @runtime.Telemetry = {
    cycles: 100L,
    tx_frames: 200L,
    rx_frames: 200L,
    timeouts: 3L,
    retries: 0L,
    wkc_errors: 0L,
    irq_events: 0L,
    dc_delay_updates: 0L,
    emergency_events: 0L,
  }
  let report : @runtime.RunReport = {
    scan,
    validation: {
      expected_source: @runtime.OnlineScan,
      actual_source: @runtime.OnlineScan,
      total_expected: 1,
      total_found: 1,
      results: [@runtime.Ok],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 100,
    cycles_ok: 90,
    until_fault: false,
    cycle_period_ns: 1000000L,
    output_period_ns: None,
    telemetry,
    final_phase: @runtime.Done,
    fault: Some(@runtime.DcDrift(delta_ns=500L)),
  }
  let surface = @runtime.diagnostic_surface_from_run(report)
  guard surface.runtime_metrics is Some(rm) else {
    fail("expected runtime_metrics")
  }
  assert_eq(rm.cycles, 100L)
  assert_eq(rm.timeouts, 3L)
  // Issues: timeouts>0 (Degrade), cycles_ok<requested (Degrade), DcDrift (Block)
  assert_true(surface.issues.length() >= 3)
  assert_eq(surface.overall_level, @runtime.Block)
}

///|
test "diagnostic_surface_from_state_transition all issues" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    Some(0x1001U),
    @protocol.Op,
    Some(@protocol.SafeOp),
    Some(@protocol.SafeOp),
    Some(true),
    Some(0x001AU),
    Some(0U),
  )
  assert_eq(surface.station_address, Some(0x1001U))
  // 4 issues: final_state != target, status_code != 0, al_error_flag, wkc == 0
  assert_eq(surface.issues.length(), 4)
  assert_eq(surface.overall_level, @runtime.Block)
}

///|
test "diagnostic_surface_from_state_transition no issues" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    Some(0x1001U),
    @protocol.Op,
    Some(@protocol.SafeOp),
    Some(@protocol.Op),
    Some(false),
    Some(0U),
    Some(1U),
  )
  assert_eq(surface.issues.length(), 0)
  assert_eq(surface.overall_level, @runtime.Info)
}

///|
test "diagnostic_surface_from_state_transition None branches" {
  let surface = @runtime.diagnostic_surface_from_state_transition(
    None,
    @protocol.Op,
    None,
    None,
    None,
    None,
    None,
  )
  // All None => no issues triggered
  assert_eq(surface.issues.length(), 0)
  assert_eq(surface.overall_level, @runtime.Info)
}

///|
test "diagnosis_restore_path PreOp" {
  let path = @runtime.diagnosis_restore_path(@protocol.PreOp)
  assert_eq(path, [@protocol.PreOp])
}

///|
test "diagnosis_restore_path SafeOp" {
  let path = @runtime.diagnosis_restore_path(@protocol.SafeOp)
  assert_eq(path, [@protocol.PreOp, @protocol.SafeOp])
}

///|
test "diagnosis_restore_path Op" {
  let path = @runtime.diagnosis_restore_path(@protocol.Op)
  assert_eq(path, [@protocol.PreOp, @protocol.SafeOp, @protocol.Op])
}

///|
test "diagnosis_restore_path Init" {
  let path = @runtime.diagnosis_restore_path(@protocol.Init)
  assert_eq(path, [@protocol.PreOp, @protocol.Init])
}

///|
test "diagnosis_restore_path Boot" {
  let path = @runtime.diagnosis_restore_path(@protocol.Boot)
  assert_eq(path, [@protocol.PreOp, @protocol.Init, @protocol.Boot])
}
