///|
pub impl Show for CycleResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn CycleResult::to_string(self : CycleResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DcState with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DcState::to_string(self : DcState) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for CycleSnapshot with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn CycleSnapshot::to_string(self : CycleSnapshot) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for CycleDirective with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn CycleDirective::to_string(self : CycleDirective) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for HilSessionSummary with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn HilSessionSummary::to_string(self : HilSessionSummary) -> String {
  @debug.render(Debug::to_repr(self))
}
