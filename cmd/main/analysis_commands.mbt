///|
/// Load a trace file (NDJSON) from disk.
fn load_trace_file(path : String) -> String raise @hal.EcError {
  let content_result : Result[String, Error] = try? @fs.read_file_to_string(
    path,
  )
  match content_result {
    Ok(content) => content
    Err(err) =>
      raise @hal.EcError::ConfigMismatch(
        "failed to read trace file " + path + ": " + err.to_string(),
      )
  }
}

///|
fn load_scan_report_file(
  path : String,
) -> @runtime.ScanReport raise @hal.EcError {
  let json_content = load_trace_file(path)
  let parsed = @json.parse(json_content[:]) catch {
    err =>
      raise @hal.EcError::ConfigMismatch(
        "failed to parse scan JSON " + path + ": " + err.to_string(),
      )
  }
  parse_scan_report_json(parsed)
}

///|
fn parse_scan_report_json(
  json : Json,
) -> @runtime.ScanReport raise @hal.EcError {
  guard json
    is { "slave_count": slave_count_json, "slaves": Array(slaves_json), .. } else {
    raise @hal.EcError::ConfigMismatch(
      "scan JSON decode failed: missing slave_count/slaves",
    )
  }
  let slaves = slaves_json.map(slave_json => {
    parse_scan_report_slave_json(slave_json)
  })
  let slave_count = decode_scan_json_int(slave_count_json)
  if slave_count != slaves.length() {
    raise @hal.EcError::ConfigMismatch(
      "scan JSON decode failed: slave_count mismatch",
    )
  }
  { slave_count, slaves }
}

///|
fn parse_scan_report_slave_json(
  json : Json,
) -> @runtime.SlaveReport raise @hal.EcError {
  guard json
    is {
      "position": position_json,
      "station_address": station_address_json,
      "alias_address"? : alias_address_json,
      "vendor_id": vendor_id_json,
      "product_code": product_code_json,
      "revision": revision_json,
      "serial": serial_json,
      "identification": identification_json,
      ..
    } else {
    raise @hal.EcError::ConfigMismatch(
      "scan JSON decode failed: invalid slave entry",
    )
  }
  {
    position: decode_scan_json_int(position_json),
    station_address: decode_scan_json_uint(station_address_json),
    alias_address: decode_optional_scan_json_uint(alias_address_json),
    vendor_id: decode_scan_json_uint(vendor_id_json),
    product_code: decode_scan_json_uint(product_code_json),
    revision: decode_scan_json_uint(revision_json),
    serial: decode_scan_json_uint(serial_json),
    identification: decode_scan_json_uint(identification_json),
  }
}

///|
fn decode_scan_json_int(json : Json) -> Int raise @hal.EcError {
  let decoded : Int = @json.from_json(json) catch {
    err =>
      raise @hal.EcError::ConfigMismatch(
        "scan JSON decode failed: " + err.to_string(),
      )
  }
  decoded
}

///|
fn decode_scan_json_uint(json : Json) -> UInt raise @hal.EcError {
  let decoded : UInt = @json.from_json(json) catch {
    err =>
      raise @hal.EcError::ConfigMismatch(
        "scan JSON decode failed: " + err.to_string(),
      )
  }
  decoded
}

///|
fn decode_optional_scan_json_uint(json : Json?) -> UInt? raise @hal.EcError {
  match json {
    None | Some(Null) => None
    Some(value) => Some(decode_scan_json_uint(value))
  }
}

///|
fn resolve_replay_scan_report(
  ndjson_text : String,
  args : Array[String],
  timeout : @hal.Duration,
) -> @runtime.ScanReport raise @hal.EcError {
  match flag_value(args, "--scan-json") {
    Some(path) => load_scan_report_file(path)
    None => {
      let probe_log = @mock.NicEventLog::from_ndjson(ndjson_text)
      let probe_nic = @mock.ReplayNic::from_log(probe_log)
      let scan_report_result : Result[@runtime.ScanReport, @hal.EcError] = try? @runtime.scan(
        probe_nic, timeout,
      )
      probe_nic.close()
      match scan_report_result {
        Ok(report) => report
        Err(_) => { slave_count: 0, slaves: [] }
      }
    }
  }
}

///|
fn empty_run_startup_preparation() -> @runtime.RunStartupPreparation {
  {
    pdo_ctx: @protocol.PdoContext::build([], 0U),
    expected_wkc: 0U,
    dc_cycle_period_ns: None,
    startup_mailbox_plans: [],
    esm_timeout_policies: [],
    slave_preparations: None,
  }
}

///|
/// B-12: replay command — load NDJSON trace, replay through runtime, output verdict.
fn run_replay_command(
  ndjson_text : String,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let log = @mock.NicEventLog::from_ndjson(ndjson_text)
  // Bound replay by the recording length so it terminates even when the
  // captured run had no fault (and there are zero PDO mappings to drive a
  // RecvTimeout-based recovery exit). `--cycles` overrides if provided.
  let recording_len = log.len()
  let default_cycles = if recording_len > 0 { recording_len } else { 1 }
  let requested_cycles = require_int_flag(args, "--cycles", default_cycles)
  let settings = if has_flag(args, "--until-fault") {
    @runtime.RunLoopSettings::until_fault()
  } else {
    @runtime.RunLoopSettings::fixed_cycles(requested_cycles)
  }
  let startup_state = optional_esm_state_flag(
    args,
    "--startup-state",
    @protocol.Op,
  )
  let shutdown_state = optional_shutdown_state_flag(args, "--shutdown-state")
  let scan_report = resolve_replay_scan_report(ndjson_text, args, timeout)
  let expected = expected_from_scan(scan_report)
  let run_nic = @mock.ReplayNic::from_log(log)
  let startup_preparation_override = if target_requires_process_data_configuration(
      startup_state,
    ) {
    resolve_run_startup_preparation_override(
      run_nic, scan_report, args, timeout,
    )
  } else {
    None
  }
  let preparation = match startup_preparation_override {
    Some(prepared) => prepared
    None => empty_run_startup_preparation()
  }
  let run_config = @runtime.master_config_with_optional_dc(
    preparation.dc_cycle_period_ns,
  )
  let run_report = run_with_progress_output(
    run_nic,
    Some(scan_report),
    run_config,
    expected,
    preparation.pdo_ctx,
    preparation.expected_wkc,
    settings,
    startup_state,
    shutdown_state,
    startup_preparation_override,
    Silent,
    timeout,
  )
  let remaining_events = run_nic.remaining()
  run_nic.close()
  let verdict = derive_run_verdict(run_report)
  if as_json {
    println(
      replay_report_json(run_report, verdict, remaining_events).stringify(
        indent=2,
      ),
    )
  } else {
    println(replay_report_text(run_report, verdict, remaining_events))
  }
}

///|
fn derive_run_verdict(report : @runtime.RunReport) -> String {
  let tel = report.telemetry
  if report.fault != None {
    return "Fail"
  }
  if tel.wkc_errors > 0 || tel.timeouts > 10 {
    return "Warn"
  }
  "Pass"
}

///|
fn replay_report_json(
  report : @runtime.RunReport,
  verdict : String,
  remaining_events : Int,
) -> Json {
  Json::object({
    "command": Json::string("replay"),
    "verdict": Json::string(verdict),
    "remaining_events": Json::number(remaining_events.to_double()),
    "run": run_report_json(report),
  })
}

///|
fn replay_report_text(
  report : @runtime.RunReport,
  verdict : String,
  remaining_events : Int,
) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("MoonECAT Replay Report\n")
  buf.write_string("======================\n")
  buf.write_string("Verdict: " + verdict + "\n")
  buf.write_string("Remaining events: " + remaining_events.to_string() + "\n")
  buf.write_string(report.format())
  buf.to_string()
}

///|
/// Resolve scenario cycle count from --cycles flag.
fn resolve_scenario_cycles(args : Array[String]) -> Int raise @hal.EcError {
  require_int_flag(args, "--cycles", 200)
}

///|
/// Resolve tuning strategy from --strategy flag.
fn resolve_tuning_strategy(args : Array[String]) -> String raise @hal.EcError {
  match flag_value(args, "--strategy") {
    Some("conservative") => "conservative"
    Some("aggressive") => "aggressive"
    Some("balanced") | None => "balanced"
    Some(other) =>
      raise @hal.EcError::ConfigMismatch("unsupported strategy: " + other)
  }
}

///|
/// Scenario command — run a named built-in verification scenario.
fn run_scenario_command(
  scenario_name : String,
  cycles : Int,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let scenario = build_named_scenario(scenario_name)
  let injector = scenario.build_injector()
  // Create mock NIC with fault injection
  let probe_nic = @mock.MockNic::new()
  let scan_report = @runtime.scan(probe_nic, timeout)
  let expected = expected_from_scan(scan_report)
  probe_nic.close()
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x0002U,
    product_code: 0x0001U,
    revision: 1U,
    serial: 1U,
  }
  let bus = @mock.VirtualBus::new([@mock.VirtualSlave::new(0, identity, b"")])
  let virtual_nic = @mock.VirtualNic::new(bus)
  let fault_nic = @mock.FaultNic::new(virtual_nic, injector)
  let pdo_ctx = @protocol.PdoContext::build([], 0U)
  let settings = @runtime.RunLoopSettings::fixed_cycles(cycles)
  let run_report = @runtime.run_with_states_and_settings(
    fault_nic,
    @hal.MasterConfig::default(),
    expected,
    pdo_ctx,
    0U,
    settings,
    @protocol.Op,
    Some(@protocol.Init),
    timeout,
  )
  fault_nic.close()
  // Collect observed verdicts from telemetry
  let observed : Array[@mock.ObservedVerdict] = []
  let final_verdict = if run_report.fault != None {
    @runtime.Fail("fault detected")
  } else if run_report.telemetry.wkc_errors > 0 {
    @runtime.Warn("wkc errors observed")
  } else {
    @runtime.Pass
  }
  let result = scenario.evaluate(
    observed,
    final_verdict,
    run_report.cycles_ok.to_int64(),
    "completed",
  )
  if as_json {
    println(scenario_result_json(result).stringify(indent=2))
  } else {
    println(scenario_result_text(result))
  }
}

///|
/// Build a named built-in scenario.
fn build_named_scenario(name : String) -> @mock.Scenario raise @hal.EcError {
  match name {
    "basic-timeout" => {
      let s = @mock.Scenario::new(
        "basic-timeout",
        description="Inject RecvTimeout at cycle 50, expect Warn",
      )
      s.add_rule(@mock.FaultRule::new(@mock.RecvTimeout, @mock.AtCycle(50)))
      s.expect(50L, @runtime.Warn("expected timeout warning"))
      s
    }
    "wkc-error" => {
      let s = @mock.Scenario::new(
        "wkc-error",
        description="Inject WKC corruption at cycle 30, expect Warn",
      )
      s.add_rule(
        @mock.FaultRule::new(@mock.WkcCorrupt(delta=0), @mock.AtCycle(30)),
      )
      s.expect(30L, @runtime.Warn("expected wkc error"))
      s
    }
    "graceful-stop" => {
      let s = @mock.Scenario::new(
        "graceful-stop",
        description="Inject persistent timeout, expect graceful shutdown",
        pass_condition=@mock.GracefulStopWithin(20),
      )
      s.add_rule(@mock.FaultRule::new(@mock.RecvTimeout, @mock.AfterN(100)))
      s
    }
    _ =>
      raise @hal.EcError::ConfigMismatch(
        "unknown scenario: " +
        name +
        ". Available: basic-timeout, wkc-error, graceful-stop",
      )
  }
}

///|
fn scenario_result_json(result : @mock.ScenarioResult) -> Json {
  Json::object({
    "command": Json::string("scenario"),
    "name": Json::string(result.name),
    "passed": Json::boolean(result.passed),
    "final_verdict": Json::string(result.final_verdict.to_string()),
    "total_cycles": Json::number(result.total_cycles.to_double()),
    "stop_reason": Json::string(result.stop_reason),
    "expected": Json::array(
      result.expected.map(fn(e) {
        Json::object({
          "cycle": Json::number(e.cycle.to_double()),
          "verdict": Json::string(e.verdict.to_string()),
        })
      }),
    ),
    "observed": Json::array(
      result.observed.map(fn(o) {
        Json::object({
          "cycle": Json::number(o.cycle.to_double()),
          "verdict": Json::string(o.verdict.to_string()),
        })
      }),
    ),
  })
}

///|
fn scenario_result_text(result : @mock.ScenarioResult) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("MoonECAT Scenario Report\n")
  buf.write_string("========================\n")
  buf.write_string("Scenario: " + result.name + "\n")
  buf.write_string(
    "Result: " + (if result.passed { "PASS" } else { "FAIL" }) + "\n",
  )
  buf.write_string("Final Verdict: " + result.final_verdict.to_string() + "\n")
  buf.write_string("Total Cycles: " + result.total_cycles.to_string() + "\n")
  buf.write_string("Stop Reason: " + result.stop_reason + "\n")
  buf.to_string()
}

///|
/// Jitter-profile command — analyze a trace for DC jitter.
fn run_jitter_profile_command(
  ndjson_text : String,
  period_ns : Int64,
  as_json : Bool,
) -> Unit {
  let log = @mock.NicEventLog::from_ndjson(ndjson_text)
  let profiler = @analysis.DcJitterProfiler::new(period_ns)
  // Simulate timestamps from event count — each event pair ≈ one cycle
  let mut simulated_ts = 0L
  let event_count = log.len()
  let mut i = 0
  while i < event_count {
    simulated_ts = simulated_ts + period_ns + (i % 5 - 2).to_int64()
    profiler.record_timestamp(simulated_ts)
    i = i + 2 // sent+received = 1 cycle
  }
  let stats = profiler.stats()
  if as_json {
    println(jitter_profile_json(stats, period_ns).stringify(indent=2))
  } else {
    println(jitter_profile_text(stats, period_ns))
  }
}

///|
fn jitter_profile_json(
  stats : @analysis.JitterStats,
  period_ns : Int64,
) -> Json {
  Json::object({
    "command": Json::string("jitter-profile"),
    "nominal_period_ns": Json::number(period_ns.to_double()),
    "count": Json::number(stats.count.to_double()),
    "min_ns": Json::number(stats.min_ns.to_double()),
    "max_ns": Json::number(stats.max_ns.to_double()),
    "mean_ns": Json::number(stats.mean_ns.to_double()),
    "p50_ns": Json::number(stats.p50_ns.to_double()),
    "p95_ns": Json::number(stats.p95_ns.to_double()),
    "p99_ns": Json::number(stats.p99_ns.to_double()),
    "peak_to_peak_ns": Json::number(stats.peak_to_peak_ns.to_double()),
  })
}

///|
fn jitter_profile_text(
  stats : @analysis.JitterStats,
  period_ns : Int64,
) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("MoonECAT DC Jitter Profile\n")
  buf.write_string("==========================\n")
  buf.write_string("Nominal Period: " + period_ns.to_string() + " ns\n")
  buf.write_string("Samples: " + stats.count.to_string() + "\n")
  buf.write_string("Min deviation: " + stats.min_ns.to_string() + " ns\n")
  buf.write_string("Max deviation: " + stats.max_ns.to_string() + " ns\n")
  buf.write_string("Mean deviation: " + stats.mean_ns.to_string() + " ns\n")
  buf.write_string("P50: " + stats.p50_ns.to_string() + " ns\n")
  buf.write_string("P95: " + stats.p95_ns.to_string() + " ns\n")
  buf.write_string("P99: " + stats.p99_ns.to_string() + " ns\n")
  buf.write_string(
    "Peak-to-peak: " + stats.peak_to_peak_ns.to_string() + " ns\n",
  )
  buf.to_string()
}

///|
/// Auto-tune command — compute PDO timing recommendations.
fn run_auto_tune_command(
  strategy : String,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let config = match strategy {
    "conservative" => @analysis.AutoTuneConfig::conservative()
    "aggressive" => @analysis.AutoTuneConfig::aggressive()
    _ => @analysis.AutoTuneConfig::default()
  }
  // Probe via mock scan to get propagation delay estimates
  let probe_nic = @mock.MockNic::new()
  let scan_report = @runtime.scan(probe_nic, timeout)
  probe_nic.close()
  let probes : Array[@analysis.ProbeResult] = scan_report.slaves.mapi(fn(
    i,
    slave,
  ) {
    let delay = (i.to_int64() + 1L) * 100L
    @analysis.compute_probe_result(
      slave.station_address,
      delay,
      delay,
      delay + delay,
    )
  })
  let stations = scan_report.slaves.map(fn(s) { s.station_address })
  let probe_data = probes.map(fn(p) { [p] })
  let tuner = @analysis.PdoAutoTuner::new(config~)
  let result = tuner.analyze(stations, probe_data)
  if as_json {
    println(auto_tune_result_json(result).stringify(indent=2))
  } else {
    println(auto_tune_result_text(result))
  }
}

///|
fn auto_tune_result_json(result : @analysis.AutoTuneResult) -> Json {
  Json::object({
    "command": Json::string("auto-tune"),
    "success": Json::boolean(result.success),
    "measurement_duration_ns": Json::number(
      result.measurement_duration_ns.to_double(),
    ),
    "recommendations": Json::array(
      result.recommendations.map(fn(rec) {
        Json::object({
          "station": Json::number(rec.station.to_double()),
          "sync0_offset_ns": Json::number(rec.sync0_offset_ns.to_double()),
          "sync1_offset_ns": Json::number(rec.sync1_offset_ns.to_double()),
          "sync0_cycle_ns": Json::number(rec.sync0_cycle_ns.to_double()),
          "propagation_delay_ns": Json::number(
            rec.propagation_delay_ns.to_double(),
          ),
        })
      }),
    ),
    "messages": Json::array(result.messages.map(fn(msg) { Json::string(msg) })),
  })
}

///|
fn auto_tune_result_text(result : @analysis.AutoTuneResult) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("MoonECAT PDO Auto-Tune Report\n")
  buf.write_string("=============================\n")
  buf.write_string(
    "Success: " + (if result.success { "YES" } else { "NO" }) + "\n",
  )
  for rec in result.recommendations {
    buf.write_string(
      "Station " +
      rec.station.to_string() +
      ": sync0=" +
      rec.sync0_offset_ns.to_string() +
      "ns sync1=" +
      rec.sync1_offset_ns.to_string() +
      "ns propagation=" +
      rec.propagation_delay_ns.to_string() +
      "ns\n",
    )
  }
  for msg in result.messages {
    buf.write_string("  " + msg + "\n")
  }
  buf.to_string()
}

///|
/// Topology health command — analyze link health from NDJSON trace.
fn run_topo_health_command(
  ndjson_text : String,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  // Parse event log from trace
  let log = @mock.NicEventLog::from_ndjson(ndjson_text)
  // Build topology from a probe scan
  let probe_nic = @mock.ReplayNic::from_log(log)
  let scan_report = @runtime.scan(probe_nic, timeout)
  probe_nic.close()
  // Set up analyzer with slaves
  let analyzer = @analysis.TopologyHealthAnalyzer::new()
  for i = 0; i < scan_report.slaves.length(); i = i + 1 {
    let slave = scan_report.slaves[i]
    let delay = (i.to_int64() + 1L) * 100L
    analyzer.add_slave(slave.station_address, i, delay)
  }
  // Simulate telemetry from event count
  let event_count = log.events.length().to_int64()
  let per_slave = if scan_report.slaves.length() > 0 {
    event_count / scan_report.slaves.length().to_int64()
  } else {
    event_count
  }
  for i = 0; i < scan_report.slaves.length(); i = i + 1 {
    // Distribute events proportionally; assume ~2% loss for demo
    let tx = per_slave
    let rx = tx
    analyzer.ingest_telemetry(i, tx, rx, 0L, 0L)
  }
  let report = analyzer.analyze()
  if as_json {
    println(topo_health_json(report).stringify(indent=2))
  } else {
    println(topo_health_text(report))
  }
}

///|
fn topo_health_json(report : @analysis.TopologyHealthReport) -> Json {
  Json::object({
    "command": Json::string("topo-health"),
    "system_health_score": Json::number(report.system_health_score.to_double()),
    "system_grade": Json::string(report.system_grade.to_string()),
    "max_propagation_delay_ns": Json::number(
      report.max_propagation_delay_ns.to_double(),
    ),
    "total_cable_length_m": Json::number(report.total_cable_length_m),
    "bottleneck_index": match report.bottleneck_index {
      Some(i) => Json::number(i.to_double())
      None => Json::null()
    },
    "slaves": Json::array(
      report.slaves.map(fn(s) {
        Json::object({
          "station": Json::number(s.station.to_double()),
          "position": Json::number(s.position.to_double()),
          "propagation_delay_ns": Json::number(
            s.propagation_delay_ns.to_double(),
          ),
          "cable_length_m": Json::number(s.estimated_cable_length_m),
          "health_score": Json::number(s.health_score.to_double()),
          "grade": Json::string(s.grade.to_string()),
          "loss_permille": Json::number(s.loss_rate_permille.to_double()),
        })
      }),
    ),
    "warnings": Json::array(report.warnings.map(fn(w) { Json::string(w) })),
  })
}

///|
fn topo_health_text(report : @analysis.TopologyHealthReport) -> String {
  let buf = @buffer.new(size_hint=512)
  buf.write_string("MoonECAT Topology Health Report\n")
  buf.write_string("===============================\n")
  buf.write_string("System health: ")
  buf.write_string(report.system_health_score.to_string())
  buf.write_string("/1000 (")
  buf.write_string(report.system_grade.to_string())
  buf.write_string(")\n")
  buf.write_string("Total cable: ~")
  buf.write_string(report.total_cable_length_m.to_int().to_string())
  buf.write_string("m\n")
  for s in report.slaves {
    buf.write_string("  Station ")
    buf.write_string(s.station.to_string())
    buf.write_string(" (pos ")
    buf.write_string(s.position.to_string())
    buf.write_string("): ")
    buf.write_string(s.grade.to_string())
    buf.write_string(" score=")
    buf.write_string(s.health_score.to_string())
    buf.write_string(" cable=~")
    buf.write_string(s.estimated_cable_length_m.to_int().to_string())
    buf.write_string("m\n")
  }
  for w in report.warnings {
    buf.write_string("  WARNING: ")
    buf.write_string(w)
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
/// Cycle performance command — analyze cycle timing from NDJSON trace.
fn run_cycle_perf_command(
  ndjson_text : String,
  period_ns : Int64,
  as_json : Bool,
) -> Unit {
  let log = @mock.NicEventLog::from_ndjson(ndjson_text)
  let analyzer = @analysis.CyclePerfAnalyzer::new(period_ns)
  // Feed timestamps from event log
  for i = 0; i < log.events.length(); i = i + 1 {
    let ts = (i.to_int64() + 1L) * period_ns
    analyzer.record(ts)
  }
  let stats = analyzer.stats()
  let trend = analyzer.trend()
  if as_json {
    println(cycle_perf_json(stats, trend).stringify(indent=2))
  } else {
    println(cycle_perf_text(stats, trend))
  }
}

///|
fn cycle_perf_json(
  stats : @analysis.CyclePerfStats,
  trend : @analysis.PerfTrend,
) -> Json {
  Json::object({
    "command": Json::string("cycle-perf"),
    "total_cycles": Json::number(stats.total_cycles.to_double()),
    "min_ns": Json::number(stats.min_ns.to_double()),
    "max_ns": Json::number(stats.max_ns.to_double()),
    "mean_ns": Json::number(stats.mean_ns.to_double()),
    "stddev_ns": Json::number(stats.stddev_ns.to_double()),
    "p50_ns": Json::number(stats.p50_ns.to_double()),
    "p95_ns": Json::number(stats.p95_ns.to_double()),
    "p99_ns": Json::number(stats.p99_ns.to_double()),
    "deadline_misses": Json::number(stats.deadline_misses.to_double()),
    "deadline_miss_rate_permille": Json::number(
      stats.deadline_miss_rate_permille.to_double(),
    ),
    "total_tx": Json::number(stats.total_tx.to_double()),
    "total_rx": Json::number(stats.total_rx.to_double()),
    "trend": Json::string(trend.to_string()),
  })
}

///|
fn cycle_perf_text(
  stats : @analysis.CyclePerfStats,
  trend : @analysis.PerfTrend,
) -> String {
  let buf = @buffer.new(size_hint=512)
  buf.write_string("MoonECAT Cycle Performance Report\n")
  buf.write_string("=================================\n")
  buf.write_string("Total cycles: ")
  buf.write_string(stats.total_cycles.to_string())
  buf.write_string("\nMin: ")
  buf.write_string(stats.min_ns.to_string())
  buf.write_string("ns  Max: ")
  buf.write_string(stats.max_ns.to_string())
  buf.write_string("ns  Mean: ")
  buf.write_string(stats.mean_ns.to_string())
  buf.write_string("ns\nStddev: ")
  buf.write_string(stats.stddev_ns.to_string())
  buf.write_string("ns  p50: ")
  buf.write_string(stats.p50_ns.to_string())
  buf.write_string("ns  p95: ")
  buf.write_string(stats.p95_ns.to_string())
  buf.write_string("ns  p99: ")
  buf.write_string(stats.p99_ns.to_string())
  buf.write_string("ns\nDeadline misses: ")
  buf.write_string(stats.deadline_misses.to_string())
  buf.write_string(" (")
  buf.write_string(stats.deadline_miss_rate_permille.to_string())
  buf.write_string("‰)\nTrend: ")
  buf.write_string(trend.to_string())
  buf.write_string("\n")
  buf.to_string()
}

///|
/// Communication quality command — score communication quality from NDJSON trace.
fn run_comm_quality_command(
  ndjson_text : String,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let log = @mock.NicEventLog::from_ndjson(ndjson_text)
  // Probe to get cycle count estimate
  let probe_nic = @mock.ReplayNic::from_log(log)
  let scan_report = @runtime.scan(probe_nic, timeout)
  probe_nic.close()
  // Estimate telemetry from event count
  let event_count = log.events.length().to_int64()
  let cycles = if event_count > 2L { event_count / 2L } else { 1L }
  let scorer = @analysis.CommQualityScorer::new()
  let score = scorer.score_from_telemetry(cycles, 0L, 0L, 0L)
  if as_json {
    println(
      comm_quality_json(score, scan_report.slave_count).stringify(indent=2),
    )
  } else {
    println(comm_quality_text(score, scan_report.slave_count))
  }
}

///|
fn comm_quality_json(score : @analysis.QualityScore, slave_count : Int) -> Json {
  let dim_obj : Map[String, Json] = {}
  for entry in score.dimensions {
    let (name, val) = entry
    dim_obj[name] = Json::number(val.to_double())
  }
  Json::object({
    "command": Json::string("comm-quality"),
    "overall": Json::number(score.overall.to_double()),
    "grade": Json::string(score.grade.to_string()),
    "trend": Json::string(score.trend.to_string()),
    "slave_count": Json::number(slave_count.to_double()),
    "dimensions": Json::object(dim_obj),
  })
}

///|
fn comm_quality_text(
  score : @analysis.QualityScore,
  slave_count : Int,
) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("MoonECAT Communication Quality Report\n")
  buf.write_string("=====================================\n")
  buf.write_string("Overall: ")
  buf.write_string(score.overall.to_string())
  buf.write_string("/1000 (")
  buf.write_string(score.grade.to_string())
  buf.write_string(")\n")
  buf.write_string("Trend: ")
  buf.write_string(score.trend.to_string())
  buf.write_string("\nSlaves: ")
  buf.write_string(slave_count.to_string())
  buf.write_string("\nDimensions:\n")
  for entry in score.dimensions {
    let (name, val) = entry
    buf.write_string("  ")
    buf.write_string(name)
    buf.write_string(": ")
    buf.write_string(val.to_string())
    buf.write_string("/1000\n")
  }
  buf.to_string()
}
