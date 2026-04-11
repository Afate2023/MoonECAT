///|
pub impl Show for CliBackend with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn CliBackend::to_string(self : CliBackend) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RunProgressOutput with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RunProgressOutput::to_string(self : RunProgressOutput) -> String {
  @debug.render(Debug::to_repr(self))
}
