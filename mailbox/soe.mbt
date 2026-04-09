///|
/// SoE (Servo over EtherCAT) frame encoding and decoding per ETG.1000.6 §5.6.
///
/// SoE header (4 bytes, follows 6-byte mailbox header):
///   Byte 0: opCode[2:0] | incomplete[3] | error[4] | driveNo[7:5]
///   Byte 1: elementflags
///   Bytes 2-3: IDN (LE u16) or fragmentsLeft (LE u16) when incomplete

///|
let soe_header_len : Int = 4

///|
/// SoE OpCode values per ETG.1000.6.
pub(all) enum SoeOpCode {
  ReadReq
  ReadRes
  WriteReq
  WriteRes
  Notification
  Emergency
} derive(Eq, Debug)

///|
pub fn SoeOpCode::to_uint(self : SoeOpCode) -> UInt {
  match self {
    ReadReq => 1U
    ReadRes => 2U
    WriteReq => 3U
    WriteRes => 4U
    Notification => 5U
    Emergency => 6U
  }
}

///|
pub fn SoeOpCode::from_uint(v : UInt) -> SoeOpCode raise @hal.EcError {
  match v {
    1U => ReadReq
    2U => ReadRes
    3U => WriteReq
    4U => WriteRes
    5U => Notification
    6U => Emergency
    _ =>
      raise @hal.EcError::MailboxProtocol(
        "unknown SoE opCode: " + v.reinterpret_as_int().to_string(),
      )
  }
}

///|
/// SoE element flags — select which IDN properties to transfer.
pub(all) enum SoeElementFlag {
  DataState
  Name
  Attribute
  Unit
  Min
  Max
  Value
  Default
} derive(Eq, Debug)

///|
pub fn SoeElementFlag::to_byte(self : SoeElementFlag) -> Byte {
  match self {
    DataState => b'\x01'
    Name => b'\x02'
    Attribute => b'\x04'
    Unit => b'\x08'
    Min => b'\x10'
    Max => b'\x20'
    Value => b'\x40'
    Default => b'\x80'
  }
}

///|
/// Combine multiple element flags into a single byte via bitwise OR.
pub fn soe_element_flags(flags : Array[SoeElementFlag]) -> Byte {
  let mut result : Byte = b'\x00'
  for f in flags {
    result = result | f.to_byte()
  }
  result
}

///|
/// Decoded SoE response.
pub(all) enum SoeResponse {
  /// Successful read response with data payload.
  SoeReadData(
    drive_no~ : UInt,
    element_flags~ : Byte,
    idn~ : UInt,
    incomplete~ : Bool,
    data~ : Bytes
  )
  /// Successful write acknowledgement.
  SoeWriteAck(drive_no~ : UInt, element_flags~ : Byte, idn~ : UInt)
  /// SoE error response with error code.
  SoeError(drive_no~ : UInt, idn~ : UInt, error_code~ : UInt)
  /// Notification from drive.
  SoeNotification(drive_no~ : UInt, idn~ : UInt, data~ : Bytes)
} derive(Eq, Debug)

///|
/// Build first SoE header byte: opCode[2:0] | incomplete[3] | error[4] | driveNo[7:5].
fn build_soe_byte0(
  op_code : SoeOpCode,
  incomplete : Bool,
  drive_no : UInt,
) -> Byte {
  let oc = op_code.to_uint() & 0x7U
  let inc : UInt = if incomplete { 0x8U } else { 0U }
  let dn = (drive_no & 0x7U) << 5
  (oc | inc | dn).to_byte()
}

///|
/// Encode a SoE Read Request.
pub fn encode_soe_read_req(
  counter : Byte,
  drive_no : UInt,
  element_flags : Byte,
  idn : UInt,
) -> Bytes {
  let payload_len = soe_header_len
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: SoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i = 0; i < hdr.length(); i = i + 1 {
    buf.write_byte(hdr[i])
  }
  buf.write_byte(build_soe_byte0(ReadReq, false, drive_no))
  buf.write_byte(element_flags)
  buf.write_byte((idn & 0xFFU).to_byte())
  buf.write_byte(((idn >> 8) & 0xFFU).to_byte())
  buf.to_bytes()
}

///|
/// Encode a SoE Write Request.
pub fn encode_soe_write_req(
  counter : Byte,
  drive_no : UInt,
  element_flags : Byte,
  idn : UInt,
  data : Bytes,
) -> Bytes {
  let payload_len = soe_header_len + data.length()
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: SoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i = 0; i < hdr.length(); i = i + 1 {
    buf.write_byte(hdr[i])
  }
  buf.write_byte(build_soe_byte0(WriteReq, false, drive_no))
  buf.write_byte(element_flags)
  buf.write_byte((idn & 0xFFU).to_byte())
  buf.write_byte(((idn >> 8) & 0xFFU).to_byte())
  for i = 0; i < data.length(); i = i + 1 {
    buf.write_byte(data[i])
  }
  buf.to_bytes()
}

///|
/// Decode a SoE response from a mailbox frame (after mailbox header).
pub fn decode_soe_response(frame : Bytes) -> SoeResponse raise @hal.EcError {
  if frame.length() < mailbox_header_len + soe_header_len {
    raise @hal.EcError::MailboxProtocol(
      "SoE frame too short: " + frame.length().to_string(),
    )
  }
  let mbh = MailboxHeader::from_bytes(frame)
  if mbh.mb_type != SoE {
    raise @hal.EcError::MailboxProtocol(
      "expected SoE mailbox type, got " + mbh.mb_type.to_string(),
    )
  }
  let off = mailbox_header_len
  let byte0 = frame[off]
  let op_code = SoeOpCode::from_uint(byte0.to_uint() & 0x7U)
  let incomplete = (byte0.to_uint() & 0x8U) != 0U
  let is_error = (byte0.to_uint() & 0x10U) != 0U
  let drive_no = (byte0.to_uint() >> 5) & 0x7U
  let element_flags = frame[off + 1]
  let idn = frame[off + 2].to_uint() | (frame[off + 3].to_uint() << 8)
  let data_start = off + soe_header_len
  if is_error {
    // Error code is at end of frame (last 2 bytes)
    let total_len = mailbox_header_len + mbh.length.reinterpret_as_int()
    let error_code = if total_len >= data_start + 2 {
      frame[total_len - 2].to_uint() | (frame[total_len - 1].to_uint() << 8)
    } else {
      0U
    }
    return SoeError(drive_no~, idn~, error_code~)
  }
  match op_code {
    ReadRes => {
      let data = if data_start < frame.length() {
        Bytes::makei(frame.length() - data_start, fn(i) {
          frame[data_start + i]
        })
      } else {
        Bytes::new(0)
      }
      SoeReadData(drive_no~, element_flags~, idn~, incomplete~, data~)
    }
    WriteRes => SoeWriteAck(drive_no~, element_flags~, idn~)
    Notification | Emergency => {
      let data = if data_start < frame.length() {
        Bytes::makei(frame.length() - data_start, fn(i) {
          frame[data_start + i]
        })
      } else {
        Bytes::new(0)
      }
      SoeNotification(drive_no~, idn~, data~)
    }
    _ =>
      raise @hal.EcError::MailboxProtocol(
        "unexpected SoE opCode in response: " + op_code.to_string(),
      )
  }
}
