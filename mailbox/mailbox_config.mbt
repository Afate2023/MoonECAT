///|
/// Mailbox configuration for a slave, derived from SII EEPROM data.
/// Describes the Sync Manager addresses and sizes for mailbox communication.

///|
/// MailboxConfig holds the SM addresses used for mailbox transport.
/// SM Out = Master → Slave (slave's "receive" mailbox, typically SM0).
/// SM In  = Slave → Master (slave's "transmit" mailbox, typically SM1).
pub(all) struct MailboxConfig {
  /// SM Output physical start address (Master writes here).
  out_address : UInt
  /// SM Output length in bytes (max frame size for outgoing mailbox).
  out_size : UInt
  /// SM Output SM index (typically 0).
  out_sm_index : Int
  /// SM Input physical start address (Master reads from here).
  in_address : UInt
  /// SM Input length in bytes (max frame size for incoming mailbox).
  in_size : UInt
  /// SM Input SM index (typically 1).
  in_sm_index : Int
} derive(Eq, Debug)

///|
/// Build a MailboxConfig from SII EEPROM header data.
/// Uses standard SM0/SM1 mailbox convention.
pub fn MailboxConfig::from_sii(sii : SiiData) -> MailboxConfig {
  {
    out_address: sii.mailbox_rx_offset,
    out_size: sii.mailbox_rx_size,
    out_sm_index: 0,
    in_address: sii.mailbox_tx_offset,
    in_size: sii.mailbox_tx_size,
    in_sm_index: 1,
  }
}

///|
/// Check if the slave supports mailbox communication
/// (both SM Out and SM In must have non-zero size).
pub fn MailboxConfig::is_valid(self : MailboxConfig) -> Bool {
  self.out_size > 0U && self.in_size > 0U
}
