///|
/// CoE/SDO transaction engine: encode/decode mailbox + CoE frames,
/// and drive expedited SDO Upload/Download transactions.
///
/// Mailbox frame layout (ETG.1000.6):
///   Bytes 0-1: Length (data area only, little-endian)
///   Bytes 2-3: Address (station address, little-endian)
///   Byte 4: bits [7:6]=Priority, [5:2]=reserved, [1:0]=Channel
///   Byte 5: bits [7:4]=Counter, [3:0]=Type
///   Bytes 6+: Protocol-specific data
///
/// CoE header (2 bytes):
///   Bits [15:12] = CoE service type
///   Bits [11:0]  = reserved/number
///
/// SDO header (expedited, 8 bytes):
///   Byte 0: Command specifier + size indicator
///   Byte 1-2: Index (little-endian)
///   Byte 3: Subindex
///   Bytes 4-7: Data (expedited) or size (normal)

///|
/// Mailbox header size in bytes.
let mailbox_header_len : Int = 6

///|
/// CoE header size in bytes.
let coe_header_len : Int = 2

///|
/// SDO expedited header size in bytes (command + index + subindex + 4 data).
let sdo_header_len : Int = 8

///|
/// SDO Info header size in bytes.
let sdo_info_header_len : Int = 4

///|
/// Master-originated mailbox requests use address 0x0000 in the header.
fn mailbox_request_address(_station : UInt) -> UInt {
  0U
}

///|
/// Encode a mailbox header into 6 bytes.
pub fn MailboxHeader::to_bytes(self : MailboxHeader) -> Bytes {
  let buf = @buffer.new(size_hint=mailbox_header_len)
  // Bytes 0-1: Length (LE)
  buf.write_byte((self.length & 0xFFU).to_byte())
  buf.write_byte(((self.length >> 8) & 0xFFU).to_byte())
  // Bytes 2-3: Address (LE)
  buf.write_byte((self.address & 0xFFU).to_byte())
  buf.write_byte(((self.address >> 8) & 0xFFU).to_byte())
  // Byte 4: Channel[1:0] | Priority[7:6]
  let b4 = (self.channel & b'\x03') | ((self.priority & b'\x03') << 6)
  buf.write_byte(b4)
  // Byte 5: Type[3:0] | Counter[7:4]
  let b5 = self.mb_type.to_byte() | ((self.counter & b'\x0F') << 4)
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
  let length = data[0].to_uint() | (data[1].to_uint() << 8)
  let address = data[2].to_uint() | (data[3].to_uint() << 8)
  let channel = data[4] & b'\x03'
  let priority = (data[4] >> 6) & b'\x03'
  let type_byte = data[5] & b'\x0F'
  let counter = (data[5] >> 4) & b'\x0F'
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
/// CoE service type encoding for the CoE header.
fn CoeService::to_uint(self : CoeService) -> UInt {
  match self {
    SdoRequest => 2U
    SdoResponse => 3U
    SdoInfo => 8U
    TxPdo => 5U
    RxPdo => 6U
    PdoRemoteRequest => 7U
    Emergency => 1U
  }
}

///|
/// Decode CoE service type from the 4-bit field.
fn coe_service_from_uint(v : UInt) -> CoeService raise @hal.EcError {
  match v {
    1U => Emergency
    2U => SdoRequest
    3U => SdoResponse
    5U => TxPdo
    6U => RxPdo
    7U => PdoRemoteRequest
    8U => SdoInfo
    _ =>
      raise @hal.EcError::MailboxProtocol(
        "unknown CoE service: " + v.reinterpret_as_int().to_string(),
      )
  }
}

///|
/// SDO command specifier byte encoding.
fn SdoCommand::to_byte(self : SdoCommand) -> Byte {
  match self {
    DownloadRequest => b'\x21' // initiate download, expedited, size=4
    DownloadResponse => b'\x60'
    UploadRequest => b'\x40'
    UploadResponse => b'\x43' // initiate upload response, expedited, size=4
    AbortTransfer => b'\x80'
  }
}

///|
/// Decode SDO command specifier from byte.
fn sdo_command_from_byte(b : Byte) -> SdoCommand raise @hal.EcError {
  // Check command specifier bits [7:5]
  let cs = (b >> 5) & b'\x07'
  match cs {
    b'\x01' => DownloadRequest // 001 = initiate download
    b'\x02' => UploadResponse // 010 = initiate upload response
    b'\x03' => DownloadResponse // 011 = initiate download response
    b'\x04' => AbortTransfer // 100 = abort
    _ =>
      if b == b'\x40' {
        UploadRequest // 010 with no data bits = upload request
      } else {
        raise @hal.EcError::MailboxProtocol(
          "unknown SDO command: 0x" + b.to_int().to_string(),
        )
      }
  }
}

///|
/// SdoTransaction tracks one SDO request-response exchange.
pub(all) struct SdoTransaction {
  /// Mailbox counter for correlation.
  counter : Byte
  /// Target slave station address.
  station : UInt
  /// SDO request to send.
  request : SdoRequest
} derive(Eq, Show)

///|
/// SdoResponse holds a decoded SDO response.
pub(all) struct SdoResponse {
  index : UInt
  subindex : Byte
  command : SdoCommand
  data : Bytes
  /// True when this response is part of segmented transfer.
  segmented : Bool
  /// Toggle bit used by segmented transfer.
  toggle : Bool
  /// True when this is the last segmented frame.
  last_segment : Bool
  /// Total transfer size if provided by initiate upload response.
  complete_size : UInt?
} derive(Eq, Show)

///|
/// Build a complete mailbox frame for an SDO request (expedited).
pub fn SdoTransaction::encode(self : SdoTransaction) -> Bytes {
  let buf = @buffer.new(
    size_hint=mailbox_header_len + coe_header_len + sdo_header_len,
  )
  let data_len = coe_header_len + sdo_header_len
  // Mailbox header
  let mbh : MailboxHeader = {
    length: data_len.reinterpret_as_uint(),
    address: mailbox_request_address(self.station),
    channel: b'\x00',
    priority: b'\x00',
    mb_type: CoE,
    counter: self.counter,
  }
  let hdr_bytes = mbh.to_bytes()
  for i = 0; i < hdr_bytes.length(); i = i + 1 {
    buf.write_byte(hdr_bytes[i])
  }
  // CoE header: service type in bits [15:12]
  let svc = self.request.command.to_coe_service()
  let coe_word = svc.to_uint() << 12
  buf.write_byte((coe_word & 0xFFU).to_byte())
  buf.write_byte(((coe_word >> 8) & 0xFFU).to_byte())
  // SDO header
  let mut cmd = self.request.command.to_byte()
  // Complete Access is bit4 in initiate upload/download command.
  if self.request.complete_access {
    cmd = cmd | b'\x10'
  }
  buf.write_byte(cmd)
  // Index (LE)
  buf.write_byte((self.request.index & 0xFFU).to_byte())
  buf.write_byte(((self.request.index >> 8) & 0xFFU).to_byte())
  // Subindex
  buf.write_byte(self.request.subindex)
  // Data (pad to 4 bytes)
  for i = 0; i < 4; i = i + 1 {
    if i < self.request.data.length() {
      buf.write_byte(self.request.data[i])
    } else {
      buf.write_byte(b'\x00')
    }
  }
  buf.to_bytes()
}

///|
/// Map SDO command to its CoE service type.
fn SdoCommand::to_coe_service(self : SdoCommand) -> CoeService {
  match self {
    DownloadRequest | UploadRequest | AbortTransfer => SdoRequest
    DownloadResponse | UploadResponse => SdoResponse
  }
}

///|
/// Decode an SDO response from a raw mailbox frame.
pub fn decode_sdo_response(
  data : Bytes,
) -> (MailboxHeader, SdoResponse) raise @hal.EcError {
  if data.length() < mailbox_header_len + coe_header_len + 1 {
    raise @hal.EcError::MailboxProtocol("SDO response frame too short")
  }
  let mbh = MailboxHeader::from_bytes(data)
  let payload_len = mbh.length.reinterpret_as_int()
  if payload_len < coe_header_len + 1 {
    raise @hal.EcError::MailboxProtocol("SDO response payload too short")
  }
  let frame_len = mailbox_header_len + payload_len
  if data.length() < frame_len {
    raise @hal.EcError::MailboxProtocol("SDO response truncated")
  }
  // Verify it's a CoE mailbox
  if mbh.mb_type != CoE {
    raise @hal.EcError::MailboxProtocol(
      "expected CoE mailbox, got " + mbh.mb_type.to_string(),
    )
  }
  let off = mailbox_header_len
  let sdo_payload_len = payload_len - coe_header_len
  // CoE header
  let coe_word = data[off].to_uint() | (data[off + 1].to_uint() << 8)
  let svc_field = (coe_word >> 12) & 0xFU
  let _svc = coe_service_from_uint(svc_field)
  // SDO header
  let sdo_off = off + coe_header_len
  let cmd_byte = data[sdo_off]

  // Abort transfer response
  if cmd_byte == b'\x80' {
    if sdo_payload_len < 8 {
      raise @hal.EcError::MailboxProtocol("SDO abort payload too short")
    }
    let abort_off = sdo_off + 4
    let abort_code = data[abort_off].to_uint() |
      (data[abort_off + 1].to_uint() << 8) |
      (data[abort_off + 2].to_uint() << 16) |
      (data[abort_off + 3].to_uint() << 24)
    raise @hal.EcError::SdoAbort(abort_code)
  }

  // Segmented upload response: command specifier in bits[7:5] = 000
  if (cmd_byte & b'\xE0') == b'\x00' {
    let toggle = (cmd_byte & b'\x10') != b'\x00'
    let n_unused = ((cmd_byte >> 1) & b'\x07').to_int()
    let last = (cmd_byte & b'\x01') != b'\x00'
    let payload_after_cmd = sdo_payload_len - 1
    let seg_len = if payload_after_cmd > 7 - n_unused {
      7 - n_unused
    } else {
      payload_after_cmd
    }
    let seg_data = if seg_len > 0 {
      Bytes::makei(seg_len, fn(i) { data[sdo_off + 1 + i] })
    } else {
      Bytes::new(0)
    }
    let resp : SdoResponse = {
      index: 0U,
      subindex: b'\x00',
      command: UploadResponse,
      data: seg_data,
      segmented: true,
      toggle,
      last_segment: last,
      complete_size: None,
    }
    return (mbh, resp)
  }

  // Segmented download response: command specifier in bits[7:5] = 001,
  // and payload contains only command byte (no index/subindex fields).
  if (cmd_byte & b'\xE0') == b'\x20' && sdo_payload_len == 1 {
    let toggle = (cmd_byte & b'\x10') != b'\x00'
    let resp : SdoResponse = {
      index: 0U,
      subindex: b'\x00',
      command: DownloadResponse,
      data: Bytes::new(0),
      segmented: true,
      toggle,
      last_segment: true,
      complete_size: None,
    }
    return (mbh, resp)
  }

  let cmd = sdo_command_from_byte(cmd_byte)

  if sdo_payload_len < sdo_header_len {
    raise @hal.EcError::MailboxProtocol("SDO response header too short")
  }
  let index = data[sdo_off + 1].to_uint() | (data[sdo_off + 2].to_uint() << 8)
  let subindex = data[sdo_off + 3]

  // Initiate upload response: command specifier bits[7:5] = 010
  if cmd == UploadResponse {
    let expedited = (cmd_byte & b'\x02') != b'\x00'
    let size_indicated = (cmd_byte & b'\x01') != b'\x00'
    if expedited {
      let n_unused = ((cmd_byte >> 2) & b'\x03').to_int()
      let data_len = 4 - n_unused
      let resp_data = Bytes::makei(data_len, fn(i) { data[sdo_off + 4 + i] })
      let resp : SdoResponse = {
        index,
        subindex,
        command: UploadResponse,
        data: resp_data,
        segmented: false,
        toggle: false,
        last_segment: true,
        complete_size: None,
      }
      return (mbh, resp)
    }

    let complete_size = if size_indicated {
      Some(
        data[sdo_off + 4].to_uint() |
        (data[sdo_off + 5].to_uint() << 8) |
        (data[sdo_off + 6].to_uint() << 16) |
        (data[sdo_off + 7].to_uint() << 24),
      )
    } else {
      None
    }
    let extra_len = sdo_payload_len - sdo_header_len
    let extra_data = if extra_len > 0 {
      Bytes::makei(extra_len, fn(i) { data[sdo_off + sdo_header_len + i] })
    } else {
      Bytes::new(0)
    }
    let resp : SdoResponse = {
      index,
      subindex,
      command: UploadResponse,
      data: extra_data,
      segmented: true,
      toggle: false,
      last_segment: false,
      complete_size,
    }
    return (mbh, resp)
  }

  let sdo_data = Bytes::makei(4, fn(i) { data[sdo_off + 4 + i] })
  let resp : SdoResponse = {
    index,
    subindex,
    command: cmd,
    data: sdo_data,
    segmented: false,
    toggle: false,
    last_segment: true,
    complete_size: None,
  }
  (mbh, resp)
}

///|
/// MailboxCounter manages the mailbox session counter cycling (1-7, wrapping).
pub(all) struct MailboxCounter {
  mut value : Byte
} derive(Show)

///|
pub fn MailboxCounter::new() -> MailboxCounter {
  { value: b'\x01' }
}

///|
/// Get the current counter value and advance.
pub fn MailboxCounter::next(self : MailboxCounter) -> Byte {
  let current = self.value
  let next_val = self.value.to_int() % 7 + 1
  self.value = next_val.to_byte()
  current
}

///|
/// Build an SDO Download (write) transaction.
pub fn build_sdo_download(
  counter : Byte,
  station : UInt,
  index : UInt,
  subindex : Byte,
  data : Bytes,
) -> SdoTransaction {
  {
    counter,
    station,
    request: {
      index,
      subindex,
      command: DownloadRequest,
      data,
      complete_access: false,
    },
  }
}

///|
/// Build an SDO Upload (read) transaction.
pub fn build_sdo_upload(
  counter : Byte,
  station : UInt,
  index : UInt,
  subindex : Byte,
) -> SdoTransaction {
  {
    counter,
    station,
    request: {
      index,
      subindex,
      command: UploadRequest,
      data: Bytes::new(0),
      complete_access: false,
    },
  }
}

///|
/// Build an SDO Download transaction with Complete Access flag set.
pub fn build_sdo_download_ca(
  counter : Byte,
  station : UInt,
  index : UInt,
  subindex : Byte,
  data : Bytes,
) -> SdoTransaction {
  {
    counter,
    station,
    request: {
      index,
      subindex,
      command: DownloadRequest,
      data,
      complete_access: true,
    },
  }
}

///|
/// Build an SDO Upload transaction with Complete Access flag set.
pub fn build_sdo_upload_ca(
  counter : Byte,
  station : UInt,
  index : UInt,
  subindex : Byte,
) -> SdoTransaction {
  {
    counter,
    station,
    request: {
      index,
      subindex,
      command: UploadRequest,
      data: Bytes::new(0),
      complete_access: true,
    },
  }
}

///|
/// Build an SDO Upload Segment request frame.
/// Toggle bit alternates on each segment round-trip.
pub fn build_sdo_upload_segment_request(
  counter : Byte,
  station : UInt,
  toggle : Bool,
) -> Bytes {
  let buf = @buffer.new(
    size_hint=mailbox_header_len + coe_header_len + sdo_header_len,
  )
  let data_len = coe_header_len + sdo_header_len
  let mbh : MailboxHeader = {
    length: data_len.reinterpret_as_uint(),
    address: mailbox_request_address(station),
    channel: b'\x00',
    priority: b'\x00',
    mb_type: CoE,
    counter,
  }
  let hdr_bytes = mbh.to_bytes()
  for i in 0..<hdr_bytes.length() {
    buf.write_byte(hdr_bytes[i])
  }
  let coe_word = 2U << 12
  buf.write_byte((coe_word & 0xFFU).to_byte())
  buf.write_byte(((coe_word >> 8) & 0xFFU).to_byte())
  let cmd = if toggle { b'\x70' } else { b'\x60' }
  buf.write_byte(cmd)
  for _i in 0..<7 {
    buf.write_byte(b'\x00')
  }
  buf.to_bytes()
}

///|
/// Build an SDO Download Segment request frame.
/// `segment` may contain at most 7 bytes.
pub fn build_sdo_download_segment_request(
  counter : Byte,
  station : UInt,
  toggle : Bool,
  last_segment : Bool,
  segment : Bytes,
) -> Bytes raise @hal.EcError {
  if segment.length() > 7 {
    raise @hal.EcError::MailboxProtocol(
      "SDO download segment too large (>7 bytes)",
    )
  }
  let buf = @buffer.new(
    size_hint=mailbox_header_len + coe_header_len + 1 + segment.length(),
  )
  let data_len = coe_header_len + 1 + segment.length()
  let mbh : MailboxHeader = {
    length: data_len.reinterpret_as_uint(),
    address: mailbox_request_address(station),
    channel: b'\x00',
    priority: b'\x00',
    mb_type: CoE,
    counter,
  }
  let hdr_bytes = mbh.to_bytes()
  for i in 0..<hdr_bytes.length() {
    buf.write_byte(hdr_bytes[i])
  }
  let coe_word = 2U << 12
  buf.write_byte((coe_word & 0xFFU).to_byte())
  buf.write_byte(((coe_word >> 8) & 0xFFU).to_byte())
  let n_unused = 7 - segment.length()
  let mut cmd = b'\x00'
  if toggle {
    cmd = cmd | b'\x10'
  }
  cmd = cmd | (n_unused.to_byte() << 1)
  if last_segment {
    cmd = cmd | b'\x01'
  }
  buf.write_byte(cmd)
  for i in 0..<segment.length() {
    buf.write_byte(segment[i])
  }
  buf.to_bytes()
}

///|
/// Build an SDO Info "Get OD List" request frame.
/// list_type: 0 = number of objects for all list classes.
pub fn build_sdo_info_get_od_list_request(
  counter : Byte,
  station : UInt,
  list_type : UInt,
) -> Bytes {
  let payload_len = coe_header_len + sdo_info_header_len + 2
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: mailbox_request_address(station),
    channel: b'\x00',
    priority: b'\x00',
    mb_type: CoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i in 0..<hdr.length() {
    buf.write_byte(hdr[i])
  }
  let coe_word = 8U << 12 // CoE Service = SDO Info
  buf.write_byte((coe_word & 0xFFU).to_byte())
  buf.write_byte(((coe_word >> 8) & 0xFFU).to_byte())
  // SDO Info header: opcode=0x01 (Get OD List req), incomplete=0, reserved=0, fragments_left=0
  buf.write_byte(b'\x01')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  // List type (WORD, LE)
  buf.write_byte((list_type & 0xFFU).to_byte())
  buf.write_byte(((list_type >> 8) & 0xFFU).to_byte())
  buf.to_bytes()
}

///|
/// Build an SDO Info "Get OD" (object description) request frame.
pub fn build_sdo_info_get_od_request(
  counter : Byte,
  station : UInt,
  index : UInt,
) -> Bytes {
  let payload_len = coe_header_len + sdo_info_header_len + 2
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: mailbox_request_address(station),
    channel: b'\x00',
    priority: b'\x00',
    mb_type: CoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i in 0..<hdr.length() {
    buf.write_byte(hdr[i])
  }
  let coe_word = 8U << 12
  buf.write_byte((coe_word & 0xFFU).to_byte())
  buf.write_byte(((coe_word >> 8) & 0xFFU).to_byte())
  buf.write_byte(b'\x03')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte((index & 0xFFU).to_byte())
  buf.write_byte(((index >> 8) & 0xFFU).to_byte())
  buf.to_bytes()
}

///|
/// Build an SDO Info "Get OE" (entry description) request frame.
/// `value_info` is a bitmask selecting additional fields in the response.
pub fn build_sdo_info_get_oe_request(
  counter : Byte,
  station : UInt,
  index : UInt,
  subindex : Byte,
  value_info : Byte,
) -> Bytes {
  let payload_len = coe_header_len + sdo_info_header_len + 4
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: mailbox_request_address(station),
    channel: b'\x00',
    priority: b'\x00',
    mb_type: CoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i in 0..<hdr.length() {
    buf.write_byte(hdr[i])
  }
  let coe_word = 8U << 12
  buf.write_byte((coe_word & 0xFFU).to_byte())
  buf.write_byte(((coe_word >> 8) & 0xFFU).to_byte())
  buf.write_byte(b'\x05')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte((index & 0xFFU).to_byte())
  buf.write_byte(((index >> 8) & 0xFFU).to_byte())
  buf.write_byte(subindex)
  buf.write_byte(value_info)
  buf.to_bytes()
}

///|
/// Decoded SDO Info response header and payload body.
pub(all) struct SdoInfoResponse {
  opcode : Byte
  incomplete : Bool
  fragments_left : UInt
  payload : Bytes
} derive(Eq, Show)

///|
/// SDO Info object description (Get OD response body).
pub(all) struct SdoInfoObjectDescription {
  index : UInt
  data_type : UInt
  object_code : Byte
  max_subindex : Byte
  name : String
} derive(Eq, Show)

///|
/// SDO Info entry description (Get OE response body).
pub(all) struct SdoInfoEntryDescription {
  index : UInt
  subindex : Byte
  value_info : Byte
  data_type : UInt
  bit_length : UInt
  access : UInt
  name : String
} derive(Eq, Show)

///|
/// Decode SDO Info response frame (service=0x08).
pub fn decode_sdo_info_response(
  data : Bytes,
) -> (MailboxHeader, SdoInfoResponse) raise @hal.EcError {
  if data.length() < mailbox_header_len + coe_header_len + sdo_info_header_len {
    raise @hal.EcError::MailboxProtocol("SDO Info response frame too short")
  }
  let mbh = MailboxHeader::from_bytes(data)
  let payload_len = mbh.length.reinterpret_as_int()
  if payload_len < coe_header_len + sdo_info_header_len {
    raise @hal.EcError::MailboxProtocol("SDO Info response payload too short")
  }
  let frame_len = mailbox_header_len + payload_len
  if data.length() < frame_len {
    raise @hal.EcError::MailboxProtocol("SDO Info response truncated")
  }
  if mbh.mb_type != CoE {
    raise @hal.EcError::MailboxProtocol(
      "expected CoE mailbox, got " + mbh.mb_type.to_string(),
    )
  }
  let off = mailbox_header_len
  let coe_word = data[off].to_uint() | (data[off + 1].to_uint() << 8)
  let svc_field = (coe_word >> 12) & 0xFU
  if svc_field != 8U {
    raise @hal.EcError::MailboxProtocol("expected SDO Info service (0x08)")
  }
  let info_off = off + coe_header_len
  let hdr0 = data[info_off]
  let opcode = hdr0 & b'\x7F'
  let incomplete = (hdr0 & b'\x80') != b'\x00'
  let fragments_left = data[info_off + 2].to_uint() |
    (data[info_off + 3].to_uint() << 8)
  let body_len = payload_len - coe_header_len - sdo_info_header_len
  let payload = if body_len > 0 {
    Bytes::makei(body_len, fn(i) { data[info_off + sdo_info_header_len + i] })
  } else {
    Bytes::new(0)
  }
  (mbh, { opcode, incomplete, fragments_left, payload })
}

///|
/// Decode OD list payload (sequence of little-endian WORD indices).
pub fn decode_sdo_info_od_list_payload(payload : Bytes) -> Array[UInt] {
  let count = payload.length() / 2
  Array::makei(count, fn(i) {
    let off = i * 2
    payload[off].to_uint() | (payload[off + 1].to_uint() << 8)
  })
}

///|
/// Decode Get OD response payload.
pub fn decode_sdo_info_od_description_payload(
  payload : Bytes,
) -> SdoInfoObjectDescription raise @hal.EcError {
  if payload.length() < 6 {
    raise @hal.EcError::MailboxProtocol("SDO Info Get OD payload too short")
  }
  let index = payload[0].to_uint() | (payload[1].to_uint() << 8)
  let data_type = payload[2].to_uint() | (payload[3].to_uint() << 8)
  let max_subindex = payload[4]
  let object_code = payload[5]
  let name = if payload.length() > 6 {
    let name_bytes = Bytes::makei(payload.length() - 6, fn(i) { payload[6 + i] })
    @utf8.decode(name_bytes) catch {
      _ =>
        raise @hal.EcError::MailboxProtocol(
          "SDO Info Get OD name is not valid UTF-8",
        )
    }
  } else {
    ""
  }
  { index, data_type, object_code, max_subindex, name }
}

///|
/// Decode Get OE response payload.
pub fn decode_sdo_info_oe_description_payload(
  payload : Bytes,
) -> SdoInfoEntryDescription raise @hal.EcError {
  if payload.length() < 10 {
    raise @hal.EcError::MailboxProtocol("SDO Info Get OE payload too short")
  }
  let index = payload[0].to_uint() | (payload[1].to_uint() << 8)
  let subindex = payload[2]
  let value_info = payload[3]
  let data_type = payload[4].to_uint() | (payload[5].to_uint() << 8)
  let bit_length = payload[6].to_uint() | (payload[7].to_uint() << 8)
  let access = payload[8].to_uint() | (payload[9].to_uint() << 8)
  let name = if payload.length() > 10 {
    let name_bytes = Bytes::makei(payload.length() - 10, fn(i) {
      payload[10 + i]
    })
    @utf8.decode(name_bytes) catch {
      _ =>
        raise @hal.EcError::MailboxProtocol(
          "SDO Info Get OE name is not valid UTF-8",
        )
    }
  } else {
    ""
  }
  { index, subindex, value_info, data_type, bit_length, access, name }
}
