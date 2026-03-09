///|
/// CLI scan command: discover EtherCAT slaves on the bus,
/// assign station addresses, read identity, and report results.
///
/// This module provides the library-level scan logic that
/// the CLI entry point invokes.

///|
/// ScanReport holds the results of a bus scan.
pub(all) struct ScanReport {
  slave_count : Int
  slaves : Array[SlaveReport]
} derive(Eq, Show)

///|
/// SlaveReport holds info for one discovered slave.
pub(all) struct SlaveReport {
  position : Int
  station_address : UInt
  vendor_id : UInt
  product_code : UInt
  revision : UInt
  serial : UInt
} derive(Eq, Show)

///|
/// Run the scan procedure: count slaves, assign addresses, read identity
/// from SII EEPROM registers.
/// Returns a ScanReport summarizing what was found.
pub fn[N : @hal.Nic] scan(
  nic : N,
  timeout : @hal.Duration,
) -> ScanReport raise @hal.EcError {
  let count = @protocol.count_slaves(nic, timeout)
  let slaves : Array[SlaveReport] = []
  for i = 0; i < count; i = i + 1 {
    let position = i.reinterpret_as_uint()
    let station = 0x1001U + position
    @protocol.assign_station_address(nic, position, station, timeout)
    // Read identity via configured (FP) addressing from DL registers
    // ESC type register at 0x0008 holds Vendor ID (4 bytes)
    let vendor_pdu = @protocol.read_register_fp(
      nic, station, 0x0008U, 4, timeout,
    )
    let vendor_id = read_u32_le(vendor_pdu.data, 0)
    let product_pdu = @protocol.read_register_fp(
      nic, station, 0x000CU, 4, timeout,
    )
    let product_code = read_u32_le(product_pdu.data, 0)
    let revision_pdu = @protocol.read_register_fp(
      nic, station, 0x0010U, 4, timeout,
    )
    let revision = read_u32_le(revision_pdu.data, 0)
    let serial_pdu = @protocol.read_register_fp(
      nic, station, 0x0014U, 4, timeout,
    )
    let serial = read_u32_le(serial_pdu.data, 0)
    slaves.push({
      position: i,
      station_address: station,
      vendor_id,
      product_code,
      revision,
      serial,
    })
  }
  { slave_count: count, slaves }
}

///|
/// Read a little-endian u32 from bytes at the given offset.
fn read_u32_le(data : Bytes, offset : Int) -> UInt {
  if data.length() < offset + 4 {
    return 0U
  }
  data[offset].to_uint() |
  (data[offset + 1].to_uint() << 8) |
  (data[offset + 2].to_uint() << 16) |
  (data[offset + 3].to_uint() << 24)
}

///|
/// Format a ScanReport as a human-readable string.
pub fn ScanReport::format(self : ScanReport) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("EtherCAT Bus Scan Report\n")
  buf.write_string("========================\n")
  buf.write_string("Slaves found: " + self.slave_count.to_string() + "\n\n")
  for i = 0; i < self.slaves.length(); i = i + 1 {
    let s = self.slaves[i]
    buf.write_string("Slave #" + s.position.to_string() + "\n")
    buf.write_string(
      "  Station: 0x" +
      s.station_address.reinterpret_as_int().to_string() +
      "\n",
    )
    buf.write_string(
      "  Vendor:  0x" + s.vendor_id.reinterpret_as_int().to_string() + "\n",
    )
    buf.write_string(
      "  Product: 0x" + s.product_code.reinterpret_as_int().to_string() + "\n",
    )
    buf.write_string(
      "  Revision: 0x" + s.revision.reinterpret_as_int().to_string() + "\n",
    )
    buf.write_string(
      "  Serial: 0x" + s.serial.reinterpret_as_int().to_string() + "\n",
    )
    if i < self.slaves.length() - 1 {
      buf.write_string("\n")
    }
  }
  buf.to_string()
}
