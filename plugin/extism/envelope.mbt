///|
pub(all) enum PluginCommand {
  Scan
  Validate
  Run
} derive(Eq, Debug)

///|
pub(all) struct PluginRequest {
  version : String
  command : PluginCommand
  request_id : String
  timeout_ns : Int64?
  payload : Json
}

///|
pub(all) struct PluginResponse {
  version : String
  request_id : String
  ok : Bool
  error_code : String?
  error_message : String?
  payload : Json
  diagnostics : Json
}

///|
pub fn PluginCommand::to_wire(self : PluginCommand) -> String {
  match self {
    Scan => "scan"
    Validate => "validate"
    Run => "run"
  }
}

///|
pub fn encode_request(req : PluginRequest) -> Json {
  Json::object({
    "version": Json::string(req.version),
    "command": Json::string(req.command.to_wire()),
    "request_id": Json::string(req.request_id),
    "timeout_ns": match req.timeout_ns {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
    "payload": req.payload,
  })
}

///|
pub fn encode_response(resp : PluginResponse) -> Json {
  Json::object({
    "version": Json::string(resp.version),
    "request_id": Json::string(resp.request_id),
    "ok": Json::boolean(resp.ok),
    "error_code": match resp.error_code {
      Some(code) => Json::string(code)
      None => Json::null()
    },
    "error_message": match resp.error_message {
      Some(message) => Json::string(message)
      None => Json::null()
    },
    "payload": resp.payload,
    "diagnostics": resp.diagnostics,
  })
}

///|
pub fn placeholder_response(
  req : PluginRequest,
  error_code : String,
  error_message : String,
) -> PluginResponse {
  {
    version: req.version,
    request_id: req.request_id,
    ok: false,
    error_code: Some(error_code),
    error_message: Some(error_message),
    payload: Json::object({}),
    diagnostics: Json::object({ "command": Json::string(req.command.to_wire()) }),
  }
}
