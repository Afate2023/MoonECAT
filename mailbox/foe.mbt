///|
/// FoE (File over EtherCAT) frame encoding and decoding per ETG.1000.6 §5.8.
///
/// FoE header (6 bytes, follows 6-byte mailbox header):
///   Byte 0: OpCode
///   Byte 1: Reserved (0x00)
///   Bytes 2-5: context-dependent union:
///     - Read/Write: Password (LE u32)
///     - Data/Ack:   Packet Number (LE u32)
///     - Error:      Error Code (LE u32)
///   Bytes 6+:  payload (filename for Read/Write, file data for Data,
///              error text for Error, nothing for Ack/Busy)

///|
let foe_header_len : Int = 6

///|
/// FoE OpCode values.
pub(all) enum FoeOpCode {
  /// Host→Slave: request to upload (read) a file.
  Read
  /// Host→Slave: request to download (write) a file.
  Write
  /// Data segment (bidirectional).
  Data
  /// Acknowledge receipt of a data segment (bidirectional).
  Ack
  /// Error indication (bidirectional).
  Error
  /// Slave→Host: busy, retry the last request.
  Busy
} derive(Eq, Show)

///|
pub fn FoeOpCode::to_byte(self : FoeOpCode) -> Byte {
  match self {
    Read => b'\x01'
    Write => b'\x02'
    Data => b'\x03'
    Ack => b'\x04'
    Error => b'\x05'
    Busy => b'\x06'
  }
}

///|
pub fn FoeOpCode::from_byte(b : Byte) -> FoeOpCode raise @hal.EcError {
  match b {
    b'\x01' => Read
    b'\x02' => Write
    b'\x03' => Data
    b'\x04' => Ack
    b'\x05' => Error
    b'\x06' => Busy
    _ =>
      raise @hal.EcError::MailboxProtocol(
        "unknown FoE opcode: " + b.to_int().to_string(),
      )
  }
}

///|
/// FoE error codes per ETG.1000.6.
pub(all) enum FoeErrorCode {
  NotDefined
  NotFound
  AccessDenied
  DiskFull
  Illegal
  PacketNumberWrong
  AlreadyExists
  NoUser
  BootstrapOnly
  NotInBootstrap
  NoRights
  ProgramError
  InvalidChecksum
  InvalidFirmware
  FlashError
  Unknown(UInt)
} derive(Eq, Show)

///|
pub fn FoeErrorCode::from_uint(code : UInt) -> FoeErrorCode {
  match code {
    0x8000U => NotDefined
    0x8001U => NotFound
    0x8002U => AccessDenied
    0x8003U => DiskFull
    0x8004U => Illegal
    0x8005U => PacketNumberWrong
    0x8006U => AlreadyExists
    0x8007U => NoUser
    0x8008U => BootstrapOnly
    0x8009U => NotInBootstrap
    0x800AU => NoRights
    0x800BU => ProgramError
    0x800CU => InvalidChecksum
    0x800DU => InvalidFirmware
    0x8011U => FlashError
    _ => Unknown(code)
  }
}

///|
pub fn FoeErrorCode::to_uint(self : FoeErrorCode) -> UInt {
  match self {
    NotDefined => 0x8000U
    NotFound => 0x8001U
    AccessDenied => 0x8002U
    DiskFull => 0x8003U
    Illegal => 0x8004U
    PacketNumberWrong => 0x8005U
    AlreadyExists => 0x8006U
    NoUser => 0x8007U
    BootstrapOnly => 0x8008U
    NotInBootstrap => 0x8009U
    NoRights => 0x800AU
    ProgramError => 0x800BU
    InvalidChecksum => 0x800CU
    InvalidFirmware => 0x800DU
    FlashError => 0x8011U
    Unknown(code) => code
  }
}

///|
/// Decoded FoE response frame.
pub(all) enum FoeResponse {
  /// Data segment with packet number and payload.
  FoeData(packet_number~ : UInt, data~ : Bytes)
  /// Acknowledgement with packet number.
  FoeAck(packet_number~ : UInt)
  /// Error with code and optional text.
  FoeError(code~ : FoeErrorCode, text~ : String)
  /// Busy: slave requests host to re-send.
  FoeBusy
} derive(Eq, Show)

///|
/// Encode a FoE Read request (upload: host wants to read file from slave).
pub fn encode_foe_read(
  counter : Byte,
  password : UInt,
  filename : String,
) -> Bytes {
  let name_bytes = filename.to_array().map(fn(c) { c.to_int().to_byte() })
  let payload_len = foe_header_len + name_bytes.length()
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: FoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i = 0; i < hdr.length(); i = i + 1 {
    buf.write_byte(hdr[i])
  }
  // FoE header: OpCode=Read, Reserved=0
  buf.write_byte(FoeOpCode::Read.to_byte())
  buf.write_byte(b'\x00')
  // Password (LE u32)
  write_u32_le(buf, password)
  // Filename (ASCII, no null terminator)
  for b in name_bytes {
    buf.write_byte(b)
  }
  buf.to_bytes()
}

///|
/// Encode a FoE Write request (download: host wants to write file to slave).
pub fn encode_foe_write(
  counter : Byte,
  password : UInt,
  filename : String,
) -> Bytes {
  let name_bytes = filename.to_array().map(fn(c) { c.to_int().to_byte() })
  let payload_len = foe_header_len + name_bytes.length()
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: FoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i = 0; i < hdr.length(); i = i + 1 {
    buf.write_byte(hdr[i])
  }
  // FoE header: OpCode=Write, Reserved=0
  buf.write_byte(FoeOpCode::Write.to_byte())
  buf.write_byte(b'\x00')
  // Password (LE u32)
  write_u32_le(buf, password)
  // Filename (ASCII, no null terminator)
  for b in name_bytes {
    buf.write_byte(b)
  }
  buf.to_bytes()
}

///|
/// Encode a FoE Data segment (used in both upload and download transfers).
pub fn encode_foe_data(
  counter : Byte,
  packet_number : UInt,
  data : Bytes,
) -> Bytes {
  let payload_len = foe_header_len + data.length()
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: FoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i = 0; i < hdr.length(); i = i + 1 {
    buf.write_byte(hdr[i])
  }
  buf.write_byte(FoeOpCode::Data.to_byte())
  buf.write_byte(b'\x00')
  write_u32_le(buf, packet_number)
  for i = 0; i < data.length(); i = i + 1 {
    buf.write_byte(data[i])
  }
  buf.to_bytes()
}

///|
/// Encode a FoE Ack frame.
pub fn encode_foe_ack(counter : Byte, packet_number : UInt) -> Bytes {
  let payload_len = foe_header_len
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: FoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i = 0; i < hdr.length(); i = i + 1 {
    buf.write_byte(hdr[i])
  }
  buf.write_byte(FoeOpCode::Ack.to_byte())
  buf.write_byte(b'\x00')
  write_u32_le(buf, packet_number)
  buf.to_bytes()
}

///|
/// Decode a FoE response from a raw mailbox frame.
pub fn decode_foe_response(
  data : Bytes,
) -> (MailboxHeader, FoeResponse) raise @hal.EcError {
  if data.length() < mailbox_header_len + 2 {
    raise @hal.EcError::MailboxProtocol("FoE response frame too short")
  }
  let mbh = MailboxHeader::from_bytes(data)
  if mbh.mb_type != FoE {
    raise @hal.EcError::MailboxProtocol(
      "expected FoE mailbox, got " + mbh.mb_type.to_string(),
    )
  }
  let payload_len = mbh.length.reinterpret_as_int()
  if payload_len < 2 {
    raise @hal.EcError::MailboxProtocol("FoE response payload too short")
  }
  let opcode = FoeOpCode::from_byte(data[mailbox_header_len])
  match opcode {
    Data => {
      if payload_len < foe_header_len {
        raise @hal.EcError::MailboxProtocol("FoE Data frame too short")
      }
      let pn = read_u32_le_bytes(data, mailbox_header_len + 2)
      let data_start = mailbox_header_len + foe_header_len
      let data_end = mailbox_header_len + payload_len
      let segment = if data_end > data_start && data.length() >= data_end {
        Bytes::makei(data_end - data_start, fn(i) { data[data_start + i] })
      } else {
        Bytes::new(0)
      }
      (mbh, FoeData(packet_number=pn, data=segment))
    }
    Ack => {
      let pn = if payload_len >= foe_header_len {
        read_u32_le_bytes(data, mailbox_header_len + 2)
      } else {
        0U
      }
      (mbh, FoeAck(packet_number=pn))
    }
    Error => {
      let error_code = if payload_len >= foe_header_len {
        FoeErrorCode::from_uint(read_u32_le_bytes(data, mailbox_header_len + 2))
      } else {
        NotDefined
      }
      let text = if payload_len > foe_header_len &&
        data.length() >= mailbox_header_len + payload_len {
        let start = mailbox_header_len + foe_header_len
        let end = mailbox_header_len + payload_len
        let chars : Array[Char] = []
        for i = start; i < end; i = i + 1 {
          chars.push(data[i].to_int().unsafe_to_char())
        }
        String::from_array(chars)
      } else {
        ""
      }
      (mbh, FoeError(code=error_code, text~))
    }
    Busy => (mbh, FoeBusy)
    _ =>
      raise @hal.EcError::MailboxProtocol(
        "unexpected FoE opcode in response: " + opcode.to_string(),
      )
  }
}

///|
fn write_u32_le(buf : @buffer.Buffer, value : UInt) -> Unit {
  buf.write_byte((value & 0xFFU).to_byte())
  buf.write_byte(((value >> 8) & 0xFFU).to_byte())
  buf.write_byte(((value >> 16) & 0xFFU).to_byte())
  buf.write_byte(((value >> 24) & 0xFFU).to_byte())
}

///|
fn read_u32_le_bytes(data : Bytes, offset : Int) -> UInt {
  if data.length() < offset + 4 {
    return 0U
  }
  data[offset].to_uint() |
  (data[offset + 1].to_uint() << 8) |
  (data[offset + 2].to_uint() << 16) |
  (data[offset + 3].to_uint() << 24)
}
