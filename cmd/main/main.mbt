///|
enum CliBackend {
  Mock
  NativeAuto
  NativeWindowsNpcap
  NativeLinuxRaw
} derive(Eq, Show)

///|
enum RunProgressOutput {
  Silent
  Text
  Ndjson
} derive(Eq, Show)

///|
let pdo_logical_base : UInt = 0x1000U

///|
let process_data_eeprom_word_count : Int = 128

///|
/// MoonECAT CLI entry point.
/// Commands: list-if, scan, validate, run, read-sii, esi-sii, state, diagnosis, od, esc-regs, expected-regs.
fn main {
  let _ = cli_main() catch {
    err => {
      println("moonecat error: " + err.to_string())
      ()
    }
  }
}

///|
fn cli_main() -> Unit raise @hal.EcError {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  let command = args[1]
  let as_json = has_flag(args, "--json")
  let timeout = resolve_timeout(args)
  let backend = parse_backend(args)

  if command == "list-if" {
    print_interfaces(backend, as_json)
    return
  }

  if command == "esi-sii" {
    run_esi_sii_command(args, as_json)
    return
  }

  if command == "read-sii" {
    match backend {
      Mock =>
        raise @hal.EcError::NotSupported("read-sii requires a native backend")
      _ => {
        let nic = @native.NativeNic::open_with_config(
          resolve_native_cli_config(args, backend, timeout),
        )
        run_read_sii_command(nic, args, as_json, timeout)
      }
    }
    return
  }

  if command == "diagnosis" {
    match backend {
      Mock =>
        raise @hal.EcError::NotSupported("diagnosis requires a native backend")
      _ => {
        let nic = @native.NativeNic::open_with_config(
          resolve_native_cli_config(args, backend, timeout),
        )
        run_diagnosis_command(nic, args, as_json, timeout)
      }
    }
    return
  }

  if command == "od" {
    match backend {
      Mock => raise @hal.EcError::NotSupported("od requires a native backend")
      _ => {
        let nic = @native.NativeNic::open_with_config(
          resolve_native_cli_config(args, backend, timeout),
        )
        run_od_command(nic, args, as_json, timeout)
      }
    }
    return
  }

  if command == "esc-regs" {
    match backend {
      Mock =>
        raise @hal.EcError::NotSupported("esc-regs requires a native backend")
      _ => {
        let nic = @native.NativeNic::open_with_config(
          resolve_native_cli_config(args, backend, timeout),
        )
        run_esc_register_command(nic, args, as_json, timeout)
      }
    }
    return
  }

  if command == "expected-regs" {
    match backend {
      Mock =>
        raise @hal.EcError::NotSupported(
          "expected-regs requires a native backend",
        )
      _ => {
        let nic = @native.NativeNic::open_with_config(
          resolve_native_cli_config(args, backend, timeout),
        )
        run_expected_register_command(nic, args, as_json, timeout)
      }
    }
    return
  }

  if command == "state" {
    match backend {
      Mock =>
        raise @hal.EcError::NotSupported("state requires a native backend")
      _ => {
        let nic = @native.NativeNic::open_with_config(
          resolve_native_cli_config(args, backend, timeout),
        )
        run_state_command(nic, args, as_json, timeout)
      }
    }
    return
  }

  if command == "run" {
    let until_fault = has_flag(args, "--until-fault")
    let progress_ndjson = has_flag(args, "--progress-ndjson")
    let settings = resolve_run_loop_settings(
      args, as_json, until_fault, progress_ndjson,
    )
    let progress_output = resolve_run_progress_output(
      as_json,
      progress_ndjson,
      settings.output_period_ns,
    )
    let startup_state = optional_esm_state_flag(
      args,
      "--startup-state",
      @protocol.Op,
    )
    let shutdown_state = optional_shutdown_state_flag(args, "--shutdown-state")
    match backend {
      Mock =>
        run_mock_command_with_fresh_nic(
          as_json, startup_state, shutdown_state, settings, progress_output, timeout,
        )
      _ =>
        run_native_command_with_fresh_nic(
          resolve_native_cli_config(args, backend, timeout),
          as_json,
          startup_state,
          shutdown_state,
          settings,
          progress_output,
          timeout,
        )
    }
    return
  }

  match backend {
    Mock =>
      run_command_with_nic(
        command,
        @mock.MockNic::new(),
        args,
        as_json,
        timeout,
      )
    _ => {
      let nic = @native.NativeNic::open_with_config(
        resolve_native_cli_config(args, backend, timeout),
      )
      run_command_with_nic(command, nic, args, as_json, timeout)
    }
  }
}

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
    @hal.MasterConfig::default(),
    expected,
    pdo_ctx,
    0U,
    settings,
    startup_state,
    shutdown_state,
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
  let preparation = if target_requires_process_data_configuration(startup_state) {
    @runtime.build_run_startup_preparation(
      run_nic, scan_report, pdo_logical_base, process_data_eeprom_word_count, timeout,
    )
  } else {
    {
      pdo_ctx: @protocol.PdoContext::build([], 0U),
      expected_wkc: 0U,
      dc_cycle_period_ns: None,
      startup_mailbox_plans: [],
    }
  }
  let run_config = @runtime.master_config_with_optional_dc(
    preparation.dc_cycle_period_ns,
  )
  let run_report = run_with_progress_output(
    run_nic,
    run_config,
    expected,
    preparation.pdo_ctx,
    preparation.expected_wkc,
    settings,
    startup_state,
    shutdown_state,
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
fn[N : @hal.Nic] run_with_progress_output(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  settings : @runtime.RunLoopSettings,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  progress_output : RunProgressOutput,
  timeout : @hal.Duration,
) -> @runtime.RunReport raise @hal.EcError {
  let text_sink = CliTextRunProgressSink::new()
  let ndjson_sink = CliNdjsonRunProgressSink::new()
  match progress_output {
    Silent =>
      @runtime.run_with_states_and_settings(
        nic, config, expected, pdo_ctx, expected_wkc, settings, startup_state, shutdown_state,
        timeout,
      )
    Text =>
      @runtime.run_with_states_and_settings_reporting_to(
        nic, config, expected, pdo_ctx, expected_wkc, settings, startup_state, shutdown_state,
        timeout, text_sink,
      )
    Ndjson =>
      @runtime.run_with_states_and_settings_reporting_to(
        nic, config, expected, pdo_ctx, expected_wkc, settings, startup_state, shutdown_state,
        timeout, ndjson_sink,
      )
  }
}

///|
fn target_requires_process_data_configuration(
  target : @protocol.EsmState,
) -> Bool {
  target is @protocol.SafeOp || target is @protocol.Op
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
fn[N : @hal.Nic] run_command_with_nic(
  command : String,
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  match command {
    "scan" => {
      let report = @runtime.scan(nic, timeout)
      nic.close()
      if as_json {
        println(scan_report_json(report).stringify(indent=2))
      } else {
        println(report.format())
      }
    }
    "validate" => {
      let report = @runtime.scan(nic, timeout)
      nic.close()
      let actual = @runtime.configuration_from_scan(report)
      let expected = resolve_validate_expected_configuration(report, args)
      let validate_report = @runtime.validate_configuration(actual, expected)
      if as_json {
        println(
          validate_output_json(report, validate_report).stringify(indent=2),
        )
      } else {
        println(validate_report.format())
      }
    }
    _ => print_usage()
  }
}

///|
fn print_usage() -> Unit {
  println("moonecat v" + @lib.version)
  println(
    "Usage: moonecat <list-if|scan|validate|run|read-sii|esi-sii|state|diagnosis|od|esc-regs|expected-regs> [--json] [--progress-ndjson] [--backend <mock|native|native-windows-npcap|native-linux-raw>] [--if <interface>] [--timeout-ms <n>] [--cycles <n>] [--until-fault] [--cycle-period-us <n>] [--output-period-ms <n>] [--max-consecutive-timeouts <n>] [--position <n>] [--words <n>] [--state <init|preop|safeop|op|boot>] [--startup-state <init|preop|safeop|op|boot>] [--shutdown-state <init|preop|safeop|op|boot|none>] [--station <configured-address>] [--index <n>] [--subindex <n>] [--read-value] [--list-type <n>] [--eni-json <path>] [--esi-json <path>] [--device-index <n>] [--path]",
  )
  println("Default backend: mock")
  println("Default timeout: 1 ms")
  println(
    "Native commands auto-probe connected non-wireless interfaces with BRD when --if is omitted",
  )
  println("Examples:")
  println("  moon run cmd/main list-if -- --backend native --json")
  println("  moon run cmd/main scan -- --backend native --if <interface>")
  println("  moon run cmd/eni_json -- --input config.xml --output config.json")
  println(
    "  moon run cmd/eni_json -- --input References/sample.xml --kind esi --output sample.esi.json",
  )
  println(
    "  moon run cmd/main validate -- --backend native --if <interface> --eni-json config.json --json",
  )
  println(
    "  moon run cmd/main run -- --backend native --if <interface> --until-fault --cycle-period-us 1000 --output-period-ms 1000",
  )
  println(
    "  moon run cmd/main run -- --json --progress-ndjson --backend native --if <interface> --until-fault --output-period-ms 1000",
  )
  println(
    "  moon run cmd/main read-sii -- --backend native --if <interface> --position 0 --json",
  )
  println(
    "  moon run cmd/main esi-sii -- --esi-json sample.esi.json --device-index 0 --json",
  )
  println(
    "  moon run cmd/main state -- --backend native --if <interface> --state safeop --station 4097 --path",
  )
  println(
    "  moon run cmd/main run -- --backend native --if <interface> --startup-state safeop --shutdown-state init --cycles 1000",
  )
  println(
    "  moon run cmd/main run -- --backend native --if <interface> --until-fault --startup-state op",
  )
  println(
    "  moon run cmd/main diagnosis -- --backend native --if <interface> --station 4097 --timeout-ms 50 --json",
  )
  println(
    "  moon run cmd/main od -- --backend native --if <interface> --station 4097 --json",
  )
  println(
    "  moon run cmd/main od -- --backend native --if <interface> --station 4097 --index 7187",
  )
  println(
    "  moon run cmd/main od -- --backend native --if <interface> --station 4097 --index 6656 --subindex 1 --json",
  )
  println(
    "  moon run cmd/main esc-regs -- --backend native --if <interface> --station 4097 --json",
  )
  println(
    "  moon run cmd/main expected-regs -- --backend native --if <interface> --station 4097 --json",
  )
}

///|
fn[N : @hal.Nic] run_state_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let target = require_esm_state_flag(args, "--state")
  let station = optional_uint_flag(args, "--station")
  let use_path = has_flag(args, "--path")
  let report_result : Result[StateTransitionReport, @hal.EcError] = try? compute_state_transition_report(
    nic, target, station, use_path, timeout,
  )
  nic.close()
  let report = match report_result {
    Ok(value) => value
    Err(err) => raise err
  }
  if as_json {
    println(state_transition_report_json(report).stringify(indent=2))
  } else {
    println(state_transition_report_text(report))
  }
}

///|
fn[N : @hal.Nic] run_esc_register_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let station = require_station_flag(args)
  let report = read_esc_register_report(nic, station, timeout)
  nic.close()
  if as_json {
    println(esc_register_report_json(report).stringify(indent=2))
  } else {
    println(esc_register_report_text(report))
  }
}

///|
fn[N : @hal.Nic] run_expected_register_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let station = require_station_flag(args)
  let report = build_expected_esc_register_report(nic, station, timeout)
  nic.close()
  if as_json {
    println(expected_esc_register_report_json(report).stringify(indent=2))
  } else {
    println(expected_esc_register_report_text(report))
  }
}

///|
fn[N : @hal.Nic] compute_state_transition_report(
  nic : N,
  target : @protocol.EsmState,
  station : UInt?,
  use_path : Bool,
  timeout : @hal.Duration,
) -> StateTransitionReport raise @hal.EcError {
  match station {
    Some(configured_station) =>
      compute_station_transition_report(
        nic, target, configured_station, use_path, timeout,
      )
    None => {
      let wkc = @protocol.broadcast_state(nic, target, timeout)
      {
        mode: "broadcast",
        target,
        station: None,
        current: None,
        final_state: None,
        al_error_flag: None,
        status_code: None,
        wkc: Some(wkc),
      }
    }
  }
}

///|
fn[N : @hal.Nic] compute_station_transition_report(
  nic : N,
  target : @protocol.EsmState,
  station : UInt,
  use_path : Bool,
  timeout : @hal.Duration,
) -> StateTransitionReport raise @hal.EcError {
  let current = @protocol.read_al_status_snapshot(nic, station, timeout).state
  if use_path && target == @protocol.Op && current != @protocol.Op {
    let (final_snapshot, kick_wkc) = transition_station_to_op(
      nic, station, current, timeout,
    )
    return {
      mode: "station-path",
      target,
      station: Some(station),
      current: Some(current),
      final_state: Some(final_snapshot.state),
      al_error_flag: Some(final_snapshot.error_indication),
      status_code: final_snapshot.status_code,
      wkc: kick_wkc,
    }
  }
  if use_path &&
    target == @protocol.SafeOp &&
    current != @protocol.SafeOp &&
    current != @protocol.Op {
    let preparation = prepare_station_startup(
      nic, station, pdo_logical_base, timeout,
    )
    let final_state = transition_station_to_safeop_with_process_mapping(
      nic, station, current, preparation, timeout,
    )
    let final_snapshot = try? @protocol.read_al_status_snapshot(
      nic, station, timeout,
    )
    return {
      mode: "station-path",
      target,
      station: Some(station),
      current: Some(current),
      final_state: match final_snapshot {
        Ok(snapshot) => Some(snapshot.state)
        Err(_) => Some(final_state)
      },
      al_error_flag: match final_snapshot {
        Ok(snapshot) => Some(snapshot.error_indication)
        Err(_) => None
      },
      status_code: match final_snapshot {
        Ok(snapshot) => snapshot.status_code
        Err(_) => None
      },
      wkc: None,
    }
  }
  let final_state = if use_path {
    transition_station_to_target_strict_after_recovery(
      nic, station, target, timeout,
    )
  } else {
    @protocol.request_state(nic, station, target, timeout)
  }
  let final_snapshot = try? @protocol.read_al_status_snapshot(
    nic, station, timeout,
  )
  {
    mode: if use_path {
      "station-path"
    } else {
      "station-direct"
    },
    target,
    station: Some(station),
    current: Some(current),
    final_state: match final_snapshot {
      Ok(snapshot) => Some(snapshot.state)
      Err(_) => Some(final_state)
    },
    al_error_flag: match final_snapshot {
      Ok(snapshot) => Some(snapshot.error_indication)
      Err(_) => None
    },
    status_code: match final_snapshot {
      Ok(snapshot) => snapshot.status_code
      Err(_) => None
    },
    wkc: None,
  }
}

///|
fn[N : @hal.Nic] transition_station_to_target_strict_after_recovery(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  timeout : @hal.Duration,
) -> @protocol.EsmState raise @hal.EcError {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  if snapshot.error_indication {
    ignore(@protocol.recover_al_error_for_transition(nic, station, timeout))
  }
  @protocol.transition_to_target_strict(nic, station, target, timeout)
}

///|
fn[N : @hal.Nic] transition_station_to_op_after_recovery(
  nic : N,
  station : UInt,
  pdo_ctx : @protocol.PdoContext,
  timeout : @hal.Duration,
) -> @protocol.EsmStatusSnapshot raise @hal.EcError {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  if snapshot.error_indication {
    ignore(@protocol.recover_al_error_for_transition(nic, station, timeout))
  }
  @protocol.request_state_with_process_data_snapshot(
    nic,
    station,
    @protocol.Op,
    pdo_ctx,
    timeout,
  )
}

///|
fn[N : @hal.Nic] transition_station_to_preop_with_mailbox(
  nic : N,
  station : UInt,
  current : @protocol.EsmState,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> @protocol.EsmState raise @hal.EcError {
  if current == @protocol.PreOp ||
    current == @protocol.SafeOp ||
    current == @protocol.Op {
    return current
  }
  ignore(
    @runtime.write_mailbox_mapping(nic, station, preparation.mapping, timeout),
  )
  transition_station_to_target_strict_after_recovery(
    nic,
    station,
    @protocol.PreOp,
    timeout,
  )
}

///|
fn[N : @hal.Nic] transition_station_to_safeop_with_process_mapping(
  nic : N,
  station : UInt,
  current : @protocol.EsmState,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> @protocol.EsmState raise @hal.EcError {
  if current == @protocol.SafeOp || current == @protocol.Op {
    return current
  }
  let preop_state = transition_station_to_preop_with_mailbox(
    nic, station, current, preparation, timeout,
  )
  if preop_state == @protocol.SafeOp || preop_state == @protocol.Op {
    return preop_state
  }
  let refined_preparation = @runtime.refine_startup_preparation_in_preop(
    nic, station, pdo_logical_base, preparation, timeout,
  )
  ignore(
    @runtime.write_process_data_mapping(
      nic,
      station,
      refined_preparation.mapping,
      timeout,
    ),
  )
  transition_station_to_target_strict_after_recovery(
    nic,
    station,
    @protocol.SafeOp,
    timeout,
  )
}

///|
fn[N : @hal.Nic] transition_station_to_op(
  nic : N,
  station : UInt,
  current : @protocol.EsmState,
  timeout : @hal.Duration,
) -> (@protocol.EsmStatusSnapshot, UInt?) raise @hal.EcError {
  let initial_preparation = prepare_station_startup(
    nic, station, pdo_logical_base, timeout,
  )
  let state_before_process_mapping = transition_station_to_preop_with_mailbox(
    nic, station, current, initial_preparation, timeout,
  )
  let preparation = if state_before_process_mapping == @protocol.PreOp {
    @runtime.refine_startup_preparation_in_preop(
      nic, station, pdo_logical_base, initial_preparation, timeout,
    )
  } else {
    initial_preparation
  }
  let pdo_ctx = @protocol.PdoContext::build(
    [(preparation.mapping, station)],
    pdo_logical_base,
  )
  match preparation.startup_outputs {
    Some(outputs) => pdo_ctx.set_slave_outputs(station, outputs)
    None => ()
  }
  let has_process_data = preparation.mapping.output_bytes > 0 ||
    preparation.mapping.input_bytes > 0
  let state_before_op = transition_station_to_safeop_with_process_mapping(
    nic, station, state_before_process_mapping, preparation, timeout,
  )
  @runtime.apply_startup_mailbox_commands(
    nic,
    station,
    preparation.mailbox_config,
    preparation.startup_mailbox_commands,
    @runtime.SafeOpToOp,
    timeout,
  )
  match preparation.dc_cycle_period_ns {
    Some(cycle_period_ns) =>
      ignore(
        @protocol.dc_configure_linear(
          nic,
          [station],
          cycle_period_ns.to_int().reinterpret_as_uint(),
          timeout,
          static_sync_iterations=32,
        ),
      )
    None => ()
  }
  let kick_before_op = if has_process_data {
    Some(@protocol.pdo_exchange(nic, pdo_ctx, timeout))
  } else {
    None
  }
  let final_snapshot : @protocol.EsmStatusSnapshot = if state_before_op ==
    @protocol.Op {
    { state: state_before_op, error_indication: false, status_code: None }
  } else if has_process_data {
    transition_station_to_op_after_recovery(nic, station, pdo_ctx, timeout)
  } else {
    let final_state = transition_station_to_target_strict_after_recovery(
      nic,
      station,
      @protocol.Op,
      timeout,
    )
    @protocol.read_al_status_snapshot(nic, station, timeout) catch {
      _ => { state: final_state, error_indication: false, status_code: None }
    }
  }
  let final_wkc = if final_snapshot.state == @protocol.Op && has_process_data {
    Some(@protocol.pdo_exchange(nic, pdo_ctx, timeout))
  } else {
    kick_before_op
  }
  (final_snapshot, final_wkc)
}

///|
fn[N : @hal.Nic] run_diagnosis_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let scan_report = diagnosis_stage(
    try? @runtime.scan(nic, timeout),
    "diagnosis.scan",
  )
  let target_slave = resolve_cli_slave(
    scan_report,
    optional_uint_flag(args, "--station"),
  )
  let station = target_slave.station_address
  let position = target_slave.position.reinterpret_as_uint()
  let diagnosis_session = diagnosis_stage(
    try? @runtime.prepare_slave_diagnosis_ap(nic, position, station, timeout),
    "diagnosis.prepare",
  )
  let diagnosis_rmsm = @mailbox.Rmsm::new(max_retries=0)
  let report = diagnosis_stage(
    try? @runtime.read_slave_diagnosis_ap(
      nic,
      position,
      station,
      diagnosis_session.mailbox_config,
      diagnosis_rmsm,
      timeout,
    ),
    "diagnosis.read_slave_diagnosis_ap",
  )
  let report = {
    ..report,
    al_state: match diagnosis_session.observed_state {
      Some(state) => Some(state)
      None => report.al_state
    },
    al_error_flag: match diagnosis_session.observed_error_flag {
      Some(flag) => Some(flag)
      None => report.al_error_flag
    },
    al_status_code: match diagnosis_session.observed_status_code {
      Some(code) => Some(code)
      None => report.al_status_code
    },
  }
  if diagnosis_session.original_state != @protocol.PreOp {
    ignore(
      diagnosis_stage(
        try? @runtime.restore_slave_diagnosis_state(
          nic,
          station,
          diagnosis_session.original_state,
          timeout,
        ),
        "diagnosis.restore",
      ) catch {
        _ => @protocol.PreOp
      },
    )
  }
  nic.close()
  if as_json {
    println(diagnosis_output_json(scan_report, report).stringify(indent=2))
  } else {
    println(diagnosis_report_text(report))
  }
}

///|
struct OdBrowseQuery {
  list_type : UInt
  index : UInt?
  subindex : Byte?
  read_value : Bool
}

///|
struct OdBrowseReport {
  station_address : UInt?
  mode : String
  list_type : UInt
  index : UInt?
  subindex : Byte?
  indices : Array[UInt]?
  object_description : @mailbox.SdoInfoObjectDescription?
  entry_description : @mailbox.SdoInfoEntryDescription?
  value_hex : String?
  value_u32 : UInt?
  error_category : String?
  error_detail : String?
  abort_code : UInt?
}

///|
fn resolve_od_query(args : Array[String]) -> OdBrowseQuery raise @hal.EcError {
  let index = optional_uint_flag(args, "--index")
  let read_value = has_flag(args, "--read-value")
  let subindex = match optional_byte_flag(args, "--subindex") {
    Some(value) => Some(value)
    None if read_value && index is Some(_) => Some(b'\x00')
    None => None
  }
  if subindex is Some(_) && index is None {
    raise @hal.EcError::ConfigMismatch("--subindex requires --index")
  }
  if read_value && index is None {
    raise @hal.EcError::ConfigMismatch("--read-value requires --index")
  }
  {
    list_type: require_uint_flag(args, "--list-type", 0U),
    index,
    subindex,
    read_value,
  }
}

///|
fn[N : @hal.Nic] run_od_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let query = resolve_od_query(args)
  let report_result : Result[OdBrowseReport, @hal.EcError] = try? compute_od_report(
    nic, args, query, timeout,
  )
  nic.close()
  let report = match report_result {
    Ok(value) => value
    Err(err) =>
      od_failure_report(optional_uint_flag(args, "--station"), query, err)
  }
  if as_json {
    println(od_report_json(report).stringify(indent=2))
  } else {
    println(od_report_text(report))
  }
}

///|
fn[N : @hal.Nic] compute_od_report(
  nic : N,
  args : Array[String],
  query : OdBrowseQuery,
  timeout : @hal.Duration,
) -> OdBrowseReport raise @hal.EcError {
  let scan_report = od_stage(try? @runtime.scan(nic, timeout), "od.scan")
  let target_slave = resolve_cli_slave(
    scan_report,
    optional_uint_flag(args, "--station"),
  )
  let station = target_slave.station_address
  let position = target_slave.position.reinterpret_as_uint()
  let mailbox_session = od_stage(
    try? @runtime.prepare_slave_mailbox_ap(nic, position, station, timeout),
    "od.prepare",
  )
  let browse_rmsm = @mailbox.Rmsm::new(max_retries=0)
  let report = match (query.index, query.subindex) {
    (None, _) => {
      let indices = od_stage(
        try? @protocol.sdo_info_get_od_list(
          nic,
          station,
          mailbox_session.mailbox_config,
          browse_rmsm,
          query.list_type,
          timeout,
        ),
        "od.get_od_list",
      )
      {
        station_address: Some(station),
        mode: "od-list",
        list_type: query.list_type,
        index: None,
        subindex: None,
        indices: Some(indices),
        object_description: None,
        entry_description: None,
        value_hex: None,
        value_u32: None,
        error_category: None,
        error_detail: None,
        abort_code: None,
      }
    }
    (Some(index), None) => {
      let description = od_stage(
        try? @protocol.sdo_info_get_od_description(
          nic,
          station,
          mailbox_session.mailbox_config,
          browse_rmsm,
          index,
          timeout,
        ),
        "od.get_od_description",
      )
      {
        station_address: Some(station),
        mode: "od-object",
        list_type: query.list_type,
        index: Some(index),
        subindex: None,
        indices: None,
        object_description: Some(description),
        entry_description: None,
        value_hex: None,
        value_u32: None,
        error_category: None,
        error_detail: None,
        abort_code: None,
      }
    }
    (Some(index), Some(subindex)) =>
      if query.read_value {
        let payload = od_stage(
          try? @protocol.sdo_upload_retry(
            nic,
            station,
            mailbox_session.mailbox_config,
            browse_rmsm,
            index,
            subindex,
            timeout,
          ),
          "od.sdo_upload",
        )
        {
          station_address: Some(station),
          mode: "od-value",
          list_type: query.list_type,
          index: Some(index),
          subindex: Some(subindex),
          indices: None,
          object_description: None,
          entry_description: None,
          value_hex: Some(bytes_hex(payload)),
          value_u32: decode_payload_u32_le(payload),
          error_category: None,
          error_detail: None,
          abort_code: None,
        }
      } else {
        let description = od_stage(
          try? @protocol.sdo_info_get_oe_description(
            nic,
            station,
            mailbox_session.mailbox_config,
            browse_rmsm,
            index,
            subindex,
            0xFF,
            timeout,
          ),
          "od.get_oe_description",
        )
        {
          station_address: Some(station),
          mode: "od-entry",
          list_type: query.list_type,
          index: Some(index),
          subindex: Some(subindex),
          indices: None,
          object_description: None,
          entry_description: Some(description),
          value_hex: None,
          value_u32: None,
          error_category: None,
          error_detail: None,
          abort_code: None,
        }
      }
  }
  if mailbox_session.original_state != @protocol.PreOp {
    ignore(
      od_stage(
        try? @runtime.restore_slave_mailbox_state(
          nic,
          station,
          mailbox_session.original_state,
          timeout,
        ),
        "od.restore",
      ) catch {
        _ => @protocol.PreOp
      },
    )
  }
  report
}

///|
fn[N : @hal.Nic] run_read_sii_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let position = require_uint_flag(args, "--position", 0U)
  let initial_word_count = require_int_flag(args, "--words", 128)
  let eeprom = @protocol.read_sii_bytes_ap(
    nic,
    position,
    initial_word_count,
    timeout,
  )
  let word_count = eeprom.length() / 4
  let sii = @mailbox.parse_sii_full_info(eeprom)
  nic.close()
  if as_json {
    println(read_sii_json(position, word_count, sii).stringify(indent=2))
  } else {
    println(read_sii_text(position, word_count, sii))
  }
}

///|
fn print_interfaces(
  backend : CliBackend,
  as_json : Bool,
) -> Unit raise @hal.EcError {
  match backend {
    Mock =>
      if as_json {
        println(
          Json::object({
            "backend": Json::string("mock"),
            "interfaces_text": Json::string(""),
            "note": Json::string("mock backend does not expose real interfaces"),
          }).stringify(indent=2),
        )
      } else {
        println("mock backend does not expose real interfaces")
      }
    NativeAuto | NativeWindowsNpcap | NativeLinuxRaw => {
      let native_backend = cli_backend_to_native_backend(backend)
      let listing = if as_json {
        @native.native_list_interfaces_json(native_backend)
      } else {
        @native.native_list_interfaces_text(native_backend)
      }
      if listing == "" {
        println("no interfaces found")
      } else {
        println(listing)
      }
    }
  }
}

///|
fn cli_backend_to_native_backend(
  backend : CliBackend,
) -> @native.NativeBackendKind {
  match backend {
    Mock => @native.Auto
    NativeAuto => @native.Auto
    NativeWindowsNpcap => @native.WindowsNpcap
    NativeLinuxRaw => @native.LinuxRawSocket
  }
}

///|
fn resolve_validate_expected_configuration(
  scan_report : @runtime.ScanReport,
  args : Array[String],
) -> @runtime.ConfigurationModel raise @hal.EcError {
  match flag_value(args, "--eni-json") {
    Some(path) => {
      let content_result : Result[String, Error] = try? @fs.read_file_to_string(
        path,
      )
      let json_content = match content_result {
        Ok(content) => content
        Err(err) =>
          raise @hal.EcError::ConfigMismatch(
            "failed to read ENI JSON file " + path + ": " + err.to_string(),
          )
      }
      @runtime.configuration_from_eni_json(json_content)
    }
    None =>
      match flag_value(args, "--eni") {
        Some(_) =>
          raise @hal.EcError::ConfigMismatch(
            "XML ENI import has been isolated from moonecat validate; run moon run cmd/eni_json -- --input <eni.xml> --output <eni.json> and then pass --eni-json <eni.json>",
          )
        None =>
          @runtime.configuration_from_expected(expected_from_scan(scan_report))
      }
  }
}

///|
fn has_flag(args : Array[String], flag : String) -> Bool {
  for a in args {
    if a == flag {
      return true
    }
  }
  false
}

///|
fn parse_backend(args : Array[String]) -> CliBackend raise @hal.EcError {
  match flag_value(args, "--backend") {
    Some("mock") | None => Mock
    Some("native") => NativeAuto
    Some("native-windows-npcap") => NativeWindowsNpcap
    Some("native-linux-raw") => NativeLinuxRaw
    Some(other) =>
      raise @hal.EcError::ConfigMismatch("unsupported backend: " + other)
  }
}

///|
fn resolve_cli_slave(
  scan_report : @runtime.ScanReport,
  requested_station : UInt?,
) -> @runtime.SlaveReport raise @hal.EcError {
  match requested_station {
    Some(station) => {
      for slave in scan_report.slaves {
        if slave.station_address == station {
          return slave
        }
      }
      raise @hal.EcError::ConfigMismatch(
        "diagnosis station not found in current scan: " + station.to_string(),
      )
    }
    None =>
      match scan_report.slaves {
        [only] => only
        [] =>
          raise @hal.EcError::ConfigMismatch(
            "diagnosis requires discovered slave or explicit --station",
          )
        _ =>
          raise @hal.EcError::ConfigMismatch(
            "diagnosis requires explicit --station when multiple slaves are present",
          )
      }
  }
}

///|
fn[T] diagnosis_stage(
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
fn[T] od_stage(
  result : Result[T, @hal.EcError],
  stage : String,
) -> T raise @hal.EcError {
  match result {
    Ok(value) => value
    Err(@hal.EcError::SendFailed(message)) =>
      raise @hal.EcError::SendFailed(stage + " -> " + message)
    Err(@hal.EcError::RecvFailed(message)) =>
      raise @hal.EcError::RecvFailed(stage + " -> " + message)
    Err(@hal.EcError::InvalidFrame(message)) =>
      raise @hal.EcError::InvalidFrame(stage + " -> " + message)
    Err(@hal.EcError::InvalidPdu(message)) =>
      raise @hal.EcError::InvalidPdu(stage + " -> " + message)
    Err(@hal.EcError::EsmStateError(message)) =>
      raise @hal.EcError::EsmStateError(stage + " -> " + message)
    Err(@hal.EcError::MailboxProtocol(message)) =>
      raise @hal.EcError::MailboxProtocol(stage + " -> " + message)
    Err(@hal.EcError::SiiReadFailed(message)) =>
      raise @hal.EcError::SiiReadFailed(stage + " -> " + message)
    Err(@hal.EcError::EsiParseFailed(message)) =>
      raise @hal.EcError::EsiParseFailed(stage + " -> " + message)
    Err(@hal.EcError::ConfigMismatch(message)) =>
      raise @hal.EcError::ConfigMismatch(stage + " -> " + message)
    Err(@hal.EcError::NotSupported(message)) =>
      raise @hal.EcError::NotSupported(stage + " -> " + message)
    Err(@hal.EcError::Internal(message)) =>
      raise @hal.EcError::Internal(stage + " -> " + message)
    Err(err) => raise err
  }
}

///|
fn require_interface_name(args : Array[String]) -> String raise @hal.EcError {
  match flag_value(args, "--if") {
    Some(name) => name
    None =>
      raise @hal.EcError::ConfigMismatch(
        "native backend requires --if <interface>",
      )
  }
}

///|
fn resolve_native_cli_config(
  args : Array[String],
  backend : CliBackend,
  timeout : @hal.Duration,
) -> @native.NativeNicConfig raise @hal.EcError {
  let requested_backend = cli_backend_to_native_backend(backend)
  match flag_value(args, "--if") {
    Some(_) =>
      native_config_for_backend(requested_backend, require_interface_name(args))
    None => auto_select_native_cli_config(requested_backend, timeout)
  }
}

///|
fn native_config_for_backend(
  backend : @native.NativeBackendKind,
  interface_name : String,
) -> @native.NativeNicConfig {
  match backend {
    @native.Auto => @native.default_native_config(interface_name)
    @native.WindowsNpcap => @native.default_windows_npcap_config(interface_name)
    @native.LinuxRawSocket => @native.default_linux_config(interface_name)
  }
}

///|
fn auto_select_native_cli_config(
  backend : @native.NativeBackendKind,
  timeout : @hal.Duration,
) -> @native.NativeNicConfig raise @hal.EcError {
  let listing = @native.native_list_interfaces(backend)
  select_native_cli_config_from_listing(listing, timeout, fn(config, timeout) {
    probe_native_cli_config(config, timeout)
  })
}

///|
fn select_native_cli_config_from_listing(
  listing : @native.NativeInterfaceListing,
  timeout : @hal.Duration,
  probe : (@native.NativeNicConfig, @hal.Duration) -> Result[Int, Error],
) -> @native.NativeNicConfig raise @hal.EcError {
  let candidates = @native.native_interface_probe_candidates(listing)
  if candidates.is_empty() {
    raise @hal.EcError::ConfigMismatch(
      "automatic native interface selection found no connected non-wireless candidates; pass --if <interface> or inspect list-if --json",
    )
  }
  let notes : Array[String] = []
  for interface in listing.interfaces {
    if not(@native.native_interface_is_probe_candidate(interface)) {
      notes.push(
        interface.name + "(" + skipped_native_interface_reason(interface) + ")",
      )
    }
  }
  for candidate in candidates {
    let config = native_config_for_backend(listing.backend, candidate.name)
    match probe(config, timeout) {
      Ok(slave_count) if slave_count > 0 => return config
      Ok(_) => notes.push(candidate.name + "(no-response)")
      Err(err) =>
        notes.push(candidate.name + "(" + native_probe_error_label(err) + ")")
    }
  }
  raise @hal.EcError::ConfigMismatch(
    "automatic native interface selection found no EtherCAT BRD response: " +
    join_cli_notes(notes),
  )
}

///|
fn probe_native_cli_config(
  config : @native.NativeNicConfig,
  timeout : @hal.Duration,
) -> Result[Int, Error] {
  let open_result : Result[@native.NativeNic, Error] = try? @native.NativeNic::open_with_config(
    config,
  )
  match open_result {
    Ok(nic) => {
      let probe_result : Result[Int, Error] = try? @protocol.count_slaves(
        nic, timeout,
      )
      nic.close()
      probe_result
    }
    Err(err) => Err(err)
  }
}

///|
fn skipped_native_interface_reason(
  interface : @native.NativeInterfaceInfo,
) -> String {
  if interface.loopback {
    return "loopback"
  }
  if interface.wireless {
    return "wireless"
  }
  if not(interface.up) {
    return "down"
  }
  if not(interface.connected) {
    return "disconnected"
  }
  "filtered"
}

///|
fn native_probe_error_label(err : Error) -> String {
  match err {
    @hal.EcError::LinkDown => "link-down"
    @hal.EcError::RecvTimeout => "recv-timeout"
    @hal.EcError::ConfigMismatch(message) => "config:" + message
    @hal.EcError::NotSupported(message) => "unsupported:" + message
    @hal.EcError::SendFailed(message) => "send:" + message
    @hal.EcError::RecvFailed(message) => "recv:" + message
    @hal.EcError::Internal(message) => "internal:" + message
    other => other.to_string()
  }
}

///|
fn join_cli_notes(values : Array[String]) -> String {
  let mut text = ""
  for i = 0; i < values.length(); i = i + 1 {
    if i > 0 {
      text = text + ", "
    }
    text = text + values[i]
  }
  text
}

///|
fn require_esm_state_flag(
  args : Array[String],
  flag : String,
) -> @protocol.EsmState raise @hal.EcError {
  match flag_value(args, flag) {
    Some(text) => parse_esm_state_flag(flag, text)
    None =>
      raise @hal.EcError::ConfigMismatch("missing state value for " + flag)
  }
}

///|
fn optional_esm_state_flag(
  args : Array[String],
  flag : String,
  default : @protocol.EsmState,
) -> @protocol.EsmState raise @hal.EcError {
  match flag_value(args, flag) {
    Some(text) => parse_esm_state_flag(flag, text)
    None => default
  }
}

///|
fn optional_shutdown_state_flag(
  args : Array[String],
  flag : String,
) -> @protocol.EsmState? raise @hal.EcError {
  match flag_value(args, flag) {
    Some("none") => None
    Some(text) => Some(parse_esm_state_flag(flag, text))
    None => Some(@protocol.Init)
  }
}

///|
fn optional_uint_flag(
  args : Array[String],
  flag : String,
) -> UInt? raise @hal.EcError {
  match flag_value(args, flag) {
    Some(text) => Some(parse_uint_flag(flag, text))
    None => None
  }
}

///|
fn require_station_flag(args : Array[String]) -> UInt raise @hal.EcError {
  match optional_uint_flag(args, "--station") {
    Some(station) => station
    None =>
      raise @hal.EcError::ConfigMismatch("esc-regs requires explicit --station")
  }
}

///|
fn optional_byte_flag(
  args : Array[String],
  flag : String,
) -> Byte? raise @hal.EcError {
  match flag_value(args, flag) {
    Some(text) => Some(parse_byte_flag(flag, text))
    None => None
  }
}

///|
fn parse_esm_state_flag(
  flag : String,
  text : String,
) -> @protocol.EsmState raise @hal.EcError {
  match text {
    "init" => @protocol.Init
    "preop" | "pre-op" => @protocol.PreOp
    "safeop" | "safe-op" => @protocol.SafeOp
    "op" => @protocol.Op
    "boot" => @protocol.Boot
    _ =>
      raise @hal.EcError::ConfigMismatch(
        "invalid ESM state for " + flag + ": " + text,
      )
  }
}

///|
struct StateTransitionReport {
  mode : String
  target : @protocol.EsmState
  station : UInt?
  current : @protocol.EsmState?
  final_state : @protocol.EsmState?
  al_error_flag : Bool?
  status_code : UInt?
  wkc : UInt?
}

///|
struct EscSyncManagerRegisterReport {
  index : Int
  register_offset : UInt
  raw_hex : String
  physical_start : UInt
  length : UInt
  control : Byte
  status : Byte
  activate : Byte
}

///|
struct EscFmmuRegisterReport {
  index : Int
  register_offset : UInt
  raw_hex : String
  logical_start : UInt
  length : UInt
  logical_start_bit : Byte
  logical_end_bit : Byte
  physical_start : UInt
  physical_start_bit : Byte
  type_register : Byte
  activate : Byte
}

///|
struct EscRegisterReport {
  station : UInt
  al_state : @protocol.EsmState
  al_error_flag : Bool
  al_status_code : UInt?
  sync_managers : Array[EscSyncManagerRegisterReport]
  fmmus : Array[EscFmmuRegisterReport]
}

///|
struct ExpectedEscRegisterReport {
  station : UInt
  sync_managers : Array[EscSyncManagerRegisterReport]
  fmmus : Array[EscFmmuRegisterReport]
}

///|
fn[N : @hal.Nic] read_esc_register_report(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> EscRegisterReport raise @hal.EcError {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  let sync_managers : Array[EscSyncManagerRegisterReport] = []
  for index = 2; index <= 3; index = index + 1 {
    let register_offset = @protocol.reg_sm_base +
      index.reinterpret_as_uint() *
      @protocol.sm_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.sm_entry_size, timeout,
      ).data
    sync_managers.push(
      decode_esc_sync_manager_window(index, register_offset, window),
    )
  }
  let fmmus : Array[EscFmmuRegisterReport] = []
  for index = 0; index <= 1; index = index + 1 {
    let register_offset = @protocol.reg_fmmu_base +
      index.reinterpret_as_uint() *
      @protocol.fmmu_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.fmmu_entry_size, timeout,
      ).data
    fmmus.push(decode_esc_fmmu_window(index, register_offset, window))
  }
  {
    station,
    al_state: snapshot.state,
    al_error_flag: snapshot.error_indication,
    al_status_code: snapshot.status_code,
    sync_managers,
    fmmus,
  }
}

///|
fn[N : @hal.Nic] build_expected_esc_register_report(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> ExpectedEscRegisterReport raise @hal.EcError {
  let initial = prepare_station_startup(nic, station, pdo_logical_base, timeout)
  let refined = @runtime.refine_startup_preparation_in_preop(
    nic, station, pdo_logical_base, initial, timeout,
  )
  {
    station,
    sync_managers: expected_sync_manager_register_reports(refined.mapping),
    fmmus: expected_fmmu_register_reports(refined.mapping),
  }
}

///|
fn expected_sync_manager_register_reports(
  mapping : @mailbox.SlaveMapping,
) -> Array[EscSyncManagerRegisterReport] raise @hal.EcError {
  let reports : Array[EscSyncManagerRegisterReport] = []
  for index = 2; index <= 3; index = index + 1 {
    reports.push(expected_sync_manager_register_report(mapping, index))
  }
  reports
}

///|
fn expected_sync_manager_register_report(
  mapping : @mailbox.SlaveMapping,
  index : Int,
) -> EscSyncManagerRegisterReport raise @hal.EcError {
  let register_offset = @protocol.reg_sm_base +
    index.reinterpret_as_uint() * @protocol.sm_entry_size.reinterpret_as_uint()
  let window = if index >= 0 && index < mapping.sm_configs.length() {
    mapping.sm_configs[index].to_bytes()
  } else {
    Bytes::new(@protocol.sm_entry_size)
  }
  decode_esc_sync_manager_window(index, register_offset, window)
}

///|
fn expected_fmmu_register_reports(
  mapping : @mailbox.SlaveMapping,
) -> Array[EscFmmuRegisterReport] raise @hal.EcError {
  let reports : Array[EscFmmuRegisterReport] = []
  for index = 0; index <= 1; index = index + 1 {
    reports.push(expected_fmmu_register_report(mapping, index))
  }
  reports
}

///|
fn expected_fmmu_register_report(
  mapping : @mailbox.SlaveMapping,
  index : Int,
) -> EscFmmuRegisterReport raise @hal.EcError {
  let register_offset = @protocol.reg_fmmu_base +
    index.reinterpret_as_uint() *
    @protocol.fmmu_entry_size.reinterpret_as_uint()
  let window = if index >= 0 && index < mapping.fmmu_configs.length() {
    mapping.fmmu_configs[index].to_bytes()
  } else {
    Bytes::new(@protocol.fmmu_entry_size)
  }
  decode_esc_fmmu_window(index, register_offset, window)
}

///|
fn decode_esc_sync_manager_window(
  index : Int,
  register_offset : UInt,
  window : Bytes,
) -> EscSyncManagerRegisterReport raise @hal.EcError {
  if window.length() < @protocol.sm_entry_size {
    raise @hal.EcError::Internal(
      "short SyncManager register window at 0x" +
      format_hex(register_offset, 4) +
      ": expected " +
      @protocol.sm_entry_size.to_string() +
      " bytes, got " +
      window.length().to_string(),
    )
  }
  {
    index,
    register_offset,
    raw_hex: bytes_hex(window),
    physical_start: decode_u16_le(window, 0),
    length: decode_u16_le(window, 2),
    control: window[4],
    status: window[5],
    activate: window[6],
  }
}

///|
fn decode_esc_fmmu_window(
  index : Int,
  register_offset : UInt,
  window : Bytes,
) -> EscFmmuRegisterReport raise @hal.EcError {
  if window.length() < @protocol.fmmu_entry_size {
    raise @hal.EcError::Internal(
      "short FMMU register window at 0x" +
      format_hex(register_offset, 4) +
      ": expected " +
      @protocol.fmmu_entry_size.to_string() +
      " bytes, got " +
      window.length().to_string(),
    )
  }
  {
    index,
    register_offset,
    raw_hex: bytes_hex(window),
    logical_start: decode_u32_le(window, 0),
    length: decode_u16_le(window, 4),
    logical_start_bit: window[6],
    logical_end_bit: window[7],
    physical_start: decode_u16_le(window, 8),
    physical_start_bit: window[10],
    type_register: window[11],
    activate: window[12],
  }
}

///|
fn esc_register_report_json(report : EscRegisterReport) -> Json {
  Json::object({
    "station": Json::number(report.station.to_double()),
    "al_state": Json::string(report.al_state.to_string()),
    "al_error_flag": Json::boolean(report.al_error_flag),
    "al_status_code": option_uint_json(report.al_status_code),
    "sync_managers": Json::array(
      report.sync_managers.map(fn(sm) {
        Json::object({
          "index": Json::number(sm.index.to_double()),
          "register_offset": Json::number(sm.register_offset.to_double()),
          "raw_hex": Json::string(sm.raw_hex),
          "physical_start": Json::number(sm.physical_start.to_double()),
          "length": Json::number(sm.length.to_double()),
          "control": Json::number(sm.control.to_uint().to_double()),
          "status": Json::number(sm.status.to_uint().to_double()),
          "activate": Json::number(sm.activate.to_uint().to_double()),
          "enabled": Json::boolean((sm.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
    "fmmus": Json::array(
      report.fmmus.map(fn(fmmu) {
        Json::object({
          "index": Json::number(fmmu.index.to_double()),
          "register_offset": Json::number(fmmu.register_offset.to_double()),
          "raw_hex": Json::string(fmmu.raw_hex),
          "logical_start": Json::number(fmmu.logical_start.to_double()),
          "length": Json::number(fmmu.length.to_double()),
          "logical_start_bit": Json::number(
            fmmu.logical_start_bit.to_uint().to_double(),
          ),
          "logical_end_bit": Json::number(
            fmmu.logical_end_bit.to_uint().to_double(),
          ),
          "physical_start": Json::number(fmmu.physical_start.to_double()),
          "physical_start_bit": Json::number(
            fmmu.physical_start_bit.to_uint().to_double(),
          ),
          "type_register": Json::number(
            fmmu.type_register.to_uint().to_double(),
          ),
          "type_description": Json::string(
            esc_fmmu_type_description(fmmu.type_register),
          ),
          "activate": Json::number(fmmu.activate.to_uint().to_double()),
          "enabled": Json::boolean((fmmu.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
  })
}

///|
fn expected_esc_register_report_json(
  report : ExpectedEscRegisterReport,
) -> Json {
  Json::object({
    "station": Json::number(report.station.to_double()),
    "sync_managers": Json::array(
      report.sync_managers.map(fn(sm) {
        Json::object({
          "index": Json::number(sm.index.to_double()),
          "register_offset": Json::number(sm.register_offset.to_double()),
          "raw_hex": Json::string(sm.raw_hex),
          "physical_start": Json::number(sm.physical_start.to_double()),
          "length": Json::number(sm.length.to_double()),
          "control": Json::number(sm.control.to_uint().to_double()),
          "status": Json::number(sm.status.to_uint().to_double()),
          "activate": Json::number(sm.activate.to_uint().to_double()),
          "enabled": Json::boolean((sm.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
    "fmmus": Json::array(
      report.fmmus.map(fn(fmmu) {
        Json::object({
          "index": Json::number(fmmu.index.to_double()),
          "register_offset": Json::number(fmmu.register_offset.to_double()),
          "raw_hex": Json::string(fmmu.raw_hex),
          "logical_start": Json::number(fmmu.logical_start.to_double()),
          "length": Json::number(fmmu.length.to_double()),
          "logical_start_bit": Json::number(
            fmmu.logical_start_bit.to_uint().to_double(),
          ),
          "logical_end_bit": Json::number(
            fmmu.logical_end_bit.to_uint().to_double(),
          ),
          "physical_start": Json::number(fmmu.physical_start.to_double()),
          "physical_start_bit": Json::number(
            fmmu.physical_start_bit.to_uint().to_double(),
          ),
          "type_register": Json::number(
            fmmu.type_register.to_uint().to_double(),
          ),
          "type_description": Json::string(
            esc_fmmu_type_description(fmmu.type_register),
          ),
          "activate": Json::number(fmmu.activate.to_uint().to_double()),
          "enabled": Json::boolean((fmmu.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
  })
}

///|
fn esc_register_report_text(report : EscRegisterReport) -> String {
  let buf = @buffer.new(size_hint=768)
  let al_error_flag_text = if report.al_error_flag { "set" } else { "clear" }
  let al_status_code_text = match report.al_status_code {
    Some(code) => format_hex(code, 4)
    None => "not set"
  }
  buf.write_string("EtherCAT ESC Register Snapshot\n")
  buf.write_string("============================\n")
  buf.write_string("Station: " + report.station.to_string() + "\n")
  buf.write_string("AL State: " + report.al_state.to_string() + "\n")
  buf.write_string("AL Error Flag: " + al_error_flag_text + "\n")
  buf.write_string("AL Status Code: " + al_status_code_text + "\n\n")
  buf.write_string("SyncManagers\n")
  buf.write_string("------------\n")
  for sm in report.sync_managers {
    buf.write_string(
      "SM" +
      sm.index.to_string() +
      " @ " +
      format_hex(sm.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + sm.raw_hex + "\n")
    buf.write_string(
      "  Physical Start: ... " + format_hex(sm.physical_start, 4) + "\n",
    )
    buf.write_string("  Length: ........... " + sm.length.to_string() + "\n")
    buf.write_string(
      "  Control: .......... " + format_hex(sm.control.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Status: ........... " + format_hex(sm.status.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(sm.activate.to_uint(), 2) + "\n",
    )
  }
  buf.write_string("\nFMMU\n")
  buf.write_string("----\n")
  for fmmu in report.fmmus {
    buf.write_string(
      "FMMU" +
      fmmu.index.to_string() +
      " @ " +
      format_hex(fmmu.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + fmmu.raw_hex + "\n")
    buf.write_string(
      "  Logical Start: .... " + format_hex(fmmu.logical_start, 8) + "\n",
    )
    buf.write_string("  Length: ........... " + fmmu.length.to_string() + "\n")
    buf.write_string(
      "  Logical Bits: ..... " +
      fmmu.logical_start_bit.to_uint().to_string() +
      "-" +
      fmmu.logical_end_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Physical Start: ... " + format_hex(fmmu.physical_start, 4) + "\n",
    )
    buf.write_string(
      "  Physical Bit: ..... " +
      fmmu.physical_start_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Type Register: .... " +
      format_hex(fmmu.type_register.to_uint(), 2) +
      " (" +
      esc_fmmu_type_description(fmmu.type_register) +
      ")\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(fmmu.activate.to_uint(), 2) + "\n",
    )
  }
  buf.to_string()
}

///|
fn expected_esc_register_report_text(
  report : ExpectedEscRegisterReport,
) -> String {
  let buf = @buffer.new(size_hint=640)
  buf.write_string("Expected EtherCAT ESC Process Mapping\n")
  buf.write_string("====================================\n")
  buf.write_string("Station: " + report.station.to_string() + "\n\n")
  buf.write_string("SyncManagers\n")
  buf.write_string("------------\n")
  for sm in report.sync_managers {
    buf.write_string(
      "SM" +
      sm.index.to_string() +
      " @ " +
      format_hex(sm.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + sm.raw_hex + "\n")
    buf.write_string(
      "  Physical Start: ... " + format_hex(sm.physical_start, 4) + "\n",
    )
    buf.write_string("  Length: ........... " + sm.length.to_string() + "\n")
    buf.write_string(
      "  Control: .......... " + format_hex(sm.control.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Status: ........... " + format_hex(sm.status.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(sm.activate.to_uint(), 2) + "\n",
    )
  }
  buf.write_string("\nFMMU\n")
  buf.write_string("----\n")
  for fmmu in report.fmmus {
    buf.write_string(
      "FMMU" +
      fmmu.index.to_string() +
      " @ " +
      format_hex(fmmu.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + fmmu.raw_hex + "\n")
    buf.write_string(
      "  Logical Start: .... " + format_hex(fmmu.logical_start, 8) + "\n",
    )
    buf.write_string("  Length: ........... " + fmmu.length.to_string() + "\n")
    buf.write_string(
      "  Logical Bits: ..... " +
      fmmu.logical_start_bit.to_uint().to_string() +
      ".." +
      fmmu.logical_end_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Physical Start: ... " + format_hex(fmmu.physical_start, 4) + "\n",
    )
    buf.write_string(
      "  Physical Bit: ..... " +
      fmmu.physical_start_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Type: ............. " +
      format_hex(fmmu.type_register.to_uint(), 2) +
      " (" +
      esc_fmmu_type_description(fmmu.type_register) +
      ")\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(fmmu.activate.to_uint(), 2) + "\n",
    )
  }
  buf.to_string()
}

///|
fn diagnosis_output_json(
  scan : @runtime.ScanReport,
  report : @runtime.SlaveDiagnosis,
) -> Json {
  Json::object({
    "station": Json::number(report.station_address.to_double()),
    "al_state": match report.al_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_error_flag": match report.al_error_flag {
      Some(flag) => Json::boolean(flag)
      None => Json::null()
    },
    "al_status_code": match report.al_status_code {
      Some(code) => Json::number(code.to_double())
      None => Json::null()
    },
    "error_register": Json::number(report.error_register.to_uint().to_double()),
    "diagnosis_counter": match report.diagnosis_counter {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_slave_diagnosis(scan, report),
    ),
  })
}

///|
fn diagnosis_report_text(report : @runtime.SlaveDiagnosis) -> String {
  let buf = @buffer.new(size_hint=192)
  let al_state_text = match report.al_state {
    Some(state) => state.to_string()
    None => "unknown"
  }
  let al_error_flag_text = match report.al_error_flag {
    Some(true) => "set"
    Some(false) => "clear"
    None => "unknown"
  }
  let al_status_code_text = match report.al_status_code {
    Some(code) => format_hex(code, 4)
    None => "unknown"
  }
  let diagnosis_counter_text = match report.diagnosis_counter {
    Some(value) => value.to_string()
    None => "not available"
  }
  buf.write_string("EtherCAT Slave Diagnosis\n")
  buf.write_string("========================\n")
  buf.write_string("Station: " + report.station_address.to_string() + "\n")
  buf.write_string("AL State: " + al_state_text + "\n")
  buf.write_string("AL Error Flag: " + al_error_flag_text + "\n")
  buf.write_string("AL Status Code: " + al_status_code_text + "\n")
  buf.write_string(
    "Error Register: " + format_hex(report.error_register.to_uint(), 2) + "\n",
  )
  buf.write_string("Diagnosis Counter: " + diagnosis_counter_text + "\n")
  buf.to_string()
}

///|
fn od_report_json(report : OdBrowseReport) -> Json {
  Json::object({
    "station": match report.station_address {
      Some(station) => Json::number(station.to_double())
      None => Json::null()
    },
    "mode": Json::string(report.mode),
    "list_type": Json::number(report.list_type.to_double()),
    "index": match report.index {
      Some(index) => Json::number(index.to_double())
      None => Json::null()
    },
    "subindex": match report.subindex {
      Some(subindex) => Json::number(subindex.to_uint().to_double())
      None => Json::null()
    },
    "indices": match report.indices {
      Some(indices) =>
        Json::array(indices.map(fn(index) { Json::number(index.to_double()) }))
      None => Json::null()
    },
    "object": match report.object_description {
      Some(description) =>
        Json::object({
          "index": Json::number(description.index.to_double()),
          "data_type": Json::number(description.data_type.to_double()),
          "object_code": Json::number(
            description.object_code.to_uint().to_double(),
          ),
          "max_subindex": Json::number(
            description.max_subindex.to_uint().to_double(),
          ),
          "name": Json::string(description.name),
        })
      None => Json::null()
    },
    "entry": match report.entry_description {
      Some(description) =>
        Json::object({
          "index": Json::number(description.index.to_double()),
          "subindex": Json::number(description.subindex.to_uint().to_double()),
          "value_info": Json::number(
            description.value_info.to_uint().to_double(),
          ),
          "data_type": Json::number(description.data_type.to_double()),
          "bit_length": Json::number(description.bit_length.to_double()),
          "access": Json::number(description.access.to_double()),
          "name": Json::string(description.name),
        })
      None => Json::null()
    },
    "value": match report.value_hex {
      Some(value_hex) =>
        Json::object({
          "hex": Json::string(value_hex),
          "u32_le": match report.value_u32 {
            Some(value) => Json::number(value.to_double())
            None => Json::null()
          },
        })
      None => Json::null()
    },
    "error": match report.error_category {
      Some(category) =>
        Json::object({
          "category": Json::string(category),
          "detail": match report.error_detail {
            Some(detail) => Json::string(detail)
            None => Json::null()
          },
          "abort_code": match report.abort_code {
            Some(code) => Json::number(code.to_double())
            None => Json::null()
          },
        })
      None => Json::null()
    },
  })
}

///|
fn od_report_text(report : OdBrowseReport) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("EtherCAT Object Dictionary\n")
  buf.write_string("==========================\n")
  let station_text = match report.station_address {
    Some(station) => station.to_string()
    None => "unknown"
  }
  buf.write_string("Station: " + station_text + "\n")
  buf.write_string("Mode: " + report.mode + "\n")
  match report.error_category {
    Some(category) => {
      buf.write_string("Error Category: " + category + "\n")
      match report.abort_code {
        Some(code) =>
          buf.write_string("Abort Code: " + format_hex(code, 8) + "\n")
        None => ()
      }
      match report.error_detail {
        Some(detail) => buf.write_string("Error Detail: " + detail + "\n")
        None => ()
      }
    }
    None => ()
  }
  match report.indices {
    Some(indices) => {
      buf.write_string("List Type: " + report.list_type.to_string() + "\n")
      buf.write_string("Indices:\n")
      for index in indices {
        buf.write_string("  - " + format_hex(index, 4) + "\n")
      }
    }
    None => ()
  }
  match report.object_description {
    Some(description) => {
      buf.write_string("Index: " + format_hex(description.index, 4) + "\n")
      buf.write_string("Name: " + description.name + "\n")
      buf.write_string(
        "Data Type: " + format_hex(description.data_type, 4) + "\n",
      )
      buf.write_string(
        "Object Code: " +
        format_hex(description.object_code.to_uint(), 2) +
        "\n",
      )
      buf.write_string(
        "Max Subindex: " + description.max_subindex.to_uint().to_string() + "\n",
      )
    }
    None => ()
  }
  match report.entry_description {
    Some(description) => {
      buf.write_string("Index: " + format_hex(description.index, 4) + "\n")
      buf.write_string(
        "Subindex: " + description.subindex.to_uint().to_string() + "\n",
      )
      buf.write_string("Name: " + description.name + "\n")
      buf.write_string(
        "Data Type: " + format_hex(description.data_type, 4) + "\n",
      )
      buf.write_string(
        "Bit Length: " + description.bit_length.to_string() + "\n",
      )
      buf.write_string("Access: " + format_hex(description.access, 4) + "\n")
      buf.write_string(
        "Value Info: " + format_hex(description.value_info.to_uint(), 2) + "\n",
      )
    }
    None => ()
  }
  match report.value_hex {
    Some(value_hex) => {
      let index = match report.index {
        Some(index) => index
        None => 0U
      }
      let subindex = match report.subindex {
        Some(subindex) => subindex
        None => b'\x00'
      }
      buf.write_string("Index: " + format_hex(index, 4) + "\n")
      buf.write_string("Subindex: " + subindex.to_uint().to_string() + "\n")
      buf.write_string("Value (hex): " + value_hex + "\n")
      match report.value_u32 {
        Some(value) =>
          buf.write_string("Value (u32 le): " + value.to_string() + "\n")
        None => ()
      }
    }
    None => ()
  }
  buf.to_string()
}

///|
fn od_failure_report(
  station : UInt?,
  query : OdBrowseQuery,
  err : @hal.EcError,
) -> OdBrowseReport {
  {
    station_address: station,
    mode: od_mode_from_query(query),
    list_type: query.list_type,
    index: query.index,
    subindex: query.subindex,
    indices: None,
    object_description: None,
    entry_description: None,
    value_hex: None,
    value_u32: None,
    error_category: Some(od_error_category(err)),
    error_detail: Some(err.to_string()),
    abort_code: match err {
      @hal.EcError::SdoAbort(code) => Some(code)
      _ => None
    },
  }
}

///|
fn od_mode_from_query(query : OdBrowseQuery) -> String {
  if query.read_value {
    return "od-value"
  }
  match (query.index, query.subindex) {
    (None, _) => "od-list"
    (Some(_), None) => "od-object"
    (Some(_), Some(_)) => "od-entry"
  }
}

///|
fn decode_payload_u32_le(payload : Bytes) -> UInt? {
  if payload.length() <= 0 || payload.length() > 4 {
    return None
  }
  let mut value = 0U
  for i = 0; i < payload.length(); i = i + 1 {
    value = value | (payload[i].to_uint() << (i * 8))
  }
  Some(value)
}

///|
fn decode_u16_le(payload : Bytes, offset : Int) -> UInt {
  if offset + 1 >= payload.length() {
    0U
  } else {
    payload[offset].to_uint() | (payload[offset + 1].to_uint() << 8)
  }
}

///|
fn decode_u32_le(payload : Bytes, offset : Int) -> UInt {
  if offset + 3 >= payload.length() {
    0U
  } else {
    payload[offset].to_uint() |
    (payload[offset + 1].to_uint() << 8) |
    (payload[offset + 2].to_uint() << 16) |
    (payload[offset + 3].to_uint() << 24)
  }
}

///|
fn bytes_hex(payload : Bytes) -> String {
  let buf = @buffer.new(size_hint=payload.length() * 2 + 2)
  buf.write_string("0x")
  for i = 0; i < payload.length(); i = i + 1 {
    buf.write_string(hex_digit((payload[i].to_int() >> 4) & 0x0F))
    buf.write_string(hex_digit(payload[i].to_int() & 0x0F))
  }
  buf.to_string()
}

///|
fn od_error_category(err : @hal.EcError) -> String {
  match err {
    @hal.EcError::LinkDown => "transport-failure"
    @hal.EcError::SendFailed(_) => "transport-failure"
    @hal.EcError::RecvTimeout => "transport-failure"
    @hal.EcError::RecvFailed(_) => "transport-failure"
    @hal.EcError::MailboxTimeout => "transport-failure"
    @hal.EcError::InvalidFrame(_) => "protocol-failure"
    @hal.EcError::InvalidPdu(_) => "protocol-failure"
    @hal.EcError::UnexpectedWkc(..) => "protocol-failure"
    @hal.EcError::MailboxProtocol(_) => "protocol-failure"
    @hal.EcError::SdoAbort(_) => "protocol-failure"
    @hal.EcError::NotSupported(_) => "unsupported"
    _ => "command-failure"
  }
}

///|
fn resolve_timeout(args : Array[String]) -> @hal.Duration raise @hal.EcError {
  let timeout_ms = require_int_flag(args, "--timeout-ms", 1)
  if timeout_ms <= 0 {
    raise @hal.EcError::ConfigMismatch(
      "timeout value for --timeout-ms must be > 0",
    )
  }
  @hal.Duration(timeout_ms.to_int64() * 1_000_000L)
}

///|
fn resolve_run_cycles(
  args : Array[String],
  until_fault : Bool,
) -> Int raise @hal.EcError {
  if until_fault {
    match flag_value(args, "--cycles") {
      Some(_) =>
        raise @hal.EcError::ConfigMismatch(
          "--cycles cannot be combined with --until-fault",
        )
      None => ()
    }
    return 0
  }
  let cycles = require_int_flag(args, "--cycles", 10)
  if cycles <= 0 {
    raise @hal.EcError::ConfigMismatch("cycle value for --cycles must be > 0")
  }
  cycles
}

///|
fn resolve_run_loop_settings(
  args : Array[String],
  as_json : Bool,
  until_fault : Bool,
  progress_ndjson : Bool,
) -> @runtime.RunLoopSettings raise @hal.EcError {
  let cycles = resolve_run_cycles(args, until_fault)
  let cycle_period_ns = optional_duration_flag_ns(
    args, "--cycle-period-us", 1_000L,
  )
  let output_period_ns = optional_duration_flag_ns(
    args, "--output-period-ms", 1_000_000L,
  )
  if progress_ndjson && not(as_json) {
    raise @hal.EcError::ConfigMismatch("--progress-ndjson requires --json")
  }
  if as_json && not(progress_ndjson) {
    match output_period_ns {
      Some(_) =>
        raise @hal.EcError::ConfigMismatch(
          "--output-period-ms cannot be combined with --json unless --progress-ndjson is enabled",
        )
      None => ()
    }
  }
  if progress_ndjson && output_period_ns is None {
    raise @hal.EcError::ConfigMismatch(
      "--progress-ndjson requires --output-period-ms",
    )
  }
  let max_consecutive_timeouts = require_int_flag(
    args, "--max-consecutive-timeouts", 5,
  )
  if max_consecutive_timeouts <= 0 {
    raise @hal.EcError::ConfigMismatch(
      "timeout value for --max-consecutive-timeouts must be > 0",
    )
  }
  let base = if until_fault {
    @runtime.RunLoopSettings::until_fault()
  } else {
    @runtime.RunLoopSettings::fixed_cycles(cycles)
  }
  { ..base, cycle_period_ns, output_period_ns, max_consecutive_timeouts }
}

///|
fn resolve_run_progress_output(
  as_json : Bool,
  progress_ndjson : Bool,
  output_period_ns : Int64?,
) -> RunProgressOutput {
  match output_period_ns {
    Some(_) => if as_json && progress_ndjson { Ndjson } else { Text }
    None => Silent
  }
}

///|
fn optional_duration_flag_ns(
  args : Array[String],
  flag : String,
  unit_ns : Int64,
) -> Int64? raise @hal.EcError {
  match flag_value(args, flag) {
    Some(text) => {
      let value = parse_int_flag(flag, text)
      if value <= 0 {
        raise @hal.EcError::ConfigMismatch(
          "numeric value for " + flag + " must be > 0",
        )
      }
      Some(value.to_int64() * unit_ns)
    }
    None => None
  }
}

///|
fn flag_value(args : Array[String], flag : String) -> String? {
  for i = 0; i < args.length() - 1; i = i + 1 {
    if args[i] == flag {
      return Some(args[i + 1])
    }
  }
  None
}

///|
fn require_uint_flag(
  args : Array[String],
  flag : String,
  default : UInt,
) -> UInt raise @hal.EcError {
  match flag_value(args, flag) {
    Some(text) => parse_uint_flag(flag, text)
    None => default
  }
}

///|
fn require_int_flag(
  args : Array[String],
  flag : String,
  default : Int,
) -> Int raise @hal.EcError {
  match flag_value(args, flag) {
    Some(text) => parse_int_flag(flag, text)
    None => default
  }
}

///|
fn parse_uint_flag(flag : String, text : String) -> UInt raise @hal.EcError {
  let mut value = 0U
  if text == "" {
    raise @hal.EcError::ConfigMismatch("missing numeric value for " + flag)
  }
  let bytes = @utf8.encode(text)
  for ch in bytes {
    if ch == b'\x00' {
      continue
    }
    if ch < b'0' || ch > b'9' {
      raise @hal.EcError::ConfigMismatch(
        "invalid numeric value for " + flag + ": " + text,
      )
    }
    value = value * 10U + (ch.to_uint() - b'0'.to_uint())
  }
  value
}

///|
fn parse_byte_flag(flag : String, text : String) -> Byte raise @hal.EcError {
  let value = parse_uint_flag(flag, text)
  if value > 255U {
    raise @hal.EcError::ConfigMismatch(
      "value out of byte range for " + flag + ": " + text,
    )
  }
  value.to_byte()
}

///|
fn parse_int_flag(flag : String, text : String) -> Int raise @hal.EcError {
  parse_uint_flag(flag, text).reinterpret_as_int()
}

///|
fn resolved_sii_string(strings : Array[String], index : Byte) -> String {
  let idx = index.to_int()
  if idx <= 0 || idx > strings.length() {
    "not set"
  } else {
    strings[idx - 1]
  }
}

///|
fn physical_port_name(port : Byte) -> String {
  match port {
    b'\x00' => "not used"
    b'\x01' => "MII"
    b'\x02' => "reserved"
    b'\x03' => "EBUS"
    b'\x04' => "Fast Hot Connect"
    _ => "unknown"
  }
}

///|
fn fmmu_usage_name(direction : @mailbox.FmmuDirection) -> String {
  match direction {
    Outputs => "used for Outputs"
    Inputs => "used for Inputs"
    MailboxState => "used for SyncM mailbox status (MBoxStat)"
  }
}

///|
fn sm_type_name(sm_type : @mailbox.SmType) -> String {
  match sm_type {
    MailboxOut => "Mailbox Out"
    MailboxIn => "Mailbox In"
    ProcessDataOut => "Process Data Out"
    ProcessDataIn => "Process Data In"
    DynamicProcessDataOut => "Dynamic Process Data Out"
    DynamicProcessDataIn => "Dynamic Process Data In"
    Unused => "not used or unknown"
  }
}

///|
fn production_weekday_name(weekday : Int) -> String {
  match weekday {
    1 => "Monday"
    2 => "Tuesday"
    3 => "Wednesday"
    4 => "Thursday"
    5 => "Friday"
    6 => "Saturday"
    7 => "Sunday"
    _ => "not set"
  }
}

///|
fn bytes_preview_hex(data : Bytes, max_bytes : Int) -> String {
  let buf = @buffer.new(size_hint=max_bytes * 3)
  let limit = if data.length() < max_bytes { data.length() } else { max_bytes }
  for i = 0; i < limit; i = i + 1 {
    if i > 0 {
      buf.write_string(" ")
    }
    buf.write_string(format_hex(data[i].to_uint(), 2))
  }
  if data.length() > max_bytes {
    buf.write_string(" ...")
  }
  buf.to_string()
}

///|
fn bool_yes_no(value : Bool) -> String {
  if value {
    "yes"
  } else {
    "no"
  }
}

///|
fn bool_enabled_text(value : Bool) -> String {
  if value {
    "enabled"
  } else {
    "not enabled"
  }
}

///|
fn esc_fmmu_type_description(type_register : Byte) -> String {
  match type_register {
    b'\x01' => "inputs"
    b'\x02' => "outputs"
    b'\x00' => "deactivated"
    _ => "unknown"
  }
}

///|
fn bool_true_false(value : Bool) -> String {
  if value {
    "True"
  } else {
    "False"
  }
}

///|
fn hex_digit(value : Int) -> String {
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

///|
fn format_hex(value : UInt, digits : Int) -> String {
  let buf = @buffer.new(size_hint=digits + 2)
  buf.write_string("0x")
  let mut index = digits - 1
  while index >= 0 {
    let nibble = ((value >> (index * 4)) & 0xFU).reinterpret_as_int()
    buf.write_string(hex_digit(nibble))
    if index == 0 {
      break
    }
    index = index - 1
  }
  buf.to_string()
}

///|
fn general_json(info : @mailbox.SiiGeneral, strings : Array[String]) -> Json {
  Json::object({
    "group_idx": Json::number(info.group_idx.to_uint().to_double()),
    "group_name": Json::string(resolved_sii_string(strings, info.group_idx)),
    "image_idx": Json::number(info.image_idx.to_uint().to_double()),
    "image_name": Json::string(resolved_sii_string(strings, info.image_idx)),
    "order_idx": Json::number(info.order_idx.to_uint().to_double()),
    "order_name": Json::string(resolved_sii_string(strings, info.order_idx)),
    "name_idx": Json::number(info.name_idx.to_uint().to_double()),
    "name": Json::string(resolved_sii_string(strings, info.name_idx)),
    "coe_details": Json::object({
      "raw": Json::number(info.coe_details.to_uint().to_double()),
      "enable_sdo": Json::boolean(info.supports_coe_sdo()),
      "enable_sdo_info": Json::boolean(info.supports_coe_sdo_info()),
      "enable_pdo_assign": Json::boolean(info.supports_coe_pdo_assign()),
      "enable_pdo_configuration": Json::boolean(
        info.supports_coe_pdo_configuration(),
      ),
      "enable_upload_at_startup": Json::boolean(
        info.supports_coe_upload_at_startup(),
      ),
      "enable_sdo_complete_access": Json::boolean(
        info.supports_coe_complete_access(),
      ),
    }),
    "foe_supported": Json::boolean(info.foe_supported),
    "eoe_supported": Json::boolean(info.eoe_supported),
    "soe_supported": Json::boolean(info.soe_supported),
    "soe_channels": Json::number(info.soe_channels.to_uint().to_double()),
    "ds402_channels": Json::number(info.ds402_channels.to_uint().to_double()),
    "sysman_class": Json::number(info.sysman_class.to_uint().to_double()),
    "flags": Json::object({
      "raw": Json::number(info.flags.to_uint().to_double()),
      "safe_op": Json::boolean(info.is_op_only()),
      "not_lrw": Json::boolean(info.prefers_not_lrw()),
      "mailbox_data_link_layer": Json::boolean(
        info.supports_mailbox_data_link_layer(),
      ),
      "ident_al_status": Json::boolean(info.supports_identification_ado()),
      "ident_physical_memory": Json::boolean(
        info.supports_identification_physical_memory(),
      ),
    }),
    "current_on_ebus": Json::number(info.current_on_ebus.to_double()),
    "physical_ports": Json::array([
      Json::string(physical_port_name(info.physical_port_0)),
      Json::string(physical_port_name(info.physical_port_1)),
      Json::string(physical_port_name(info.physical_port_2)),
      Json::string(physical_port_name(info.physical_port_3)),
    ]),
    "physical_memory_address": Json::number(
      info.physical_memory_address.to_double(),
    ),
  })
}

///|
fn pdo_json(pdo : @mailbox.SiiPdo, strings : Array[String]) -> Json {
  let entries_json = pdo.entries.map(fn(entry) {
    Json::object({
      "entry_index": Json::number(entry.entry_index.to_double()),
      "subindex": Json::number(entry.subindex.to_uint().to_double()),
      "name_idx": Json::number(entry.name_idx.to_uint().to_double()),
      "name": Json::string(resolved_sii_string(strings, entry.name_idx)),
      "data_type": Json::number(entry.data_type.to_uint().to_double()),
      "bit_length": Json::number(entry.bit_length.to_uint().to_double()),
      "flags": Json::number(entry.flags.to_double()),
    })
  })
  Json::object({
    "pdo_index": Json::number(pdo.pdo_index.to_double()),
    "entry_count": Json::number(pdo.entry_count.to_uint().to_double()),
    "sync_manager": Json::number(pdo.sync_manager.to_uint().to_double()),
    "synchronization": Json::number(pdo.synchronization.to_uint().to_double()),
    "name_idx": Json::number(pdo.name_idx.to_uint().to_double()),
    "name": Json::string(resolved_sii_string(strings, pdo.name_idx)),
    "flags": Json::number(pdo.flags.to_double()),
    "entries": Json::array(entries_json),
  })
}

///|
fn read_sii_json(
  position : UInt,
  word_count : Int,
  sii : @mailbox.SiiFullInfo,
) -> Json {
  let preamble = sii.preamble
  let standard = sii.standard
  let header = sii.header
  let general = sii.general
  let strings = sii.strings
  let fmmu = sii.fmmu
  let sync_managers = sii.sync_managers
  let dc_clocks = sii.dc_clocks
  let tx_pdo = sii.tx_pdo
  let rx_pdo = sii.rx_pdo
  let categories = sii.categories
  let categories_json = categories.map(fn(entry) {
    let category_class = entry.category_class().label()
    let overlay_key = match entry.overlay_candidate() {
      Some(candidate) => Json::string(candidate.dispatch_key())
      None => Json::null()
    }
    Json::object({
      "category": Json::string(entry.category.to_string()),
      "title": Json::string(sii_category_title(entry.category, entry.type_code)),
      "category_code": Json::number(entry.type_code.to_double()),
      "category_class": Json::string(category_class),
      "overlay_key": overlay_key,
      "known": Json::boolean(entry.category != @mailbox.Raw),
      "byte_length": Json::number(entry.data.length().to_double()),
      "preview_hex": Json::string(bytes_preview_hex(entry.data, 16)),
    })
  })
  let strings_json = strings.map(fn(text) { Json::string(text) })
  let general_json = match general {
    Some(info) => general_json(info, strings)
    None => Json::null()
  }
  let fmmu_json = fmmu.map(fn(direction) {
    Json::object({
      "usage": Json::string(direction.to_string()),
      "description": Json::string(fmmu_usage_name(direction)),
    })
  })
  let fmmu_ex_json = sii.fmmu_ex.map(fn(entry) {
    Json::object({
      "op_only": Json::boolean(entry.op_only),
      "sm_defined": Json::boolean(entry.sm_defined),
      "su_defined": Json::boolean(entry.su_defined),
      "sync_manager": Json::number(entry.sync_manager.to_uint().to_double()),
      "sync_unit": Json::number(entry.sync_unit.to_uint().to_double()),
    })
  })
  let sm_json = sync_managers.map(fn(sm) {
    Json::object({
      "physical_start": Json::number(sm.physical_start.to_double()),
      "length": Json::number(sm.length.to_double()),
      "control": Json::number(sm.control.to_uint().to_double()),
      "status": Json::number(sm.status.to_uint().to_double()),
      "activate": Json::number(sm.activate.to_uint().to_double()),
      "sm_type": Json::string(sm.sm_type.to_string()),
    })
  })
  let sync_units_json = sii.sync_units.map(fn(entry) {
    Json::object({
      "separate_su": Json::boolean(entry.separate_su),
      "separate_frame": Json::boolean(entry.separate_frame),
      "depend_on_input_state": Json::boolean(entry.depend_on_input_state),
      "frame_repeat_support": Json::boolean(entry.frame_repeat_support),
      "raw_flags": Json::number(entry.raw_flags.to_uint().to_double()),
    })
  })
  let dc_json = dc_clocks.map(fn(dc) {
    Json::object({
      "cycle_time_0": Json::number(dc.cycle_time_0.to_double()),
      "shift_time_0": Json::number(dc.shift_time_0.to_double()),
      "shift_time_1": Json::number(dc.shift_time_1.to_double()),
      "sync1_cycle_factor": Json::number(dc.sync1_cycle_factor.to_double()),
      "assign_activate": Json::number(dc.assign_activate.to_double()),
      "sync0_cycle_factor": Json::number(dc.sync0_cycle_factor.to_double()),
      "name_idx": Json::number(dc.name_idx.to_uint().to_double()),
      "name": Json::string(resolved_sii_string(strings, dc.name_idx)),
      "description_idx": Json::number(dc.description_idx.to_uint().to_double()),
      "description": Json::string(
        resolved_sii_string(strings, dc.description_idx),
      ),
    })
  })
  let tx_pdo_json = tx_pdo.map(fn(pdo) { pdo_json(pdo, strings) })
  let rx_pdo_json = rx_pdo.map(fn(pdo) { pdo_json(pdo, strings) })
  let timeouts_json = match sii.timeouts {
    Some(value) =>
      Json::object({
        "preop_timeout_ms": Json::number(value.preop_timeout_ms.to_double()),
        "safeop_op_timeout_ms": Json::number(
          value.safeop_op_timeout_ms.to_double(),
        ),
        "back_to_init_timeout_ms": Json::number(
          value.back_to_init_timeout_ms.to_double(),
        ),
        "back_to_safeop_timeout_ms": Json::number(
          value.back_to_safeop_timeout_ms.to_double(),
        ),
        "mailbox_request_timeout_ms": Json::number(
          value.mailbox_request_timeout_ms.to_double(),
        ),
        "mailbox_response_timeout_ms": Json::number(
          value.mailbox_response_timeout_ms.to_double(),
        ),
      })
    None => Json::null()
  }
  Json::object({
    "position": Json::number(position.to_double()),
    "word_count": Json::number(word_count.to_double()),
    "preamble": Json::object({
      "pdi_control": Json::number(preamble.pdi_control.to_double()),
      "pdi_config": Json::number(preamble.pdi_config.to_double()),
      "sync_impulse_length_raw": Json::number(
        preamble.sync_impulse_length_raw.to_double(),
      ),
      "sync_impulse_length_ns": Json::number(
        preamble.sync_impulse_length_ns().to_double(),
      ),
      "pdi_config2": Json::number(preamble.pdi_config2.to_double()),
      "configured_station_alias": Json::number(
        preamble.configured_station_alias.to_double(),
      ),
      "checksum": Json::number(preamble.checksum.to_double()),
      "checksum_ok": Json::boolean(preamble.checksum_ok),
    }),
    "header": Json::object({
      "vendor_id": Json::number(header.vendor_id.to_double()),
      "product_code": Json::number(header.product_code.to_double()),
      "revision": Json::number(header.revision.to_double()),
      "serial": Json::number(header.serial.to_double()),
      "bootstrap_rx_offset": Json::number(
        header.bootstrap_rx_offset.to_double(),
      ),
      "bootstrap_rx_size": Json::number(header.bootstrap_rx_size.to_double()),
      "bootstrap_tx_offset": Json::number(
        header.bootstrap_tx_offset.to_double(),
      ),
      "bootstrap_tx_size": Json::number(header.bootstrap_tx_size.to_double()),
      "mailbox_rx_offset": Json::number(header.mailbox_rx_offset.to_double()),
      "mailbox_rx_size": Json::number(header.mailbox_rx_size.to_double()),
      "mailbox_tx_offset": Json::number(header.mailbox_tx_offset.to_double()),
      "mailbox_tx_size": Json::number(header.mailbox_tx_size.to_double()),
      "mailbox_protocols": Json::number(header.mailbox_protocols.to_double()),
      "firmware_version": Json::number(header.firmware_version.to_double()),
      "hardware_version": Json::number(header.hardware_version.to_double()),
      "production_date_raw": Json::number(
        header.production_date_raw.to_double(),
      ),
      "production_year": Json::number(header.production_year().to_double()),
      "production_weekday": Json::number(
        header.production_weekday().to_double(),
      ),
      "production_week": Json::number(header.production_week().to_double()),
      "esc_config_b_present": Json::boolean(header.esc_config_b_present),
      "pdi_control_1": Json::number(header.pdi_control_1.to_uint().to_double()),
      "esc_config_b0": Json::number(header.esc_config_b0.to_uint().to_double()),
      "pdi_config_1": Json::number(header.pdi_config_1.to_double()),
      "pdi_config_1_ext": Json::number(header.pdi_config_1_ext.to_double()),
      "esc_config_b4": Json::number(header.esc_config_b4.to_double()),
      "esc_config_b5": Json::number(header.esc_config_b5.to_double()),
      "esc_config_b6": Json::number(header.esc_config_b6.to_double()),
      "checksum_b": Json::number(header.checksum_b.to_double()),
    }),
    "supported_mailboxes": Json::object({
      "aoe": Json::boolean(header.supports_aoe()),
      "coe": Json::boolean(header.supports_coe()),
      "eoe": Json::boolean(header.supports_eoe()),
      "foe": Json::boolean(header.supports_foe()),
      "soe": Json::boolean(header.supports_soe()),
      "voe": Json::boolean(header.supports_voe()),
    }),
    "standard_metadata": Json::object({
      "eeprom_size_raw": Json::number(standard.eeprom_size_raw.to_double()),
      "eeprom_size_bytes": Json::number(
        standard.eeprom_size_bytes().to_double(),
      ),
      "version": Json::number(standard.version.to_double()),
    }),
    "general": general_json,
    "strings": Json::array(strings_json),
    "fmmu": Json::array(fmmu_json),
    "fmmu_ex": Json::array(fmmu_ex_json),
    "sync_managers": Json::array(sm_json),
    "sync_units": Json::array(sync_units_json),
    "dc_clocks": Json::array(dc_json),
    "timeouts": timeouts_json,
    "tx_pdo": Json::array(tx_pdo_json),
    "rx_pdo": Json::array(rx_pdo_json),
    "categories": Json::array(categories_json),
  })
}

///|
fn sii_category_title(
  category : @mailbox.SiiCategory,
  type_code : UInt,
) -> String {
  match category {
    Strings => "Strings"
    DataTypes => "DataTypes"
    General => "General"
    Fmmu => "FMMU"
    SyncManager => "SyncManager"
    FmmuEx => "FMMU_EX"
    SyncUnit => "SyncUnit"
    TxPdo => "TX PDO"
    RxPdo => "RX PDO"
    Dc => "DC CLOCK"
    Timeouts => "Timeouts"
    Dictionary => "Dictionary"
    Hardware => "Hardware"
    VendorInformation => "Vendor Information"
    Images => "Images"
    Raw => "Raw Category " + format_hex(type_code, 4)
  }
}

///|
fn append_sii_strings_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string(
    "  Size: " +
    entry.data.length().to_string() +
    " Bytes with " +
    strings.length().to_string() +
    " strings\n",
  )
  buf.write_string("  ID   Size (Bytes)    String\n")
  for i = 0; i < strings.length(); i = i + 1 {
    let text = strings[i]
    buf.write_string(
      "  " +
      (i + 1).to_string() +
      ": (" +
      text.length().to_string() +
      ") ......... '" +
      text +
      "'\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_general_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  info : @mailbox.SiiGeneral,
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Vendor Specific (Index of String)\n")
  buf.write_string(
    "    Name  Index: " +
    info.name_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.name_idx) +
    "\n",
  )
  buf.write_string(
    "    Group Index: " +
    info.group_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.group_idx) +
    "\n",
  )
  buf.write_string(
    "    Image Index: " +
    info.image_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.image_idx) +
    "\n",
  )
  buf.write_string(
    "    Order Index: " +
    info.order_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.order_idx) +
    "\n\n",
  )
  buf.write_string("  CoE Details:\n")
  buf.write_string(
    "    Enable SDO: .................. " +
    bool_yes_no(info.supports_coe_sdo()) +
    "\n",
  )
  buf.write_string(
    "    Enable SDO Info: ............. " +
    bool_yes_no(info.supports_coe_sdo_info()) +
    "\n",
  )
  buf.write_string(
    "    Enable PDO Assign: ........... " +
    bool_yes_no(info.supports_coe_pdo_assign()) +
    "\n",
  )
  buf.write_string(
    "    Enable PDO Configuration: .... " +
    bool_yes_no(info.supports_coe_pdo_configuration()) +
    "\n",
  )
  buf.write_string(
    "    Enable Upload at Startup: .... " +
    bool_yes_no(info.supports_coe_upload_at_startup()) +
    "\n",
  )
  buf.write_string(
    "    Enable SDO complete access: .. " +
    bool_yes_no(info.supports_coe_complete_access()) +
    "\n",
  )
  buf.write_string(
    "  FoE Details: ................... " +
    bool_enabled_text(info.foe_supported) +
    "\n",
  )
  buf.write_string(
    "  EoE Details: ................... " +
    bool_enabled_text(info.eoe_supported) +
    "\n\n",
  )
  buf.write_string(
    "  Flag SafeOp: ................... " +
    bool_enabled_text(info.is_op_only()) +
    "\n",
  )
  buf.write_string(
    "  Flag notLRW: ................... " +
    bool_enabled_text(info.prefers_not_lrw()) +
    "\n",
  )
  buf.write_string(
    "  Flag MBox Data Link Layer ...... " +
    bool_enabled_text(info.supports_mailbox_data_link_layer()) +
    "\n",
  )
  buf.write_string(
    "  Flag Ident AL Status ........... " +
    bool_enabled_text(info.supports_identification_ado()) +
    "\n",
  )
  buf.write_string(
    "  Flag Ident Physical Memory ..... " +
    bool_enabled_text(info.supports_identification_physical_memory()) +
    "\n\n",
  )
  buf.write_string(
    "  CurrentOnEBus: ................. " +
    info.current_on_ebus.to_string() +
    " mA\n",
  )
  buf.write_string("\n  Physical Ports:\n")
  buf.write_string(
    "     Port 0: ..................... " +
    physical_port_name(info.physical_port_0) +
    "\n",
  )
  buf.write_string(
    "     Port 1: ..................... " +
    physical_port_name(info.physical_port_1) +
    "\n",
  )
  buf.write_string(
    "     Port 2: ..................... " +
    physical_port_name(info.physical_port_2) +
    "\n",
  )
  buf.write_string(
    "     Port 3: ..................... " +
    physical_port_name(info.physical_port_3) +
    "\n\n",
  )
  buf.write_string(
    "  Physical Memory Address ........ " +
    format_hex(info.physical_memory_address, 4) +
    "\n\n",
  )
}

///|
fn append_sii_fmmu_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  fmmu : Array[@mailbox.FmmuDirection],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Number of FMMUs: " + fmmu.length().to_string() + "\n")
  for i = 0; i < fmmu.length(); i = i + 1 {
    buf.write_string(
      "    FMMU" + i.to_string() + ": " + fmmu_usage_name(fmmu[i]) + "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_fmmu_ex_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  fmmu_ex : Array[@mailbox.SiiFmmuEx],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Number of FMMU_EX entries: " + fmmu_ex.length().to_string() + "\n",
  )
  for i = 0; i < fmmu_ex.length(); i = i + 1 {
    let current = fmmu_ex[i]
    buf.write_string("    FMMU" + i.to_string() + "\n")
    buf.write_string(
      "      opOnly: ............... " + bool_yes_no(current.op_only) + "\n",
    )
    buf.write_string(
      "      syncManager defined: .. " + bool_yes_no(current.sm_defined) + "\n",
    )
    buf.write_string(
      "      syncUnit defined: ..... " + bool_yes_no(current.su_defined) + "\n",
    )
    buf.write_string(
      "      syncManager index: .... " +
      current.sync_manager.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "      syncUnit index: ....... " +
      current.sync_unit.to_uint().to_string() +
      "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_sm_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  sms : Array[@mailbox.SiiSmEntry],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Number of SyncManager: " + sms.length().to_string() + "\n",
  )
  for i = 0; i < sms.length(); i = i + 1 {
    let sm = sms[i]
    buf.write_string("  SyncManager SM" + i.to_string() + "\n")
    buf.write_string(
      "    Physical Startaddress: ... " +
      format_hex(sm.physical_start, 4) +
      "\n",
    )
    buf.write_string(
      "    Length: .................. " + sm.length.to_string() + "\n",
    )
    buf.write_string(
      "    Control Register: ........ " +
      format_hex(sm.control.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "    Status Register: ......... " +
      format_hex(sm.status.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "    Enable byte: ............. " +
      format_hex(sm.activate.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "    SM Type: ................. " + sm_type_name(sm.sm_type) + "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_dc_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  dc : @mailbox.SiiDcClock,
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Cycle Time 0 .................. " + dc.cycle_time_0.to_string() + "\n",
  )
  buf.write_string(
    "  Shift Time 0 .................. " + dc.shift_time_0.to_string() + "\n",
  )
  buf.write_string(
    "  Shift Time 1 .................. " + dc.shift_time_1.to_string() + "\n",
  )
  buf.write_string(
    "  Sync1 Cycle Factor ............ " +
    dc.sync1_cycle_factor.to_string() +
    "\n",
  )
  buf.write_string(
    "  Assign Activate ............... " + dc.assign_activate.to_string() + "\n",
  )
  buf.write_string(
    "  Sync0 Cylce Factor ............ " +
    dc.sync0_cycle_factor.to_string() +
    "\n",
  )
  buf.write_string(
    "  Name Index .................... " +
    dc.name_idx.to_uint().to_string() +
    " (" +
    resolved_sii_string(strings, dc.name_idx) +
    ")\n",
  )
  buf.write_string(
    "  Description Index ............. " +
    dc.description_idx.to_uint().to_string() +
    " (" +
    resolved_sii_string(strings, dc.description_idx) +
    ")\n\n",
  )
}

///|
fn append_sii_timeouts_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  timeouts : @mailbox.SiiTimeouts,
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  INIT -> PREOP/BOOT Timeout ... " +
    timeouts.preop_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  SAFEOP -> OP Timeout ........ " +
    timeouts.safeop_op_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  Back To INIT Timeout ........ " +
    timeouts.back_to_init_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  OP -> SAFEOP Timeout ........ " +
    timeouts.back_to_safeop_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  Mailbox Request Timeout ..... " +
    timeouts.mailbox_request_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  Mailbox Response Timeout .... " +
    timeouts.mailbox_response_timeout_ms.to_string() +
    " ms\n\n",
  )
}

///|
fn append_sii_sync_unit_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  sync_units : Array[@mailbox.SiiSyncUnit],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Number of SyncUnits: " + sync_units.length().to_string() + "\n",
  )
  for i = 0; i < sync_units.length(); i = i + 1 {
    let current = sync_units[i]
    buf.write_string("    SyncUnit " + i.to_string() + "\n")
    buf.write_string(
      "      separateSu: ........... " + bool_yes_no(current.separate_su) + "\n",
    )
    buf.write_string(
      "      separateFrame: ........ " +
      bool_yes_no(current.separate_frame) +
      "\n",
    )
    buf.write_string(
      "      dependOnInputState: ... " +
      bool_yes_no(current.depend_on_input_state) +
      "\n",
    )
    buf.write_string(
      "      frameRepeatSupport: ... " +
      bool_yes_no(current.frame_repeat_support) +
      "\n",
    )
    buf.write_string(
      "      raw flags: ............ " +
      format_hex(current.raw_flags.to_uint(), 2) +
      "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_pdo_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  pdos : Array[@mailbox.SiiPdo],
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Number of PDOs: " + pdos.length().to_string() + "\n")
  for i = 0; i < pdos.length(); i = i + 1 {
    let pdo = pdos[i]
    buf.write_string(
      "  PDO " +
      i.to_string() +
      ": index=" +
      format_hex(pdo.pdo_index, 4) +
      ", name=" +
      resolved_sii_string(strings, pdo.name_idx) +
      "\n",
    )
    buf.write_string(
      "    Sync Manager: ............ " +
      pdo.sync_manager.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "    Synchronization: ......... " +
      pdo.synchronization.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "    Entry Count: ............. " +
      pdo.entry_count.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "    Flags: ................... " + format_hex(pdo.flags, 4) + "\n",
    )
    for j = 0; j < pdo.entries.length(); j = j + 1 {
      let pdo_entry = pdo.entries[j]
      buf.write_string(
        "    Entry " +
        j.to_string() +
        ": " +
        format_hex(pdo_entry.entry_index, 4) +
        ":" +
        pdo_entry.subindex.to_uint().to_string() +
        " " +
        resolved_sii_string(strings, pdo_entry.name_idx) +
        " (" +
        pdo_entry.bit_length.to_uint().to_string() +
        " bits, type=" +
        format_hex(pdo_entry.data_type.to_uint(), 2) +
        ", flags=" +
        format_hex(pdo_entry.flags, 4) +
        ")\n",
      )
    }
  }
  buf.write_string("\n")
}

///|
fn append_sii_raw_category_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
) -> Unit {
  let category_class = entry.category_class().label()
  let overlay_key = match entry.overlay_candidate() {
    Some(candidate) => candidate.dispatch_key()
    None => ""
  }
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Class: " + category_class + "\n")
  if overlay_key != "" {
    buf.write_string("  Overlay Key: " + overlay_key + "\n")
  }
  buf.write_string(
    "  Raw Preview: " + bytes_preview_hex(entry.data, 24) + "\n\n",
  )
}

///|
fn read_sii_text(
  position : UInt,
  word_count : Int,
  sii : @mailbox.SiiFullInfo,
) -> String {
  let eeprom = sii.eeprom
  let preamble = sii.preamble
  let standard = sii.standard
  let header = sii.header
  let general = sii.general
  let strings = sii.strings
  let categories = sii.categories
  let buf = @buffer.new(size_hint=2048)
  buf.write_string("First print preamble and config\n")
  buf.write_string(
    "Position: ................... " + position.to_string() + "\n",
  )
  buf.write_string(
    "Words requested: ............ " + word_count.to_string() + "\n",
  )
  buf.write_string(
    "Bytes read: ................. " + eeprom.length().to_string() + "\n",
  )
  buf.write_string("Preamble:\n")
  buf.write_string(
    "PDI Control: ................ " +
    format_hex(preamble.pdi_control, 4) +
    "\n",
  )
  buf.write_string(
    "PDI Config: ................. " + format_hex(preamble.pdi_config, 4) + "\n",
  )
  buf.write_string(
    "Sync Impulse Length: ........ " +
    preamble.sync_impulse_length_ns().to_string() +
    " ns (raw: " +
    format_hex(preamble.sync_impulse_length_raw, 4) +
    ")\n",
  )
  buf.write_string(
    "PDI Config 2: ............... " +
    format_hex(preamble.pdi_config2, 4) +
    "\n",
  )
  buf.write_string(
    "Configured Station Alias: ... " +
    format_hex(preamble.configured_station_alias, 4) +
    "\n",
  )
  buf.write_string(
    "Checksum of Preamble: ....... " +
    format_hex(preamble.checksum, 4) +
    " (" +
    (if preamble.checksum_ok { "ok" } else { "wrong" }) +
    ")\n\n",
  )
  buf.write_string("Identity:\n")
  buf.write_string(
    "  Vendor ID: ................ " + format_hex(header.vendor_id, 8) + "\n",
  )
  buf.write_string(
    "  Product ID: ............... " + format_hex(header.product_code, 8) + "\n",
  )
  buf.write_string(
    "  Revision ID: .............. " + format_hex(header.revision, 8) + "\n",
  )
  buf.write_string(
    "  Serial Number: ............ " + format_hex(header.serial, 8) + "\n\n",
  )
  buf.write_string("Default mailbox settings:\n")
  buf.write_string("  Bootstrap Mailbox:\n")
  buf.write_string(
    "  Received Mailbox Offset: .. " +
    format_hex(header.bootstrap_rx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Received Mailbox Size: .... " +
    header.bootstrap_rx_size.to_string() +
    "\n",
  )
  buf.write_string(
    "  Send Mailbox Offset: ...... " +
    format_hex(header.bootstrap_tx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Send Mailbox Size: ........ " +
    header.bootstrap_tx_size.to_string() +
    "\n",
  )
  buf.write_string("\n  Mailbox Settings:\n")
  buf.write_string(
    "  Received Mailbox Offset: .. " +
    format_hex(header.mailbox_rx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Received Mailbox Size: .... " + header.mailbox_rx_size.to_string() + "\n",
  )
  buf.write_string(
    "  Send Mailbox Offset: ...... " +
    format_hex(header.mailbox_tx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Send Mailbox Size: ........ " +
    header.mailbox_tx_size.to_string() +
    "\n\n",
  )
  buf.write_string("Supported Mailboxes:\n")
  buf.write_string(
    "  AoE ....................... " +
    bool_true_false(header.supports_aoe()) +
    "\n",
  )
  buf.write_string(
    "  CoE ....................... " +
    bool_true_false(header.supports_coe()) +
    "\n",
  )
  buf.write_string(
    "  EoE ....................... " +
    bool_true_false(header.supports_eoe()) +
    "\n",
  )
  buf.write_string(
    "  FoE ....................... " +
    bool_true_false(header.supports_foe()) +
    "\n",
  )
  buf.write_string(
    "  SoE ....................... " +
    bool_true_false(header.supports_soe()) +
    "\n",
  )
  buf.write_string(
    "  VoE ....................... " +
    bool_true_false(header.supports_voe()) +
    "\n\n",
  )
  buf.write_string("Vendor Info:\n")
  buf.write_string(
    "  Firmware Version: ......... " +
    format_hex(header.firmware_version, 4) +
    "\n",
  )
  buf.write_string(
    "  Hardware Version: ......... " +
    format_hex(header.hardware_version, 4) +
    "\n",
  )
  buf.write_string(
    "  Production Date Raw: ...... " +
    format_hex(header.production_date_raw, 4) +
    "\n",
  )
  buf.write_string(
    "  Production Year: .......... " +
    header.production_year().to_string() +
    "\n",
  )
  buf.write_string(
    "  Production Weekday: ....... " +
    production_weekday_name(header.production_weekday()) +
    "\n",
  )
  buf.write_string(
    "  Production Week: .......... " +
    header.production_week().to_string() +
    "\n\n",
  )
  buf.write_string("ESC Configuration Area B:\n")
  buf.write_string(
    "  Present: .................. " +
    bool_yes_no(header.esc_config_b_present) +
    "\n",
  )
  buf.write_string(
    "  PDI1 Control: ............. " +
    format_hex(header.pdi_control_1.to_uint(), 2) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B0: ............ " +
    format_hex(header.esc_config_b0.to_uint(), 2) +
    "\n",
  )
  buf.write_string(
    "  PDI1 Configuration: ....... " + format_hex(header.pdi_config_1, 4) + "\n",
  )
  buf.write_string(
    "  Extended PDI1 Config: ..... " +
    format_hex(header.pdi_config_1_ext, 4) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B4: ............ " +
    format_hex(header.esc_config_b4, 4) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B5: ............ " +
    format_hex(header.esc_config_b5, 4) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B6: ............ " +
    format_hex(header.esc_config_b6, 4) +
    "\n",
  )
  buf.write_string(
    "  Checksum B: ............... " + format_hex(header.checksum_b, 4) + "\n\n",
  )
  buf.write_string(
    "EEPROM size: ................ " +
    standard.eeprom_size_bytes().to_string() +
    " bytes\n",
  )
  buf.write_string(
    "Version: .................... " + standard.version.to_string() + "\n\n",
  )
  let fmmu = sii.fmmu
  let fmmu_ex = sii.fmmu_ex
  let sync_managers = sii.sync_managers
  let sync_units = sii.sync_units
  let mut dc_index = 0
  for entry in categories {
    match entry.category {
      Strings => append_sii_strings_section(buf, entry, strings)
      DataTypes => append_sii_raw_category_section(buf, entry)
      General =>
        match general {
          Some(info) => append_sii_general_section(buf, entry, info, strings)
          None => ()
        }
      Fmmu => append_sii_fmmu_section(buf, entry, fmmu)
      FmmuEx => append_sii_fmmu_ex_section(buf, entry, fmmu_ex)
      SyncManager => append_sii_sm_section(buf, entry, sync_managers)
      SyncUnit => append_sii_sync_unit_section(buf, entry, sync_units)
      TxPdo =>
        append_sii_pdo_section(
          buf,
          entry,
          @mailbox.parse_sii_pdo(entry.data),
          strings,
        )
      RxPdo =>
        append_sii_pdo_section(
          buf,
          entry,
          @mailbox.parse_sii_pdo(entry.data),
          strings,
        )
      Dc =>
        if dc_index < sii.dc_clocks.length() {
          append_sii_dc_section(buf, entry, sii.dc_clocks[dc_index], strings)
          dc_index = dc_index + 1
        }
      Timeouts =>
        match sii.timeouts {
          Some(timeouts) => append_sii_timeouts_section(buf, entry, timeouts)
          None => ()
        }
      Dictionary => append_sii_raw_category_section(buf, entry)
      Hardware => append_sii_raw_category_section(buf, entry)
      VendorInformation => append_sii_raw_category_section(buf, entry)
      Images => append_sii_raw_category_section(buf, entry)
      Raw => append_sii_raw_category_section(buf, entry)
    }
  }
  buf.to_string()
}

///|
fn expected_from_scan(scan : @runtime.ScanReport) -> Array[@hal.SlaveConfig] {
  scan.slaves.map(fn(s) {
    {
      position: s.position.reinterpret_as_uint(),
      expected_identity: Some({
        vendor_id: s.vendor_id,
        product_code: s.product_code,
        revision: s.revision,
        serial: s.serial,
      }),
      expected_identification: Some(s.identification),
      expected_alias_address: s.alias_address,
      configured_address: s.station_address,
      presence: @hal.Mandatory,
    }
  })
}

///|
fn scan_report_json(report : @runtime.ScanReport) -> Json {
  let items = report.slaves.map(fn(s) {
    Json::object({
      "position": Json::number(s.position.to_double()),
      "station_address": Json::number(s.station_address.to_double()),
      "alias_address": option_uint_json(s.alias_address),
      "vendor_id": Json::number(s.vendor_id.to_double()),
      "product_code": Json::number(s.product_code.to_double()),
      "revision": Json::number(s.revision.to_double()),
      "serial": Json::number(s.serial.to_double()),
      "identification": Json::number(s.identification.to_double()),
    })
  })
  Json::object({
    "slave_count": Json::number(report.slave_count.to_double()),
    "slaves": Json::array(items),
  })
}

///|
fn option_uint_json(value : UInt?) -> Json {
  match value {
    Some(number) => Json::number(number.to_double())
    None => Json::null()
  }
}

///|
fn identity_json(identity : @hal.SlaveIdentity) -> Json {
  Json::object({
    "vendor_id": Json::number(identity.vendor_id.to_double()),
    "product_code": Json::number(identity.product_code.to_double()),
    "revision": Json::number(identity.revision.to_double()),
    "serial": Json::number(identity.serial.to_double()),
  })
}

///|
fn option_identity_json(value : @hal.SlaveIdentity?) -> Json {
  match value {
    Some(identity) => identity_json(identity)
    None => Json::null()
  }
}

///|
fn mailbox_protocols_json(
  protocols : @runtime.ConfigurationMailboxProtocols,
) -> Json {
  Json::object({
    "aoe": Json::boolean(protocols.aoe),
    "coe": Json::boolean(protocols.coe),
    "eoe": Json::boolean(protocols.eoe),
    "foe": Json::boolean(protocols.foe),
    "soe": Json::boolean(protocols.soe),
    "voe": Json::boolean(protocols.voe),
  })
}

///|
fn process_data_summary_json(
  summary : @runtime.ConfigurationProcessDataSummary,
) -> Json {
  Json::object({
    "sync_manager_count": Json::number(summary.sync_manager_count.to_double()),
    "fmmu_count": Json::number(summary.fmmu_count.to_double()),
    "rx_pdo_count": Json::number(summary.rx_pdo_count.to_double()),
    "tx_pdo_count": Json::number(summary.tx_pdo_count.to_double()),
    "mailbox_protocols": match summary.mailbox_protocols {
      Some(protocols) => mailbox_protocols_json(protocols)
      None => Json::null()
    },
    "dc_op_mode_count": Json::number(summary.dc_op_mode_count.to_double()),
    "dc_assign_activate_count": Json::number(
      summary.dc_assign_activate_count.to_double(),
    ),
  })
}

///|
fn configuration_difference_json(
  diff : @runtime.ConfigurationDifference,
) -> Json {
  match diff {
    @runtime.Missing(position~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("missing"),
        "position": Json::number(position.to_double()),
      })
    @runtime.OptionalMissing(position~, group_id~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("optional-missing"),
        "position": Json::number(position.to_double()),
        "group_id": option_uint_json(group_id),
      })
    @runtime.Extra(position~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("extra"),
        "position": Json::number(position.to_double()),
      })
    @runtime.StationAddressMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("station-address-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_uint_json(expected),
        "actual": option_uint_json(actual),
      })
    @runtime.AliasAddressMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("alias-address-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_uint_json(expected),
        "actual": option_uint_json(actual),
      })
    @runtime.IdentityMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("identity-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_identity_json(expected),
        "actual": option_identity_json(actual),
      })
    @runtime.IdentificationMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("identification-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_uint_json(expected),
        "actual": option_uint_json(actual),
      })
    @runtime.ProcessDataSummaryMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("process-data-summary-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": process_data_summary_json(expected),
        "actual": process_data_summary_json(actual),
      })
  }
}

///|
fn validate_report_json(report : @runtime.ValidateReport) -> Json {
  Json::object({
    "expected_source": Json::string(report.expected_source.to_string()),
    "actual_source": Json::string(report.actual_source.to_string()),
    "total_expected": Json::number(report.total_expected.to_double()),
    "total_found": Json::number(report.total_found.to_double()),
    "all_ok": Json::boolean(report.all_ok),
    "grade": Json::string(report.grade.to_string()),
    "result_count": Json::number(report.results.length().to_double()),
    "difference_count": Json::number(report.differences.length().to_double()),
    "differences": Json::array(
      report.differences.map(fn(diff) { configuration_difference_json(diff) }),
    ),
  })
}

///|
fn validate_output_json(
  scan : @runtime.ScanReport,
  report : @runtime.ValidateReport,
) -> Json {
  Json::object({
    "expected_source": Json::string(report.expected_source.to_string()),
    "actual_source": Json::string(report.actual_source.to_string()),
    "total_expected": Json::number(report.total_expected.to_double()),
    "total_found": Json::number(report.total_found.to_double()),
    "all_ok": Json::boolean(report.all_ok),
    "grade": Json::string(report.grade.to_string()),
    "result_count": Json::number(report.results.length().to_double()),
    "difference_count": Json::number(report.differences.length().to_double()),
    "differences": Json::array(
      report.differences.map(fn(diff) { configuration_difference_json(diff) }),
    ),
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_validate(scan, report),
    ),
  })
}

///|
fn run_report_json(report : @runtime.RunReport) -> Json {
  let tel = report.telemetry
  Json::object({
    "scan": scan_report_json(report.scan),
    "validation": validate_report_json(report.validation),
    "cycles_requested": Json::number(report.cycles_requested.to_double()),
    "cycles_ok": Json::number(report.cycles_ok.to_double()),
    "until_fault": Json::boolean(report.until_fault),
    "cycle_period_ns": Json::number(report.cycle_period_ns.to_double()),
    "output_period_ns": match report.output_period_ns {
      Some(output_period_ns) => Json::number(output_period_ns.to_double())
      None => Json::null()
    },
    "final_phase": Json::string(report.final_phase.to_string()),
    "fault": match report.fault {
      Some(fault) => run_fault_json(fault)
      None => Json::null()
    },
    "telemetry": Json::object({
      "cycles": Json::number(tel.cycles.to_double()),
      "tx_frames": Json::number(tel.tx_frames.to_double()),
      "rx_frames": Json::number(tel.rx_frames.to_double()),
      "timeouts": Json::number(tel.timeouts.to_double()),
      "retries": Json::number(tel.retries.to_double()),
      "wkc_errors": Json::number(tel.wkc_errors.to_double()),
      "irq_events": Json::number(tel.irq_events.to_double()),
      "dc_delay_updates": Json::number(tel.dc_delay_updates.to_double()),
    }),
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_run(report),
    ),
  })
}

///|
fn run_report_ndjson(report : @runtime.RunReport) -> Json {
  Json::object({
    "kind": Json::string("run-summary"),
    "summary": run_report_json(report),
  })
}

///|
fn run_progress_json(progress : @runtime.RunProgress) -> Json {
  Json::object({
    "kind": Json::string("run-progress"),
    "cycles_completed": Json::number(progress.cycles_completed.to_double()),
    "cycles_ok": Json::number(progress.cycles_ok.to_double()),
    "cycles_requested": match progress.cycles_requested {
      Some(cycles_requested) => Json::number(cycles_requested.to_double())
      None => Json::null()
    },
    "until_fault": Json::boolean(progress.until_fault),
    "cycle_period_ns": Json::number(progress.cycle_period_ns.to_double()),
    "output_period_ns": Json::number(progress.output_period_ns.to_double()),
    "telemetry": Json::object({
      "cycles": Json::number(progress.telemetry.cycles.to_double()),
      "tx_frames": Json::number(progress.telemetry.tx_frames.to_double()),
      "rx_frames": Json::number(progress.telemetry.rx_frames.to_double()),
      "timeouts": Json::number(progress.telemetry.timeouts.to_double()),
      "retries": Json::number(progress.telemetry.retries.to_double()),
      "wkc_errors": Json::number(progress.telemetry.wkc_errors.to_double()),
      "irq_events": Json::number(progress.telemetry.irq_events.to_double()),
      "dc_delay_updates": Json::number(
        progress.telemetry.dc_delay_updates.to_double(),
      ),
    }),
    "consecutive_timeouts": Json::number(
      progress.consecutive_timeouts.to_double(),
    ),
  })
}

///|
fn run_progress_text(progress : @runtime.RunProgress) -> String {
  "run progress: cycles=" +
  progress.cycles_completed.to_string() +
  " ok=" +
  progress.cycles_ok.to_string() +
  " timeouts=" +
  progress.telemetry.timeouts.to_string() +
  " consecutive_timeouts=" +
  progress.consecutive_timeouts.to_string() +
  " wkc_errors=" +
  progress.telemetry.wkc_errors.to_string()
}

///|
struct CliTextRunProgressSink {
  _unused : Unit
}

///|
fn CliTextRunProgressSink::new() -> CliTextRunProgressSink {
  { _unused: () }
}

///|
pub impl @runtime.RunProgressSink for CliTextRunProgressSink with emit(
  self,
  progress,
) {
  ignore(self)
  println(run_progress_text(progress))
}

///|
struct CliNdjsonRunProgressSink {
  _unused : Unit
}

///|
fn CliNdjsonRunProgressSink::new() -> CliNdjsonRunProgressSink {
  { _unused: () }
}

///|
pub impl @runtime.RunProgressSink for CliNdjsonRunProgressSink with emit(
  self,
  progress,
) {
  ignore(self)
  println(run_progress_json(progress).stringify())
}

///|
fn run_fault_json(fault : @runtime.RunFault) -> Json {
  match fault {
    StartupTransitionFailed(
      station~,
      target~,
      current~,
      error_indication~,
      status_code~
    ) =>
      Json::object({
        "kind": Json::string("startup-transition-failed"),
        "station": Json::number(station.to_double()),
        "target": Json::string(target.to_string()),
        "current": match current {
          Some(state) => Json::string(state.to_string())
          None => Json::null()
        },
        "al_error_flag": match error_indication {
          Some(flag) => Json::boolean(flag)
          None => Json::null()
        },
        "status_code": match status_code {
          Some(code) => Json::number(code.to_double())
          None => Json::null()
        },
      })
    TimeoutRecoveryRequired(observed_timeouts~, consecutive_timeouts~) =>
      Json::object({
        "kind": Json::string("timeout-recovery-required"),
        "observed_timeouts": Json::number(observed_timeouts.to_double()),
        "consecutive_timeouts": Json::number(consecutive_timeouts.to_double()),
      })
    RuntimeRecoveryRequired(expected_wkc~, observed_wkc_errors~) =>
      Json::object({
        "kind": Json::string("runtime-recovery-required"),
        "expected_wkc": Json::number(expected_wkc.to_double()),
        "observed_wkc_errors": Json::number(observed_wkc_errors.to_double()),
      })
    DcDrift(delta_ns~) =>
      Json::object({
        "kind": Json::string("dc-drift"),
        "delta_ns": Json::number(delta_ns.to_double()),
      })
  }
}

///|
fn state_transition_report_json(report : StateTransitionReport) -> Json {
  Json::object({
    "mode": Json::string(report.mode),
    "target_state": Json::string(report.target.to_string()),
    "station": match report.station {
      Some(station) => Json::number(station.to_double())
      None => Json::null()
    },
    "current_state": match report.current {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "final_state": match report.final_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_error_flag": match report.al_error_flag {
      Some(flag) => Json::boolean(flag)
      None => Json::null()
    },
    "status_code": match report.status_code {
      Some(code) => Json::number(code.to_double())
      None => Json::null()
    },
    "wkc": match report.wkc {
      Some(wkc) => Json::number(wkc.to_double())
      None => Json::null()
    },
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_state_transition(
        report.station,
        report.target,
        report.current,
        report.final_state,
        report.al_error_flag,
        report.status_code,
        report.wkc,
      ),
    ),
  })
}

///|
fn state_surface_summary_json(summary : @runtime.StateSurfaceSummary) -> Json {
  Json::object({
    "target_state": match summary.target_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "current_state": match summary.current_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "final_state": match summary.final_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_state": match summary.al_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_error_flag": match summary.al_error_flag {
      Some(flag) => Json::boolean(flag)
      None => Json::null()
    },
    "al_status_code": match summary.al_status_code {
      Some(code) => Json::number(code.to_double())
      None => Json::null()
    },
    "wkc": match summary.wkc {
      Some(wkc) => Json::number(wkc.to_double())
      None => Json::null()
    },
  })
}

///|
fn configuration_surface_summary_json(
  summary : @runtime.ConfigurationSurfaceSummary,
) -> Json {
  Json::object({
    "slave_count": Json::number(summary.slave_count.to_double()),
    "station_addresses": Json::array(
      summary.station_addresses.map(fn(station) {
        Json::number(station.to_double())
      }),
    ),
    "expected_source": match summary.expected_source {
      Some(source) => Json::string(source.to_string())
      None => Json::null()
    },
    "actual_source": match summary.actual_source {
      Some(source) => Json::string(source.to_string())
      None => Json::null()
    },
    "validation_grade": match summary.validation_grade {
      Some(grade) => Json::string(grade.to_string())
      None => Json::null()
    },
    "difference_count": Json::number(summary.difference_count.to_double()),
  })
}

///|
fn runtime_metrics_summary_json(
  summary : @runtime.RuntimeMetricsSummary,
) -> Json {
  Json::object({
    "cycles": Json::number(summary.cycles.to_double()),
    "tx_frames": Json::number(summary.tx_frames.to_double()),
    "rx_frames": Json::number(summary.rx_frames.to_double()),
    "timeouts": Json::number(summary.timeouts.to_double()),
    "retries": Json::number(summary.retries.to_double()),
    "wkc_errors": Json::number(summary.wkc_errors.to_double()),
    "irq_events": Json::number(summary.irq_events.to_double()),
    "dc_delay_updates": Json::number(summary.dc_delay_updates.to_double()),
  })
}

///|
fn diagnostic_issue_json(issue : @runtime.DiagnosticIssue) -> Json {
  Json::object({
    "source": Json::string(issue.source.to_string()),
    "category": Json::string(issue.category.to_string()),
    "level": Json::string(issue.level.to_string()),
    "detail": Json::string(issue.detail),
  })
}

///|
fn diagnostic_surface_json(surface : @runtime.DiagnosticSurface) -> Json {
  Json::object({
    "station": match surface.station_address {
      Some(station) => Json::number(station.to_double())
      None => Json::null()
    },
    "overall_level": Json::string(surface.overall_level.to_string()),
    "state": state_surface_summary_json(surface.state_summary),
    "configuration": match surface.configuration_summary {
      Some(summary) => configuration_surface_summary_json(summary)
      None => Json::null()
    },
    "error_register": match surface.error_register {
      Some(value) => Json::number(value.to_uint().to_double())
      None => Json::null()
    },
    "diagnosis_counter": match surface.diagnosis_counter {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
    "runtime_metrics": match surface.runtime_metrics {
      Some(summary) => runtime_metrics_summary_json(summary)
      None => Json::null()
    },
    "issues": Json::array(
      surface.issues.map(fn(issue) { diagnostic_issue_json(issue) }),
    ),
  })
}

///|
fn state_transition_report_text(report : StateTransitionReport) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("EtherCAT State Transition\n")
  buf.write_string("=========================\n")
  buf.write_string("Mode: " + report.mode + "\n")
  buf.write_string("Target: " + report.target.to_string() + "\n")
  match report.station {
    Some(station) =>
      buf.write_string("Station: " + format_hex(station, 4) + "\n")
    None => ()
  }
  match report.current {
    Some(state) => buf.write_string("Current: " + state.to_string() + "\n")
    None => ()
  }
  match report.final_state {
    Some(state) => buf.write_string("Final: " + state.to_string() + "\n")
    None => ()
  }
  match report.al_error_flag {
    Some(true) => buf.write_string("AL Error Flag: set\n")
    Some(false) => buf.write_string("AL Error Flag: clear\n")
    None => ()
  }
  match report.status_code {
    Some(code) =>
      buf.write_string("AL Status Code: " + format_hex(code, 4) + "\n")
    None => ()
  }
  match report.wkc {
    Some(wkc) => buf.write_string("WKC: " + wkc.to_string() + "\n")
    None => ()
  }
  buf.to_string()
}
