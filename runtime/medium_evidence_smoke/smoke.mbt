///|
/// Smoke report for the medium evidence plugin call chain.

///|
pub(all) struct MediumEvidenceCallChainReport {
  provider_id : String
  provider_kind : String
  section_count : Int
  covers_sixpack : Bool
  diagnostic_label : String
  runtime_envelope_artifact_ref : String
  oracle_artifact_ref : String
  oracle_boundary_label : String
  live_claimed : Bool
} derive(Eq, Debug)

///|
fn section_for_stage(
  report : @medium_evidence.MediumEvidenceReport,
  stage : @medium_evidence.MediumEvidenceStage,
) -> @medium_evidence.MediumEvidenceSection? {
  for section in report.sections {
    if section.stage == stage {
      return Some(section)
    }
  }
  None
}

///|
fn artifact_ref_or_empty(
  section : @medium_evidence.MediumEvidenceSection?,
) -> String {
  match section {
    Some(value) =>
      match value.artifact_ref {
        Some(artifact_ref) => artifact_ref
        None => ""
      }
    None => ""
  }
}

///|
fn boundary_label_or_empty(
  section : @medium_evidence.MediumEvidenceSection?,
) -> String {
  match section {
    Some(value) =>
      @medium_evidence.medium_evidence_boundary_label(value.boundary)
    None => ""
  }
}

///|
pub fn run_medium_evidence_call_chain_smoke() -> MediumEvidenceCallChainReport {
  let report = @medium_evidence_slot.describe_medium_evidence()
  let runtime_envelope = section_for_stage(
    report,
    @medium_evidence.RuntimeEnvelope,
  )
  let oracle_artifact = section_for_stage(
    report,
    @medium_evidence.OracleArtifact,
  )
  {
    provider_id: report.provider_id,
    provider_kind: report.provider_kind,
    section_count: report.section_count(),
    covers_sixpack: report.covers_sixpack(),
    diagnostic_label: @medium_evidence.medium_evidence_diagnostic_label(
      @medium_evidence_simulation_vocab.diagnostic_kind(),
    ),
    runtime_envelope_artifact_ref: artifact_ref_or_empty(runtime_envelope),
    oracle_artifact_ref: artifact_ref_or_empty(oracle_artifact),
    oracle_boundary_label: boundary_label_or_empty(oracle_artifact),
    live_claimed: report.live_claimed,
  }
}

///|
pub fn run_medium_envelope_oracle_smoke() -> @medium_envelope_oracle_evidence.RuntimeEnvelopeOracleEvidenceReport {
  @medium_envelope_oracle_evidence.runtime_envelope_oracle_evidence_report()
}
