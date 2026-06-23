///|
test "MockNic send and recv roundtrip" {
  let nic = @mock.MockNic::new()
  let frame = Bytes::from_array([b'\x01', b'\x02', b'\x03'])
  let sent = nic.send(frame)
  @debug.assert_eq(sent, 3)
  let received = nic.recv(timeout=@hal.Duration(1000L))
  @debug.assert_eq(received, frame)
}

///|
test "MockNic recv on empty buffer raises RecvTimeout" {
  let nic = @mock.MockNic::new()
  let result = Result::Ok(nic.recv(timeout=@hal.Duration(1000L))) catch {
    err => Result::Err(err)
  }
  @debug.debug_inspect(result, content="Err(RecvTimeout)")
}

///|
test "MockClock advance and now" {
  let clock = @mock.MockClock::new()
  @debug.assert_eq(clock.now(), @hal.Timestamp(0L))
  clock.advance(5000L)
  @debug.assert_eq(clock.now(), @hal.Timestamp(5000L))
  clock.sleep(@hal.Duration(3000L))
  @debug.assert_eq(clock.now(), @hal.Timestamp(8000L))
}

// ── MockZeroCopyNic Tests ──

///|
test "MockZeroCopyNic loopback: send then recv" {
  let pool = @hal.FramePool::new(capacity=8, frame_size=64)
  let nic = @mock.MockZeroCopyNic::new(pool)
  let tx_ref = nic.acquire_tx()
  let tx_buf = nic.tx_buffer(tx_ref)
  tx_buf[0] = b'\xAA'
  tx_buf[1] = b'\xBB'
  tx_buf[2] = b'\xCC'
  nic.submit(tx_ref, length=3)
  let rx_ref = nic.recv(timeout=@hal.Duration(50_000_000L))
  let rx_buf = nic.rx_buffer(rx_ref)
  let rx_len = nic.rx_length(rx_ref)
  @debug.assert_eq(rx_len, 3)
  @debug.assert_eq(rx_buf[0], b'\xAA')
  @debug.assert_eq(rx_buf[1], b'\xBB')
  @debug.assert_eq(rx_buf[2], b'\xCC')
  nic.release(rx_ref)
}

///|
test "MockZeroCopyNic recv timeout when no data" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  let nic = @mock.MockZeroCopyNic::new(pool)
  let result = Result::Ok(nic.recv(timeout=@hal.Duration(1_000_000L))) catch {
    err => Result::Err(err)
  }
  assert_true(result is Err(_))
}

///|
test "MockZeroCopyNic multiple send/recv in order" {
  let pool = @hal.FramePool::new(capacity=16, frame_size=64)
  let nic = @mock.MockZeroCopyNic::new(pool)
  for i = 0; i < 3; i = i + 1 {
    let tx = nic.acquire_tx()
    let buf = nic.tx_buffer(tx)
    buf[0] = (i + 1).to_byte()
    nic.submit(tx, length=1)
  }
  for i = 0; i < 3; i = i + 1 {
    let rx = nic.recv(timeout=@hal.Duration(1_000_000L))
    let buf = nic.rx_buffer(rx)
    @debug.assert_eq(buf[0], (i + 1).to_byte())
    nic.release(rx)
  }
}

///|
test "MockZeroCopyNic close resets pool" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  let nic = @mock.MockZeroCopyNic::new(pool)
  let _ = nic.acquire_tx()
  @debug.assert_eq(pool.free_count(), 3)
  nic.close()
  @debug.assert_eq(pool.free_count(), 4)
}
