///|
/// MockZeroCopyNic is a test backend implementing ZeroCopyNic.
/// It uses a FramePool for pre-allocated buffer management and
/// supports loopback (echoes sent frames back on recv).
pub(all) struct MockZeroCopyNic {
  pool : @hal.FramePool
  /// Queue of pending received frames (slot indices)
  mut rx_queue : FixedArray[Int]
  mut rx_head : Int
  mut rx_tail : Int
  mut rx_count : Int
  rx_capacity : Int
  mut is_open : Bool
}

///|
let mock_rx_queue_size : Int = 32

///|
pub fn MockZeroCopyNic::new(pool : @hal.FramePool) -> MockZeroCopyNic {
  {
    pool,
    rx_queue: FixedArray::make(mock_rx_queue_size, 0),
    rx_head: 0,
    rx_tail: 0,
    rx_count: 0,
    rx_capacity: mock_rx_queue_size,
    is_open: false,
  }
}

///|
pub impl @hal.ZeroCopyNic for MockZeroCopyNic with open_(
  _name : String,
  pool : @hal.FramePool,
) -> MockZeroCopyNic raise @hal.EcError {
  MockZeroCopyNic::new(pool)
}

///|
pub impl @hal.ZeroCopyNic for MockZeroCopyNic with acquire_tx(
  self : MockZeroCopyNic,
) -> @hal.FrameRef raise @hal.EcError {
  self.pool.acquire()
}

///|
pub impl @hal.ZeroCopyNic for MockZeroCopyNic with tx_buffer(
  self : MockZeroCopyNic,
  fref : @hal.FrameRef,
) -> FixedArray[Byte] {
  self.pool.buffer(fref)
}

///|
pub impl @hal.ZeroCopyNic for MockZeroCopyNic with submit(
  self : MockZeroCopyNic,
  fref : @hal.FrameRef,
  length~ : Int,
) -> Unit raise @hal.EcError {
  // Loopback: copy the sent frame into an RX slot
  let tx_buf = self.pool.buffer(fref)
  let rx_ref = self.pool.acquire_rx()
  let rx_buf = self.pool.buffer(rx_ref)
  for i = 0; i < length; i = i + 1 {
    rx_buf[i] = tx_buf[i]
  }
  let _ = self.pool.mark_received(rx_ref, length)
  // Enqueue RX slot
  if self.rx_count < self.rx_capacity {
    self.rx_queue[self.rx_tail] = rx_ref.slot
    self.rx_tail = (self.rx_tail + 1) % self.rx_capacity
    self.rx_count = self.rx_count + 1
  } else {
    // RX queue is full; drop this loopback frame and release the slot
    self.pool.release(rx_ref)
  }
  // Release TX slot
  self.pool.mark_sent(fref)
  self.pool.release(fref)
}

///|
pub impl @hal.ZeroCopyNic for MockZeroCopyNic with recv(
  self : MockZeroCopyNic,
  timeout~ : @hal.Duration,
) -> @hal.FrameRef raise @hal.EcError {
  let _ = timeout
  if self.rx_count == 0 {
    raise @hal.EcError::RecvTimeout
  }
  let slot = self.rx_queue[self.rx_head]
  self.rx_head = (self.rx_head + 1) % self.rx_capacity
  self.rx_count = self.rx_count - 1
  let length = self.pool.data_length({
    pool_id: self.pool.id,
    slot,
    offset: 0,
    length: 0,
  })
  { pool_id: self.pool.id, slot, offset: 0, length }
}

///|
pub impl @hal.ZeroCopyNic for MockZeroCopyNic with rx_buffer(
  self : MockZeroCopyNic,
  fref : @hal.FrameRef,
) -> FixedArray[Byte] {
  self.pool.buffer(fref)
}

///|
pub impl @hal.ZeroCopyNic for MockZeroCopyNic with rx_length(
  self : MockZeroCopyNic,
  fref : @hal.FrameRef,
) -> Int {
  self.pool.data_length(fref)
}

///|
pub impl @hal.ZeroCopyNic for MockZeroCopyNic with release(
  self : MockZeroCopyNic,
  fref : @hal.FrameRef,
) -> Unit {
  self.pool.release(fref)
}

///|
pub impl @hal.ZeroCopyNic for MockZeroCopyNic with close(self : MockZeroCopyNic) -> Unit {
  self.is_open = false
  self.pool.reset()
}
