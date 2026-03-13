///|
pub fn scan_entry(req : PluginRequest) -> PluginResponse {
  run_with_mock(req, (nic, timeout) => {
    let report = @runtime.scan(nic, timeout)
    ok_response(
      req,
      scan_report_json(report),
      Json::object({
        "command": Json::string(req.command.to_wire()),
        "backend": Json::string("mock"),
        "host_capabilities_required": encode_host_contract(
          required_host_contract(req.command),
        ),
      }),
    )
  })
}

///|
pub fn validate_entry(req : PluginRequest) -> PluginResponse {
  run_with_mock(req, (nic, timeout) => {
    let scan_report = @runtime.scan(nic, timeout)
    let expected = expected_from_scan(scan_report)
    let report = @runtime.validate(scan_report, expected)
    ok_response(
      req,
      validate_output_json(scan_report, report),
      Json::object({
        "command": Json::string(req.command.to_wire()),
        "backend": Json::string("mock"),
        "host_capabilities_required": encode_host_contract(
          required_host_contract(req.command),
        ),
      }),
    )
  })
}

///|
pub fn run_entry(req : PluginRequest) -> PluginResponse {
  run_with_mock(req, (nic, timeout) => {
    let scan_report = @runtime.scan(nic, timeout)
    let expected = expected_from_scan(scan_report)
    let pdo_ctx = @protocol.PdoContext::build([], 0U)
    let report = @runtime.run(
      nic,
      @hal.MasterConfig::default(),
      expected,
      pdo_ctx,
      0U,
      10,
      timeout,
    )
    ok_response(
      req,
      run_report_json(report),
      Json::object({
        "command": Json::string(req.command.to_wire()),
        "backend": Json::string("mock"),
        "host_capabilities_required": encode_host_contract(
          required_host_contract(req.command),
        ),
      }),
    )
  })
}

///|
fn run_with_mock(
  req : PluginRequest,
  action : (@mock.MockNic, @hal.Duration) -> PluginResponse raise @hal.EcError,
) -> PluginResponse {
  let nic = @mock.MockNic::new()
  let timeout = request_timeout(req)
  action(nic, timeout) catch {
    err => {
      nic.close()
      error_response(req, err)
    }
  }
}

///|
fn request_timeout(req : PluginRequest) -> @hal.Duration {
  match req.timeout_ns {
    Some(ns) => @hal.Duration(ns)
    None => @hal.Duration(1_000_000L)
  }
}

///|
fn error_response(req : PluginRequest, err : @hal.EcError) -> PluginResponse {
  {
    version: req.version,
    request_id: req.request_id,
    ok: false,
    error_code: Some(ec_error_code(err)),
    error_message: Some(err.to_string()),
    payload: Json::object({}),
    diagnostics: Json::object({
      "command": Json::string(req.command.to_wire()),
      "host_capabilities_required": encode_host_contract(
        required_host_contract(req.command),
      ),
    }),
  }
}

///|
fn ok_response(
  req : PluginRequest,
  payload : Json,
  diagnostics : Json,
) -> PluginResponse {
  {
    version: req.version,
    request_id: req.request_id,
    ok: true,
    error_code: None,
    error_message: None,
    payload,
    diagnostics,
  }
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
fn option_uint_json(value : UInt?) -> Json {
  match value {
    Some(number) => Json::number(number.to_double())
    None => Json::null()
  }
}

///|
fn identity_json(identity : @hal.SlaveIdentity) -> Json {
  Json::object({
    "vendor_id": Json::number(identity.vendor_id.to_double()),
    "product_code": Json::number(identity.product_code.to_double()),
    "revision": Json::number(identity.revision.to_double()),
    "serial": Json::number(identity.serial.to_double()),
  })
}

///|
fn option_identity_json(value : @hal.SlaveIdentity?) -> Json {
  match value {
    Some(identity) => identity_json(identity)
    None => Json::null()
  }
}

///|
fn mailbox_protocols_json(
  protocols : @runtime.ConfigurationMailboxProtocols,
) -> Json {
  Json::object({
    "aoe": Json::boolean(protocols.aoe),
    "coe": Json::boolean(protocols.coe),
    "eoe": Json::boolean(protocols.eoe),
    "foe": Json::boolean(protocols.foe),
    "soe": Json::boolean(protocols.soe),
    "voe": Json::boolean(protocols.voe),
  })
}

///|
fn process_data_summary_json(
  summary : @runtime.ConfigurationProcessDataSummary,
) -> Json {
  Json::object({
    "sync_manager_count": Json::number(summary.sync_manager_count.to_double()),
    "fmmu_count": Json::number(summary.fmmu_count.to_double()),
    "rx_pdo_count": Json::number(summary.rx_pdo_count.to_double()),
    "tx_pdo_count": Json::number(summary.tx_pdo_count.to_double()),
    "mailbox_protocols": match summary.mailbox_protocols {
      Some(protocols) => mailbox_protocols_json(protocols)
      None => Json::null()
    },
    "dc_op_mode_count": Json::number(summary.dc_op_mode_count.to_double()),
    "dc_assign_activate_count": Json::number(
      summary.dc_assign_activate_count.to_double(),
    ),
  })
}

///|
fn configuration_difference_json(
  diff : @runtime.ConfigurationDifference,
) -> Json {
  match diff {
    @runtime.Missing(position~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("missing"),
        "position": Json::number(position.to_double()),
      })
    @runtime.Extra(position~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("extra"),
        "position": Json::number(position.to_double()),
      })
    @runtime.StationAddressMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("station-address-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_uint_json(expected),
        "actual": option_uint_json(actual),
      })
    @runtime.IdentityMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("identity-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_identity_json(expected),
        "actual": option_identity_json(actual),
      })
    @runtime.IdentificationMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("identification-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_uint_json(expected),
        "actual": option_uint_json(actual),
      })
    @runtime.ProcessDataSummaryMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("process-data-summary-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": process_data_summary_json(expected),
        "actual": process_data_summary_json(actual),
      })
  }
}

///|
fn validate_report_json(report : @runtime.ValidateReport) -> Json {
  Json::object({
    "expected_source": Json::string(report.expected_source.to_string()),
    "actual_source": Json::string(report.actual_source.to_string()),
    "total_expected": Json::number(report.total_expected.to_double()),
    "total_found": Json::number(report.total_found.to_double()),
    "all_ok": Json::boolean(report.all_ok),
    "grade": Json::string(report.grade.to_string()),
    "result_count": Json::number(report.results.length().to_double()),
    "difference_count": Json::number(report.differences.length().to_double()),
    "differences": Json::array(
      report.differences.map(fn(diff) { configuration_difference_json(diff) }),
    ),
  })
}

///|
fn validate_output_json(
  scan : @runtime.ScanReport,
  report : @runtime.ValidateReport,
) -> Json {
  Json::object({
    "expected_source": Json::string(report.expected_source.to_string()),
    "actual_source": Json::string(report.actual_source.to_string()),
    "total_expected": Json::number(report.total_expected.to_double()),
    "total_found": Json::number(report.total_found.to_double()),
    "all_ok": Json::boolean(report.all_ok),
    "grade": Json::string(report.grade.to_string()),
    "result_count": Json::number(report.results.length().to_double()),
    "difference_count": Json::number(report.differences.length().to_double()),
    "differences": Json::array(
      report.differences.map(fn(diff) { configuration_difference_json(diff) }),
    ),
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_validate(scan, report),
    ),
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
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_run(report),
    ),
  })
}

///|
fn state_surface_summary_json(summary : @runtime.StateSurfaceSummary) -> Json {
  Json::object({
    "target_state": match summary.target_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "current_state": match summary.current_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "final_state": match summary.final_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_state": match summary.al_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_error_flag": match summary.al_error_flag {
      Some(flag) => Json::boolean(flag)
      None => Json::null()
    },
    "al_status_code": match summary.al_status_code {
      Some(code) => Json::number(code.to_double())
      None => Json::null()
    },
    "wkc": match summary.wkc {
      Some(wkc) => Json::number(wkc.to_double())
      None => Json::null()
    },
  })
}

///|
fn configuration_surface_summary_json(
  summary : @runtime.ConfigurationSurfaceSummary,
) -> Json {
  Json::object({
    "slave_count": Json::number(summary.slave_count.to_double()),
    "station_addresses": Json::array(
      summary.station_addresses.map(fn(station) {
        Json::number(station.to_double())
      }),
    ),
    "expected_source": match summary.expected_source {
      Some(source) => Json::string(source.to_string())
      None => Json::null()
    },
    "actual_source": match summary.actual_source {
      Some(source) => Json::string(source.to_string())
      None => Json::null()
    },
    "validation_grade": match summary.validation_grade {
      Some(grade) => Json::string(grade.to_string())
      None => Json::null()
    },
    "difference_count": Json::number(summary.difference_count.to_double()),
  })
}

///|
fn runtime_metrics_summary_json(
  summary : @runtime.RuntimeMetricsSummary,
) -> Json {
  Json::object({
    "cycles": Json::number(summary.cycles.to_double()),
    "tx_frames": Json::number(summary.tx_frames.to_double()),
    "rx_frames": Json::number(summary.rx_frames.to_double()),
    "timeouts": Json::number(summary.timeouts.to_double()),
    "retries": Json::number(summary.retries.to_double()),
    "wkc_errors": Json::number(summary.wkc_errors.to_double()),
    "irq_events": Json::number(summary.irq_events.to_double()),
    "dc_delay_updates": Json::number(summary.dc_delay_updates.to_double()),
  })
}

///|
fn diagnostic_issue_json(issue : @runtime.DiagnosticIssue) -> Json {
  Json::object({
    "source": Json::string(issue.source.to_string()),
    "category": Json::string(issue.category.to_string()),
    "level": Json::string(issue.level.to_string()),
    "detail": Json::string(issue.detail),
  })
}

///|
fn diagnostic_surface_json(surface : @runtime.DiagnosticSurface) -> Json {
  Json::object({
    "station": match surface.station_address {
      Some(station) => Json::number(station.to_double())
      None => Json::null()
    },
    "overall_level": Json::string(surface.overall_level.to_string()),
    "state": state_surface_summary_json(surface.state_summary),
    "configuration": match surface.configuration_summary {
      Some(summary) => configuration_surface_summary_json(summary)
      None => Json::null()
    },
    "error_register": match surface.error_register {
      Some(value) => Json::number(value.to_uint().to_double())
      None => Json::null()
    },
    "diagnosis_counter": match surface.diagnosis_counter {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
    "runtime_metrics": match surface.runtime_metrics {
      Some(summary) => runtime_metrics_summary_json(summary)
      None => Json::null()
    },
    "issues": Json::array(
      surface.issues.map(fn(issue) { diagnostic_issue_json(issue) }),
    ),
  })
}

///|
pub fn ec_error_code(err : @hal.EcError) -> String {
  match err {
    LinkDown => "link_down"
    SendFailed(_) => "send_failed"
    RecvTimeout => "recv_timeout"
    RecvFailed(_) => "recv_failed"
    InvalidFrame(_) => "invalid_frame"
    InvalidPdu(_) => "invalid_pdu"
    UnexpectedWkc(..) => "unexpected_wkc"
    EsmTransitionFailed(..) => "esm_transition_failed"
    EsmStateError(_) => "esm_state_error"
    MailboxTimeout => "mailbox_timeout"
    MailboxProtocol(_) => "mailbox_protocol"
    SdoAbort(_) => "sdo_abort"
    SiiReadFailed(_) => "sii_read_failed"
    EsiParseFailed(_) => "esi_parse_failed"
    ConfigMismatch(_) => "config_mismatch"
    NotSupported(_) => "not_supported"
    Internal(_) => "internal"
  }
}
