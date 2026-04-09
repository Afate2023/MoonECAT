///|
// ===== Mailbox Integration Tests =====
// Full SDO/FoE round-trip tests using custom mock NICs that handle
// complete mailbox protocol: SM status, padded reads/writes, response framing.

///|
/// MailboxMockNic implements @hal.Nic for FP-addressed mailbox round-trips.
/// Pre-built response frames are returned sequentially for in_address reads.
pub struct MailboxMockNic {
  mut next_response : Bytes
  mut is_open : Bool
  responses : Array[Bytes]
  mut response_index : Int
}

///|
fn MailboxMockNic::new(responses : Array[Bytes]) -> MailboxMockNic {
  { next_response: Bytes::new(0), is_open: true, responses, response_index: 0 }
}

///|
pub impl @hal.Nic for MailboxMockNic with open_(name) {
  ignore(name)
  MailboxMockNic::new([])
}

///|
pub impl @hal.Nic for MailboxMockNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  let sm0_addr = @protocol.reg_sm_base
  let sm1_addr = @protocol.reg_sm_base +
    @protocol.sm_entry_size.reinterpret_as_uint()
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == sm0_addr {
        // SM0 (out): not busy — status byte 5 = 0x00
        Bytes::makei(8, fn(i) {
          match i {
            0 => b'\x00'
            1 => b'\x10'
            2 => b'\x80'
            3 => b'\x00'
            5 => b'\x00'
            6 => b'\x01'
            _ => b'\x00'
          }
        })
      } else if offset == sm1_addr {
        // SM1 (in): ready — status byte 5 = 0x08
        Bytes::makei(8, fn(i) {
          match i {
            0 => b'\x80'
            1 => b'\x10'
            2 => b'\x80'
            3 => b'\x00'
            5 => b'\x08'
            6 => b'\x01'
            _ => b'\x00'
          }
        })
      } else if offset == 0x1080U {
        // in_address: return next queued response
        if self.response_index < self.responses.length() {
          let resp = self.responses[self.response_index]
          self.response_index += 1
          resp
        } else {
          Bytes::makei(128, fn(_) { b'\x00' })
        }
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR =>
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    _ => build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for MailboxMockNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for MailboxMockNic with close(self) {
  self.is_open = false
}

///|
/// ApMailboxFullMockNic handles AP-addressed mailbox round-trips.
pub struct ApMailboxFullMockNic {
  mut next_response : Bytes
  mut is_open : Bool
  responses : Array[Bytes]
  mut response_index : Int
  mut mailbox_ready : Bool
}

///|
fn ApMailboxFullMockNic::new(responses : Array[Bytes]) -> ApMailboxFullMockNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    responses,
    response_index: 0,
    mailbox_ready: false,
  }
}

///|
pub impl @hal.Nic for ApMailboxFullMockNic with open_(name) {
  ignore(name)
  ApMailboxFullMockNic::new([])
}

///|
pub impl @hal.Nic for ApMailboxFullMockNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  let sm0_addr = @protocol.reg_sm_base
  let sm1_addr = @protocol.reg_sm_base +
    @protocol.sm_entry_size.reinterpret_as_uint()
  self.next_response = match pdu.header.command {
    @protocol.APRD => {
      let response_data = if offset == sm0_addr {
        Bytes::makei(8, fn(i) {
          match i {
            0 => b'\x00'
            1 => b'\x10'
            2 => b'\x80'
            3 => b'\x00'
            5 => b'\x00'
            6 => b'\x01'
            _ => b'\x00'
          }
        })
      } else if offset == sm1_addr {
        let status = if self.mailbox_ready { b'\x08' } else { b'\x00' }
        Bytes::makei(8, fn(i) {
          match i {
            0 => b'\x80'
            1 => b'\x10'
            2 => b'\x80'
            3 => b'\x00'
            5 => status
            6 => b'\x01'
            _ => b'\x00'
          }
        })
      } else if offset == 0x1080U {
        self.mailbox_ready = false
        if self.response_index < self.responses.length() {
          let resp = self.responses[self.response_index]
          self.response_index += 1
          resp
        } else {
          Bytes::makei(128, fn(_) { b'\x00' })
        }
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.APWR => {
      if offset == 0x1000U {
        self.mailbox_ready = true
      }
      build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
    }
    _ => build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for ApMailboxFullMockNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for ApMailboxFullMockNic with close(self) {
  self.is_open = false
}

// ===== Response Frame Builders =====

///|
fn mbh_bytes(
  length : UInt,
  station : UInt,
  mb_type : @mailbox.MailboxType,
  counter : Byte,
) -> Bytes {
  let mbh : @mailbox.MailboxHeader = {
    length,
    address: station,
    channel: b'\x00',
    priority: b'\x00',
    mb_type,
    counter,
  }
  mbh.to_bytes()
}

///|
fn pad_to_128(frame : Bytes) -> Bytes {
  Bytes::makei(128, fn(i) {
    if i < frame.length() {
      frame[i]
    } else {
      b'\x00'
    }
  })
}

///|
/// Build SDO expedited download response (cmd=0x60).
fn build_sdo_download_resp(
  counter : Byte,
  station : UInt,
  index : UInt,
  subindex : Byte,
) -> Bytes {
  let hdr = mbh_bytes(10U, station, @mailbox.MailboxType::CoE, counter)
  pad_to_128(
    Bytes::makei(16, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x00'
          7 => b'\x30'
          8 => b'\x60'
          9 => (index & 0xFFU).to_byte()
          10 => ((index >> 8) & 0xFFU).to_byte()
          11 => subindex
          _ => b'\x00'
        }
      }
    }),
  )
}

///|
/// Build SDO expedited upload response (cmd=0x43, 4 bytes data).
fn build_sdo_upload_expedited_resp(
  counter : Byte,
  station : UInt,
  index : UInt,
  subindex : Byte,
  payload : Bytes,
) -> Bytes {
  let hdr = mbh_bytes(10U, station, @mailbox.MailboxType::CoE, counter)
  pad_to_128(
    Bytes::makei(16, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x00'
          7 => b'\x30'
          8 => b'\x43'
          9 => (index & 0xFFU).to_byte()
          10 => ((index >> 8) & 0xFFU).to_byte()
          11 => subindex
          _ => if i - 12 < payload.length() { payload[i - 12] } else { b'\x00' }
        }
      }
    }),
  )
}

///|
/// Build SDO non-expedited upload initiate response (segmented, size indicated).
/// cmd=0x41: bits[7:5]=010(UploadResponse), bit1=0(non-expedited), bit0=1(size_indicated)
fn build_sdo_upload_initiate_resp(
  counter : Byte,
  station : UInt,
  index : UInt,
  subindex : Byte,
  total_size : UInt,
) -> Bytes {
  let hdr = mbh_bytes(10U, station, @mailbox.MailboxType::CoE, counter)
  pad_to_128(
    Bytes::makei(16, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x00'
          7 => b'\x30'
          8 => b'\x41'
          9 => (index & 0xFFU).to_byte()
          10 => ((index >> 8) & 0xFFU).to_byte()
          11 => subindex
          12 => (total_size & 0xFFU).to_byte()
          13 => ((total_size >> 8) & 0xFFU).to_byte()
          14 => ((total_size >> 16) & 0xFFU).to_byte()
          15 => ((total_size >> 24) & 0xFFU).to_byte()
          _ => b'\x00'
        }
      }
    }),
  )
}

///|
/// Build SDO segmented upload response.
/// cmd: bits[7:5]=000, bit4=toggle, bits[3:1]=n_unused, bit0=last.
fn build_sdo_upload_segment_resp(
  counter : Byte,
  station : UInt,
  toggle : Bool,
  last : Bool,
  segment : Bytes,
) -> Bytes {
  let n_unused = 7 - segment.length()
  let cmd : Int = (if toggle { 0x10 } else { 0 }) |
    (n_unused << 1) |
    (if last { 1 } else { 0 })
  // mailbox length = CoE header(2) + cmd(1) + 7 = 10
  let hdr = mbh_bytes(10U, station, @mailbox.MailboxType::CoE, counter)
  pad_to_128(
    Bytes::makei(16, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x00'
          7 => b'\x30'
          8 => cmd.to_byte()
          _ => if i - 9 < segment.length() { segment[i - 9] } else { b'\x00' }
        }
      }
    }),
  )
}

///|
/// Build SDO segmented download response.
/// cmd: bits[7:5]=001, bit4=toggle. Payload is cmd byte only.
fn build_sdo_download_segment_resp(
  counter : Byte,
  station : UInt,
  toggle : Bool,
) -> Bytes {
  let cmd : Int = 0x20 | (if toggle { 0x10 } else { 0 })
  // mailbox length = CoE header(2) + cmd(1) = 3
  let hdr = mbh_bytes(3U, station, @mailbox.MailboxType::CoE, counter)
  pad_to_128(
    Bytes::makei(9, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x00'
          7 => b'\x30'
          8 => cmd.to_byte()
          _ => b'\x00'
        }
      }
    }),
  )
}

///|
/// Build FoE Ack response frame.
fn build_foe_ack_resp(
  counter : Byte,
  station : UInt,
  packet_number : UInt,
) -> Bytes {
  let hdr = mbh_bytes(6U, station, @mailbox.MailboxType::FoE, counter)
  pad_to_128(
    Bytes::makei(12, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x04'
          7 => b'\x00'
          8 => (packet_number & 0xFFU).to_byte()
          9 => ((packet_number >> 8) & 0xFFU).to_byte()
          10 => ((packet_number >> 16) & 0xFFU).to_byte()
          11 => ((packet_number >> 24) & 0xFFU).to_byte()
          _ => b'\x00'
        }
      }
    }),
  )
}

///|
/// Build FoE Data response frame.
fn build_foe_data_resp(
  counter : Byte,
  station : UInt,
  packet_number : UInt,
  payload : Bytes,
) -> Bytes {
  let payload_len = 6 + payload.length()
  let hdr = mbh_bytes(
    payload_len.reinterpret_as_uint(),
    station,
    @mailbox.MailboxType::FoE,
    counter,
  )
  let frame_len = 12 + payload.length()
  pad_to_128(
    Bytes::makei(frame_len, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x03'
          7 => b'\x00'
          8 => (packet_number & 0xFFU).to_byte()
          9 => ((packet_number >> 8) & 0xFFU).to_byte()
          10 => ((packet_number >> 16) & 0xFFU).to_byte()
          11 => ((packet_number >> 24) & 0xFFU).to_byte()
          _ => if i - 12 < payload.length() { payload[i - 12] } else { b'\x00' }
        }
      }
    }),
  )
}

///|
/// Build FoE Error response frame.
fn build_foe_error_resp(
  counter : Byte,
  station : UInt,
  error_code : UInt,
  text : String,
) -> Bytes {
  let text_bytes = text.to_array().map(fn(c) { c.to_int().to_byte() })
  let payload_len = 6 + text_bytes.length()
  let hdr = mbh_bytes(
    payload_len.reinterpret_as_uint(),
    station,
    @mailbox.MailboxType::FoE,
    counter,
  )
  let frame_len = 12 + text_bytes.length()
  pad_to_128(
    Bytes::makei(frame_len, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x05'
          7 => b'\x00'
          8 => (error_code & 0xFFU).to_byte()
          9 => ((error_code >> 8) & 0xFFU).to_byte()
          10 => ((error_code >> 16) & 0xFFU).to_byte()
          11 => ((error_code >> 24) & 0xFFU).to_byte()
          _ =>
            if i - 12 < text_bytes.length() {
              text_bytes[i - 12]
            } else {
              b'\x00'
            }
        }
      }
    }),
  )
}

///|
/// Build FoE Busy response frame.
fn build_foe_busy_resp(counter : Byte, station : UInt) -> Bytes {
  let hdr = mbh_bytes(2U, station, @mailbox.MailboxType::FoE, counter)
  pad_to_128(
    Bytes::makei(8, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x06'
          7 => b'\x00'
          _ => b'\x00'
        }
      }
    }),
  )
}

///|
/// Build SDO Info response frame.
/// opcode: e.g. 0x02 for OD list, 0x04 for OD description, 0x06 for OE description.
fn build_sdo_info_resp(
  counter : Byte,
  station : UInt,
  opcode : Byte,
  incomplete : Bool,
  payload : Bytes,
) -> Bytes {
  // SDO Info header: 4 bytes; CoE header: 2 bytes
  let mb_payload_len = 2 + 4 + payload.length()
  let hdr = mbh_bytes(
    mb_payload_len.reinterpret_as_uint(),
    station,
    @mailbox.MailboxType::CoE,
    counter,
  )
  let frame_len = 6 + mb_payload_len
  let opcode_byte : Byte = if incomplete { opcode | b'\x80' } else { opcode }
  pad_to_128(
    Bytes::makei(frame_len, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x00'
          7 => b'\x80'
          8 => opcode_byte
          9 => b'\x00'
          10 => b'\x00'
          11 => b'\x00'
          _ => if i - 12 < payload.length() { payload[i - 12] } else { b'\x00' }
        }
      }
    }),
  )
}

// ===== Standard test config =====

///|
let test_station : UInt = 0x1001U

///|
let test_timeout : @hal.Duration = @hal.Duration(1000L)

///|
fn test_mb_config() -> @mailbox.MailboxConfig {
  {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
}

// ========== SDO Expedited Download ==========

///|
test "integration/sdo_download expedited via FP mock" {
  let nic = MailboxMockNic::new([
    build_sdo_download_resp(b'\x01', test_station, 0x6040U, b'\x00'),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let data = Bytes::from_array([b'\x06', b'\x00', b'\x00', b'\x00'])
  @protocol.sdo_download(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x6040U,
    b'\x00',
    data,
    test_timeout,
  )
  // If we get here without error, the download succeeded
  assert_eq(nic.response_index, 1)
}

// ========== SDO Segmented Download ==========

///|
test "integration/sdo_download segmented 8 bytes via FP mock" {
  // 8 bytes data > 4 → segmented download
  // Flow: initiate download → DownloadResponse
  //       segment1 (7 bytes, toggle=false) → seg DownloadResponse
  //       segment2 (1 byte, toggle=true, last) → seg DownloadResponse
  let nic = MailboxMockNic::new([
    build_sdo_download_resp(b'\x01', test_station, 0x2000U, b'\x01'),
    build_sdo_download_segment_resp(b'\x02', test_station, false),
    build_sdo_download_segment_resp(b'\x03', test_station, true),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let data = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
  ])
  @protocol.sdo_download(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x2000U,
    b'\x01',
    data,
    test_timeout,
  )
  assert_eq(nic.response_index, 3)
}

// ========== SDO Expedited Upload ==========

///|
test "integration/sdo_upload expedited via FP mock" {
  let expected = Bytes::from_array([b'\xDE', b'\xAD', b'\xBE', b'\xEF'])
  let nic = MailboxMockNic::new([
    build_sdo_upload_expedited_resp(
      b'\x01', test_station, 0x1018U, b'\x01', expected,
    ),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let result = @protocol.sdo_upload(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x1018U,
    b'\x01',
    test_timeout,
  )
  assert_eq(result, expected)
}

// ========== SDO Segmented Upload ==========

///|
test "integration/sdo_upload segmented 10 bytes via FP mock" {
  // 10 bytes total: initiate (size=10, no initial data), seg1 (7 bytes), seg2 (3 bytes, last)
  let nic = MailboxMockNic::new([
    build_sdo_upload_initiate_resp(b'\x01', test_station, 0x2001U, b'\x00', 10U),
    build_sdo_upload_segment_resp(
      b'\x02',
      test_station,
      false,
      false,
      Bytes::from_array([
        b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07',
      ]),
    ),
    build_sdo_upload_segment_resp(
      b'\x03',
      test_station,
      true,
      true,
      Bytes::from_array([b'\x08', b'\x09', b'\x0A']),
    ),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let result = @protocol.sdo_upload(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x2001U,
    b'\x00',
    test_timeout,
  )
  assert_eq(result.length(), 10)
  assert_eq(
    result,
    Bytes::from_array([
      b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08', b'\x09',
      b'\x0A',
    ]),
  )
}

// ========== SDO Upload AP (expedited) ==========

///|
test "integration/sdo_upload_ap expedited via AP mock" {
  let expected = Bytes::from_array([b'\xCA', b'\xFE', b'\x00', b'\x00'])
  let nic = ApMailboxFullMockNic::new([
    build_sdo_upload_expedited_resp(
      b'\x01', test_station, 0x1001U, b'\x00', expected,
    ),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let result = @protocol.sdo_upload_ap(
    nic,
    0U,
    test_station,
    test_mb_config(),
    rmsm,
    0x1001U,
    b'\x00',
    test_timeout,
  )
  assert_eq(result, expected)
}

// ========== SDO Complete Access Download ==========

///|
test "integration/sdo_download_complete_access expedited via FP mock" {
  let nic = MailboxMockNic::new([
    build_sdo_download_resp(b'\x01', test_station, 0x1C12U, b'\x00'),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let data = Bytes::from_array([b'\x01', b'\x00', b'\x00', b'\x00'])
  @protocol.sdo_download_complete_access(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x1C12U,
    b'\x00',
    data,
    test_timeout,
  )
  assert_eq(nic.response_index, 1)
}

// ========== SDO Complete Access Download Segmented ==========

///|
test "integration/sdo_download_complete_access segmented via FP mock" {
  // 8 bytes data > 4 → segmented with CA flag
  let nic = MailboxMockNic::new([
    build_sdo_download_resp(b'\x01', test_station, 0x1C12U, b'\x00'),
    build_sdo_download_segment_resp(b'\x02', test_station, false),
    build_sdo_download_segment_resp(b'\x03', test_station, true),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let data = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
  ])
  @protocol.sdo_download_complete_access(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x1C12U,
    b'\x00',
    data,
    test_timeout,
  )
  assert_eq(nic.response_index, 3)
}

// ========== SDO Complete Access Upload ==========

///|
test "integration/sdo_upload_complete_access expedited via FP mock" {
  let expected = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let nic = MailboxMockNic::new([
    build_sdo_upload_expedited_resp(
      b'\x01', test_station, 0x1C13U, b'\x00', expected,
    ),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let result = @protocol.sdo_upload_complete_access(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x1C13U,
    b'\x00',
    test_timeout,
  )
  assert_eq(result, expected)
}

// ========== SDO Complete Access Upload Segmented ==========

///|
test "integration/sdo_upload_complete_access segmented via FP mock" {
  let nic = MailboxMockNic::new([
    build_sdo_upload_initiate_resp(b'\x01', test_station, 0x1C13U, b'\x00', 10U),
    build_sdo_upload_segment_resp(
      b'\x02',
      test_station,
      false,
      false,
      Bytes::from_array([
        b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07',
      ]),
    ),
    build_sdo_upload_segment_resp(
      b'\x03',
      test_station,
      true,
      true,
      Bytes::from_array([b'\x08', b'\x09', b'\x0A']),
    ),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let result = @protocol.sdo_upload_complete_access(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x1C13U,
    b'\x00',
    test_timeout,
  )
  assert_eq(result.length(), 10)
}

// ========== SDO Download Retry ==========

///|
test "integration/sdo_download_retry succeeds after timeout" {
  // First attempt times out (SM1 never ready), second attempt succeeds.
  // We use a special NIC that returns not-ready for SM1 on first round,
  // then ready on second round.
  let nic = MailboxMockNic::new([
    build_sdo_download_resp(b'\x01', test_station, 0x6040U, b'\x00'),
  ])
  // With max_retries=1, the retry budget allows one retry.
  let rmsm = @mailbox.Rmsm::new(max_retries=1)
  let data = Bytes::from_array([b'\x06', b'\x00', b'\x00', b'\x00'])
  @protocol.sdo_download_retry(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x6040U,
    b'\x00',
    data,
    test_timeout,
  )
  assert_eq(nic.response_index, 1)
}

// ========== SDO Upload Retry ==========

///|
test "integration/sdo_upload_retry succeeds first try via FP mock" {
  let expected = Bytes::from_array([b'\xAB', b'\xCD', b'\x00', b'\x00'])
  let nic = MailboxMockNic::new([
    build_sdo_upload_expedited_resp(
      b'\x01', test_station, 0x6041U, b'\x00', expected,
    ),
  ])
  let rmsm = @mailbox.Rmsm::new(max_retries=2)
  let result = @protocol.sdo_upload_retry(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x6041U,
    b'\x00',
    test_timeout,
  )
  assert_eq(result, expected)
}

// ========== SDO Upload Retry AP ==========

///|
test "integration/sdo_upload_retry_ap succeeds first try via AP mock" {
  let expected = Bytes::from_array([b'\x11', b'\x22', b'\x33', b'\x44'])
  let nic = ApMailboxFullMockNic::new([
    build_sdo_upload_expedited_resp(
      b'\x01', test_station, 0x6041U, b'\x00', expected,
    ),
  ])
  let rmsm = @mailbox.Rmsm::new(max_retries=1)
  let result = @protocol.sdo_upload_retry_ap(
    nic,
    0U,
    test_station,
    test_mb_config(),
    rmsm,
    0x6041U,
    b'\x00',
    test_timeout,
  )
  assert_eq(result, expected)
}

// ========== SDO Upload Retry AP timeout ==========

///|
test "integration/sdo_upload_retry_ap exhausts retries" {
  let nic = TimeoutMailboxMockNic::new()
  let rmsm = @mailbox.Rmsm::new(max_retries=1)
  let result : Result[Bytes, Error] = try? @protocol.sdo_upload_retry_ap(
    nic,
    0U,
    test_station,
    test_mb_config(),
    rmsm,
    0x6041U,
    b'\x00',
    test_timeout,
  )
  assert_true(result is Err(@hal.EcError::MailboxTimeout))
}

// ========== FoE Download (FP) ==========

///|
test "integration/foe_download via FP mock" {
  // Flow: Write → Ack(0), Data(1) → Ack(1)
  let nic = MailboxMockNic::new([
    build_foe_ack_resp(b'\x01', test_station, 0U),
    build_foe_ack_resp(b'\x02', test_station, 1U),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let file_data = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08', b'\x09',
    b'\x0A',
  ])
  @protocol.foe_download(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    "test.bin",
    0U,
    file_data,
    test_timeout,
  )
  assert_eq(nic.response_index, 2)
}

// ========== FoE Upload (FP) ==========

///|
test "integration/foe_upload via FP mock" {
  // Flow: Read → Data(1, short) → Ack(1) [EOF because segment < max_data]
  let file_content = Bytes::from_array([
    b'\xAA', b'\xBB', b'\xCC', b'\xDD', b'\xEE',
  ])
  let nic = MailboxMockNic::new([
    build_foe_data_resp(b'\x01', test_station, 1U, file_content),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let result = @protocol.foe_upload(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    "test.bin",
    0U,
    test_timeout,
  )
  assert_eq(result, file_content)
}

// ========== FoE Download Error ==========

///|
test "integration/foe_download error response raises" {
  let nic = MailboxMockNic::new([
    build_foe_error_resp(b'\x01', test_station, 0x8001U, "not found"),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let data = Bytes::from_array([b'\x01'])
  let result = try? @protocol.foe_download(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    "missing.bin",
    0U,
    data,
    test_timeout,
  )
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

// ========== FoE Download AP ==========

///|
test "integration/foe_download_ap via AP mock" {
  let nic = ApMailboxFullMockNic::new([
    build_foe_ack_resp(b'\x01', test_station, 0U),
    build_foe_ack_resp(b'\x02', test_station, 1U),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let file_data = Bytes::from_array([b'\x01', b'\x02', b'\x03'])
  @protocol.foe_download_ap(
    nic,
    0U,
    test_mb_config(),
    rmsm,
    "fw.bin",
    0U,
    file_data,
    test_timeout,
  )
  assert_eq(nic.response_index, 2)
}

// ========== FoE Upload AP ==========

///|
test "integration/foe_upload_ap via AP mock" {
  let file_content = Bytes::from_array([b'\x10', b'\x20', b'\x30'])
  let nic = ApMailboxFullMockNic::new([
    build_foe_data_resp(b'\x01', test_station, 1U, file_content),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let result = @protocol.foe_upload_ap(
    nic,
    0U,
    test_mb_config(),
    rmsm,
    "config.dat",
    0U,
    test_timeout,
  )
  assert_eq(result, file_content)
}

// ========== FoE Upload Error ==========

///|
test "integration/foe_upload error response raises" {
  let nic = MailboxMockNic::new([
    build_foe_error_resp(b'\x01', test_station, 0x8002U, "access denied"),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let result = try? @protocol.foe_upload(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    "secret.bin",
    0U,
    test_timeout,
  )
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

// ========== FoE Busy then Ack ==========

///|
test "integration/foe_download busy then ack via FP mock" {
  // First response to Write is Busy (counter=1), then retry re-sends with
  // new counter=2 (begin_retry_transaction), gets Ack(0) with counter=2.
  // Then data segment uses counter=3, gets Ack(1) with counter=3.
  let nic = MailboxMockNic::new([
    build_foe_busy_resp(b'\x01', test_station),
    build_foe_ack_resp(b'\x02', test_station, 0U),
    build_foe_ack_resp(b'\x03', test_station, 1U),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let file_data = Bytes::from_array([b'\xFF'])
  @protocol.foe_download(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    "fw.bin",
    0U,
    file_data,
    test_timeout,
  )
  assert_eq(nic.response_index, 3)
}

// ========== SDO Info Get OD List ==========

///|
test "integration/sdo_info_get_od_list via FP mock" {
  // Single fragment: opcode=0x02, incomplete=false
  // First 2 bytes are ListType (skipped), then pairs of index words.
  // Indices: 0x1000, 0x1018, 0x6000
  let info_payload = Bytes::from_array([
    b'\x01', b'\x00', // list_type = 1 (all objects)
     b'\x00', b'\x10', // 0x1000
     b'\x18', b'\x10', // 0x1018
     b'\x00', b'\x60', // 0x6000
  ])
  let nic = MailboxMockNic::new([
    build_sdo_info_resp(b'\x01', test_station, b'\x02', false, info_payload),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let indices = @protocol.sdo_info_get_od_list(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    1U,
    test_timeout,
  )
  assert_eq(indices.length(), 3)
  assert_eq(indices[0], 0x1000U)
  assert_eq(indices[1], 0x1018U)
  assert_eq(indices[2], 0x6000U)
}

// ========== SDO Info Get OD Description ==========

///|
test "integration/sdo_info_get_od_description via FP mock" {
  // OD description payload: index(2), data_type(2), max_subindex(1), object_code(1), name...
  let od_payload = Bytes::from_array([
    b'\x18', b'\x10', // index = 0x1018
     b'\x09', b'\x00', // data_type = 9 (RECORD)
     b'\x04', // max_subindex = 4
     b'\x09', // object_code = 9 (RECORD)
     b'\x49', b'\x44', // "ID" (name)
  ])
  let nic = MailboxMockNic::new([
    build_sdo_info_resp(b'\x01', test_station, b'\x04', false, od_payload),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let desc = @protocol.sdo_info_get_od_description(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x1018U,
    test_timeout,
  )
  assert_eq(desc.index, 0x1018U)
  assert_eq(desc.max_subindex, b'\x04')
}

// ========== SDO Info Get OE Description ==========

///|
test "integration/sdo_info_get_oe_description via FP mock" {
  // OE description payload: index(2), subindex(1), value_info(1),
  // data_type(2), bit_length(2), access(2), name...
  let oe_payload = Bytes::from_array([
    b'\x18', b'\x10', // index = 0x1018
     b'\x01', // subindex = 1
     b'\x00', // value_info = 0
     b'\x05', b'\x00', // data_type = 5 (UNSIGNED32)
     b'\x20', b'\x00', // bit_length = 32
     b'\x07', b'\x00', // access = 7 (RWR)
     b'\x56', b'\x49', // "VI" (name)
  ])
  let nic = MailboxMockNic::new([
    build_sdo_info_resp(b'\x01', test_station, b'\x06', false, oe_payload),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let entry = @protocol.sdo_info_get_oe_description(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x1018U,
    b'\x01',
    b'\x00',
    test_timeout,
  )
  assert_eq(entry.index, 0x1018U)
  assert_eq(entry.subindex, b'\x01')
  assert_eq(entry.bit_length, 32U)
}

// ========== SDO Info Multi-Fragment ==========

///|
test "integration/sdo_info_get_od_list multi-fragment via FP mock" {
  // Two fragments: first incomplete, second complete
  let frag1 = Bytes::from_array([
      b'\x01', b'\x00', // list_type = 1
       b'\x00', b'\x10',
    ], // 0x1000
  )
  let frag2 = Bytes::from_array([
    b'\x18', b'\x10', // 0x1018
     b'\x00', b'\x60', // 0x6000
  ])
  // Fragment 1 uses counter=1 from initial begin_transaction.
  // Fragment 2 uses counter=2 from continuation begin_transaction.
  let nic = MailboxMockNic::new([
    build_sdo_info_resp(b'\x01', test_station, b'\x02', true, frag1),
    build_sdo_info_resp(b'\x02', test_station, b'\x02', false, frag2),
  ])
  let rmsm = @mailbox.Rmsm::new()
  let indices = @protocol.sdo_info_get_od_list(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    1U,
    test_timeout,
  )
  assert_eq(indices.length(), 3)
  assert_eq(indices[0], 0x1000U)
  assert_eq(indices[1], 0x1018U)
  assert_eq(indices[2], 0x6000U)
}

// ========== SDO Abort ==========

///|
test "integration/sdo_upload abort response raises SdoAbort" {
  // Build an abort response: cmd=0x80, then index, subindex, then abort_code
  let hdr = mbh_bytes(10U, test_station, @mailbox.MailboxType::CoE, b'\x01')
  let abort_frame = pad_to_128(
    Bytes::makei(16, fn(i) {
      if i < 6 {
        hdr[i]
      } else {
        match i {
          6 => b'\x00'
          7 => b'\x30'
          8 => b'\x80'
          9 => b'\x18'
          10 => b'\x10'
          11 => b'\x01'
          12 => b'\x00'
          13 => b'\x00'
          14 => b'\x02'
          15 => b'\x06'
          _ => b'\x00'
        }
      }
    }),
  )
  let nic = MailboxMockNic::new([abort_frame])
  let rmsm = @mailbox.Rmsm::new()
  let result = try? @protocol.sdo_upload(
    nic,
    test_station,
    test_mb_config(),
    rmsm,
    0x1018U,
    b'\x01',
    test_timeout,
  )
  assert_true(result is Err(@hal.EcError::SdoAbort(_)))
}
