///|
test "format helpers decode_payload_u32_le rejects empty and oversized payloads" {
  assert_eq(decode_payload_u32_le(Bytes::new(0)), None)
  assert_eq(
    decode_payload_u32_le(
      Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x00', b'\x00']),
    ),
    None,
  )
}

///|
test "format helpers decode_payload_u32_le assembles partial little-endian values" {
  assert_eq(decode_payload_u32_le(Bytes::from_array([b'\x12'])), Some(0x12U))
  assert_eq(
    decode_payload_u32_le(
      Bytes::from_array([b'\x78', b'\x56', b'\x34', b'\x12']),
    ),
    Some(0x12345678U),
  )
}

///|
test "format helpers decode u16/u32 little endian return zero on short payloads" {
  assert_eq(decode_u16_le(Bytes::from_array([b'\x01']), 0), 0U)
  assert_eq(decode_u32_le(Bytes::from_array([b'\x01', b'\x02']), 0), 0U)
}

///|
test "format helpers physical_port_name covers reserved port" {
  assert_eq(physical_port_name(b'\x02'), "reserved")
}

///|
test "cli show bridge renders backend and progress output as readable text" {
  assert_eq(CliBackend::to_string(NativeAuto), "NativeAuto")
  assert_eq(CliBackend::to_string(NativeWindowsNpcap), "NativeWindowsNpcap")
  assert_eq(RunProgressOutput::to_string(Ndjson), "Ndjson")
  let buf = @buffer.new(size_hint=16)
  buf.write_object(Mock)
  buf.write_string(",")
  buf.write_object(Text)
  assert_eq(buf.to_string(), "Mock,Text")
}

///|
test "cli parse_backend rejects unknown backend identifier" {
  let result : Result[CliBackend, Error] = try? parse_backend([
    "moonecat", "scan", "--backend", "unsupported-backend",
  ])
  guard result is Err(@hal.EcError::ConfigMismatch(message)) else {
    fail("expected unsupported backend to fail")
  }
  assert_true(message.contains("unsupported backend"))
  assert_true(message.contains("unsupported-backend"))
}

///|
test "cli resolve_native_cli_config honors explicit interface flag" {
  let timeout = @hal.Duration(1_000_000L)
  let config = resolve_native_cli_config(
    ["moonecat", "scan", "--backend", "native-linux-raw", "--if", "eth7"],
    NativeLinuxRaw,
    timeout,
  )
  assert_eq(config.backend, @native.LinuxRawSocket)
  assert_eq(config.interface_name, "eth7")
}

///|
test "cli mailbox_sm_window_matches checks size and ignores reserved status byte" {
  let short = Bytes::from_array([b'\x00', b'\x00', b'\x00'])
  assert_eq(mailbox_sm_window_matches(short, short), false)
  let expected = Bytes::from_array([
    b'\x00', b'\x10', b'\x80', b'\x00', b'\x26', b'\x00', b'\x01', b'\x00',
  ])
  let actual_match = Bytes::from_array([
    b'\x00', b'\x10', b'\x80', b'\x00', b'\x26', b'\xFF', b'\x01', b'\x00',
  ])
  assert_true(mailbox_sm_window_matches(expected, actual_match))
  let actual_diff = Bytes::from_array([
    b'\x00', b'\x10', b'\x80', b'\x00', b'\x27', b'\x00', b'\x01', b'\x00',
  ])
  assert_eq(mailbox_sm_window_matches(expected, actual_diff), false)
}

///|
fn sample_mailbox_readback_entry(matches : Bool) -> MailboxReadbackEntry {
  let raw_expected = "0x0010008000260001"
  let raw_actual = if matches { raw_expected } else { "0x0010008000270001" }
  {
    index: 0,
    register_offset: 0x0800U,
    expected: {
      index: 0,
      register_offset: 0x0800U,
      raw_hex: raw_expected,
      physical_start: 0x1000U,
      length: 128U,
      control: b'\x26',
      status: b'\x00',
      activate: b'\x01',
    },
    actual: {
      index: 0,
      register_offset: 0x0800U,
      raw_hex: raw_actual,
      physical_start: 0x1000U,
      length: 128U,
      control: if matches {
        b'\x26'
      } else {
        b'\x27'
      },
      status: b'\x00',
      activate: b'\x01',
    },
    matches,
  }
}

///|
test "cli build_mailbox_readback_mismatch composes structured message" {
  let entry = sample_mailbox_readback_entry(false)
  let message = build_mailbox_readback_mismatch(entry)
  assert_true(message.contains("SM0"))
  assert_true(message.contains("expected=0x0010008000260001"))
  assert_true(message.contains("actual=0x0010008000270001"))
}

///|
test "cli mailbox_readback_report_text prints entries and mismatch list" {
  let entry = sample_mailbox_readback_entry(false)
  let report : MailboxReadbackReport = {
    station: 0x1001U,
    source: "esi-json",
    entries: [entry],
    mismatches: [build_mailbox_readback_mismatch(entry)],
  }
  let text = mailbox_readback_report_text(report)
  assert_true(text.contains("Mailbox SyncManager Readback"))
  assert_true(text.contains("Station: 4097"))
  assert_true(text.contains("Source: esi-json"))
  assert_true(text.contains("SM0 @ 0x0800"))
  assert_true(text.contains("Match: ............ false"))
  assert_true(text.contains("Mismatches"))
  assert_true(text.contains("- SM0"))
}

///|
test "cli mailbox_readback_report_text reports clean run when no mismatches" {
  let entry = sample_mailbox_readback_entry(true)
  let report : MailboxReadbackReport = {
    station: 0x1001U,
    source: "online-sii",
    entries: [entry],
    mismatches: [],
  }
  let text = mailbox_readback_report_text(report)
  assert_true(text.contains("No mismatches"))
}

///|
test "cli run_esi_sii_command rejects deprecated --xml flag" {
  let result : Result[Unit, Error] = try? run_esi_sii_command(
    ["moonecat", "esi-sii", "--xml", "sample.esi.xml"],
    false,
  )
  guard result is Err(@hal.EcError::ConfigMismatch(message)) else {
    fail("expected --xml flag to be rejected")
  }
  assert_true(message.contains("--esi-json"))
}

///|
test "cli require_cli_file_flag requires the flag to be present" {
  let result : Result[String, Error] = try? require_cli_file_flag(
    ["moonecat", "esi-sii"],
    "--esi-json",
    "ESI JSON",
  )
  guard result is Err(@hal.EcError::ConfigMismatch(message)) else {
    fail("expected missing flag to be reported")
  }
  assert_true(message.contains("--esi-json"))
  assert_true(message.contains("ESI JSON"))
}

///|
test "cli read_cli_text_file surfaces filesystem errors with context" {
  let result : Result[String, Error] = try? read_cli_text_file(
    "definitely-missing-file-cli-coverage.json", "ESI JSON",
  )
  guard result is Err(@hal.EcError::ConfigMismatch(message)) else {
    fail("expected missing file to surface as ConfigMismatch")
  }
  assert_true(message.contains("definitely-missing-file-cli-coverage.json"))
  assert_true(message.contains("ESI JSON"))
}

///|
test "cli require_uint_flag returns parsed value or default" {
  assert_eq(
    require_uint_flag(
      ["moonecat", "scan", "--position", "12"],
      "--position",
      0U,
    ),
    12U,
  )
  assert_eq(require_uint_flag(["moonecat", "scan"], "--position", 7U), 7U)
}

///|
test "cli require_station_flag enforces explicit station value" {
  assert_eq(
    require_station_flag(["moonecat", "esc-regs", "--station", "4097"]),
    4097U,
  )
  let missing : Result[UInt, Error] = try? require_station_flag([
    "moonecat", "esc-regs",
  ])
  guard missing is Err(@hal.EcError::ConfigMismatch(message)) else {
    fail("expected missing station to fail")
  }
  assert_true(message.contains("esc-regs"))
}

///|
test "cli pdo_policy_name maps the prefer-live toggle" {
  assert_eq(pdo_policy_name(true), "prefer-live")
  assert_eq(pdo_policy_name(false), "force-configured")
}

///|
test "cli pdo_effective_source picks force/live/plan branches" {
  assert_eq(pdo_effective_source("esi-json", false, true), "forced-esi")
  assert_eq(
    pdo_effective_source("online-sii", false, false),
    "forced-online-sii",
  )
  assert_eq(pdo_effective_source("esi-json", true, true), "live")
  assert_eq(pdo_effective_source("online-sii", true, false), "online-sii")
}

///|
test "cli pdo mapping entry raw round trips through normalization" {
  let entry : @mailbox.SiiPdoEntry = {
    entry_index: 0x6040U,
    subindex: b'\x02',
    name_idx: b'\x00',
    data_type: b'\x00',
    bit_length: b'\x10',
    flags: 0U,
  }
  // Encoding mirrors the implementation: entry_index | subindex<<16 | bit_length<<24.
  let raw = pdo_mapping_entry_raw(entry)
  assert_true(raw != 0U)
  // normalize re-packs the SDO 0x1A00 word format ([index:16][sub:8][len:8])
  // into the same shape used by pdo_mapping_entry_raw.
  let live_word : UInt = 0x60400210U
  let normalized = normalize_pdo_mapping_entry_raw(live_word)
  // After normalization the top byte must carry the bit length (0x10).
  assert_eq((normalized >> 24) & 0xFFU, 0x10U)
  // ...the next byte the subindex (0x02)...
  assert_eq((normalized >> 16) & 0xFFU, 0x02U)
  // ...and the low half preserves the object index (0x6040).
  assert_eq(normalized & 0xFFFFU, 0x6040U)
}

///|
fn sample_sii_pdo() -> @mailbox.SiiPdo {
  {
    pdo_index: 0x1600U,
    entry_count: b'\x01',
    sync_manager: b'\x02',
    synchronization: b'\x00',
    name_idx: b'\x00',
    flags: 0U,
    entries: [
      {
        entry_index: 0x6040U,
        subindex: b'\x00',
        name_idx: b'\x00',
        data_type: b'\x00',
        bit_length: b'\x10',
        flags: 0U,
      },
    ],
  }
}

///|
test "cli pdo_direction_from_sii projects assigned indices and entry triplets" {
  let direction = pdo_direction_from_sii([sample_sii_pdo()], 0x1C12U)
  assert_eq(direction.assignment_index, 0x1C12U)
  assert_eq(direction.assigned_pdos, [0x1600U])
  assert_eq(direction.objects.length(), 1)
  assert_eq(direction.objects[0].index, 0x1600U)
  assert_eq(direction.objects[0].entries, [0x10006040U])
}

///|
test "cli pdo_uint_arrays_equal handles length and element differences" {
  assert_true(pdo_uint_arrays_equal([1U, 2U], [1U, 2U]))
  assert_eq(pdo_uint_arrays_equal([1U, 2U], [1U]), false)
  assert_eq(pdo_uint_arrays_equal([1U, 2U], [1U, 3U]), false)
}

///|
test "cli pdo_direction_mismatch_messages reports assignment and mapping diffs" {
  let configured : PdoDirectionReport = {
    assignment_index: 0x1C12U,
    assigned_pdos: [0x1602U],
    objects: [{ index: 0x1602U, entries: [0x10004060U] }],
  }
  let live : PdoDirectionReport = {
    assignment_index: 0x1C12U,
    assigned_pdos: [0x1600U],
    objects: [{ index: 0x1600U, entries: [0x10004061U] }],
  }
  let messages = pdo_direction_mismatch_messages(configured, live)
  assert_true(messages.length() >= 2)
  let joined = join_strings(messages, " | ")
  assert_true(joined.contains("assignment 0x1C12"))
  assert_true(joined.contains("expected=[0x1602]"))
  assert_true(joined.contains("actual=[0x1600]"))
  assert_true(joined.contains("mapping 0x1602"))
  assert_true(joined.contains("mapping 0x1600"))
}

///|
test "cli pdo_direction_mismatch_messages returns empty when reports agree" {
  let same : PdoDirectionReport = {
    assignment_index: 0x1C13U,
    assigned_pdos: [0x1A00U],
    objects: [{ index: 0x1A00U, entries: [0x10004160U] }],
  }
  assert_true(pdo_direction_mismatch_messages(same, same).is_empty())
}

///|
test "cli pdo_audit_report_text formats configured/live sections and mismatches" {
  let report = sample_pdo_audit_report()
  let text = pdo_audit_report_text(report)
  assert_true(text.contains("PDO Audit"))
  assert_true(text.contains("Plan Source: esi-json"))
  assert_true(text.contains("Policy: prefer-live"))
  assert_true(text.contains("Effective Source: live"))
  assert_true(text.contains("Live Detected: yes"))
  assert_true(text.contains("Live Differs From Plan: yes"))
  assert_true(text.contains("Configured Rx: 0x1C12"))
  assert_true(text.contains("Configured Rx Objects: 0x1602"))
  assert_true(text.contains("Live Rx: 0x1C12"))
  assert_true(text.contains("Live Tx Objects: 0x1A00"))
  assert_true(text.contains("Mismatches:"))
  assert_true(text.contains("- assignment 0x1C12"))
}

///|
test "cli pdo_audit_report_text reports clean run when no mismatches" {
  let direction : PdoDirectionReport = {
    assignment_index: 0x1C12U,
    assigned_pdos: [],
    objects: [],
  }
  let report : PdoAuditReport = {
    plan_source: "online-sii",
    policy: "force-configured",
    effective_source: "forced-online-sii",
    live_detected: None,
    live_differs_from_plan: None,
    live_read_error: Some("RecvTimeout"),
    configured_rx: direction,
    configured_tx: { ..direction, assignment_index: 0x1C13U },
    live_rx: None,
    live_tx: None,
    mismatches: [],
  }
  let text = pdo_audit_report_text(report)
  assert_true(text.contains("Live Read Error: RecvTimeout"))
  assert_true(text.contains("Mismatches: none"))
}

///|
test "cli scan_report_json serializes per-slave fields" {
  let report : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: Some(0x12U),
        vendor_id: 2U,
        product_code: 0x44C2C52U,
        revision: 0x110000U,
        serial: 9U,
        identification: 5U,
      },
    ],
  }
  let text = scan_report_json(report).stringify(indent=2)
  assert_true(text.contains("\"slave_count\": 1"))
  assert_true(text.contains("\"station_address\": 4097"))
  assert_true(text.contains("\"alias_address\": 18"))
  assert_true(text.contains("\"identification\": 5"))
}

///|
test "cli option helpers fall through to null for None inputs" {
  assert_eq(option_bool_json(None).stringify(), "null")
  assert_eq(option_esm_state_json(None).stringify(), "null")
  assert_eq(option_identity_json(None).stringify(), "null")
}

///|
test "cli identity_json renders the four identity fields" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 2U,
    product_code: 17U,
    revision: 3U,
    serial: 4U,
  }
  let text = identity_json(identity).stringify()
  assert_true(text.contains("\"vendor_id\":2"))
  assert_true(text.contains("\"product_code\":17"))
  assert_true(text.contains("\"revision\":3"))
  assert_true(text.contains("\"serial\":4"))
}

///|
test "cli mailbox_protocols_json maps each protocol flag" {
  let protocols : @runtime.ConfigurationMailboxProtocols = {
    aoe: false,
    coe: true,
    eoe: false,
    foe: true,
    soe: false,
    voe: false,
  }
  let text = mailbox_protocols_json(protocols).stringify()
  assert_true(text.contains("\"coe\":true"))
  assert_true(text.contains("\"foe\":true"))
  assert_true(text.contains("\"voe\":false"))
}

///|
test "cli process_data_summary_json includes mailbox protocols and counts" {
  let summary : @runtime.ConfigurationProcessDataSummary = {
    sync_manager_count: 4,
    fmmu_count: 2,
    rx_pdo_count: 1,
    tx_pdo_count: 1,
    mailbox_protocols: Some({
      aoe: false,
      coe: true,
      eoe: false,
      foe: false,
      soe: false,
      voe: false,
    }),
    dc_op_mode_count: 1,
    dc_assign_activate_count: 768,
  }
  let text = process_data_summary_json(summary).stringify(indent=2)
  assert_true(text.contains("\"sync_manager_count\": 4"))
  assert_true(text.contains("\"dc_assign_activate_count\": 768"))
  assert_true(text.contains("\"coe\": true"))
}

///|
test "cli configuration_difference_json covers identity and process-data variants" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
  }
  let summary : @runtime.ConfigurationProcessDataSummary = {
    sync_manager_count: 1,
    fmmu_count: 0,
    rx_pdo_count: 0,
    tx_pdo_count: 0,
    mailbox_protocols: None,
    dc_op_mode_count: 0,
    dc_assign_activate_count: 0,
  }
  let missing_text = configuration_difference_json(
    @runtime.ConfigurationDifference::Missing(position=2),
  ).stringify()
  assert_true(missing_text.contains("\"type\":\"missing\""))
  assert_true(missing_text.contains("\"position\":2"))
  let identity_text = configuration_difference_json(
    @runtime.ConfigurationDifference::IdentityMismatch(
      position=0,
      expected=Some(identity),
      actual=None,
    ),
  ).stringify()
  assert_true(identity_text.contains("\"type\":\"identity-mismatch\""))
  assert_true(identity_text.contains("\"vendor_id\":1"))
  let identification_text = configuration_difference_json(
    @runtime.ConfigurationDifference::IdentificationMismatch(
      position=1,
      expected=Some(7U),
      actual=Some(8U),
    ),
  ).stringify()
  assert_true(
    identification_text.contains("\"type\":\"identification-mismatch\""),
  )
  assert_true(identification_text.contains("\"actual\":8"))
  let summary_text = configuration_difference_json(
    @runtime.ConfigurationDifference::ProcessDataSummaryMismatch(
      position=3,
      expected=summary,
      actual=summary,
    ),
  ).stringify()
  assert_true(
    summary_text.contains("\"type\":\"process-data-summary-mismatch\""),
  )
  assert_true(summary_text.contains("\"sync_manager_count\":1"))
}
