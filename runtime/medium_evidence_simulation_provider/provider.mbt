///|
/// Simulation provider for the medium evidence virtual slot.

///|
pub fn describe_medium_evidence() -> @medium_evidence.MediumEvidenceReport {
  let envelope_oracle = @medium_envelope_oracle_evidence.runtime_envelope_oracle_evidence_report()
  @medium_evidence.MediumEvidenceReport::make(
    report_version="medium-sixpack-evidence-v1",
    provider_id="moonecat.runtime.simulation",
    provider_kind="mock-replay-simulation",
    live_claimed=false,
    sections=[
      @medium_evidence.MediumEvidenceSection::make(
        stage=@medium_evidence.MediumTransport,
        title="EtherCAT medium transport",
        source="protocol + hal/mock/VirtualBus",
        summary="records frame/PDU routing, LRW/LRD/LWR shape, WKC behavior, and DC timing boundaries without claiming live NIC behavior",
        boundary=@medium_evidence.MockSimulation,
      ),
      @medium_evidence.MediumEvidenceSection::make(
        stage=@medium_evidence.NodeModel,
        title="Virtual slave node model",
        source="hal/mock/VirtualSlaveTemplate + runtime configuration",
        summary="captures virtual slave identity, SII/ESI-derived startup data, FMMU/SM and mailbox configuration surfaces",
        boundary=@medium_evidence.MockSimulation,
      ),
      @medium_evidence.MediumEvidenceSection::make(
        stage=@medium_evidence.ObjectBinding,
        title="CoE/PDO object evidence",
        source="mailbox SII/PDO parser + runtime startup preparation",
        summary="keeps index, subindex, channel, direction and process-image offsets as exportable evidence, not as Isochronon ObjectContract values",
        boundary=@medium_evidence.StaticSchema,
      ),
      envelope_oracle.to_runtime_envelope_section(),
      envelope_oracle.to_oracle_artifact_section(),
      @medium_evidence.MediumEvidenceSection::make(
        stage=@medium_evidence.ProfileProtocol,
        title="ESM/CoE/DS402 profile sequence",
        source="runtime startup plan + protocol ESM + mailbox CoE",
        summary="emits neutral profile/protocol event labels that can later be consumed by an adapter without importing conformance monitors",
        boundary=@medium_evidence.StaticSchema,
        artifact_ref="startup_mailbox_commands",
      ),
    ],
  )
}
