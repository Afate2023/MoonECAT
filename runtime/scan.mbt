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
  identification : UInt
} derive(Eq, Show)

///|
/// Default IdentificationAdo register used for explicit device identification.
let default_identification_ado : UInt = 0x0014U

///|
/// Bytes needed to cover the fixed SII header through mailbox protocol word.
let sii_header_read_dwords : Int = 15

///|
/// Run the scan procedure: count slaves, assign addresses, read identity
/// from SII EEPROM registers.
/// Returns a ScanReport summarizing what was found.
pub fn[N : @hal.Nic] scan(
  nic : N,
  timeout : @hal.Duration,
) -> ScanReport raise @hal.EcError {
  scan_with_identification_ado(nic, timeout, default_identification_ado)
}

///|
/// Run the scan procedure with a configurable IdentificationAdo register.
pub fn[N : @hal.Nic] scan_with_identification_ado(
  nic : N,
  timeout : @hal.Duration,
  identification_ado : UInt,
) -> ScanReport raise @hal.EcError {
  let count = @protocol.count_slaves(nic, timeout)
  let slaves : Array[SlaveReport] = []
  for i = 0; i < count; i = i + 1 {
    let position = i.reinterpret_as_uint()
    let station = 0x1001U + position
    @protocol.assign_station_address(nic, position, station, timeout)
    let identity = read_best_identity(nic, position, station, timeout)
    let identification_pdu = @protocol.read_register_ap(
      nic, position, identification_ado, 4, timeout,
    )
    let identification = read_u32_le(identification_pdu.data, 0)
    slaves.push({
      position: i,
      station_address: station,
      vendor_id: identity.vendor_id,
      product_code: identity.product_code,
      revision: identity.revision,
      serial: identity.serial,
      identification,
    })
  }
  { slave_count: count, slaves }
}

///|
fn[N : @hal.Nic] read_best_identity(
  nic : N,
  position : UInt,
  station : UInt,
  timeout : @hal.Duration,
) -> @hal.SlaveIdentity {
  let ap_sii = try? read_identity_from_sii_ap(nic, position, timeout)
  match ap_sii {
    Ok(identity) if not(identity_is_zero(identity)) => identity
    _ => {
      let fp_sii = try? read_identity_from_sii(nic, station, timeout)
      match fp_sii {
        Ok(identity) if not(identity_is_zero(identity)) => identity
        _ => {
          let ap_regs = try? read_identity_from_registers_ap(
            nic, position, timeout,
          )
          match ap_regs {
            Ok(identity) if not(identity_is_zero(identity)) => identity
            _ =>
              read_identity_from_registers(nic, station, timeout) catch {
                _ =>
                  { vendor_id: 0U, product_code: 0U, revision: 0U, serial: 0U }
              }
          }
        }
      }
    }
  }
}

///|
fn identity_is_zero(identity : @hal.SlaveIdentity) -> Bool {
  identity.vendor_id == 0U &&
  identity.product_code == 0U &&
  identity.revision == 0U &&
  identity.serial == 0U
}

///|
fn[N : @hal.Nic] read_identity_from_sii_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> @hal.SlaveIdentity raise @hal.EcError {
  let eeprom = @protocol.eeprom_read_ap(
    nic, position, 0U, sii_header_read_dwords, timeout,
  )
  let sii = @mailbox.parse_sii_header(eeprom)
  {
    vendor_id: sii.vendor_id,
    product_code: sii.product_code,
    revision: sii.revision,
    serial: sii.serial,
  }
}

///|
fn[N : @hal.Nic] read_identity_from_sii(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> @hal.SlaveIdentity raise @hal.EcError {
  let eeprom = @protocol.eeprom_read(
    nic, station, 0U, sii_header_read_dwords, timeout,
  )
  let sii = @mailbox.parse_sii_header(eeprom)
  {
    vendor_id: sii.vendor_id,
    product_code: sii.product_code,
    revision: sii.revision,
    serial: sii.serial,
  }
}

///|
fn[N : @hal.Nic] read_identity_from_registers(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> @hal.SlaveIdentity raise @hal.EcError {
  let vendor_pdu = @protocol.read_register_fp(nic, station, 0x0008U, 4, timeout)
  let product_pdu = @protocol.read_register_fp(
    nic, station, 0x000CU, 4, timeout,
  )
  let revision_pdu = @protocol.read_register_fp(
    nic, station, 0x0010U, 4, timeout,
  )
  let serial_pdu = @protocol.read_register_fp(nic, station, 0x0014U, 4, timeout)
  {
    vendor_id: read_u32_le(vendor_pdu.data, 0),
    product_code: read_u32_le(product_pdu.data, 0),
    revision: read_u32_le(revision_pdu.data, 0),
    serial: read_u32_le(serial_pdu.data, 0),
  }
}

///|
fn[N : @hal.Nic] read_identity_from_registers_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> @hal.SlaveIdentity raise @hal.EcError {
  let vendor_pdu = @protocol.read_register_ap(
    nic, position, 0x0008U, 4, timeout,
  )
  let product_pdu = @protocol.read_register_ap(
    nic, position, 0x000CU, 4, timeout,
  )
  let revision_pdu = @protocol.read_register_ap(
    nic, position, 0x0010U, 4, timeout,
  )
  let serial_pdu = @protocol.read_register_ap(
    nic, position, 0x0014U, 4, timeout,
  )
  {
    vendor_id: read_u32_le(vendor_pdu.data, 0),
    product_code: read_u32_le(product_pdu.data, 0),
    revision: read_u32_le(revision_pdu.data, 0),
    serial: read_u32_le(serial_pdu.data, 0),
  }
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
    buf.write_string("  Station: " + s.station_address.to_string() + "\n")
    buf.write_string("  Vendor:  " + s.vendor_id.to_string() + "\n")
    buf.write_string("  Product: " + s.product_code.to_string() + "\n")
    buf.write_string("  Revision: " + s.revision.to_string() + "\n")
    buf.write_string("  Serial: " + s.serial.to_string() + "\n")
    buf.write_string("  Identification: " + s.identification.to_string() + "\n")
    if i < self.slaves.length() - 1 {
      buf.write_string("\n")
    }
  }
  buf.to_string()
}
