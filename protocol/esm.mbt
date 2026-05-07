///|
/// EtherCAT Slave Machine (ESM) states as defined in ETG.1000.6.
pub(all) enum EsmState {
  Init
  PreOp
  SafeOp
  Op
  /// Bootstrap state for firmware update (optional)
  Boot
} derive(Eq, Debug)

///|
/// ESM state register values.
pub fn EsmState::to_byte(
  self : EsmState,
) -> Byte where {
  proof_ensure: result => esm_state_byte(self, result),
} {
  match self {
    Init => b'\x01'
    PreOp => b'\x02'
    SafeOp => b'\x04'
    Op => b'\x08'
    Boot => b'\x03'
  }
}

///|
pub fn EsmState::from_byte(b : Byte) -> EsmState raise @hal.EcError {
  match b & b'\x0F' {
    b'\x01' => Init
    b'\x02' => PreOp
    b'\x04' => SafeOp
    b'\x08' => Op
    b'\x03' => Boot
    _ =>
      raise @hal.EcError::EsmStateError(
        "unknown ESM state: 0x" + b.to_int().to_string(),
      )
  }
}

///|
/// Check whether the transition from one ESM state to another is valid.
pub fn EsmState::can_transition(
  self : EsmState,
  target : EsmState,
) -> Bool where {
  proof_ensure: result => result == valid_esm_transition(self, target),
} {
  match (self, target) {
    (Init, PreOp) => true
    (Init, Boot) => true
    (PreOp, SafeOp) => true
    (PreOp, Init) => true
    (SafeOp, Op) => true
    (SafeOp, PreOp) => true
    (SafeOp, Init) => true
    (Op, SafeOp) => true
    (Op, PreOp) => true
    (Op, Init) => true
    (Boot, Init) => true
    _ => false
  }
}

///|
/// Addressing mode used when communicating with slaves.
pub(all) enum AddressMode {
  /// Auto-increment addressing: slaves are addressed sequentially by position.
  AutoIncrement
  /// Configured station addressing: slaves use an assigned 16-bit address.
  ConfiguredStation(UInt)
  /// Logical addressing: FMMU-mapped address space.
  Logical(UInt)
} derive(Eq, Debug)

///|
/// Human-readable description of an AL Status Code per ETG.1000.6 Table 11.
pub fn al_status_code_description(code : UInt) -> String {
  match code {
    0x0000U => "No error"
    0x0001U => "Unspecified error"
    0x0002U => "No memory"
    0x0003U => "Invalid device setup"
    0x0004U => "Invalid revision"
    0x0006U => "SII/EEPROM information does not match firmware"
    0x0007U => "Firmware update not successful, old firmware still running"
    0x000EU => "License error"
    0x0011U => "Invalid requested state change"
    0x0012U => "Unknown requested state"
    0x0013U => "Bootstrap not supported"
    0x0014U => "No valid firmware"
    0x0015U => "Invalid mailbox configuration (PreOp)"
    0x0016U => "Invalid mailbox configuration (SafeOp)"
    0x0017U => "Invalid sync manager configuration"
    0x0018U => "No valid inputs available"
    0x0019U => "No valid outputs"
    0x001AU => "Synchronization error"
    0x001BU => "Sync manager watchdog"
    0x001CU => "Invalid sync manager types"
    0x001DU => "Invalid output configuration"
    0x001EU => "Invalid input configuration"
    0x001FU => "Invalid watchdog configuration"
    0x0020U => "Slave needs cold start"
    0x0021U => "Slave needs INIT"
    0x0022U => "Slave needs PREOP"
    0x0023U => "Slave needs SAFEOP"
    0x0024U => "Invalid input mapping"
    0x0025U => "Invalid output mapping"
    0x0026U => "Inconsistent settings"
    0x0027U => "Freerun not supported"
    0x0028U => "Synchronisation not supported"
    0x0029U => "Freerun needs 3-buffer mode"
    0x002AU => "Background watchdog"
    0x002BU => "No valid inputs and outputs"
    0x002CU => "Fatal sync error"
    0x002DU => "No sync error"
    0x002EU => "Invalid input FMMU configuration"
    0x0030U => "Invalid DC SYNC configuration"
    0x0031U => "Invalid DC latch configuration"
    0x0032U => "PLL error"
    0x0033U => "DC sync IO error"
    0x0034U => "DC sync timeout error"
    0x0035U => "DC invalid sync cycle time"
    0x0036U => "DC invalid sync0 cycle time"
    0x0037U => "DC invalid sync1 cycle time"
    0x0041U => "MBX_AOE"
    0x0042U => "MBX_EOE"
    0x0043U => "MBX_COE"
    0x0044U => "MBX_FOE"
    0x0045U => "MBX_SOE"
    0x004FU => "MBX_VOE"
    0x0050U => "EEPROM no access"
    0x0051U => "EEPROM error"
    0x0052U => "External hardware not ready"
    0x0060U => "Slave restarted locally"
    0x0061U => "Device identification value updated"
    0x0070U => "Detected module ident list does not match"
    0x0080U => "Supply voltage too low"
    0x0081U => "Supply voltage too high"
    0x0082U => "Temperature too low"
    0x0083U => "Temperature too high"
    _ => "Unknown (" + code.to_string() + ")"
  }
}
