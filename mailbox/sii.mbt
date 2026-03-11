///|
/// SII category types (Slave Information Interface).
pub(all) enum SiiCategory {
  Strings
  General
  Fmmu
  SyncManager
  TxPdo
  RxPdo
  Dc
} derive(Eq, Show)

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
} derive(Eq, Show)

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
