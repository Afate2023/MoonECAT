///|
pub impl Show for AddressType with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn AddressType::to_string(self : AddressType) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DcInitResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DcInitResult::to_string(self : DcInitResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DcPortTimes with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DcPortTimes::to_string(self : DcPortTimes) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SlaveInfo with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SlaveInfo::to_string(self : SlaveInfo) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ScanResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ScanResult::to_string(self : ScanResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsmState with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsmState::to_string(self : EsmState) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for AddressMode with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn AddressMode::to_string(self : AddressMode) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsmStatusSnapshot with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsmStatusSnapshot::to_string(self : EsmStatusSnapshot) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsmTimeoutPolicy with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsmTimeoutPolicy::to_string(self : EsmTimeoutPolicy) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SmWatchdogConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SmWatchdogConfig::to_string(self : SmWatchdogConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for PortErrorCounters with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PortErrorCounters::to_string(self : PortErrorCounters) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DlErrorCounters with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DlErrorCounters::to_string(self : DlErrorCounters) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EcFrame with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EcFrame::to_string(self : EcFrame) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ProcessImage with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ProcessImage::to_string(self : ProcessImage) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for PdoMapping with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PdoMapping::to_string(self : PdoMapping) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for PdoContext with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PdoContext::to_string(self : PdoContext) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for PdoExchangeResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PdoExchangeResult::to_string(self : PdoExchangeResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EcCommand with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EcCommand::to_string(self : EcCommand) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for PduHeader with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PduHeader::to_string(self : PduHeader) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for Pdu with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn Pdu::to_string(self : Pdu) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FrameBuilder with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FrameBuilder::to_string(self : FrameBuilder) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MutablePdoContext with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MutablePdoContext::to_string(self : MutablePdoContext) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsmStateRequestObservation with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsmStateRequestObservation::to_string(
  self : EsmStateRequestObservation,
) -> String {
  @debug.render(Debug::to_repr(self))
}
