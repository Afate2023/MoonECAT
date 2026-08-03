///|
fn test_profile_xml(first_serial : UInt?) -> String {
  let serial_text = match first_serial {
    Some(value) => " SerialNo=\"" + value.to_string() + "\""
    None => ""
  }
  "<?xml version=\"1.0\"?>" +
  "<EtherCATInfo><Vendor><Id>#x00005566</Id></Vendor>" +
  "<Descriptions><Devices>" +
  "<Device Physics=\"YY\"><Type ProductCode=\"10\" RevisionNo=\"1\"" +
  serial_text +
  ">DriveA</Type><Name>Drive A</Name></Device>" +
  "<Device Physics=\"YY\"><Type ProductCode=\"20\" RevisionNo=\"2\" SerialNo=\"222\">DriveB</Type><Name>Drive B</Name></Device>" +
  "</Devices></Descriptions></EtherCATInfo>"
}

///|
fn test_sha(value : Bytes) -> String {
  let output = StringBuilder::new()
  for byte in @crypto.sha256(value) {
    output.write_string(byte.to_hex())
  }
  output.to_string()
}

///|
fn test_topology(first_serial : UInt?) -> ExpectedBusTopology {
  let bytes = @utf8.encode(test_profile_xml(first_serial))
  let candidate = try! @device_profile.DeviceProfileCandidate::from_esi_xml(
    asset_id="vendor/test.xml",
    declared_source_sha256=test_sha(bytes),
    bytes,
  )
  let profiles = candidate.profiles()
  let selections = profiles.map(fn(profile) {
    try! @device_profile.DeviceProfileSelection::new(
      source_asset_id=profile.source_asset_id(),
      vendor_id=profile.vendor_id(),
      product_code=profile.product_code(),
      revision=profile.revision(),
      expected_profile_digest=profile.digest(),
    )
  })
  let catalog = try! @device_profile.DeviceProfileCatalog::activate(
    @device_profile.DeviceProfilePreview::new([candidate]),
    selections,
  )
  let activated = catalog.profiles()
  let bindings = activated.mapi(fn(index, profile) {
    let config = try! @device_profile.MoonEcatDeviceConfig::new(
      configured_station_address=(0x1001 + index).reinterpret_as_uint(),
      cycle_time_ns=1_000_000L,
      watchdog_timeout_ns=10_000_000L,
      startup_target=@device_profile.MoonEcatStartupTarget::operational(),
    )
    try! @device_profile.ProviderDeviceInstanceBinding::new(
      device_node_id="axis/" + (index + 1).to_string(),
      protocol_role_binding_id="ethercat/master/axis-" + (index + 1).to_string(),
      activated_profile=profile,
      physical_position=index,
      config~,
    )
  })
  try! ExpectedBusTopology::new(bindings)
}

///|
fn test_domain() -> @clock.DomainId {
  @clock.DomainId::new(name="fixture-monotonic")
}

///|
fn test_mac() -> Bytes {
  b"\x02\x11\x22\x33\x44\x55"
}

///|
fn test_context() -> EthernetFrameContext {
  try! EthernetFrameContext::new(
    resolved_binding_digest="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    current_mac=test_mac(),
    clock_domain=test_domain(),
  )
}

///|
fn test_devices() -> Array[@fixtures.FixtureDeviceIdentity] {
  [
    @fixtures.FixtureDeviceIdentity::new(
      vendor_id=0x5566U,
      product_code=10U,
      revision=1U,
      serial=111U,
    ),
    @fixtures.FixtureDeviceIdentity::new(
      vendor_id=0x5566U,
      product_code=20U,
      revision=2U,
      serial=222U,
    ),
  ]
}

///|
fn run_fixture(
  source : ProviderExecutionSource,
  devices : Array[@fixtures.FixtureDeviceIdentity],
  expected : ExpectedBusTopology,
  inject_failure : Bool,
) -> (InspectBusIdentityResult, @fixtures.IdentityFixtureHarness) {
  let harness = try! @fixtures.IdentityFixtureHarness::new(
    source~,
    domain=test_domain(),
    current_mac=test_mac(),
    devices~,
    emit_echo=true,
    inject_one_poll_failure=inject_failure,
  )
  let deadline = @clock.DomainInstant::new(domain=test_domain(), ns=10_000_000L)
  let result = try! inspect_bus_identity(
    expected~,
    context=test_context(),
    policy=InspectBusIdentityPolicy::verification_default(),
    deadline~,
    port=harness.port(),
  )
  (result, harness)
}

///|
test "sim replay fault and native-contract fixtures preserve one deadline and one outstanding request" {
  let sources = [
    SimulationFixture,
    ReplayFixture,
    FaultFixture,
    NativeContractFixture,
  ]
  for source in sources {
    let (result, harness) = run_fixture(
      source,
      test_devices(),
      test_topology(None),
      source == FaultFixture,
    )
    @debug.assert_eq(result.passes(), true)
    @debug.assert_eq(result.identity_strength(), ModelAndTopology)
    @debug.assert_eq(result.source(), source)
    @debug.assert_eq(harness.source(), source)
    @debug.assert_eq(harness.current_mac(), test_mac())
    @debug.assert_eq(result.live_verified(), false)
    @debug.assert_eq(result.source().live_verified(), false)
    @debug.assert_eq(result.observed()[0].serial(), 111U)
    @debug.assert_eq(result.observed()[1].serial(), 222U)
    @debug.assert_eq(harness.max_outstanding_transactions(), 1)
    @debug.assert_eq(
      result.transaction_count(),
      harness.submitted_frames().length(),
    )
    @debug.assert_eq(result.echoes().is_empty(), false)
    let deadlines = harness.poll_deadlines()
    @debug.assert_eq(deadlines.is_empty(), false)
    for deadline in deadlines {
      @debug.assert_eq(deadline.ns(), 10_000_000L)
      @debug.assert_eq(deadline.domain(), test_domain())
    }
    for frame in harness.submitted_frames() {
      @debug.assert_eq(frame.length(), 60)
      for index in 0..<6 {
        @debug.assert_eq(frame[index + 6], test_mac()[index])
      }
    }
    for register in harness.accessed_registers() {
      @debug.assert_eq(
        register == @protocol.reg_sii_config ||
        register == @protocol.reg_sii_control ||
        register == @protocol.reg_sii_data,
        true,
      )
    }
    for word in harness.accessed_sii_words() {
      @debug.assert_eq(word >= 8U && word <= 14U && word % 2U == 0U, true)
    }
    if source == FaultFixture {
      @debug.assert_eq(
        result.trace().any(fn(event) { event.kind() == RetryScheduled }),
        true,
      )
    }
  }
}

///|
test "all serial pins produce unit identity and result projections are defensive" {
  let (result, _) = run_fixture(
    SimulationFixture,
    test_devices(),
    test_topology(Some(111U)),
    false,
  )
  @debug.assert_eq(result.passes(), true)
  @debug.assert_eq(result.identity_strength(), UnitIdentity)
  let observed = result.observed()
  observed.clear()
  @debug.assert_eq(result.observed().length(), 2)
  let effects = result.effects()
  effects.clear()
  @debug.assert_eq(result.effects().is_empty(), false)
  let trace = result.trace()
  trace.clear()
  @debug.assert_eq(result.trace().is_empty(), false)
  @debug.assert_eq(result.digest().length(), 64)
  @debug.assert_eq(result.schema_id(), inspect_bus_identity_result_schema_id)
  let canonical = result.canonical_bytes()
  @debug.assert_eq(canonical.length() > 64, true)
  @debug.assert_eq(result.canonical_bytes(), canonical)
}

///|
test "extra missing reordered model and serial differences fail complete topology" {
  let expected = test_topology(None)
  let extra_devices = test_devices()
  extra_devices.push(
    @fixtures.FixtureDeviceIdentity::new(
      vendor_id=9U,
      product_code=9U,
      revision=9U,
      serial=9U,
    ),
  )
  let (extra, _) = run_fixture(
    SimulationFixture,
    extra_devices,
    expected,
    false,
  )
  @debug.assert_eq(extra.passes(), false)
  @debug.assert_eq(
    extra.issues().any(fn(issue) { issue is ExtraDevice(2) }),
    true,
  )

  let (missing, _) = run_fixture(
    ReplayFixture,
    [test_devices()[0]],
    test_topology(None),
    false,
  )
  @debug.assert_eq(missing.passes(), false)
  @debug.assert_eq(
    missing.issues().any(fn(issue) { issue is MissingDevice(1) }),
    true,
  )

  let reordered_devices = [test_devices()[1], test_devices()[0]]
  let (reordered, _) = run_fixture(
    NativeContractFixture,
    reordered_devices,
    test_topology(None),
    false,
  )
  @debug.assert_eq(reordered.passes(), false)
  @debug.assert_eq(
    reordered.issues().any(fn(issue) { issue is ReorderedDevice(..) }),
    true,
  )

  let serial_mismatch_devices = test_devices()
  serial_mismatch_devices[1] = @fixtures.FixtureDeviceIdentity::new(
    vendor_id=0x5566U,
    product_code=20U,
    revision=2U,
    serial=999U,
  )
  let (serial_mismatch, _) = run_fixture(
    FaultFixture,
    serial_mismatch_devices,
    test_topology(None),
    false,
  )
  @debug.assert_eq(
    serial_mismatch.issues().any(fn(issue) { issue is UnitSerialMismatchAt(1) }),
    true,
  )

  let model_mismatch_devices = test_devices()
  model_mismatch_devices[0] = @fixtures.FixtureDeviceIdentity::new(
    vendor_id=0x5566U,
    product_code=999U,
    revision=1U,
    serial=111U,
  )
  let (model_mismatch, _) = run_fixture(
    SimulationFixture,
    model_mismatch_devices,
    test_topology(None),
    false,
  )
  @debug.assert_eq(
    model_mismatch
    .issues()
    .any(fn(issue) { issue is ModelOrRevisionMismatchAt(0) }),
    true,
  )
  @debug.assert_eq(model_mismatch.identity_strength(), NoIdentityAssurance)
}

///|
test "expected topology and operation policy reject unbounded or ambiguous inputs" {
  let bindings = test_topology(None).bindings()
  let reversed = [bindings[1], bindings[0]]
  let bad_order : Result[ExpectedBusTopology, IdentityProviderError] = Result::Ok(
    ExpectedBusTopology::new(reversed),
  ) catch {
    error => Result::Err(error)
  }
  guard bad_order is Err(InvalidTopology(_)) else {
    fail("expected non-contiguous ordered topology rejection")
  }
  let bad_policy : Result[InspectBusIdentityPolicy, IdentityProviderError] = Result::Ok(
    InspectBusIdentityPolicy::new(
      max_slaves=65,
      max_wire_transactions=1,
      max_transport_retries=0,
      max_sii_status_polls=1,
      max_sii_nack_retries=0,
      max_ignored_observations=0,
      retry_backoff_ns=0L,
    ),
  ) catch {
    error => Result::Err(error)
  }
  guard bad_policy is Err(InvalidPolicy(_)) else {
    fail("expected bounded policy rejection")
  }
}

///|
test "absolute deadline and transaction budget fail closed" {
  let domain = test_domain()
  let harness = try! @fixtures.IdentityFixtureHarness::new(
    source=SimulationFixture,
    domain~,
    current_mac=test_mac(),
    devices=test_devices(),
  )
  let expired : Result[InspectBusIdentityResult, IdentityProviderError] = Result::Ok(
    inspect_bus_identity(
      expected=test_topology(None),
      context=test_context(),
      policy=InspectBusIdentityPolicy::verification_default(),
      deadline=@clock.DomainInstant::new(domain~, ns=999L),
      port=harness.port(),
    ),
  ) catch {
    error => Result::Err(error)
  }
  guard expired is Err(DeadlineExpired) else {
    fail("expected already-expired absolute deadline rejection")
  }

  let limited_harness = try! @fixtures.IdentityFixtureHarness::new(
    source=NativeContractFixture,
    domain~,
    current_mac=test_mac(),
    devices=test_devices(),
    emit_echo=false,
  )
  let limited_policy = try! InspectBusIdentityPolicy::new(
    max_slaves=64,
    max_wire_transactions=1,
    max_transport_retries=0,
    max_sii_status_polls=1,
    max_sii_nack_retries=0,
    max_ignored_observations=0,
    retry_backoff_ns=0L,
  )
  let limited : Result[InspectBusIdentityResult, IdentityProviderError] = Result::Ok(
    inspect_bus_identity(
      expected=test_topology(None),
      context=test_context(),
      policy=limited_policy,
      deadline=@clock.DomainInstant::new(domain~, ns=100_000L),
      port=limited_harness.port(),
    ),
  ) catch {
    error => Result::Err(error)
  }
  guard limited is Err(TransactionLimitExceeded(1)) else {
    fail("expected exact wire transaction budget rejection")
  }
}

///|
test "ambiguous live transport failure is not retried" {
  let domain = test_domain()
  let submitted : Array[Unit] = []
  let slept : Array[Unit] = []
  let port = IdentityLinkPort::new(
    source=RuntimeUnverified,
    now_fn=fn() { @clock.DomainInstant::new(domain~, ns=1_000L) },
    submit_fn=_ => submitted.push(()),
    poll_fn=_ => raise TransportFailure("ambiguous-live-poll"),
    sleep_until_fn=_ => slept.push(()),
  )
  let result : Result[InspectBusIdentityResult, IdentityProviderError] = Result::Ok(
    inspect_bus_identity(
      expected=test_topology(None),
      context=test_context(),
      policy=InspectBusIdentityPolicy::verification_default(),
      deadline=@clock.DomainInstant::new(domain~, ns=100_000L),
      port~,
    ),
  ) catch {
    error => Result::Err(error)
  }
  guard result is Err(TransportFailure("ambiguous-live-poll")) else {
    fail("expected ambiguous live failure to stop without retry")
  }
  @debug.assert_eq(submitted.length(), 1)
  @debug.assert_eq(slept.length(), 0)
}

///|
test "SII ownership reserves cleanup transaction capacity" {
  let domain = test_domain()
  let harness = try! @fixtures.IdentityFixtureHarness::new(
    source=NativeContractFixture,
    domain~,
    current_mac=test_mac(),
    devices=test_devices(),
    emit_echo=false,
  )
  let policy = try! InspectBusIdentityPolicy::new(
    max_slaves=64,
    max_wire_transactions=4,
    max_transport_retries=1,
    max_sii_status_polls=1,
    max_sii_nack_retries=0,
    max_ignored_observations=0,
    retry_backoff_ns=0L,
  )
  let result : Result[InspectBusIdentityResult, IdentityProviderError] = Result::Ok(
    inspect_bus_identity(
      expected=test_topology(None),
      context=test_context(),
      policy~,
      deadline=@clock.DomainInstant::new(domain~, ns=100_000L),
      port=harness.port(),
    ),
  ) catch {
    error => Result::Err(error)
  }
  guard result is Err(TransactionLimitExceeded(4)) else {
    fail("expected bounded read to stop while retaining cleanup capacity")
  }
  let frames = harness.submitted_frames()
  @debug.assert_eq(frames.length(), 3)
  let cleanup = try! @protocol.EcFrame::decode(frames[2])
  @debug.assert_eq(cleanup.pdus[0].header.command, @protocol.APWR)
  @debug.assert_eq(
    @protocol.address_offset(cleanup.pdus[0].header.address),
    @protocol.reg_sii_config,
  )
  @debug.assert_eq(cleanup.pdus[0].data, b"\x01")
}

///|
test "provider owns exact non-VLAN EtherCAT capture filter asset" {
  let asset = try! inspect_bus_identity_capture_filter()
  @debug.assert_eq(asset.provider_id(), "moonecat")
  @debug.assert_eq(asset.operation_id(), inspect_bus_identity_operation_id)
  @debug.assert_eq(asset.canonical_bpf(), "ether proto 0x88a4 and not vlan")
  @debug.assert_eq(asset.digest_hex().length(), 64)
}
