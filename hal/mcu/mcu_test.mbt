///|
test "McuNicConfig default RzN2L" {
  let config = @mcu.McuNicConfig::default(@mcu.RzN2L)
  inspect(config.platform, content="RzN2L")
  inspect(config.ring_size, content="64")
}

///|
test "McuNic open raises NotSupported" {
  let result : Result[@mcu.McuNic, _] = Ok(@hal.Nic::open_("eth0")) catch {
    e => Err(e)
  }
  inspect(result.is_err(), content="true")
}

///|
test "McuClock now returns zero stub" {
  let clk = @mcu.McuClock::new(@mcu.RzN2L, 400_000_000L)
  let ts = @hal.Clock::now(clk)
  inspect(ts, content="Timestamp(0)")
}

///|
test "EventRing push and pop" {
  let ring = @mcu.EventRing::new(4, 64)
  inspect(ring.is_empty(), content="true")
  inspect(ring.push(Bytes::make(3, b'\xAA')), content="true")
  inspect(ring.is_empty(), content="false")
  inspect(ring.len(), content="1")
  match ring.pop() {
    Some(entry) => inspect(entry.length, content="3")
    None => inspect(false, content="true")
  }
  inspect(ring.is_empty(), content="true")
}

///|
test "EventRing full detection" {
  let ring = @mcu.EventRing::new(2, 16)
  inspect(ring.push(Bytes::make(1, b'\x01')), content="true")
  inspect(ring.push(Bytes::make(1, b'\x02')), content="true")
  // Ring is full (capacity 2)
  inspect(ring.is_full(), content="true")
  inspect(ring.push(Bytes::make(1, b'\x03')), content="false")
}

///|
test "EventRing overwrites slots on wraparound" {
  let ring = @mcu.EventRing::new(2, 16)
  assert_true(ring.push(Bytes::make(1, b'\x01')))
  assert_true(ring.push(Bytes::make(1, b'\x02')))
  guard ring.pop() is Some(first) else { fail("missing first entry") }
  assert_eq(first.data[0], b'\x01')
  assert_true(ring.push(Bytes::make(1, b'\x03')))
  guard ring.pop() is Some(second) else { fail("missing second entry") }
  assert_eq(second.data[0], b'\x02')
  guard ring.pop() is Some(third) else { fail("missing wrapped entry") }
  assert_eq(third.data[0], b'\x03')
}

///|
test "SharedMemoryRegion creation" {
  let region = @mcu.SharedMemoryRegion::new("ecat_ring", 0x2000_0000U, 65536)
  inspect(region.name, content="ecat_ring")
  inspect(region.cache_coherent, content="false")
}

///|
test "BridgeStats tracking" {
  let stats = @mcu.BridgeStats::new()
  stats.record_push(true)
  stats.record_push(true)
  stats.record_push(false)
  stats.record_pop()
  stats.update_fill(2)
  inspect(stats.total_pushed, content="2")
  inspect(stats.total_dropped, content="1")
  inspect(stats.total_popped, content="1")
  inspect(stats.max_fill_level, content="2")
}
