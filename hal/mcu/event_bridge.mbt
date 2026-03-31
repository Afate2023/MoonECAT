///|
/// MCU→Linux event queue bridge types.
///
/// C-10: Lock-free ring buffer and shared memory region descriptors
/// for bridging events between an MCU EtherCAT slave controller
/// and a Linux host running MoonECAT runtime.
///
/// Architecture:
///   MCU (bare-metal) ──[Shared SRAM / PCIe BAR]──→ Linux (MoonECAT)
///      Writer                                       Reader
///      (IRQ handler)                                (poll or epoll)
///
/// The ring uses a single-producer / single-consumer (SPSC) design
/// with acquire/release memory ordering semantics.

///|
/// Ring buffer entry header (8 bytes, cache-line aligned on MCU side).
pub(all) struct RingEntry {
  /// Sequence number (monotonically increasing, wraps at UInt::max).
  seq : UInt
  /// Payload length in bytes.
  length : Int
  /// Payload data.
  data : Bytes
} derive(Show)

///|
/// Lock-free SPSC ring buffer for cross-domain event transfer.
///
/// Parameters:
///   - capacity: must be power of 2 (enforced by constructor)
///   - slot_size: max payload size per entry
///
/// Memory layout in shared memory:
///   [0..4)   : write_index (MCU writes, Linux reads)
///   [4..8)   : read_index  (Linux writes, MCU reads)
///   [8..12)  : capacity
///   [12..16) : slot_size
///   [16..)   : slot_data[capacity][slot_size + 8]  (8-byte header per slot)
pub(all) struct EventRing {
  capacity : Int
  slot_size : Int
  mut write_idx : UInt
  mut read_idx : UInt
  slots : Array[RingEntry]
} derive(Show)

///|
fn is_power_of_two(n : Int) -> Bool {
  n > 0 && n.land(n - 1) == 0
}

///|
pub fn EventRing::new(capacity : Int, slot_size : Int) -> EventRing {
  let cap = if is_power_of_two(capacity) { capacity } else { 64 }
  { capacity: cap, slot_size, write_idx: 0U, read_idx: 0U, slots: [] }
}

///|
/// Check if the ring is full.
pub fn EventRing::is_full(self : EventRing) -> Bool {
  let mask = self.capacity.reinterpret_as_uint()
  self.write_idx - self.read_idx >= mask
}

///|
/// Check if the ring is empty.
pub fn EventRing::is_empty(self : EventRing) -> Bool {
  self.write_idx == self.read_idx
}

///|
/// Number of entries currently in the ring.
pub fn EventRing::len(self : EventRing) -> Int {
  (self.write_idx - self.read_idx).reinterpret_as_int()
}

///|
/// Push an entry into the ring (producer side).
/// Returns false if the ring is full.
pub fn EventRing::push(self : EventRing, data : Bytes) -> Bool {
  if self.is_full() {
    return false
  }
  let seq = self.write_idx
  let length = if data.length() > self.slot_size {
    self.slot_size
  } else {
    data.length()
  }
  let trimmed = Bytes::makei(length, fn(i) { data[i] })
  self.slots.push({ seq, length, data: trimmed })
  self.write_idx = self.write_idx + 1U
  true
}

///|
/// Pop an entry from the ring (consumer side).
/// Returns None if the ring is empty.
pub fn EventRing::pop(self : EventRing) -> RingEntry? {
  if self.is_empty() {
    return None
  }
  let idx = self.read_idx.reinterpret_as_int() % self.capacity
  if idx >= self.slots.length() {
    return None
  }
  let entry = self.slots[idx]
  self.read_idx = self.read_idx + 1U
  Some(entry)
}

///|
/// Shared memory region descriptor for MCU↔Linux communication.
///
/// Describes a named shared memory region that both sides can map.
/// On Linux: /dev/shm or mmap'd file.
/// On MCU: fixed SRAM address range.
pub(all) struct SharedMemoryRegion {
  /// Human-readable name (e.g., "ecat_event_ring")
  name : String
  /// Base address on the MCU side (physical address).
  mcu_base_addr : UInt
  /// Size in bytes.
  size : Int
  /// Whether this region is cache-coherent between domains.
  cache_coherent : Bool
} derive(Show)

///|
pub fn SharedMemoryRegion::new(
  name : String,
  mcu_base_addr : UInt,
  size : Int,
  cache_coherent? : Bool = false,
) -> SharedMemoryRegion {
  { name, mcu_base_addr, size, cache_coherent }
}

///|
/// BridgeConfig combines ring buffer and shared memory configuration.
pub(all) struct BridgeConfig {
  /// Event ring for MCU→Linux event delivery.
  event_ring : EventRing
  /// Shared memory region for ring buffer backing store.
  region : SharedMemoryRegion
  /// Maximum events per poll batch.
  max_batch : Int
} derive(Show)

///|
pub fn BridgeConfig::new(
  region : SharedMemoryRegion,
  capacity? : Int = 256,
  slot_size? : Int = 1536,
  max_batch? : Int = 32,
) -> BridgeConfig {
  { event_ring: EventRing::new(capacity, slot_size), region, max_batch }
}

///|
/// BridgeStats tracks runtime statistics of the event bridge.
pub(all) struct BridgeStats {
  mut total_pushed : Int64
  mut total_popped : Int64
  mut total_dropped : Int64
  mut max_fill_level : Int
} derive(Show)

///|
pub fn BridgeStats::new() -> BridgeStats {
  { total_pushed: 0L, total_popped: 0L, total_dropped: 0L, max_fill_level: 0 }
}

///|
pub fn BridgeStats::record_push(self : BridgeStats, success : Bool) -> Unit {
  if success {
    self.total_pushed = self.total_pushed + 1L
  } else {
    self.total_dropped = self.total_dropped + 1L
  }
}

///|
pub fn BridgeStats::record_pop(self : BridgeStats) -> Unit {
  self.total_popped = self.total_popped + 1L
}

///|
pub fn BridgeStats::update_fill(self : BridgeStats, current_fill : Int) -> Unit {
  if current_fill > self.max_fill_level {
    self.max_fill_level = current_fill
  }
}
