///|
/// FrameState tracks the lifecycle of a frame slot in the pool.
/// Transitions: Free 鈫?Acquired 鈫?Filled 鈫?Sending 鈫?Sent 鈫?Free
///              Free 鈫?Receiving 鈫?Received 鈫?Free
pub(all) enum FrameState {
  Free
  Acquired
  Filled
  Sending
  Sent
  Receiving
  Received
} derive(Eq, Debug)

///|
/// FrameRef is a lightweight value-type reference to a frame slot.
/// No heap allocation 鈥?just 4 integers identifying the slice of data.
pub(all) struct FrameRef {
  pool_id : Int
  slot : Int
  offset : Int
  length : Int
} derive(Eq, Debug)

///|
/// FramePool provides pre-allocated frame buffers that eliminate
/// per-cycle heap allocation in the PDO hot path.
///
/// Inspired by EtherCrab's PduStorage (atomic frame pool) and
/// CherryECAT's DMA descriptor ring (static buffer reuse).
pub(all) struct FramePool {
  id : Int
  frames : FixedArray[FixedArray[Byte]]
  states : FixedArray[FrameState]
  lengths : FixedArray[Int]
  capacity : Int
  frame_size : Int
  mut next_scan : Int
}

///|
/// Default number of frame slots in a pool.
pub let default_pool_capacity : Int = 16

///|
/// Create a new FramePool with the given capacity and frame size.
/// All buffers are pre-allocated; no further allocation occurs during operation.
pub fn FramePool::new(
  capacity? : Int = default_pool_capacity,
  frame_size? : Int = max_frame_size,
  id? : Int = 0,
) -> FramePool {
  let frames : FixedArray[FixedArray[Byte]] = FixedArray::makei(capacity, fn(
    _i,
  ) {
    FixedArray::make(frame_size, b'\x00')
  })
  let states = FixedArray::make(capacity, Free)
  let lengths = FixedArray::make(capacity, 0)
  { id, frames, states, lengths, capacity, frame_size, next_scan: 0 }
}

///|
/// Acquire a free frame slot from the pool.
/// Scans from the last allocation point (round-robin) for O(1) amortized.
/// Returns EcError if no free slots are available.
pub fn FramePool::acquire(self : FramePool) -> FrameRef raise EcError {
  let start = self.next_scan
  for i = 0; i < self.capacity; i = i + 1 {
    let idx = (start + i) % self.capacity
    if self.states[idx] == Free {
      self.states[idx] = Acquired
      self.lengths[idx] = 0
      self.next_scan = (idx + 1) % self.capacity
      return { pool_id: self.id, slot: idx, offset: 0, length: 0 }
    }
  }
  raise EcError::Internal("FramePool: no free slots")
}

///|
/// Get the writable buffer for an acquired frame slot.
/// The caller fills this buffer with frame data, then calls mark_filled.
pub fn FramePool::buffer(self : FramePool, fref : FrameRef) -> FixedArray[Byte] {
  self.frames[fref.slot]
}

///|
/// Mark a frame as filled with the given data length.
pub fn FramePool::mark_filled(
  self : FramePool,
  fref : FrameRef,
  length : Int,
) -> FrameRef {
  self.states[fref.slot] = Filled
  self.lengths[fref.slot] = length
  { ..fref, length, }
}

///|
/// Mark a frame as being sent by the platform backend.
pub fn FramePool::mark_sending(self : FramePool, fref : FrameRef) -> Unit {
  self.states[fref.slot] = Sending
}

///|
/// Mark a frame as sent (transmission complete).
pub fn FramePool::mark_sent(self : FramePool, fref : FrameRef) -> Unit {
  self.states[fref.slot] = Sent
}

///|
/// Acquire a slot for receiving into.
pub fn FramePool::acquire_rx(self : FramePool) -> FrameRef raise EcError {
  let fref = self.acquire()
  self.states[fref.slot] = Receiving
  fref
}

///|
/// Mark a receive slot as having received data.
pub fn FramePool::mark_received(
  self : FramePool,
  fref : FrameRef,
  length : Int,
) -> FrameRef {
  self.states[fref.slot] = Received
  self.lengths[fref.slot] = length
  { ..fref, length, }
}

///|
/// Release a frame slot back to the pool for reuse.
pub fn FramePool::release(self : FramePool, fref : FrameRef) -> Unit {
  self.states[fref.slot] = Free
  self.lengths[fref.slot] = 0
}

///|
/// Get the current state of a frame slot.
pub fn FramePool::state(self : FramePool, fref : FrameRef) -> FrameState {
  self.states[fref.slot]
}

///|
/// Get the effective data length for a frame slot.
pub fn FramePool::data_length(self : FramePool, fref : FrameRef) -> Int {
  self.lengths[fref.slot]
}

///|
/// Count the number of free slots available.
pub fn FramePool::free_count(self : FramePool) -> Int {
  let mut count = 0
  for i = 0; i < self.capacity; i = i + 1 {
    if self.states[i] == Free {
      count = count + 1
    }
  }
  count
}

///|
/// Reset all slots to Free state. Used for pool reinitialization.
pub fn FramePool::reset(self : FramePool) -> Unit {
  for i = 0; i < self.capacity; i = i + 1 {
    self.states[i] = Free
    self.lengths[i] = 0
  }
  self.next_scan = 0
}

///|
/// Write a single byte into a frame buffer at the given offset.
pub fn FramePool::write_byte(
  self : FramePool,
  fref : FrameRef,
  offset : Int,
  value : Byte,
) -> Unit {
  self.frames[fref.slot][offset] = value
}

///|
/// Read a single byte from a frame buffer at the given offset.
pub fn FramePool::read_byte(
  self : FramePool,
  fref : FrameRef,
  offset : Int,
) -> Byte {
  self.frames[fref.slot][offset]
}

///|
/// Copy data from a FixedArray into a frame buffer at the given offset.
pub fn FramePool::write_bytes(
  self : FramePool,
  fref : FrameRef,
  offset : Int,
  src : FixedArray[Byte],
  src_offset : Int,
  count : Int,
) -> Unit {
  let buf = self.frames[fref.slot]
  for i = 0; i < count; i = i + 1 {
    buf[offset + i] = src[src_offset + i]
  }
}

///|
/// Copy data from a frame buffer into a FixedArray at the given offset.
pub fn FramePool::read_bytes(
  self : FramePool,
  fref : FrameRef,
  offset : Int,
  dst : FixedArray[Byte],
  dst_offset : Int,
  count : Int,
) -> Unit {
  let buf = self.frames[fref.slot]
  for i = 0; i < count; i = i + 1 {
    dst[dst_offset + i] = buf[offset + i]
  }
}

///|
/// Write a 16-bit little-endian value into a frame buffer.
pub fn FramePool::write_u16_le(
  self : FramePool,
  fref : FrameRef,
  offset : Int,
  value : Int,
) -> Unit {
  let buf = self.frames[fref.slot]
  buf[offset] = (value & 0xFF).to_byte()
  buf[offset + 1] = ((value >> 8) & 0xFF).to_byte()
}

///|
/// Read a 16-bit little-endian value from a frame buffer.
pub fn FramePool::read_u16_le(
  self : FramePool,
  fref : FrameRef,
  offset : Int,
) -> Int {
  let buf = self.frames[fref.slot]
  buf[offset].to_int() | (buf[offset + 1].to_int() << 8)
}

///|
/// Write a 32-bit little-endian value into a frame buffer.
pub fn FramePool::write_u32_le(
  self : FramePool,
  fref : FrameRef,
  offset : Int,
  value : Int,
) -> Unit {
  let buf = self.frames[fref.slot]
  buf[offset] = (value & 0xFF).to_byte()
  buf[offset + 1] = ((value >> 8) & 0xFF).to_byte()
  buf[offset + 2] = ((value >> 16) & 0xFF).to_byte()
  buf[offset + 3] = ((value >> 24) & 0xFF).to_byte()
}

///|
/// Read a 32-bit little-endian value from a frame buffer.
pub fn FramePool::read_u32_le(
  self : FramePool,
  fref : FrameRef,
  offset : Int,
) -> Int {
  let buf = self.frames[fref.slot]
  buf[offset].to_int() |
  (buf[offset + 1].to_int() << 8) |
  (buf[offset + 2].to_int() << 16) |
  (buf[offset + 3].to_int() << 24)
}
