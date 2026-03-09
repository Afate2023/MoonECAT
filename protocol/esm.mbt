///|
/// EtherCAT Slave Machine (ESM) states as defined in ETG.1000.6.
pub(all) enum EsmState {
  Init
  PreOp
  SafeOp
  Op
  /// Bootstrap state for firmware update (optional)
  Boot
} derive(Eq, Show)

///|
/// ESM state register values.
pub fn EsmState::to_byte(self : EsmState) -> Byte {
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
pub fn EsmState::can_transition(self : EsmState, target : EsmState) -> Bool {
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
} derive(Eq, Show)
