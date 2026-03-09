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
