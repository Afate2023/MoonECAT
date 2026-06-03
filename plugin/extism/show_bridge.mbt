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
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PluginRequest::to_string(self : PluginRequest) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for PluginResponse with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PluginResponse::to_string(self : PluginResponse) -> String {
  @debug.render(Debug::to_repr(self))
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
