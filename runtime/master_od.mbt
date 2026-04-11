///|
/// Master Object Dictionary (ETG.1500 #1301) — local OD for the EtherCAT master.
///
/// Exposes standard CiA-301 objects 0x1000–0x10FF that describe the master
/// device identity, runtime state, and network topology. This is a read-only
/// view synthesised from Runtime, ScanReport, Telemetry, and DiagnosticSurface;
/// the master does not store a persistent OD in EEPROM.

///|
/// Standard data types for OD entries (CiA-301 subset).
pub(all) enum MasterOdDataType {
  Unsigned8
  Unsigned16
  Unsigned32
  Integer32
  VisibleString
  OctetString
} derive(Eq, Debug)

///|
/// Access mode for an OD entry.
pub(all) enum MasterOdAccess {
  ReadOnly
  ReadWrite
} derive(Eq, Debug)

///|
/// One entry in the master object dictionary.
pub(all) struct MasterOdEntry {
  index : UInt
  subindex : Byte
  name : String
  data_type : MasterOdDataType
  access : MasterOdAccess
  value : MasterOdValue
} derive(Eq, Debug)

///|
/// Value stored (or computed) for an OD entry.
pub(all) enum MasterOdValue {
  U8(Byte)
  U16(UInt)
  U32(UInt)
  I32(Int)
  Str(String)
  Raw(Bytes)
} derive(Eq, Debug)

///|
/// The master object dictionary: a flat list of entries.
pub(all) struct MasterObjectDictionary {
  entries : Array[MasterOdEntry]
} derive(Eq, Debug)

///|
/// Identity used when building the master's own 0x1018.
pub(all) struct MasterIdentity {
  vendor_id : UInt
  product_code : UInt
  revision : UInt
  serial : UInt
} derive(Eq, Debug)

///|
pub fn default_master_identity() -> MasterIdentity {
  { vendor_id: 0U, product_code: 0U, revision: 0U, serial: 0U }
}

///|
let moonecat_device_name : String = "MoonECAT"

///|
let moonecat_hw_version : String = "0.1"

///|
let moonecat_sw_version : String = "0.1.0"

///|
/// Build the full master OD from current runtime state.
pub fn build_master_od(
  identity : MasterIdentity,
  scan : ScanReport?,
  telemetry : Telemetry?,
  surface : DiagnosticSurface?,
) -> MasterObjectDictionary {
  let entries : Array[MasterOdEntry] = []
  // 0x1000 Device Type  — 0 for generic master
  entries.push({
    index: 0x1000U,
    subindex: b'\x00',
    name: "Device Type",
    data_type: Unsigned32,
    access: ReadOnly,
    value: U32(0U),
  })
  // 0x1001 Error Register
  let err_reg : Byte = match surface {
    Some(s) =>
      match s.error_register {
        Some(e) => e
        None => b'\x00'
      }
    None => b'\x00'
  }
  entries.push({
    index: 0x1001U,
    subindex: b'\x00',
    name: "Error Register",
    data_type: Unsigned8,
    access: ReadOnly,
    value: U8(err_reg),
  })
  // 0x1008 Manufacturer Device Name
  entries.push({
    index: 0x1008U,
    subindex: b'\x00',
    name: "Manufacturer Device Name",
    data_type: VisibleString,
    access: ReadOnly,
    value: Str(moonecat_device_name),
  })
  // 0x1009 Hardware Version
  entries.push({
    index: 0x1009U,
    subindex: b'\x00',
    name: "Manufacturer Hardware Version",
    data_type: VisibleString,
    access: ReadOnly,
    value: Str(moonecat_hw_version),
  })
  // 0x100A Software Version
  entries.push({
    index: 0x100AU,
    subindex: b'\x00',
    name: "Manufacturer Software Version",
    data_type: VisibleString,
    access: ReadOnly,
    value: Str(moonecat_sw_version),
  })
  // 0x1018 Identity Object (sub0=number of entries, sub1–sub4)
  entries.push({
    index: 0x1018U,
    subindex: b'\x00',
    name: "Identity Object / Number of Entries",
    data_type: Unsigned8,
    access: ReadOnly,
    value: U8(b'\x04'),
  })
  entries.push({
    index: 0x1018U,
    subindex: b'\x01',
    name: "Identity Object / Vendor ID",
    data_type: Unsigned32,
    access: ReadOnly,
    value: U32(identity.vendor_id),
  })
  entries.push({
    index: 0x1018U,
    subindex: b'\x02',
    name: "Identity Object / Product Code",
    data_type: Unsigned32,
    access: ReadOnly,
    value: U32(identity.product_code),
  })
  entries.push({
    index: 0x1018U,
    subindex: b'\x03',
    name: "Identity Object / Revision Number",
    data_type: Unsigned32,
    access: ReadOnly,
    value: U32(identity.revision),
  })
  entries.push({
    index: 0x1018U,
    subindex: b'\x04',
    name: "Identity Object / Serial Number",
    data_type: Unsigned32,
    access: ReadOnly,
    value: U32(identity.serial),
  })
  // 0x10F3 Diagnosis History — aggregated from surface
  let diag_count : UInt = match surface {
    Some(s) =>
      match s.diagnosis_counter {
        Some(c) => c
        None => 0U
      }
    None => 0U
  }
  entries.push({
    index: 0x10F3U,
    subindex: b'\x00',
    name: "Diagnosis History / Maximum Messages",
    data_type: Unsigned8,
    access: ReadOnly,
    value: U8(b'\x01'),
  })
  entries.push({
    index: 0x10F3U,
    subindex: b'\x01',
    name: "Diagnosis History / Newest Message",
    data_type: Unsigned32,
    access: ReadOnly,
    value: U32(diag_count),
  })
  // 0x2000 Slave Count (vendor-specific range)
  let slave_count : Int = match scan {
    Some(s) => s.slave_count
    None => 0
  }
  entries.push({
    index: 0x2000U,
    subindex: b'\x00',
    name: "Slave Count",
    data_type: Unsigned32,
    access: ReadOnly,
    value: U32(slave_count.reinterpret_as_uint()),
  })
  // 0x2001 Runtime Telemetry sub-objects
  match telemetry {
    Some(t) => {
      entries.push({
        index: 0x2001U,
        subindex: b'\x00',
        name: "Runtime Telemetry / Number of Entries",
        data_type: Unsigned8,
        access: ReadOnly,
        value: U8(b'\x09'),
      })
      entries.push({
        index: 0x2001U,
        subindex: b'\x01',
        name: "Runtime Telemetry / Cycles",
        data_type: Unsigned32,
        access: ReadOnly,
        value: U32(t.cycles.to_int().reinterpret_as_uint()),
      })
      entries.push({
        index: 0x2001U,
        subindex: b'\x02',
        name: "Runtime Telemetry / TX Frames",
        data_type: Unsigned32,
        access: ReadOnly,
        value: U32(t.tx_frames.to_int().reinterpret_as_uint()),
      })
      entries.push({
        index: 0x2001U,
        subindex: b'\x03',
        name: "Runtime Telemetry / RX Frames",
        data_type: Unsigned32,
        access: ReadOnly,
        value: U32(t.rx_frames.to_int().reinterpret_as_uint()),
      })
      entries.push({
        index: 0x2001U,
        subindex: b'\x04',
        name: "Runtime Telemetry / Timeouts",
        data_type: Unsigned32,
        access: ReadOnly,
        value: U32(t.timeouts.to_int().reinterpret_as_uint()),
      })
      entries.push({
        index: 0x2001U,
        subindex: b'\x05',
        name: "Runtime Telemetry / Retries",
        data_type: Unsigned32,
        access: ReadOnly,
        value: U32(t.retries.to_int().reinterpret_as_uint()),
      })
      entries.push({
        index: 0x2001U,
        subindex: b'\x06',
        name: "Runtime Telemetry / WKC Errors",
        data_type: Unsigned32,
        access: ReadOnly,
        value: U32(t.wkc_errors.to_int().reinterpret_as_uint()),
      })
      entries.push({
        index: 0x2001U,
        subindex: b'\x07',
        name: "Runtime Telemetry / IRQ Events",
        data_type: Unsigned32,
        access: ReadOnly,
        value: U32(t.irq_events.to_int().reinterpret_as_uint()),
      })
      entries.push({
        index: 0x2001U,
        subindex: b'\x08',
        name: "Runtime Telemetry / DC Delay Updates",
        data_type: Unsigned32,
        access: ReadOnly,
        value: U32(t.dc_delay_updates.to_int().reinterpret_as_uint()),
      })
      entries.push({
        index: 0x2001U,
        subindex: b'\x09',
        name: "Runtime Telemetry / Emergency Events",
        data_type: Unsigned32,
        access: ReadOnly,
        value: U32(t.emergency_events.to_int().reinterpret_as_uint()),
      })
    }
    None => ()
  }
  // 0x2002 Diagnostic Issues count (vendor-specific)
  let issue_count : Int = match surface {
    Some(s) => s.issues.length()
    None => 0
  }
  entries.push({
    index: 0x2002U,
    subindex: b'\x00',
    name: "Diagnostic Issue Count",
    data_type: Unsigned32,
    access: ReadOnly,
    value: U32(issue_count.reinterpret_as_uint()),
  })
  // 0x2003 Overall Diagnostic Level
  let level_code : UInt = match surface {
    Some(s) => diagnostic_level_code(s.overall_level)
    None => 0U
  }
  entries.push({
    index: 0x2003U,
    subindex: b'\x00',
    name: "Overall Diagnostic Level",
    data_type: Unsigned8,
    access: ReadOnly,
    value: U8(level_code.to_byte()),
  })
  { entries, }
}

///|
fn diagnostic_level_code(level : DiagnosticLevel) -> UInt {
  match level {
    Block => 2U
    Degrade => 1U
    Info => 0U
  }
}

///|
/// Lookup a single entry by index and subindex.
pub fn MasterObjectDictionary::lookup(
  self : MasterObjectDictionary,
  index : UInt,
  subindex : Byte,
) -> MasterOdEntry? {
  for entry in self.entries {
    if entry.index == index && entry.subindex == subindex {
      return Some(entry)
    }
  }
  None
}

///|
/// List all unique indices in the dictionary.
pub fn MasterObjectDictionary::indices(
  self : MasterObjectDictionary,
) -> Array[UInt] {
  let seen : Array[UInt] = []
  for entry in self.entries {
    let mut found = false
    for idx in seen {
      if idx == entry.index {
        found = true
        break
      }
    }
    if !found {
      seen.push(entry.index)
    }
  }
  seen
}

///|
/// Get all entries for a given index.
pub fn MasterObjectDictionary::entries_at(
  self : MasterObjectDictionary,
  index : UInt,
) -> Array[MasterOdEntry] {
  self.entries.filter(fn(e) { e.index == index })
}

///|
/// Format an OD value as a human-readable string.
pub fn MasterOdValue::format(self : MasterOdValue) -> String {
  match self {
    U8(v) => "0x" + hex_byte(v)
    U16(v) => "0x" + hex_uint16(v)
    U32(v) => "0x" + hex_uint32(v)
    I32(v) => v.to_string()
    Str(s) => s
    Raw(b) => {
      let mut out = ""
      for i = 0; i < b.length(); i = i + 1 {
        if i > 0 {
          out = out + " "
        }
        out = out + hex_byte(b[i])
      }
      out
    }
  }
}

///|
fn hex_byte(b : Byte) -> String {
  let hi = (b.to_uint() >> 4) & 0xFU
  let lo = b.to_uint() & 0xFU
  hex_nibble(hi).to_string() + hex_nibble(lo).to_string()
}

///|
fn hex_uint16(v : UInt) -> String {
  hex_byte(((v >> 8) & 0xFFU).to_byte()) + hex_byte((v & 0xFFU).to_byte())
}

///|
fn hex_uint32(v : UInt) -> String {
  hex_uint16((v >> 16) & 0xFFFFU) + hex_uint16(v & 0xFFFFU)
}

///|
fn hex_nibble(n : UInt) -> Char {
  if n < 10U {
    (n.reinterpret_as_int() + 0x30).unsafe_to_char()
  } else {
    (n.reinterpret_as_int() - 10 + 0x61).unsafe_to_char()
  }
}

///|
/// Serialize the full OD to JSON.
pub fn MasterObjectDictionary::to_json(self : MasterObjectDictionary) -> Json {
  let items = self.entries.map(fn(entry) { master_od_entry_json(entry) })
  Json::object({
    "object_count": Json::number(self.indices().length().to_double()),
    "entry_count": Json::number(self.entries.length().to_double()),
    "entries": Json::array(items),
  })
}

///|
fn master_od_entry_json(entry : MasterOdEntry) -> Json {
  Json::object({
    "index": Json::number(entry.index.to_double()),
    "index_hex": Json::string("0x" + hex_uint16(entry.index)),
    "subindex": Json::number(entry.subindex.to_uint().to_double()),
    "name": Json::string(entry.name),
    "data_type": Json::string(entry.data_type.to_string()),
    "access": Json::string(entry.access.to_string()),
    "value": master_od_value_json(entry.value),
    "value_formatted": Json::string(entry.value.format()),
  })
}

///|
fn master_od_value_json(value : MasterOdValue) -> Json {
  match value {
    U8(v) => Json::number(v.to_uint().to_double())
    U16(v) => Json::number(v.to_double())
    U32(v) => Json::number(v.to_double())
    I32(v) => Json::number(v.to_double())
    Str(s) => Json::string(s)
    Raw(b) => {
      let mut hex = ""
      for i = 0; i < b.length(); i = i + 1 {
        hex = hex + hex_byte(b[i])
      }
      Json::string(hex)
    }
  }
}

///|
/// Format the full OD as a human-readable text table.
pub fn MasterObjectDictionary::format_text(
  self : MasterObjectDictionary,
) -> String {
  let buf = @buffer.new(size_hint=1024)
  buf.write_string("Master Object Dictionary\n")
  buf.write_string("========================\n")
  let current_indices = self.indices()
  for idx in current_indices {
    let subs = self.entries_at(idx)
    buf.write_string("\n[0x" + hex_uint16(idx) + "] ")
    // Use first entry name (strip "/ ..." suffix if compound)
    match subs[0] {
      { name, .. } => {
        let base_name = od_base_name(name)
        buf.write_string(base_name)
      }
    }
    buf.write_string("\n")
    for entry in subs {
      buf.write_string(
        "  Sub " +
        entry.subindex.to_uint().to_string() +
        ": " +
        entry.value.format() +
        "  (" +
        entry.name +
        ")\n",
      )
    }
  }
  buf.to_string()
}

///|
fn od_base_name(name : String) -> String {
  // Extract text before " / " separator, if present
  let mut i = 0
  while i + 2 < name.length() {
    if name[i] == ' ' && name[i + 1] == '/' && name[i + 2] == ' ' {
      return name[:i].to_string()
    }
    i = i + 1
  }
  name
}
