///|
/// Mailbox protocol types as defined in ETG.1000.6.
pub(all) enum MailboxType {
  /// Error mailbox
  Err
  /// ADS over EtherCAT
  AoE
  /// Ethernet over EtherCAT (out of scope)
  EoE
  /// CAN application protocol over EtherCAT
  CoE
  /// File access over EtherCAT (out of scope)
  FoE
  /// Servo profile over EtherCAT
  SoE
  /// Vendor specific
  VoE
} derive(Eq, Show)

///|
pub fn MailboxType::to_byte(self : MailboxType) -> Byte {
  match self {
    Err => b'\x00'
    AoE => b'\x01'
    EoE => b'\x02'
    CoE => b'\x03'
    FoE => b'\x04'
    SoE => b'\x05'
    VoE => b'\x0F'
  }
}

///|
/// Mailbox header structure (6 bytes in protocol).
pub(all) struct MailboxHeader {
  length : UInt
  address : UInt
  channel : Byte
  priority : Byte
  mb_type : MailboxType
  counter : Byte
} derive(Eq, Show)
