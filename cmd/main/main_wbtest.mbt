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
  let path = build_cli_transition_path(@protocol.Op, @protocol.Boot)
  assert_eq(path.length(), 5)
  assert_eq(path[0], @protocol.Op)
  assert_eq(path[1], @protocol.SafeOp)
  assert_eq(path[2], @protocol.PreOp)
  assert_eq(path[3], @protocol.Init)
  assert_eq(path[4], @protocol.Boot)
}

///|
test "cli state transition report json includes station mode fields" {
  let json = state_transition_report_json({
    mode: "station-path",
    target: @protocol.SafeOp,
    station: Some(0x1001U),
    current: Some(@protocol.PreOp),
    final_state: Some(@protocol.SafeOp),
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
  }
  let text = run_report_json(report).stringify(indent=2)
  assert_true(text.contains("\"surface\""))
  assert_true(text.contains("\"runtime_metrics\""))
  assert_true(text.contains("\"overall_level\": \"Info\""))
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
test "cli run helper reopens nic for run path" {
  let result : Result[Unit, Error] = try? run_mock_command_with_fresh_nic(
    true,
    @protocol.Op,
    Some(@protocol.Init),
    @hal.Duration(1000L),
  )
  assert_true(result is Ok(_))
}

///|
test "cli read_sii_json includes header and categories" {
  let preamble : @mailbox.SiiPreamble = {
    pdi_control: 0x0E80U,
    pdi_config: 0xEE44U,
    sync_impulse_length_raw: 0x0010U,
    pdi_config2: 0U,
    configured_station_alias: 0U,
    checksum: 0x00CBU,
    checksum_ok: true,
  }
  let standard : @mailbox.SiiStandardMetadata = {
    eeprom_size_raw: 15U,
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
    current_on_ebus: 14U,
    physical_port_0: b'\x01',
    physical_port_1: b'\x01',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  })
  let json = read_sii_json(
    0U,
    128,
    preamble,
    standard,
    header,
    general,
    ["SlaveName"],
    [@mailbox.FmmuDirection::Outputs],
    [
      {
        physical_start: 0x1000U,
        length: 256U,
        control: b'\x26',
        status: b'\x00',
        enable: true,
        sm_type: @mailbox.SmType::MailboxOut,
      },
    ],
    [
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
    [
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
    [],
    [{ category: @mailbox.General, data: Bytes::new(32) }],
  )
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"vendor_id\": 1"))
  assert_true(text.contains("\"preamble\""))
  assert_true(text.contains("\"dc_clocks\""))
  assert_true(text.contains("\"tx_pdo\""))
  assert_true(text.contains("\"strings\""))
  assert_true(text.contains("\"categories\""))
}
