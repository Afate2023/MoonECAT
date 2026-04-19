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
fn require_station_flag(args : Array[String]) -> UInt raise @hal.EcError {
  match optional_uint_flag(args, "--station") {
    Some(station) => station
    None =>
      raise @hal.EcError::ConfigMismatch("esc-regs requires explicit --station")
  }
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
  if progress_ndjson && !as_json {
    raise @hal.EcError::ConfigMismatch("--progress-ndjson requires --json")
  }
  if as_json && !progress_ndjson {
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
