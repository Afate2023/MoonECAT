///|
/// MoonECAT — A modular EtherCAT master library written in MoonBit.
///
/// This root package re-exports the public API surface.
/// Users should import `@mokomoking2501/MoonECAT` as the primary entry point.

///|
/// Library version string.
pub let version : String = "0.2.0"

///|
/// Stable public facade for closed-world ESI profile intake and exact
/// engineering instance binding.
pub using @device_profile {
  type ActivatedDeviceProfile,
  type DeviceProfile,
  type DeviceProfileCandidate,
  type DeviceProfileCatalog,
  type DeviceProfileError,
  type DeviceProfilePin,
  type DeviceProfilePreview,
  type DeviceProfileSelection,
  type MoonEcatDeviceConfig,
  type MoonEcatStartupTarget,
  type ProviderDeviceInstanceBinding,
  convert_esi_xml_to_json_string,
  device_profile_package_id,
  esi_json_document_from_xml,
}
