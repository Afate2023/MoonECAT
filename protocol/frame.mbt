///|
/// Ethernet II frame header length: dst(6) + src(6) + ethertype(2) = 14 bytes.
pub let ethernet_header_len : Int = 14

///|
/// EtherCAT frame header length: 2 bytes (length + type).
pub let ecat_header_len : Int = 2

///|
/// Minimum EtherCAT PDU header length: 10 bytes.
pub let pdu_header_len : Int = 10

///|
/// Working counter size: 2 bytes per PDU.
pub let wkc_len : Int = 2

///|
/// EtherCAT frame type in the 4-bit type field (always 0x1).
pub let ecat_frame_type : Int = 0x1

///|
/// Broadcast MAC address used as destination for EtherCAT frames.
pub let broadcast_mac : FixedArray[Byte] = [
  b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
]

///|
/// A default source MAC address for the master.
pub let default_master_mac : FixedArray[Byte] = [
  b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
]

///|
/// EcFrame represents a fully decoded EtherCAT Ethernet frame.
pub(all) struct EcFrame {
  dst_mac : FixedArray[Byte] // 6 bytes
  src_mac : FixedArray[Byte] // 6 bytes
  pdus : Array[Pdu]
} derive(Eq, Debug)
