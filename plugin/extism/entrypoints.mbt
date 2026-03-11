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
      validate_report_json(report),
      Json::object({
        "command": Json::string(req.command.to_wire()),
        "backend": Json::string("mock"),
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
    diagnostics: Json::object({ "command": Json::string(req.command.to_wire()) }),
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
