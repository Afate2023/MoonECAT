///|
/// VirtualSlave CoE/SDO mailbox emulation (B-9).
///
/// Extends the VirtualSlave simulation with basic CoE SDO upload/download
/// and Emergency message injection, enabling protocol-level verification
/// of the mailbox resilient layer without real hardware.

///|
/// OdEntry represents one pre-configured object dictionary entry on a VirtualSlave.
pub(all) struct OdEntry {
  index : UInt
  subindex : Byte
  data : Bytes
  access : OdAccess
} derive(Show)

///|
/// OdAccess flags for object dictionary entries.
pub(all) enum OdAccess {
  ReadOnly
  ReadWrite
  WriteOnly
} derive(Eq, Show)

///|
/// VirtualMailbox holds the mailbox emulation state for one VirtualSlave.
pub(all) struct VirtualMailbox {
  /// Pre-configured object dictionary entries.
  od : Array[OdEntry]
  /// Outgoing mailbox queue (slave→master): emergency, SDO response, etc.
  outbox : Array[Bytes]
  /// Incoming mailbox queue (master→slave): SDO request, etc.
  inbox : Array[Bytes]
  /// Mailbox counter (wraps 1-7 per ETG.1000.4).
  mut counter : Int
  /// Pending emergency messages to emit.
  emergencies : Array[EmergencyEvent]
} derive(Show)

///|
/// EmergencyEvent describes a scheduled CoE Emergency message.
pub(all) struct EmergencyEvent {
  error_code : UInt
  error_register : Byte
  data : Bytes
  /// Cycle at which to emit this emergency (0 = immediately).
  at_cycle : Int64
  mut emitted : Bool
} derive(Show)

///|
pub fn VirtualMailbox::new() -> VirtualMailbox {
  { od: [], outbox: [], inbox: [], counter: 1, emergencies: [] }
}

///|
/// Add an OD entry for SDO emulation.
pub fn VirtualMailbox::add_od(
  self : VirtualMailbox,
  index : UInt,
  subindex : Byte,
  data : Bytes,
  access? : OdAccess = ReadWrite,
) -> Unit {
  self.od.push({ index, subindex, data, access })
}

///|
/// Schedule an Emergency message.
pub fn VirtualMailbox::add_emergency(
  self : VirtualMailbox,
  error_code : UInt,
  error_register : Byte,
  data? : Bytes = Bytes::new(5),
  at_cycle? : Int64 = 0L,
) -> Unit {
  self.emergencies.push({
    error_code,
    error_register,
    data,
    at_cycle,
    emitted: false,
  })
}

///|
/// Next mailbox counter (1-7 wrapping).
pub fn VirtualMailbox::next_counter(self : VirtualMailbox) -> Int {
  let c = self.counter
  self.counter = if self.counter >= 7 { 1 } else { self.counter + 1 }
  c
}

///|
/// Look up an OD entry by index+subindex.
pub fn VirtualMailbox::find_od(
  self : VirtualMailbox,
  index : UInt,
  subindex : Byte,
) -> OdEntry? {
  for entry in self.od {
    if entry.index == index && entry.subindex == subindex {
      return Some(entry)
    }
  }
  None
}

///|
/// Process an SDO upload request (master reads from slave OD).
/// Returns the SDO upload response frame bytes, or None if index not found.
pub fn VirtualMailbox::handle_sdo_upload(
  self : VirtualMailbox,
  index : UInt,
  subindex : Byte,
) -> Bytes? {
  match self.find_od(index, subindex) {
    Some(entry) =>
      match entry.access {
        WriteOnly => Some(build_sdo_abort(index, subindex, 0x06010001U))
        _ => {
          let cnt = self.next_counter()
          Some(build_sdo_upload_response(index, subindex, entry.data, cnt))
        }
      }
    None => Some(build_sdo_abort(index, subindex, 0x06020000U))
  }
}

///|
/// Process an SDO download request (master writes to slave OD).
/// Returns the SDO download response frame bytes.
pub fn VirtualMailbox::handle_sdo_download(
  self : VirtualMailbox,
  index : UInt,
  subindex : Byte,
  data : Bytes,
) -> Bytes {
  match self.find_od(index, subindex) {
    Some(entry) =>
      match entry.access {
        ReadOnly => build_sdo_abort(index, subindex, 0x06010002U)
        _ => {
          // Update the OD entry data (find and replace)
          for i, e in self.od {
            if e.index == index && e.subindex == subindex {
              self.od[i] = { ..e, data, }
              break
            }
          }
          let cnt = self.next_counter()
          build_sdo_download_response(index, subindex, cnt)
        }
      }
    None => {
      // Auto-create if not found
      self.od.push({ index, subindex, data, access: ReadWrite })
      let cnt = self.next_counter()
      build_sdo_download_response(index, subindex, cnt)
    }
  }
}

///|
/// Check and emit due emergency messages for the given cycle.
pub fn VirtualMailbox::emit_emergencies(
  self : VirtualMailbox,
  current_cycle : Int64,
) -> Array[Bytes] {
  let result : Array[Bytes] = []
  for emg in self.emergencies {
    if !emg.emitted && current_cycle >= emg.at_cycle {
      emg.emitted = true
      result.push(
        build_emergency_frame(emg.error_code, emg.error_register, emg.data),
      )
    }
  }
  result
}

///|
/// Build an expedited SDO upload response (≤4 bytes).
fn build_sdo_upload_response(
  index : UInt,
  subindex : Byte,
  data : Bytes,
  counter : Int,
) -> Bytes {
  // CoE header (2) + SDO header (4) + data (up to 4)
  let data_len = if data.length() > 4 { 4 } else { data.length() }
  let size_indicator = (4 - data_len) << 2
  let frame_len = 10
  let buf = FixedArray::make(frame_len, b'\x00')
  // Mailbox header (simplified): length(2) + address(2) + channel+cnt(1) + type(1)
  let mbx_len = frame_len - 6
  buf[0] = (mbx_len & 0xFF).to_byte()
  buf[1] = ((mbx_len >> 8) & 0xFF).to_byte()
  buf[4] = (counter & 0x07).to_byte()
  buf[5] = b'\x03' // CoE type
  // CoE SDO response: command specifier 0x02 (upload response) + size + expedited + size_indicator
  buf[6] = (0x42 | size_indicator).to_byte()
  buf[7] = (index.reinterpret_as_int() & 0xFF).to_byte()
  buf[8] = ((index.reinterpret_as_int() >> 8) & 0xFF).to_byte()
  buf[9] = subindex
  Bytes::from_array(buf)
}

///|
/// Build an SDO download response.
fn build_sdo_download_response(
  index : UInt,
  subindex : Byte,
  counter : Int,
) -> Bytes {
  let frame_len = 10
  let buf = FixedArray::make(frame_len, b'\x00')
  let mbx_len = frame_len - 6
  buf[0] = (mbx_len & 0xFF).to_byte()
  buf[1] = ((mbx_len >> 8) & 0xFF).to_byte()
  buf[4] = (counter & 0x07).to_byte()
  buf[5] = b'\x03' // CoE type
  buf[6] = b'\x60' // Download response
  buf[7] = (index.reinterpret_as_int() & 0xFF).to_byte()
  buf[8] = ((index.reinterpret_as_int() >> 8) & 0xFF).to_byte()
  buf[9] = subindex
  Bytes::from_array(buf)
}

///|
/// Build an SDO abort transfer frame.
fn build_sdo_abort(index : UInt, subindex : Byte, abort_code : UInt) -> Bytes {
  let frame_len = 14
  let buf = FixedArray::make(frame_len, b'\x00')
  let mbx_len = frame_len - 6
  buf[0] = (mbx_len & 0xFF).to_byte()
  buf[1] = ((mbx_len >> 8) & 0xFF).to_byte()
  buf[5] = b'\x03'
  buf[6] = b'\x80' // Abort
  buf[7] = (index.reinterpret_as_int() & 0xFF).to_byte()
  buf[8] = ((index.reinterpret_as_int() >> 8) & 0xFF).to_byte()
  buf[9] = subindex
  buf[10] = (abort_code.reinterpret_as_int() & 0xFF).to_byte()
  buf[11] = ((abort_code.reinterpret_as_int() >> 8) & 0xFF).to_byte()
  buf[12] = ((abort_code.reinterpret_as_int() >> 16) & 0xFF).to_byte()
  buf[13] = ((abort_code.reinterpret_as_int() >> 24) & 0xFF).to_byte()
  Bytes::from_array(buf)
}

///|
/// Build a CoE Emergency frame.
fn build_emergency_frame(
  error_code : UInt,
  error_register : Byte,
  data : Bytes,
) -> Bytes {
  // EmergencyFrame: mbx_header(6) + error_code(2) + error_register(1) + data(5)
  let frame_len = 14
  let buf = FixedArray::make(frame_len, b'\x00')
  let mbx_len = frame_len - 6
  buf[0] = (mbx_len & 0xFF).to_byte()
  buf[1] = ((mbx_len >> 8) & 0xFF).to_byte()
  buf[5] = b'\x03' // CoE type
  // CoE header: Emergency type (0x01 << 12)
  buf[6] = (error_code.reinterpret_as_int() & 0xFF).to_byte()
  buf[7] = ((error_code.reinterpret_as_int() >> 8) & 0xFF).to_byte()
  buf[8] = error_register
  // Copy up to 5 bytes of manufacturer-specific data
  let data_len = if data.length() > 5 { 5 } else { data.length() }
  for i in 0..<data_len {
    buf[9 + i] = data[i]
  }
  Bytes::from_array(buf)
}
