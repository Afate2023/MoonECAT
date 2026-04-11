///|
pub impl Show for NicEvent with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn NicEvent::to_string(self : NicEvent) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for NicEventLog with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn NicEventLog::to_string(self : NicEventLog) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FaultType with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FaultType::to_string(self : FaultType) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FaultSchedule with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FaultSchedule::to_string(self : FaultSchedule) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FaultRule with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FaultRule::to_string(self : FaultRule) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FaultInjector with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FaultInjector::to_string(self : FaultInjector) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FuzzRng with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FuzzRng::to_string(self : FuzzRng) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FuzzResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FuzzResult::to_string(self : FuzzResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ProtocolDeviation with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ProtocolDeviation::to_string(self : ProtocolDeviation) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ExpectedVerdict with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ExpectedVerdict::to_string(self : ExpectedVerdict) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ScenarioPassCondition with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ScenarioPassCondition::to_string(self : ScenarioPassCondition) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for Scenario with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn Scenario::to_string(self : Scenario) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ObservedVerdict with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ObservedVerdict::to_string(self : ObservedVerdict) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ScenarioResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ScenarioResult::to_string(self : ScenarioResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for VirtualBus with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn VirtualBus::to_string(self : VirtualBus) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for OdEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn OdEntry::to_string(self : OdEntry) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for OdAccess with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn OdAccess::to_string(self : OdAccess) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for VirtualMailbox with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn VirtualMailbox::to_string(self : VirtualMailbox) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EmergencyEvent with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EmergencyEvent::to_string(self : EmergencyEvent) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for VirtualSlave with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn VirtualSlave::to_string(self : VirtualSlave) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FmmuEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FmmuEntry::to_string(self : FmmuEntry) -> String {
  @debug.render(Debug::to_repr(self))
}
