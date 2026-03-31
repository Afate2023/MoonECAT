///|
/// Protocol deviation injection (B-10).
///
/// Extends the fault injection framework with protocol-level deviations:
/// malformed frames, PDU length violations, and positional WKC corruption.
/// These model real-world protocol stack errors and interoperability issues.

///|
/// ProtocolDeviation describes a specific protocol-level fault that can
/// be applied to an EtherCAT frame before or after transmission.
pub(all) enum ProtocolDeviation {
  /// Truncate the frame to N bytes (simulating partial reception).
  TruncateFrame(Int)
  /// Insert extra bytes at the given offset (PDU length overflow).
  PadFrame(offset~ : Int, count~ : Int)
  /// Corrupt the EtherCAT header length field (byte 14-15 of Ethernet frame).
  CorruptEcatLength(delta~ : Int)
  /// Corrupt a specific PDU's data at the given PDU-relative offset.
  CorruptPduData(pdu_index~ : Int, offset~ : Int, value~ : Byte)
  /// Set the PDU command type to an invalid value.
  InvalidPduCommand(pdu_index~ : Int, command~ : Byte)
  /// Zero out the entire frame (complete corruption).
  ZeroFrame
} derive(Show)

///|
/// Apply a protocol deviation to raw frame data.
/// Returns the modified frame, or the original if the deviation
/// cannot be applied (e.g., offsets out of range).
pub fn apply_protocol_deviation(
  deviation : ProtocolDeviation,
  data : Bytes,
) -> Bytes {
  match deviation {
    TruncateFrame(n) =>
      if n >= 0 && n < data.length() {
        Bytes::makei(n, fn(i) { data[i] })
      } else {
        data
      }
    PadFrame(offset~, count~) =>
      if offset >= 0 && offset <= data.length() && count > 0 {
        let new_len = data.length() + count
        let buf = FixedArray::make(new_len, b'\x00')
        for i in 0..<offset {
          buf[i] = data[i]
        }
        // Padding bytes are already zero
        for i in offset..<data.length() {
          buf[i + count] = data[i]
        }
        Bytes::from_array(buf)
      } else {
        data
      }
    CorruptEcatLength(delta~) =>
      // EtherCAT header is at bytes 14-15 of an Ethernet frame.
      // Lower 11 bits = EtherCAT PDU length.
      if data.length() > 15 {
        let buf = FixedArray::make(data.length(), b'\x00')
        for i in 0..<data.length() {
          buf[i] = data[i]
        }
        let lo = data[14].to_int()
        let hi = data[15].to_int()
        let ecat_len = (lo | (hi << 8)) & 0x07FF
        let new_len = ecat_len + delta
        buf[14] = (new_len & 0xFF).to_byte()
        buf[15] = ((data[15].to_int() & 0xF8) | ((new_len >> 8) & 0x07)).to_byte()
        Bytes::from_array(buf)
      } else {
        data
      }
    CorruptPduData(pdu_index~, offset~, value~) =>
      // For simplicity, assume single-PDU frames: PDU data starts at byte 16+10
      // (14 eth + 2 ecat header + 10 PDU header)
      if pdu_index == 0 {
        let pdu_data_start = 26
        let abs_offset = pdu_data_start + offset
        if abs_offset >= 0 && abs_offset < data.length() {
          let buf = FixedArray::make(data.length(), b'\x00')
          for i in 0..<data.length() {
            buf[i] = data[i]
          }
          buf[abs_offset] = value
          Bytes::from_array(buf)
        } else {
          data
        }
      } else {
        data
      }
    InvalidPduCommand(pdu_index~, command~) =>
      // PDU command byte is at offset 16 (for first PDU in a single-PDU frame)
      if pdu_index == 0 && data.length() > 16 {
        let buf = FixedArray::make(data.length(), b'\x00')
        for i in 0..<data.length() {
          buf[i] = data[i]
        }
        buf[16] = command
        Bytes::from_array(buf)
      } else {
        data
      }
    ZeroFrame => Bytes::new(data.length())
  }
}
