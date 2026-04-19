///|
enum CliBackend {
  Mock
  NativeAuto
  NativeWindowsNpcap
  NativeLinuxRaw
} derive(Eq, Debug)

///|
enum RunProgressOutput {
  Silent
  Text
  Ndjson
} derive(Eq, Debug)

///|
let pdo_logical_base : UInt = 0x1000U

///|
let process_data_eeprom_word_count : Int = 128

///|
/// MoonECAT CLI entry point.
/// Commands: list-if, scan, validate, run, run-zc, run-virtual, read-sii, esi-sii, state, diagnosis, od, master-od, esc-regs, expected-regs, startup-diff, mailbox-readback, startup-trace, replay, scenario, jitter-profile, auto-tune, topo-health, cycle-perf, comm-quality.
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

  if try_handle_local_cli_command(command, args, backend, as_json, timeout) {
    return
  }

  if try_handle_native_cli_command(command, args, backend, as_json, timeout) {
    return
  }

  if try_handle_run_cli_command(command, args, backend, as_json, timeout) {
    return
  }

  run_default_cli_command(command, args, backend, as_json, timeout)
}

///|
