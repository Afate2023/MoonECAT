///|
pub impl Show for PluginCommand with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PluginCommand::to_string(self : PluginCommand) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for PluginRequest with output(self, logger) {
  logger.write_string("PluginRequest::{")
  logger.write_string(" version: ")
  Show::output(self.version, logger)
  logger.write_string(", command: ")
  Show::output(self.command, logger)
  logger.write_string(", request_id: ")
  Show::output(self.request_id, logger)
  logger.write_string(", timeout_ns: ")
  Show::output(self.timeout_ns, logger)
  logger.write_string(", payload: ")
  Show::output(self.payload, logger)
  logger.write_string(" }")
}

///|
pub fn PluginRequest::to_string(self : PluginRequest) -> String {
  let buf = StringBuilder::new()
  Show::output(self, buf)
  buf.to_string()
}

///|
pub impl Show for PluginResponse with output(self, logger) {
  logger.write_string("PluginResponse::{")
  logger.write_string(" version: ")
  Show::output(self.version, logger)
  logger.write_string(", request_id: ")
  Show::output(self.request_id, logger)
  logger.write_string(", ok: ")
  Show::output(self.ok, logger)
  logger.write_string(", error_code: ")
  Show::output(self.error_code, logger)
  logger.write_string(", error_message: ")
  Show::output(self.error_message, logger)
  logger.write_string(", payload: ")
  Show::output(self.payload, logger)
  logger.write_string(", diagnostics: ")
  Show::output(self.diagnostics, logger)
  logger.write_string(" }")
}

///|
pub fn PluginResponse::to_string(self : PluginResponse) -> String {
  let buf = StringBuilder::new()
  Show::output(self, buf)
  buf.to_string()
}

///|
pub impl Show for HostCapabilityContract with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn HostCapabilityContract::to_string(
  self : HostCapabilityContract,
) -> String {
  @debug.render(Debug::to_repr(self))
}
