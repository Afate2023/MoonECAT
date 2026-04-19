///|
/// Command dispatch helpers for the CLI entrypoint.

///|
fn try_handle_local_cli_command(
  command : String,
  args : Array[String],
  backend : CliBackend,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
  if command == "list-if" {
    print_interfaces(backend, as_json)
    return true
  }

  if command == "esi-sii" {
    run_esi_sii_command(args, as_json)
    return true
  }

  try_handle_analysis_cli_command(command, args, as_json, timeout)
}

///|
fn try_handle_analysis_cli_command(
  command : String,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
  if command == "replay" {
    let trace_path = match flag_value(args, "--trace") {
      Some(path) => path
      None =>
        raise @hal.EcError::ConfigMismatch("replay requires --trace <path>")
    }
    let ndjson_text = load_trace_file(trace_path)
    run_replay_command(ndjson_text, args, as_json, timeout)
    return true
  }

  if command == "scenario" {
    let scenario_name = match flag_value(args, "--scenario") {
      Some(name) => name
      None =>
        raise @hal.EcError::ConfigMismatch(
          "scenario requires --scenario <name>",
        )
    }
    let cycles = resolve_scenario_cycles(args)
    run_scenario_command(scenario_name, cycles, as_json, timeout)
    return true
  }

  if command == "jitter-profile" {
    let trace_path = match flag_value(args, "--trace") {
      Some(path) => path
      None =>
        raise @hal.EcError::ConfigMismatch(
          "jitter-profile requires --trace <path>",
        )
    }
    let period_ns = require_int_flag(args, "--period-ns", 1000000)
    let ndjson_text = load_trace_file(trace_path)
    run_jitter_profile_command(ndjson_text, period_ns.to_int64(), as_json)
    return true
  }

  if command == "auto-tune" {
    let strategy = resolve_tuning_strategy(args)
    run_auto_tune_command(strategy, as_json, timeout)
    return true
  }

  if command == "topo-health" {
    let trace_path = match flag_value(args, "--trace") {
      Some(path) => path
      None =>
        raise @hal.EcError::ConfigMismatch(
          "topo-health requires --trace <path>",
        )
    }
    let ndjson_text = load_trace_file(trace_path)
    run_topo_health_command(ndjson_text, as_json, timeout)
    return true
  }

  if command == "cycle-perf" {
    let trace_path = match flag_value(args, "--trace") {
      Some(path) => path
      None =>
        raise @hal.EcError::ConfigMismatch("cycle-perf requires --trace <path>")
    }
    let period_ns = require_int_flag(args, "--period-ns", 1000000)
    let ndjson_text = load_trace_file(trace_path)
    run_cycle_perf_command(ndjson_text, period_ns.to_int64(), as_json)
    return true
  }

  if command == "comm-quality" {
    let trace_path = match flag_value(args, "--trace") {
      Some(path) => path
      None =>
        raise @hal.EcError::ConfigMismatch(
          "comm-quality requires --trace <path>",
        )
    }
    let ndjson_text = load_trace_file(trace_path)
    run_comm_quality_command(ndjson_text, as_json, timeout)
    return true
  }

  false
}

///|
fn open_native_cli_nic(
  command : String,
  args : Array[String],
  backend : CliBackend,
  timeout : @hal.Duration,
) -> @native.NativeNic raise @hal.EcError {
  match backend {
    Mock =>
      raise @hal.EcError::NotSupported(command + " requires a native backend")
    _ =>
      @native.NativeNic::open_with_config(
        resolve_native_cli_config(args, backend, timeout),
      )
  }
}

///|
fn try_handle_native_cli_command(
  command : String,
  args : Array[String],
  backend : CliBackend,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
  if command == "read-sii" {
    let nic = open_native_cli_nic(command, args, backend, timeout)
    run_read_sii_command(nic, args, as_json, timeout)
    return true
  }

  if command == "diagnosis" {
    let nic = open_native_cli_nic(command, args, backend, timeout)
    run_diagnosis_command(nic, args, as_json, timeout)
    return true
  }

  if command == "od" {
    let nic = open_native_cli_nic(command, args, backend, timeout)
    run_od_command(nic, args, as_json, timeout)
    return true
  }

  if command == "esc-regs" {
    let nic = open_native_cli_nic(command, args, backend, timeout)
    run_esc_register_command(nic, args, as_json, timeout)
    return true
  }

  if command == "expected-regs" {
    let nic = open_native_cli_nic(command, args, backend, timeout)
    run_expected_register_command(nic, args, as_json, timeout)
    return true
  }

  if command == "startup-diff" {
    let nic = open_native_cli_nic(command, args, backend, timeout)
    run_startup_diff_command(nic, args, as_json, timeout)
    return true
  }

  if command == "mailbox-readback" {
    let nic = open_native_cli_nic(command, args, backend, timeout)
    run_mailbox_readback_command(nic, args, as_json, timeout)
    return true
  }

  if command == "startup-trace" {
    let nic = open_native_cli_nic(command, args, backend, timeout)
    run_startup_trace_command(nic, args, as_json, timeout)
    return true
  }

  if command == "state" {
    let nic = open_native_cli_nic(command, args, backend, timeout)
    run_state_command(nic, args, as_json, timeout)
    return true
  }

  false
}

///|
fn try_handle_run_cli_command(
  command : String,
  args : Array[String],
  backend : CliBackend,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
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
          args,
          as_json,
          startup_state,
          shutdown_state,
          settings,
          progress_output,
          timeout,
        )
    }
    return true
  }

  if command == "run-zc" {
    let cycles = require_int_flag(args, "--cycles", 100)
    let pool_capacity = require_int_flag(args, "--pool-capacity", 16)
    match backend {
      Mock => run_zc_mock_command(cycles, pool_capacity, as_json, timeout)
      _ =>
        run_zc_native_command(
          resolve_native_cli_config(args, backend, timeout),
          args,
          cycles,
          pool_capacity,
          as_json,
          timeout,
        )
    }
    return true
  }

  if command == "run-virtual" {
    let esi_json_path = require_cli_file_flag(args, "--esi-json", "ESI JSON")
    let json_content = load_esi_json_text(esi_json_path)
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
    run_virtual_command(
      json_content, as_json, startup_state, shutdown_state, settings, progress_output,
      timeout,
    )
    return true
  }

  false
}

///|
fn run_default_cli_command(
  command : String,
  args : Array[String],
  backend : CliBackend,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
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
