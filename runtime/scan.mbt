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
  alias_address : UInt?
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
/// Base of the reserved scan-time station address range.
let scan_station_address_base : UInt = 0x1001U

///|
/// Bytes needed to cover the fixed SII header through mailbox protocol word.
let sii_header_read_dwords : Int = 15

///|
struct ObservedSlaveAddress {
  position : UInt
  current_station_address : UInt
} derive(Eq, Show)

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
  let observed_addresses = observe_slave_station_addresses(nic, count, timeout)
  let planned_addresses = plan_scan_station_addresses(observed_addresses)
  apply_scan_station_addresses(
    nic, observed_addresses, planned_addresses, timeout,
  )
  let slaves : Array[SlaveReport] = []
  for i = 0; i < count; i = i + 1 {
    let position = i.reinterpret_as_uint()
    let station = planned_addresses[i]
    let alias_address = try
      @protocol.read_station_alias(nic, station, timeout)
    catch {
      _ => None
    } noraise {
      value => Some(value)
    }
    let identity = read_best_identity(nic, position, station, timeout)
    let identification_pdu = @protocol.read_register_ap(
      nic, position, identification_ado, 4, timeout,
    )
    let identification = read_u32_le(identification_pdu.data, 0)
    slaves.push({
      position: i,
      station_address: station,
      alias_address,
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
fn[N : @hal.Nic] observe_slave_station_addresses(
  nic : N,
  count : Int,
  timeout : @hal.Duration,
) -> Array[ObservedSlaveAddress] raise @hal.EcError {
  let observed : Array[ObservedSlaveAddress] = []
  for i = 0; i < count; i = i + 1 {
    let position = i.reinterpret_as_uint()
    observed.push({
      position,
      current_station_address: @protocol.read_station_address_ap(
        nic, position, timeout,
      ),
    })
  }
  observed
}

///|
fn plan_scan_station_addresses(
  observed : Array[ObservedSlaveAddress],
) -> Array[UInt] raise @hal.EcError {
  let planned : Array[UInt] = []
  let used : Array[UInt] = []
  for item in observed {
    let current_station_address = item.current_station_address
    if should_preserve_scan_station_address(current_station_address, observed) &&
      not(array_contains_uint(used, current_station_address)) {
      planned.push(current_station_address)
      used.push(current_station_address)
    } else {
      let reassigned = next_scan_station_address(used)
      planned.push(reassigned)
      used.push(reassigned)
    }
  }
  planned
}

///|
fn should_preserve_scan_station_address(
  station_address : UInt,
  observed : Array[ObservedSlaveAddress],
) -> Bool {
  station_address != 0U &&
  scan_station_address_occurs_once(station_address, observed)
}

///|
fn scan_station_address_occurs_once(
  station_address : UInt,
  observed : Array[ObservedSlaveAddress],
) -> Bool {
  let mut matches = 0
  for item in observed {
    if item.current_station_address == station_address {
      matches = matches + 1
    }
  }
  matches == 1
}

///|
fn next_scan_station_address(used : Array[UInt]) -> UInt raise @hal.EcError {
  let mut candidate = scan_station_address_base
  while array_contains_uint(used, candidate) {
    if candidate == 0xFFFFU {
      raise @hal.EcError::ConfigMismatch("scan station address pool exhausted")
    }
    candidate = candidate + 1U
  }
  candidate
}

///|
fn array_contains_uint(values : Array[UInt], target : UInt) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

///|
fn[N : @hal.Nic] apply_scan_station_addresses(
  nic : N,
  observed : Array[ObservedSlaveAddress],
  planned : Array[UInt],
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  for i = 0; i < observed.length(); i = i + 1 {
    let item = observed[i]
    let station_address = planned[i]
    if item.current_station_address != station_address {
      @protocol.assign_station_address(
        nic,
        item.position,
        station_address,
        timeout,
      )
    }
  }
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
    match s.alias_address {
      Some(alias_value) =>
        buf.write_string("  Alias:   " + alias_value.to_string() + "\n")
      None => ()
    }
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
