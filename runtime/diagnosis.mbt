///|
/// Runtime diagnosis helpers that expose standard EtherCAT diagnostics
/// objects to applications via CoE SDO.

///|
/// SlaveDiagnosis aggregates a minimal diagnosis snapshot for one slave.
pub(all) struct SlaveDiagnosis {
  station_address : UInt
  /// Observed AL state when the snapshot was taken.
  al_state : @protocol.EsmState?
  /// AL Error Flag from AL Status register.
  al_error_flag : Bool?
  /// AL Status Code from register 0x0134.
  al_status_code : UInt?
  /// CiA-301 Error Register (0x1001:0)
  error_register : Byte
  /// Diagnosis history object counter (0x10F3:0), when available.
  diagnosis_counter : UInt?
  /// DL/Physical layer error counters (ESC 0x0300–0x0313), when available.
  dl_error_counters : @protocol.DlErrorCounters?
} derive(Eq, Show)

///|
pub(all) enum DiagnosticLevel {
  Block
  Degrade
  Info
} derive(Eq, Show)

///|
pub(all) enum DiagnosticSourceLayer {
  Registers
  Mailbox
  Topology
  Configuration
  RuntimeTelemetry
  StateTransition
  Monitor
} derive(Eq, Show)

///|
pub(all) enum DiagnosticCategory {
  AlStatus
  ErrorRegister
  DiagnosisHistory
  Topology
  Identity
  Configuration
  RuntimeMetrics
  StateTransition
  MonitorVerdict
} derive(Eq, Show)

///|
pub(all) struct StateSurfaceSummary {
  target_state : @protocol.EsmState?
  current_state : @protocol.EsmState?
  final_state : @protocol.EsmState?
  al_state : @protocol.EsmState?
  al_error_flag : Bool?
  al_status_code : UInt?
  wkc : UInt?
} derive(Eq, Show)

///|
pub(all) struct ConfigurationSurfaceSummary {
  slave_count : Int
  station_addresses : Array[UInt]
  expected_source : ConfigurationSource?
  actual_source : ConfigurationSource?
  validation_grade : ValidateGrade?
  difference_count : Int
} derive(Eq, Show)

///|
pub(all) struct RuntimeMetricsSummary {
  cycles : Int64
  tx_frames : Int64
  rx_frames : Int64
  timeouts : Int64
  retries : Int64
  wkc_errors : Int64
  irq_events : Int64
  dc_delay_updates : Int64
  emergency_events : Int64
} derive(Eq, Show)

///|
pub(all) struct DiagnosticIssue {
  source : DiagnosticSourceLayer
  category : DiagnosticCategory
  level : DiagnosticLevel
  detail : String
} derive(Eq, Show)

///|
pub(all) struct DiagnosticSurface {
  station_address : UInt?
  state_summary : StateSurfaceSummary
  configuration_summary : ConfigurationSurfaceSummary?
  error_register : Byte?
  diagnosis_counter : UInt?
  runtime_metrics : RuntimeMetricsSummary?
  issues : Array[DiagnosticIssue]
  overall_level : DiagnosticLevel
  monitor_verdicts : Array[MonitorResult]?
  overall_verdict : Verdict?
  topology_fingerprint : TopologyFingerprint?
} derive(Eq, Show)

///|
/// DiagnosisSession captures the state needed around a diagnosis run.
pub(all) struct DiagnosisSession {
  original_state : @protocol.EsmState
  observed_state : @protocol.EsmState?
  observed_error_flag : Bool?
  observed_status_code : UInt?
  mailbox_config : @mailbox.MailboxConfig
}

///|
/// MailboxSession captures generic mailbox preparation state for one slave.
pub(all) struct MailboxSession {
  original_state : @protocol.EsmState
  mailbox_config : @mailbox.MailboxConfig
}

///|
priv struct AlStatusSnapshot {
  state : @protocol.EsmState
  error_flag : Bool
  status_code : UInt
}

///|
let diagnosis_mailbox_max_polls : Int = 32

///|
let diagnosis_sm_window_size : Int = 8

///|
let diagnosis_sdo_max_attempts : Int = 3

///|
let diagnosis_sii_word_count : Int = 128

///|
/// Parse a one-byte error register payload.
pub fn parse_error_register_payload(payload : Bytes) -> Byte raise @hal.EcError {
  if payload.length() < 1 {
    raise @hal.EcError::MailboxProtocol(
      "diagnosis: error register payload too short",
    )
  }
  payload[0]
}

///|
/// Parse a little-endian UInt32 payload.
pub fn parse_u32_payload(payload : Bytes) -> UInt raise @hal.EcError {
  if payload.length() < 4 {
    raise @hal.EcError::MailboxProtocol("diagnosis: u32 payload too short")
  }
  payload[0].to_uint() |
  (payload[1].to_uint() << 8) |
  (payload[2].to_uint() << 16) |
  (payload[3].to_uint() << 24)
}

///|
/// Read Error Register (0x1001:0) from one slave.
pub fn[N : @hal.Nic] read_error_register(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let payload = diagnosis_timeout_step(
    try? @protocol.sdo_upload_retry(
      nic, station, mb_config, rmsm, 0x1001U, b'\x00', timeout,
    ),
    "CoE 0x1001:0 upload",
  )
  parse_error_register_payload(payload)
}

///|
/// Read diagnosis object counter (0x10F3:0) from one slave.
/// Some slaves may not implement this object; callers can handle errors.
pub fn[N : @hal.Nic] read_diagnosis_counter(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let payload = diagnosis_timeout_step(
    try? @protocol.sdo_upload_retry(
      nic, station, mb_config, rmsm, 0x10F3U, b'\x00', timeout,
    ),
    "CoE 0x10F3:0 upload",
  )
  parse_u32_payload(payload)
}

///|
/// Read Error Register (0x1001:0) from one slave via AP mailbox transport.
pub fn[N : @hal.Nic] read_error_register_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let payload = diagnosis_sdo_upload_ap(
    nic, position, station, mb_config, rmsm, 0x1001U, b'\x00', timeout, "AP CoE 0x1001:0 upload",
  )
  parse_error_register_payload(payload)
}

///|
/// Read diagnosis object counter (0x10F3:0) via AP mailbox transport.
pub fn[N : @hal.Nic] read_diagnosis_counter_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let payload = diagnosis_sdo_upload_ap(
    nic, position, station, mb_config, rmsm, 0x10F3U, b'\x00', timeout, "AP CoE 0x10F3:0 upload",
  )
  parse_u32_payload(payload)
}

///|
/// Read a diagnosis snapshot for one slave.
/// If 0x10F3 is unavailable, the counter is returned as None.
pub fn[N : @hal.Nic] read_slave_diagnosis(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> SlaveDiagnosis raise @hal.EcError {
  let al_snapshot = Some(read_al_status_snapshot_fp(nic, station, timeout)) catch {
    _ => None
  }
  let err = read_error_register(nic, station, mb_config, rmsm, timeout)
  let diag = Some(
    read_diagnosis_counter(nic, station, mb_config, rmsm, timeout),
  ) catch {
    _ => None
  }
  let dl_counters : @protocol.DlErrorCounters? = Some(
    @protocol.read_dl_error_counters(nic, station, timeout),
  ) catch {
    _ => None
  }
  {
    station_address: station,
    al_state: match al_snapshot {
      Some(snapshot) => Some(snapshot.state)
      None => None
    },
    al_error_flag: match al_snapshot {
      Some(snapshot) => Some(snapshot.error_flag)
      None => None
    },
    al_status_code: match al_snapshot {
      Some(snapshot) => Some(snapshot.status_code)
      None => None
    },
    error_register: err,
    diagnosis_counter: diag,
    dl_error_counters: dl_counters,
  }
}

///|
/// Read a diagnosis snapshot for one slave via AP mailbox transport.
pub fn[N : @hal.Nic] read_slave_diagnosis_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> SlaveDiagnosis raise @hal.EcError {
  let al_snapshot = Some(read_al_status_snapshot_fp(nic, station, timeout)) catch {
    _ => None
  }
  let err = read_error_register_ap(
    nic, position, station, mb_config, rmsm, timeout,
  )
  let diag = Some(
    read_diagnosis_counter_ap(nic, position, station, mb_config, rmsm, timeout),
  ) catch {
    _ => None
  }
  let dl_counters : @protocol.DlErrorCounters? = Some(
    @protocol.read_dl_error_counters_ap(nic, position, timeout),
  ) catch {
    _ => None
  }
  {
    station_address: station,
    al_state: match al_snapshot {
      Some(snapshot) => Some(snapshot.state)
      None => None
    },
    al_error_flag: match al_snapshot {
      Some(snapshot) => Some(snapshot.error_flag)
      None => None
    },
    al_status_code: match al_snapshot {
      Some(snapshot) => Some(snapshot.status_code)
      None => None
    },
    error_register: err,
    diagnosis_counter: diag,
    dl_error_counters: dl_counters,
  }
}

///|
pub fn diagnostic_surface_from_slave_diagnosis(
  scan : ScanReport,
  report : SlaveDiagnosis,
) -> DiagnosticSurface {
  let issues : Array[DiagnosticIssue] = []
  match report.al_error_flag {
    Some(true) =>
      issues.push({
        source: Registers,
        category: AlStatus,
        level: Block,
        detail: "AL error flag set",
      })
    _ => ()
  }
  match report.al_status_code {
    Some(code) if code != 0U =>
      issues.push({
        source: Registers,
        category: AlStatus,
        level: Block,
        detail: "AL status code " + code.to_string(),
      })
    _ => ()
  }
  if report.error_register != b'\x00' {
    issues.push({
      source: Mailbox,
      category: ErrorRegister,
      level: Degrade,
      detail: "Error register " + report.error_register.to_uint().to_string(),
    })
  }
  match report.diagnosis_counter {
    Some(value) if value > 0U =>
      issues.push({
        source: Mailbox,
        category: DiagnosisHistory,
        level: Info,
        detail: "Diagnosis history count " + value.to_string(),
      })
    _ => ()
  }
  {
    station_address: Some(report.station_address),
    state_summary: {
      target_state: None,
      current_state: None,
      final_state: None,
      al_state: report.al_state,
      al_error_flag: report.al_error_flag,
      al_status_code: report.al_status_code,
      wkc: None,
    },
    configuration_summary: Some(
      configuration_surface_summary(scan, None, Some(OnlineScan), None, 0),
    ),
    error_register: Some(report.error_register),
    diagnosis_counter: report.diagnosis_counter,
    runtime_metrics: None,
    issues,
    overall_level: highest_diagnostic_level(issues, Info),
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
}

///|
pub fn diagnostic_surface_from_validate(
  scan : ScanReport,
  report : ValidateReport,
) -> DiagnosticSurface {
  let issues = report.differences.map(fn(diff) {
    validation_difference_issue(diff)
  })
  let baseline = diagnostic_level_from_validate_grade(report.grade)
  {
    station_address: None,
    state_summary: empty_state_surface_summary(),
    configuration_summary: Some(
      configuration_surface_summary(
        scan,
        Some(report.expected_source),
        Some(report.actual_source),
        Some(report.grade),
        report.differences.length(),
      ),
    ),
    error_register: None,
    diagnosis_counter: None,
    runtime_metrics: None,
    issues,
    overall_level: highest_diagnostic_level(issues, baseline),
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
}

///|
pub fn diagnostic_surface_from_run(report : RunReport) -> DiagnosticSurface {
  let base = diagnostic_surface_from_validate(report.scan, report.validation)
  let issues = base.issues
  let telemetry_issues = runtime_metrics_issues(
    report.telemetry,
    report.cycles_requested,
    report.cycles_ok,
  )
  for issue in telemetry_issues {
    issues.push(issue)
  }
  match report.fault {
    Some(fault) =>
      for issue in run_fault_issues(fault) {
        issues.push(issue)
      }
    None => ()
  }
  {
    ..base,
    runtime_metrics: Some(runtime_metrics_summary(report.telemetry)),
    issues,
    overall_level: highest_diagnostic_level(
      issues,
      highest_diagnostic_level(base.issues, base.overall_level),
    ),
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
}

///|
fn run_fault_issues(fault : RunFault) -> Array[DiagnosticIssue] {
  match fault {
    StartupTransitionFailed(
      station~,
      target~,
      current~,
      error_indication~,
      status_code~,
      raw_status_code~,
      control_wkc~
    ) => {
      let current_text = match current {
        Some(state) => state.to_string()
        None => "unknown"
      }
      let error_text = match error_indication {
        Some(true) => "set"
        Some(false) => "clear"
        None => "unknown"
      }
      let status_text = match status_code {
        Some(code) => code.to_string()
        None => "unknown"
      }
      let raw_status_text = match raw_status_code {
        Some(code) => code.to_string()
        None => "unknown"
      }
      let control_wkc_text = match control_wkc {
        Some(wkc) => wkc.to_string()
        None => "unknown"
      }
      [
        {
          source: StateTransition,
          category: StateTransition,
          level: Block,
          detail: "Startup transition failed for station " +
          station.to_string() +
          ": target=" +
          target.to_string() +
          " current=" +
          current_text +
          " error_flag=" +
          error_text +
          " status_code=" +
          status_text +
          " raw_status_code=" +
          raw_status_text +
          " control_wkc=" +
          control_wkc_text,
        },
      ]
    }
    TimeoutRecoveryRequired(observed_timeouts~, consecutive_timeouts~) =>
      [
        {
          source: RuntimeTelemetry,
          category: RuntimeMetrics,
          level: Block,
          detail: "Timeout recovery required: timeouts=" +
          observed_timeouts.to_string() +
          " consecutive_timeouts=" +
          consecutive_timeouts.to_string(),
        },
      ]
    RuntimeRecoveryRequired(expected_wkc~, observed_wkc_errors~) =>
      [
        {
          source: RuntimeTelemetry,
          category: RuntimeMetrics,
          level: Block,
          detail: "Runtime recovery required: expected_wkc=" +
          expected_wkc.to_string() +
          " wkc_errors=" +
          observed_wkc_errors.to_string(),
        },
      ]
    DcDrift(delta_ns~) =>
      [
        {
          source: RuntimeTelemetry,
          category: RuntimeMetrics,
          level: Block,
          detail: "DC drift detected: delta_ns=" + delta_ns.to_string(),
        },
      ]
  }
}

///|
pub fn diagnostic_surface_from_state_transition(
  station : UInt?,
  target : @protocol.EsmState,
  current : @protocol.EsmState?,
  final_state : @protocol.EsmState?,
  al_error_flag : Bool?,
  status_code : UInt?,
  wkc : UInt?,
) -> DiagnosticSurface {
  let issues : Array[DiagnosticIssue] = []
  match final_state {
    Some(state) if state != target =>
      issues.push({
        source: StateTransition,
        category: StateTransition,
        level: Block,
        detail: "Final state " +
        state.to_string() +
        " does not match target " +
        target.to_string(),
      })
    _ => ()
  }
  match status_code {
    Some(code) if code != 0U =>
      issues.push({
        source: Registers,
        category: AlStatus,
        level: Block,
        detail: "AL status code " + code.to_string(),
      })
    _ => ()
  }
  match al_error_flag {
    Some(true) =>
      issues.push({
        source: Registers,
        category: AlStatus,
        level: Block,
        detail: "AL error indication is set",
      })
    _ => ()
  }
  match wkc {
    Some(value) if value == 0U =>
      issues.push({
        source: StateTransition,
        category: StateTransition,
        level: Degrade,
        detail: "WKC is zero during state transition",
      })
    _ => ()
  }
  {
    station_address: station,
    state_summary: {
      target_state: Some(target),
      current_state: current,
      final_state,
      al_state: None,
      al_error_flag,
      al_status_code: status_code,
      wkc,
    },
    configuration_summary: None,
    error_register: None,
    diagnosis_counter: None,
    runtime_metrics: None,
    issues,
    overall_level: highest_diagnostic_level(issues, Info),
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
}

///|
fn empty_state_surface_summary() -> StateSurfaceSummary {
  {
    target_state: None,
    current_state: None,
    final_state: None,
    al_state: None,
    al_error_flag: None,
    al_status_code: None,
    wkc: None,
  }
}

///|
fn configuration_surface_summary(
  scan : ScanReport,
  expected_source : ConfigurationSource?,
  actual_source : ConfigurationSource?,
  validation_grade : ValidateGrade?,
  difference_count : Int,
) -> ConfigurationSurfaceSummary {
  {
    slave_count: scan.slave_count,
    station_addresses: scan.slaves.map(fn(slave) { slave.station_address }),
    expected_source,
    actual_source,
    validation_grade,
    difference_count,
  }
}

///|
fn runtime_metrics_summary(telemetry : Telemetry) -> RuntimeMetricsSummary {
  {
    cycles: telemetry.cycles,
    tx_frames: telemetry.tx_frames,
    rx_frames: telemetry.rx_frames,
    timeouts: telemetry.timeouts,
    retries: telemetry.retries,
    wkc_errors: telemetry.wkc_errors,
    irq_events: telemetry.irq_events,
    dc_delay_updates: telemetry.dc_delay_updates,
    emergency_events: telemetry.emergency_events,
  }
}

///|
fn validation_difference_issue(
  diff : ConfigurationDifference,
) -> DiagnosticIssue {
  let (source, category) = match validation_difference_category(diff) {
    ValidateDifferenceCategory::Topology =>
      (DiagnosticSourceLayer::Topology, DiagnosticCategory::Topology)
    ValidateDifferenceCategory::Identity =>
      (DiagnosticSourceLayer::Configuration, DiagnosticCategory::Identity)
    ValidateDifferenceCategory::Configuration =>
      (DiagnosticSourceLayer::Configuration, DiagnosticCategory::Configuration)
    ValidateDifferenceCategory::Informational =>
      (DiagnosticSourceLayer::Configuration, DiagnosticCategory::Configuration)
  }
  {
    source,
    category,
    level: diagnostic_level_from_validate_grade(
      validation_difference_grade(diff),
    ),
    detail: diff.to_string(),
  }
}

///|
fn diagnostic_level_from_validate_grade(
  grade : ValidateGrade,
) -> DiagnosticLevel {
  match grade {
    Pass => Info
    Warn => Degrade
    Block => Block
  }
}

///|
fn runtime_metrics_issues(
  telemetry : Telemetry,
  cycles_requested : Int,
  cycles_ok : Int,
) -> Array[DiagnosticIssue] {
  let issues : Array[DiagnosticIssue] = []
  if telemetry.timeouts > 0L {
    issues.push({
      source: RuntimeTelemetry,
      category: RuntimeMetrics,
      level: Degrade,
      detail: "Timeout count " + telemetry.timeouts.to_string(),
    })
  }
  if telemetry.wkc_errors > 0L {
    issues.push({
      source: RuntimeTelemetry,
      category: RuntimeMetrics,
      level: Degrade,
      detail: "WKC error count " + telemetry.wkc_errors.to_string(),
    })
  }
  if telemetry.retries > 0L {
    issues.push({
      source: RuntimeTelemetry,
      category: RuntimeMetrics,
      level: Info,
      detail: "Retry count " + telemetry.retries.to_string(),
    })
  }
  if cycles_ok < cycles_requested {
    issues.push({
      source: RuntimeTelemetry,
      category: RuntimeMetrics,
      level: Degrade,
      detail: "Cycle completion " +
      cycles_ok.to_string() +
      "/" +
      cycles_requested.to_string(),
    })
  }
  issues
}

///|
/// Convert a Verdict severity to a DiagnosticLevel.
pub fn verdict_to_diagnostic_level(v : Verdict) -> DiagnosticLevel {
  match v {
    Pass => Info
    Warn(_) => Info
    Fail(_) => Degrade
    Block(_) => Block
  }
}

///|
/// Convert a non-Pass MonitorResult into a DiagnosticIssue.
/// Returns None for Pass verdicts.
pub fn monitor_result_to_issue(r : MonitorResult) -> DiagnosticIssue? {
  match r.verdict {
    Pass => None
    Warn(msg) =>
      Some({
        source: Monitor,
        category: MonitorVerdict,
        level: Info,
        detail: r.name + ": " + msg,
      })
    Fail(msg) =>
      Some({
        source: Monitor,
        category: MonitorVerdict,
        level: Degrade,
        detail: r.name + ": " + msg,
      })
    Block(msg) =>
      Some({
        source: Monitor,
        category: MonitorVerdict,
        level: Block,
        detail: r.name + ": " + msg,
      })
  }
}

///|
/// Enrich an existing DiagnosticSurface with monitor verdicts.
/// Monitor-originated issues are appended to the issue list and
/// the overall level is recomputed.
pub fn enrich_surface_with_monitors(
  surface : DiagnosticSurface,
  results : Array[MonitorResult],
  verdict : Verdict,
) -> DiagnosticSurface {
  let issues = surface.issues.copy()
  for r in results {
    match monitor_result_to_issue(r) {
      Some(issue) => issues.push(issue)
      None => ()
    }
  }
  {
    ..surface,
    issues,
    overall_level: highest_diagnostic_level(issues, surface.overall_level),
    monitor_verdicts: Some(results),
    overall_verdict: Some(verdict),
  }
}

///|
/// Enrich an existing DiagnosticSurface with a topology fingerprint.
pub fn enrich_surface_with_fingerprint(
  surface : DiagnosticSurface,
  fingerprint : TopologyFingerprint,
) -> DiagnosticSurface {
  { ..surface, topology_fingerprint: Some(fingerprint) }
}

///|
fn highest_diagnostic_level(
  issues : Array[DiagnosticIssue],
  fallback : DiagnosticLevel,
) -> DiagnosticLevel {
  let mut level = fallback
  for issue in issues {
    if diagnostic_level_rank(issue.level) > diagnostic_level_rank(level) {
      level = issue.level
    }
  }
  level
}

///|
fn diagnostic_level_rank(level : DiagnosticLevel) -> Int {
  match level {
    Info => 0
    Degrade => 1
    Block => 2
  }
}

///|
/// Prepare one slave for mailbox-based diagnosis via AP discovery and FP state control.
///
/// This flow is intentionally diagnosis-specific: it normalizes the slave back to
/// Init before entering PreOp so mailbox SM programming happens from a known base state.
pub fn[N : @hal.Nic] prepare_slave_diagnosis_ap(
  nic : N,
  position : UInt,
  station : UInt,
  timeout : @hal.Duration,
) -> DiagnosisSession raise @hal.EcError {
  let original_snapshot_result : Result[AlStatusSnapshot, Error] = try? diagnosis_timeout_step(
    try? read_al_status_snapshot_fp(nic, station, timeout),
    "diagnosis.prepare.read_al_status_fp",
  )
  let original_state = match original_snapshot_result {
    Ok(snapshot) => snapshot.state
    Err(_) => @protocol.Init
  }
  let eeprom = diagnosis_timeout_step(
    try? read_sii_with_metadata_ap(
      nic, position, diagnosis_sii_word_count, timeout,
    ),
    "diagnosis.prepare.eeprom_read_ap",
  )
  let sii = @mailbox.parse_sii_header(eeprom)
  let mailbox_config = @mailbox.MailboxConfig::from_sii(sii)
  if !mailbox_config.is_valid() {
    raise @hal.EcError::ConfigMismatch(
      "diagnosis requires mailbox-capable slave at station " +
      station.to_string(),
    )
  }
  configure_diagnosis_mailbox_sms(nic, station, eeprom, timeout)
  enter_diagnosis_preop(nic, station, original_state, timeout)
  {
    original_state,
    observed_state: match original_snapshot_result {
      Ok(snapshot) => Some(snapshot.state)
      Err(_) => None
    },
    observed_error_flag: match original_snapshot_result {
      Ok(snapshot) => Some(snapshot.error_flag)
      Err(_) => None
    },
    observed_status_code: match original_snapshot_result {
      Ok(snapshot) => Some(snapshot.status_code)
      Err(_) => None
    },
    mailbox_config,
  }
}

///|
/// Prepare one slave for generic mailbox-based access via AP discovery and FP state control.
/// Unlike diagnosis-specific helpers, this only returns the mailbox configuration and
/// original state needed for restoring the slave after read-only mailbox operations.
pub fn[N : @hal.Nic] prepare_slave_mailbox_ap(
  nic : N,
  position : UInt,
  station : UInt,
  timeout : @hal.Duration,
) -> MailboxSession raise @hal.EcError {
  let original_snapshot_result : Result[AlStatusSnapshot, Error] = try? diagnosis_timeout_step(
    try? read_al_status_snapshot_fp(nic, station, timeout),
    "mailbox.prepare.read_al_status_fp",
  )
  let original_state = match original_snapshot_result {
    Ok(snapshot) => snapshot.state
    Err(_) => @protocol.Init
  }
  let eeprom = diagnosis_timeout_step(
    try? read_sii_with_metadata_ap(
      nic, position, diagnosis_sii_word_count, timeout,
    ),
    "mailbox.prepare.eeprom_read_ap",
  )
  let sii = @mailbox.parse_sii_header(eeprom)
  let mailbox_config = @mailbox.MailboxConfig::from_sii(sii)
  if !mailbox_config.is_valid() {
    raise @hal.EcError::ConfigMismatch(
      "mailbox access requires mailbox-capable slave at station " +
      station.to_string(),
    )
  }
  configure_diagnosis_mailbox_sms(nic, station, eeprom, timeout)
  enter_diagnosis_preop(nic, station, original_state, timeout)
  { original_state, mailbox_config }
}

///|
/// Restore a slave after diagnosis using a legal path from PreOp back to the original state.
pub fn[N : @hal.Nic] restore_slave_diagnosis_state(
  nic : N,
  station : UInt,
  original_state : @protocol.EsmState,
  timeout : @hal.Duration,
) -> @protocol.EsmState raise @hal.EcError {
  let restore_path = diagnosis_restore_path(original_state)
  diagnosis_timeout_step(
    try? @protocol.transition_through(nic, station, restore_path, timeout),
    "diagnosis.restore_original_state_fp",
  )
}

///|
/// Restore a slave after generic mailbox-based access using the legal path from
/// PreOp back to the original state.
pub fn[N : @hal.Nic] restore_slave_mailbox_state(
  nic : N,
  station : UInt,
  original_state : @protocol.EsmState,
  timeout : @hal.Duration,
) -> @protocol.EsmState raise @hal.EcError {
  let restore_path = diagnosis_restore_path(original_state)
  diagnosis_timeout_step(
    try? @protocol.transition_through(nic, station, restore_path, timeout),
    "mailbox.restore_original_state_fp",
  )
}

///|
/// Build the diagnosis-specific restore path from PreOp back to the target state.
pub fn diagnosis_restore_path(
  target : @protocol.EsmState,
) -> Array[@protocol.EsmState] {
  match target {
    @protocol.PreOp => [@protocol.PreOp]
    @protocol.SafeOp => [@protocol.PreOp, @protocol.SafeOp]
    @protocol.Op => [@protocol.PreOp, @protocol.SafeOp, @protocol.Op]
    @protocol.Init => [@protocol.PreOp, @protocol.Init]
    @protocol.Boot => [@protocol.PreOp, @protocol.Init, @protocol.Boot]
  }
}

///|
fn[T] diagnosis_timeout_step(
  result : Result[T, Error],
  stage : String,
) -> T raise @hal.EcError {
  match result {
    Ok(value) => value
    Err(@hal.EcError::RecvTimeout) =>
      raise @hal.EcError::Internal("timeout at " + stage + " (RecvTimeout)")
    Err(@hal.EcError::MailboxTimeout) =>
      raise @hal.EcError::Internal("timeout at " + stage + " (MailboxTimeout)")
    Err(@hal.EcError::Internal(message)) if message.contains("timeout at ") =>
      raise @hal.EcError::Internal(stage + " -> " + message)
    Err(err) => raise @hal.EcError::Internal(err.to_string())
  }
}

///|
fn[N : @hal.Nic] read_al_status_snapshot_fp(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> AlStatusSnapshot raise @hal.EcError {
  let pdu = @protocol.read_register_fp(
    nic, station, @protocol.reg_al_status, 6, timeout,
  )
  if pdu.data.length() < 1 {
    raise @hal.EcError::EsmStateError("empty AL Status response")
  }
  let state = @protocol.EsmState::from_byte(pdu.data[0])
  let error_flag = (pdu.data[0] & b'\x10') != b'\x00'
  let status_code = if pdu.data.length() >= 6 {
    pdu.data[4].to_int().reinterpret_as_uint() |
    (pdu.data[5].to_int().reinterpret_as_uint() << 8)
  } else {
    0U
  }
  { state, error_flag, status_code }
}

///|
fn[N : @hal.Nic] configure_diagnosis_mailbox_sms(
  nic : N,
  station : UInt,
  eeprom : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let mapping = @mailbox.calculate_slave_mapping(eeprom, 0U)
  for i = 0; i < mapping.sm_configs.length(); i = i + 1 {
    let sm = mapping.sm_configs[i]
    match sm.sm_type {
      @mailbox.MailboxOut | @mailbox.MailboxIn => {
        let sm_addr = @protocol.reg_sm_base +
          i.reinterpret_as_uint() *
          @protocol.sm_entry_size.reinterpret_as_uint()
        let _ = @protocol.write_register_fp(
          nic,
          station,
          sm_addr,
          sm.to_bytes(),
          timeout,
        )
      }
      _ => ()
    }
  }
}

///|
fn[N : @hal.Nic] enter_diagnosis_preop(
  nic : N,
  station : UInt,
  original_state : @protocol.EsmState,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  if original_state != @protocol.Init {
    ignore(
      diagnosis_timeout_step(
        try? @protocol.transition_through(
          nic,
          station,
          @protocol.build_shutdown_path(original_state),
          timeout,
        ),
        "diagnosis.prepare.request_init_fp",
      ),
    )
  }
  let preop_snapshot = diagnosis_timeout_step(
    try? @protocol.read_al_status_snapshot(nic, station, timeout),
    "diagnosis.prepare.read_al_status_before_preop_fp",
  )
  if preop_snapshot.error_indication {
    ignore(
      diagnosis_timeout_step(
        try? @protocol.recover_al_error_for_transition(nic, station, timeout),
        "diagnosis.prepare.clear_al_error_fp",
      ),
    )
  }
  let confirmed_preop = diagnosis_timeout_step(
    try? @protocol.transition_to_target_strict(
      nic,
      station,
      @protocol.PreOp,
      timeout,
    ),
    "diagnosis.prepare.request_preop_fp",
  )
  if confirmed_preop != @protocol.PreOp {
    let status_code = try? @protocol.read_al_status_code(nic, station, timeout)
    let status_code_text = match status_code {
      Ok(code) => code.to_string()
      Err(err) => err.to_string()
    }
    raise @hal.EcError::Internal(
      "diagnosis failed to enter PreOp: actual=" +
      confirmed_preop.to_string() +
      ", AL status code=" +
      status_code_text,
    )
  }
}

///|
fn[N : @hal.Nic] diagnosis_sdo_upload_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
  stage : String,
) -> Bytes raise @hal.EcError {
  for attempt = 0; attempt < diagnosis_sdo_max_attempts; attempt = attempt + 1 {
    let result = try? diagnosis_sdo_upload_ap_once(
      nic, position, station, mb_config, rmsm, index, subindex, timeout, stage,
    )
    match result {
      Ok(payload) => return payload
      Err(@hal.EcError::Internal(message)) =>
        if message.contains("MailboxTimeout") &&
          attempt + 1 < diagnosis_sdo_max_attempts {
          rmsm.reset()
          diagnosis_drain_mailbox_fp(nic, station, mb_config)
        } else {
          raise @hal.EcError::Internal(message)
        }
      Err(@hal.EcError::MailboxTimeout) =>
        if attempt + 1 < diagnosis_sdo_max_attempts {
          rmsm.reset()
          diagnosis_drain_mailbox_fp(nic, station, mb_config)
        } else {
          raise @hal.EcError::MailboxTimeout
        }
      Err(err) => raise err
    }
  }
  raise @hal.EcError::MailboxTimeout
}

///|
fn[N : @hal.Nic] diagnosis_sdo_upload_ap_once(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
  stage : String,
) -> Bytes raise @hal.EcError {
  ignore(position)
  let counter = diagnosis_timeout_step(
    try? rmsm.begin_transaction(),
    stage + ".begin_transaction",
  )
  let txn = @mailbox.build_sdo_upload(counter, station, index, subindex)
  let frame = txn.encode()
  diagnosis_drain_mailbox_fp(nic, station, mb_config)
  let _ = diagnosis_timeout_step(
    try? @protocol.mailbox_send(nic, station, mb_config, frame, timeout),
    stage + ".mailbox_send_fp",
  )
  let response_raw = diagnosis_mailbox_recv_fp(
    nic,
    station,
    mb_config,
    rmsm,
    timeout,
    stage + ".mailbox_recv_fp",
  )
  let decoded = diagnosis_timeout_step(
    try? @mailbox.decode_sdo_response(response_raw),
    stage + ".decode_sdo_response",
  )
  let (mbh, resp) = decoded
  diagnosis_accept_response_counter(rmsm, mbh.counter)
  if resp.command != @mailbox.SdoCommand::UploadResponse {
    raise @hal.EcError::MailboxProtocol(
      stage + ": expected UploadResponse, got " + resp.command.to_string(),
    )
  }
  if resp.index != index || resp.subindex != subindex {
    raise @hal.EcError::MailboxProtocol(
      stage + ": index/subindex mismatch in response",
    )
  }
  if resp.segmented {
    raise @hal.EcError::MailboxProtocol(
      stage + ": segmented response is not supported in diagnosis path",
    )
  }
  resp.data
}

///|
fn[N : @hal.Nic] diagnosis_mailbox_recv_fp(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
  stage : String,
) -> Bytes raise @hal.EcError {
  let recv_result = try? @protocol.mailbox_recv_rmsm(
    nic,
    station,
    mb_config,
    rmsm,
    timeout,
    max_polls=diagnosis_mailbox_max_polls,
  )
  match recv_result {
    Ok(frame) => return frame
    Err(@hal.EcError::MailboxTimeout) => ()
    Err(err) => raise err
  }
  let sm0_status = diagnosis_register_snapshot(
    try? @protocol.read_register_fp(
      nic, station, @protocol.reg_sm_base, diagnosis_sm_window_size, timeout,
    ),
  )
  let sm1_status = diagnosis_register_snapshot(
    try? @protocol.read_register_fp(
      nic,
      station,
      @protocol.reg_sm_base + @protocol.sm_entry_size.reinterpret_as_uint(),
      diagnosis_sm_window_size,
      timeout,
    ),
  )
  let al_status = diagnosis_register_snapshot(
    try? @protocol.read_register_fp(
      nic, station, @protocol.reg_al_status, 2, timeout,
    ),
  )
  raise @hal.EcError::Internal(
    "timeout at " +
    stage +
    ".read_frame (MailboxTimeout; SM0=" +
    sm0_status +
    "; SM1=" +
    sm1_status +
    "; AL=" +
    al_status +
    ")",
  )
}

///|
fn[N : @hal.Nic] diagnosis_drain_mailbox_fp(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
) -> Unit {
  let zero_timeout = @hal.Duration(0L)
  let poll_result = try? @protocol.mailbox_poll(
    nic, station, mb_config, zero_timeout,
  )
  match poll_result {
    Ok(true) =>
      ignore(
        try? @protocol.mailbox_recv(
          nic,
          station,
          mb_config,
          zero_timeout,
          max_polls=1,
        ),
      )
    _ => ()
  }
}

///|
fn diagnosis_register_snapshot(result : Result[@protocol.Pdu, Error]) -> String {
  match result {
    Ok(pdu) => diagnosis_bytes_preview(pdu.data)
    Err(err) => "error=" + err.to_string()
  }
}

///|
fn diagnosis_accept_response_counter(
  rmsm : @mailbox.Rmsm,
  counter : Byte,
) -> Unit raise @hal.EcError {
  let validation = try? rmsm.validate_response(counter)
  match validation {
    Ok(_) => ()
    Err(@hal.EcError::MailboxProtocol(message)) =>
      if message.contains("counter mismatch") {
        rmsm.reset()
      } else {
        raise @hal.EcError::MailboxProtocol(message)
      }
    Err(err) => raise err
  }
}

///|
fn diagnosis_bytes_preview(data : Bytes) -> String {
  if data.length() == 0 {
    return "<empty>"
  }
  let mut rendered = ""
  for i = 0; i < data.length(); i = i + 1 {
    if i > 0 {
      rendered = rendered + " "
    }
    rendered = rendered + diagnosis_hex_byte(data[i])
  }
  rendered
}

///|
fn diagnosis_hex_byte(value : Byte) -> String {
  "0x" +
  diagnosis_hex_digit((value.to_int() >> 4) & 0xF) +
  diagnosis_hex_digit(value.to_int() & 0xF)
}

///|
fn diagnosis_hex_digit(value : Int) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "A"
    11 => "B"
    12 => "C"
    13 => "D"
    14 => "E"
    _ => "F"
  }
}
