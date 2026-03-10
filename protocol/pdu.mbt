///|
/// EtherCAT command types as defined in ETG.1000.4.
pub(all) enum EcCommand {
  NOP // No operation
  APRD // Auto Increment Physical Read
  APWR // Auto Increment Physical Write
  APRW // Auto Increment Physical Read Write
  FPRD // Configured Address Physical Read
  FPWR // Configured Address Physical Write
  FPRW // Configured Address Physical Read Write
  BRD // Broadcast Read
  BWR // Broadcast Write
  BRW // Broadcast Read Write
  LRD // Logical Read
  LWR // Logical Write
  LRW // Logical Read Write
  ARMW // Auto Increment Physical Read Multiple Write
  FRMW // Configured Address Physical Read Multiple Write
} derive(Eq, Show)

///|
pub fn EcCommand::to_byte(self : EcCommand) -> Byte {
  match self {
    NOP => b'\x00'
    APRD => b'\x01'
    APWR => b'\x02'
    APRW => b'\x03'
    FPRD => b'\x04'
    FPWR => b'\x05'
    FPRW => b'\x06'
    BRD => b'\x07'
    BWR => b'\x08'
    BRW => b'\x09'
    LRD => b'\x0A'
    LWR => b'\x0B'
    LRW => b'\x0C'
    ARMW => b'\x0D'
    FRMW => b'\x0E'
  }
}

///|
pub fn EcCommand::from_byte(b : Byte) -> EcCommand raise @hal.EcError {
  match b {
    b'\x00' => NOP
    b'\x01' => APRD
    b'\x02' => APWR
    b'\x03' => APRW
    b'\x04' => FPRD
    b'\x05' => FPWR
    b'\x06' => FPRW
    b'\x07' => BRD
    b'\x08' => BWR
    b'\x09' => BRW
    b'\x0A' => LRD
    b'\x0B' => LWR
    b'\x0C' => LRW
    b'\x0D' => ARMW
    b'\x0E' => FRMW
    _ =>
      raise @hal.EcError::InvalidPdu(
        "unknown command byte: " + b.to_int().to_string(),
      )
  }
}

///|
/// EtherCAT PDU (Protocol Data Unit) header.
pub(all) struct PduHeader {
  command : EcCommand
  index : Byte
  /// Slave address (auto-increment or configured) or logical address
  address : UInt
  /// Data length and next/last flags packed into 11+1+4 bits
  len_flags : UInt
  /// Datagram IRQ field (ETG.1000.4), parsed and propagated for runtime use.
  irq : UInt
} derive(Eq, Show)

///|
/// Full PDU including header, data payload, and working counter.
pub(all) struct Pdu {
  header : PduHeader
  data : Bytes
  wkc : UInt
} derive(Eq, Show)
