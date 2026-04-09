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
} derive(Eq, Debug)

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
} derive(Eq, Debug)

///|
/// Repeat request / acknowledge state for resilient mailbox read recovery.
///
/// Repeat Request is toggled by the MainDevice in the SyncManager activate
/// byte (offset 0x0006 bit 1). Repeat Acknowledge is toggled by the SubDevice
/// in the PDI-owned status byte (offset 0x0007 bit 1) after restoring the last
/// readable mailbox payload.
pub(all) struct MailboxRepeatState {
  request : Bool
  acknowledge : Bool
} derive(Eq, Debug)

///|
let mailbox_repeat_bit : Byte = b'\x02'

///|
fn set_mask_bit(value : Byte, mask : Byte, enabled : Bool) -> Byte {
  if enabled {
    value | mask
  } else {
    value & (mask ^ b'\xFF')
  }
}

///|
/// Decode resilient mailbox repeat state from the two SyncManager bytes.
pub fn MailboxRepeatState::from_sync_manager_bytes(
  activate : Byte,
  pdi_control : Byte,
) -> MailboxRepeatState {
  {
    request: (activate & mailbox_repeat_bit) != b'\x00',
    acknowledge: (pdi_control & mailbox_repeat_bit) != b'\x00',
  }
}

///|
/// Return true once the SubDevice has observed and acknowledged the current
/// repeat request toggle.
pub fn MailboxRepeatState::is_acknowledged(self : MailboxRepeatState) -> Bool {
  self.request == self.acknowledge
}

///|
/// Toggle the MainDevice repeat request state for a mailbox-read replay.
pub fn MailboxRepeatState::toggle_request(self : MailboxRepeatState) -> Bool {
  !self.request
}

///|
/// Apply the current repeat request value to a SyncManager activate byte.
pub fn MailboxRepeatState::apply_to_activate_byte(
  self : MailboxRepeatState,
  activate : Byte,
) -> Byte {
  set_mask_bit(activate, mailbox_repeat_bit, self.request)
}

///|
/// Apply the current repeat acknowledge value to the SyncManager PDI byte.
pub fn MailboxRepeatState::apply_to_pdi_control_byte(
  self : MailboxRepeatState,
  pdi_control : Byte,
) -> Byte {
  set_mask_bit(pdi_control, mailbox_repeat_bit, self.acknowledge)
}
