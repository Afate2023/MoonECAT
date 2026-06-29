///|
/// Companion vocabulary for simulation medium evidence.

///|
pub(all) extenum @medium_evidence.MediumEvidenceDiagnostic += {
  SimulationReplayProvider
}

///|
pub fn diagnostic_kind() -> @medium_evidence.MediumEvidenceDiagnostic {
  SimulationReplayProvider
}
