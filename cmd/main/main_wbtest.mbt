///|
test "cli parse_backend supports explicit native backends" {
  assert_eq(
    parse_backend(["moonecat", "list-if", "--backend", "native-windows-npcap"]),
    NativeWindowsNpcap,
  )
  assert_eq(
    parse_backend(["moonecat", "list-if", "--backend", "native-linux-raw"]),
    NativeLinuxRaw,
  )
}

///|
test "cli parse_backend defaults to mock and native" {
  assert_eq(parse_backend(["moonecat", "scan"]), Mock)
  assert_eq(
    parse_backend(["moonecat", "scan", "--backend", "native"]),
    NativeAuto,
  )
}

///|
test "cli require_interface_name validates flag presence" {
  assert_eq(
    require_interface_name(["moonecat", "scan", "--if", "eth0"]),
    "eth0",
  )
  let result : Result[String, Error] = try? require_interface_name([
    "moonecat", "scan",
  ])
  assert_true(result is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli native config helper maps explicit backends" {
  assert_eq(
    native_config_for_backend(@native.WindowsNpcap, "npcap0").backend,
    @native.WindowsNpcap,
  )
  assert_eq(
    native_config_for_backend(@native.LinuxRawSocket, "eth0").backend,
    @native.LinuxRawSocket,
  )
  assert_eq(
    native_config_for_backend(@native.Auto, "eth0").backend,
    @native.Auto,
  )
}

///|
test "cli native auto select picks first probing candidate with slaves" {
  let listing : @native.NativeInterfaceListing = {
    backend: @native.WindowsNpcap,
    interfaces: [
      {
        name: "wifi0",
        description: "Wi-Fi",
        loopback: false,
        up: true,
        connected: true,
        wireless: true,
        index: None,
      },
      {
        name: "eth0",
        description: "EtherCAT uplink",
        loopback: false,
        up: true,
        connected: true,
        wireless: false,
        index: None,
      },
      {
        name: "eth1",
        description: "Secondary uplink",
        loopback: false,
        up: true,
        connected: true,
        wireless: false,
        index: None,
      },
    ],
  }
  let timeout = @hal.Duration(1_000_000L)
  let config = select_native_cli_config_from_listing(listing, timeout, fn(
    config,
    _timeout,
  ) {
    match config.interface_name {
      "eth0" => Ok(0)
      "eth1" => Ok(2)
      _ => Err(@hal.EcError::Internal("unexpected candidate"))
    }
  })
  assert_eq(config.backend, @native.WindowsNpcap)
  assert_eq(config.interface_name, "eth1")
}

///|
test "cli native auto select error keeps filtered and probe notes" {
  let listing : @native.NativeInterfaceListing = {
    backend: @native.LinuxRawSocket,
    interfaces: [
      {
        name: "lo",
        description: "Loopback",
        loopback: true,
        up: true,
        connected: true,
        wireless: false,
        index: Some(1),
      },
      {
        name: "eth0",
        description: "Primary",
        loopback: false,
        up: true,
        connected: true,
        wireless: false,
        index: Some(2),
      },
      {
        name: "eth1",
        description: "Secondary",
        loopback: false,
        up: true,
        connected: true,
        wireless: false,
        index: Some(3),
      },
    ],
  }
  let timeout = @hal.Duration(1_000_000L)
  let result : Result[@native.NativeNicConfig, Error] = try? select_native_cli_config_from_listing(
    listing,
    timeout,
    fn(config, _timeout) {
      match config.interface_name {
        "eth0" => Ok(0)
        "eth1" => Err(@hal.EcError::LinkDown)
        _ => Err(@hal.EcError::Internal("unexpected candidate"))
      }
    },
  )
  guard result is Err(@hal.EcError::ConfigMismatch(message)) else {
    fail("expected native auto select to fail")
  }
  assert_true(message.contains("lo(loopback)"))
  assert_true(message.contains("eth0(no-response)"))
  assert_true(message.contains("eth1(link-down)"))
}

///|
test "cli skipped interface reason is stable" {
  assert_eq(
    skipped_native_interface_reason({
      name: "loop",
      description: "",
      loopback: true,
      up: true,
      connected: true,
      wireless: false,
      index: None,
    }),
    "loopback",
  )
  assert_eq(
    skipped_native_interface_reason({
      name: "wifi",
      description: "",
      loopback: false,
      up: true,
      connected: true,
      wireless: true,
      index: None,
    }),
    "wireless",
  )
}

///|
test "cli numeric flag parsers accept valid integers" {
  assert_eq(parse_uint_flag("--position", "12"), 12U)
  assert_eq(parse_int_flag("--words", "128"), 128)
}

///|
test "cli numeric flag parsers reject invalid integers" {
  let bad_uint : Result[UInt, Error] = try? parse_uint_flag("--position", "1a")
  let bad_int : Result[Int, Error] = try? parse_int_flag("--words", "")
  assert_true(bad_uint is Err(@hal.EcError::ConfigMismatch(_)))
  assert_true(bad_int is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli timeout flag defaults to 1ms and parses milliseconds" {
  assert_eq(resolve_timeout(["moonecat", "scan"]), @hal.Duration(1_000_000L))
  assert_eq(
    resolve_timeout(["moonecat", "diagnosis", "--timeout-ms", "50"]),
    @hal.Duration(50_000_000L),
  )
}

///|
test "cli timeout flag rejects non-positive values" {
  let zero : Result[@hal.Duration, Error] = try? resolve_timeout([
    "moonecat", "diagnosis", "--timeout-ms", "0",
  ])
  assert_true(zero is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli run cycles default and parse explicit values" {
  assert_eq(resolve_run_cycles(["moonecat", "run"], false), 10)
  assert_eq(
    resolve_run_cycles(["moonecat", "run", "--cycles", "250"], false),
    250,
  )
}

///|
test "cli run cycles rejects non-positive values" {
  let zero : Result[Int, Error] = try? resolve_run_cycles(
    ["moonecat", "run", "--cycles", "0"],
    false,
  )
  assert_true(zero is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli until-fault mode rejects explicit cycles" {
  let bad : Result[Int, Error] = try? resolve_run_cycles(
    ["moonecat", "run", "--until-fault", "--cycles", "10"],
    true,
  )
  assert_true(bad is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli run loop settings parse timing and timeout controls" {
  let settings = resolve_run_loop_settings(
    [
      "moonecat", "run", "--until-fault", "--cycle-period-us", "500", "--output-period-ms",
      "20", "--max-consecutive-timeouts", "7",
    ],
    false,
    true,
    false,
  )
  assert_eq(settings.until_fault, true)
  assert_eq(settings.cycles, 0)
  assert_eq(settings.cycle_period_ns, Some(500_000L))
  assert_eq(settings.output_period_ns, Some(20_000_000L))
  assert_eq(settings.max_consecutive_timeouts, 7)
}

///|
test "cli run loop settings reject progress output with json" {
  let result : Result[@runtime.RunLoopSettings, Error] = try? resolve_run_loop_settings(
    ["moonecat", "run", "--output-period-ms", "1000"],
    true,
    false,
    false,
  )
  assert_true(result is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli run loop settings allow ndjson progress with json" {
  let settings = resolve_run_loop_settings(
    [
      "moonecat", "run", "--json", "--progress-ndjson", "--until-fault", "--output-period-ms",
      "1000",
    ],
    true,
    true,
    true,
  )
  assert_eq(settings.until_fault, true)
  assert_eq(settings.output_period_ns, Some(1_000_000_000L))
}

///|
test "cli run loop settings reject ndjson progress without output period" {
  let result : Result[@runtime.RunLoopSettings, Error] = try? resolve_run_loop_settings(
    ["moonecat", "run", "--json", "--progress-ndjson", "--until-fault"],
    true,
    true,
    true,
  )
  assert_true(result is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli resolve run progress output selects silent text and ndjson" {
  assert_eq(resolve_run_progress_output(false, false, None), Silent)
  assert_eq(resolve_run_progress_output(false, false, Some(1_000_000L)), Text)
  assert_eq(resolve_run_progress_output(true, true, Some(1_000_000L)), Ndjson)
}

///|
test "cli resolve validate expected configuration defaults to scan projection" {
  let scan_report : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let expected = resolve_validate_expected_configuration(scan_report, [
    "moonecat", "validate",
  ])
  assert_eq(expected.source, @runtime.OfflineConfig)
  assert_eq(expected.total_slaves, 1)
  assert_eq(expected.slaves[0].configured_address, Some(0x1001U))
}

///|
test "cli resolve validate expected configuration rejects XML ENI input" {
  let scan_report : @runtime.ScanReport = { slave_count: 0, slaves: [] }
  let result : Result[@runtime.ConfigurationModel, Error] = try? resolve_validate_expected_configuration(
    scan_report,
    ["moonecat", "validate", "--eni", "config.xml"],
  )
  guard result is Err(@hal.EcError::ConfigMismatch(message)) else {
    fail("expected XML ENI validation path to be rejected")
  }
  assert_true(message.contains("--eni-json"))
}

///|
test "cli esm state parser accepts canonical names" {
  assert_eq(parse_esm_state_flag("--state", "init"), @protocol.Init)
  assert_eq(parse_esm_state_flag("--state", "pre-op"), @protocol.PreOp)
  assert_eq(parse_esm_state_flag("--state", "safeop"), @protocol.SafeOp)
  assert_eq(parse_esm_state_flag("--state", "op"), @protocol.Op)
  assert_eq(parse_esm_state_flag("--state", "boot"), @protocol.Boot)
}

///|
test "cli esm state parser rejects unknown names" {
  let result : Result[@protocol.EsmState, Error] = try? parse_esm_state_flag(
    "--state", "running",
  )
  assert_true(result is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli optional esm state flag defaults and parses values" {
  assert_eq(
    optional_esm_state_flag(
      ["moonecat", "run"],
      "--startup-state",
      @protocol.Op,
    ),
    @protocol.Op,
  )
  assert_eq(
    optional_esm_state_flag(
      ["moonecat", "run", "--startup-state", "safeop"],
      "--startup-state",
      @protocol.Op,
    ),
    @protocol.SafeOp,
  )
}

///|
test "cli optional shutdown state flag supports default and none" {
  assert_eq(
    optional_shutdown_state_flag(["moonecat", "run"], "--shutdown-state"),
    Some(@protocol.Init),
  )
  assert_eq(
    optional_shutdown_state_flag(
      ["moonecat", "run", "--shutdown-state", "none"],
      "--shutdown-state",
    ),
    None,
  )
  assert_eq(
    optional_shutdown_state_flag(
      ["moonecat", "run", "--shutdown-state", "preop"],
      "--shutdown-state",
    ),
    Some(@protocol.PreOp),
  )
}

///|
test "cli preferred sii dc clock favors assign activate" {
  let selected = @runtime.preferred_sii_dc_clock([
    {
      cycle_time_0: 500_000U,
      shift_time_0: 0U,
      shift_time_1: 0U,
      sync1_cycle_factor: 0,
      assign_activate: 0U,
      sync0_cycle_factor: 0,
      name_idx: b'\x00',
      description_idx: b'\x00',
    },
    {
      cycle_time_0: 1_000_000U,
      shift_time_0: 0U,
      shift_time_1: 0U,
      sync1_cycle_factor: 0,
      assign_activate: 0x0300U,
      sync0_cycle_factor: 0,
      name_idx: b'\x01',
      description_idx: b'\x01',
    },
  ])
  guard selected is Some(clock) else { fail("expected a preferred DC clock") }
  assert_eq(clock.assign_activate, 0x0300U)
  assert_eq(clock.cycle_time_0, 1_000_000U)
}

///|
test "cli dc cycle period helper maps nonzero cycle" {
  let result = @runtime.dc_cycle_period_ns({
    cycle_time_0: 1_000_000U,
    shift_time_0: 0U,
    shift_time_1: 0U,
    sync1_cycle_factor: 0,
    assign_activate: 0x0300U,
    sync0_cycle_factor: 0,
    name_idx: b'\x00',
    description_idx: b'\x00',
  })
  assert_eq(result, Some(1_000_000L))
  let none_result = @runtime.dc_cycle_period_ns({
    cycle_time_0: 0U,
    shift_time_0: 0U,
    shift_time_1: 0U,
    sync1_cycle_factor: 0,
    assign_activate: 0U,
    sync0_cycle_factor: 0,
    name_idx: b'\x00',
    description_idx: b'\x00',
  })
  assert_eq(none_result, None)
}

///|
test "cli master config helper enables dc when cycle is present" {
  let dc_config = @runtime.master_config_with_optional_dc(Some(250_000L))
  assert_true(dc_config.dc_enabled)
  assert_eq(dc_config.cycle_period_ns, 250_000L)

  let default_config = @runtime.master_config_with_optional_dc(None)
  assert_true(not(default_config.dc_enabled))
  assert_eq(default_config.cycle_period_ns, 1_000_000L)
}

///|
test "cli optional byte flag parses values and defaults" {
  assert_eq(optional_byte_flag(["moonecat", "od"], "--subindex"), None)
  assert_eq(
    optional_byte_flag(["moonecat", "od", "--subindex", "7"], "--subindex"),
    Some(b'\x07'),
  )
}

///|
test "cli optional byte flag rejects out-of-range values" {
  let result : Result[Byte?, Error] = try? optional_byte_flag(
    ["moonecat", "od", "--subindex", "256"],
    "--subindex",
  )
  assert_true(result is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli resolve od query supports list object and entry modes" {
  let list_query = resolve_od_query(["moonecat", "od"])
  assert_eq(list_query.list_type, 0U)
  assert_eq(list_query.index, None)
  assert_eq(list_query.subindex, None)
  assert_eq(list_query.read_value, false)

  let object_query = resolve_od_query(["moonecat", "od", "--index", "7187"])
  assert_eq(object_query.index, Some(7187U))
  assert_eq(object_query.subindex, None)
  assert_eq(object_query.read_value, false)

  let entry_query = resolve_od_query([
    "moonecat", "od", "--index", "6656", "--subindex", "1",
  ])
  assert_eq(entry_query.index, Some(6656U))
  assert_eq(entry_query.subindex, Some(b'\x01'))
  assert_eq(entry_query.read_value, false)

  let value_query = resolve_od_query([
    "moonecat", "od", "--index", "7186", "--read-value",
  ])
  assert_eq(value_query.index, Some(7186U))
  assert_eq(value_query.subindex, Some(b'\x00'))
  assert_eq(value_query.read_value, true)
}

///|
test "cli resolve od query rejects orphan subindex" {
  let result : Result[OdBrowseQuery, Error] = try? resolve_od_query([
    "moonecat", "od", "--subindex", "1",
  ])
  assert_true(result is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli resolve diagnosis station uses explicit or single slave" {
  let scan_report : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let slave = resolve_cli_slave(scan_report, None)
  assert_eq(slave.station_address, 0x1001U)
}

///|
test "cli resolve diagnosis slave finds explicit station" {
  let scan_report : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 6U,
        product_code: 7U,
        revision: 8U,
        serial: 9U,
        identification: 10U,
      },
    ],
  }
  let slave = resolve_cli_slave(scan_report, Some(0x1002U))
  assert_eq(slave.position, 1)
  assert_eq(slave.station_address, 0x1002U)
}

///|
test "cli resolve diagnosis slave rejects missing explicit station" {
  let scan_report : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let result : Result[@runtime.SlaveReport, Error] = try? resolve_cli_slave(
    scan_report,
    Some(0x2000U),
  )
  assert_true(result is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli resolve diagnosis station rejects ambiguous scan" {
  let scan_report : @runtime.ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 6U,
        product_code: 7U,
        revision: 8U,
        serial: 9U,
        identification: 10U,
      },
    ],
  }
  let result : Result[@runtime.SlaveReport, Error] = try? resolve_cli_slave(
    scan_report,
    None,
  )
  assert_true(result is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli diagnosis output json includes nullable counter" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let text = diagnosis_output_json(scan, {
    station_address: 0x1001U,
    al_state: Some(@protocol.SafeOp),
    al_error_flag: Some(true),
    al_status_code: Some(0x0016U),
    error_register: b'\x0A',
    diagnosis_counter: None,
  }).stringify(indent=2)
  assert_true(text.contains("\"station\": 4097"))
  assert_true(text.contains("\"al_state\": \"SafeOp\""))
  assert_true(text.contains("\"al_error_flag\": true"))
  assert_true(text.contains("\"al_status_code\": 22"))
  assert_true(text.contains("\"error_register\": 10"))
  assert_true(text.contains("\"diagnosis_counter\": null"))
}

///|
test "cli diagnosis output json includes shared surface" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let text = diagnosis_output_json(scan, {
    station_address: 0x1001U,
    al_state: Some(@protocol.SafeOp),
    al_error_flag: Some(true),
    al_status_code: Some(0x0011U),
    error_register: b'\x04',
    diagnosis_counter: Some(2U),
  }).stringify(indent=2)
  assert_true(text.contains("\"surface\""))
  assert_true(text.contains("\"overall_level\": \"Block\""))
  assert_true(text.contains("\"source\": \"Registers\""))
}

///|
test "cli diagnosis report text includes AL snapshot fields" {
  let text = diagnosis_report_text({
    station_address: 0x1001U,
    al_state: Some(@protocol.Op),
    al_error_flag: Some(false),
    al_status_code: Some(0x0000U),
    error_register: b'\x04',
    diagnosis_counter: Some(3U),
  })
  assert_true(text.contains("AL State: Op"))
  assert_true(text.contains("AL Error Flag: clear"))
  assert_true(text.contains("AL Status Code: 0x0000"))
  assert_true(text.contains("Diagnosis Counter: 3"))
}

///|
test "cli validate report json includes grade and sources" {
  let json = validate_report_json({
    expected_source: @runtime.EniImport,
    actual_source: @runtime.OnlineScan,
    total_expected: 1,
    total_found: 2,
    results: [@runtime.Ok, @runtime.Extra(position=1)],
    differences: [@runtime.ConfigurationDifference::Extra(position=1)],
    all_ok: false,
    grade: @runtime.Warn,
  })
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"expected_source\": \"EniImport\""))
  assert_true(text.contains("\"actual_source\": \"OnlineScan\""))
  assert_true(text.contains("\"grade\": \"Warn\""))
  assert_true(text.contains("\"difference_count\": 1"))
  assert_true(text.contains("\"type\": \"extra\""))
  assert_true(text.contains("\"category\": \"Topology\""))
}

///|
test "cli validate report json includes optional missing topology detail" {
  let json = validate_report_json({
    expected_source: @runtime.OfflineConfig,
    actual_source: @runtime.OnlineScan,
    total_expected: 1,
    total_found: 0,
    results: [@runtime.OptionalMissing(position=3, group_id=Some(7U))],
    differences: [
      @runtime.ConfigurationDifference::OptionalMissing(
        position=3,
        group_id=Some(7U),
      ),
    ],
    all_ok: false,
    grade: @runtime.Warn,
  })
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"type\": \"optional-missing\""))
  assert_true(text.contains("\"group_id\": 7"))
  assert_true(text.contains("\"grade\": \"Warn\""))
}

///|
test "cli validate report json includes alias mismatch as block" {
  let json = validate_report_json({
    expected_source: @runtime.OfflineConfig,
    actual_source: @runtime.OnlineScan,
    total_expected: 1,
    total_found: 1,
    results: [
      @runtime.AliasAddressMismatch(position=0, expected=0x20U, actual=0x21U),
    ],
    differences: [
      @runtime.ConfigurationDifference::AliasAddressMismatch(
        position=0,
        expected=Some(0x20U),
        actual=Some(0x21U),
      ),
    ],
    all_ok: false,
    grade: @runtime.Block,
  })
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"type\": \"alias-address-mismatch\""))
  assert_true(text.contains("\"category\": \"Topology\""))
  assert_true(text.contains("\"grade\": \"Block\""))
}

///|
test "cli validate output json includes shared surface" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let text = validate_output_json(scan, {
    expected_source: @runtime.EniImport,
    actual_source: @runtime.OnlineScan,
    total_expected: 1,
    total_found: 2,
    results: [@runtime.Ok, @runtime.Extra(position=1)],
    differences: [@runtime.ConfigurationDifference::Extra(position=1)],
    all_ok: false,
    grade: @runtime.Warn,
  }).stringify(indent=2)
  assert_true(text.contains("\"surface\""))
  assert_true(text.contains("\"overall_level\": \"Degrade\""))
  assert_true(text.contains("\"validation_grade\": \"Warn\""))
}

///|
test "cli od report json includes list indices" {
  let json = od_report_json({
    station_address: Some(0x1001U),
    mode: "od-list",
    list_type: 0U,
    index: None,
    subindex: None,
    indices: Some([0x1000U, 0x1C13U]),
    object_description: None,
    entry_description: None,
    value_hex: None,
    value_u32: None,
    error_category: None,
    error_detail: None,
    abort_code: None,
  })
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"mode\": \"od-list\""))
  assert_true(text.contains("\"indices\""))
  assert_true(text.contains("4096"))
  assert_true(text.contains("7187"))
  assert_true(text.contains("\"error\": null"))
}

///|
test "cli od report text includes object description fields" {
  let text = od_report_text({
    station_address: Some(0x1001U),
    mode: "od-object",
    list_type: 0U,
    index: Some(0x1C13U),
    subindex: None,
    indices: None,
    object_description: Some({
      index: 0x1C13U,
      data_type: 0x0007U,
      object_code: b'\x09',
      max_subindex: b'\x03',
      name: "MapPDO",
    }),
    entry_description: None,
    value_hex: None,
    value_u32: None,
    error_category: None,
    error_detail: None,
    abort_code: None,
  })
  assert_true(text.contains("Mode: od-object"))
  assert_true(text.contains("Index: 0x1C13"))
  assert_true(text.contains("Name: MapPDO"))
  assert_true(text.contains("Object Code: 0x09"))
}

///|
test "cli od report text includes entry description fields" {
  let text = od_report_text({
    station_address: Some(0x1001U),
    mode: "od-entry",
    list_type: 0U,
    index: Some(0x1A00U),
    subindex: Some(b'\x02'),
    indices: None,
    object_description: None,
    entry_description: Some({
      index: 0x1A00U,
      subindex: b'\x02',
      value_info: b'\x3F',
      data_type: 0x0005U,
      bit_length: 16U,
      access: 0x003FU,
      name: "Entry2",
    }),
    value_hex: None,
    value_u32: None,
    error_category: None,
    error_detail: None,
    abort_code: None,
  })
  assert_true(text.contains("Mode: od-entry"))
  assert_true(text.contains("Subindex: 2"))
  assert_true(text.contains("Bit Length: 16"))
  assert_true(text.contains("Value Info: 0x3F"))
}

///|
test "cli od error category distinguishes major failure classes" {
  assert_eq(
    od_error_category(@hal.EcError::MailboxTimeout),
    "transport-failure",
  )
  assert_eq(
    od_error_category(@hal.EcError::SdoAbort(0x06020000U)),
    "protocol-failure",
  )
  assert_eq(
    od_error_category(@hal.EcError::NotSupported("od requires native")),
    "unsupported",
  )
}

///|
test "cli od failure report json includes structured error" {
  let json = od_report_json(
    od_failure_report(
      Some(0x1001U),
      {
        list_type: 0U,
        index: Some(0x2000U),
        subindex: Some(b'\x01'),
        read_value: false,
      },
      @hal.EcError::SdoAbort(0x06020000U),
    ),
  )
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"category\": \"protocol-failure\""))
  assert_true(text.contains("\"abort_code\": 100794368"))
  assert_true(text.contains("\"station\": 4097"))
}

///|
test "cli od failure text includes error summary" {
  let text = od_report_text(
    od_failure_report(
      None,
      { list_type: 0U, index: None, subindex: None, read_value: false },
      @hal.EcError::MailboxTimeout,
    ),
  )
  assert_true(text.contains("Station: unknown"))
  assert_true(text.contains("Error Category: transport-failure"))
  assert_true(text.contains("Error Detail: MailboxTimeout"))
}

///|
test "cli od report json includes uploaded value" {
  let json = od_report_json({
    station_address: Some(0x1001U),
    mode: "od-value",
    list_type: 0U,
    index: Some(0x1C12U),
    subindex: Some(b'\x01'),
    indices: None,
    object_description: None,
    entry_description: None,
    value_hex: Some("0x0016"),
    value_u32: Some(22U),
    error_category: None,
    error_detail: None,
    abort_code: None,
  })
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"mode\": \"od-value\""))
  assert_true(text.contains("\"hex\": \"0x0016\""))
  assert_true(text.contains("\"u32_le\": 22"))
}

///|
test "cli od report text includes uploaded value" {
  let text = od_report_text({
    station_address: Some(0x1001U),
    mode: "od-value",
    list_type: 0U,
    index: Some(0x1C13U),
    subindex: Some(b'\x00'),
    indices: None,
    object_description: None,
    entry_description: None,
    value_hex: Some("0x0200"),
    value_u32: Some(2U),
    error_category: None,
    error_detail: None,
    abort_code: None,
  })
  assert_true(text.contains("Mode: od-value"))
  assert_true(text.contains("Value (hex): 0x0200"))
  assert_true(text.contains("Value (u32 le): 2"))
}

///|
fn sample_esi_json_text() -> String {
  @runtime.esi_json_to_string({
    devices: [
      {
        vendor_id: 1894U,
        product_code: 2320U,
        revision: 1U,
        serial: 0U,
        physics: "YY",
        device_name: "RZN2 CoE Demo",
        type_name: "rzn2",
        slot_index_increment: 0x800U,
        slot_pdo_increment: 16U,
        mailbox: {
          data_link_layer: false,
          aoe: false,
          coe_present: true,
          coe_sdo_info: true,
          coe_pdo_assign: true,
          coe_pdo_config: true,
          coe_complete_access: true,
          eoe: false,
          foe: false,
          soe: false,
          voe: false,
        },
        fmmu: ["outputs", "inputs", "mailbox-state"],
        sync_managers: [
          {
            physical_start: 0x1000U,
            length: 256U,
            control: b'\x26',
            status: b'\x00',
            enable: true,
            sm_type: "mailbox-out",
          },
          {
            physical_start: 0x1400U,
            length: 256U,
            control: b'\x22',
            status: b'\x00',
            enable: true,
            sm_type: "mailbox-in",
          },
          {
            physical_start: 0x1800U,
            length: 28U,
            control: b'\x64',
            status: b'\x00',
            enable: true,
            sm_type: "process-data-out",
          },
          {
            physical_start: 0x1C00U,
            length: 32U,
            control: b'\x20',
            status: b'\x00',
            enable: true,
            sm_type: "process-data-in",
          },
        ],
        dc_modes: [
          {
            name: "DC",
            description: "DC-Synchron",
            assign_activate: 0x0300U,
            cycle_time_sync0: 0U,
            sync0_factor: 1,
            sync1_factor: 1,
          },
        ],
        eeprom_byte_size: 2048U,
        config_data: b"\x80\x0E\x44\xEE\x10\x00\x00\x00",
        bootstrap: b"\x00\x10\x80\x00\x80\x10\x80\x00",
        default_modules: [{ module_ident: 0x219800U, slot_index: 0 }],
        rx_pdos: [],
        tx_pdos: [],
      },
    ],
    modules: [
      {
        module_ident: 0x219800U,
        module_name: "axis",
        rx_pdos: [
          {
            direction: "rx",
            base_index: 0x1600U,
            depend_on_slot_pdo: true,
            sync_manager: b'\x02',
            name: "Outputs",
            entries: [
              {
                base_index: 0x6040U,
                depend_on_slot_index: true,
                subindex: b'\x00',
                bit_length: b'\x10',
                name: "ControlWord",
                data_type_name: "UINT",
              },
            ],
          },
        ],
        tx_pdos: [
          {
            direction: "tx",
            base_index: 0x1A00U,
            depend_on_slot_pdo: true,
            sync_manager: b'\x03',
            name: "Inputs",
            entries: [
              {
                base_index: 0x6041U,
                depend_on_slot_index: true,
                subindex: b'\x00',
                bit_length: b'\x10',
                name: "StatusWord",
                data_type_name: "UINT",
              },
            ],
          },
        ],
      },
    ],
  })
}

///|
test "cli esi-sii projection renders JSON from shared ESI JSON bridge" {
  let report = @runtime.offline_sii_report_from_esi_json(
    sample_esi_json_text(),
    0,
  )
  let text = offline_sii_json(report).stringify(indent=2)
  assert_true(text.contains("\"vendor_id\": 1894"))
  assert_true(text.contains("\"product_code\": 2320"))
  assert_true(text.contains("\"mailbox_protocols\": 4"))
  assert_true(text.contains("\"assign_activate\": 768"))
  assert_true(text.contains("ControlWord"))
  assert_true(text.contains("StatusWord"))
}

///|
test "cli esi-sii projection renders siitool-like text sections" {
  let report = @runtime.offline_sii_report_from_esi_json(
    sample_esi_json_text(),
    0,
  )
  let text = offline_sii_text(report)
  assert_true(text.contains("Print Categorie: FMMU"))
  assert_true(text.contains("Print Categorie: SyncManager"))
  assert_true(text.contains("Print Categorie: RX PDO"))
  assert_true(text.contains("Print Categorie: DC CLOCK"))
  assert_true(text.contains("ControlWord"))
}

///|
test "cli od stage preserves mailbox protocol classification" {
  let result : Result[Int, Error] = try? od_stage(
    Err(@hal.EcError::MailboxProtocol("payload too short")),
    "od.get_od_list",
  )
  guard result is Err(@hal.EcError::MailboxProtocol(message)) else {
    fail("expected mailbox protocol error")
  }
  assert_true(message.contains("od.get_od_list -> payload too short"))
}

///|
test "cli transition path falls back through init when needed" {
  let path = @protocol.build_transition_route(@protocol.Op, @protocol.Boot)
  assert_eq(path.length(), 5)
  assert_eq(path[0], @protocol.Op)
  assert_eq(path[1], @protocol.SafeOp)
  assert_eq(path[2], @protocol.PreOp)
  assert_eq(path[3], @protocol.Init)
  assert_eq(path[4], @protocol.Boot)
}

///|
test "cli state transition report uses broadcast when station is omitted" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let report = compute_state_transition_report(
    nic,
    @protocol.Init,
    None,
    false,
    timeout,
  )
  nic.close()
  assert_eq(report.mode, "broadcast")
  assert_eq(report.station, None)
  assert_eq(report.current, None)
  assert_eq(report.final_state, None)
  assert_eq(report.status_code, None)
  assert_eq(report.wkc, Some(0U))
}

///|
fn build_esm_response_frame(
  request : @protocol.EcFrame,
  data : Bytes,
  wkc : UInt,
) -> Bytes {
  let request_pdu = request.pdus[0]
  (
    {
      dst_mac: request.src_mac,
      src_mac: request.dst_mac,
      pdus: [
        {
          header: {
            command: request_pdu.header.command,
            index: request_pdu.header.index,
            address: request_pdu.header.address,
            len_flags: data.length().reinterpret_as_uint(),
            irq: request_pdu.header.irq,
          },
          data,
          wkc,
        },
      ],
    } : @protocol.EcFrame).encode()
}

///|
pub struct StrictTransitionNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut current_state : Byte
  mut error_indication : Bool
  mut status_code : UInt
  control_writes : Array[Byte]
}

///|
fn StrictTransitionNic::new(
  current_state : @protocol.EsmState,
  error_indication : Bool,
  status_code : UInt,
) -> StrictTransitionNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    current_state: current_state.to_byte(),
    error_indication,
    status_code,
    control_writes: [],
  }
}

///|
fn strict_status_bytes(nic : StrictTransitionNic) -> Bytes {
  let status = if nic.error_indication {
    nic.current_state | b'\x10'
  } else {
    nic.current_state
  }
  Bytes::from_array([status, b'\x00'])
}

///|
fn strict_status_code_bytes(status_code : UInt) -> Bytes {
  Bytes::from_array([
    (status_code & 0xFFU).reinterpret_as_int().to_byte(),
    ((status_code >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
  ])
}

///|
pub impl @hal.Nic for StrictTransitionNic with open_(name) {
  ignore(name)
  StrictTransitionNic::new(@protocol.EsmState::Init, false, 0U)
}

///|
pub impl @hal.Nic for StrictTransitionNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_al_status {
        strict_status_bytes(self)
      } else if offset == @protocol.reg_al_status_code {
        strict_status_code_bytes(self.status_code)
      } else {
        Bytes::new(pdu.data.length())
      }
      build_esm_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
        let control = pdu.data[0]
        self.control_writes.push(control)
        let requested_state = control & b'\x0F'
        let acknowledge = (control & b'\x10') != b'\x00'
        if acknowledge {
          self.error_indication = false
          self.status_code = 0U
        }
        if requested_state != self.current_state {
          let current = @protocol.EsmState::from_byte(self.current_state)
          let target = @protocol.EsmState::from_byte(requested_state)
          if current.can_transition(target) {
            self.current_state = requested_state
            self.error_indication = false
            self.status_code = 0U
          } else {
            self.error_indication = true
            self.status_code = 0x0011U
          }
        }
      }
      build_esm_response_frame(request, strict_status_bytes(self), 1U)
    }
    _ => build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for StrictTransitionNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for StrictTransitionNic with close(self) {
  self.is_open = false
}

///|
test "cli state path recovers configuration error to init" {
  let nic = StrictTransitionNic::new(@protocol.EsmState::SafeOp, true, 0x0016U)
  let timeout = @hal.Duration(1000L)
  let report = compute_station_transition_report(
    nic,
    @protocol.EsmState::Init,
    0x1001U,
    true,
    timeout,
  )
  assert_eq(report.mode, "station-path")
  assert_eq(report.current, Some(@protocol.EsmState::SafeOp))
  assert_eq(report.final_state, Some(@protocol.EsmState::Init))
  assert_eq(report.al_error_flag, Some(false))
  assert_eq(report.status_code, None)
  assert_eq(nic.control_writes.length(), 2)
  assert_eq(
    nic.control_writes[0],
    @protocol.EsmState::SafeOp.to_byte() | b'\x10',
  )
  assert_eq(nic.control_writes[1] & b'\x0F', @protocol.EsmState::Init.to_byte())
}

///|
test "cli state transition report json includes station mode fields" {
  let json = state_transition_report_json({
    mode: "station-path",
    target: @protocol.SafeOp,
    station: Some(0x1001U),
    current: Some(@protocol.PreOp),
    final_state: Some(@protocol.SafeOp),
    al_error_flag: Some(false),
    status_code: Some(0U),
    wkc: None,
  })
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"mode\": \"station-path\""))
  assert_true(text.contains("\"target_state\": \"SafeOp\""))
  assert_true(text.contains("\"station\": 4097"))
  assert_true(text.contains("\"final_state\": \"SafeOp\""))
  assert_true(text.contains("\"surface\""))
  assert_true(text.contains("\"overall_level\": \"Info\""))
}

///|
test "cli state transition report text includes broadcast mode and wkc" {
  let text = state_transition_report_text({
    mode: "broadcast",
    target: @protocol.Init,
    station: None,
    current: None,
    final_state: None,
    al_error_flag: None,
    status_code: None,
    wkc: Some(0U),
  })
  assert_true(text.contains("Mode: broadcast"))
  assert_true(text.contains("Target: Init"))
  assert_true(text.contains("WKC: 0"))
  assert_true(not(text.contains("Station:")))
}

///|
test "cli run report json includes shared surface telemetry" {
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OfflineConfig,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 10,
    cycles_ok: 10,
    until_fault: true,
    cycle_period_ns: 1_000_000L,
    output_period_ns: Some(5_000_000L),
    telemetry: {
      cycles: 10L,
      tx_frames: 10L,
      rx_frames: 10L,
      timeouts: 0L,
      retries: 0L,
      wkc_errors: 0L,
      irq_events: 0L,
      dc_delay_updates: 0L,
    },
    final_phase: @runtime.Done,
    fault: Some(
      @runtime.RuntimeRecoveryRequired(expected_wkc=1U, observed_wkc_errors=2L),
    ),
  }
  let text = run_report_json(report).stringify(indent=2)
  assert_true(text.contains("\"until_fault\": true"))
  assert_true(text.contains("\"cycle_period_ns\": 1000000"))
  assert_true(text.contains("\"output_period_ns\": 5000000"))
  assert_true(text.contains("\"fault\""))
  assert_true(text.contains("\"runtime-recovery-required\""))
  assert_true(text.contains("\"surface\""))
  assert_true(text.contains("\"runtime_metrics\""))
  assert_true(text.contains("\"overall_level\": \"Block\""))
}

///|
test "cli run report ndjson wraps summary payload" {
  let report : @runtime.RunReport = {
    scan: { slave_count: 0, slaves: [] },
    validation: {
      expected_source: @runtime.OfflineConfig,
      actual_source: @runtime.OnlineScan,
      total_expected: 0,
      total_found: 0,
      results: [],
      differences: [],
      all_ok: true,
      grade: @runtime.Pass,
    },
    cycles_requested: 4,
    cycles_ok: 3,
    until_fault: false,
    cycle_period_ns: 500_000L,
    output_period_ns: Some(2_000_000L),
    telemetry: {
      cycles: 4L,
      tx_frames: 4L,
      rx_frames: 4L,
      timeouts: 1L,
      retries: 0L,
      wkc_errors: 1L,
      irq_events: 0L,
      dc_delay_updates: 0L,
    },
    final_phase: @runtime.Done,
    fault: None,
  }
  let text = run_report_ndjson(report).stringify()
  assert_true(text.contains("\"kind\":\"run-summary\""))
  assert_true(text.contains("\"summary\""))
  assert_true(text.contains("\"cycles_ok\":3"))
  assert_true(text.contains("\"until_fault\":false"))
}

///|
test "cli run progress json includes telemetry snapshot" {
  let text = run_progress_json({
    cycles_completed: 42L,
    cycles_ok: 40,
    cycles_requested: Some(100),
    until_fault: true,
    cycle_period_ns: 1_000_000L,
    output_period_ns: 5_000_000,
    telemetry: {
      cycles: 42L,
      tx_frames: 42L,
      rx_frames: 41L,
      timeouts: 2L,
      retries: 1L,
      wkc_errors: 3L,
      irq_events: 4L,
      dc_delay_updates: 5L,
    },
    consecutive_timeouts: 2,
  }).stringify()
  assert_true(text.contains("\"kind\":\"run-progress\""))
  assert_true(text.contains("\"cycles_completed\":42"))
  assert_true(text.contains("\"cycles_requested\":100"))
  assert_true(text.contains("\"timeouts\":2"))
  assert_true(text.contains("\"consecutive_timeouts\":2"))
}

///|
test "cli run progress json emits null requested cycles for until-fault mode" {
  let text = run_progress_json({
    cycles_completed: 7L,
    cycles_ok: 7,
    cycles_requested: None,
    until_fault: true,
    cycle_period_ns: 250_000L,
    output_period_ns: 1_000_000,
    telemetry: {
      cycles: 7L,
      tx_frames: 7L,
      rx_frames: 7L,
      timeouts: 0L,
      retries: 0L,
      wkc_errors: 0L,
      irq_events: 0L,
      dc_delay_updates: 0L,
    },
    consecutive_timeouts: 0,
  }).stringify()
  assert_true(text.contains("\"cycles_requested\":null"))
  assert_true(text.contains("\"until_fault\":true"))
}

///|
test "cli run progress text formats key counters" {
  let text = run_progress_text({
    cycles_completed: 9L,
    cycles_ok: 8,
    cycles_requested: Some(10),
    until_fault: false,
    cycle_period_ns: 1_000_000L,
    output_period_ns: 2_000_000,
    telemetry: {
      cycles: 9L,
      tx_frames: 9L,
      rx_frames: 9L,
      timeouts: 1L,
      retries: 0L,
      wkc_errors: 2L,
      irq_events: 0L,
      dc_delay_updates: 0L,
    },
    consecutive_timeouts: 1,
  })
  assert_true(text.contains("cycles=9"))
  assert_true(text.contains("ok=8"))
  assert_true(text.contains("timeouts=1"))
  assert_true(text.contains("wkc_errors=2"))
}

///|
test "cli native backend mapping stays stable" {
  assert_eq(cli_backend_to_native_backend(NativeAuto), @native.Auto)
  assert_eq(
    cli_backend_to_native_backend(NativeWindowsNpcap),
    @native.WindowsNpcap,
  )
  assert_eq(
    cli_backend_to_native_backend(NativeLinuxRaw),
    @native.LinuxRawSocket,
  )
}

///|
test "cli read-sii json includes categories" {
  let preamble : @mailbox.SiiPreamble = {
    pdi_control: 1U,
    pdi_config: 2U,
    sync_impulse_length_raw: 3U,
    pdi_config2: 4U,
    configured_station_alias: 5U,
    checksum: 6U,
    checksum_ok: true,
  }
  let standard : @mailbox.SiiStandardMetadata = {
    eeprom_size_raw: 7U,
    version: 1U,
  }
  let header : @mailbox.SiiData = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
    bootstrap_rx_offset: 5U,
    bootstrap_rx_size: 6U,
    bootstrap_tx_offset: 7U,
    bootstrap_tx_size: 8U,
    mailbox_rx_offset: 9U,
    mailbox_rx_size: 10U,
    mailbox_tx_offset: 11U,
    mailbox_tx_size: 12U,
    mailbox_protocols: 13U,
    firmware_version: 14U,
    hardware_version: 15U,
    production_date_raw: 0x5A31U,
    pdi_control_1: b'\x16',
    esc_config_b0: b'\x81',
    pdi_config_1: 16U,
    pdi_config_1_ext: 17U,
    esc_config_b4: 18U,
    esc_config_b5: 19U,
    esc_config_b6: 20U,
    checksum_b: 21U,
    esc_config_b_present: true,
  }
  let general : @mailbox.SiiGeneral? = Some({
    group_idx: b'\x01',
    image_idx: b'\x02',
    order_idx: b'\x03',
    name_idx: b'\x04',
    coe_details: b'\x05',
    foe_supported: true,
    eoe_supported: false,
    soe_supported: true,
    soe_channels: b'\x01',
    ds402_channels: b'\x00',
    sysman_class: b'\x00',
    flags: b'\x0A',
    current_on_ebus: 14,
    physical_port_0: b'\x01',
    physical_port_1: b'\x01',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  })
  let sii : @mailbox.SiiFullInfo = {
    eeprom: Bytes::new(256),
    preamble,
    standard,
    header,
    categories: [
      { category: @mailbox.General, type_code: 30U, data: Bytes::new(32) },
      {
        category: @mailbox.Dictionary,
        type_code: 80U,
        data: Bytes::from_array([b'\x12', b'\x34', b'\x56', b'\x78']),
      },
      {
        category: @mailbox.FmmuEx,
        type_code: 42U,
        data: Bytes::from_array([b'\x07', b'\x00', b'\x02', b'\x01']),
      },
      {
        category: @mailbox.SyncUnit,
        type_code: 43U,
        data: Bytes::from_array([b'\x0F', b'\x00']),
      },
      {
        category: @mailbox.Timeouts,
        type_code: 70U,
        data: Bytes::from_array([
          b'\xB8', b'\x0B', b'\x10', b'\x27', b'\x88', b'\x13', b'\xC8', b'\x00',
          b'\x64', b'\x00', b'\xE8', b'\x03', b'\x00', b'\x00', b'\x00', b'\x00',
        ]),
      },
      {
        category: @mailbox.Raw,
        type_code: 0x1234U,
        data: Bytes::from_array([b'\x9A', b'\xBC', b'\xDE', b'\xF0']),
      },
    ],
    strings: ["SlaveName"],
    general,
    timeouts: Some({
      preop_timeout_ms: 3000U,
      safeop_op_timeout_ms: 10000U,
      back_to_init_timeout_ms: 5000U,
      back_to_safeop_timeout_ms: 200U,
      mailbox_request_timeout_ms: 100U,
      mailbox_response_timeout_ms: 1000U,
    }),
    fmmu: [@mailbox.FmmuDirection::Outputs],
    fmmu_ex: [
      {
        op_only: true,
        sm_defined: true,
        su_defined: true,
        sync_manager: b'\x02',
        sync_unit: b'\x01',
      },
    ],
    sync_managers: [
      {
        physical_start: 0x1000U,
        length: 256U,
        control: b'\x26',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.SmType::MailboxOut,
      },
    ],
    sync_units: [
      {
        separate_su: true,
        separate_frame: true,
        depend_on_input_state: true,
        frame_repeat_support: true,
        raw_flags: b'\x0F',
      },
      {
        separate_su: false,
        separate_frame: false,
        depend_on_input_state: false,
        frame_repeat_support: false,
        raw_flags: b'\x00',
      },
    ],
    tx_pdo: [
      {
        pdo_index: 0x1A00U,
        entry_count: b'\x01',
        sync_manager: b'\x03',
        synchronization: b'\x00',
        name_idx: b'\x01',
        flags: 0U,
        entries: [
          {
            entry_index: 0x6000U,
            subindex: b'\x01',
            name_idx: b'\x01',
            data_type: b'\x05',
            bit_length: b'\x10',
            flags: 0U,
          },
        ],
      },
    ],
    rx_pdo: [],
    dc_clocks: [
      {
        cycle_time_0: 0U,
        shift_time_0: 0U,
        shift_time_1: 0U,
        sync1_cycle_factor: 0,
        assign_activate: 0x0300U,
        sync0_cycle_factor: 0,
        name_idx: b'\x01',
        description_idx: b'\x01',
      },
    ],
  }
  let json = read_sii_json(0U, 128, sii)
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"vendor_id\": 1"))
  assert_true(text.contains("\"aoe\": true"))
  assert_true(text.contains("\"preamble\""))
  assert_true(text.contains("\"dc_clocks\""))
  assert_true(text.contains("\"fmmu_ex\""))
  assert_true(text.contains("\"sync_units\""))
  assert_true(text.contains("\"timeouts\""))
  assert_true(text.contains("\"tx_pdo\""))
  assert_true(text.contains("\"strings\""))
  assert_true(text.contains("\"categories\""))
  assert_true(text.contains("\"production_week\""))
  assert_true(text.contains("\"esc_config_b_present\": true"))
  assert_true(text.contains("\"title\": \"Dictionary\""))
  assert_true(text.contains("\"known\": false"))
}

///|
test "cli decode esc syncmanager window decodes physical fields" {
  let report = decode_esc_sync_manager_window(
    2,
    0x0810U,
    Bytes::from_array([
      b'\x00', b'\x11', b'\x06', b'\x00', b'\x64', b'\x00', b'\x01', b'\x00',
    ]),
  )
  assert_eq(report.index, 2)
  assert_eq(report.register_offset, 0x0810U)
  assert_eq(report.physical_start, 0x1100U)
  assert_eq(report.length, 6U)
  assert_eq(report.control, b'\x64')
  assert_eq(report.activate, b'\x01')
}

///|
test "cli decode esc fmmu window decodes addressing fields" {
  let report = decode_esc_fmmu_window(
    0,
    0x0600U,
    Bytes::from_array([
      b'\x00', b'\x10', b'\x00', b'\x00', b'\x06', b'\x00', b'\x00', b'\x07', b'\x00',
      b'\x11', b'\x00', b'\x02', b'\x01', b'\x00', b'\x00', b'\x00',
    ]),
  )
  assert_eq(report.index, 0)
  assert_eq(report.logical_start, 0x1000U)
  assert_eq(report.length, 6U)
  assert_eq(report.physical_start, 0x1100U)
  assert_eq(report.type_register, b'\x02')
  assert_eq(report.activate, b'\x01')
}

///|
test "cli expected syncmanager report encodes computed config" {
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [
      {
        physical_start: 0x1000U,
        length: 8U,
        control: b'\x26',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.MailboxOut,
      },
      {
        physical_start: 0x1080U,
        length: 8U,
        control: b'\x22',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.MailboxIn,
      },
      {
        physical_start: 0x1100U,
        length: 6U,
        control: b'\x64',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.ProcessDataOut,
      },
      {
        physical_start: 0x1180U,
        length: 10U,
        control: b'\x20',
        status: b'\x00',
        activate: b'\x01',
        sm_type: @mailbox.ProcessDataIn,
      },
    ],
    fmmu_configs: [],
    output_bytes: 6,
    input_bytes: 10,
  }
  let report = expected_sync_manager_register_report(mapping, 2)
  assert_eq(report.index, 2)
  assert_eq(report.register_offset, 0x0810U)
  assert_eq(report.physical_start, 0x1100U)
  assert_eq(report.length, 6U)
  assert_eq(report.control, b'\x64')
  assert_eq(report.activate, b'\x01')
}

///|
test "cli expected fmmu report encodes computed config" {
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [
      {
        logical_start: 0x1000U,
        length: 6U,
        logical_start_bit: b'\x00',
        logical_end_bit: b'\x07',
        physical_start: 0x1100U,
        physical_start_bit: b'\x00',
        direction: @mailbox.Outputs,
        activate: true,
      },
      {
        logical_start: 0x1006U,
        length: 10U,
        logical_start_bit: b'\x00',
        logical_end_bit: b'\x07',
        physical_start: 0x1180U,
        physical_start_bit: b'\x00',
        direction: @mailbox.Inputs,
        activate: true,
      },
    ],
    output_bytes: 6,
    input_bytes: 10,
  }
  let report = expected_fmmu_register_report(mapping, 0)
  assert_eq(report.index, 0)
  assert_eq(report.register_offset, 0x0600U)
  assert_eq(report.logical_start, 0x1000U)
  assert_eq(report.length, 6U)
  assert_eq(report.physical_start, 0x1100U)
  assert_eq(report.type_register, b'\x02')
  assert_eq(report.activate, b'\x01')
}
