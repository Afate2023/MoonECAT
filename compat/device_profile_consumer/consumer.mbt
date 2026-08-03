///|
pub fn build_external_binding() -> @MoonECAT.ProviderDeviceInstanceBinding raise @MoonECAT.DeviceProfileError {
  let xml = "<?xml version=\"1.0\"?><EtherCATInfo><Vendor><Id>#x5566</Id></Vendor><Descriptions><Devices><Device Physics=\"YY\"><Type ProductCode=\"32\" RevisionNo=\"1\">Drive</Type><Name>Drive</Name></Device></Devices></Descriptions></EtherCATInfo>"
  let candidate = @MoonECAT.DeviceProfileCandidate::from_esi_xml(
    asset_id="vendor/drive.xml",
    declared_source_sha256="a828404905a7f3677f4a6a0926b8474239be4a0fde9278561594e355c8973820",
    @utf8.encode(xml),
  )
  let profile = candidate.profiles()[0]
  let selection = @MoonECAT.DeviceProfileSelection::new(
    source_asset_id=profile.source_asset_id(),
    vendor_id=profile.vendor_id(),
    product_code=profile.product_code(),
    revision=profile.revision(),
    expected_profile_digest=profile.digest(),
  )
  let catalog = @MoonECAT.DeviceProfileCatalog::activate(
    @MoonECAT.DeviceProfilePreview::new([candidate]),
    [selection],
  )
  let activated = catalog.resolve_exact(selection)
  let config = @MoonECAT.MoonEcatDeviceConfig::new(
    configured_station_address=0x1001U,
    cycle_time_ns=1_000_000L,
    watchdog_timeout_ns=10_000_000L,
    startup_target=@MoonECAT.MoonEcatStartupTarget::operational(),
  )
  @MoonECAT.ProviderDeviceInstanceBinding::new(
    device_node_id="axis/1",
    protocol_role_binding_id="ethercat/master/axis-1",
    activated_profile=activated,
    physical_position=0,
    config~,
  )
}
