///|
pub impl Show for CoeService with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn CoeService::to_string(self : CoeService) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SdoCommand with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SdoCommand::to_string(self : SdoCommand) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SdoRequest with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SdoRequest::to_string(self : SdoRequest) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SdoTransaction with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SdoTransaction::to_string(self : SdoTransaction) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SdoResponse with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SdoResponse::to_string(self : SdoResponse) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MailboxCounter with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MailboxCounter::to_string(self : MailboxCounter) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SdoInfoResponse with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SdoInfoResponse::to_string(self : SdoInfoResponse) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SdoInfoObjectDescription with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SdoInfoObjectDescription::to_string(
  self : SdoInfoObjectDescription,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SdoInfoEntryDescription with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SdoInfoEntryDescription::to_string(
  self : SdoInfoEntryDescription,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EmergencyMessage with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EmergencyMessage::to_string(self : EmergencyMessage) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeFrameType with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeFrameType::to_string(self : EoeFrameType) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeResult::to_string(self : EoeResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeResponse with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeResponse::to_string(self : EoeResponse) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FmmuConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FmmuConfig::to_string(self : FmmuConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FmmuDirection with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FmmuDirection::to_string(self : FmmuDirection) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SmConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SmConfig::to_string(self : SmConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SmType with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SmType::to_string(self : SmType) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FoeOpCode with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FoeOpCode::to_string(self : FoeOpCode) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FoeErrorCode with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FoeErrorCode::to_string(self : FoeErrorCode) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for FoeResponse with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn FoeResponse::to_string(self : FoeResponse) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MailboxType with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MailboxType::to_string(self : MailboxType) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MailboxHeader with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MailboxHeader::to_string(self : MailboxHeader) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MailboxRepeatState with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MailboxRepeatState::to_string(self : MailboxRepeatState) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MailboxConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MailboxConfig::to_string(self : MailboxConfig) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SlaveMapping with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SlaveMapping::to_string(self : SlaveMapping) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RmsmState with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RmsmState::to_string(self : RmsmState) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for Rmsm with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn Rmsm::to_string(self : Rmsm) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiCategory with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiCategory::to_string(self : SiiCategory) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiCategoryClass with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiCategoryClass::to_string(self : SiiCategoryClass) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiOverlayScope with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiOverlayScope::to_string(self : SiiOverlayScope) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiOverlayCandidate with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiOverlayCandidate::to_string(self : SiiOverlayCandidate) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiData with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiData::to_string(self : SiiData) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiPreamble with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiPreamble::to_string(self : SiiPreamble) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiStandardMetadata with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiStandardMetadata::to_string(self : SiiStandardMetadata) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiDcClock with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiDcClock::to_string(self : SiiDcClock) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiPdo with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiPdo::to_string(self : SiiPdo) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiPdoEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiPdoEntry::to_string(self : SiiPdoEntry) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiTimeouts with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiTimeouts::to_string(self : SiiTimeouts) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiFmmuEx with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiFmmuEx::to_string(self : SiiFmmuEx) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiSyncUnit with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiSyncUnit::to_string(self : SiiSyncUnit) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiCategoryEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiCategoryEntry::to_string(self : SiiCategoryEntry) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiFullInfo with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiFullInfo::to_string(self : SiiFullInfo) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiGeneral with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiGeneral::to_string(self : SiiGeneral) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SiiSmEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SiiSmEntry::to_string(self : SiiSmEntry) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SoeOpCode with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SoeOpCode::to_string(self : SoeOpCode) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SoeElementFlag with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SoeElementFlag::to_string(self : SoeElementFlag) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SoeResponse with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SoeResponse::to_string(self : SoeResponse) -> String {
  @debug.render(Debug::to_repr(self))
}
