///|
/// Smoke report for the medium evidence plugin call chain.

///|
pub(all) struct MediumEvidenceCallChainReport {
  provider_id : String
  provider_kind : String
  section_count : Int
  covers_sixpack : Bool
  diagnostic_label : String
  live_claimed : Bool
} derive(Eq, Debug)

///|
pub fn run_medium_evidence_call_chain_smoke() -> MediumEvidenceCallChainReport {
  let report = @medium_evidence_slot.describe_medium_evidence()
  {
    provider_id: report.provider_id,
    provider_kind: report.provider_kind,
    section_count: report.section_count(),
    covers_sixpack: report.covers_sixpack(),
    diagnostic_label: @medium_evidence.medium_evidence_diagnostic_label(
      @medium_evidence_simulation_vocab.diagnostic_kind(),
    ),
    live_claimed: report.live_claimed,
  }
}
