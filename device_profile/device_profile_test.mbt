///|
fn multi_revision_xml() -> String {
  let xml =
    #|<?xml version="1.0"?>
    #|<EtherCATInfo>
    #|  <Vendor><Id>#x00556666</Id></Vendor>
    #|  <Descriptions>
    #|    <Devices>
    #|      <Device Physics="YY">
    #|        <Type ProductCode="#x00009D08" RevisionNo="#x78B41FA4">EX_CA20</Type>
    #|        <Name>EX_CA20</Name>
    #|        <Profile><ProfileNo>402</ProfileNo></Profile>
    #|      </Device>
    #|      <Device Physics="YY">
    #|        <Type ProductCode="#x00009D08" RevisionNo="#x78B41FA5" SerialNo="#x63">EX_CA20</Type>
    #|        <Name>EX_CA20 next revision</Name>
    #|        <Profile><ProfileNo>402</ProfileNo></Profile>
    #|      </Device>
    #|    </Devices>
    #|  </Descriptions>
    #|</EtherCATInfo>
  xml
}

///|
fn single_profile_xml(product : UInt, revision : UInt) -> String {
  "<?xml version=\"1.0\"?>" +
  "<EtherCATInfo><Vendor><Id>#x00005566</Id></Vendor>" +
  "<Descriptions><Devices><Device Physics=\"YY\">" +
  "<Type ProductCode=\"" +
  product.to_string() +
  "\" RevisionNo=\"" +
  revision.to_string() +
  "\">Device</Type><Name>Device</Name>" +
  "</Device></Devices></Descriptions></EtherCATInfo>"
}

///|
fn test_sha256_hex(value : Bytes) -> String {
  let builder = StringBuilder::new()
  for byte in @crypto.sha256(value) {
    builder.write_string(byte.to_hex())
  }
  builder.to_string()
}

///|
fn candidate(asset_id : String, xml : String) -> DeviceProfileCandidate {
  let bytes = @utf8.encode(xml)
  try! DeviceProfileCandidate::from_esi_xml(
    asset_id~,
    declared_source_sha256=test_sha256_hex(bytes),
    bytes,
  )
}

///|
fn select(profile : DeviceProfile) -> DeviceProfileSelection {
  try! DeviceProfileSelection::new(
    source_asset_id=profile.source_asset_id(),
    vendor_id=profile.vendor_id(),
    product_code=profile.product_code(),
    revision=profile.revision(),
    expected_profile_digest=profile.digest(),
  )
}

///|
test "candidate projects multiple revisions and preserves optional serial" {
  let value = candidate("vendor/drive-a.xml", multi_revision_xml())
  let profiles = value.profiles()
  @debug.assert_eq(profiles.length(), 2)
  @debug.assert_eq(profiles[0].vendor_id(), 0x556666U)
  @debug.assert_eq(profiles[0].product_code(), 0x9D08U)
  @debug.assert_eq(profiles[0].revision(), 0x78B41FA4U)
  @debug.assert_eq(profiles[0].serial(), None)
  @debug.assert_eq(profiles[1].revision(), 0x78B41FA5U)
  @debug.assert_eq(profiles[1].serial(), Some(99U))
  @debug.assert_eq(profiles[1].profile_no(), Some(402U))
  @debug.assert_eq(value.source_sha256().length(), 64)
  @debug.assert_eq(value.digest().length(), 64)
}

///|
test "candidate verifies bytes digest before utf8 and XML projection" {
  let xml_bytes = @utf8.encode(multi_revision_xml())
  let mismatch : Result[DeviceProfileCandidate, DeviceProfileError] = Result::Ok(
    DeviceProfileCandidate::from_esi_xml(
      asset_id="vendor/drive-a.xml",
      declared_source_sha256="0000000000000000000000000000000000000000000000000000000000000000",
      xml_bytes,
    ),
  ) catch {
    error => Result::Err(error)
  }
  guard mismatch is Err(SourceDigestMismatch(_, _, _)) else {
    fail("expected exact source digest mismatch")
  }

  let invalid_utf8 = b"\xFF"
  let utf8_result : Result[DeviceProfileCandidate, DeviceProfileError] = Result::Ok(
    DeviceProfileCandidate::from_esi_xml(
      asset_id="vendor/invalid-utf8.xml",
      declared_source_sha256=test_sha256_hex(invalid_utf8),
      invalid_utf8,
    ),
  ) catch {
    error => Result::Err(error)
  }
  guard utf8_result is Err(InvalidUtf8("vendor/invalid-utf8.xml")) else {
    fail("expected invalid UTF-8 rejection")
  }

  let invalid_xml = @utf8.encode("<EtherCATInfo><Vendor>")
  let xml_result : Result[DeviceProfileCandidate, DeviceProfileError] = Result::Ok(
    DeviceProfileCandidate::from_esi_xml(
      asset_id="vendor/invalid.xml",
      declared_source_sha256=test_sha256_hex(invalid_xml),
      invalid_xml,
    ),
  ) catch {
    error => Result::Err(error)
  }
  guard xml_result is Err(InvalidEsi("vendor/invalid.xml", _)) else {
    fail("expected invalid XML rejection")
  }
}

///|
test "preview is order independent and rejects duplicate asset and identity" {
  let left = candidate("vendor/a.xml", single_profile_xml(10U, 1U))
  let right = candidate("vendor/b.xml", single_profile_xml(20U, 1U))
  let registrations = [left, right]
  let forward = try! DeviceProfilePreview::new(registrations)
  registrations.clear()
  @debug.assert_eq(forward.candidates().length(), 2)
  let returned_profiles = forward.profiles()
  returned_profiles.clear()
  @debug.assert_eq(forward.profiles().length(), 2)
  let reverse = try! DeviceProfilePreview::new([right, left])
  @debug.assert_eq(forward.digest(), reverse.digest())

  let duplicate_asset : Result[DeviceProfilePreview, DeviceProfileError] = Result::Ok(
    DeviceProfilePreview::new([left, left]),
  ) catch {
    error => Result::Err(error)
  }
  guard duplicate_asset is Err(DuplicateAsset("vendor/a.xml")) else {
    fail("expected duplicate asset rejection")
  }

  let same_identity = candidate("vendor/c.xml", single_profile_xml(10U, 1U))
  let duplicate_identity : Result[DeviceProfilePreview, DeviceProfileError] = Result::Ok(
    DeviceProfilePreview::new([left, same_identity]),
  ) catch {
    error => Result::Err(error)
  }
  guard duplicate_identity is Err(DuplicateProfile(_)) else {
    fail("expected ambiguous exact profile rejection")
  }
}

///|
test "activation selects exact closed world and ignores extra unselected profile" {
  let selected_candidate = candidate("vendor/drive-a.xml", multi_revision_xml())
  let profiles = selected_candidate.profiles()
  let selected = select(profiles[0])
  let base_preview = try! DeviceProfilePreview::new([selected_candidate])
  let base_catalog = try! DeviceProfileCatalog::activate(base_preview, [
    selected,
  ])

  let extra = candidate("vendor/extra.xml", single_profile_xml(99U, 1U))
  let expanded_preview = try! DeviceProfilePreview::new([
    selected_candidate, extra,
  ])
  let expanded_catalog = try! DeviceProfileCatalog::activate(expanded_preview, [
    selected,
  ])
  @debug.assert_eq(base_catalog.digest(), expanded_catalog.digest())
  @debug.assert_eq(expanded_catalog.profiles().length(), 1)
  let returned_activated = expanded_catalog.profiles()
  returned_activated.clear()
  @debug.assert_eq(expanded_catalog.profiles().length(), 1)
  @debug.assert_eq(
    (try! expanded_catalog.resolve_exact(selected)).profile().revision(),
    0x78B41FA4U,
  )
}

///|
test "activation rejects missing highest-revision fallback duplicate and digest mismatch" {
  let value = candidate("vendor/drive-a.xml", multi_revision_xml())
  let preview = try! DeviceProfilePreview::new([value])
  let first = value.profiles()[0]
  let missing = try! DeviceProfileSelection::new(
    source_asset_id=first.source_asset_id(),
    vendor_id=first.vendor_id(),
    product_code=first.product_code(),
    revision=0x78B41FA6U,
    expected_profile_digest=first.digest(),
  )
  let missing_result : Result[DeviceProfileCatalog, DeviceProfileError] = Result::Ok(
    DeviceProfileCatalog::activate(preview, [missing]),
  ) catch {
    error => Result::Err(error)
  }
  guard missing_result is Err(MissingProfile(_)) else {
    fail("expected no highest-revision fallback")
  }

  let exact = select(first)
  let duplicate_result : Result[DeviceProfileCatalog, DeviceProfileError] = Result::Ok(
    DeviceProfileCatalog::activate(preview, [exact, exact]),
  ) catch {
    error => Result::Err(error)
  }
  guard duplicate_result is Err(DuplicateSelection(_)) else {
    fail("expected duplicate selection rejection")
  }

  let wrong_digest = try! DeviceProfileSelection::new(
    source_asset_id=first.source_asset_id(),
    vendor_id=first.vendor_id(),
    product_code=first.product_code(),
    revision=first.revision(),
    expected_profile_digest="0000000000000000000000000000000000000000000000000000000000000000",
  )
  let digest_result : Result[DeviceProfileCatalog, DeviceProfileError] = Result::Ok(
    DeviceProfileCatalog::activate(preview, [wrong_digest]),
  ) catch {
    error => Result::Err(error)
  }
  guard digest_result is Err(ProfileDigestMismatch(_, _, _)) else {
    fail("expected selected profile digest mismatch")
  }
}

///|
test "activated profile document is defensive and binding pins placement config" {
  let value = candidate("vendor/drive-a.xml", multi_revision_xml())
  let selected = select(value.profiles()[1])
  let catalog = try! DeviceProfileCatalog::activate(
    DeviceProfilePreview::new([value]),
    [selected],
  )
  let activated = try! catalog.resolve_exact(selected)
  let first_document = try! activated.typed_document()
  first_document.devices.clear()
  let second_document = try! activated.typed_document()
  @debug.assert_eq(second_document.devices.length(), 1)
  @debug.assert_eq(second_document.devices[0].serial, Some(99U))

  let config = try! MoonEcatDeviceConfig::new(
    configured_station_address=0x1001U,
    cycle_time_ns=1_000_000L,
    watchdog_timeout_ns=10_000_000L,
    startup_target=MoonEcatStartupTarget::operational(),
  )
  let binding = try! ProviderDeviceInstanceBinding::new(
    device_node_id="axis/1",
    protocol_role_binding_id="ethercat/master/axis-1",
    activated_profile=activated,
    physical_position=0,
    config~,
  )
  @debug.assert_eq(binding.physical_position(), 0)
  @debug.assert_eq(binding.profile_pin().serial(), Some(99U))
  @debug.assert_eq(binding.config().configured_station_address(), 0x1001U)
  @debug.assert_eq(binding.digest().length(), 64)
}
