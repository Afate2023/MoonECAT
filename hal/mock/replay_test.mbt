///|
test "record and replay count_slaves produces identical result" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x044C2C52,
    revision: 0x00120000,
    serial: 0x00000001,
  }
  let slave = @mock.VirtualSlave::new(0, identity, b"")
  let nic = @mock.VirtualNic::with_slaves([slave])
  let recording = @mock.RecordingNic::wrap(nic)
  let count1 = @protocol.count_slaves(recording, @hal.Duration(1_000_000L))
  let log = recording.get_log()
  assert_true(log.len() > 0)
  // Replay the recorded session
  let replay = @mock.ReplayNic::from_log(log)
  let count2 = @protocol.count_slaves(replay, @hal.Duration(1_000_000L))
  assert_eq(count1, count2)
  assert_true(replay.is_exhausted())
}

///|
test "record and replay multi-slave discovery" {
  let id1 : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x044C2C52,
    revision: 0x00120000,
    serial: 0x00000001,
  }
  let id2 : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x04562C52,
    revision: 0x00120000,
    serial: 0x00000002,
  }
  let slaves = [
    @mock.VirtualSlave::new(0, id1, b""),
    @mock.VirtualSlave::new(0, id2, b""),
  ]
  let nic = @mock.VirtualNic::with_slaves(slaves)
  let recording = @mock.RecordingNic::wrap(nic)
  let count1 = @protocol.count_slaves(recording, @hal.Duration(1_000_000L))
  assert_eq(count1, 2)
  let log = recording.get_log()
  let replay = @mock.ReplayNic::from_log(log)
  let count2 = @protocol.count_slaves(replay, @hal.Duration(1_000_000L))
  assert_eq(count2, 2)
  assert_true(replay.is_exhausted())
}

///|
test "recorded log captures send+recv pairs" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x044C2C52,
    revision: 0x00120000,
    serial: 0x00000001,
  }
  let slave = @mock.VirtualSlave::new(0, identity, b"")
  let nic = @mock.VirtualNic::with_slaves([slave])
  let recording = @mock.RecordingNic::wrap(nic)
  let _ = @protocol.count_slaves(recording, @hal.Duration(1_000_000L))
  let log = recording.get_log()
  // count_slaves does one BRD transact: send + recv = 2 events
  assert_eq(log.len(), 2)
  assert_true(log.events[0] is @mock.Sent(_, _))
  assert_true(log.events[1] is @mock.Received(_))
}

///|
test "replay exhausted log raises error on send" {
  let log = @mock.NicEventLog::new()
  let replay = @mock.ReplayNic::from_log(log)
  assert_true(replay.is_exhausted())
  let result : Result[Int, @hal.EcError] = Ok(replay.send(b"\x00")) catch {
    e => Err(e)
  }
  assert_true(result is Err(@hal.EcError::SendFailed(_)))
}

///|
test "replay exhausted log raises RecvTimeout on recv" {
  let log = @mock.NicEventLog::new()
  let replay = @mock.ReplayNic::from_log(log)
  let result : Result[Bytes, @hal.EcError] = Ok(
    replay.recv(timeout=@hal.Duration(1_000_000L)),
  ) catch {
    e => Err(e)
  }
  assert_true(result is Err(@hal.EcError::RecvTimeout))
}

///|
test "replay remaining tracks cursor position" {
  let log = @mock.NicEventLog::new()
  log.append(@mock.Sent(b"\x01\x02", 2))
  log.append(@mock.Received(b"\x03\x04"))
  let replay = @mock.ReplayNic::from_log(log)
  assert_eq(replay.remaining(), 2)
  let _ = replay.send(b"\x01\x02")
  assert_eq(replay.remaining(), 1)
  let _ = replay.recv(timeout=@hal.Duration(1_000_000L))
  assert_eq(replay.remaining(), 0)
  assert_true(replay.is_exhausted())
}

///|
test "replay RecvTimeout event raises RecvTimeout" {
  let log = @mock.NicEventLog::new()
  log.append(@mock.Sent(b"\x01", 1))
  log.append(@mock.RecvTimeout)
  let replay = @mock.ReplayNic::from_log(log)
  let _ = replay.send(b"\x01")
  let result : Result[Bytes, @hal.EcError] = Ok(
    replay.recv(timeout=@hal.Duration(1_000_000L)),
  ) catch {
    e => Err(e)
  }
  assert_true(result is Err(@hal.EcError::RecvTimeout))
  assert_true(replay.is_exhausted())
}

///|
test "replay SendFailed event raises SendFailed" {
  let log = @mock.NicEventLog::new()
  log.append(@mock.SendFailed("injected"))
  let replay = @mock.ReplayNic::from_log(log)
  let result : Result[Int, @hal.EcError] = Ok(replay.send(b"\x01")) catch {
    e => Err(e)
  }
  assert_true(result is Err(@hal.EcError::SendFailed(_)))
  assert_true(replay.is_exhausted())
}

///|
test "record fault then replay reproduces fault" {
  let identity : @hal.SlaveIdentity = {
    vendor_id: 0x02,
    product_code: 0x044C2C52,
    revision: 0x00120000,
    serial: 0x00000001,
  }
  let slave = @mock.VirtualSlave::new(0, identity, b"")
  let nic = @mock.VirtualNic::with_slaves([slave])
  // Record through a FaultNic that will timeout on recv
  let fault_nic = @mock.FaultNic::wrap(nic)
  fault_nic.injector.add(@mock.RecvTimeout, @mock.Always)
  // Wrap the FaultNic in a recording layer
  // We can't directly wrap FaultNic, so record manually
  let log = @mock.NicEventLog::new()
  // Simulate what would happen: send succeeds, recv times out
  let send_data = @protocol.EcFrame::{
    dst_mac: [b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF'],
    src_mac: [b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00'],
    pdus: [],
  }.encode()
  log.append(@mock.Sent(send_data, send_data.length()))
  log.append(@mock.RecvTimeout)
  // Replay the fault session
  let replay = @mock.ReplayNic::from_log(log)
  let result : Result[Int, @hal.EcError] = Ok(
    @protocol.count_slaves(replay, @hal.Duration(1_000_000L)),
  ) catch {
    e => Err(e)
  }
  assert_true(result is Err(@hal.EcError::RecvTimeout))
}

///|
test "NicEventLog::new creates empty log" {
  let log = @mock.NicEventLog::new()
  assert_eq(log.len(), 0)
}

///|
test "record and replay multi-slave FMMU PDO exchange" {
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
  // Direct slave setup: station addresses and FMMUs
  guard bus.get_slave(1) is Some(s1) else { fail("slave 1 not found") }
  guard bus.get_slave(2) is Some(s2) else { fail("slave 2 not found") }
  s1.write_reg(0x0010, Bytes::from_array([b'\x02', b'\x10'])) // 0x1002
  s2.write_reg(0x0010, Bytes::from_array([b'\x03', b'\x10'])) // 0x1003
  // FMMU0 on s1: outputs, logical 0x0000, 4 bytes, physical 0x1000, write
  let fmmu_out = FixedArray::make(16, b'\x00')
  fmmu_out[4] = b'\x04' // length
  fmmu_out[7] = b'\x07'
  fmmu_out[9] = b'\x10' // physical = 0x1000
  fmmu_out[11] = b'\x02' // write
  fmmu_out[12] = b'\x01' // activate
  s1.write_reg(0x0600, Bytes::makei(16, fn(i) { fmmu_out[i] }))
  // FMMU0 on s2: inputs, logical 0x0004, 2 bytes, physical 0x1000, read
  let fmmu_in = FixedArray::make(16, b'\x00')
  fmmu_in[0] = b'\x04' // logical start = 0x0004
  fmmu_in[4] = b'\x02' // length
  fmmu_in[7] = b'\x07'
  fmmu_in[9] = b'\x10' // physical = 0x1000
  fmmu_in[11] = b'\x01' // read
  fmmu_in[12] = b'\x01'
  s2.write_reg(0x0600, Bytes::makei(16, fn(i) { fmmu_in[i] }))
  // Pre-populate input data
  s2.process_data[0x1000] = b'\xAB'
  s2.process_data[0x1001] = b'\xCD'
  // Record PDO exchange
  let nic = @mock.VirtualNic::new(bus)
  let recording = @mock.RecordingNic::wrap(nic)
  let timeout = @hal.Duration(50_000_000L)
  let builder = @protocol.FrameBuilder::new()
  let pdo = Bytes::from_array([
    b'\x11', b'\x22', b'\x33', b'\x44', b'\x00', b'\x00',
  ])
  let _ = builder.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    pdo,
  )
  let response1 = @protocol.transact(recording, builder.build(), timeout)
  assert_eq(response1.pdus[0].wkc, 2U)
  assert_eq(response1.pdus[0].data[4], b'\xAB')
  assert_eq(response1.pdus[0].data[5], b'\xCD')
  // Replay
  let log = recording.get_log()
  assert_eq(log.len(), 2)
  let replay = @mock.ReplayNic::from_log(log)
  let builder2 = @protocol.FrameBuilder::new()
  let pdo2 = Bytes::from_array([
    b'\x11', b'\x22', b'\x33', b'\x44', b'\x00', b'\x00',
  ])
  let _ = builder2.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    pdo2,
  )
  let response2 = @protocol.transact(replay, builder2.build(), timeout)
  assert_eq(response1.pdus[0].wkc, response2.pdus[0].wkc)
  assert_eq(response2.pdus[0].data[4], b'\xAB')
  assert_eq(response2.pdus[0].data[5], b'\xCD')
  assert_true(replay.is_exhausted())
}

///|
test "record and replay multi-cycle PDO with changing inputs" {
  let id_out : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x07D43052U,
    revision: 0x00100000U,
    serial: 0x00000000U,
  }
  let id_in : @hal.SlaveIdentity = {
    vendor_id: 0x02U,
    product_code: 0x03F03052U,
    revision: 0x00100000U,
    serial: 0x00000000U,
  }
  let bus = @mock.VirtualBus::new([
    @mock.VirtualSlave::new(0, id_out, b""),
    @mock.VirtualSlave::new(1, id_in, b""),
  ])
  guard bus.get_slave(0) is Some(s_out) else { fail("output slave not found") }
  guard bus.get_slave(1) is Some(s_in) else { fail("input slave not found") }
  s_out.write_reg(0x0010, Bytes::from_array([b'\x01', b'\x10'])) // 0x1001
  s_in.write_reg(0x0010, Bytes::from_array([b'\x02', b'\x10'])) // 0x1002
  // FMMU on output: logical 0x0000, 2 bytes, physical 0x1000, write
  let fmmu_o = FixedArray::make(16, b'\x00')
  fmmu_o[4] = b'\x02'
  fmmu_o[7] = b'\x07'
  fmmu_o[9] = b'\x10'
  fmmu_o[11] = b'\x02'
  fmmu_o[12] = b'\x01'
  s_out.write_reg(0x0600, Bytes::makei(16, fn(i) { fmmu_o[i] }))
  // FMMU on input: logical 0x0002, 2 bytes, physical 0x1000, read
  let fmmu_i = FixedArray::make(16, b'\x00')
  fmmu_i[0] = b'\x02' // logical start = 0x0002
  fmmu_i[4] = b'\x02'
  fmmu_i[7] = b'\x07'
  fmmu_i[9] = b'\x10'
  fmmu_i[11] = b'\x01'
  fmmu_i[12] = b'\x01'
  s_in.write_reg(0x0600, Bytes::makei(16, fn(i) { fmmu_i[i] }))
  // Record 3 PDO cycles with changing inputs
  let nic = @mock.VirtualNic::new(bus)
  let recording = @mock.RecordingNic::wrap(nic)
  let timeout = @hal.Duration(50_000_000L)
  // Cycle 1: inputs = 0xAB 0xCD
  s_in.process_data[0x1000] = b'\xAB'
  s_in.process_data[0x1001] = b'\xCD'
  let b1 = @protocol.FrameBuilder::new()
  let _ = b1.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    Bytes::from_array([b'\x11', b'\x22', b'\x00', b'\x00']),
  )
  let r1 = @protocol.transact(recording, b1.build(), timeout)
  assert_eq(r1.pdus[0].data[2], b'\xAB')
  assert_eq(r1.pdus[0].data[3], b'\xCD')
  // Cycle 2: inputs change to 0x55 0xAA
  s_in.process_data[0x1000] = b'\x55'
  s_in.process_data[0x1001] = b'\xAA'
  let b2 = @protocol.FrameBuilder::new()
  let _ = b2.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    Bytes::from_array([b'\x33', b'\x44', b'\x00', b'\x00']),
  )
  let r2 = @protocol.transact(recording, b2.build(), timeout)
  assert_eq(r2.pdus[0].data[2], b'\x55')
  assert_eq(r2.pdus[0].data[3], b'\xAA')
  // Cycle 3: inputs change again
  s_in.process_data[0x1000] = b'\xDE'
  s_in.process_data[0x1001] = b'\xAD'
  let b3 = @protocol.FrameBuilder::new()
  let _ = b3.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    Bytes::from_array([b'\x55', b'\x66', b'\x00', b'\x00']),
  )
  let r3 = @protocol.transact(recording, b3.build(), timeout)
  assert_eq(r3.pdus[0].data[2], b'\xDE')
  assert_eq(r3.pdus[0].data[3], b'\xAD')
  // Replay all 3 cycles
  let log = recording.get_log()
  assert_eq(log.len(), 6) // 3 cycles * (send + recv)
  let replay = @mock.ReplayNic::from_log(log)
  // Replay cycle 1
  let rb1 = @protocol.FrameBuilder::new()
  let _ = rb1.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    Bytes::from_array([b'\x11', b'\x22', b'\x00', b'\x00']),
  )
  let rr1 = @protocol.transact(replay, rb1.build(), timeout)
  assert_eq(rr1.pdus[0].data[2], b'\xAB')
  assert_eq(rr1.pdus[0].data[3], b'\xCD')
  // Replay cycle 2
  let rb2 = @protocol.FrameBuilder::new()
  let _ = rb2.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    Bytes::from_array([b'\x33', b'\x44', b'\x00', b'\x00']),
  )
  let rr2 = @protocol.transact(replay, rb2.build(), timeout)
  assert_eq(rr2.pdus[0].data[2], b'\x55')
  assert_eq(rr2.pdus[0].data[3], b'\xAA')
  // Replay cycle 3
  let rb3 = @protocol.FrameBuilder::new()
  let _ = rb3.add(
    @protocol.EcCommand::LRW,
    @protocol.logical_address(0x0000U),
    Bytes::from_array([b'\x55', b'\x66', b'\x00', b'\x00']),
  )
  let rr3 = @protocol.transact(replay, rb3.build(), timeout)
  assert_eq(rr3.pdus[0].data[2], b'\xDE')
  assert_eq(rr3.pdus[0].data[3], b'\xAD')
  assert_true(replay.is_exhausted())
}
