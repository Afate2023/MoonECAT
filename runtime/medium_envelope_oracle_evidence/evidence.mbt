///|
/// RuntimeEnvelopeEvidence records the MoonECAT runtime/reporting fields that
/// form the MC1D runtime envelope.
pub(all) struct RuntimeEnvelopeEvidence {
  cycles_requested : Int
  cycles_ok : Int
  until_fault : Bool
  cycle_period_ns : Int64
  output_period_ns : Int64?
  telemetry_cycles : Int64
  telemetry_tx_frames : Int64
  telemetry_rx_frames : Int64
  telemetry_timeouts : Int64
  telemetry_retries : Int64
  telemetry_wkc_errors : Int64
  telemetry_irq_events : Int64
  telemetry_dc_delay_updates : Int64
  telemetry_emergency_events : Int64
  final_phase : @runtime.RunPhase
  final_phase_label : String
  fault_label : String
  diagnostic_issue_count : Int
  diagnostic_overall_level : @runtime.DiagnosticLevel
  diagnostic_overall_level_label : String
  metrics_match_diagnostic_surface : Bool
  runtime_run_completed : Bool
  live_claimed : Bool
  source : String
} derive(Eq, Debug)

///|
pub(all) struct OracleArtifactEvidence {
  artifact_kind : String
  artifact_ref : String
  event_count : Int
  ndjson_line_count : Int
  ndjson_has_header : Bool
  roundtrip_event_count : Int
  roundtrip_matches_recorded : Bool
  replay_exhausted : Bool
  recorded_result : Int?
  replay_result : Int?
  record_replay_result_match : Bool
  live_claimed : Bool
  external_tool_required : Bool
  source : String
} derive(Eq, Debug)

///|
pub(all) struct RuntimeEnvelopeOracleEvidenceReport {
  report_version : String
  envelope : RuntimeEnvelopeEvidence
  oracle : OracleArtifactEvidence
  verification_markdown : String
  verification_json : String
  live_claimed : Bool
} derive(Eq, Debug)

///|
pub(all) struct RecordedCountSlavesOracle {
  recorded_count : Int
  replay_count : Int
  log : @mock.NicEventLog
  replay_exhausted : Bool
} derive(Debug)

///|
pub fn run_phase_label(phase : @runtime.RunPhase) -> String {
  match phase {
    @runtime.Scanning => "scanning"
    @runtime.Validating => "validating"
    @runtime.Configuring => "configuring"
    @runtime.Operational => "operational"
    @runtime.Stopping => "stopping"
    @runtime.Done => "done"
  }
}

///|
pub fn diagnostic_level_label(level : @runtime.DiagnosticLevel) -> String {
  match level {
    @runtime.Block => "block"
    @runtime.Degrade => "degrade"
    @runtime.Info => "info"
  }
}

///|
pub fn run_fault_label(fault : @runtime.RunFault?) -> String {
  match fault {
    None => "none"
    Some(@runtime.StartupTransitionFailed(..)) => "startup.transition_failed"
    Some(@runtime.TimeoutRecoveryRequired(..)) => "timeout.recovery_required"
    Some(@runtime.RuntimeRecoveryRequired(..)) => "runtime.recovery_required"
    Some(@runtime.DcDrift(..)) => "dc.drift"
  }
}

///|
fn metrics_match_report(
  metrics : @runtime.RuntimeMetricsSummary?,
  telemetry : @runtime.Telemetry,
) -> Bool {
  match metrics {
    Some(summary) =>
      summary.cycles == telemetry.cycles &&
      summary.tx_frames == telemetry.tx_frames &&
      summary.rx_frames == telemetry.rx_frames &&
      summary.timeouts == telemetry.timeouts &&
      summary.retries == telemetry.retries &&
      summary.wkc_errors == telemetry.wkc_errors &&
      summary.irq_events == telemetry.irq_events &&
      summary.dc_delay_updates == telemetry.dc_delay_updates &&
      summary.emergency_events == telemetry.emergency_events
    None => false
  }
}

///|
pub fn runtime_envelope_evidence_from_run(
  report : @runtime.RunReport,
  runtime_run_completed? : Bool = true,
) -> RuntimeEnvelopeEvidence {
  let surface = @runtime.diagnostic_surface_from_run(report)
  {
    cycles_requested: report.cycles_requested,
    cycles_ok: report.cycles_ok,
    until_fault: report.until_fault,
    cycle_period_ns: report.cycle_period_ns,
    output_period_ns: report.output_period_ns,
    telemetry_cycles: report.telemetry.cycles,
    telemetry_tx_frames: report.telemetry.tx_frames,
    telemetry_rx_frames: report.telemetry.rx_frames,
    telemetry_timeouts: report.telemetry.timeouts,
    telemetry_retries: report.telemetry.retries,
    telemetry_wkc_errors: report.telemetry.wkc_errors,
    telemetry_irq_events: report.telemetry.irq_events,
    telemetry_dc_delay_updates: report.telemetry.dc_delay_updates,
    telemetry_emergency_events: report.telemetry.emergency_events,
    final_phase: report.final_phase,
    final_phase_label: run_phase_label(report.final_phase),
    fault_label: run_fault_label(report.fault),
    diagnostic_issue_count: surface.issues.length(),
    diagnostic_overall_level: surface.overall_level,
    diagnostic_overall_level_label: diagnostic_level_label(
      surface.overall_level,
    ),
    metrics_match_diagnostic_surface: metrics_match_report(
      surface.runtime_metrics,
      report.telemetry,
    ),
    runtime_run_completed,
    live_claimed: false,
    source: "runtime/RunReport + runtime/DiagnosticSurface",
  }
}

///|
pub fn RuntimeEnvelopeEvidence::covers_required_runtime_envelope(
  self : RuntimeEnvelopeEvidence,
) -> Bool {
  self.runtime_run_completed &&
  self.cycles_requested >= self.cycles_ok &&
  self.telemetry_cycles >= self.cycles_ok.to_int64() &&
  self.metrics_match_diagnostic_surface &&
  !self.live_claimed
}

///|
fn non_empty_line_count(text : String) -> Int {
  let mut count = 0
  let mut in_line = false
  for ch in text {
    if ch == '\n' {
      if in_line {
        count = count + 1
      }
      in_line = false
    } else if ch != '\r' {
      in_line = true
    }
  }
  if in_line {
    count = count + 1
  }
  count
}

///|
fn same_event_log(left : @mock.NicEventLog, right : @mock.NicEventLog) -> Bool {
  if left.len() != right.len() {
    return false
  }
  for i = 0; i < left.len(); i = i + 1 {
    if left.events[i] != right.events[i] {
      return false
    }
  }
  true
}

///|
fn replay_send_failed(
  replay : @mock.ReplayNic,
  expected_message : String,
) -> Bool {
  let result : Result[Int, @hal.EcError] = Ok(replay.send(b"")) catch {
    err => Err(err)
  }
  match result {
    Err(@hal.EcError::SendFailed(actual_message)) =>
      actual_message == expected_message
    _ => false
  }
}

///|
fn replay_recv_failed(
  replay : @mock.ReplayNic,
  expected_message : String,
) -> Bool {
  let result : Result[Bytes, @hal.EcError] = Ok(
    replay.recv(timeout=@hal.Duration(1_000_000L)),
  ) catch {
    err => Err(err)
  }
  match result {
    Err(@hal.EcError::RecvFailed(actual_message)) =>
      actual_message == expected_message
    _ => false
  }
}

///|
fn replay_recv_timeout(replay : @mock.ReplayNic) -> Bool {
  let result : Result[Bytes, @hal.EcError] = Ok(
    replay.recv(timeout=@hal.Duration(1_000_000L)),
  ) catch {
    err => Err(err)
  }
  match result {
    Err(@hal.EcError::RecvTimeout) => true
    _ => false
  }
}

///|
fn replay_link_down(replay : @mock.ReplayNic) -> Bool {
  let result : Result[Bytes, @hal.EcError] = Ok(
    replay.recv(timeout=@hal.Duration(1_000_000L)),
  ) catch {
    err => Err(err)
  }
  match result {
    Err(@hal.EcError::LinkDown) => true
    _ => false
  }
}

///|
fn consume_replay_event(
  replay : @mock.ReplayNic,
  event : @mock.NicEvent,
) -> Bool {
  match event {
    @mock.Sent(data, expected_len) => {
      let result : Result[Int, @hal.EcError] = Ok(replay.send(data)) catch {
        err => Err(err)
      }
      match result {
        Ok(actual_len) => actual_len == expected_len
        _ => false
      }
    }
    @mock.Received(expected_data) => {
      let result : Result[Bytes, @hal.EcError] = Ok(
        replay.recv(timeout=@hal.Duration(1_000_000L)),
      ) catch {
        err => Err(err)
      }
      match result {
        Ok(actual_data) => actual_data == expected_data
        _ => false
      }
    }
    @mock.RecvTimeout => replay_recv_timeout(replay)
    @mock.RecvFailed(message) => replay_recv_failed(replay, message)
    @mock.LinkDown => replay_link_down(replay)
    @mock.SendFailed(message) => replay_send_failed(replay, message)
  }
}

///|
pub fn replay_log_to_exhaustion(log : @mock.NicEventLog) -> Bool {
  let replay = @mock.ReplayNic::from_log(log)
  for event in log.events {
    if !consume_replay_event(replay, event) {
      return false
    }
  }
  replay.is_exhausted()
}

///|
pub fn oracle_artifact_evidence_from_log(
  log : @mock.NicEventLog,
  slave_count? : Int = 0,
  fingerprint? : String = "",
  recorded_result? : Int,
  replay_result? : Int,
) -> OracleArtifactEvidence {
  let ndjson = log.to_ndjson_with_header(slave_count~, fingerprint~)
  let roundtrip = @mock.NicEventLog::from_ndjson(ndjson)
  {
    artifact_kind: "NicEventLog.NDJSON",
    artifact_ref: "NicEventLog::to_ndjson_with_header",
    event_count: log.len(),
    ndjson_line_count: non_empty_line_count(ndjson),
    ndjson_has_header: ndjson.contains("\"header\":true"),
    roundtrip_event_count: roundtrip.len(),
    roundtrip_matches_recorded: same_event_log(log, roundtrip),
    replay_exhausted: replay_log_to_exhaustion(roundtrip),
    recorded_result,
    replay_result,
    record_replay_result_match: match (recorded_result, replay_result) {
      (Some(recorded), Some(replayed)) => recorded == replayed
      _ => false
    },
    live_claimed: false,
    external_tool_required: false,
    source: "hal/mock/NicEventLog + NDJSON + ReplayNic",
  }
}

///|
pub fn OracleArtifactEvidence::covers_required_oracle_artifact(
  self : OracleArtifactEvidence,
) -> Bool {
  self.event_count > 0 &&
  self.ndjson_has_header &&
  self.roundtrip_event_count == self.event_count &&
  self.roundtrip_matches_recorded &&
  self.replay_exhausted &&
  self.record_replay_result_match &&
  !self.live_claimed &&
  !self.external_tool_required
}

///|
pub fn recorded_count_slaves_oracle() -> RecordedCountSlavesOracle raise @hal.EcError {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x044C2C52U,
    revision: 0x00120000U,
    serial: 0x00000001U,
  }
  let slave = @mock.VirtualSlave::new(0, identity, b"")
  let recording = @mock.RecordingNic::wrap(
    @mock.VirtualNic::with_slaves([slave]),
  )
  let recording_session = @protocol.DatagramSession::new(recording)
  let recorded_count = @protocol.count_slaves(
    recording_session,
    @hal.Duration(1_000_000L),
  )
  let log = recording.get_log()
  let replay = @mock.ReplayNic::from_log(log)
  let replay_session = @protocol.DatagramSession::new(replay)
  let replay_count = @protocol.count_slaves(
    replay_session,
    @hal.Duration(1_000_000L),
  )
  { recorded_count, replay_count, log, replay_exhausted: replay.is_exhausted() }
}

///|
fn fallback_recorded_count_slaves_oracle() -> RecordedCountSlavesOracle {
  {
    recorded_count: 0,
    replay_count: -1,
    log: @mock.NicEventLog::new(),
    replay_exhausted: false,
  }
}

///|
fn offline_scan_report() -> @runtime.ScanReport {
  { slave_count: 0, slaves: [] }
}

///|
fn offline_empty_pdo_context() -> @protocol.PdoContext {
  @protocol.PdoContext::build([], 0U)
}

///|
pub fn offline_runtime_run_report() -> @runtime.RunReport {
  let scan = offline_scan_report()
  let expected : Array[@hal.SlaveConfig] = []
  let config = @hal.MasterConfig::default()
  @runtime.run_with_scan_and_states_and_settings_prepared_reporting_to(
    @protocol.DatagramSession::new(@mock.MockNic::new()),
    scan,
    config,
    expected,
    offline_empty_pdo_context(),
    0U,
    @runtime.RunLoopSettings::fixed_cycles(3),
    @protocol.Init,
    None,
    None,
    @hal.Duration(1_000_000L),
    @runtime.NullRunProgressSink::new(),
  ) catch {
    _ => {
      let telemetry = @runtime.Telemetry::new()
      {
        scan,
        validation: @runtime.validate(scan, expected),
        cycles_requested: 3,
        cycles_ok: 0,
        until_fault: false,
        cycle_period_ns: config.cycle_period_ns,
        output_period_ns: None,
        telemetry,
        final_phase: @runtime.Configuring,
        fault: Some(
          @runtime.RuntimeRecoveryRequired(
            expected_wkc=0U,
            observed_wkc_errors=0L,
          ),
        ),
      }
    }
  }
}

///|
fn verification_report_from_evidence(
  envelope : RuntimeEnvelopeEvidence,
  oracle : OracleArtifactEvidence,
) -> @runtime.VerificationReport {
  let verdict = if envelope.covers_required_runtime_envelope() &&
    oracle.covers_required_oracle_artifact() {
    @runtime.Verdict::Pass
  } else {
    @runtime.Verdict::Fail("MC1D evidence incomplete")
  }
  {
    title: "MC1D Runtime Envelope Oracle Evidence",
    summary_verdict: verdict,
    total_cycles: envelope.telemetry_cycles,
    duration_ns: envelope.telemetry_cycles * envelope.cycle_period_ns,
    monitor_results: [
      {
        name: "runtime-envelope",
        verdict: if envelope.covers_required_runtime_envelope() {
          @runtime.Verdict::Pass
        } else {
          @runtime.Verdict::Fail("runtime envelope is incomplete")
        },
      },
      {
        name: "oracle-artifact",
        verdict: if oracle.covers_required_oracle_artifact() {
          @runtime.Verdict::Pass
        } else {
          @runtime.Verdict::Fail("oracle artifact is incomplete")
        },
      },
    ],
    timeline: [
      {
        cycle: 0L,
        timestamp_ns: 0L,
        event_type: "runtime.envelope",
        detail: envelope.final_phase_label,
        verdict: if envelope.covers_required_runtime_envelope() {
          @runtime.Verdict::Pass
        } else {
          @runtime.Verdict::Fail("runtime envelope is incomplete")
        },
      },
      {
        cycle: envelope.telemetry_cycles,
        timestamp_ns: envelope.telemetry_cycles * envelope.cycle_period_ns,
        event_type: "oracle.artifact",
        detail: oracle.artifact_kind + ":" + oracle.artifact_ref,
        verdict: if oracle.covers_required_oracle_artifact() {
          @runtime.Verdict::Pass
        } else {
          @runtime.Verdict::Fail("oracle artifact is incomplete")
        },
      },
    ],
    fault_injections: [],
    metadata: [
      ("report_version", "runtime-envelope-oracle-evidence-v1"),
      ("artifact_kind", oracle.artifact_kind),
      ("live_claimed", "false"),
    ],
  }
}

///|
pub fn runtime_envelope_oracle_evidence_report() -> RuntimeEnvelopeOracleEvidenceReport {
  let run_report = offline_runtime_run_report()
  let envelope = runtime_envelope_evidence_from_run(
    run_report,
    runtime_run_completed=run_report.final_phase == @runtime.Done,
  )
  let recorded = recorded_count_slaves_oracle() catch {
    _ => fallback_recorded_count_slaves_oracle()
  }
  let oracle = oracle_artifact_evidence_from_log(
    recorded.log,
    slave_count=recorded.recorded_count,
    fingerprint="mock-count-slaves",
    recorded_result=recorded.recorded_count,
    replay_result=recorded.replay_count,
  )
  let verification = verification_report_from_evidence(envelope, oracle)
  {
    report_version: "runtime-envelope-oracle-evidence-v1",
    envelope,
    oracle,
    verification_markdown: verification.to_markdown(),
    verification_json: verification.to_json(),
    live_claimed: false,
  }
}

///|
pub fn RuntimeEnvelopeOracleEvidenceReport::covers_required_mc1d(
  self : RuntimeEnvelopeOracleEvidenceReport,
) -> Bool {
  self.envelope.covers_required_runtime_envelope() &&
  self.oracle.covers_required_oracle_artifact() &&
  !self.live_claimed
}

///|
pub fn RuntimeEnvelopeOracleEvidenceReport::to_runtime_envelope_section(
  self : RuntimeEnvelopeOracleEvidenceReport,
) -> @medium_evidence.MediumEvidenceSection {
  @medium_evidence.MediumEvidenceSection::make(
    stage=@medium_evidence.RuntimeEnvelope,
    title="Runtime envelope evidence",
    source="runtime/medium_envelope_oracle_evidence + RunReport + DiagnosticSurface",
    summary="records cycles=\{self.envelope.cycles_ok}/\{self.envelope.cycles_requested}, telemetry tx/rx=\{self.envelope.telemetry_tx_frames}/\{self.envelope.telemetry_rx_frames}, diagnostic_level=\{self.envelope.diagnostic_overall_level_label}, metrics_match_diagnostic_surface=\{self.envelope.metrics_match_diagnostic_surface}, live_claimed=\{self.live_claimed}",
    boundary=@medium_evidence.MockSimulation,
    artifact_ref=self.report_version,
  )
}

///|
pub fn RuntimeEnvelopeOracleEvidenceReport::to_oracle_artifact_section(
  self : RuntimeEnvelopeOracleEvidenceReport,
) -> @medium_evidence.MediumEvidenceSection {
  @medium_evidence.MediumEvidenceSection::make(
    stage=@medium_evidence.OracleArtifact,
    title="Replayable oracle artifact evidence",
    source="runtime/medium_envelope_oracle_evidence + hal/mock/NicEventLog",
    summary="records artifact=\{self.oracle.artifact_kind}, events=\{self.oracle.event_count}, ndjson_lines=\{self.oracle.ndjson_line_count}, roundtrip_matches_recorded=\{self.oracle.roundtrip_matches_recorded}, replay_exhausted=\{self.oracle.replay_exhausted}, external_tool_required=\{self.oracle.external_tool_required}",
    boundary=@medium_evidence.Replay,
    artifact_ref=self.oracle.artifact_ref,
  )
}
