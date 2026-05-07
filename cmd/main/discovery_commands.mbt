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
    "master-od" => {
      let scan_report : @runtime.ScanReport? = Some(@runtime.scan(nic, timeout)) catch {
        _ => None
      }
      nic.close()
      let identity = @runtime.default_master_identity()
      let od = @runtime.build_master_od(identity, scan_report, None, None)
      if as_json {
        println(od.to_json().stringify(indent=2))
      } else {
        println(od.format_text())
      }
    }
    _ => print_usage()
  }
}

///|
fn print_usage() -> Unit {
  println("moonecat v" + @lib.version)
  println(
    "Usage: moonecat <list-if|scan|validate|run|run-zc|run-virtual|read-sii|esi-sii|state|diagnosis|od|master-od|esc-regs|expected-regs|startup-diff|mailbox-readback|startup-trace|replay|scenario|jitter-profile|auto-tune|topo-health|cycle-perf|comm-quality> [--json] [--progress-ndjson] [--backend <mock|native|native-windows-npcap|native-linux-raw>] [--if <interface>] [--timeout-ms <n>] [--cycles <n>] [--until-fault] [--cycle-period-us <n>] [--output-period-ms <n>] [--max-consecutive-timeouts <n>] [--position <n>] [--words <n>] [--state <init|preop|safeop|op|boot>] [--startup-state <init|preop|safeop|op|boot>] [--shutdown-state <init|preop|safeop|op|boot|none>] [--station <configured-address>] [--index <n>] [--subindex <n>] [--read-value] [--list-type <n>] [--eni-json <path>] [--esi-json <path>] [--device-index <n>] [--path] [--reset-init] [--pdo-strategy <prefer-live|force-esi>] [--force-pdo-remap] [--record <path>] [--trace <path>] [--scan-json <path>] [--scenario <name>] [--period-ns <n>] [--strategy <balanced|conservative|aggressive>] [--pool-capacity <n>]",
  )
  println(
    "  moon run cmd/main state -- --backend native --if <interface> --state safeop --station 4097 --path --esi-json sample.esi.json --force-pdo-remap --json",
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
  println(
    "  moon run cmd/main startup-diff -- --backend native --if <interface> --station 4097 --esi-json sample.esi.json --device-index 0 --json",
  )
  println(
    "  moon run cmd/main mailbox-readback -- --backend native --if <interface> --station 4097 --esi-json sample.esi.json --device-index 0 --json",
  )
  println(
    "  moon run cmd/main startup-trace -- --backend native --if <interface> --station 4097 --esi-json sample.esi.json --device-index 0 --json",
  )
  println(
    "  moon run cmd/main startup-trace -- --backend native --if <interface> --station 4097 --esi-json sample.esi.json --device-index 0 --reset-init --json",
  )
  println(
    "  moon run cmd/main replay -- --trace session.ndjson --scan-json 02-scan.json --startup-state preop --shutdown-state init --cycles 200 --json",
  )
  println(
    "  moon run cmd/main scenario -- --scenario basic-timeout --cycles 200 --json",
  )
  println(
    "  moon run cmd/main jitter-profile -- --trace session.ndjson --period-ns 1000000 --json",
  )
  println("  moon run cmd/main auto-tune -- --strategy balanced --json")
  println("  moon run cmd/main topo-health -- --trace session.ndjson --json")
  println(
    "  moon run cmd/main cycle-perf -- --trace session.ndjson --period-ns 1000000 --json",
  )
  println("  moon run cmd/main comm-quality -- --trace session.ndjson --json")
  println("  moon run cmd/main run-zc -- --backend mock --cycles 1000 --json")
  println(
    "  moon run cmd/main run-zc -- --backend native --if <interface> --cycles 1000 --startup-state op --shutdown-state init --pool-capacity 32 --json",
  )
  println(
    "  moon run cmd/main run-virtual -- --esi-json sample.esi.json --cycles 100 --json",
  )
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
    nic, position, initial_word_count, timeout,
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
