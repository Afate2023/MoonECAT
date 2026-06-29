///|
test "offline runtime report maps telemetry into diagnostic envelope" {
  let run_report = offline_runtime_run_report()
  @debug.assert_eq(run_report.final_phase, @runtime.Done)
  @debug.assert_eq(run_report.cycles_requested, 3)
  @debug.assert_eq(run_report.cycles_ok, 3)
  let envelope = runtime_envelope_evidence_from_run(run_report)
  assert_true(envelope.covers_required_runtime_envelope())
  @debug.assert_eq(envelope.telemetry_cycles, 3L)
  @debug.assert_eq(envelope.telemetry_tx_frames, 3L)
  @debug.assert_eq(envelope.telemetry_rx_frames, 3L)
  @debug.assert_eq(envelope.fault_label, "none")
  @debug.assert_eq(envelope.final_phase_label, "done")
  @debug.assert_eq(envelope.diagnostic_overall_level_label, "info")
  assert_true(envelope.metrics_match_diagnostic_surface)
}

///|
test "recorded count_slaves oracle roundtrips through NDJSON and ReplayNic" {
  let recorded = recorded_count_slaves_oracle()
  @debug.assert_eq(recorded.recorded_count, 1)
  @debug.assert_eq(recorded.replay_count, 1)
  assert_true(recorded.replay_exhausted)
  assert_true(recorded.log.len() > 0)
  let evidence = oracle_artifact_evidence_from_log(
    recorded.log,
    slave_count=recorded.recorded_count,
    fingerprint="wbtest-count-slaves",
    recorded_result=recorded.recorded_count,
    replay_result=recorded.replay_count,
  )
  assert_true(evidence.covers_required_oracle_artifact())
  @debug.assert_eq(evidence.artifact_kind, "NicEventLog.NDJSON")
  @debug.assert_eq(evidence.artifact_ref, "NicEventLog::to_ndjson_with_header")
  @debug.assert_eq(evidence.ndjson_line_count, evidence.event_count + 1)
  @debug.assert_eq(evidence.roundtrip_event_count, evidence.event_count)
}

///|
test "oracle replay exhaustion consumes error events through ReplayNic API" {
  let log = @mock.NicEventLog::new()
  log.append(@mock.Sent(b"\x01\x02", 2))
  log.append(@mock.Received(b"\x03\x04"))
  log.append(@mock.RecvTimeout)
  log.append(@mock.RecvFailed("rx failed"))
  log.append(@mock.LinkDown)
  log.append(@mock.SendFailed("tx failed"))
  assert_true(replay_log_to_exhaustion(log))
  let evidence = oracle_artifact_evidence_from_log(
    log,
    recorded_result=6,
    replay_result=6,
  )
  assert_true(evidence.roundtrip_matches_recorded)
  assert_true(evidence.replay_exhausted)
}

///|
test "MC1D report converts to runtime envelope and oracle sections" {
  let report = runtime_envelope_oracle_evidence_report()
  assert_true(report.covers_required_mc1d())
  assert_true(!report.live_claimed)
  assert_true(
    report.verification_markdown.contains(
      "MC1D Runtime Envelope Oracle Evidence",
    ),
  )
  assert_true(report.verification_json.contains("NicEventLog.NDJSON"))
  let envelope_section = report.to_runtime_envelope_section()
  let oracle_section = report.to_oracle_artifact_section()
  @debug.assert_eq(envelope_section.stage, @medium_evidence.RuntimeEnvelope)
  @debug.assert_eq(envelope_section.boundary, @medium_evidence.MockSimulation)
  @debug.assert_eq(envelope_section.artifact_ref, Some(report.report_version))
  @debug.assert_eq(oracle_section.stage, @medium_evidence.OracleArtifact)
  @debug.assert_eq(oracle_section.boundary, @medium_evidence.Replay)
  @debug.assert_eq(
    oracle_section.artifact_ref,
    Some("NicEventLog::to_ndjson_with_header"),
  )
}
