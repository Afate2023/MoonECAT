///|
enum CliBackend {
  Mock
  NativeAuto
  NativeWindowsNpcap
  NativeLinuxRaw
}

///|
/// MoonECAT CLI entry point.
/// Commands: scan, validate, run.
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
  let timeout = @hal.Duration(1_000_000L)
  let backend = parse_backend(args)

  match backend {
    Mock =>
      run_command_with_nic(command, @mock.MockNic::new(), as_json, timeout)
    NativeAuto => {
      let interface_name = require_interface_name(args)
      let nic = @native.NativeNic::open_with_config(
        @native.default_native_config(interface_name),
      )
      run_command_with_nic(command, nic, as_json, timeout)
    }
    NativeWindowsNpcap => {
      let interface_name = require_interface_name(args)
      let nic = @native.NativeNic::open_with_config(
        @native.default_windows_npcap_config(interface_name),
      )
      run_command_with_nic(command, nic, as_json, timeout)
    }
    NativeLinuxRaw => {
      let interface_name = require_interface_name(args)
      let nic = @native.NativeNic::open_with_config(
        @native.default_linux_config(interface_name),
      )
      run_command_with_nic(command, nic, as_json, timeout)
    }
  }
}

///|
fn[N : @hal.Nic] run_command_with_nic(
  command : String,
  nic : N,
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
      let expected = expected_from_scan(report)
      let validate_report = @runtime.validate(report, expected)
      if as_json {
        println(validate_report_json(validate_report).stringify(indent=2))
      } else {
        println(validate_report.format())
      }
    }
    "run" => {
      let scan_report = @runtime.scan(nic, timeout)
      let expected = expected_from_scan(scan_report)
      let pdo_ctx = @protocol.PdoContext::build([], 0U)
      let run_report = @runtime.run(
        nic,
        @hal.MasterConfig::default(),
        expected,
        pdo_ctx,
        0U,
        10,
        timeout,
      )
      nic.close()
      if as_json {
        println(run_report_json(run_report).stringify(indent=2))
      } else {
        println(run_report.format())
      }
    }
    _ => print_usage()
  }
}

///|
fn print_usage() -> Unit {
  println("moonecat v" + @lib.version)
  println(
    "Usage: moonecat <scan|validate|run> [--json] [--backend <mock|native|native-windows-npcap|native-linux-raw>] [--if <interface>]",
  )
  println("Default backend: mock")
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
fn flag_value(args : Array[String], flag : String) -> String? {
  for i = 0; i < args.length() - 1; i = i + 1 {
    if args[i] == flag {
      return Some(args[i + 1])
    }
  }
  None
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
      configured_address: s.station_address,
    }
  })
}

///|
fn scan_report_json(report : @runtime.ScanReport) -> Json {
  let items = report.slaves.map(fn(s) {
    Json::object({
      "position": Json::number(s.position.to_double()),
      "station_address": Json::number(s.station_address.to_double()),
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
fn validate_report_json(report : @runtime.ValidateReport) -> Json {
  Json::object({
    "total_expected": Json::number(report.total_expected.to_double()),
    "total_found": Json::number(report.total_found.to_double()),
    "all_ok": Json::boolean(report.all_ok),
    "result_count": Json::number(report.results.length().to_double()),
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
    "final_phase": Json::string(report.final_phase.to_string()),
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
  })
}
