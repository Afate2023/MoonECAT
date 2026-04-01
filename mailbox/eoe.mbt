///|
/// EoE (Ethernet over EtherCAT) frame encoding and decoding per ETG.1000.6 §5.7.
///
/// EoE header (4 bytes, follows 6-byte mailbox header):
///   Bytes 0-1: frameinfo1 (LE u16)
///     bits [3:0]  = frame type
///     bits [7:4]  = port
///     bit  [8]    = last fragment
///     bit  [9]    = time appended
///     bit  [10]   = time request
///   Bytes 2-3: frameinfo2 (LE u16)
///     bits [5:0]  = fragment number
///     bits [11:6] = frame offset (in 32-byte units)
///     bits [15:12] = frame number
///   Bytes 4+:  payload

///|
let eoe_header_len : Int = 4

///|
/// EoE frame type values per ETG.1000.6.
pub(all) enum EoeFrameType {
  /// Ethernet frame fragment data.
  FragData
  /// Timestamp response (Init response with timestamp).
  InitRespTimestamp
  /// Set IP parameter request (INIT_REQ).
  SetIpReq
  /// Set IP parameter response (INIT_RESP).
  SetIpResp
  /// Set address filter request.
  SetAddrFilterReq
  /// Set address filter response.
  SetAddrFilterResp
  /// Get IP parameter request.
  GetIpReq
  /// Get IP parameter response.
  GetIpResp
  /// Get address filter request.
  GetAddrFilterReq
  /// Get address filter response.
  GetAddrFilterResp
} derive(Eq, Show)

///|
pub fn EoeFrameType::to_uint(self : EoeFrameType) -> UInt {
  match self {
    FragData => 0U
    InitRespTimestamp => 1U
    SetIpReq => 2U
    SetIpResp => 3U
    SetAddrFilterReq => 4U
    SetAddrFilterResp => 5U
    GetIpReq => 6U
    GetIpResp => 7U
    GetAddrFilterReq => 8U
    GetAddrFilterResp => 9U
  }
}

///|
pub fn EoeFrameType::from_uint(v : UInt) -> EoeFrameType raise @hal.EcError {
  match v {
    0U => FragData
    1U => InitRespTimestamp
    2U => SetIpReq
    3U => SetIpResp
    4U => SetAddrFilterReq
    5U => SetAddrFilterResp
    6U => GetIpReq
    7U => GetIpResp
    8U => GetAddrFilterReq
    9U => GetAddrFilterResp
    _ =>
      raise @hal.EcError::MailboxProtocol(
        "unknown EoE frame type: " + v.reinterpret_as_int().to_string(),
      )
  }
}

///|
/// EoE result codes for Set IP / Get IP responses.
pub(all) enum EoeResult {
  Success
  UnspecifiedError
  UnsupportedFrameType
  NoIpSupport
  NoDhcpSupport
  NoFilterSupport
  Unknown(UInt)
} derive(Eq, Show)

///|
pub fn EoeResult::from_uint(v : UInt) -> EoeResult {
  match v {
    0x0000U => Success
    0x0001U => UnspecifiedError
    0x0002U => UnsupportedFrameType
    0x0201U => NoIpSupport
    0x0202U => NoDhcpSupport
    0x0401U => NoFilterSupport
    _ => Unknown(v)
  }
}

///|
pub fn EoeResult::to_uint(self : EoeResult) -> UInt {
  match self {
    Success => 0x0000U
    UnspecifiedError => 0x0001U
    UnsupportedFrameType => 0x0002U
    NoIpSupport => 0x0201U
    NoDhcpSupport => 0x0202U
    NoFilterSupport => 0x0401U
    Unknown(v) => v
  }
}

///|
/// Decoded EoE response.
pub(all) enum EoeResponse {
  /// Received an Ethernet frame fragment.
  EoeFragment(
    frame_type~ : EoeFrameType,
    last_fragment~ : Bool,
    frag_number~ : UInt,
    frame_offset~ : UInt,
    frame_number~ : UInt,
    data~ : Bytes
  )
  /// Set/Get IP parameter response with result code.
  EoeIpResponse(result~ : EoeResult, data~ : Bytes)
} derive(Eq, Show)

///|
/// Build frameinfo1 LE u16 value.
fn build_frameinfo1(
  frame_type : EoeFrameType,
  port : UInt,
  last_fragment : Bool,
) -> UInt {
  let ft = frame_type.to_uint() & 0xFU
  let p = (port & 0xFU) << 4
  let lf : UInt = if last_fragment { 1U << 8 } else { 0U }
  ft | p | lf
}

///|
/// Build frameinfo2 LE u16 value.
fn build_frameinfo2(
  frag_number : UInt,
  frame_offset : UInt,
  frame_number : UInt,
) -> UInt {
  let fn_ = frag_number & 0x3FU
  let fo = (frame_offset & 0x3FU) << 6
  let fno = (frame_number & 0xFU) << 12
  fn_ | fo | fno
}

///|
/// Encode an EoE Ethernet frame fragment for sending to a slave.
pub fn encode_eoe_fragment(
  counter : Byte,
  port : UInt,
  last_fragment : Bool,
  frag_number : UInt,
  frame_offset : UInt,
  frame_number : UInt,
  data : Bytes,
) -> Bytes {
  let payload_len = eoe_header_len + data.length()
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: EoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i = 0; i < hdr.length(); i = i + 1 {
    buf.write_byte(hdr[i])
  }
  let fi1 = build_frameinfo1(FragData, port, last_fragment)
  buf.write_byte((fi1 & 0xFFU).to_byte())
  buf.write_byte(((fi1 >> 8) & 0xFFU).to_byte())
  let fi2 = build_frameinfo2(frag_number, frame_offset, frame_number)
  buf.write_byte((fi2 & 0xFFU).to_byte())
  buf.write_byte(((fi2 >> 8) & 0xFFU).to_byte())
  for i = 0; i < data.length(); i = i + 1 {
    buf.write_byte(data[i])
  }
  buf.to_bytes()
}

///|
/// Encode an EoE Set IP parameter request.
pub fn encode_eoe_set_ip_req(
  counter : Byte,
  port : UInt,
  ip : Bytes,
  subnet : Bytes,
  gateway : Bytes,
) -> Bytes {
  // Flags byte: bit 1=IP, bit 2=subnet, bit 3=gateway
  let mut flags : Byte = b'\x00'
  let params : Array[Bytes] = []
  if ip.length() == 4 {
    flags = flags | b'\x02'
    params.push(ip)
  }
  if subnet.length() == 4 {
    flags = flags | b'\x04'
    params.push(subnet)
  }
  if gateway.length() == 4 {
    flags = flags | b'\x08'
    params.push(gateway)
  }
  let mut param_total = 0
  for p in params {
    param_total += p.length()
  }
  let payload_len = eoe_header_len + 1 + param_total
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: EoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i = 0; i < hdr.length(); i = i + 1 {
    buf.write_byte(hdr[i])
  }
  let fi1 = build_frameinfo1(SetIpReq, port, true)
  buf.write_byte((fi1 & 0xFFU).to_byte())
  buf.write_byte(((fi1 >> 8) & 0xFFU).to_byte())
  // frameinfo2 = 0
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(flags)
  for p in params {
    for i = 0; i < p.length(); i = i + 1 {
      buf.write_byte(p[i])
    }
  }
  buf.to_bytes()
}

///|
/// Encode an EoE Get IP parameter request.
pub fn encode_eoe_get_ip_req(counter : Byte, port : UInt) -> Bytes {
  let payload_len = eoe_header_len
  let buf = @buffer.new(size_hint=mailbox_header_len + payload_len)
  let mbh : MailboxHeader = {
    length: payload_len.reinterpret_as_uint(),
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: EoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  for i = 0; i < hdr.length(); i = i + 1 {
    buf.write_byte(hdr[i])
  }
  let fi1 = build_frameinfo1(GetIpReq, port, true)
  buf.write_byte((fi1 & 0xFFU).to_byte())
  buf.write_byte(((fi1 >> 8) & 0xFFU).to_byte())
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.to_bytes()
}

///|
/// Decode an EoE response from a mailbox frame (after mailbox header).
pub fn decode_eoe_response(frame : Bytes) -> EoeResponse raise @hal.EcError {
  if frame.length() < mailbox_header_len + eoe_header_len {
    raise @hal.EcError::MailboxProtocol(
      "EoE frame too short: " + frame.length().to_string(),
    )
  }
  let mbh = MailboxHeader::from_bytes(frame)
  if mbh.mb_type != EoE {
    raise @hal.EcError::MailboxProtocol(
      "expected EoE mailbox type, got " + mbh.mb_type.to_string(),
    )
  }
  let off = mailbox_header_len
  let fi1 = frame[off].to_uint() | (frame[off + 1].to_uint() << 8)
  let fi2 = frame[off + 2].to_uint() | (frame[off + 3].to_uint() << 8)
  let frame_type = EoeFrameType::from_uint(fi1 & 0xFU)
  let last_fragment = ((fi1 >> 8) & 1U) != 0U
  let frag_number = fi2 & 0x3FU
  let frame_offset = (fi2 >> 6) & 0x3FU
  let frame_number = (fi2 >> 12) & 0xFU
  match frame_type {
    SetIpResp | GetIpResp | SetAddrFilterResp | GetAddrFilterResp => {
      // frameinfo2 doubles as result code for IP responses
      let result = EoeResult::from_uint(fi2)
      let data_start = off + eoe_header_len
      let data = if data_start < frame.length() {
        Bytes::makei(frame.length() - data_start, fn(i) {
          frame[data_start + i]
        })
      } else {
        Bytes::new(0)
      }
      EoeIpResponse(result~, data~)
    }
    _ => {
      let data_start = off + eoe_header_len
      let data = if data_start < frame.length() {
        Bytes::makei(frame.length() - data_start, fn(i) {
          frame[data_start + i]
        })
      } else {
        Bytes::new(0)
      }
      EoeFragment(
        frame_type~,
        last_fragment~,
        frag_number~,
        frame_offset~,
        frame_number~,
        data~,
      )
    }
  }
}
