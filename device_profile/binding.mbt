///|
/// Exact declared profile identity pinned into an engineering revision.
pub struct DeviceProfilePin {
  priv source_asset_id : String
  priv source_sha256 : String
  priv vendor_id : UInt
  priv product_code : UInt
  priv revision : UInt
  priv serial : UInt?
  priv profile_digest : String
}

///|
fn DeviceProfilePin::from_activated(
  activated : ActivatedDeviceProfile,
) -> DeviceProfilePin {
  let profile = activated.profile()
  {
    source_asset_id: profile.source_asset_id(),
    source_sha256: profile.source_sha256(),
    vendor_id: profile.vendor_id(),
    product_code: profile.product_code(),
    revision: profile.revision(),
    serial: profile.serial(),
    profile_digest: profile.digest(),
  }
}

///|
pub fn DeviceProfilePin::source_asset_id(self : DeviceProfilePin) -> String {
  self.source_asset_id
}

///|
pub fn DeviceProfilePin::source_sha256(self : DeviceProfilePin) -> String {
  self.source_sha256
}

///|
pub fn DeviceProfilePin::vendor_id(self : DeviceProfilePin) -> UInt {
  self.vendor_id
}

///|
pub fn DeviceProfilePin::product_code(self : DeviceProfilePin) -> UInt {
  self.product_code
}

///|
pub fn DeviceProfilePin::revision(self : DeviceProfilePin) -> UInt {
  self.revision
}

///|
pub fn DeviceProfilePin::serial(self : DeviceProfilePin) -> UInt? {
  self.serial
}

///|
pub fn DeviceProfilePin::profile_digest(self : DeviceProfilePin) -> String {
  self.profile_digest
}

///|
pub(all) enum MoonEcatStartupTarget {
  PreOperational
  SafeOperational
  Operational
} derive(Eq, Debug, ToJson)

///|
pub fn MoonEcatStartupTarget::pre_operational() -> MoonEcatStartupTarget {
  PreOperational
}

///|
pub fn MoonEcatStartupTarget::safe_operational() -> MoonEcatStartupTarget {
  SafeOperational
}

///|
pub fn MoonEcatStartupTarget::operational() -> MoonEcatStartupTarget {
  Operational
}

///|
fn MoonEcatStartupTarget::label(self : MoonEcatStartupTarget) -> String {
  match self {
    PreOperational => "pre-operational"
    SafeOperational => "safe-operational"
    Operational => "operational"
  }
}

///|
/// MoonECAT-owned configuration. EtherCAT details remain outside IsoProject.
pub struct MoonEcatDeviceConfig {
  priv configured_station_address : UInt
  priv cycle_time_ns : Int64
  priv watchdog_timeout_ns : Int64
  priv startup_target : MoonEcatStartupTarget
}

///|
pub fn MoonEcatDeviceConfig::new(
  configured_station_address~ : UInt,
  cycle_time_ns~ : Int64,
  watchdog_timeout_ns~ : Int64,
  startup_target~ : MoonEcatStartupTarget,
) -> MoonEcatDeviceConfig raise DeviceProfileError {
  if configured_station_address == 0U || configured_station_address > 0xFFFFU {
    raise InvalidBinding("configured station address must be 1..65535")
  }
  if cycle_time_ns <= 0L {
    raise InvalidBinding("cycle time must be positive")
  }
  if watchdog_timeout_ns < cycle_time_ns {
    raise InvalidBinding("watchdog timeout must cover at least one cycle")
  }
  {
    configured_station_address,
    cycle_time_ns,
    watchdog_timeout_ns,
    startup_target,
  }
}

///|
pub fn MoonEcatDeviceConfig::configured_station_address(
  self : MoonEcatDeviceConfig,
) -> UInt {
  self.configured_station_address
}

///|
pub fn MoonEcatDeviceConfig::cycle_time_ns(
  self : MoonEcatDeviceConfig,
) -> Int64 {
  self.cycle_time_ns
}

///|
pub fn MoonEcatDeviceConfig::watchdog_timeout_ns(
  self : MoonEcatDeviceConfig,
) -> Int64 {
  self.watchdog_timeout_ns
}

///|
pub fn MoonEcatDeviceConfig::startup_target(
  self : MoonEcatDeviceConfig,
) -> MoonEcatStartupTarget {
  self.startup_target
}

///|
/// An engineering instance binding. It contains expected declarations only;
/// observed topology and unit identity belong to AR7M2 evidence.
pub struct ProviderDeviceInstanceBinding {
  priv device_node_id : String
  priv protocol_role_binding_id : String
  priv profile_pin : DeviceProfilePin
  priv physical_position : Int
  priv config : MoonEcatDeviceConfig
  priv digest : String
}

///|
pub fn ProviderDeviceInstanceBinding::new(
  device_node_id~ : String,
  protocol_role_binding_id~ : String,
  activated_profile~ : ActivatedDeviceProfile,
  physical_position~ : Int,
  config~ : MoonEcatDeviceConfig,
) -> ProviderDeviceInstanceBinding raise DeviceProfileError {
  validate_binding_id("device node id", device_node_id)
  validate_binding_id("protocol role binding id", protocol_role_binding_id)
  if physical_position < 0 {
    raise InvalidBinding("physical position must be non-negative")
  }
  let profile_pin = DeviceProfilePin::from_activated(activated_profile)
  let digest = digest_record("moonecat.provider-device-instance-binding.v1", [
    device_node_id,
    protocol_role_binding_id,
    profile_pin.source_asset_id(),
    profile_pin.source_sha256(),
    profile_pin.vendor_id().to_string(),
    profile_pin.product_code().to_string(),
    profile_pin.revision().to_string(),
    option_uint_text(profile_pin.serial()),
    profile_pin.profile_digest(),
    physical_position.to_string(),
    config.configured_station_address().to_string(),
    config.cycle_time_ns().to_string(),
    config.watchdog_timeout_ns().to_string(),
    config.startup_target().label(),
  ])
  {
    device_node_id,
    protocol_role_binding_id,
    profile_pin,
    physical_position,
    config,
    digest,
  }
}

///|
pub fn ProviderDeviceInstanceBinding::device_node_id(
  self : ProviderDeviceInstanceBinding,
) -> String {
  self.device_node_id
}

///|
pub fn ProviderDeviceInstanceBinding::protocol_role_binding_id(
  self : ProviderDeviceInstanceBinding,
) -> String {
  self.protocol_role_binding_id
}

///|
pub fn ProviderDeviceInstanceBinding::profile_pin(
  self : ProviderDeviceInstanceBinding,
) -> DeviceProfilePin {
  self.profile_pin
}

///|
pub fn ProviderDeviceInstanceBinding::physical_position(
  self : ProviderDeviceInstanceBinding,
) -> Int {
  self.physical_position
}

///|
pub fn ProviderDeviceInstanceBinding::config(
  self : ProviderDeviceInstanceBinding,
) -> MoonEcatDeviceConfig {
  self.config
}

///|
pub fn ProviderDeviceInstanceBinding::digest(
  self : ProviderDeviceInstanceBinding,
) -> String {
  self.digest
}

///|
pub fn device_profile_package_id() -> String {
  "mokomoking2501/MoonECAT/device_profile"
}
