///|
/// Mailbox header size in bytes.
let mailbox_header_len : Int = 6

///|
/// Generic mailbox error type (ETG.1000.4 Table 30).
pub(all) enum MailboxErrorType {
  MailboxCommand
  Unknown(UInt)
} derive(Eq, Debug)

///|
/// Generic mailbox error detail (ETG.1000.4 Table 30).
/// ServiceInWork is the later ETG/implementation extension used by common
/// reference stacks; unknown values are preserved for forward compatibility.
pub(all) enum MailboxErrorDetail {
  Syntax
  UnsupportedProtocol
  InvalidChannel
  ServiceNotSupported
  InvalidHeader
  SizeTooShort
  NoMoreMemory
  InvalidSize
  ServiceInWork
  Unknown(UInt)
} derive(Eq, Debug)

///|
/// Decoded generic mailbox error payload.
pub(all) struct MailboxError {
  error_type : MailboxErrorType
  detail : MailboxErrorDetail
} derive(Eq, Debug)

///|
/// A mailbox frame bounded by the Length declared in its header.
/// Bytes beyond payload belong to the physical SyncManager window and are not
/// part of this protocol entity.
pub(all) struct MailboxFrame {
  header : MailboxHeader
  payload : Bytes
} derive(Eq, Debug)

///|
pub fn MailboxErrorType::from_uint(value : UInt) -> MailboxErrorType {
  match value {
    1U => MailboxCommand
    other => Unknown(other)
  }
}

///|
pub fn MailboxErrorType::to_uint(self : MailboxErrorType) -> UInt {
  match self {
    MailboxCommand => 1U
    Unknown(value) => value
  }
}

///|
pub fn MailboxErrorDetail::from_uint(value : UInt) -> MailboxErrorDetail {
  match value {
    1U => Syntax
    2U => UnsupportedProtocol
    3U => InvalidChannel
    4U => ServiceNotSupported
    5U => InvalidHeader
    6U => SizeTooShort
    7U => NoMoreMemory
    8U => InvalidSize
    9U => ServiceInWork
    other => Unknown(other)
  }
}

///|
pub fn MailboxErrorDetail::to_uint(self : MailboxErrorDetail) -> UInt {
  match self {
    Syntax => 1U
    UnsupportedProtocol => 2U
    InvalidChannel => 3U
    ServiceNotSupported => 4U
    InvalidHeader => 5U
    SizeTooShort => 6U
    NoMoreMemory => 7U
    InvalidSize => 8U
    ServiceInWork => 9U
    Unknown(value) => value
  }
}

///|
pub fn MailboxErrorDetail::label(self : MailboxErrorDetail) -> String {
  match self {
    Syntax => "syntax"
    UnsupportedProtocol => "unsupported protocol"
    InvalidChannel => "invalid channel"
    ServiceNotSupported => "service not supported"
    InvalidHeader => "invalid header"
    SizeTooShort => "size too short"
    NoMoreMemory => "no more memory"
    InvalidSize => "invalid size"
    ServiceInWork => "service in work"
    Unknown(value) => "unknown detail " + value.reinterpret_as_int().to_string()
  }
}

///|
/// Encode a mailbox header into 6 bytes.
pub fn MailboxHeader::to_bytes(self : MailboxHeader) -> Bytes {
  let buf = Buffer(size_hint=mailbox_header_len)
  buf.write_byte((self.length & 0xFFU).to_byte())
  buf.write_byte(((self.length >> 8) & 0xFFU).to_byte())
  buf.write_byte((self.address & 0xFFU).to_byte())
  buf.write_byte(((self.address >> 8) & 0xFFU).to_byte())
  // Channel is U6, Priority is U2.
  let b4 = (self.channel & b'\x3F') | ((self.priority & b'\x03') << 6)
  buf.write_byte(b4)
  // Type[3:0] | Counter[6:4], bit 7 remains reserved.
  let b5 = self.mb_type.to_byte() | ((self.counter & b'\x07') << 4)
  buf.write_byte(b5)
  buf.to_bytes()
}

///|
/// Decode a mailbox header from bytes (needs at least 6 bytes).
pub fn MailboxHeader::from_bytes(
  data : Bytes,
) -> MailboxHeader raise @hal.EcError {
  if data.length() < mailbox_header_len {
    raise @hal.EcError::MailboxProtocol("mailbox header too short")
  }
  if (data[5] & b'\x80') != b'\x00' {
    raise @hal.EcError::MailboxProtocol("mailbox header reserved bit is set")
  }
  let length = data[0].to_uint() | (data[1].to_uint() << 8)
  let address = data[2].to_uint() | (data[3].to_uint() << 8)
  let channel = data[4] & b'\x3F'
  let priority = (data[4] >> 6) & b'\x03'
  let type_byte = data[5] & b'\x0F'
  let counter = (data[5] >> 4) & b'\x07'
  let mb_type : MailboxType = match type_byte {
    b'\x00' => Err
    b'\x01' => AoE
    b'\x02' => EoE
    b'\x03' => CoE
    b'\x04' => FoE
    b'\x05' => SoE
    b'\x0F' => VoE
    _ =>
      raise @hal.EcError::MailboxProtocol(
        "unknown mailbox type: " + type_byte.to_int().to_string(),
      )
  }
  { length, address, channel, priority, mb_type, counter }
}

///|
/// Decode only the bytes declared by the mailbox Length field.
pub fn MailboxFrame::from_bytes(
  data : Bytes,
) -> MailboxFrame raise @hal.EcError {
  let header = MailboxHeader::from_bytes(data)
  let payload_len = header.length.reinterpret_as_int()
  let frame_len = mailbox_header_len + payload_len
  if data.length() < frame_len {
    raise @hal.EcError::MailboxProtocol("mailbox frame truncated")
  }
  let payload = Bytes::makei(payload_len, fn(i) { data[mailbox_header_len + i] })
  { header, payload }
}

///|
/// Encode a bounded mailbox frame. Length is derived from payload so a stale
/// header value cannot produce a malformed frame.
pub fn MailboxFrame::to_bytes(self : MailboxFrame) -> Bytes raise @hal.EcError {
  if self.payload.length() > 0xFFFF {
    raise @hal.EcError::MailboxProtocol("mailbox payload exceeds 65535 bytes")
  }
  let header = {
    ..self.header,
    length: self.payload.length().reinterpret_as_uint(),
  }
  let buf = Buffer(size_hint=mailbox_header_len + self.payload.length())
  let encoded_header = header.to_bytes()
  for byte in encoded_header {
    buf.write_byte(byte)
  }
  for byte in self.payload {
    buf.write_byte(byte)
  }
  buf.to_bytes()
}

///|
/// Decode an ERR mailbox payload. The generic error service is exactly two
/// little-endian WORD values: Type and Detail.
pub fn MailboxFrame::decode_error(
  self : MailboxFrame,
) -> MailboxError raise @hal.EcError {
  if self.header.mb_type != Err {
    raise @hal.EcError::MailboxProtocol("mailbox frame is not an ERR frame")
  }
  if self.payload.length() != 4 {
    raise @hal.EcError::MailboxProtocol(
      "mailbox ERR payload must be exactly 4 bytes",
    )
  }
  let error_type = self.payload[0].to_uint() | (self.payload[1].to_uint() << 8)
  let detail = self.payload[2].to_uint() | (self.payload[3].to_uint() << 8)
  {
    error_type: MailboxErrorType::from_uint(error_type),
    detail: MailboxErrorDetail::from_uint(detail),
  }
}

///|
/// Validate the application protocol before its decoder touches the payload.
/// Generic ERR frames are decoded first so callers receive the real mailbox
/// failure instead of a misleading protocol-type or short-frame error.
pub fn MailboxFrame::require_type(
  self : MailboxFrame,
  expected : MailboxType,
) -> Unit raise @hal.EcError {
  if self.header.mb_type == Err {
    let mailbox_error = self.decode_error()
    raise @hal.EcError::MailboxProtocol(
      "mailbox error: " +
      mailbox_error.detail.label() +
      " (type=" +
      mailbox_error.error_type.to_uint().reinterpret_as_int().to_string() +
      ", detail=" +
      mailbox_error.detail.to_uint().reinterpret_as_int().to_string() +
      ")",
    )
  }
  if self.header.mb_type != expected {
    raise @hal.EcError::MailboxProtocol(
      "expected " +
      @debug.to_string(expected) +
      " mailbox, got " +
      @debug.to_string(self.header.mb_type),
    )
  }
}
