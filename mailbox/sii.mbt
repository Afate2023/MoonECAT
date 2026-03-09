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
  mailbox_rx_offset : UInt
  mailbox_rx_size : UInt
  mailbox_tx_offset : UInt
  mailbox_tx_size : UInt
  mailbox_protocols : UInt
} derive(Eq, Show)
