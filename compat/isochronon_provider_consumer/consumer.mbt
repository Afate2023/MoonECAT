///|
pub struct ProviderBoundaryProbe {
  operation_id : String
  result_schema_id : String
  assurance_scope : String
  policy_digest : String
  frame_context_digest : String
  capture_filter_digest : String
}

///|
pub fn provider_boundary_probe() -> ProviderBoundaryProbe {
  let domain = @clock.DomainId::new(name="external-provider-consumer")
  let context = try! @isochronon_provider.EthernetFrameContext::new(
    resolved_binding_digest="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    current_mac=b"\x02\x10\x20\x30\x40\x50",
    clock_domain=domain,
  )
  let policy = @isochronon_provider.InspectBusIdentityPolicy::verification_default()
  let filter = try! @isochronon_provider.inspect_bus_identity_capture_filter()
  {
    operation_id: @isochronon_provider.inspect_bus_identity_operation_id,
    result_schema_id: @isochronon_provider.inspect_bus_identity_result_schema_id,
    assurance_scope: @assurance.identity_assurance_scope,
    policy_digest: policy.digest(),
    frame_context_digest: context.digest(),
    capture_filter_digest: filter.digest_hex(),
  }
}
