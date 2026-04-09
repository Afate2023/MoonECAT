///|
pub impl Show for MasterConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MasterConfig::to_string(self : MasterConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SlaveIdentity with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SlaveIdentity::to_string(self : SlaveIdentity) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SlavePresence with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SlavePresence::to_string(self : SlavePresence) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SlaveConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SlaveConfig::to_string(self : SlaveConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for Severity with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn Severity::to_string(self : Severity) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DiagnosticEvent with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DiagnosticEvent::to_string(self : DiagnosticEvent) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EcError with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EcError::to_string(self : EcError) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FrameState with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FrameState::to_string(self : FrameState) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FrameRef with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FrameRef::to_string(self : FrameRef) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for Timestamp with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn Timestamp::to_string(self : Timestamp) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for Duration with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn Duration::to_string(self : Duration) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for NicHandle with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn NicHandle::to_string(self : NicHandle) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MutableProcessImage with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MutableProcessImage::to_string(self : MutableProcessImage) -> String {
  @debug.render(Debug::to_repr(self))
}
