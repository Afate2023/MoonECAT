///|
/// SII category types (Slave Information Interface).
pub(all) enum SiiCategory {
  Strings
  DataTypes
  General
  Fmmu
  SyncManager
  FmmuEx
  SyncUnit
  TxPdo
  RxPdo
  Dc
  Timeouts
  Dictionary
  Hardware
  VendorInformation
  Images
  Raw
} derive(Eq, Show)

///|
/// Stable export classification for SII categories.
pub(all) enum SiiCategoryClass {
  StandardKnown
  StandardUnknown
  DeviceSpecific
  VendorSpecific
  ApplicationSpecific
} derive(Eq, Show)

///|
/// Dispatch scope for future typed overlays on raw SII categories.
pub(all) enum SiiOverlayScope {
  DeviceSpecific
  VendorSpecific
  ApplicationSpecific
} derive(Eq, Show)

///|
pub(all) struct SiiOverlayCandidate {
  scope : SiiOverlayScope
  type_code : UInt
  data : Bytes
} derive(Eq, Show)

///|
pub fn SiiCategoryClass::label(self : SiiCategoryClass) -> String {
  match self {
    StandardKnown => "standard-known"
    StandardUnknown => "standard-unknown"
    DeviceSpecific => "device-specific"
    VendorSpecific => "vendor-specific"
    ApplicationSpecific => "application-specific"
  }
}

///|
pub fn SiiOverlayScope::label(self : SiiOverlayScope) -> String {
  match self {
    DeviceSpecific => "device-specific"
    VendorSpecific => "vendor-specific"
    ApplicationSpecific => "application-specific"
  }
}

///|
fn hex_digit(value : UInt) -> String {
  match value {
    0U => "0"
    1U => "1"
    2U => "2"
    3U => "3"
    4U => "4"
    5U => "5"
    6U => "6"
    7U => "7"
    8U => "8"
    9U => "9"
    10U => "A"
    11U => "B"
    12U => "C"
    13U => "D"
    14U => "E"
    _ => "F"
  }
}

///|
fn format_hex4(value : UInt) -> String {
  hex_digit((value >> 12) & 0x0FU) +
  hex_digit((value >> 8) & 0x0FU) +
  hex_digit((value >> 4) & 0x0FU) +
  hex_digit(value & 0x0FU)
}

///|
pub fn SiiOverlayCandidate::dispatch_key(self : SiiOverlayCandidate) -> String {
  self.scope.label() + ":" + format_hex4(self.type_code)
}

///|
pub fn SiiCategoryEntry::category_class(
  self : SiiCategoryEntry,
) -> SiiCategoryClass {
  if self.category != Raw {
    return StandardKnown
  }
  let type_code = self.type_code
  if type_code >= 1U && type_code <= 9U {
    return DeviceSpecific
  }
  if type_code >= 0x2000U && type_code <= 0x2FFFU {
    return ApplicationSpecific
  }
  if (type_code >= 0x0800U && type_code <= 0x1FFFU) ||
    (type_code >= 0x3000U && type_code <= 0xFFFEU) {
    return VendorSpecific
  }
  StandardUnknown
}

///|
pub fn SiiCategoryEntry::overlay_candidate(
  self : SiiCategoryEntry,
) -> SiiOverlayCandidate? {
  match self.category_class() {
    DeviceSpecific =>
      Some({
        scope: SiiOverlayScope::DeviceSpecific,
        type_code: self.type_code,
        data: self.data,
      })
    VendorSpecific =>
      Some({
        scope: SiiOverlayScope::VendorSpecific,
        type_code: self.type_code,
        data: self.data,
      })
    ApplicationSpecific =>
      Some({
        scope: SiiOverlayScope::ApplicationSpecific,
        type_code: self.type_code,
        data: self.data,
      })
    _ => None
  }
}

///|
/// Basic SII data read from slave EEPROM.
pub(all) struct SiiData {
  vendor_id : UInt
  product_code : UInt
  revision : UInt
  serial : UInt
  bootstrap_rx_offset : UInt
  bootstrap_rx_size : UInt
  bootstrap_tx_offset : UInt
  bootstrap_tx_size : UInt
  mailbox_rx_offset : UInt
  mailbox_rx_size : UInt
  mailbox_tx_offset : UInt
  mailbox_tx_size : UInt
  mailbox_protocols : UInt
  firmware_version : UInt
  hardware_version : UInt
  production_date_raw : UInt
  pdi_control_1 : Byte
  esc_config_b0 : Byte
  pdi_config_1 : UInt
  pdi_config_1_ext : UInt
  esc_config_b4 : UInt
  esc_config_b5 : UInt
  esc_config_b6 : UInt
  checksum_b : UInt
  esc_config_b_present : Bool
} derive(Eq, Show)

///|
pub fn SiiData::production_year(self : SiiData) -> Int {
  2000 + (self.production_date_raw & 0x7FU).reinterpret_as_int()
}

///|
pub fn SiiData::production_weekday(self : SiiData) -> Int {
  ((self.production_date_raw >> 7) & 0x07U).reinterpret_as_int()
}

///|
pub fn SiiData::production_week(self : SiiData) -> Int {
  ((self.production_date_raw >> 10) & 0x3FU).reinterpret_as_int()
}

///|
/// Fixed SII preamble loaded by the ESC during startup.
pub(all) struct SiiPreamble {
  pdi_control : UInt
  pdi_config : UInt
  sync_impulse_length_raw : UInt
  pdi_config2 : UInt
  configured_station_alias : UInt
  checksum : UInt
  checksum_ok : Bool
} derive(Eq, Show)

///|
pub fn SiiPreamble::sync_impulse_length_ns(self : SiiPreamble) -> UInt {
  self.sync_impulse_length_raw * 10U
}

///|
/// Additional fixed metadata stored after the standard SII config block.
pub(all) struct SiiStandardMetadata {
  eeprom_size_raw : UInt
  version : UInt
} derive(Eq, Show)

///|
pub fn SiiStandardMetadata::eeprom_size_bytes(
  self : SiiStandardMetadata,
) -> UInt {
  (self.eeprom_size_raw << 7) + 0x80U
}

///|
/// Parsed DC clock category entry.
/// This follows the field layout siitool uses for category 0x3c.
pub(all) struct SiiDcClock {
  cycle_time_0 : UInt
  shift_time_0 : UInt
  shift_time_1 : UInt
  sync1_cycle_factor : Int
  assign_activate : UInt
  sync0_cycle_factor : Int
  name_idx : Byte
  description_idx : Byte
} derive(Eq, Show)

///|
/// Parsed SII PDO descriptor (TxPdo/RxPdo category).
pub(all) struct SiiPdo {
  pdo_index : UInt
  entry_count : Byte
  sync_manager : Byte
  synchronization : Byte
  name_idx : Byte
  flags : UInt
  entries : Array[SiiPdoEntry]
} derive(Eq, Show)

///|
/// Single entry within a PDO descriptor.
pub(all) struct SiiPdoEntry {
  entry_index : UInt
  subindex : Byte
  name_idx : Byte
  data_type : Byte
  bit_length : Byte
  flags : UInt
} derive(Eq, Show)

///|
/// Parsed SII timeout category (ETG.2010 Table 13), values in milliseconds.
pub(all) struct SiiTimeouts {
  preop_timeout_ms : UInt
  safeop_op_timeout_ms : UInt
  back_to_init_timeout_ms : UInt
  back_to_safeop_timeout_ms : UInt
  mailbox_request_timeout_ms : UInt
  mailbox_response_timeout_ms : UInt
} derive(Eq, Show)

///|
/// Parsed SII FMMU_EX category element (ETG.2010 Table 10).
pub(all) struct SiiFmmuEx {
  op_only : Bool
  sm_defined : Bool
  su_defined : Bool
  sync_manager : Byte
  sync_unit : Byte
} derive(Eq, Show)

///|
/// Parsed SII SyncUnit category element (ETG.2010 Table 14).
pub(all) struct SiiSyncUnit {
  separate_su : Bool
  separate_frame : Bool
  depend_on_input_state : Bool
  frame_repeat_support : Bool
  raw_flags : Byte
} derive(Eq, Show)

///|
/// A parsed SII category with its type tag and raw data.
pub(all) struct SiiCategoryEntry {
  category : SiiCategory
  type_code : UInt
  data : Bytes
} derive(Eq, Show)

///|
/// Aggregated SII view shared by CLI, runtime, and offline projection paths.
pub(all) struct SiiFullInfo {
  eeprom : Bytes
  preamble : SiiPreamble
  standard : SiiStandardMetadata
  header : SiiData
  categories : Array[SiiCategoryEntry]
  strings : Array[String]
  general : SiiGeneral?
  timeouts : SiiTimeouts?
  fmmu : Array[FmmuDirection]
  fmmu_ex : Array[SiiFmmuEx]
  sync_managers : Array[SiiSmEntry]
  sync_units : Array[SiiSyncUnit]
  tx_pdo : Array[SiiPdo]
  rx_pdo : Array[SiiPdo]
  dc_clocks : Array[SiiDcClock]
} derive(Show)
