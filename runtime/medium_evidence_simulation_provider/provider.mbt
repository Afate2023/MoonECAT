///|
/// Simulation provider for the medium evidence virtual slot.

///|
pub fn describe_medium_evidence() -> @medium_evidence.MediumEvidenceReport {
  let timing = @simulation.cycle_timing_report(
    1_000_000L,
    0L,
    1_000_100L,
    @simulation.Virtual,
  )
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
      @medium_evidence.MediumEvidenceSection::make(
        stage=@medium_evidence.RuntimeEnvelope,
        title="Runtime envelope metrics",
        source="RunReport + Telemetry + DiagnosticSurface",
        summary="covers cycle counts, timeout/retry/WKC/DC/emergency counters and diagnostic verdict sources for offline/replay analysis; sample virtual jitter_ns=\{timing.jitter_ns}",
        boundary=@medium_evidence.MockSimulation,
      ),
      @medium_evidence.MediumEvidenceSection::make(
        stage=@medium_evidence.OracleArtifact,
        title="Replayable NIC artifact",
        source="hal/mock/NicEventLog + RecordingNic + ReplayNic",
        summary="uses record/replay as the first oracle artifact path; pcap/tshark and certification evidence remain external gates",
        boundary=@medium_evidence.Replay,
        artifact_ref="NicEventLog::to_ndjson_with_header",
      ),
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
