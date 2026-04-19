///|
fn run_mock_command_with_fresh_nic(
  as_json : Bool,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  settings : @runtime.RunLoopSettings,
  progress_output : RunProgressOutput,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let probe_nic = @mock.MockNic::new()
  let scan_report = @runtime.scan(probe_nic, timeout)
  let expected = expected_from_scan(scan_report)
  probe_nic.close()
  let run_nic = @mock.MockNic::new()
  let pdo_ctx = @protocol.PdoContext::build([], 0U)
  let run_report = run_with_progress_output(
    run_nic,
    None,
    @hal.MasterConfig::default(),
    expected,
    pdo_ctx,
    0U,
    settings,
    startup_state,
    shutdown_state,
    None,
    progress_output,
    timeout,
  )
  run_nic.close()
  if as_json && progress_output != Ndjson {
    println(run_report_json(run_report).stringify(indent=2))
  } else if as_json {
    println(run_report_ndjson(run_report).stringify())
  } else {
    println(run_report.format())
  }
}

///|
fn run_native_command_with_fresh_nic(
  config : @native.NativeNicConfig,
  args : Array[String],
  as_json : Bool,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  settings : @runtime.RunLoopSettings,
  progress_output : RunProgressOutput,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let probe_nic = @native.NativeNic::open_with_config(config)
  let scan_report = @runtime.scan(probe_nic, timeout)
  let expected = expected_from_scan(scan_report)
  probe_nic.close()
  let run_nic = @native.NativeNic::open_with_config(config)
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
    None =>
      if target_requires_process_data_configuration(startup_state) {
        @runtime.build_run_startup_preparation(
          run_nic, scan_report, pdo_logical_base, process_data_eeprom_word_count,
          timeout,
        )
      } else {
        {
          pdo_ctx: @protocol.PdoContext::build([], 0U),
          expected_wkc: 0U,
          dc_cycle_period_ns: None,
          startup_mailbox_plans: [],
          esm_timeout_policies: [],
          slave_preparations: None,
        }
      }
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
    progress_output,
    timeout,
  )
  run_nic.close()
  if as_json && progress_output != Ndjson {
    println(run_report_json(run_report).stringify(indent=2))
  } else if as_json {
    println(run_report_ndjson(run_report).stringify())
  } else {
    println(run_report.format())
  }
}

///|
/// run-zc mock backend: create MockZeroCopyNic, run N zero-copy PDO cycles.
fn run_zc_mock_command(
  cycles : Int,
  pool_capacity : Int,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let pool = @hal.FramePool::new(capacity=pool_capacity)
  let nic = @mock.MockZeroCopyNic::new(pool)
  let ctx = @protocol.MutablePdoContext::build([], 0U)
  let mut ok_count = 0
  let mut timeout_count = 0L
  let mut wkc_errors = 0L
  for _i = 0; _i < cycles; _i = _i + 1 {
    let result = @protocol.pdo_exchange_zero_copy(nic, ctx, timeout) catch {
      @hal.EcError::RecvTimeout => {
        timeout_count = timeout_count + 1L
        continue
      }
      err => raise err
    }
    if result.wkc >= 0U {
      ok_count = ok_count + 1
    } else {
      wkc_errors = wkc_errors + 1L
    }
  }
  nic.close()
  let report = zc_run_report(cycles, ok_count, timeout_count, wkc_errors)
  if as_json {
    println(report.stringify(indent=2))
  } else {
    println(zc_run_report_text(cycles, ok_count, timeout_count, wkc_errors))
  }
}

///|
/// run-zc native backend: scan with Nic, transition states, then zero-copy PDO hot loop.
fn run_zc_native_command(
  config : @native.NativeNicConfig,
  args : Array[String],
  cycles : Int,
  pool_capacity : Int,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  // Phase 1: probe/scan using standard Nic
  let probe_nic = @native.NativeNic::open_with_config(config)
  let scan_report = @runtime.scan(probe_nic, timeout)
  probe_nic.close()
  // Phase 2: state transitions using standard Nic
  let setup_nic = @native.NativeNic::open_with_config(config)
  let startup_state = optional_esm_state_flag(
    args,
    "--startup-state",
    @protocol.Op,
  )
  let shutdown_state = optional_shutdown_state_flag(args, "--shutdown-state")
  let stations = scan_report.slaves.map(fn(s) { s.station_address })
  let preparation = if target_requires_process_data_configuration(startup_state) {
    @runtime.build_run_startup_preparation(
      setup_nic, scan_report, pdo_logical_base, process_data_eeprom_word_count, timeout,
    )
  } else {
    {
      pdo_ctx: @protocol.PdoContext::build([], 0U),
      expected_wkc: 0U,
      dc_cycle_period_ns: None,
      startup_mailbox_plans: [],
      esm_timeout_policies: [],
      slave_preparations: None,
    }
  }
  // Transition to target state
  if scan_report.slave_count > 0 {
    for station in stations {
      ignore(
        try? @protocol.transition_to_target_strict(
          setup_nic, station, startup_state, timeout,
        ),
      )
    }
  }
  setup_nic.close()
  // Phase 3: zero-copy hot loop using NativeZeroCopyNic
  let pool = @hal.FramePool::new(capacity=pool_capacity)
  let zc_nic = @native.NativeZeroCopyNic::open_with_config(config, pool)
  // Build MutablePdoContext from the same slave mappings
  let zc_ctx = build_mutable_pdo_context_from_preparation(preparation)
  let mut ok_count = 0
  let mut timeout_count = 0L
  let mut wkc_errors = 0L
  for _i = 0; _i < cycles; _i = _i + 1 {
    let result = @protocol.pdo_exchange_zero_copy(zc_nic, zc_ctx, timeout) catch {
      @hal.EcError::RecvTimeout => {
        timeout_count = timeout_count + 1L
        continue
      }
      err => raise err
    }
    if result.wkc >= preparation.expected_wkc {
      ok_count = ok_count + 1
    } else {
      wkc_errors = wkc_errors + 1L
    }
  }
  zc_nic.close()
  // Phase 4: shutdown using standard Nic
  match shutdown_state {
    Some(target) => {
      let shutdown_nic = @native.NativeNic::open_with_config(config)
      for station in stations {
        ignore(
          try? @protocol.transition_to_target_strict(
            shutdown_nic, station, target, timeout,
          ),
        )
      }
      shutdown_nic.close()
    }
    None => ()
  }
  let report = zc_run_report(cycles, ok_count, timeout_count, wkc_errors)
  if as_json {
    println(report.stringify(indent=2))
  } else {
    println(zc_run_report_text(cycles, ok_count, timeout_count, wkc_errors))
  }
}

///|
/// Build MutablePdoContext from a RunStartupPreparation (reuses slave mappings).
fn build_mutable_pdo_context_from_preparation(
  preparation : @runtime.RunStartupPreparation,
) -> @protocol.MutablePdoContext {
  // Mirror the slave mappings from PdoContext into MutablePdoContext
  let pdo_ctx = preparation.pdo_ctx
  let slave_mappings : Array[(@mailbox.SlaveMapping, UInt)] = []
  for m in pdo_ctx.mappings {
    slave_mappings.push(
      (
        {
          sm_configs: [],
          fmmu_configs: [],
          output_bytes: m.output_length,
          input_bytes: m.input_length,
        },
        m.station,
      ),
    )
  }
  @protocol.MutablePdoContext::build(slave_mappings, pdo_ctx.logical_base)
}

///|
/// run-virtual: build VirtualBus from ESI JSON, scan, configure, and run.
fn run_virtual_command(
  json_content : String,
  as_json : Bool,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  settings : @runtime.RunLoopSettings,
  progress_output : RunProgressOutput,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let (bus, templates) = @mock.VirtualBus::from_esi_json(json_content)
  let nic = @mock.VirtualNic::new(bus)
  // Phase 1: scan to discover virtual slaves + assign station addresses
  let scan_report = @runtime.scan(nic, timeout)
  let expected = expected_from_scan(scan_report)
  // Phase 2: build startup preparation from ESI templates
  let startup_preparation = if target_requires_process_data_configuration(
      startup_state,
    ) &&
    templates.length() > 0 {
    let slave_preparations : Array[(UInt, @runtime.SlaveStartupPreparation)] = []
    for i = 0; i < templates.length(); i = i + 1 {
      if i < scan_report.slaves.length() {
        let station = scan_report.slaves[i].station_address
        slave_preparations.push((station, templates[i].startup_preparation))
      }
    }
    Some(
      @runtime.run_startup_preparation_from_slave_preparations(
        slave_preparations, pdo_logical_base,
      ),
    )
  } else {
    None
  }
  // Phase 3: run loop
  let (pdo_ctx, expected_wkc) = match startup_preparation {
    Some(p) => (p.pdo_ctx, p.expected_wkc)
    None => (@protocol.PdoContext::build([], 0U), 0U)
  }
  let run_config = match startup_preparation {
    Some(p) => @runtime.master_config_with_optional_dc(p.dc_cycle_period_ns)
    None => @hal.MasterConfig::default()
  }
  let run_report = run_with_progress_output(
    nic,
    Some(scan_report),
    run_config,
    expected,
    pdo_ctx,
    expected_wkc,
    settings,
    startup_state,
    shutdown_state,
    startup_preparation,
    progress_output,
    timeout,
  )
  nic.close()
  if as_json && progress_output != Ndjson {
    println(run_report_json(run_report).stringify(indent=2))
  } else if as_json {
    println(run_report_ndjson(run_report).stringify())
  } else {
    println(run_report.format())
  }
}

///|
fn zc_run_report(
  cycles : Int,
  ok_count : Int,
  timeout_count : Int64,
  wkc_errors : Int64,
) -> Json {
  Json::object({
    "command": Json::string("run-zc"),
    "mode": Json::string("zero-copy"),
    "cycles_requested": Json::number(cycles.to_double()),
    "cycles_ok": Json::number(ok_count.to_double()),
    "timeouts": Json::number(timeout_count.to_double()),
    "wkc_errors": Json::number(wkc_errors.to_double()),
  })
}

///|
fn zc_run_report_text(
  cycles : Int,
  ok_count : Int,
  timeout_count : Int64,
  wkc_errors : Int64,
) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("MoonECAT Zero-Copy Run Report\n")
  buf.write_string("=============================\n")
  buf.write_string("Mode: zero-copy (FramePool + FixedArray)\n")
  buf.write_string("Cycles requested: " + cycles.to_string() + "\n")
  buf.write_string("Cycles OK: " + ok_count.to_string() + "\n")
  buf.write_string("Timeouts: " + timeout_count.to_string() + "\n")
  buf.write_string("WKC errors: " + wkc_errors.to_string() + "\n")
  buf.to_string()
}

///|
fn[N : @hal.Nic] run_with_progress_output(
  nic : N,
  scan_report_override : @runtime.ScanReport?,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  settings : @runtime.RunLoopSettings,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  startup_preparation_override : @runtime.RunStartupPreparation?,
  progress_output : RunProgressOutput,
  timeout : @hal.Duration,
) -> @runtime.RunReport raise @hal.EcError {
  let text_sink = CliTextRunProgressSink::new()
  let ndjson_sink = CliNdjsonRunProgressSink::new()
  match progress_output {
    Silent =>
      match scan_report_override {
        Some(scan_report) =>
          @runtime.run_with_scan_and_states_and_settings_prepared_reporting_to(
            nic,
            scan_report,
            config,
            expected,
            pdo_ctx,
            expected_wkc,
            settings,
            startup_state,
            shutdown_state,
            startup_preparation_override,
            timeout,
            @runtime.NullRunProgressSink::new(),
          )
        None =>
          @runtime.run_with_states_and_settings_prepared_reporting_to(
            nic,
            config,
            expected,
            pdo_ctx,
            expected_wkc,
            settings,
            startup_state,
            shutdown_state,
            startup_preparation_override,
            timeout,
            @runtime.NullRunProgressSink::new(),
          )
      }
    Text =>
      match scan_report_override {
        Some(scan_report) =>
          @runtime.run_with_scan_and_states_and_settings_prepared_reporting_to(
            nic, scan_report, config, expected, pdo_ctx, expected_wkc, settings,
            startup_state, shutdown_state, startup_preparation_override, timeout,
            text_sink,
          )
        None =>
          @runtime.run_with_states_and_settings_prepared_reporting_to(
            nic, config, expected, pdo_ctx, expected_wkc, settings, startup_state,
            shutdown_state, startup_preparation_override, timeout, text_sink,
          )
      }
    Ndjson =>
      match scan_report_override {
        Some(scan_report) =>
          @runtime.run_with_scan_and_states_and_settings_prepared_reporting_to(
            nic, scan_report, config, expected, pdo_ctx, expected_wkc, settings,
            startup_state, shutdown_state, startup_preparation_override, timeout,
            ndjson_sink,
          )
        None =>
          @runtime.run_with_states_and_settings_prepared_reporting_to(
            nic, config, expected, pdo_ctx, expected_wkc, settings, startup_state,
            shutdown_state, startup_preparation_override, timeout, ndjson_sink,
          )
      }
  }
}

///|
fn target_requires_process_data_configuration(
  target : @protocol.EsmState,
) -> Bool {
  target is @protocol.SafeOp || target is @protocol.Op
}

///|
fn load_esi_json_text(path : String) -> String raise @hal.EcError {
  let content_result : Result[String, Error] = try? @fs.read_file_to_string(
    path,
  )
  match content_result {
    Ok(content) => content
    Err(err) =>
      raise @hal.EcError::ConfigMismatch(
        "failed to read ESI JSON file " + path + ": " + err.to_string(),
      )
  }
}

///|
fn optional_device_index_flag(args : Array[String]) -> Int raise @hal.EcError {
  require_int_flag(args, "--device-index", 0)
}

///|
fn optional_esi_json_startup_preparation(
  args : Array[String],
  logical_base : UInt,
) -> @runtime.SlaveStartupPreparation? raise @hal.EcError {
  match flag_value(args, "--esi-json") {
    Some(path) =>
      Some(
        @runtime.startup_preparation_from_esi_json(
          load_esi_json_text(path),
          optional_device_index_flag(args),
          logical_base,
        ),
      )
    None => None
  }
}

///|
fn configured_startup_source(args : Array[String]) -> String {
  match flag_value(args, "--esi-json") {
    Some(_) => "esi-json"
    None => "online-sii"
  }
}

///|
fn pdo_force_requested(args : Array[String]) -> Bool raise @hal.EcError {
  if has_flag(args, "--force-pdo-remap") {
    return true
  }
  match flag_value(args, "--pdo-strategy") {
    None | Some("prefer-live") => false
    Some("force-esi") | Some("force-configured") => true
    Some(value) =>
      raise @hal.EcError::ConfigMismatch(
        "invalid PDO strategy: " +
        value +
        " (expected prefer-live, force-esi, or force-configured)",
      )
  }
}

///|
fn apply_pdo_policy_to_preparation(
  preparation : @runtime.SlaveStartupPreparation,
  args : Array[String],
) -> @runtime.SlaveStartupPreparation raise @hal.EcError {
  { ..preparation, prefer_live_pdo_state: !pdo_force_requested(args) }
}

///|
fn[N : @hal.Nic] resolve_run_startup_preparation_override(
  nic : N,
  scan_report : @runtime.ScanReport,
  args : Array[String],
  timeout : @hal.Duration,
) -> @runtime.RunStartupPreparation? raise @hal.EcError {
  let has_esi_json = flag_value(args, "--esi-json") is Some(_)
  let force_pdo_remap = pdo_force_requested(args)
  if !has_esi_json && !force_pdo_remap {
    return None
  }
  let slave_preparations : Array[(UInt, @runtime.SlaveStartupPreparation)] = []
  let mut current_logical_base = pdo_logical_base
  if has_esi_json {
    if scan_report.slaves.length() != 1 {
      raise @hal.EcError::ConfigMismatch(
        "run --esi-json currently requires exactly one discovered slave",
      )
    }
    let station = scan_report.slaves[0].station_address
    let preparation = prepare_station_startup_from_args(
      nic, args, station, current_logical_base, timeout,
    )
    slave_preparations.push((station, preparation))
  } else {
    for slave in scan_report.slaves {
      let preparation = apply_pdo_policy_to_preparation(
        @runtime.prepare_slave_startup(
          nic,
          slave.station_address,
          current_logical_base,
          process_data_eeprom_word_count,
          timeout,
        ),
        args,
      )
      slave_preparations.push((slave.station_address, preparation))
      current_logical_base = current_logical_base +
        preparation.mapping.output_bytes.reinterpret_as_uint() +
        preparation.mapping.input_bytes.reinterpret_as_uint()
    }
  }
  Some(
    @runtime.run_startup_preparation_from_slave_preparations(
      slave_preparations, pdo_logical_base,
    ),
  )
}

///|
fn[N : @hal.Nic] prepare_station_startup(
  nic : N,
  station : UInt,
  logical_base : UInt,
  timeout : @hal.Duration,
) -> @runtime.SlaveStartupPreparation raise @hal.EcError {
  @runtime.prepare_slave_startup(
    nic, station, logical_base, process_data_eeprom_word_count, timeout,
  )
}

///|
fn[N : @hal.Nic] prepare_station_startup_from_args(
  nic : N,
  args : Array[String],
  station : UInt,
  logical_base : UInt,
  timeout : @hal.Duration,
) -> @runtime.SlaveStartupPreparation raise @hal.EcError {
  apply_pdo_policy_to_preparation(
    match optional_esi_json_startup_preparation(args, logical_base) {
      Some(preparation) => preparation
      None => prepare_station_startup(nic, station, logical_base, timeout)
    },
    args,
  )
}
