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
} derive(Eq, Show)

///|
/// Build a PDU address from auto-increment position (negative offset from first slave).
/// Position 0 = first slave, 1 = second slave, etc.
pub fn auto_increment_address(position : UInt) -> UInt {
  // Auto-increment uses negative offset: 0 - position encoded as uint16 in lower 16 bits
  // Upper 16 bits = 0 (offset), Lower 16 bits = position (auto-increment address)
  position & 0xFFFFU
}

///|
/// Build a PDU address from configured (fixed) station address and memory offset.
pub fn configured_address(station : UInt, offset : UInt) -> UInt {
  // Upper 16 bits = station address, Lower 16 bits = memory offset (register/memory address)
  // Wait - actually in EtherCAT PDU the 4-byte address field is:
  //   For position addressing (APRD/APWR/APRW): [position:16][offset:16]
  //   For node addressing (FPRD/FPWR/FPRW):     [address:16][offset:16]
  //   For broadcast (BRD/BWR/BRW):               [0:16][offset:16]
  //   For logical (LRD/LWR/LRW):                 [logical_address:32]
  ((station & 0xFFFFU) << 16) | (offset & 0xFFFFU)
}

///|
/// Build a PDU address for broadcast with register/memory offset.
pub fn broadcast_address(offset : UInt) -> UInt {
  offset & 0xFFFFU
}

///|
/// Build a 32-bit logical address for LRD/LWR/LRW commands.
pub fn logical_address(addr : UInt) -> UInt {
  addr
}

///|
/// Extract the position or station address from a PDU address (upper 16 bits).
pub fn address_station(addr : UInt) -> UInt {
  (addr >> 16) & 0xFFFFU
}

///|
/// Extract the offset from a PDU address (lower 16 bits).
pub fn address_offset(addr : UInt) -> UInt {
  addr & 0xFFFFU
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
