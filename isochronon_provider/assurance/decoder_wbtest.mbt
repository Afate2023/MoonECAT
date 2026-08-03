///|
fn assurance_sha(value : Bytes) -> String {
  let output = StringBuilder::new()
  for byte in @crypto.sha256(value) {
    output.write_string(byte.to_hex())
  }
  output.to_string()
}

///|
fn assurance_expected() -> @isochronon_provider.ExpectedBusTopology {
  let bytes = @utf8.encode(
    "<EtherCATInfo><Vendor><Id>7</Id></Vendor><Descriptions><Devices>" +
    "<Device Physics=\"YY\"><Type ProductCode=\"8\" RevisionNo=\"9\">D</Type>" +
    "<Name>D</Name></Device></Devices></Descriptions></EtherCATInfo>",
  )
  let candidate = try! @device_profile.DeviceProfileCandidate::from_esi_xml(
    asset_id="vendor/assurance.xml",
    declared_source_sha256=assurance_sha(bytes),
    bytes,
  )
  let profile = candidate.profiles()[0]
  let selection = try! @device_profile.DeviceProfileSelection::new(
    source_asset_id=profile.source_asset_id(),
    vendor_id=profile.vendor_id(),
    product_code=profile.product_code(),
    revision=profile.revision(),
    expected_profile_digest=profile.digest(),
  )
  let catalog = try! @device_profile.DeviceProfileCatalog::activate(
    @device_profile.DeviceProfilePreview::new([candidate]),
    [selection],
  )
  let config = try! @device_profile.MoonEcatDeviceConfig::new(
    configured_station_address=0x1001U,
    cycle_time_ns=1_000_000L,
    watchdog_timeout_ns=10_000_000L,
    startup_target=@device_profile.MoonEcatStartupTarget::operational(),
  )
  try! @isochronon_provider.ExpectedBusTopology::new([
    try! @device_profile.ProviderDeviceInstanceBinding::new(
      device_node_id="axis/1",
      protocol_role_binding_id="ethercat/master/axis-1",
      activated_profile=catalog.profiles()[0],
      physical_position=0,
      config~,
    ),
  ])
}

///|
fn assurance_result(
  product_code : UInt,
) -> @isochronon_provider.InspectBusIdentityResult {
  let domain = @clock.DomainId::new(name="assurance-fixture")
  let mac = b"\x02\x01\x02\x03\x04\x05"
  let harness = try! @fixtures.IdentityFixtureHarness::new(
    source=@isochronon_provider.ReplayFixture,
    domain~,
    current_mac=mac,
    devices=[
      @fixtures.FixtureDeviceIdentity::new(
        vendor_id=7U,
        product_code~,
        revision=9U,
        serial=10U,
      ),
    ],
  )
  try! @isochronon_provider.inspect_bus_identity(
    expected=assurance_expected(),
    context=@isochronon_provider.EthernetFrameContext::new(
      resolved_binding_digest="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      current_mac=mac,
      clock_domain=domain,
    ),
    policy=@isochronon_provider.InspectBusIdentityPolicy::verification_default(),
    deadline=@clock.DomainInstant::new(domain~, ns=1_000_000L),
    port=harness.port(),
  )
}

///|
test "assurance decoder normalizes typed facts but never self-issues a claim" {
  let matched_result = assurance_result(8U)
  let matched = decode_identity_assurance(matched_result)
  @debug.assert_eq(matched.scope(), identity_assurance_scope)
  @debug.assert_eq(
    matched.disposition(),
    ProtocolFactsMatchAwaitingExternalEvidence,
  )
  @debug.assert_eq(
    matched.identity_strength(),
    @isochronon_provider.ModelAndTopology,
  )
  @debug.assert_eq(matched.external_evidence_complete(), false)
  @debug.assert_eq(matched.claim_eligible(), false)
  @debug.assert_eq(matched.result_digest().length(), 64)
  @debug.assert_eq(matched.expected_count(), 1)
  @debug.assert_eq(matched.transaction_count() > 0, true)
  let decoded_from_bytes = try! decode_identity_assurance_artifact(
    matched_result.canonical_bytes(),
    expected_digest=matched_result.digest(),
  )
  @debug.assert_eq(decoded_from_bytes.result_digest(), matched.result_digest())

  let wrong_digest : Result[
    DecodedIdentityAssurance,
    IdentityAssuranceDecodeError,
  ] = Result::Ok(
    decode_identity_assurance_artifact(
      matched_result.canonical_bytes(),
      expected_digest="0000000000000000000000000000000000000000000000000000000000000000",
    ),
  ) catch {
    error => Result::Err(error)
  }
  guard wrong_digest is Err(InvalidIdentityResultArtifact(_)) else {
    fail("expected canonical result digest mismatch rejection")
  }

  let rejected = decode_identity_assurance(assurance_result(99U))
  @debug.assert_eq(rejected.disposition(), ProtocolFactsRejected)
  @debug.assert_eq(rejected.issue_count(), 1)
  @debug.assert_eq(rejected.claim_eligible(), false)
}
