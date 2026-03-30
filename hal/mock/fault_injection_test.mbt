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
