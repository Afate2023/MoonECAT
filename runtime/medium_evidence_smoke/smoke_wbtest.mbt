///|
test "simulation provider covers medium sixpack through virtual slot" {
  let report = @medium_evidence_slot.describe_medium_evidence()
  @debug.assert_eq(report.provider_id, "moonecat.runtime.simulation")
  @debug.assert_eq(report.live_claimed, false)
  assert_true(report.covers_sixpack())
  @debug.assert_eq(report.section_count(), 6)
  assert_true(report.has_stage(@medium_evidence.MediumTransport))
  assert_true(report.has_stage(@medium_evidence.NodeModel))
  assert_true(report.has_stage(@medium_evidence.ObjectBinding))
  assert_true(report.has_stage(@medium_evidence.RuntimeEnvelope))
  assert_true(report.has_stage(@medium_evidence.OracleArtifact))
  assert_true(report.has_stage(@medium_evidence.ProfileProtocol))
}

///|
test "companion vocabulary remains external to the provider implementation" {
  let smoke = run_medium_evidence_call_chain_smoke()
  @debug.assert_eq(smoke.provider_kind, "mock-replay-simulation")
  @debug.assert_eq(smoke.diagnostic_label, "external")
  @debug.assert_eq(smoke.live_claimed, false)
  assert_true(smoke.covers_sixpack)
}
