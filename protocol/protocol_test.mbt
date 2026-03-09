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
        header: { command: NOP, index: b'\x00', address: 0U, len_flags: 0U },
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
        header: { command: FPRD, index: b'\x00', address: addr, len_flags: 0U },
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
          header: { command: cmd, index: b'\x00', address: 0U, len_flags: 0U },
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
  // SII registers
  assert_true(@protocol.reg_sii_control.reinterpret_as_int() >= 0x500)
}

///|
test "SlaveInfo with SII data" {
  let sii : @mailbox.SiiData = {
    vendor_id: 0x2U,
    product_code: 0x044C2C52U,
    revision: 0x00110000U,
    serial: 0U,
    mailbox_rx_offset: 0x1000U,
    mailbox_rx_size: 128U,
    mailbox_tx_offset: 0x1080U,
    mailbox_tx_size: 128U,
    mailbox_protocols: 0xCU,
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
    configured_address: 0x1001U,
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
