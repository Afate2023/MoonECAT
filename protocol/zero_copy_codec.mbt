///|
/// Zero-copy in-place codec functions for the PDO hot path.
/// These write/read EtherCAT frames directly into pre-allocated
/// FixedArray[Byte] buffers, avoiding all heap allocation.

///|
/// Write a 16-bit little-endian value into a FixedArray[Byte].
fn write_u16_le_fixed(
  buf : FixedArray[Byte],
  offset : Int,
  value : UInt,
) -> Unit {
  buf[offset] = (value & 0xFFU).reinterpret_as_int().to_byte()
  buf[offset + 1] = ((value >> 8) & 0xFFU).reinterpret_as_int().to_byte()
}

///|
/// Write a 32-bit little-endian value into a FixedArray[Byte].
fn write_u32_le_fixed(
  buf : FixedArray[Byte],
  offset : Int,
  value : UInt,
) -> Unit {
  buf[offset] = (value & 0xFFU).reinterpret_as_int().to_byte()
  buf[offset + 1] = ((value >> 8) & 0xFFU).reinterpret_as_int().to_byte()
  buf[offset + 2] = ((value >> 16) & 0xFFU).reinterpret_as_int().to_byte()
  buf[offset + 3] = ((value >> 24) & 0xFFU).reinterpret_as_int().to_byte()
}

///|
/// Read a 16-bit little-endian value from a FixedArray[Byte].
fn read_u16_le_fixed(buf : FixedArray[Byte], offset : Int) -> UInt {
  buf[offset].to_int().reinterpret_as_uint() |
  (buf[offset + 1].to_int().reinterpret_as_uint() << 8)
}

///|
/// Encode a single LRW PDU frame directly into a FixedArray[Byte] buffer.
/// Returns the total frame length written.
/// This is the zero-allocation hot-path encoder for PDO exchange.
///
/// The frame layout:
///   [Ethernet header 14B] [EtherCAT header 2B] [PDU header 10B] [data] [WKC 2B]
pub fn encode_lrw_frame_into(
  buf : FixedArray[Byte],
  dst_mac : FixedArray[Byte],
  src_mac : FixedArray[Byte],
  index : Byte,
  logical_addr : UInt,
  data : FixedArray[Byte],
  data_offset : Int,
  data_len : Int,
) -> Int {
  let mut pos = 0
  // Ethernet II header: dst MAC (6 bytes)
  for i in 0..<6 {
    buf[pos + i] = dst_mac[i]
  }
  pos = pos + 6
  // Src MAC (6 bytes)
  for i in 0..<6 {
    buf[pos + i] = src_mac[i]
  }
  pos = pos + 6
  // EtherType: 0x88A4 big-endian
  buf[pos] = b'\x88'
  buf[pos + 1] = b'\xA4'
  pos = pos + 2
  // EtherCAT header: pdu_payload_len[10:0] | type[15:12]
  let pdu_payload_len = pdu_header_len + data_len + wkc_len
  let ecat_hdr = (pdu_payload_len.reinterpret_as_uint() & 0x7FFU) |
    (ecat_frame_type.reinterpret_as_uint() << 12)
  write_u16_le_fixed(buf, pos, ecat_hdr)
  pos = pos + 2
  // PDU header
  buf[pos] = EcCommand::LRW.to_byte() // command
  buf[pos + 1] = index // index
  write_u32_le_fixed(buf, pos + 2, logical_addr) // address
  // len_flags: data_len[10:0], more=0 (last PDU)
  let len_flags = data_len.reinterpret_as_uint() & 0x7FFU
  write_u16_le_fixed(buf, pos + 6, len_flags)
  // IRQ = 0
  write_u16_le_fixed(buf, pos + 8, 0U)
  pos = pos + pdu_header_len
  // Data payload: copy from source
  for i = 0; i < data_len; i = i + 1 {
    buf[pos + i] = data[data_offset + i]
  }
  pos = pos + data_len
  // WKC = 0 (will be filled by slaves)
  write_u16_le_fixed(buf, pos, 0U)
  pos = pos + wkc_len
  pos
}

///|
/// Encode a single command PDU frame into a FixedArray[Byte] buffer.
/// More general than encode_lrw_frame_into — supports any EcCommand.
/// Returns the total frame length written.
pub fn encode_pdu_frame_into(
  buf : FixedArray[Byte],
  dst_mac : FixedArray[Byte],
  src_mac : FixedArray[Byte],
  command : EcCommand,
  index : Byte,
  address : UInt,
  data : FixedArray[Byte],
  data_offset : Int,
  data_len : Int,
) -> Int {
  let mut pos = 0
  // Ethernet II header
  for i in 0..<6 {
    buf[pos + i] = dst_mac[i]
  }
  pos = pos + 6
  for i in 0..<6 {
    buf[pos + i] = src_mac[i]
  }
  pos = pos + 6
  buf[pos] = b'\x88'
  buf[pos + 1] = b'\xA4'
  pos = pos + 2
  // EtherCAT header
  let pdu_payload_len = pdu_header_len + data_len + wkc_len
  let ecat_hdr = (pdu_payload_len.reinterpret_as_uint() & 0x7FFU) |
    (ecat_frame_type.reinterpret_as_uint() << 12)
  write_u16_le_fixed(buf, pos, ecat_hdr)
  pos = pos + 2
  // PDU header
  buf[pos] = command.to_byte()
  buf[pos + 1] = index
  write_u32_le_fixed(buf, pos + 2, address)
  let len_flags = data_len.reinterpret_as_uint() & 0x7FFU
  write_u16_le_fixed(buf, pos + 6, len_flags)
  write_u16_le_fixed(buf, pos + 8, 0U)
  pos = pos + pdu_header_len
  // Data
  for i = 0; i < data_len; i = i + 1 {
    buf[pos + i] = data[data_offset + i]
  }
  pos = pos + data_len
  // WKC = 0
  write_u16_le_fixed(buf, pos, 0U)
  pos = pos + wkc_len
  pos
}

///|
/// Decode the first PDU's WKC and data from a received frame in a FixedArray[Byte].
/// Extracts WKC and copies input data back into the target buffer.
/// Returns (wkc, irq) on success.
/// This is the zero-allocation hot-path decoder for PDO exchange.
pub fn decode_pdu_response_from(
  buf : FixedArray[Byte],
  buf_len : Int,
  target : FixedArray[Byte],
  target_offset : Int,
  target_len : Int,
) -> (UInt, UInt) raise @hal.EcError {
  // Validate minimum frame size
  let min_size = ethernet_header_len + ecat_header_len + pdu_header_len
  if buf_len < min_size {
    raise @hal.EcError::InvalidFrame("frame too short: " + buf_len.to_string())
  }
  // Validate EtherType
  let ethertype = (buf[12].to_int() << 8) | buf[13].to_int()
  if ethertype != @hal.ethercat_ethertype {
    raise @hal.EcError::InvalidFrame(
      "wrong ethertype: 0x" + ethertype.to_string(),
    )
  }
  // Validate EtherCAT frame type
  let ecat_hdr = read_u16_le_fixed(buf, ethernet_header_len)
  let frame_type = ((ecat_hdr >> 12) & 0xFU).reinterpret_as_int()
  if frame_type != ecat_frame_type {
    raise @hal.EcError::InvalidFrame(
      "wrong ecat type: " + frame_type.to_string(),
    )
  }
  // Parse first PDU header
  let pdu_offset = ethernet_header_len + ecat_header_len
  if pdu_offset + pdu_header_len > buf_len {
    raise @hal.EcError::InvalidPdu("PDU header truncated")
  }
  let len_flags = read_u16_le_fixed(buf, pdu_offset + 6)
  let pdu_data_len = (len_flags & 0x7FFU).reinterpret_as_int()
  let irq = read_u16_le_fixed(buf, pdu_offset + 8)
  let data_start = pdu_offset + pdu_header_len
  // Validate enough data
  if data_start + pdu_data_len + wkc_len > buf_len {
    raise @hal.EcError::InvalidPdu("PDU data truncated")
  }
  // Copy response data into target at the specified offset
  let copy_len = if target_len < pdu_data_len {
    target_len
  } else {
    pdu_data_len
  }
  for i = 0; i < copy_len; i = i + 1 {
    target[target_offset + i] = buf[data_start + i]
  }
  // Read WKC
  let wkc = read_u16_le_fixed(buf, data_start + pdu_data_len)
  (wkc, irq)
}

///|
/// Decode the first PDU from a received frame, copying only a sub-range of
/// the PDU data into the target buffer. Used for LRW responses where we only
/// want the input portion (skipping the output echo).
/// Returns (wkc, irq) on success.
pub fn decode_pdu_response_slice(
  buf : FixedArray[Byte],
  buf_len : Int,
  skip : Int,
  target : FixedArray[Byte],
  target_offset : Int,
  target_len : Int,
) -> (UInt, UInt) raise @hal.EcError {
  let min_size = ethernet_header_len + ecat_header_len + pdu_header_len
  if buf_len < min_size {
    raise @hal.EcError::InvalidFrame("frame too short: " + buf_len.to_string())
  }
  let ethertype = (buf[12].to_int() << 8) | buf[13].to_int()
  if ethertype != @hal.ethercat_ethertype {
    raise @hal.EcError::InvalidFrame(
      "wrong ethertype: 0x" + ethertype.to_string(),
    )
  }
  let ecat_hdr = read_u16_le_fixed(buf, ethernet_header_len)
  let frame_type = ((ecat_hdr >> 12) & 0xFU).reinterpret_as_int()
  if frame_type != ecat_frame_type {
    raise @hal.EcError::InvalidFrame(
      "wrong ecat type: " + frame_type.to_string(),
    )
  }
  let pdu_offset = ethernet_header_len + ecat_header_len
  if pdu_offset + pdu_header_len > buf_len {
    raise @hal.EcError::InvalidPdu("PDU header truncated")
  }
  let len_flags = read_u16_le_fixed(buf, pdu_offset + 6)
  let pdu_data_len = (len_flags & 0x7FFU).reinterpret_as_int()
  let irq = read_u16_le_fixed(buf, pdu_offset + 8)
  let data_start = pdu_offset + pdu_header_len
  if data_start + pdu_data_len + wkc_len > buf_len {
    raise @hal.EcError::InvalidPdu("PDU data truncated")
  }
  // Copy from data_start + skip into target
  let avail = pdu_data_len - skip
  let copy_len = if target_len < avail { target_len } else { avail }
  for i = 0; i < copy_len; i = i + 1 {
    target[target_offset + i] = buf[data_start + skip + i]
  }
  let wkc = read_u16_le_fixed(buf, data_start + pdu_data_len)
  (wkc, irq)
}

///|
/// Encode a PDU frame with a zero-filled data payload (no source array needed).
/// Used for LRD requests where the outgoing data is all zeros.
/// Returns the total frame length.
pub fn encode_zero_data_frame_into(
  buf : FixedArray[Byte],
  dst_mac : FixedArray[Byte],
  src_mac : FixedArray[Byte],
  command : EcCommand,
  index : Byte,
  address : UInt,
  data_len : Int,
) -> Int {
  let mut pos = 0
  // Ethernet II header
  for i in 0..<6 {
    buf[pos + i] = dst_mac[i]
  }
  pos = pos + 6
  for i in 0..<6 {
    buf[pos + i] = src_mac[i]
  }
  pos = pos + 6
  buf[pos] = b'\x88'
  buf[pos + 1] = b'\xA4'
  pos = pos + 2
  // EtherCAT header
  let pdu_payload_len = pdu_header_len + data_len + wkc_len
  let ecat_hdr = (pdu_payload_len.reinterpret_as_uint() & 0x7FFU) |
    (ecat_frame_type.reinterpret_as_uint() << 12)
  write_u16_le_fixed(buf, pos, ecat_hdr)
  pos = pos + 2
  // PDU header
  buf[pos] = command.to_byte()
  buf[pos + 1] = index
  write_u32_le_fixed(buf, pos + 2, address)
  let len_flags = data_len.reinterpret_as_uint() & 0x7FFU
  write_u16_le_fixed(buf, pos + 6, len_flags)
  write_u16_le_fixed(buf, pos + 8, 0U) // IRQ
  pos = pos + pdu_header_len
  // Data: all zeros
  for i = 0; i < data_len; i = i + 1 {
    buf[pos + i] = b'\x00'
  }
  pos = pos + data_len
  // WKC = 0
  write_u16_le_fixed(buf, pos, 0U)
  pos = pos + wkc_len
  pos
}

///|
/// Decode only the WKC from the first PDU in a received frame.
/// Used for LWR responses where we don't need the response data.
/// Zero allocation.
pub fn decode_pdu_wkc_only(
  buf : FixedArray[Byte],
  buf_len : Int,
) -> UInt raise @hal.EcError {
  let min_size = ethernet_header_len + ecat_header_len + pdu_header_len
  if buf_len < min_size {
    raise @hal.EcError::InvalidFrame("frame too short: " + buf_len.to_string())
  }
  let ethertype = (buf[12].to_int() << 8) | buf[13].to_int()
  if ethertype != @hal.ethercat_ethertype {
    raise @hal.EcError::InvalidFrame(
      "wrong ethertype: 0x" + ethertype.to_string(),
    )
  }
  let ecat_hdr = read_u16_le_fixed(buf, ethernet_header_len)
  let frame_type = ((ecat_hdr >> 12) & 0xFU).reinterpret_as_int()
  if frame_type != ecat_frame_type {
    raise @hal.EcError::InvalidFrame(
      "wrong ecat type: " + frame_type.to_string(),
    )
  }
  let pdu_offset = ethernet_header_len + ecat_header_len
  if pdu_offset + pdu_header_len > buf_len {
    raise @hal.EcError::InvalidPdu("PDU header truncated")
  }
  let len_flags = read_u16_le_fixed(buf, pdu_offset + 6)
  let pdu_data_len = (len_flags & 0x7FFU).reinterpret_as_int()
  let data_start = pdu_offset + pdu_header_len
  if data_start + pdu_data_len + wkc_len > buf_len {
    raise @hal.EcError::InvalidPdu("PDU data truncated")
  }
  read_u16_le_fixed(buf, data_start + pdu_data_len)
}
