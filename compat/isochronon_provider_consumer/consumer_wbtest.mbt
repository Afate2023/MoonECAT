///|
test "external package consumes provider and assurance public boundaries" {
  let probe = provider_boundary_probe()
  @debug.assert_eq(probe.operation_id, "inspect-bus-identity")
  @debug.assert_eq(
    probe.result_schema_id, "moonecat.inspect-bus-identity.result.v1",
  )
  @debug.assert_eq(
    probe.assurance_scope, "moonecat.inspect-bus-identity",
  )
  @debug.assert_eq(probe.policy_digest.length(), 64)
  @debug.assert_eq(probe.frame_context_digest.length(), 64)
  @debug.assert_eq(probe.capture_filter_digest.length(), 64)
}
