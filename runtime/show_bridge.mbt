///|
pub impl Show for QualityTrend with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn QualityTrend::to_string(self : QualityTrend) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for QualityGrade with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn QualityGrade::to_string(self : QualityGrade) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ConfigurationSource with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ConfigurationSource::to_string(self : ConfigurationSource) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ConfigurationSlave with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ConfigurationSlave::to_string(self : ConfigurationSlave) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ConfigurationMailboxProtocols with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ConfigurationMailboxProtocols::to_string(
  self : ConfigurationMailboxProtocols,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ConfigurationProcessDataSummary with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ConfigurationProcessDataSummary::to_string(
  self : ConfigurationProcessDataSummary,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ConfigurationModel with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ConfigurationModel::to_string(self : ConfigurationModel) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ConfigurationDifference with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ConfigurationDifference::to_string(
  self : ConfigurationDifference,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ConfigurationComparisonReport with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ConfigurationComparisonReport::to_string(
  self : ConfigurationComparisonReport,
) -> String {
  @debug.render(Debug::to_repr(self))
}

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
pub impl Show for CoSimConfig with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn CoSimConfig::to_string(self : CoSimConfig) -> String {
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
pub impl Show for PerfTrend with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn PerfTrend::to_string(self : PerfTrend) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SlaveDiagnosis with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SlaveDiagnosis::to_string(self : SlaveDiagnosis) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DiagnosticLevel with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DiagnosticLevel::to_string(self : DiagnosticLevel) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DiagnosticSourceLayer with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DiagnosticSourceLayer::to_string(self : DiagnosticSourceLayer) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DiagnosticCategory with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DiagnosticCategory::to_string(self : DiagnosticCategory) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for StateSurfaceSummary with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn StateSurfaceSummary::to_string(self : StateSurfaceSummary) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ConfigurationSurfaceSummary with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ConfigurationSurfaceSummary::to_string(
  self : ConfigurationSurfaceSummary,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RuntimeMetricsSummary with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RuntimeMetricsSummary::to_string(self : RuntimeMetricsSummary) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DiagnosticIssue with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DiagnosticIssue::to_string(self : DiagnosticIssue) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DiagnosticSurface with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DiagnosticSurface::to_string(self : DiagnosticSurface) -> String {
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
pub impl Show for DriftCompensator with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DriftCompensator::to_string(self : DriftCompensator) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DriftCompensationReport with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DriftCompensationReport::to_string(
  self : DriftCompensationReport,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for QueueEndpoint with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn QueueEndpoint::to_string(self : QueueEndpoint) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeEndpointFrame with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeEndpointFrame::to_string(self : EoeEndpointFrame) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeRelayDirection with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeRelayDirection::to_string(self : EoeRelayDirection) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeRelayFrame with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeRelayFrame::to_string(self : EoeRelayFrame) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeRelayStats with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeRelayStats::to_string(self : EoeRelayStats) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeRelay with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeRelay::to_string(self : EoeRelay) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeReassemblyBuffer with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeReassemblyBuffer::to_string(self : EoeReassemblyBuffer) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeStationContext with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeStationContext::to_string(self : EoeStationContext) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeReceivedFrame with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeReceivedFrame::to_string(self : EoeReceivedFrame) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EoeSwitch with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EoeSwitch::to_string(self : EoeSwitch) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonMailbox with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonMailbox::to_string(self : EsiJsonMailbox) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonSmEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonSmEntry::to_string(self : EsiJsonSmEntry) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonPdoEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonPdoEntry::to_string(self : EsiJsonPdoEntry) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonPdo with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonPdo::to_string(self : EsiJsonPdo) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonDcMode with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonDcMode::to_string(self : EsiJsonDcMode) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonSelectedModule with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonSelectedModule::to_string(self : EsiJsonSelectedModule) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonInitCommand with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonInitCommand::to_string(self : EsiJsonInitCommand) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonDevice with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonDevice::to_string(self : EsiJsonDevice) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonModule with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonModule::to_string(self : EsiJsonModule) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for EsiJsonDocument with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn EsiJsonDocument::to_string(self : EsiJsonDocument) -> String {
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
pub impl Show for ExternalProcessBridge with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ExternalProcessBridge::to_string(self : ExternalProcessBridge) -> String {
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

///|
pub impl Show for MasterOdDataType with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MasterOdDataType::to_string(self : MasterOdDataType) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MasterOdAccess with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MasterOdAccess::to_string(self : MasterOdAccess) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MasterOdEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MasterOdEntry::to_string(self : MasterOdEntry) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MasterOdValue with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MasterOdValue::to_string(self : MasterOdValue) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MasterObjectDictionary with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MasterObjectDictionary::to_string(
  self : MasterObjectDictionary,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MasterIdentity with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MasterIdentity::to_string(self : MasterIdentity) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MultiRateAnalysis with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MultiRateAnalysis::to_string(self : MultiRateAnalysis) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RunPhase with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RunPhase::to_string(self : RunPhase) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RunFault with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RunFault::to_string(self : RunFault) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RunLoopSettings with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RunLoopSettings::to_string(self : RunLoopSettings) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RunReport with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RunReport::to_string(self : RunReport) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for StartupCommandTransition with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn StartupCommandTransition::to_string(
  self : StartupCommandTransition,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for StartupMailboxCommand with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn StartupMailboxCommand::to_string(self : StartupMailboxCommand) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for StationStartupMailboxPlan with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn StationStartupMailboxPlan::to_string(
  self : StationStartupMailboxPlan,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for OperationalStartupStep with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn OperationalStartupStep::to_string(
  self : OperationalStartupStep,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for StartupRecoveryStrategy with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn StartupRecoveryStrategy::to_string(
  self : StartupRecoveryStrategy,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SmWatchdogValidation with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SmWatchdogValidation::to_string(self : SmWatchdogValidation) -> String {
  @debug.render(Debug::to_repr(self))
}

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
pub impl Show for Runtime with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn Runtime::to_string(self : Runtime) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RunProgress with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RunProgress::to_string(self : RunProgress) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ScanReport with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ScanReport::to_string(self : ScanReport) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for SlaveReport with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn SlaveReport::to_string(self : SlaveReport) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ScanStationAddressStrategy with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ScanStationAddressStrategy::to_string(
  self : ScanStationAddressStrategy,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ObservedSlaveAddress with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ObservedSlaveAddress::to_string(self : ObservedSlaveAddress) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RunMode with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RunMode::to_string(self : RunMode) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for RuntimeState with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn RuntimeState::to_string(self : RuntimeState) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for Telemetry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn Telemetry::to_string(self : Telemetry) -> String {
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
pub impl Show for ClockDomain with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ClockDomain::to_string(self : ClockDomain) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for DomainTimestamp with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn DomainTimestamp::to_string(self : DomainTimestamp) -> String {
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

///|
pub impl Show for CycleTimingReport with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn CycleTimingReport::to_string(self : CycleTimingReport) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for TopologyFingerprint with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn TopologyFingerprint::to_string(self : TopologyFingerprint) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for TopologyFingerprintMatch with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn TopologyFingerprintMatch::to_string(
  self : TopologyFingerprintMatch,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for LinkGrade with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn LinkGrade::to_string(self : LinkGrade) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ValidationResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ValidationResult::to_string(self : ValidationResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ValidateGrade with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ValidateGrade::to_string(self : ValidateGrade) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ValidateDifferenceCategory with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ValidateDifferenceCategory::to_string(
  self : ValidateDifferenceCategory,
) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ValidateReport with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ValidateReport::to_string(self : ValidateReport) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for Verdict with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn Verdict::to_string(self : Verdict) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for MonitorResult with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn MonitorResult::to_string(self : MonitorResult) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for ReportEntry with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn ReportEntry::to_string(self : ReportEntry) -> String {
  @debug.render(Debug::to_repr(self))
}

///|
pub impl Show for VerificationReport with output(self, logger) {
  logger.write_string(@debug.render(Debug::to_repr(self)))
}

///|
pub fn VerificationReport::to_string(self : VerificationReport) -> String {
  @debug.render(Debug::to_repr(self))
}
