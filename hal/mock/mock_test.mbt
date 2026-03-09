///|
test "MockNic send and recv roundtrip" {
  let nic = @mock.MockNic::new()
  let frame = Bytes::from_array([b'\x01', b'\x02', b'\x03'])
  let sent = nic.send(frame)
  assert_eq(sent, 3)
  let received = nic.recv(timeout=@hal.Duration(1000L))
  assert_eq(received, frame)
}

///|
test "MockNic recv on empty buffer raises RecvTimeout" {
  let nic = @mock.MockNic::new()
  let result = try? nic.recv(timeout=@hal.Duration(1000L))
  inspect(result, content="Err(RecvTimeout)")
}

///|
test "MockClock advance and now" {
  let clock = @mock.MockClock::new()
  assert_eq(clock.now(), @hal.Timestamp(0L))
  clock.advance(5000L)
  assert_eq(clock.now(), @hal.Timestamp(5000L))
  clock.sleep(@hal.Duration(3000L))
  assert_eq(clock.now(), @hal.Timestamp(8000L))
}
