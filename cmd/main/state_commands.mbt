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
    nic, args, target, station, use_path, timeout,
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
fn[N : @hal.Nic] run_startup_diff_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let station = require_station_flag(args)
  let report = build_startup_diff_report(nic, args, station, timeout)
  nic.close()
  if as_json {
    println(startup_diff_report_json(report).stringify(indent=2))
  } else {
    println(startup_diff_report_text(report))
  }
}

///|
fn[N : @hal.Nic] run_mailbox_readback_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let station = require_station_flag(args)
  let report = build_mailbox_readback_report(nic, args, station, timeout)
  nic.close()
  if as_json {
    println(mailbox_readback_report_json(report).stringify(indent=2))
  } else {
    println(mailbox_readback_report_text(report))
  }
}

///|
fn[N : @hal.Nic] run_startup_trace_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let station = require_station_flag(args)
  let report = build_startup_trace_report(nic, args, station, timeout)
  nic.close()
  if as_json {
    println(startup_trace_report_json(report).stringify(indent=2))
  } else {
    println(startup_trace_report_text(report))
  }
}
