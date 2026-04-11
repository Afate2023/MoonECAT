///|
/// EtherCAT addressing modes.
/// Auto-increment: slave position relative to first slave (negative offset).
/// Configured: fixed address assigned during configuration.
/// Broadcast: address 0x0000, all slaves respond.
/// Logical: 32-bit address mapped via FMMU.
pub(all) enum AddressType {
  AutoIncrement
  Configured
  Broadcast
  Logical
} derive(Eq, Debug)

///|
/// Build a PDU address from auto-increment position (negative offset from first slave).
/// Position 0 = first slave, 1 = second slave, etc.
pub fn auto_increment_address(position : UInt) -> UInt {
  // PDU address is serialized as ADP then ADO, and codec writes the 32-bit value as LE.
  // Keep ADP/position in the low 16 bits so the wire bytes are [ADP][ADO].
  position & 0xFFFFU
}

///|
/// Build a PDU address from configured (fixed) station address and memory offset.
pub fn configured_address(station : UInt, offset : UInt) -> UInt {
  // Low 16 bits = ADP/station, high 16 bits = ADO/register offset.
  (station & 0xFFFFU) | ((offset & 0xFFFFU) << 16)
}

///|
/// Build a PDU address for broadcast with register/memory offset.
pub fn broadcast_address(offset : UInt) -> UInt {
  (offset & 0xFFFFU) << 16
}

///|
/// Build a 32-bit logical address for LRD/LWR/LRW commands.
pub fn logical_address(addr : UInt) -> UInt {
  addr
}

///|
/// Extract the position or station address from a PDU address (low 16 bits).
pub fn address_station(addr : UInt) -> UInt {
  addr & 0xFFFFU
}

///|
/// Extract the offset from a PDU address (high 16 bits).
pub fn address_offset(addr : UInt) -> UInt {
  (addr >> 16) & 0xFFFFU
}

///|
/// Determine which command to use for a read operation given an address type.
pub fn read_command(addr_type : AddressType) -> EcCommand {
  match addr_type {
    AutoIncrement => APRD
    Configured => FPRD
    Broadcast => BRD
    Logical => LRD
  }
}

///|
/// Determine which command to use for a write operation given an address type.
pub fn write_command(addr_type : AddressType) -> EcCommand {
  match addr_type {
    AutoIncrement => APWR
    Configured => FPWR
    Broadcast => BWR
    Logical => LWR
  }
}

///|
/// Determine which command to use for a read-write operation given an address type.
pub fn readwrite_command(addr_type : AddressType) -> EcCommand {
  match addr_type {
    AutoIncrement => APRW
    Configured => FPRW
    Broadcast => BRW
    Logical => LRW
  }
}
