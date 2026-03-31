///|
test "EcCommand roundtrip byte conversion" {
  let cmds : Array[@protocol.EcCommand] = [
    APRD,
    APWR,
    APRW,
    FPRD,
    FPWR,
    FPRW,
    BRD,
    BWR,
    BRW,
    LRD,
    LWR,
    LRW,
    ARMW,
    FRMW,
  ]
  for cmd in cmds {
    let b = cmd.to_byte()
    let decoded = @protocol.EcCommand::from_byte(b)
    assert_eq(cmd, decoded)
  }
}

///|
test "EcCommand from_byte invalid raises error" {
  let result = try? @protocol.EcCommand::from_byte(b'\xFF')
  inspect(result, content="Err(InvalidPdu(\"unknown command byte: 255\"))")
}

///|
test "EsmState roundtrip byte conversion" {
  let states : Array[@protocol.EsmState] = [Init, PreOp, SafeOp, Op, Boot]
  for state in states {
    let b = state.to_byte()
    let decoded = @protocol.EsmState::from_byte(b)
    assert_eq(state, decoded)
  }
}

///|
test "EsmState valid transitions" {
  assert_true(
    @protocol.EsmState::Init.can_transition(@protocol.EsmState::PreOp),
  )
  assert_true(
    @protocol.EsmState::PreOp.can_transition(@protocol.EsmState::SafeOp),
  )
  assert_true(@protocol.EsmState::SafeOp.can_transition(@protocol.EsmState::Op))
  assert_true(@protocol.EsmState::Op.can_transition(@protocol.EsmState::SafeOp))
  // Invalid transition
  assert_true(
    not(@protocol.EsmState::Init.can_transition(@protocol.EsmState::Op)),
  )
}

///|
test "EcFrame encode/decode roundtrip - single NOP PDU" {
  let frame : @protocol.EcFrame = {
    dst_mac: @protocol.broadcast_mac,
    src_mac: @protocol.default_master_mac,
    pdus: [
      {
        header: {
          command: NOP,
          index: b'\x00',
          address: 0U,
          len_flags: 0U,
          irq: 0U,
        },
        data: Bytes::new(0),
        wkc: 0U,
      },
    ],
  }
  let encoded = frame.encode()
  let decoded = @protocol.EcFrame::decode(encoded)
  assert_eq(decoded.pdus.length(), 1)
  assert_eq(decoded.pdus[0].header.command, @protocol.EcCommand::NOP)
  assert_eq(decoded.pdus[0].wkc, 0U)
}

///|
fn build_response_frame(
  request : @protocol.EcFrame,
  data : Bytes,
  wkc : UInt,
) -> Bytes {
  let request_pdu = request.pdus[0]
  (
    {
      dst_mac: request.src_mac,
      src_mac: request.dst_mac,
      pdus: [
        {
          header: {
            command: request_pdu.header.command,
            index: request_pdu.header.index,
            address: request_pdu.header.address,
            len_flags: data.length().reinterpret_as_uint(),
            irq: request_pdu.header.irq,
          },
          data,
          wkc,
        },
      ],
    } : @protocol.EcFrame).encode()
}

///|
test "EcFrame encode/decode roundtrip - BRD with data" {
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let frame : @protocol.EcFrame = {
    dst_mac: @protocol.broadcast_mac,
    src_mac: @protocol.default_master_mac,
    pdus: [
      {
        header: {
          command: BRD,
          index: b'\x42',
          address: 0x1234U,
          len_flags: 4U,
          irq: 0x1234U,
        },
        data,
        wkc: 1U,
      },
    ],
  }
  let encoded = frame.encode()
  let decoded = @protocol.EcFrame::decode(encoded)
  assert_eq(decoded.pdus.length(), 1)
  assert_eq(decoded.pdus[0].header.command, @protocol.EcCommand::BRD)
  assert_eq(decoded.pdus[0].header.index, b'\x42')
  assert_eq(decoded.pdus[0].header.address, 0x1234U)
  assert_eq(decoded.pdus[0].header.irq, 0x1234U)
  assert_eq(decoded.pdus[0].data, data)
  assert_eq(decoded.pdus[0].wkc, 1U)
}

///|
test "EcFrame encode/decode roundtrip - multiple PDUs" {
  let frame : @protocol.EcFrame = {
    dst_mac: @protocol.broadcast_mac,
    src_mac: @protocol.default_master_mac,
    pdus: [
      {
        header: {
          command: APRD,
          index: b'\x01',
          address: 0U,
          len_flags: 0U,
          irq: 0U,
        },
        data: Bytes::new(0),
        wkc: 0U,
      },
      {
        header: {
          command: FPWR,
          index: b'\x02',
          address: 0x1000U,
          len_flags: 2U,
          irq: 0U,
        },
        data: Bytes::from_array([b'\xAA', b'\xBB']),
        wkc: 1U,
      },
    ],
  }
  let encoded = frame.encode()
  let decoded = @protocol.EcFrame::decode(encoded)
  assert_eq(decoded.pdus.length(), 2)
  assert_eq(decoded.pdus[0].header.command, @protocol.EcCommand::APRD)
  assert_eq(decoded.pdus[1].header.command, @protocol.EcCommand::FPWR)
  assert_eq(decoded.pdus[1].data, Bytes::from_array([b'\xAA', b'\xBB']))
  assert_eq(decoded.pdus[1].wkc, 1U)
}

///|
test "EcFrame decode fixture minimal_nop_frame" {
  let raw = @fixtures.minimal_nop_frame()
  let frame = @protocol.EcFrame::decode(raw)
  assert_eq(frame.pdus.length(), 1)
  assert_eq(frame.pdus[0].header.command, @protocol.EcCommand::NOP)
  assert_eq(frame.pdus[0].data.length(), 0)
  assert_eq(frame.pdus[0].wkc, 0U)
}

///|
test "EcFrame decode rejects short frame" {
  let short = Bytes::from_array([b'\x00', b'\x01'])
  let result = try? @protocol.EcFrame::decode(short)
  assert_true(result is Err(_))
}

///|
test "EcFrame decode rejects wrong ethertype" {
  // Build a frame with wrong ethertype (0x0800 = IPv4)
  let bad = Bytes::from_array([
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\x02', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x01', b'\x08', b'\x00', // wrong ethertype
     b'\x0C', b'\x10', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  let result = try? @protocol.EcFrame::decode(bad)
  assert_true(result is Err(_))
}

///|
test "address helpers - configured address packing" {
  let addr = @protocol.configured_address(0x1001U, 0x0130U)
  assert_eq(addr, 0x01301001U)
  assert_eq(@protocol.address_station(addr), 0x1001U)
  assert_eq(@protocol.address_offset(addr), 0x0130U)
}

///|
test "address helpers - broadcast address" {
  let addr = @protocol.broadcast_address(0x0130U)
  assert_eq(addr, 0x01300000U)
  assert_eq(@protocol.address_station(addr), 0U)
  assert_eq(@protocol.address_offset(addr), 0x0130U)
}

///|
test "address helpers - auto increment address" {
  let addr = @protocol.auto_increment_address(0U)
  assert_eq(addr, 0U)
  let addr2 = @protocol.auto_increment_address(3U)
  assert_eq(addr2, 3U)
}

///|
test "address helpers - logical address passthrough" {
  let addr = @protocol.logical_address(0xDEADBEEFU)
  assert_eq(addr, 0xDEADBEEFU)
}

///|
test "command selection by address type" {
  assert_eq(@protocol.read_command(AutoIncrement), @protocol.EcCommand::APRD)
  assert_eq(@protocol.write_command(Configured), @protocol.EcCommand::FPWR)
  assert_eq(@protocol.readwrite_command(Broadcast), @protocol.EcCommand::BRW)
  assert_eq(@protocol.read_command(Logical), @protocol.EcCommand::LRD)
  assert_eq(@protocol.write_command(Logical), @protocol.EcCommand::LWR)
  assert_eq(@protocol.readwrite_command(Logical), @protocol.EcCommand::LRW)
}

///|
test "FrameBuilder - add and build single PDU" {
  let builder = @protocol.FrameBuilder::new()
  let idx = builder.add(
    BRD,
    @protocol.broadcast_address(0x0130U),
    Bytes::new(2),
  )
  assert_eq(idx, b'\x00')
  assert_eq(builder.length(), 1)
  let frame = builder.build()
  assert_eq(frame.pdus.length(), 1)
  assert_eq(frame.pdus[0].header.command, @protocol.EcCommand::BRD)
  // After build, builder is reset
  assert_true(builder.is_empty())
}

///|
test "FrameBuilder - sequential index assignment" {
  let builder = @protocol.FrameBuilder::new()
  let idx0 = builder.add(BRD, 0U, Bytes::new(0))
  let idx1 = builder.add(
    FPRD,
    @protocol.configured_address(0x1001U, 0x0130U),
    Bytes::new(4),
  )
  let idx2 = builder.add(LRW, 0x1000U, Bytes::new(8))
  assert_eq(idx0, b'\x00')
  assert_eq(idx1, b'\x01')
  assert_eq(idx2, b'\x02')
  let frame = builder.build()
  assert_eq(frame.pdus.length(), 3)
}

///|
test "FrameBuilder - build and encode/decode roundtrip" {
  let builder = @protocol.FrameBuilder::new()
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let idx = builder.add(
    FPRD,
    @protocol.configured_address(0x1001U, 0x0130U),
    data,
  )
  let frame = builder.build()
  let encoded = frame.encode()
  let decoded = @protocol.EcFrame::decode(encoded)
  let found = @protocol.find_pdu_by_index(decoded, idx)
  assert_true(found is Some(_))
  guard found is Some(pdu)
  assert_eq(pdu.header.command, @protocol.EcCommand::FPRD)
  assert_eq(pdu.data, data)
}

///|
test "find_pdu_by_index returns None for missing index" {
  let frame : @protocol.EcFrame = {
    dst_mac: @protocol.broadcast_mac,
    src_mac: @protocol.default_master_mac,
    pdus: [],
  }
  assert_true(@protocol.find_pdu_by_index(frame, b'\xFF') is None)
}

///|
test "transact loopback - NOP roundtrip via MockNic" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let data = Bytes::new(0)
  let pdu = @protocol.transact_pdu(
    nic,
    @protocol.EcCommand::NOP,
    0U,
    data,
    timeout,
  )
  // MockNic echoes the sent frame, so the response PDU should match
  assert_eq(pdu.header.command, @protocol.EcCommand::NOP)
  assert_eq(pdu.wkc, 0U)
}

///|
test "transact loopback - BRD with payload via MockNic" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let pdu = @protocol.transact_pdu(
    nic,
    @protocol.EcCommand::BRD,
    @protocol.broadcast_address(0x0130U),
    data,
    timeout,
  )
  assert_eq(pdu.header.command, @protocol.EcCommand::BRD)
  assert_eq(pdu.data, data)
}

///|
test "transact loopback - full frame transaction via MockNic" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let builder = @protocol.FrameBuilder::new()
  let idx0 = builder.add(@protocol.EcCommand::APRD, 0U, Bytes::new(2))
  let idx1 = builder.add(
    @protocol.EcCommand::FPWR,
    @protocol.configured_address(0x1001U, 0x0130U),
    Bytes::from_array([b'\xAA', b'\xBB']),
  )
  let frame = builder.build()
  let response = @protocol.transact(nic, frame, timeout)
  // Both PDUs should be present in the echoed response
  let pdu0 = @protocol.find_pdu_by_index(response, idx0)
  let pdu1 = @protocol.find_pdu_by_index(response, idx1)
  assert_true(pdu0 is Some(_))
  assert_true(pdu1 is Some(_))
}

///|
pub struct NoiseMockNic {
  mut next_response : Bytes
  noise_response : Bytes
  mut emit_noise : Bool
  mut is_open : Bool
}

///|
fn NoiseMockNic::new() -> NoiseMockNic {
  NoiseMockNic::new_with_noise(ipv4_noise_frame())
}

///|
fn NoiseMockNic::new_with_noise(noise_response : Bytes) -> NoiseMockNic {
  {
    next_response: Bytes::new(0),
    noise_response,
    emit_noise: true,
    is_open: true,
  }
}

///|
fn ipv4_noise_frame() -> Bytes {
  Bytes::from_array([
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\x02', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x01', b'\x08', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00',
  ])
}

///|
pub impl @hal.Nic for NoiseMockNic with open_(name) {
  ignore(name)
  NoiseMockNic::new()
}

///|
pub impl @hal.Nic for NoiseMockNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response = data
  data.length()
}

///|
pub impl @hal.Nic for NoiseMockNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  if self.emit_noise {
    self.emit_noise = false
    return self.noise_response
  }
  self.next_response
}

///|
pub impl @hal.Nic for NoiseMockNic with close(self) {
  self.is_open = false
}

///|
test "transact ignores non-ethercat noise frames before response" {
  let nic = NoiseMockNic::new()
  let timeout = @hal.Duration(1000L)
  let pdu = @protocol.transact_pdu(
    nic,
    @protocol.EcCommand::NOP,
    0U,
    Bytes::new(0),
    timeout,
  )
  assert_eq(pdu.header.command, @protocol.EcCommand::NOP)
  assert_eq(pdu.wkc, 0U)
}

///|
test "transact ignores short noise frames before response" {
  let nic = NoiseMockNic::new_with_noise(Bytes::new(10))
  let timeout = @hal.Duration(1000L)
  let pdu = @protocol.transact_pdu(
    nic,
    @protocol.EcCommand::NOP,
    0U,
    Bytes::new(0),
    timeout,
  )
  assert_eq(pdu.header.command, @protocol.EcCommand::NOP)
  assert_eq(pdu.wkc, 0U)
}

///|
test "transact_pdu_retry - succeeds on first try" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let pdu = @protocol.transact_pdu_retry(
    nic,
    @protocol.EcCommand::BRD,
    0U,
    Bytes::new(0),
    timeout,
    3,
  )
  assert_eq(pdu.header.command, @protocol.EcCommand::BRD)
}

///|
test "count_slaves via mock loopback" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // MockNic echoes frames, so WKC will be 0 (no real slaves)
  let count = @protocol.count_slaves(nic, timeout)
  assert_eq(count, 0)
}

///|
test "register read/write helpers compile and run" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // Test that read_register_ap sends the right command
  let pdu = @protocol.read_register_ap(
    nic, 0U, @protocol.reg_al_status, 2, timeout,
  )
  assert_eq(pdu.header.command, @protocol.EcCommand::APRD)
}

///|
test "SlaveInfo construction" {
  let info : @protocol.SlaveInfo = {
    position: 0,
    configured_address: 0x1001U,
    identity: @fixtures.sample_ek1100_identity(),
    al_status: Init,
    dl_status: 0U,
    sii: None,
  }
  assert_eq(info.position, 0)
  assert_eq(info.configured_address, 0x1001U)
  assert_true(info.sii is None)
}

///|
test "ScanResult construction" {
  let scan : @protocol.ScanResult = { slave_count: 0, slaves: [] }
  assert_eq(scan.slave_count, 0)
  assert_eq(scan.slaves.length(), 0)
}

///|
test "EcFrame roundtrip preserves large PDU data" {
  // Create a PDU with 256 bytes of payload
  let data = Bytes::makei(256, fn(i) { (i % 256).to_byte() })
  let frame : @protocol.EcFrame = {
    dst_mac: @protocol.broadcast_mac,
    src_mac: @protocol.default_master_mac,
    pdus: [
      {
        header: {
          command: LRW,
          index: b'\x07',
          address: 0x10000U,
          len_flags: 256U,
          irq: 0U,
        },
        data,
        wkc: 42U,
      },
    ],
  }
  let decoded = @protocol.EcFrame::decode(frame.encode())
  assert_eq(decoded.pdus[0].data.length(), 256)
  assert_eq(decoded.pdus[0].data, data)
  assert_eq(decoded.pdus[0].wkc, 42U)
}

///|
test "EcFrame roundtrip preserves MAC addresses" {
  let custom_dst : FixedArray[Byte] = [
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06',
  ]
  let custom_src : FixedArray[Byte] = [
    b'\x0A', b'\x0B', b'\x0C', b'\x0D', b'\x0E', b'\x0F',
  ]
  let frame : @protocol.EcFrame = {
    dst_mac: custom_dst,
    src_mac: custom_src,
    pdus: [
      {
        header: {
          command: NOP,
          index: b'\x00',
          address: 0U,
          len_flags: 0U,
          irq: 0U,
        },
        data: Bytes::new(0),
        wkc: 0U,
      },
    ],
  }
  let decoded = @protocol.EcFrame::decode(frame.encode())
  assert_eq(decoded.dst_mac, custom_dst)
  assert_eq(decoded.src_mac, custom_src)
}

///|
test "EcFrame roundtrip preserves address through encode/decode" {
  let addr = @protocol.configured_address(0x1001U, 0x0130U)
  let frame : @protocol.EcFrame = {
    dst_mac: @protocol.broadcast_mac,
    src_mac: @protocol.default_master_mac,
    pdus: [
      {
        header: {
          command: FPRD,
          index: b'\x00',
          address: addr,
          len_flags: 0U,
          irq: 0U,
        },
        data: Bytes::new(0),
        wkc: 0U,
      },
    ],
  }
  let decoded = @protocol.EcFrame::decode(frame.encode())
  assert_eq(@protocol.address_station(decoded.pdus[0].header.address), 0x1001U)
  assert_eq(@protocol.address_offset(decoded.pdus[0].header.address), 0x0130U)
}

///|
test "EcFrame encode writes ADP before ADO on wire" {
  let frame : @protocol.EcFrame = {
    dst_mac: @protocol.broadcast_mac,
    src_mac: @protocol.default_master_mac,
    pdus: [
      {
        header: {
          command: FPRD,
          index: b'\x00',
          address: @protocol.configured_address(0x1001U, 0x0130U),
          len_flags: 0U,
          irq: 0U,
        },
        data: Bytes::new(0),
        wkc: 0U,
      },
    ],
  }
  let encoded = frame.encode()
  assert_eq(encoded[18], b'\x01')
  assert_eq(encoded[19], b'\x10')
  assert_eq(encoded[20], b'\x30')
  assert_eq(encoded[21], b'\x01')
}

///|
test "FrameBuilder index wraps at 256" {
  let builder = @protocol.FrameBuilder::new()
  // Manually set next_index near wrap point
  builder.next_index = 254
  let idx254 = builder.add(NOP, 0U, Bytes::new(0))
  assert_eq(idx254, b'\xFE')
  let _ = builder.build()
  let idx255 = builder.add(NOP, 0U, Bytes::new(0))
  assert_eq(idx255, b'\xFF')
  let _ = builder.build()
  let idx0 = builder.add(NOP, 0U, Bytes::new(0))
  assert_eq(idx0, b'\x00')
}

///|
test "all EcCommand values survive encode/decode" {
  let cmds : Array[@protocol.EcCommand] = [
    NOP,
    APRD,
    APWR,
    APRW,
    FPRD,
    FPWR,
    FPRW,
    BRD,
    BWR,
    BRW,
    LRD,
    LWR,
    LRW,
    ARMW,
    FRMW,
  ]
  for cmd in cmds {
    let frame : @protocol.EcFrame = {
      dst_mac: @protocol.broadcast_mac,
      src_mac: @protocol.default_master_mac,
      pdus: [
        {
          header: {
            command: cmd,
            index: b'\x00',
            address: 0U,
            len_flags: 0U,
            irq: 0U,
          },
          data: Bytes::new(0),
          wkc: 0U,
        },
      ],
    }
    let decoded = @protocol.EcFrame::decode(frame.encode())
    assert_eq(decoded.pdus[0].header.command, cmd)
  }
}

///|
test "discovery - assign_station_address via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // MockNic echoes with wkc=0 so this will raise SendFailed
  let result = try? @protocol.assign_station_address(nic, 0U, 0x1001U, timeout)
  assert_true(result is Err(_))
}

///|
test "discovery - read_station_address_ap via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let station_address = @protocol.read_station_address_ap(nic, 0U, timeout)
  assert_eq(station_address, 0U)
}

///|
test "discovery - read_register_fp command type" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let pdu = @protocol.read_register_fp(
    nic, 0x1001U, @protocol.reg_al_status, 2, timeout,
  )
  assert_eq(pdu.header.command, @protocol.EcCommand::FPRD)
}

///|
test "discovery - write_register_fp command type" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let data = Bytes::from_array([b'\x02', b'\x00'])
  let pdu = @protocol.write_register_fp(
    nic, 0x1001U, @protocol.reg_al_control, data, timeout,
  )
  assert_eq(pdu.header.command, @protocol.EcCommand::FPWR)
}

///|
test "discovery - write_register_ap command type" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let data = Bytes::from_array([b'\x01', b'\x10'])
  let pdu = @protocol.write_register_ap(
    nic, 0U, @protocol.reg_station_address, data, timeout,
  )
  assert_eq(pdu.header.command, @protocol.EcCommand::APWR)
}

///|
test "discovery - register address constants are reasonable" {
  // FMMU registers start at 0x0600
  assert_eq(@protocol.reg_fmmu_base, 0x0600U)
  assert_eq(@protocol.fmmu_entry_size, 16)
  // SM registers start at 0x0800
  assert_eq(@protocol.reg_sm_base, 0x0800U)
  assert_eq(@protocol.sm_entry_size, 8)
  // AL registers in expected range
  assert_true(@protocol.reg_al_status.reinterpret_as_int() >= 0x100)
  assert_true(@protocol.reg_al_control.reinterpret_as_int() >= 0x100)
  assert_eq(@protocol.reg_dl_control, 0x0100U)
  assert_eq(@protocol.reg_station_alias, 0x0012U)
  assert_eq(@protocol.dl_control_alias_enable_bit, 24)
  // SII registers
  assert_true(@protocol.reg_sii_control.reinterpret_as_int() >= 0x500)
}

///|
test "discovery - read_station_alias via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let station_alias = @protocol.read_station_alias(nic, 0x1001U, timeout)
  assert_eq(station_alias, 0U)
}

///|
test "discovery - enable_alias_addressing via mock returns error" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let result = try? @protocol.enable_alias_addressing(nic, 0x1001U, timeout)
  assert_true(result is Err(_))
}

///|
test "SlaveInfo with SII data" {
  let sii : @mailbox.SiiData = {
    vendor_id: 0x2U,
    product_code: 0x044C2C52U,
    revision: 0x00110000U,
    serial: 0U,
    bootstrap_rx_offset: 0U,
    bootstrap_rx_size: 0U,
    bootstrap_tx_offset: 0U,
    bootstrap_tx_size: 0U,
    mailbox_rx_offset: 0x1000U,
    mailbox_rx_size: 128U,
    mailbox_tx_offset: 0x1080U,
    mailbox_tx_size: 128U,
    mailbox_protocols: 0xCU,
    firmware_version: 0U,
    hardware_version: 0U,
    production_date_raw: 0U,
    pdi_control_1: b'\x00',
    esc_config_b0: b'\x00',
    pdi_config_1: 0U,
    pdi_config_1_ext: 0U,
    esc_config_b4: 0U,
    esc_config_b5: 0U,
    esc_config_b6: 0U,
    checksum_b: 0U,
    esc_config_b_present: false,
  }
  let info : @protocol.SlaveInfo = {
    position: 0,
    configured_address: 0x1001U,
    identity: @fixtures.sample_ek1100_identity(),
    al_status: Init,
    dl_status: 0x0037U,
    sii: Some(sii),
  }
  assert_true(info.sii is Some(_))
  guard info.sii is Some(s)
  assert_eq(s.vendor_id, 0x2U)
  assert_eq(s.mailbox_protocols, 0xCU)
}

///|
test "identity validation - matching" {
  let expected : @hal.SlaveIdentity = {
    vendor_id: 0x2U,
    product_code: 0x044C2C52U,
    revision: 0x00110000U,
    serial: 0U,
  }
  let actual = @fixtures.sample_ek1100_identity()
  assert_eq(expected, actual)
}

///|
test "identity validation - mismatch detection" {
  let expected : @hal.SlaveIdentity = {
    vendor_id: 0x2U,
    product_code: 0x12345678U, // different product
    revision: 0x00110000U,
    serial: 0U,
  }
  let actual = @fixtures.sample_ek1100_identity()
  assert_true(expected != actual)
}

///|
test "SlaveConfig construction" {
  let cfg : @hal.SlaveConfig = {
    position: 0U,
    expected_identity: Some(@fixtures.sample_ek1100_identity()),
    expected_identification: None,
    expected_alias_address: None,
    configured_address: 0x1001U,
    presence: @hal.Mandatory,
  }
  assert_eq(cfg.position, 0U)
  assert_eq(cfg.configured_address, 0x1001U)
  assert_true(cfg.expected_identity is Some(_))
}

///|
test "ESM state transitions - Init to Boot" {
  assert_true(@protocol.EsmState::Init.can_transition(@protocol.EsmState::Boot))
}

///|
test "ESM state transitions - Boot to Init" {
  assert_true(@protocol.EsmState::Boot.can_transition(@protocol.EsmState::Init))
}

///|
test "ESM state transitions - PreOp to Init" {
  assert_true(
    @protocol.EsmState::PreOp.can_transition(@protocol.EsmState::Init),
  )
}

///|
test "ESM state transitions - SafeOp to Init" {
  assert_true(
    @protocol.EsmState::SafeOp.can_transition(@protocol.EsmState::Init),
  )
}

///|
test "ESM state transitions - Op to SafeOp only" {
  // Op can go to SafeOp
  assert_true(@protocol.EsmState::Op.can_transition(@protocol.EsmState::SafeOp))
  // Op can also go to PreOp and Init per ETG.1000
  assert_true(@protocol.EsmState::Op.can_transition(@protocol.EsmState::PreOp))
  assert_true(@protocol.EsmState::Op.can_transition(@protocol.EsmState::Init))
  // Op cannot go to Boot
  assert_true(
    not(@protocol.EsmState::Op.can_transition(@protocol.EsmState::Boot)),
  )
}

///|
test "FrameBuilder - max PDU capacity" {
  let builder = @protocol.FrameBuilder::new()
  for _i = 0; _i < @protocol.max_pdus_per_frame; _i = _i + 1 {
    let _ = builder.add(NOP, 0U, Bytes::new(0))
  }
  assert_eq(builder.length(), @protocol.max_pdus_per_frame)
  let frame = builder.build()
  assert_eq(frame.pdus.length(), @protocol.max_pdus_per_frame)
}

///|
test "full discovery flow simulation" {
  // Simulate a scan workflow: count → assign → read registers
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // 1. Count slaves (mock returns 0)
  let count = @protocol.count_slaves(nic, timeout)
  assert_eq(count, 0)
  // 2. Build scan result
  let scan : @protocol.ScanResult = { slave_count: count, slaves: [] }
  assert_eq(scan.slave_count, 0)
  assert_eq(scan.slaves.length(), 0)
}

///|
test "build_transition_path to Op" {
  let path = @protocol.build_transition_path(@protocol.EsmState::Op)
  assert_eq(path.length(), 4)
  assert_eq(path[0], @protocol.EsmState::Init)
  assert_eq(path[1], @protocol.EsmState::PreOp)
  assert_eq(path[2], @protocol.EsmState::SafeOp)
  assert_eq(path[3], @protocol.EsmState::Op)
}

///|
test "build_transition_path to PreOp" {
  let path = @protocol.build_transition_path(@protocol.EsmState::PreOp)
  assert_eq(path.length(), 2)
  assert_eq(path[0], @protocol.EsmState::Init)
  assert_eq(path[1], @protocol.EsmState::PreOp)
}

///|
test "build_transition_path to Boot" {
  let path = @protocol.build_transition_path(@protocol.EsmState::Boot)
  assert_eq(path.length(), 2)
  assert_eq(path[0], @protocol.EsmState::Init)
  assert_eq(path[1], @protocol.EsmState::Boot)
}

///|
test "build_shutdown_path from Op" {
  let path = @protocol.build_shutdown_path(@protocol.EsmState::Op)
  assert_eq(path.length(), 4)
  assert_eq(path[0], @protocol.EsmState::Op)
  assert_eq(path[1], @protocol.EsmState::SafeOp)
  assert_eq(path[2], @protocol.EsmState::PreOp)
  assert_eq(path[3], @protocol.EsmState::Init)
}

///|
test "build_shutdown_path from Init is idempotent" {
  let path = @protocol.build_shutdown_path(@protocol.EsmState::Init)
  assert_eq(path.length(), 1)
  assert_eq(path[0], @protocol.EsmState::Init)
}

///|
pub struct EsmControlNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut current_state : Byte
  mut error_indication : Bool
  mut status_code : UInt
  control_writes : Array[Byte]
}

///|
fn EsmControlNic::new(
  current_state : @protocol.EsmState,
  error_indication : Bool,
  status_code : UInt,
) -> EsmControlNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    current_state: current_state.to_byte(),
    error_indication,
    status_code,
    control_writes: [],
  }
}

///|
fn esm_status_bytes(nic : EsmControlNic) -> Bytes {
  let status = if nic.error_indication {
    nic.current_state | b'\x10'
  } else {
    nic.current_state
  }
  Bytes::from_array([status, b'\x00'])
}

///|
fn esm_status_code_bytes(status_code : UInt) -> Bytes {
  Bytes::from_array([
    (status_code & 0xFFU).reinterpret_as_int().to_byte(),
    ((status_code >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
  ])
}

///|
pub impl @hal.Nic for EsmControlNic with open_(name) {
  ignore(name)
  EsmControlNic::new(@protocol.EsmState::Init, false, 0U)
}

///|
pub impl @hal.Nic for EsmControlNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_al_status {
        esm_status_bytes(self)
      } else if offset == @protocol.reg_al_status_code {
        esm_status_code_bytes(self.status_code)
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
        let control = pdu.data[0]
        self.control_writes.push(control)
        let requested_state = control & b'\x0F'
        let acknowledge = (control & b'\x10') != b'\x00'
        if acknowledge {
          self.error_indication = false
          self.status_code = 0U
        }
        if requested_state != self.current_state {
          let current = @protocol.EsmState::from_byte(self.current_state)
          let target = @protocol.EsmState::from_byte(requested_state)
          if current.can_transition(target) {
            self.current_state = requested_state
            self.error_indication = false
            self.status_code = 0U
          } else {
            self.error_indication = true
            self.status_code = 0x0011U
          }
        }
      }
      build_response_frame(request, esm_status_bytes(self), 1U)
    }
    _ => build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for EsmControlNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for EsmControlNic with close(self) {
  self.is_open = false
}

///|
pub struct EsmRollbackToInitNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut current_state : Byte
  mut error_indication : Bool
  mut status_code : UInt
  control_writes : Array[Byte]
}

///|
fn EsmRollbackToInitNic::new(
  current_state : @protocol.EsmState,
  status_code : UInt,
) -> EsmRollbackToInitNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    current_state: current_state.to_byte(),
    error_indication: true,
    status_code,
    control_writes: [],
  }
}

///|
fn esm_rollback_status_bytes(nic : EsmRollbackToInitNic) -> Bytes {
  let status = if nic.error_indication {
    nic.current_state | b'\x10'
  } else {
    nic.current_state
  }
  Bytes::from_array([status, b'\x00'])
}

///|
pub impl @hal.Nic for EsmRollbackToInitNic with open_(name) {
  ignore(name)
  EsmRollbackToInitNic::new(@protocol.EsmState::PreOp, 0x001EU)
}

///|
pub impl @hal.Nic for EsmRollbackToInitNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_al_status {
        esm_rollback_status_bytes(self)
      } else if offset == @protocol.reg_al_status_code {
        esm_status_code_bytes(self.status_code)
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
        let control = pdu.data[0]
        self.control_writes.push(control)
        let requested_state = control & b'\x0F'
        let acknowledge = (control & b'\x10') != b'\x00'
        if requested_state == @protocol.EsmState::Init.to_byte() {
          self.current_state = requested_state
          self.error_indication = false
          self.status_code = 0U
        } else if acknowledge && requested_state == self.current_state {
          self.error_indication = true
        }
      }
      build_response_frame(request, esm_rollback_status_bytes(self), 1U)
    }
    _ => build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for EsmRollbackToInitNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for EsmRollbackToInitNic with close(self) {
  self.is_open = false
}

///|
pub struct EsmOpNeedsPdoNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut current_state : Byte
  mut op_request_pending : Bool
  mut pdo_after_op_request : Int
  required_pdo_after_op_request : Int
}

///|
fn EsmOpNeedsPdoNic::new(
  current_state : @protocol.EsmState,
) -> EsmOpNeedsPdoNic {
  EsmOpNeedsPdoNic::with_required_pdo_cycles(current_state, 1)
}

///|
fn EsmOpNeedsPdoNic::with_required_pdo_cycles(
  current_state : @protocol.EsmState,
  required_pdo_after_op_request : Int,
) -> EsmOpNeedsPdoNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    current_state: current_state.to_byte(),
    op_request_pending: false,
    pdo_after_op_request: 0,
    required_pdo_after_op_request,
  }
}

///|
fn esm_op_needs_pdo_status_bytes(nic : EsmOpNeedsPdoNic) -> Bytes {
  Bytes::from_array([nic.current_state, b'\x00'])
}

///|
pub impl @hal.Nic for EsmOpNeedsPdoNic with open_(name) {
  ignore(name)
  EsmOpNeedsPdoNic::new(@protocol.EsmState::SafeOp)
}

///|
pub impl @hal.Nic for EsmOpNeedsPdoNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_al_status {
        esm_op_needs_pdo_status_bytes(self)
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
        let requested_state = pdu.data[0] & b'\x0F'
        let current = @protocol.EsmState::from_byte(self.current_state)
        let target = @protocol.EsmState::from_byte(requested_state)
        if current == @protocol.EsmState::SafeOp &&
          target == @protocol.EsmState::Op {
          self.op_request_pending = true
        } else if current.can_transition(target) {
          self.current_state = requested_state
        }
      }
      build_response_frame(request, esm_op_needs_pdo_status_bytes(self), 1U)
    }
    @protocol.LRW | @protocol.LWR => {
      if self.op_request_pending {
        self.pdo_after_op_request = self.pdo_after_op_request + 1
        if self.pdo_after_op_request >= self.required_pdo_after_op_request {
          self.current_state = @protocol.EsmState::Op.to_byte()
          self.op_request_pending = false
        }
      }
      build_response_frame(request, pdu.data, 1U)
    }
    _ => build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for EsmOpNeedsPdoNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for EsmOpNeedsPdoNic with close(self) {
  self.is_open = false
}

///|
pub struct EsmOpFailureSnapshotNic {
  mut next_response : Bytes
  mut is_open : Bool
  current_state : Byte
  mut error_indication : Bool
  mut status_code : UInt
  mut op_request_pending : Bool
}

///|
fn EsmOpFailureSnapshotNic::new() -> EsmOpFailureSnapshotNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    current_state: @protocol.EsmState::SafeOp.to_byte(),
    error_indication: false,
    status_code: 0U,
    op_request_pending: false,
  }
}

///|
fn esm_op_failure_snapshot_status_bytes(nic : EsmOpFailureSnapshotNic) -> Bytes {
  let status = if nic.error_indication {
    nic.current_state | b'\x10'
  } else {
    nic.current_state
  }
  Bytes::from_array([status, b'\x00'])
}

///|
pub impl @hal.Nic for EsmOpFailureSnapshotNic with open_(name) {
  ignore(name)
  EsmOpFailureSnapshotNic::new()
}

///|
pub impl @hal.Nic for EsmOpFailureSnapshotNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_al_status {
        esm_op_failure_snapshot_status_bytes(self)
      } else if offset == @protocol.reg_al_status_code {
        Bytes::from_array([
          (self.status_code & 0xFFU).reinterpret_as_int().to_byte(),
          ((self.status_code >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
        ])
      } else {
        Bytes::new(pdu.data.length())
      }
      build_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
        let requested_state = pdu.data[0] & b'\x0F'
        let acknowledge = (pdu.data[0] & b'\x10') != b'\x00'
        if acknowledge {
          self.error_indication = false
          self.status_code = 0U
          self.op_request_pending = false
        } else if requested_state == @protocol.EsmState::Op.to_byte() {
          self.op_request_pending = true
        }
      }
      build_response_frame(
        request,
        esm_op_failure_snapshot_status_bytes(self),
        1U,
      )
    }
    @protocol.LRW | @protocol.LWR => {
      if self.op_request_pending {
        self.error_indication = true
        self.status_code = 0x001BU
        self.op_request_pending = false
      }
      build_response_frame(request, pdu.data, 1U)
    }
    _ => build_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for EsmOpFailureSnapshotNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for EsmOpFailureSnapshotNic with close(self) {
  self.is_open = false
}

///|
test "build_strict_transition_route to Op respects PreOp and SafeOp" {
  let path = @protocol.build_strict_transition_route(
    @protocol.EsmState::Init,
    @protocol.EsmState::Op,
  )
  assert_eq(path, [
    @protocol.EsmState::Init,
    @protocol.EsmState::PreOp,
    @protocol.EsmState::SafeOp,
    @protocol.EsmState::Op,
  ])
}

///|
test "transition_to_target_strict rotates through legal direct steps" {
  let nic = EsmControlNic::new(@protocol.EsmState::Init, false, 0U)
  let timeout = @hal.Duration(1000L)
  let final_state = @protocol.transition_to_target_strict(
    nic,
    0x1001U,
    @protocol.EsmState::Op,
    timeout,
  )
  assert_eq(final_state, @protocol.EsmState::Op)
  assert_eq(nic.control_writes.length(), 3)
  assert_eq(
    nic.control_writes[0] & b'\x0F',
    @protocol.EsmState::PreOp.to_byte(),
  )
  assert_eq(
    nic.control_writes[1] & b'\x0F',
    @protocol.EsmState::SafeOp.to_byte(),
  )
  assert_eq(nic.control_writes[2] & b'\x0F', @protocol.EsmState::Op.to_byte())
}

///|
test "request_state_with_process_data keeps sending PDO until Op is confirmed" {
  let nic = EsmOpNeedsPdoNic::new(@protocol.EsmState::SafeOp)
  let timeout = @hal.Duration(1000L)
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let pdo_ctx = @protocol.PdoContext::build([(mapping, 0x1001U)], 0x1000U)
  let final_state = @protocol.request_state_with_process_data(
    nic,
    0x1001U,
    @protocol.EsmState::Op,
    pdo_ctx,
    timeout,
  )
  assert_eq(final_state, @protocol.EsmState::Op)
  assert_eq(nic.current_state, @protocol.EsmState::Op.to_byte())
  assert_true(nic.pdo_after_op_request >= 1)
}

///|
test "request_state_with_process_data extends confirmation window beyond fixed 32 polls" {
  let nic = EsmOpNeedsPdoNic::with_required_pdo_cycles(
    @protocol.EsmState::SafeOp,
    48,
  )
  let timeout = @hal.Duration(1_000_000L)
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let pdo_ctx = @protocol.PdoContext::build([(mapping, 0x1001U)], 0x1000U)
  let final_state = @protocol.request_state_with_process_data(
    nic,
    0x1001U,
    @protocol.EsmState::Op,
    pdo_ctx,
    timeout,
  )
  assert_eq(final_state, @protocol.EsmState::Op)
  assert_eq(nic.current_state, @protocol.EsmState::Op.to_byte())
  assert_true(nic.pdo_after_op_request >= 48)
}

///|
test "request_state_with_process_data_snapshot captures AL error window" {
  let nic = EsmOpFailureSnapshotNic::new()
  let timeout = @hal.Duration(1000L)
  let mapping : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let pdo_ctx = @protocol.PdoContext::build([(mapping, 0x1001U)], 0x1000U)
  let snapshot = @protocol.request_state_with_process_data_snapshot(
    nic,
    0x1001U,
    @protocol.EsmState::Op,
    pdo_ctx,
    timeout,
  )
  assert_eq(snapshot.state, @protocol.EsmState::SafeOp)
  assert_true(snapshot.error_indication)
  assert_eq(snapshot.status_code, Some(0x001BU))
}

///|
test "transition_to_target_strict rejects pending AL error indication" {
  let nic = EsmControlNic::new(@protocol.EsmState::SafeOp, true, 0x0016U)
  let timeout = @hal.Duration(1000L)
  let result : Result[@protocol.EsmState, Error] = try? @protocol.transition_to_target_strict(
    nic,
    0x1001U,
    @protocol.EsmState::Op,
    timeout,
  )
  guard result is Err(@hal.EcError::EsmStateError(message)) else {
    fail("expected strict transition to reject pending AL error indication")
  }
  assert_true(message.contains("clear the error"))
}

///|
test "clear_al_error stabilizes state before caller chooses next target" {
  let nic = EsmControlNic::new(@protocol.EsmState::SafeOp, true, 0x0016U)
  let timeout = @hal.Duration(1000L)
  let cleared = @protocol.clear_al_error(nic, 0x1001U, timeout)
  assert_eq(cleared.state, @protocol.EsmState::SafeOp)
  assert_true(not(cleared.error_indication))
  assert_eq(cleared.status_code, None)
  let final_state = @protocol.transition_to_target_strict(
    nic,
    0x1001U,
    @protocol.EsmState::Init,
    timeout,
  )
  assert_eq(final_state, @protocol.EsmState::Init)
  assert_eq(nic.control_writes.length(), 3)
  assert_eq(
    nic.control_writes[0],
    @protocol.EsmState::SafeOp.to_byte() | b'\x10',
  )
  assert_eq(
    nic.control_writes[1] & b'\x0F',
    @protocol.EsmState::PreOp.to_byte(),
  )
  assert_eq(nic.control_writes[2] & b'\x0F', @protocol.EsmState::Init.to_byte())
}

///|
test "recover_al_error_for_transition rolls configuration error back to init" {
  let nic = EsmRollbackToInitNic::new(@protocol.EsmState::PreOp, 0x001EU)
  let timeout = @hal.Duration(1000L)
  let recovered = @protocol.recover_al_error_for_transition(
    nic, 0x1001U, timeout,
  )
  assert_eq(recovered.state, @protocol.EsmState::Init)
  assert_true(not(recovered.error_indication))
  assert_eq(recovered.status_code, None)
  assert_eq(nic.control_writes.length(), 2)
  assert_eq(
    nic.control_writes[0],
    @protocol.EsmState::PreOp.to_byte() | b'\x10',
  )
  assert_eq(nic.control_writes[1] & b'\x0F', @protocol.EsmState::Init.to_byte())
}

///|
test "transition_through with empty path raises error" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let result = try? @protocol.transition_through(nic, 0x1001U, [], timeout)
  assert_true(result is Err(_))
}

///|
test "broadcast_state via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let wkc = @protocol.broadcast_state(nic, @protocol.EsmState::Init, timeout)
  assert_eq(wkc, 0U) // MockNic echoes, WKC=0
}

///|
test "read_al_status via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // MockNic echoes the sent frame (which has zero-initialized data)
  // EsmState::from_byte(0) will fail because 0 isn't a valid ESM state
  let result = try? @protocol.read_al_status(nic, 0x1001U, timeout)
  // We expect either a valid state or an error from the mock
  match result {
    Ok(state) => assert_true(state is Init)
    Err(_) => () // acceptable with mock
  }
}

///|
test "read_al_status_code via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let code = @protocol.read_al_status_code(nic, 0x1001U, timeout)
  // MockNic returns zeroed data, so status code = 0
  assert_eq(code, 0U)
}

///|
test "ESM default timeout values by target state" {
  assert_eq(
    @protocol.esm_default_timeout(@protocol.EsmState::Init),
    @hal.Duration(5_000_000_000L),
  )
  assert_eq(
    @protocol.esm_default_timeout(@protocol.EsmState::PreOp),
    @hal.Duration(3_000_000_000L),
  )
  assert_eq(
    @protocol.esm_default_timeout(@protocol.EsmState::SafeOp),
    @hal.Duration(10_000_000_000L),
  )
  assert_eq(
    @protocol.esm_default_timeout(@protocol.EsmState::Op),
    @hal.Duration(10_000_000_000L),
  )
  assert_eq(
    @protocol.esm_default_timeout(@protocol.EsmState::Boot),
    @hal.Duration(5_000_000_000L),
  )
}

///|
test "ESM timeout policy uses override then default" {
  let policy : @protocol.EsmTimeoutPolicy = {
    init: Some(@hal.Duration(9L)),
    preop: None,
    safeop: Some(@hal.Duration(11L)),
    op: None,
    boot: None,
  }
  assert_eq(
    @protocol.esm_timeout_for(@protocol.EsmState::Init, policy),
    @hal.Duration(9L),
  )
  assert_eq(
    @protocol.esm_timeout_for(@protocol.EsmState::SafeOp, policy),
    @hal.Duration(11L),
  )
  // No override for PreOp -> falls back to default policy.
  assert_eq(
    @protocol.esm_timeout_for(@protocol.EsmState::PreOp, policy),
    @protocol.esm_default_timeout(@protocol.EsmState::PreOp),
  )
}

///|
test "ProcessImage construction" {
  let img = @protocol.ProcessImage::new(32, 16)
  assert_eq(img.output_size, 32)
  assert_eq(img.input_size, 16)
  assert_eq(img.outputs.length(), 32)
  assert_eq(img.inputs.length(), 16)
}

///|
test "PdoContext build from slave mappings" {
  let sm1 : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 32,
    input_bytes: 16,
  }
  let sm2 : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 8,
    input_bytes: 4,
  }
  let ctx = @protocol.PdoContext::build(
    [(sm1, 0x1001U), (sm2, 0x1002U)],
    0x10000U,
  )
  assert_eq(ctx.mappings.length(), 2)
  assert_eq(ctx.image.output_size, 40) // 32 + 8
  assert_eq(ctx.image.input_size, 20) // 16 + 4
  assert_eq(ctx.logical_size, 60) // 40 + 20
  // First slave starts at logical base
  assert_eq(ctx.mappings[0].output_logical, 0x10000U)
  assert_eq(ctx.mappings[0].output_offset, 0)
  assert_eq(ctx.mappings[0].output_length, 32)
  // Second slave follows
  assert_eq(ctx.mappings[1].output_offset, 32)
  assert_eq(ctx.mappings[1].input_offset, 16)
}

///|
test "PdoContext set and get slave data" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0U)
  // Set outputs for slave
  let out_data = Bytes::from_array([b'\xAA', b'\xBB', b'\xCC', b'\xDD'])
  ctx.set_slave_outputs(0x1001U, out_data)
  assert_eq(ctx.image.outputs[0], b'\xAA')
  assert_eq(ctx.image.outputs[3], b'\xDD')
  // Get inputs (initially zero)
  let in_data = ctx.get_slave_inputs(0x1001U)
  assert_eq(in_data.length(), 2)
  assert_eq(in_data[0], b'\x00')
}

///|
test "PdoContext set_slave_outputs rejects wrong length" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 0,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0U)
  let result = try? ctx.set_slave_outputs(0x1001U, Bytes::new(2))
  assert_true(result is Err(_))
}

///|
test "PdoContext set_slave_outputs rejects unknown station" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 0,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0U)
  let result = try? ctx.set_slave_outputs(0x9999U, Bytes::new(4))
  assert_true(result is Err(_))
}

// ========== Mailbox Transport Tests ==========

///|
test "mailbox_poll via mock loopback" {
  // MockNic echoes frames; the response data will be zeroed (from the request)
  // so SM status bit 3 = 0 → mailbox not ready
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 64U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 64U,
    in_sm_index: 1,
  }
  let ready = @protocol.mailbox_poll(nic, 0x1001U, cfg, timeout)
  assert_eq(ready, false) // Echo returns zero data → not ready
}

///|
test "mailbox_poll reports deactivated mailbox sync manager" {
  let nic = RepeatMailboxMockNic::new()
  nic.deactivated_mailbox = true
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 64U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 64U,
    in_sm_index: 1,
  }
  let result = try? @protocol.mailbox_poll(nic, 0x1001U, cfg, timeout)
  match result {
    Err(@hal.EcError::MailboxProtocol(message)) => {
      assert_true(message.contains("deactivated/reset"))
      assert_true(message.contains("control=0x102"))
    }
    _ => fail("expected MailboxProtocol for deactivated mailbox sync manager")
  }
}

///|
test "mailbox_send via mock loopback" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 64U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 64U,
    in_sm_index: 1,
  }
  // Should succeed without error
  @protocol.mailbox_send(nic, 0x1001U, cfg, Bytes::new(16), timeout)
}

///|
test "mailbox_send rejects oversized data" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 16U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 16U,
    in_sm_index: 1,
  }
  let result = try? @protocol.mailbox_send(
    nic,
    0x1001U,
    cfg,
    Bytes::new(32), // larger than out_size
    timeout,
  )
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

///|
test "mailbox_recv times out when poll never succeeds" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 64U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 64U,
    in_sm_index: 1,
  }
  // MockNic echoes zero data → poll always returns false → should timeout
  let result = try? @protocol.mailbox_recv(
    nic,
    0x1001U,
    cfg,
    timeout,
    max_polls=3,
  )
  assert_true(result is Err(@hal.EcError::MailboxTimeout))
}

///|
pub struct RepeatMailboxMockNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut repeat_triggered : Bool
  mut deactivated_mailbox : Bool
  mut last_command : Byte
  mut last_offset : UInt
}

///|
fn RepeatMailboxMockNic::new() -> RepeatMailboxMockNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    repeat_triggered: false,
    deactivated_mailbox: false,
    last_command: b'\xFF',
    last_offset: 0U,
  }
}

///|
pub struct TimeoutMailboxMockNic {
  mut next_response : Bytes
  mut is_open : Bool
}

///|
fn TimeoutMailboxMockNic::new() -> TimeoutMailboxMockNic {
  { next_response: Bytes::new(0), is_open: true }
}

///|
pub struct ApMailboxMockNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut mailbox_ready : Bool
  mut repeat_triggered : Bool
  mut last_command : Byte
  mut last_offset : UInt
}

///|
fn ApMailboxMockNic::new() -> ApMailboxMockNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    mailbox_ready: false,
    repeat_triggered: false,
    last_command: b'\xFF',
    last_offset: 0U,
  }
}

///|
fn build_ap_mailbox_sdo_upload_response(
  station : UInt,
  counter : Byte,
  index : UInt,
  subindex : Byte,
  payload : Bytes,
) -> Bytes {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: station,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter,
  }
  let hdr = mbh.to_bytes()
  let frame = Bytes::makei(16, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00'
    } else if i == 7 {
      b'\x30'
    } else if i == 8 {
      b'\x43'
    } else if i == 9 {
      (index & 0xFFU).to_byte()
    } else if i == 10 {
      ((index >> 8) & 0xFFU).to_byte()
    } else if i == 11 {
      subindex
    } else if i < 12 + payload.length() {
      payload[i - 12]
    } else {
      b'\x00'
    }
  })
  Bytes::makei(128, fn(i) {
    if i < frame.length() {
      frame[i]
    } else {
      b'\x00'
    }
  })
}

///|
pub impl @hal.Nic for RepeatMailboxMockNic with open_(name) {
  ignore(name)
  RepeatMailboxMockNic::new()
}

///|
pub impl @hal.Nic for RepeatMailboxMockNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  self.last_command = pdu.header.command.to_byte()
  self.last_offset = @protocol.address_offset(pdu.header.address)
  let sm1_base_addr = @protocol.reg_sm_base +
    @protocol.sm_entry_size.reinterpret_as_uint()
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if self.last_offset == sm1_base_addr {
        if self.deactivated_mailbox {
          Bytes::makei(8, fn(i) {
            if i == 5 {
              b'\x30'
            } else if i == 6 {
              b'\x02'
            } else if i == 7 {
              b'\x01'
            } else {
              b'\x00'
            }
          })
        } else {
          let status = if self.repeat_triggered { b'\x08' } else { b'\x00' }
          let repeat_ack = if self.repeat_triggered { b'\x02' } else { b'\x00' }
          Bytes::makei(8, fn(i) {
            if i == 5 {
              status
            } else if i == 7 {
              repeat_ack
            } else {
              b'\x00'
            }
          })
        }
      } else if self.last_offset == 0x1080U {
        build_ap_mailbox_sdo_upload_response(
          0x1001U,
          b'\x01',
          0x1001U,
          b'\x00',
          Bytes::from_array([b'\xAA', b'\x00', b'\x00', b'\x00']),
        )
      } else {
        Bytes::new(pdu.data.length())
      }
      build_eeprom_response(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if self.last_offset == sm1_base_addr + 6U && pdu.data.length() >= 1 {
        self.repeat_triggered = (pdu.data[0] & b'\x02') != b'\x00'
      }
      build_eeprom_response(request, Bytes::new(pdu.data.length()), 1U)
    }
    _ => build_eeprom_response(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for RepeatMailboxMockNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for RepeatMailboxMockNic with close(self) {
  self.is_open = false
}

///|
pub impl @hal.Nic for TimeoutMailboxMockNic with open_(name) {
  ignore(name)
  TimeoutMailboxMockNic::new()
}

///|
pub impl @hal.Nic for TimeoutMailboxMockNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  let sm0_base_addr = @protocol.reg_sm_base
  let sm1_base_addr = @protocol.reg_sm_base +
    @protocol.sm_entry_size.reinterpret_as_uint()
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == sm0_base_addr || offset == sm1_base_addr {
        Bytes::makei(8, fn(_i) { b'\x00' })
      } else {
        Bytes::new(pdu.data.length())
      }
      build_eeprom_response(request, response_data, 1U)
    }
    _ => build_eeprom_response(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for TimeoutMailboxMockNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for TimeoutMailboxMockNic with close(self) {
  self.is_open = false
}

///|
pub impl @hal.Nic for ApMailboxMockNic with open_(name) {
  ignore(name)
  ApMailboxMockNic::new()
}

///|
pub impl @hal.Nic for ApMailboxMockNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  self.last_command = pdu.header.command.to_byte()
  self.last_offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.APRD => {
      let sm1_base_addr = @protocol.reg_sm_base +
        @protocol.sm_entry_size.reinterpret_as_uint()
      let response_data = if self.last_offset == sm1_base_addr {
        let status = if self.mailbox_ready || self.repeat_triggered {
          b'\x08'
        } else {
          b'\x00'
        }
        let repeat_ack = if self.repeat_triggered { b'\x02' } else { b'\x00' }
        Bytes::makei(8, fn(i) {
          if i == 5 {
            status
          } else if i == 7 {
            repeat_ack
          } else {
            b'\x00'
          }
        })
      } else if self.last_offset == 0x1080U {
        build_ap_mailbox_sdo_upload_response(
          0x1001U,
          b'\x01',
          0x1001U,
          b'\x00',
          Bytes::from_array([b'\xAA', b'\x00', b'\x00', b'\x00']),
        )
      } else {
        Bytes::new(pdu.data.length())
      }
      build_eeprom_response(request, response_data, 1U)
    }
    @protocol.APWR => {
      let sm1_activate_addr = @protocol.reg_sm_base +
        @protocol.sm_entry_size.reinterpret_as_uint() +
        6U
      if self.last_offset == 0x1000U {
        self.mailbox_ready = true
      } else if self.last_offset == sm1_activate_addr && pdu.data.length() >= 1 {
        self.repeat_triggered = (pdu.data[0] & b'\x02') != b'\x00'
      }
      build_eeprom_response(request, Bytes::new(pdu.data.length()), 1U)
    }
    _ => build_eeprom_response(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for ApMailboxMockNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for ApMailboxMockNic with close(self) {
  self.is_open = false
}

///|
test "mailbox_poll_ap reads status via APRD" {
  let nic = ApMailboxMockNic::new()
  let timeout = @hal.Duration(1000L)
  nic.mailbox_ready = true
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let ready = @protocol.mailbox_poll_ap(nic, 0U, cfg, timeout)
  let expected_status_addr = @protocol.reg_sm_base +
    cfg.in_sm_index.reinterpret_as_uint() *
    @protocol.sm_entry_size.reinterpret_as_uint()
  assert_true(ready)
  assert_eq(nic.last_command, @protocol.APRD.to_byte())
  assert_eq(nic.last_offset, expected_status_addr)
}

///|
test "mailbox_send_ap writes output mailbox via APWR" {
  let nic = ApMailboxMockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  @protocol.mailbox_send_ap(nic, 0U, cfg, Bytes::new(16), timeout)
  assert_eq(nic.last_command, @protocol.APWR.to_byte())
  assert_eq(nic.last_offset, 0x1000U)
}

///|
test "mailbox_read_ap reads input mailbox via APRD" {
  let nic = ApMailboxMockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let data = @protocol.mailbox_read_ap(nic, 0U, cfg, timeout)
  assert_eq(nic.last_command, @protocol.APRD.to_byte())
  assert_eq(nic.last_offset, 0x1080U)
  assert_eq(data.length(), 128)
}

///|
test "mailbox_recv_rmsm requests repeat and returns replayed frame" {
  let nic = RepeatMailboxMockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 64U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let rmsm = @mailbox.Rmsm::new(max_retries=0)
  ignore(rmsm.begin_transaction())
  let frame = @protocol.mailbox_recv_rmsm(
    nic,
    0x1001U,
    cfg,
    rmsm,
    timeout,
    max_polls=1,
  )
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_true(nic.repeat_triggered)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::CoE)
  assert_eq(mbh.counter, b'\x01')
}

///|
test "sdo_upload_retry stops after retry budget is exhausted" {
  let nic = TimeoutMailboxMockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 64U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let rmsm = @mailbox.Rmsm::new(max_retries=1)
  let result : Result[Bytes, Error] = try? @protocol.sdo_upload_retry(
    nic, 0x1001U, cfg, rmsm, 0x1001U, b'\x00', timeout,
  )
  assert_true(result is Err(@hal.EcError::MailboxTimeout))
}

///|
test "mailbox_recv_ap_rmsm requests repeat and returns replayed frame" {
  let nic = ApMailboxMockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let rmsm = @mailbox.Rmsm::new(max_retries=0)
  ignore(rmsm.begin_transaction())
  let frame = @protocol.mailbox_recv_ap_rmsm(
    nic,
    0U,
    cfg,
    rmsm,
    timeout,
    max_polls=1,
  )
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_true(nic.repeat_triggered)
  assert_eq(mbh.counter, b'\x01')
}

///|
test "sdo_upload_ap reads expedited payload via AP mailbox transport" {
  let nic = ApMailboxMockNic::new()
  let timeout = @hal.Duration(1000L)
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  let payload = @protocol.sdo_upload_ap(
    nic,
    0U,
    0x1001U,
    cfg,
    @mailbox.Rmsm::new(),
    0x1001U,
    b'\x00',
    timeout,
  )
  assert_eq(payload, Bytes::from_array([b'\xAA', b'\x00', b'\x00', b'\x00']))
}

///|
pub struct EepromMockNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut sii_word_address : UInt
  image : Bytes
}

///|
fn EepromMockNic::new() -> EepromMockNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    sii_word_address: 0U,
    image: Bytes::new(0),
  }
}

///|
fn EepromMockNic::with_image(image : Bytes) -> EepromMockNic {
  { next_response: Bytes::new(0), is_open: true, sii_word_address: 0U, image }
}

///|
fn build_eeprom_response(
  request : @protocol.EcFrame,
  data : Bytes,
  wkc : UInt,
) -> Bytes {
  let request_pdu = request.pdus[0]
  (
    {
      dst_mac: request.src_mac,
      src_mac: request.dst_mac,
      pdus: [
        {
          header: {
            command: request_pdu.header.command,
            index: request_pdu.header.index,
            address: request_pdu.header.address,
            len_flags: data.length().reinterpret_as_uint(),
            irq: request_pdu.header.irq,
          },
          data,
          wkc,
        },
      ],
    } : @protocol.EcFrame).encode()
}

///|
pub impl @hal.Nic for EepromMockNic with open_(name) {
  ignore(name)
  EepromMockNic::new()
}

///|
pub impl @hal.Nic for EepromMockNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.FPWR | @protocol.APWR => {
      if offset == @protocol.reg_sii_control && pdu.data.length() >= 4 {
        self.sii_word_address = pdu.data[2].to_uint() |
          (pdu.data[3].to_uint() << 8)
      }
      build_eeprom_response(request, Bytes::new(pdu.data.length()), 1U)
    }
    @protocol.FPRD | @protocol.APRD => {
      let response_data = if offset == @protocol.reg_sii_control {
        Bytes::from_array([b'\x00', b'\x00'])
      } else if offset == @protocol.reg_sii_data {
        let byte_offset = self.sii_word_address.reinterpret_as_int() * 2
        if self.image.length() > 0 {
          Bytes::makei(pdu.data.length(), fn(i) {
            let index = byte_offset + i
            if index < self.image.length() {
              self.image[index]
            } else {
              b'\xFF'
            }
          })
        } else {
          Bytes::makei(pdu.data.length(), fn(i) {
            (self.sii_word_address.reinterpret_as_int() * 2 + i).to_byte()
          })
        }
      } else {
        Bytes::new(pdu.data.length())
      }
      build_eeprom_response(request, response_data, 1U)
    }
    _ => build_eeprom_response(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for EepromMockNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for EepromMockNic with close(self) {
  self.is_open = false
}

// ========== EEPROM Read Tests ==========

///|
test "eeprom_read_word via mock loopback" {
  let nic = EepromMockNic::new()
  let timeout = @hal.Duration(1000L)
  let data = @protocol.eeprom_read_word(nic, 0x1001U, 0U, timeout)
  assert_eq(data.length(), 4)
}

///|
test "eeprom_read multi-word via mock" {
  let nic = EepromMockNic::new()
  let timeout = @hal.Duration(1000L)
  let data = @protocol.eeprom_read(nic, 0x1001U, 0U, 3, timeout)
  assert_eq(data.length(), 12) // 3 words * 4 bytes
}

///|
fn make_sii_image(byte_size : Int) -> Bytes {
  let image = Array::make(byte_size, b'\x00')
  let encoded_size = if byte_size <= 0x80 {
    0U
  } else {
    (byte_size.reinterpret_as_uint() - 0x80U) >> 7
  }
  image[124] = (encoded_size & 0xFFU).to_byte()
  image[125] = ((encoded_size >> 8) & 0xFFU).to_byte()
  for i = 0; i < byte_size; i = i + 1 {
    image[i] = (i % 251).to_byte()
  }
  image[124] = (encoded_size & 0xFFU).to_byte()
  image[125] = ((encoded_size >> 8) & 0xFFU).to_byte()
  Bytes::from_array(image)
}

///|
test "read_sii_bytes expands probe to eeprom size" {
  let nic = EepromMockNic::with_image(make_sii_image(512))
  let timeout = @hal.Duration(1000L)
  let data = @protocol.read_sii_bytes(nic, 0x1001U, 8, timeout)
  assert_eq(data.length(), 512)
}

///|
test "read_sii_bytes_ap expands probe to eeprom size" {
  let nic = EepromMockNic::with_image(make_sii_image(512))
  let timeout = @hal.Duration(1000L)
  let data = @protocol.read_sii_bytes_ap(nic, 0U, 8, timeout)
  assert_eq(data.length(), 512)
}

// ========== ESM Extensions Tests ==========

///|
test "read_device_emulation via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // MockNic echoes zero data → bit 7 = 0 → no device emulation
  let is_emu = @protocol.read_device_emulation(nic, 0x1001U, timeout)
  assert_eq(is_emu, false)
}

///|
test "request_state_aware without device_emulation same as request_state" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // MockNic echoes zeros → read_al_status gets 0x00 → EsmStateError
  let result = try? @protocol.request_state_aware(
    nic,
    0x1001U,
    @protocol.EsmState::Init,
    timeout,
  )
  assert_true(result is Err(@hal.EcError::EsmStateError(_)))
}

///|
test "request_state_aware with device_emulation" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // With device_emulation flag, should check error indication first,
  // then proceed to request_state (which also gets EsmStateError from mock)
  let result = try? @protocol.request_state_aware(
    nic,
    0x1001U,
    @protocol.EsmState::Init,
    device_emulation=true,
    timeout,
  )
  assert_true(result is Err(@hal.EcError::EsmStateError(_)))
}

///|
test "set_sm_enable via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // Enable SM2
  @protocol.set_sm_enable(nic, 0x1001U, 2, true, timeout)
  // Disable SM2
  @protocol.set_sm_enable(nic, 0x1001U, 2, false, timeout)
}

///|
test "apply_op_only_policy no-op when not op_only" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // When op_only = false, should do nothing
  @protocol.apply_op_only_policy(
    nic,
    0x1001U,
    @protocol.EsmState::SafeOp,
    false,
    [2],
    timeout,
  )
}

///|
test "apply_op_only_policy disables SM when not Op" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // When op_only = true and state is SafeOp, should disable SM
  @protocol.apply_op_only_policy(
    nic,
    0x1001U,
    @protocol.EsmState::SafeOp,
    true,
    [2],
    timeout,
  )
}

///|
test "apply_op_only_policy enables SM when Op" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // When op_only = true and state is Op, should enable SM
  @protocol.apply_op_only_policy(
    nic,
    0x1001U,
    @protocol.EsmState::Op,
    true,
    [2, 3],
    timeout,
  )
}

// ========== Distributed Clock Tests ==========

///|
test "dc_latch_times via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  @protocol.dc_latch_times(nic, timeout)
}

///|
test "dc_read_receive_time via mock returns zero" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let t = @protocol.dc_read_receive_time(nic, 0x1001U, timeout)
  assert_eq(t, 0U)
}

///|
test "watchdog register constants match ETG1000.4 addresses" {
  assert_eq(@protocol.reg_watchdog_divider, 0x0400U)
  assert_eq(@protocol.reg_watchdog_time_pdi, 0x0410U)
  assert_eq(@protocol.reg_watchdog_time_pdata, 0x0420U)
  assert_eq(@protocol.reg_watchdog_status_pdata, 0x0440U)
  assert_eq(@protocol.reg_watchdog_counter_pdata, 0x0442U)
}

///|
test "SmWatchdogConfig struct equality and derive Show" {
  let a : @protocol.SmWatchdogConfig = {
    divider: 0x09C2U,
    pdi_time: 0x03E8U,
    pdata_time: 0x03E8U,
    pdata_status: true,
    pdata_counter: 5U,
  }
  let b : @protocol.SmWatchdogConfig = {
    divider: 0x09C2U,
    pdi_time: 0x03E8U,
    pdata_time: 0x03E8U,
    pdata_status: true,
    pdata_counter: 5U,
  }
  assert_eq(a, b)
  // Show derive produces non-empty string
  assert_true(a.to_string().length() > 0)
}

///|
test "SmWatchdogConfig inequality on different pdata_time" {
  let a : @protocol.SmWatchdogConfig = {
    divider: 0x09C2U,
    pdi_time: 0x03E8U,
    pdata_time: 0x03E8U,
    pdata_status: true,
    pdata_counter: 0U,
  }
  let b : @protocol.SmWatchdogConfig = {
    divider: 0x09C2U,
    pdi_time: 0x03E8U,
    pdata_time: 0U,
    pdata_status: true,
    pdata_counter: 0U,
  }
  assert_true(a != b)
}

///|
test "read_sm_watchdog_config via mock returns zeroed defaults" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let config = @protocol.read_sm_watchdog_config(nic, 0x1001U, timeout)
  // MockNic loopback echoes frame with zero-filled data area for FPRD
  assert_eq(config.divider, 0U)
  assert_eq(config.pdi_time, 0U)
  assert_eq(config.pdata_time, 0U)
  assert_eq(config.pdata_status, false)
  assert_eq(config.pdata_counter, 0U)
}

///|
test "esm_timeout_policy_from_sii_timeouts returns defaults when None" {
  let policy = @protocol.esm_timeout_policy_from_sii_timeouts(None)
  assert_eq(policy, @protocol.default_esm_timeout_policy())
  assert_eq(policy.init, None)
  assert_eq(policy.preop, None)
  assert_eq(policy.safeop, None)
  assert_eq(policy.op, None)
  assert_eq(policy.boot, None)
}

///|
test "esm_timeout_policy_from_sii_timeouts maps SII fields correctly" {
  let timeouts : @mailbox.SiiTimeouts = {
    preop_timeout_ms: 2000U,
    safeop_op_timeout_ms: 5000U,
    back_to_init_timeout_ms: 1000U,
    back_to_safeop_timeout_ms: 3000U,
    mailbox_request_timeout_ms: 100U,
    mailbox_response_timeout_ms: 200U,
  }
  let policy = @protocol.esm_timeout_policy_from_sii_timeouts(Some(timeouts))
  // preop_timeout_ms → preop
  assert_eq(policy.preop, Some(@hal.Duration(2_000_000_000L)))
  // safeop_op_timeout_ms → op
  assert_eq(policy.op, Some(@hal.Duration(5_000_000_000L)))
  // back_to_init_timeout_ms → init
  assert_eq(policy.init, Some(@hal.Duration(1_000_000_000L)))
  // back_to_safeop_timeout_ms → safeop
  assert_eq(policy.safeop, Some(@hal.Duration(3_000_000_000L)))
  // boot is always None
  assert_eq(policy.boot, None)
}

///|
test "esm_timeout_policy_from_sii_timeouts zero fields remain None" {
  let timeouts : @mailbox.SiiTimeouts = {
    preop_timeout_ms: 0U,
    safeop_op_timeout_ms: 0U,
    back_to_init_timeout_ms: 0U,
    back_to_safeop_timeout_ms: 0U,
    mailbox_request_timeout_ms: 0U,
    mailbox_response_timeout_ms: 0U,
  }
  let policy = @protocol.esm_timeout_policy_from_sii_timeouts(Some(timeouts))
  assert_eq(policy, @protocol.default_esm_timeout_policy())
}

///|
test "dc_read_sync_window via mock returns zero" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let w = @protocol.dc_read_sync_window(nic, 0x1001U, timeout)
  assert_eq(w, 0U)
}

///|
test "dc_configure_sync0 via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  @protocol.dc_configure_sync0(nic, 0x1001U, 1_000_000U, timeout)
}

///|
test "dc_compensate_cycle via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  @protocol.dc_compensate_cycle(nic, 0x1001U, timeout)
}

///|
test "dc_configure_linear returns reference station" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let result = @protocol.dc_configure_linear(
    nic,
    [0x1001U, 0x1002U],
    1_000_000U,
    timeout,
    static_sync_iterations=2,
  )
  assert_true(result is Some(_))
  match result {
    Some(info) => {
      assert_eq(info.reference_station, 0x1001U)
      assert_eq(info.configured_count, 2)
    }
    None => assert_true(false)
  }
}

///|
test "dc_reestimate_propagation_delays via mock" {
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  @protocol.dc_reestimate_propagation_delays(
    nic,
    0x1001U,
    [0x1001U, 0x1002U],
    timeout,
  )
}

///|
test "PdoContext get_slave_inputs rejects unknown station" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 0,
    input_bytes: 4,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0U)
  let result = try? ctx.get_slave_inputs(0x9999U)
  assert_true(result is Err(_))
}

///|
test "pdo_exchange via mock loopback" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 4,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0U)
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let wkc = @protocol.pdo_exchange(nic, ctx, timeout)
  assert_eq(wkc, 0U) // MockNic echoes, WKC=0
}

///|
test "pdo_read via mock loopback" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 0,
    input_bytes: 8,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0U)
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let wkc = @protocol.pdo_read(nic, ctx, timeout)
  assert_eq(wkc, 0U)
}

///|
test "pdo_write via mock loopback" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 8,
    input_bytes: 0,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0U)
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let wkc = @protocol.pdo_write(nic, ctx, timeout)
  assert_eq(wkc, 0U)
}

///|
test "pdo_exchange with empty context" {
  let ctx = @protocol.PdoContext::build([], 0U)
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let wkc = @protocol.pdo_exchange(nic, ctx, timeout)
  assert_eq(wkc, 0U) // no data to exchange
}

///|
test "pdo_exchange_result with block_lrw uses split LRD+LWR" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0U)
  ctx.block_lrw = true
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  // MockNic returns WKC=0 for all transactions; verify no crash and result shape
  let result = @protocol.pdo_exchange_result(nic, ctx, timeout)
  // LRD WKC + LWR WKC*2, both 0 from mock
  assert_eq(result.wkc, 0U)
}

///|
test "pdo_exchange_result with block_lrw false uses LRW" {
  let sm : @mailbox.SlaveMapping = {
    sm_configs: [],
    fmmu_configs: [],
    output_bytes: 2,
    input_bytes: 2,
  }
  let ctx = @protocol.PdoContext::build([(sm, 0x1001U)], 0U)
  assert_true(not(ctx.block_lrw))
  let nic = @mock.MockNic::new()
  let timeout = @hal.Duration(1000L)
  let result = @protocol.pdo_exchange_result(nic, ctx, timeout)
  assert_eq(result.wkc, 0U)
}

///|
test "PdoContext build sets block_lrw to false by default" {
  let ctx = @protocol.PdoContext::build([], 0U)
  assert_true(not(ctx.block_lrw))
}

///|
test "al_status_code_description known codes" {
  assert_eq(@protocol.al_status_code_description(0x0000U), "No error")
  assert_eq(
    @protocol.al_status_code_description(0x001EU),
    "Invalid input configuration",
  )
  assert_eq(
    @protocol.al_status_code_description(0x0016U),
    "Invalid mailbox configuration (SafeOp)",
  )
  assert_eq(
    @protocol.al_status_code_description(0x0070U),
    "Detected module ident list does not match",
  )
  assert_eq(
    @protocol.al_status_code_description(0x0030U),
    "Invalid DC SYNC configuration",
  )
  assert_eq(@protocol.al_status_code_description(0x0051U), "EEPROM error")
}

///|
test "al_status_code_description unknown code" {
  let desc = @protocol.al_status_code_description(0xABCDU)
  assert_true(desc.contains("Unknown"))
}
