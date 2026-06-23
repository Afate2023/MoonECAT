///|
test "EcError variants display correctly" {
  @debug.debug_inspect(@hal.EcError::LinkDown, content="LinkDown")
  @debug.debug_inspect(
    @hal.EcError::SendFailed("test"),
    content="SendFailed(\"test\")",
  )
  @debug.debug_inspect(@hal.EcError::RecvTimeout, content="RecvTimeout")
}

///|
test "Duration and Timestamp construct correctly" {
  let ts = @hal.Timestamp(1000L)
  let dur = @hal.Duration(500L)
  @debug.debug_inspect(ts, content="Timestamp(1000)")
  @debug.debug_inspect(dur, content="Duration(500)")
}

///|
test "MasterConfig default values" {
  let cfg = @hal.MasterConfig::default()
  @debug.assert_eq(cfg.interface_name, "eth0")
  @debug.assert_eq(cfg.cycle_period_ns, 1_000_000L)
  @debug.assert_eq(cfg.max_retries, 3)
  @debug.assert_eq(cfg.dc_enabled, false)
}

///|
test "DiagnosticEvent construction" {
  let evt = @hal.DiagnosticEvent::new(
    @hal.Timestamp(100L),
    @hal.Severity::Info,
    "hal",
    "link up",
  )
  @debug.assert_eq(evt.severity, @hal.Severity::Info)
  @debug.assert_eq(evt.source, "hal")
  @debug.assert_eq(evt.message, "link up")
}

///|
test "SlaveIdentity equality" {
  let id1 : @hal.SlaveIdentity = {
    vendor_id: 0x2U,
    product_code: 0x1U,
    revision: 0x0U,
    serial: 0x0U,
  }
  let id2 : @hal.SlaveIdentity = {
    vendor_id: 0x2U,
    product_code: 0x1U,
    revision: 0x0U,
    serial: 0x0U,
  }
  @debug.assert_eq(id1, id2)
}

// ── FramePool Tests ──

///|
test "FramePool::new creates pool with correct capacity" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  @debug.assert_eq(pool.capacity, 4)
  @debug.assert_eq(pool.frame_size, 64)
  @debug.assert_eq(pool.free_count(), 4)
}

///|
test "FramePool::acquire returns valid FrameRef" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  let fref = pool.acquire()
  assert_true(fref.slot >= 0 && fref.slot < 4)
  @debug.assert_eq(pool.state(fref), @hal.Acquired)
  @debug.assert_eq(pool.free_count(), 3)
}

///|
test "FramePool::acquire round-robin allocation" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  let f0 = pool.acquire()
  let f1 = pool.acquire()
  let f2 = pool.acquire()
  @debug.assert_eq(f0.slot, 0)
  @debug.assert_eq(f1.slot, 1)
  @debug.assert_eq(f2.slot, 2)
}

///|
test "FramePool::acquire exhaustion raises error" {
  let pool = @hal.FramePool::new(capacity=2, frame_size=64)
  let _ = pool.acquire()
  let _ = pool.acquire()
  let result = Result::Ok(pool.acquire()) catch { err => Result::Err(err) }
  assert_true(result is Err(_))
}

///|
test "FramePool::release makes slot available again" {
  let pool = @hal.FramePool::new(capacity=1, frame_size=64)
  let fref = pool.acquire()
  @debug.assert_eq(pool.free_count(), 0)
  pool.release(fref)
  @debug.assert_eq(pool.free_count(), 1)
  let fref2 = pool.acquire()
  @debug.assert_eq(fref2.slot, fref.slot)
}

///|
test "FramePool state transitions TX" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  let fref = pool.acquire()
  @debug.assert_eq(pool.state(fref), @hal.Acquired)
  let fref2 = pool.mark_filled(fref, 42)
  @debug.assert_eq(pool.state(fref2), @hal.Filled)
  @debug.assert_eq(pool.data_length(fref2), 42)
  pool.mark_sending(fref2)
  @debug.assert_eq(pool.state(fref2), @hal.Sending)
  pool.mark_sent(fref2)
  @debug.assert_eq(pool.state(fref2), @hal.Sent)
  pool.release(fref2)
  @debug.assert_eq(pool.state(fref2), @hal.Free)
}

///|
test "FramePool::acquire_rx sets Receiving state" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  let rx = pool.acquire_rx()
  @debug.assert_eq(pool.state(rx), @hal.Receiving)
}

///|
test "FramePool::mark_received sets Received state with length" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  let rx = pool.acquire_rx()
  let rx2 = pool.mark_received(rx, 100)
  @debug.assert_eq(pool.state(rx2), @hal.Received)
  @debug.assert_eq(rx2.length, 100)
  @debug.assert_eq(pool.data_length(rx2), 100)
}

///|
test "FramePool::reset clears all slots" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  let _ = pool.acquire()
  let _ = pool.acquire()
  let _ = pool.acquire()
  @debug.assert_eq(pool.free_count(), 1)
  pool.reset()
  @debug.assert_eq(pool.free_count(), 4)
}

// ── Buffer Read/Write Tests ──

///|
test "FramePool write_byte and read_byte" {
  let pool = @hal.FramePool::new(capacity=1, frame_size=64)
  let fref = pool.acquire()
  pool.write_byte(fref, 0, b'\xAA')
  pool.write_byte(fref, 1, b'\xBB')
  @debug.assert_eq(pool.read_byte(fref, 0), b'\xAA')
  @debug.assert_eq(pool.read_byte(fref, 1), b'\xBB')
}

///|
test "FramePool write_u16_le and read_u16_le" {
  let pool = @hal.FramePool::new(capacity=1, frame_size=64)
  let fref = pool.acquire()
  pool.write_u16_le(fref, 0, 0x1234)
  @debug.assert_eq(pool.read_u16_le(fref, 0), 0x1234)
  // Little-endian byte order
  @debug.assert_eq(pool.read_byte(fref, 0), b'\x34')
  @debug.assert_eq(pool.read_byte(fref, 1), b'\x12')
}

///|
test "FramePool write_u32_le and read_u32_le" {
  let pool = @hal.FramePool::new(capacity=1, frame_size=64)
  let fref = pool.acquire()
  pool.write_u32_le(fref, 0, 0x12345678)
  @debug.assert_eq(pool.read_u32_le(fref, 0), 0x12345678)
  @debug.assert_eq(pool.read_byte(fref, 0), b'\x78')
  @debug.assert_eq(pool.read_byte(fref, 3), b'\x12')
}

///|
test "FramePool write_bytes and read_bytes" {
  let pool = @hal.FramePool::new(capacity=1, frame_size=64)
  let fref = pool.acquire()
  let src : FixedArray[Byte] = [b'\x01', b'\x02', b'\x03', b'\x04']
  pool.write_bytes(fref, 10, src, 0, 4)
  let dst : FixedArray[Byte] = FixedArray::make(4, b'\x00')
  pool.read_bytes(fref, 10, dst, 0, 4)
  @debug.assert_eq(dst[0], b'\x01')
  @debug.assert_eq(dst[1], b'\x02')
  @debug.assert_eq(dst[2], b'\x03')
  @debug.assert_eq(dst[3], b'\x04')
}

///|
test "FramePool buffer returns writable array" {
  let pool = @hal.FramePool::new(capacity=1, frame_size=64)
  let fref = pool.acquire()
  let buf = pool.buffer(fref)
  buf[0] = b'\xFF'
  buf[63] = b'\xAA'
  @debug.assert_eq(pool.read_byte(fref, 0), b'\xFF')
  @debug.assert_eq(pool.read_byte(fref, 63), b'\xAA')
}

// ── FrameRef Tests ──

///|
test "FrameRef is a pure value type" {
  let fref : @hal.FrameRef = { pool_id: 0, slot: 3, offset: 14, length: 100 }
  @debug.assert_eq(fref.pool_id, 0)
  @debug.assert_eq(fref.slot, 3)
  @debug.assert_eq(fref.offset, 14)
  @debug.assert_eq(fref.length, 100)
}

///|
test "FrameRef update via struct spread" {
  let fref : @hal.FrameRef = { pool_id: 0, slot: 1, offset: 0, length: 0 }
  let updated : @hal.FrameRef = { ..fref, length: 42 }
  @debug.assert_eq(updated.slot, 1)
  @debug.assert_eq(updated.length, 42)
}

// ── MutableProcessImage Tests ──

///|
test "MutableProcessImage::new creates zeroed buffers" {
  let mpi = @hal.MutableProcessImage::new(8, 16)
  @debug.assert_eq(mpi.output_size, 8)
  @debug.assert_eq(mpi.input_size, 16)
  for i = 0; i < 8; i = i + 1 {
    @debug.assert_eq(mpi.outputs[i], b'\x00')
  }
  for i = 0; i < 16; i = i + 1 {
    @debug.assert_eq(mpi.inputs[i], b'\x00')
  }
}

///|
test "MutableProcessImage in-place write and read" {
  let mpi = @hal.MutableProcessImage::new(4, 4)
  mpi.outputs[0] = b'\xFF'
  mpi.outputs[1] = b'\x80'
  @debug.assert_eq(mpi.outputs[0], b'\xFF')
  @debug.assert_eq(mpi.outputs[1], b'\x80')
  mpi.inputs[0] = b'\x01'
  mpi.inputs[3] = b'\xFE'
  @debug.assert_eq(mpi.inputs[0], b'\x01')
  @debug.assert_eq(mpi.inputs[3], b'\xFE')
}

///|
test "MutableProcessImage::clear_inputs zeroes buffer" {
  let mpi = @hal.MutableProcessImage::new(4, 4)
  mpi.inputs[0] = b'\xFF'
  mpi.inputs[3] = b'\xAA'
  mpi.clear_inputs()
  for i = 0; i < 4; i = i + 1 {
    @debug.assert_eq(mpi.inputs[i], b'\x00')
  }
}

// ── Stress Tests ──

///|
test "FramePool acquire/release cycle x100" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=64)
  for i = 0; i < 100; i = i + 1 {
    let f = pool.acquire()
    pool.write_byte(f, 0, (i % 256).to_byte())
    let filled = pool.mark_filled(f, 1)
    pool.mark_sending(filled)
    pool.mark_sent(filled)
    pool.release(filled)
  }
  @debug.assert_eq(pool.free_count(), 4)
}

///|
test "FramePool full pipeline TX+RX simulation" {
  let pool = @hal.FramePool::new(capacity=8, frame_size=64)
  for cycle = 0; cycle < 50; cycle = cycle + 1 {
    // TX path
    let tx = pool.acquire()
    let tx_buf = pool.buffer(tx)
    tx_buf[0] = (cycle & 0xFF).to_byte()
    let filled = pool.mark_filled(tx, 1)
    pool.mark_sending(filled)
    pool.mark_sent(filled)
    pool.release(filled)
    // RX path
    let rx = pool.acquire_rx()
    let rx_buf = pool.buffer(rx)
    rx_buf[0] = (cycle & 0xFF).to_byte()
    let received = pool.mark_received(rx, 1)
    @debug.assert_eq(pool.buffer(received)[0], (cycle & 0xFF).to_byte())
    pool.release(received)
  }
  @debug.assert_eq(pool.free_count(), 8)
}

///|
test "FramePool build EtherCAT-like frame in-place" {
  let pool = @hal.FramePool::new(capacity=4, frame_size=@hal.max_frame_size)
  let fref = pool.acquire()
  let buf = pool.buffer(fref)
  // Ethernet header
  for i = 0; i < 6; i = i + 1 {
    buf[i] = b'\xFF' // dst broadcast
    buf[6 + i] = b'\x00' // src zeros
  }
  buf[12] = b'\x88'
  buf[13] = b'\xA4'
  // EtherCAT header
  pool.write_u16_le(fref, 14, 0x1001)
  @debug.assert_eq(buf[12], b'\x88')
  @debug.assert_eq(buf[13], b'\xA4')
  @debug.assert_eq(pool.read_u16_le(fref, 14), 0x1001)
  let filled = pool.mark_filled(fref, 16)
  @debug.assert_eq(filled.length, 16)
  @debug.assert_eq(pool.state(filled), @hal.Filled)
  pool.release(filled)
}
