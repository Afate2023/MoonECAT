///|
test "FaultRule: Always schedule fires every time" {
  let rule = @mock.FaultRule::new(@mock.RecvTimeout, @mock.Always)
  assert_true(rule.should_fire(0))
  assert_true(rule.should_fire(1))
  assert_true(rule.should_fire(2))
  assert_eq(rule.fired_count, 3)
}

///|
test "FaultRule: Once schedule fires exactly once" {
  let rule = @mock.FaultRule::new(@mock.RecvTimeout, @mock.Once)
  assert_true(rule.should_fire(0))
  assert_false(rule.should_fire(1))
  assert_false(rule.should_fire(2))
  assert_eq(rule.fired_count, 1)
}

///|
test "FaultRule: CountDown(3) fires 3 times then stops" {
  let rule = @mock.FaultRule::new(@mock.FrameDrop, @mock.CountDown(3))
  assert_true(rule.should_fire(0))
  assert_true(rule.should_fire(1))
  assert_true(rule.should_fire(2))
  assert_false(rule.should_fire(3))
  assert_eq(rule.fired_count, 3)
}

///|
test "FaultRule: AfterN(2) dormant then permanent" {
  let rule = @mock.FaultRule::new(@mock.RecvTimeout, @mock.AfterN(2))
  assert_false(rule.should_fire(0))
  assert_false(rule.should_fire(1))
  assert_true(rule.should_fire(2))
  assert_true(rule.should_fire(3))
  assert_eq(rule.fired_count, 2)
}

///|
test "FaultRule: AtCycle(3) fires only at cycle 3" {
  let rule = @mock.FaultRule::new(@mock.RecvTimeout, @mock.AtCycle(3))
  assert_false(rule.should_fire(0))
  assert_false(rule.should_fire(1))
  assert_false(rule.should_fire(2))
  assert_true(rule.should_fire(3))
  assert_false(rule.should_fire(4))
  assert_eq(rule.fired_count, 1)
}

///|
test "FaultInjector: RecvTimeout injection raises RecvTimeout" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x044C2C52,
    revision: 0x00120000,
    serial: 0x00000001,
  }
  let slave = @mock.VirtualSlave::new(0, identity, b"")
  let nic = @mock.VirtualNic::with_slaves([slave])
  let fault_nic = @mock.FaultNic::wrap(nic)
  fault_nic.injector.add(@mock.RecvTimeout, @mock.Always)
  // count_slaves sends a BRD and needs to recv — should fail
  let result : Result[Int, @hal.EcError] = Ok(
    @protocol.count_slaves(fault_nic, @hal.Duration(1_000_000L)),
  ) catch {
    e => Err(e)
  }
  assert_true(result is Err(@hal.EcError::RecvTimeout))
}

///|
test "FaultInjector: SendFailure injection raises SendFailed" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x044C2C52,
    revision: 0x00120000,
    serial: 0x00000001,
  }
  let slave = @mock.VirtualSlave::new(0, identity, b"")
  let nic = @mock.VirtualNic::with_slaves([slave])
  let fault_nic = @mock.FaultNic::wrap(nic)
  fault_nic.injector.add(
    @mock.SendFailure("injected NIC failure"),
    @mock.Always,
  )
  let result : Result[Int, @hal.EcError] = Ok(
    @protocol.count_slaves(fault_nic, @hal.Duration(1_000_000L)),
  ) catch {
    e => Err(e)
  }
  assert_true(result is Err(@hal.EcError::SendFailed(_)))
}

///|
test "FaultInjector: WkcCorrupt modifies WKC in response" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x044C2C52,
    revision: 0x00120000,
    serial: 0x00000001,
  }
  let slave = @mock.VirtualSlave::new(0, identity, b"")
  let nic = @mock.VirtualNic::with_slaves([slave])
  let fault_nic = @mock.FaultNic::wrap(nic)
  // Corrupt WKC by subtracting 1 (WKC=1 from BRD → will become 0)
  fault_nic.injector.add(@mock.WkcCorrupt(delta=-1), @mock.Always)
  // BRD count_slaves expects WKC == slave_count; with WKC corrupted to 0,
  // it returns 0 instead of 1
  let count = @protocol.count_slaves(fault_nic, @hal.Duration(1_000_000L))
  assert_eq(count, 0)
}

///|
test "FaultInjector: FrameDrop causes RecvTimeout" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x044C2C52,
    revision: 0x00120000,
    serial: 0x00000001,
  }
  let slave = @mock.VirtualSlave::new(0, identity, b"")
  let nic = @mock.VirtualNic::with_slaves([slave])
  let fault_nic = @mock.FaultNic::wrap(nic)
  fault_nic.injector.add(@mock.FrameDrop, @mock.Once)
  // First call: frame dropped → RecvTimeout
  let result : Result[Int, @hal.EcError] = Ok(
    @protocol.count_slaves(fault_nic, @hal.Duration(1_000_000L)),
  ) catch {
    e => Err(e)
  }
  assert_true(result is Err(@hal.EcError::RecvTimeout))
  // Second call: fault was Once, should pass now
  let count = @protocol.count_slaves(fault_nic, @hal.Duration(1_000_000L))
  assert_eq(count, 1)
}

///|
test "FaultInjector: FrameCorrupt corrupts specific byte in response" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x044C2C52,
    revision: 0x00120000,
    serial: 0x00000001,
  }
  let slave = @mock.VirtualSlave::new(0, identity, b"")
  let nic = @mock.VirtualNic::with_slaves([slave])
  let fault_nic = @mock.FaultNic::wrap(nic)
  // Corrupt byte at offset 0 — will break frame decoding
  fault_nic.injector.add(
    @mock.FrameCorrupt(offset=0, value=b'\xFF'),
    @mock.Once,
  )
  // First call: corrupted frame, transact should either fail or return garbled data
  // depending on how frame decode handles it. Let's just check it doesn't crash.
  let result : Result[Int, @hal.EcError] = Ok(
    @protocol.count_slaves(fault_nic, @hal.Duration(1_000_000L)),
  ) catch {
    _ => Err(@hal.EcError::Internal("caught"))
  }
  // The corrupted frame will likely cause InvalidFrame or be silently ignored
  // After the single fault, the next call should succeed
  ignore(result)
  let count = @protocol.count_slaves(fault_nic, @hal.Duration(1_000_000L))
  assert_eq(count, 1)
}

///|
test "FaultInjector: total_fired tracks all fired faults" {
  let injector = @mock.FaultInjector::new()
  injector.add(@mock.RecvTimeout, @mock.CountDown(2))
  injector.add(@mock.FrameDrop, @mock.Once)
  // 3 recv checks
  let _ = injector.check_recv() // RecvTimeout fires
  let _ = injector.check_recv() // RecvTimeout fires (last countdown) + FrameDrop fires
  let _ = injector.check_recv() // nothing fires
  assert_eq(injector.total_fired(), 3)
}

///|
test "FaultInjector: reset re-enables all rules" {
  let injector = @mock.FaultInjector::new()
  injector.add(@mock.RecvTimeout, @mock.Once)
  let _ = injector.check_recv()
  assert_eq(injector.total_fired(), 1)
  injector.reset()
  assert_eq(injector.total_fired(), 0)
  let _ = injector.check_recv()
  assert_eq(injector.total_fired(), 1)
}

///|
test "FaultNic: multi-slave FMMU RecvTimeout — frame reaches slaves" {
  let id0 : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x044C2C52U,
    revision: 0x00120000U,
    serial: 0x00000001U,
  }
  let id1 : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x07D43052U,
    revision: 0x00100000U,
    serial: 0x00000000U,
  }
  let bus = @mock.VirtualBus::new([
    @mock.VirtualSlave::new(0, id0, b""),
    @mock.VirtualSlave::new(1, id1, b""),
  ])
  guard bus.get_slave(1) is Some(slave) else { fail("slave not found") }
  slave.write_reg(0x0010, Bytes::from_array([b'\x02', b'\x10'])) // 0x1002
  // FMMU0: write, logical 0x0000, 4 bytes, physical 0x1000
  let fmmu = FixedArray::make(16, b'\x00')
  fmmu[4] = b'\x04'
  fmmu[7] = b'\x07'
  fmmu[9] = b'\x10'
  fmmu[11] = b'\x02'
  fmmu[12] = b'\x01'
  slave.write_reg(0x0600, Bytes::makei(16, fn(i) { fmmu[i] }))
  // Wrap in FaultNic + inject RecvTimeout on first recv
  let nic = @mock.VirtualNic::new(bus)
  let fault_nic = @mock.FaultNic::wrap(nic)
  fault_nic.injector.add(@mock.RecvTimeout, @mock.Once)
  let timeout = @hal.Duration(50_000_000L)
  // LWR PDO — master fails but bus processed the frame
  let builder = @protocol.FrameBuilder::new()
  let pdo = Bytes::from_array([b'\xAA', b'\xBB', b'\xCC', b'\xDD'])
  let _ = builder.add(
    @protocol.EcCommand::LWR,
    @protocol.logical_address(0x0000U),
    pdo,
  )
  let result : Result[@protocol.EcFrame, @hal.EcError] = Ok(
    @protocol.transact(fault_nic, builder.build(), timeout),
  ) catch {
    e => Err(e)
  }
  assert_true(result is Err(@hal.EcError::RecvTimeout))
  // Frame DID reach slave (bus processed it despite master recv failure)
  assert_eq(slave.process_data[0x1000], b'\xAA')
  assert_eq(slave.process_data[0x1001], b'\xBB')
  assert_eq(slave.process_data[0x1002], b'\xCC')
  assert_eq(slave.process_data[0x1003], b'\xDD')
}

///|
test "FaultNic: multi-slave FMMU WKC corruption" {
  let id0 : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x044C2C52U,
    revision: 0x00120000U,
    serial: 0x00000001U,
  }
  let id1 : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x07D43052U,
    revision: 0x00100000U,
    serial: 0x00000000U,
  }
  let id2 : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x03F03052U,
    revision: 0x00100000U,
    serial: 0x00000000U,
  }
  let bus = @mock.VirtualBus::new([
    @mock.VirtualSlave::new(0, id0, b""),
    @mock.VirtualSlave::new(1, id1, b""),
    @mock.VirtualSlave::new(2, id2, b""),
  ])
  guard bus.get_slave(1) is Some(s1) else { fail("slave 1 not found") }
  guard bus.get_slave(2) is Some(s2) else { fail("slave 2 not found") }
  s1.write_reg(0x0010, Bytes::from_array([b'\x02', b'\x10']))
  s2.write_reg(0x0010, Bytes::from_array([b'\x03', b'\x10']))
  // FMMU on s1: write, logical 0x0000, 4 bytes, physical 0x1000
  let fmmu1 = FixedArray::make(16, b'\x00')
  fmmu1[4] = b'\x04'
  fmmu1[7] = b'\x07'
  fmmu1[9] = b'\x10'
  fmmu1[11] = b'\x02'
  fmmu1[12] = b'\x01'
  s1.write_reg(0x0600, Bytes::makei(16, fn(i) { fmmu1[i] }))
  // FMMU on s2: read, logical 0x0004, 2 bytes, physical 0x1000
  let fmmu2 = FixedArray::make(16, b'\x00')
  fmmu2[0] = b'\x04'
  fmmu2[4] = b'\x02'
  fmmu2[7] = b'\x07'
  fmmu2[9] = b'\x10'
  fmmu2[11] = b'\x01'
  fmmu2[12] = b'\x01'
  s2.write_reg(0x0600, Bytes::makei(16, fn(i) { fmmu2[i] }))
  s2.process_data[0x1000] = b'\xFF'
  s2.process_data[0x1001] = b'\x0F'
  // Wrap in FaultNic with WKC corruption
  let nic = @mock.VirtualNic::new(bus)
  let fault_nic = @mock.FaultNic::wrap(nic)
  fault_nic.injector.add(@mock.WkcCorrupt(delta=-1), @mock.Always)
  let timeout = @hal.Duration(50_000_000L)
  // LRW: expect WKC=2 (1 write + 1 read) but corrupted to 1
  let builder = @protocol.FrameBuilder::new()
  let pdo = Bytes::from_array([
    b'\x11', b'\x22', b'\x33', b'\x44', b'\x00', b'\x00',
  ])
  let _ = builder.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    pdo,
  )
  let response = @protocol.transact(fault_nic, builder.build(), timeout)
  // WKC corrupted: 2 - 1 = 1
  assert_eq(response.pdus[0].wkc, 1U)
  // But data exchange still happened correctly
  assert_eq(s1.process_data[0x1000], b'\x11')
  assert_eq(response.pdus[0].data[4], b'\xFF')
}

///|
test "FaultNic: multi-slave CountDown recv fault then PDO recovery" {
  let id0 : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x044C2C52U,
    revision: 0x00120000U,
    serial: 0x00000001U,
  }
  let id1 : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x07D43052U,
    revision: 0x00100000U,
    serial: 0x00000000U,
  }
  let bus = @mock.VirtualBus::new([
    @mock.VirtualSlave::new(0, id0, b""),
    @mock.VirtualSlave::new(1, id1, b""),
  ])
  guard bus.get_slave(1) is Some(slave) else { fail("slave not found") }
  slave.write_reg(0x0010, Bytes::from_array([b'\x02', b'\x10'])) // 0x1002
  // FMMU0: write, logical 0x0000, 4 bytes, physical 0x1000
  let fmmu = FixedArray::make(16, b'\x00')
  fmmu[4] = b'\x04'
  fmmu[7] = b'\x07'
  fmmu[9] = b'\x10'
  fmmu[11] = b'\x02'
  fmmu[12] = b'\x01'
  slave.write_reg(0x0600, Bytes::makei(16, fn(i) { fmmu[i] }))
  // Wrap in FaultNic with CountDown(3) RecvTimeout
  let nic = @mock.VirtualNic::new(bus)
  let fault_nic = @mock.FaultNic::wrap(nic)
  fault_nic.injector.add(@mock.RecvTimeout, @mock.CountDown(3))
  let timeout = @hal.Duration(50_000_000L)
  // First 3 PDO attempts fail
  for _i = 0; _i < 3; _i = _i + 1 {
    let builder = @protocol.FrameBuilder::new()
    let pdo = Bytes::from_array([b'\xAA', b'\xBB', b'\xCC', b'\xDD'])
    let _ = builder.add(
      @protocol.EcCommand::LWR,
      @protocol.logical_address(0x0000U),
      pdo,
    )
    let result : Result[@protocol.EcFrame, @hal.EcError] = Ok(
      @protocol.transact(fault_nic, builder.build(), timeout),
    ) catch {
      e => Err(e)
    }
    assert_true(result is Err(@hal.EcError::RecvTimeout))
  }
  assert_eq(fault_nic.injector.total_fired(), 3)
  // 4th attempt succeeds (fault exhausted)
  let builder = @protocol.FrameBuilder::new()
  let pdo = Bytes::from_array([b'\xAA', b'\xBB', b'\xCC', b'\xDD'])
  let _ = builder.add(
    @protocol.EcCommand::LWR,
    @protocol.logical_address(0x0000U),
    pdo,
  )
  let response = @protocol.transact(fault_nic, builder.build(), timeout)
  assert_eq(response.pdus[0].wkc, 1U)
  // Data arrived at slave
  assert_eq(slave.process_data[0x1000], b'\xAA')
  assert_eq(slave.process_data[0x1001], b'\xBB')
  assert_eq(slave.process_data[0x1002], b'\xCC')
  assert_eq(slave.process_data[0x1003], b'\xDD')
}
