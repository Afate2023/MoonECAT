///|
/// Provides shared test fixtures across the project.
/// Import this package in test-import sections for common test data.

///|
/// A minimal valid EtherCAT frame (broadcast NOP) for testing.
/// dst(6) + src(6) + ethertype(2) + ecat_header(2) + pdu_header(10) + wkc(2) = 28 bytes
pub fn minimal_nop_frame() -> Bytes {
  Bytes::from_array([
    // Dst MAC: broadcast
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
    // Src MAC: default master
     b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
    // EtherType: 0x88A4 (EtherCAT)
     b'\x88', b'\xA4',
    // EtherCAT header: length=12 (PDU header 10 + WKC 2), type=1
     b'\x0C', b'\x10',
    // PDU: NOP command
     b'\x00', // command: NOP
     b'\x00', // index
     b'\x00', b'\x00', b'\x00', b'\x00', // address
     b'\x00', b'\x00', // len_flags (data_len=0, next=0)
     b'\x00', b'\x00', // IRQ
    // WKC
     b'\x00', b'\x00',
  ])
}

///|
/// A sample slave identity for the Beckhoff EK1100 coupler.
pub fn sample_ek1100_identity() -> @hal.SlaveIdentity {
  {
    vendor_id: 0x2U, // Beckhoff
    product_code: 0x44C2C52U,
    revision: 0x110000U,
    serial: 0x0U,
  }
}
