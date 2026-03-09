///|
/// Helper to read a little-endian UInt16 from Bytes at the given offset.
fn read_u16_le(data : Bytes, offset : Int) -> UInt {
  data[offset].to_int().reinterpret_as_uint() |
  (data[offset + 1].to_int().reinterpret_as_uint() << 8)
}

///|
/// Helper to read a little-endian UInt32 from Bytes at the given offset.
fn read_u32_le(data : Bytes, offset : Int) -> UInt {
  data[offset].to_int().reinterpret_as_uint() |
  (data[offset + 1].to_int().reinterpret_as_uint() << 8) |
  (data[offset + 2].to_int().reinterpret_as_uint() << 16) |
  (data[offset + 3].to_int().reinterpret_as_uint() << 24)
}

///|
/// Helper to write a little-endian UInt16 to a Buffer.
fn write_u16_le(buf : @buffer.Buffer, value : UInt) -> Unit {
  buf.write_byte((value & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 8) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
/// Helper to write a little-endian UInt32 to a Buffer.
fn write_u32_le(buf : @buffer.Buffer, value : UInt) -> Unit {
  buf.write_byte((value & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 24) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
/// Encode a single PDU into the buffer.
fn encode_pdu(buf : @buffer.Buffer, pdu : Pdu, is_last : Bool) -> Unit {
  // Command byte
  buf.write_byte(pdu.header.command.to_byte())
  // Index
  buf.write_byte(pdu.header.index)
  // Address (4 bytes LE)
  write_u32_le(buf, pdu.header.address)
  // Length and flags: data_len[10:0], R[13:11], C[14], M[15]
  let data_len = pdu.data.length().reinterpret_as_uint()
  let more : UInt = if is_last { 0U } else { 1U }
  let len_flags = (data_len & 0x7FFU) | (more << 15)
  write_u16_le(buf, len_flags)
  // IRQ (2 bytes, typically 0)
  write_u16_le(buf, 0U)
  // Data payload
  buf.write_bytes(pdu.data)
  // Working counter (2 bytes LE)
  write_u16_le(buf, pdu.wkc)
}

///|
/// Encode an EcFrame into raw Ethernet bytes.
pub fn EcFrame::encode(self : EcFrame) -> Bytes {
  let buf = @buffer.new(size_hint=@hal.max_frame_size)
  // Ethernet II header: dst MAC
  for i in 0..<6 {
    buf.write_byte(self.dst_mac[i])
  }
  // Src MAC
  for i in 0..<6 {
    buf.write_byte(self.src_mac[i])
  }
  // EtherType: 0x88A4 big-endian
  buf.write_byte(b'\x88')
  buf.write_byte(b'\xA4')
  // Calculate total PDU payload length (for EtherCAT header)
  let mut pdu_total_len = 0
  for pdu in self.pdus {
    pdu_total_len = pdu_total_len + pdu_header_len + pdu.data.length() + wkc_len
  }
  // EtherCAT header: length[10:0] + reserved[11] + type[15:12]
  let ecat_hdr = (pdu_total_len.reinterpret_as_uint() & 0x7FFU) |
    (ecat_frame_type.reinterpret_as_uint() << 12)
  write_u16_le(buf, ecat_hdr)
  // Encode each PDU
  for i, pdu in self.pdus {
    let is_last = i == self.pdus.length() - 1
    encode_pdu(buf, pdu, is_last)
  }
  buf.to_bytes()
}

///|
/// Decode an EcFrame from raw Ethernet bytes.
pub fn EcFrame::decode(data : Bytes) -> EcFrame raise @hal.EcError {
  if data.length() < ethernet_header_len + ecat_header_len {
    raise @hal.EcError::InvalidFrame(
      "frame too short: " + data.length().to_string(),
    )
  }
  // Parse Ethernet header
  let dst_mac : FixedArray[Byte] = FixedArray::make(6, b'\x00')
  let src_mac : FixedArray[Byte] = FixedArray::make(6, b'\x00')
  for i in 0..<6 {
    dst_mac[i] = data[i]
    src_mac[i] = data[i + 6]
  }
  // Check EtherType
  let ethertype = (data[12].to_int() << 8) | data[13].to_int()
  if ethertype != @hal.ethercat_ethertype {
    raise @hal.EcError::InvalidFrame(
      "wrong ethertype: 0x" + ethertype.to_string(),
    )
  }
  // Parse EtherCAT header
  let ecat_hdr = read_u16_le(data, ethernet_header_len)
  let payload_len = (ecat_hdr & 0x7FFU).reinterpret_as_int()
  let frame_type = ((ecat_hdr >> 12) & 0xFU).reinterpret_as_int()
  if frame_type != ecat_frame_type {
    raise @hal.EcError::InvalidFrame(
      "wrong ecat type: " + frame_type.to_string(),
    )
  }
  // Parse PDUs
  let pdus : Array[Pdu] = []
  let mut offset = ethernet_header_len + ecat_header_len
  let end_offset = ethernet_header_len + ecat_header_len + payload_len
  while offset < end_offset {
    if offset + pdu_header_len > data.length() {
      raise @hal.EcError::InvalidPdu(
        "PDU header truncated at offset " + offset.to_string(),
      )
    }
    let command = EcCommand::from_byte(data[offset])
    let index = data[offset + 1]
    let address = read_u32_le(data, offset + 2)
    let len_flags = read_u16_le(data, offset + 6)
    let data_len = (len_flags & 0x7FFU).reinterpret_as_int()
    let more = ((len_flags >> 15) & 1U).reinterpret_as_int()
    // Skip IRQ at offset+8..offset+10
    offset = offset + pdu_header_len
    if offset + data_len + wkc_len > data.length() {
      raise @hal.EcError::InvalidPdu("PDU data truncated")
    }
    // Extract data payload
    let pdu_data = if data_len > 0 {
      Bytes::makei(data_len, fn(i) { data[offset + i] })
    } else {
      Bytes::new(0)
    }
    offset = offset + data_len
    // Working counter
    let wkc = read_u16_le(data, offset)
    offset = offset + wkc_len
    pdus.push({
      header: { command, index, address, len_flags },
      data: pdu_data,
      wkc,
    })
    if more == 0 {
      break
    }
  }
  { dst_mac, src_mac, pdus }
}
