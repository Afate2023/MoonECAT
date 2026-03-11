///|
pub fn scan_entry(req : PluginRequest) -> PluginResponse {
  placeholder_response(
    req, "not_implemented", "Extism scan adapter is not implemented yet",
  )
}

///|
pub fn validate_entry(req : PluginRequest) -> PluginResponse {
  placeholder_response(
    req, "not_implemented", "Extism validate adapter is not implemented yet",
  )
}

///|
pub fn run_entry(req : PluginRequest) -> PluginResponse {
  placeholder_response(
    req, "not_implemented", "Extism run adapter is not implemented yet",
  )
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
