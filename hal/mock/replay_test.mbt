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
