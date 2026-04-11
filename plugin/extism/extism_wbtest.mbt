// ===== Batch 11: whitebox tests for entrypoints.mbt JSON serializer helpers =====

///|
test "ec_error_code all EcError variants" {
  assert_eq(ec_error_code(@hal.EcError::LinkDown), "link_down")
  assert_eq(ec_error_code(@hal.EcError::SendFailed("x")), "send_failed")
  assert_eq(ec_error_code(@hal.EcError::RecvTimeout), "recv_timeout")
  assert_eq(ec_error_code(@hal.EcError::RecvFailed("x")), "recv_failed")
  assert_eq(ec_error_code(@hal.EcError::InvalidFrame("x")), "invalid_frame")
  assert_eq(ec_error_code(@hal.EcError::InvalidPdu("x")), "invalid_pdu")
  assert_eq(
    ec_error_code(@hal.EcError::UnexpectedWkc(expected=1, actual=0)),
    "unexpected_wkc",
  )
  assert_eq(
    ec_error_code(@hal.EcError::EsmTransitionFailed(from="Init", to="PreOp")),
    "esm_transition_failed",
  )
  assert_eq(ec_error_code(@hal.EcError::EsmStateError("x")), "esm_state_error")
  assert_eq(ec_error_code(@hal.EcError::MailboxTimeout), "mailbox_timeout")
  assert_eq(
    ec_error_code(@hal.EcError::MailboxProtocol("x")),
    "mailbox_protocol",
  )
  assert_eq(ec_error_code(@hal.EcError::SdoAbort(0x06090030U)), "sdo_abort")
  assert_eq(ec_error_code(@hal.EcError::SiiReadFailed("x")), "sii_read_failed")
  assert_eq(
    ec_error_code(@hal.EcError::EsiParseFailed("x")),
    "esi_parse_failed",
  )
  assert_eq(ec_error_code(@hal.EcError::ConfigMismatch("x")), "config_mismatch")
  assert_eq(ec_error_code(@hal.EcError::NotSupported("x")), "not_supported")
  assert_eq(ec_error_code(@hal.EcError::Internal("x")), "internal")
}

///|
test "error_response builds PluginResponse for LinkDown" {
  let req : PluginRequest = {
    version: "v1",
    command: Scan,
    request_id: "err-1",
    timeout_ns: None,
    payload: Json::object({}),
  }
  let resp = error_response(req, @hal.EcError::LinkDown)
  assert_eq(resp.ok, false)
  assert_eq(resp.error_code, Some("link_down"))
  assert_true(resp.error_message is Some(_))
  assert_eq(resp.request_id, "err-1")
}

///|
test "identity_json serializes SlaveIdentity" {
  let id : @hal.SlaveIdentity = {
    vendor_id: 0x1234U,
    product_code: 0x5678U,
    revision: 0x0001U,
    serial: 0xAAAAU,
  }
  let j = identity_json(id)
  inspect(
    j,
    content=(
      #|Object({"vendor_id": Number(4660), "product_code": Number(22136), "revision": Number(1), "serial": Number(43690)})
    ),
  )
}

///|
test "option_identity_json Some and None" {
  let id : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
  }
  let some_j = option_identity_json(Some(id))
  inspect(
    some_j,
    content=(
      #|Object({"vendor_id": Number(1), "product_code": Number(2), "revision": Number(3), "serial": Number(4)})
    ),
  )
  let none_j = option_identity_json(None)
  inspect(
    none_j,
    content=(
      #|Null
    ),
  )
}

///|
test "option_uint_json Some and None" {
  inspect(
    option_uint_json(Some(42U)),
    content=(
      #|Number(42)
    ),
  )
  inspect(
    option_uint_json(None),
    content=(
      #|Null
    ),
  )
}

///|
test "mailbox_protocols_json all fields" {
  let mp : @runtime.ConfigurationMailboxProtocols = {
    aoe: true,
    coe: true,
    eoe: false,
    foe: true,
    soe: false,
    voe: true,
  }
  let j = mailbox_protocols_json(mp)
  inspect(
    j,
    content=(
      #|Object({"aoe": True, "coe": True, "eoe": False, "foe": True, "soe": False, "voe": True})
    ),
  )
}

///|
test "process_data_summary_json with mailbox_protocols" {
  let summary : @runtime.ConfigurationProcessDataSummary = {
    sync_manager_count: 4,
    fmmu_count: 2,
    rx_pdo_count: 1,
    tx_pdo_count: 3,
    mailbox_protocols: Some({
      aoe: false,
      coe: true,
      eoe: false,
      foe: false,
      soe: false,
      voe: false,
    }),
    dc_op_mode_count: 1,
    dc_assign_activate_count: 2,
  }
  let j = process_data_summary_json(summary)
  inspect(
    j,
    content=(
      #|Object({"sync_manager_count": Number(4), "fmmu_count": Number(2), "rx_pdo_count": Number(1), "tx_pdo_count": Number(3), "mailbox_protocols": Object({"aoe": False, "coe": True, "eoe": False, "foe": False, "soe": False, "voe": False}), "dc_op_mode_count": Number(1), "dc_assign_activate_count": Number(2)})
    ),
  )
}

///|
test "process_data_summary_json without mailbox_protocols" {
  let summary : @runtime.ConfigurationProcessDataSummary = {
    sync_manager_count: 0,
    fmmu_count: 0,
    rx_pdo_count: 0,
    tx_pdo_count: 0,
    mailbox_protocols: None,
    dc_op_mode_count: 0,
    dc_assign_activate_count: 0,
  }
  let j = process_data_summary_json(summary)
  inspect(
    j,
    content=(
      #|Object({"sync_manager_count": Number(0), "fmmu_count": Number(0), "rx_pdo_count": Number(0), "tx_pdo_count": Number(0), "mailbox_protocols": Null, "dc_op_mode_count": Number(0), "dc_assign_activate_count": Number(0)})
    ),
  )
}

///|
test "configuration_difference_json Missing" {
  let diff = @runtime.ConfigurationDifference::Missing(position=2)
  let j = configuration_difference_json(diff)
  inspect(
    j,
    content=(
      #|Object({"category": String("Topology"), "grade": String("Block"), "type": String("missing"), "position": Number(2)})
    ),
  )
}

///|
test "configuration_difference_json OptionalMissing" {
  let diff = @runtime.ConfigurationDifference::OptionalMissing(
    position=1,
    group_id=Some(5U),
  )
  let j = configuration_difference_json(diff)
  inspect(
    j,
    content=(
      #|Object({"category": String("Topology"), "grade": String("Warn"), "type": String("optional-missing"), "position": Number(1), "group_id": Number(5)})
    ),
  )
}

///|
test "configuration_difference_json Extra" {
  let diff = @runtime.ConfigurationDifference::Extra(position=3)
  let j = configuration_difference_json(diff)
  inspect(
    j,
    content=(
      #|Object({"category": String("Topology"), "grade": String("Warn"), "type": String("extra"), "position": Number(3)})
    ),
  )
}

///|
test "configuration_difference_json StationAddressMismatch" {
  let diff = @runtime.ConfigurationDifference::StationAddressMismatch(
    position=0,
    expected=Some(0x1001U),
    actual=Some(0x1002U),
  )
  let j = configuration_difference_json(diff)
  inspect(
    j,
    content=(
      #|Object({"category": String("Topology"), "grade": String("Block"), "type": String("station-address-mismatch"), "position": Number(0), "expected": Number(4097), "actual": Number(4098)})
    ),
  )
}

///|
test "configuration_difference_json AliasAddressMismatch" {
  let diff = @runtime.ConfigurationDifference::AliasAddressMismatch(
    position=1,
    expected=Some(10U),
    actual=None,
  )
  let j = configuration_difference_json(diff)
  inspect(
    j,
    content=(
      #|Object({"category": String("Topology"), "grade": String("Block"), "type": String("alias-address-mismatch"), "position": Number(1), "expected": Number(10), "actual": Null})
    ),
  )
}

///|
test "configuration_difference_json IdentityMismatch" {
  let expected : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
  }
  let actual : @hal.SlaveIdentity = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 99U,
    serial: 4U,
  }
  let diff = @runtime.ConfigurationDifference::IdentityMismatch(
    position=0,
    expected=Some(expected),
    actual=Some(actual),
  )
  let j = configuration_difference_json(diff)
  inspect(
    j,
    content=(
      #|Object({"category": String("Identity"), "grade": String("Block"), "type": String("identity-mismatch"), "position": Number(0), "expected": Object({"vendor_id": Number(1), "product_code": Number(2), "revision": Number(3), "serial": Number(4)}), "actual": Object({"vendor_id": Number(1), "product_code": Number(2), "revision": Number(99), "serial": Number(4)})})
    ),
  )
}

///|
test "configuration_difference_json IdentificationMismatch" {
  let diff = @runtime.ConfigurationDifference::IdentificationMismatch(
    position=2,
    expected=Some(100U),
    actual=Some(200U),
  )
  let j = configuration_difference_json(diff)
  inspect(
    j,
    content=(
      #|Object({"category": String("Configuration"), "grade": String("Block"), "type": String("identification-mismatch"), "position": Number(2), "expected": Number(100), "actual": Number(200)})
    ),
  )
}

///|
test "configuration_difference_json ProcessDataSummaryMismatch" {
  let expected : @runtime.ConfigurationProcessDataSummary = {
    sync_manager_count: 4,
    fmmu_count: 2,
    rx_pdo_count: 1,
    tx_pdo_count: 1,
    mailbox_protocols: None,
    dc_op_mode_count: 0,
    dc_assign_activate_count: 0,
  }
  let actual : @runtime.ConfigurationProcessDataSummary = {
    sync_manager_count: 2,
    fmmu_count: 1,
    rx_pdo_count: 0,
    tx_pdo_count: 0,
    mailbox_protocols: None,
    dc_op_mode_count: 0,
    dc_assign_activate_count: 0,
  }
  let diff = @runtime.ConfigurationDifference::ProcessDataSummaryMismatch(
    position=0,
    expected~,
    actual~,
  )
  let j = configuration_difference_json(diff)
  inspect(
    j,
    content=(
      #|Object({"category": String("Configuration"), "grade": String("Block"), "type": String("process-data-summary-mismatch"), "position": Number(0), "expected": Object({"sync_manager_count": Number(4), "fmmu_count": Number(2), "rx_pdo_count": Number(1), "tx_pdo_count": Number(1), "mailbox_protocols": Null, "dc_op_mode_count": Number(0), "dc_assign_activate_count": Number(0)}), "actual": Object({"sync_manager_count": Number(2), "fmmu_count": Number(1), "rx_pdo_count": Number(0), "tx_pdo_count": Number(0), "mailbox_protocols": Null, "dc_op_mode_count": Number(0), "dc_assign_activate_count": Number(0)})})
    ),
  )
}

///|
test "state_surface_summary_json all Some fields" {
  let summary : @runtime.StateSurfaceSummary = {
    target_state: Some(@protocol.EsmState::Op),
    current_state: Some(@protocol.EsmState::SafeOp),
    final_state: Some(@protocol.EsmState::Op),
    al_state: Some(@protocol.EsmState::Op),
    al_error_flag: Some(true),
    al_status_code: Some(0x001AU),
    wkc: Some(3U),
  }
  let j = state_surface_summary_json(summary)
  inspect(
    j,
    content=(
      #|Object({"target_state": String("Op"), "current_state": String("SafeOp"), "final_state": String("Op"), "al_state": String("Op"), "al_error_flag": True, "al_status_code": Number(26), "wkc": Number(3)})
    ),
  )
}

///|
test "diagnostic_issue_json serializes issue" {
  let issue : @runtime.DiagnosticIssue = {
    source: @runtime.DiagnosticSourceLayer::Registers,
    category: @runtime.DiagnosticCategory::ErrorRegister,
    level: @runtime.DiagnosticLevel::Degrade,
    detail: "CRC errors detected",
  }
  let j = diagnostic_issue_json(issue)
  inspect(
    j,
    content=(
      #|Object({"source": String("Registers"), "category": String("ErrorRegister"), "level": String("Degrade"), "detail": String("CRC errors detected")})
    ),
  )
}

///|
test "configuration_surface_summary_json all Some" {
  let summary : @runtime.ConfigurationSurfaceSummary = {
    slave_count: 3,
    station_addresses: [0x1001U, 0x1002U, 0x1003U],
    expected_source: Some(@runtime.ConfigurationSource::EniImport),
    actual_source: Some(@runtime.ConfigurationSource::OnlineScan),
    validation_grade: Some(@runtime.ValidateGrade::Warn),
    difference_count: 1,
  }
  let j = configuration_surface_summary_json(summary)
  inspect(
    j,
    content=(
      #|Object({"slave_count": Number(3), "station_addresses": Array([Number(4097), Number(4098), Number(4099)]), "expected_source": String("EniImport"), "actual_source": String("OnlineScan"), "validation_grade": String("Warn"), "difference_count": Number(1)})
    ),
  )
}

///|
test "runtime_metrics_summary_json all fields" {
  let summary : @runtime.RuntimeMetricsSummary = {
    cycles: 1000L,
    tx_frames: 2000L,
    rx_frames: 1999L,
    timeouts: 1L,
    retries: 5L,
    wkc_errors: 2L,
    irq_events: 10L,
    dc_delay_updates: 3L,
    emergency_events: 0L,
  }
  let j = runtime_metrics_summary_json(summary)
  inspect(
    j,
    content=(
      #|Object({"cycles": Number(1000), "tx_frames": Number(2000), "rx_frames": Number(1999), "timeouts": Number(1), "retries": Number(5), "wkc_errors": Number(2), "irq_events": Number(10), "dc_delay_updates": Number(3)})
    ),
  )
}

///|
test "diagnostic_surface_json with populated fields" {
  let surface : @runtime.DiagnosticSurface = {
    station_address: Some(0x1001U),
    state_summary: {
      target_state: Some(@protocol.EsmState::Op),
      current_state: Some(@protocol.EsmState::SafeOp),
      final_state: None,
      al_state: None,
      al_error_flag: None,
      al_status_code: None,
      wkc: None,
    },
    configuration_summary: Some({
      slave_count: 1,
      station_addresses: [0x1001U],
      expected_source: Some(@runtime.ConfigurationSource::OfflineConfig),
      actual_source: Some(@runtime.ConfigurationSource::OnlineScan),
      validation_grade: Some(@runtime.ValidateGrade::Pass),
      difference_count: 0,
    }),
    error_register: Some(b'\x02'),
    diagnosis_counter: Some(5U),
    runtime_metrics: Some({
      cycles: 100L,
      tx_frames: 200L,
      rx_frames: 200L,
      timeouts: 0L,
      retries: 0L,
      wkc_errors: 0L,
      irq_events: 0L,
      dc_delay_updates: 0L,
      emergency_events: 0L,
    }),
    issues: [
      {
        source: @runtime.DiagnosticSourceLayer::Registers,
        category: @runtime.DiagnosticCategory::ErrorRegister,
        level: @runtime.DiagnosticLevel::Degrade,
        detail: "CRC errors",
      },
    ],
    overall_level: @runtime.DiagnosticLevel::Degrade,
    monitor_verdicts: Some([
      { name: "link_quality", verdict: @runtime.Verdict::Pass },
      { name: "timing", verdict: @runtime.Verdict::Warn("jitter high") },
    ]),
    overall_verdict: Some(@runtime.Verdict::Fail("degraded")),
    topology_fingerprint: Some({ slave_count: 1, identity_hash: 0x12345678L }),
  }
  let j = diagnostic_surface_json(surface)
  // Use inspect to capture the full JSON
  inspect(
    j,
    content=(
      #|Object({"station": Number(4097), "overall_level": String("Degrade"), "state": Object({"target_state": String("Op"), "current_state": String("SafeOp"), "final_state": Null, "al_state": Null, "al_error_flag": Null, "al_status_code": Null, "wkc": Null}), "configuration": Object({"slave_count": Number(1), "station_addresses": Array([Number(4097)]), "expected_source": String("OfflineConfig"), "actual_source": String("OnlineScan"), "validation_grade": String("Pass"), "difference_count": Number(0)}), "error_register": Number(2), "diagnosis_counter": Number(5), "runtime_metrics": Object({"cycles": Number(100), "tx_frames": Number(200), "rx_frames": Number(200), "timeouts": Number(0), "retries": Number(0), "wkc_errors": Number(0), "irq_events": Number(0), "dc_delay_updates": Number(0)}), "issues": Array([Object({"source": String("Registers"), "category": String("ErrorRegister"), "level": String("Degrade"), "detail": String("CRC errors")})]), "monitor_verdicts": Array([Object({"name": String("link_quality"), "verdict": String("Pass")}), Object({"name": String("timing"), "verdict": String("Warn(\"jitter high\")")})]), "overall_verdict": String("Fail(\"degraded\")"), "topology_fingerprint": Object({"slave_count": Number(1), "identity_hash": Number(305419896)})})
    ),
  )
}

///|
test "validate_report_json with differences" {
  let report : @runtime.ValidateReport = {
    expected_source: @runtime.ConfigurationSource::EniImport,
    actual_source: @runtime.ConfigurationSource::OnlineScan,
    total_expected: 3,
    total_found: 2,
    results: [@runtime.ValidationResult::Ok],
    differences: [@runtime.ConfigurationDifference::Missing(position=2)],
    all_ok: false,
    grade: @runtime.ValidateGrade::Block,
  }
  let j = validate_report_json(report)
  inspect(
    j,
    content=(
      #|Object({"expected_source": String("EniImport"), "actual_source": String("OnlineScan"), "total_expected": Number(3), "total_found": Number(2), "all_ok": False, "grade": String("Block"), "result_count": Number(1), "difference_count": Number(1), "differences": Array([Object({"category": String("Topology"), "grade": String("Block"), "type": String("missing"), "position": Number(2)})])})
    ),
  )
}

///|
test "scan_report_json with slaves" {
  let report : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: Some(10U),
        vendor_id: 0x0002U,
        product_code: 0x004CU,
        revision: 0x0001U,
        serial: 0xABCDU,
        identification: 0U,
      },
    ],
  }
  let j = scan_report_json(report)
  inspect(
    j,
    content=(
      #|Object({"slave_count": Number(1), "slaves": Array([Object({"position": Number(0), "station_address": Number(4097), "alias_address": Number(10), "vendor_id": Number(2), "product_code": Number(76), "revision": Number(1), "serial": Number(43981), "identification": Number(0)})])})
    ),
  )
}

///|
test "request_timeout with Some" {
  let req : PluginRequest = {
    version: "v1",
    command: Scan,
    request_id: "t-1",
    timeout_ns: Some(5_000_000L),
    payload: Json::object({}),
  }
  let t = request_timeout(req)
  assert_eq(t, @hal.Duration(5_000_000L))
}

///|
test "request_timeout with None uses default" {
  let req : PluginRequest = {
    version: "v1",
    command: Scan,
    request_id: "t-2",
    timeout_ns: None,
    payload: Json::object({}),
  }
  let t = request_timeout(req)
  assert_eq(t, @hal.Duration(1_000_000L))
}

///|
test "placeholder_response builds ok=false response" {
  let req : PluginRequest = {
    version: "v1",
    command: Scan,
    request_id: "ph-1",
    timeout_ns: None,
    payload: Json::object({}),
  }
  let resp = placeholder_response(req, "test_error", "something went wrong")
  assert_eq(resp.ok, false)
  assert_eq(resp.error_code, Some("test_error"))
  assert_eq(resp.error_message, Some("something went wrong"))
  assert_eq(resp.request_id, "ph-1")
}

// ===== Batch 25: run_with_mock error path, expected_from_scan, configuration_surface_summary_json None branches =====

///|
test "run_with_mock error path returns error_response" {
  let req : PluginRequest = {
    version: "v1",
    command: Scan,
    request_id: "err-1",
    timeout_ns: None,
    payload: Json::object({}),
  }
  let resp = run_with_mock(req, (_nic, _timeout) => {
    raise @hal.EcError::RecvTimeout
  })
  assert_eq(resp.ok, false)
  assert_eq(resp.request_id, "err-1")
}

///|
test "expected_from_scan converts scan report to configs" {
  let scan : @runtime.ScanReport = {
    slave_count: 1,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 10U,
        product_code: 20U,
        revision: 30U,
        serial: 40U,
        identification: 0U,
      },
    ],
  }
  let configs = expected_from_scan(scan)
  assert_eq(configs.length(), 1)
  assert_eq(configs[0].configured_address, 0x1001U)
  assert_eq(configs[0].position, 0U)
}

///|
test "configuration_surface_summary_json None branches" {
  let summary : @runtime.ConfigurationSurfaceSummary = {
    slave_count: 0,
    station_addresses: [],
    expected_source: None,
    actual_source: None,
    validation_grade: None,
    difference_count: 0,
  }
  let json = configuration_surface_summary_json(summary)
  // All None fields should render as null
  inspect(
    json,
    content=(
      #|Object({"slave_count": Number(0), "station_addresses": Array([]), "expected_source": Null, "actual_source": Null, "validation_grade": Null, "difference_count": Number(0)})
    ),
  )
}

///|
test "diagnostic_surface_json configuration_summary None" {
  let surface : @runtime.DiagnosticSurface = {
    station_address: None,
    state_summary: {
      target_state: None,
      current_state: None,
      final_state: None,
      al_state: None,
      al_error_flag: None,
      al_status_code: None,
      wkc: None,
    },
    configuration_summary: None,
    error_register: None,
    diagnosis_counter: None,
    runtime_metrics: None,
    issues: [],
    overall_level: @runtime.Info,
    monitor_verdicts: None,
    overall_verdict: None,
    topology_fingerprint: None,
  }
  let json = diagnostic_surface_json(surface)
  // configuration should be null in the JSON
  let json_str = json.stringify()
  assert_true(json_str.contains("\"configuration\":null"))
}
