///|
pub impl Show for SimTime with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SimTime::to_string(self : SimTime) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SimStepResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SimStepResult::to_string(self : SimStepResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ProcessImageSlice with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ProcessImageSlice::to_string(self : ProcessImageSlice) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for TaskDescriptor with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn TaskDescriptor::to_string(self : TaskDescriptor) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for TaskSchedule with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn TaskSchedule::to_string(self : TaskSchedule) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for CoSimConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn CoSimConfig::to_string(self : CoSimConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DriftCompensationGains with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DriftCompensationGains::to_string(
  self : DriftCompensationGains,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for BridgeTransport with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn BridgeTransport::to_string(self : BridgeTransport) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ExternalBridgeConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ExternalBridgeConfig::to_string(self : ExternalBridgeConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for BridgeState with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn BridgeState::to_string(self : BridgeState) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ClockDomain with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ClockDomain::to_string(self : ClockDomain) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for TimebaseSync with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn TimebaseSync::to_string(self : TimebaseSync) -> String {
  @debug.render(Debug::to_repr(self))
}
