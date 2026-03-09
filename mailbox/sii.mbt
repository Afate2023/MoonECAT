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
