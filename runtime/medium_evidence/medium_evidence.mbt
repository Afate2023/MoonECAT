///|
/// MediumEvidenceStage names the six evidence buckets required before an
/// EtherCAT stack can be consumed by a higher-level conformance framework.

///|
pub(all) enum MediumEvidenceStage {
  MediumTransport
  NodeModel
  ObjectBinding
  RuntimeEnvelope
  OracleArtifact
  ProfileProtocol
} derive(Eq, Debug)

///|
pub fn medium_evidence_stage_label(stage : MediumEvidenceStage) -> String {
  match stage {
    MediumTransport => "medium.transport"
    NodeModel => "node.model"
    ObjectBinding => "object.binding"
    RuntimeEnvelope => "runtime.envelope"
    OracleArtifact => "oracle.artifact"
    ProfileProtocol => "profile.protocol"
  }
}

///|
pub(all) enum MediumEvidenceBoundary {
  StaticSchema
  MockSimulation
  Replay
  NativeOffline
  LiveHardware
  ExternalTool
} derive(Eq, Debug)

///|
pub fn medium_evidence_boundary_label(
  boundary : MediumEvidenceBoundary,
) -> String {
  match boundary {
    StaticSchema => "static.schema"
    MockSimulation => "mock.simulation"
    Replay => "replay"
    NativeOffline => "native.offline"
    LiveHardware => "live.hardware"
    ExternalTool => "external.tool"
  }
}

///|
pub(all) extenum MediumEvidenceDiagnostic {
  CoreSchema
}

///|
pub fn medium_evidence_diagnostic_label(
  diagnostic : MediumEvidenceDiagnostic,
) -> String {
  match diagnostic {
    CoreSchema => "core.schema"
    _ => "external"
  }
}

///|
pub(all) struct MediumEvidenceSection {
  stage : MediumEvidenceStage
  title : String
  source : String
  summary : String
  boundary : MediumEvidenceBoundary
  artifact_ref : String?
} derive(Eq, Debug)

///|
pub fn MediumEvidenceSection::make(
  stage~ : MediumEvidenceStage,
  title~ : String,
  source~ : String,
  summary~ : String,
  boundary~ : MediumEvidenceBoundary,
  artifact_ref? : String,
) -> MediumEvidenceSection {
  { stage, title, source, summary, boundary, artifact_ref }
}

///|
pub(all) struct MediumEvidenceReport {
  report_version : String
  provider_id : String
  provider_kind : String
  sections : Array[MediumEvidenceSection]
  live_claimed : Bool
} derive(Eq, Debug)

///|
pub fn MediumEvidenceReport::make(
  report_version~ : String,
  provider_id~ : String,
  provider_kind~ : String,
  sections~ : Array[MediumEvidenceSection],
  live_claimed? : Bool = false,
) -> MediumEvidenceReport {
  { report_version, provider_id, provider_kind, sections, live_claimed }
}

///|
pub fn MediumEvidenceReport::has_stage(
  self : MediumEvidenceReport,
  stage : MediumEvidenceStage,
) -> Bool {
  self.sections.iter().any(fn(section) { section.stage == stage })
}

///|
pub fn MediumEvidenceReport::covers_sixpack(
  self : MediumEvidenceReport,
) -> Bool {
  self.has_stage(MediumTransport) &&
  self.has_stage(NodeModel) &&
  self.has_stage(ObjectBinding) &&
  self.has_stage(RuntimeEnvelope) &&
  self.has_stage(OracleArtifact) &&
  self.has_stage(ProfileProtocol)
}

///|
pub fn MediumEvidenceReport::section_count(self : MediumEvidenceReport) -> Int {
  self.sections.length()
}
