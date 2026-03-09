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
        header: { command: NOP, index: b'\x00', address: 0U, len_flags: 0U },
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
        header: { command: APRD, index: b'\x01', address: 0U, len_flags: 0U },
        data: Bytes::new(0),
        wkc: 0U,
      },
      {
        header: {
          command: FPWR,
          index: b'\x02',
          address: 0x1000U,
          len_flags: 2U,
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
  assert_eq(@protocol.address_station(addr), 0x1001U)
  assert_eq(@protocol.address_offset(addr), 0x0130U)
}

///|
test "address helpers - broadcast address" {
  let addr = @protocol.broadcast_address(0x0130U)
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
  let idx1 = builder.add(FPRD, 0x10010130U, Bytes::new(4))
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
