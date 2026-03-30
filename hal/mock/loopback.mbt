///|
/// MockNic is a loopback network interface for testing.
/// Sent frames are buffered and returned on the next recv call.
pub struct MockNic {
  buffer : Array[Bytes]
  mut is_open : Bool
}

///|
pub fn MockNic::new() -> MockNic {
  { buffer: [], is_open: true }
}

///|
pub impl @hal.Nic for MockNic with open_(name) {
  ignore(name)
  MockNic::new()
}

///|
pub impl @hal.Nic for MockNic with send(self, data) {
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  self.buffer.push(data)
  data.length()
}

///|
pub impl @hal.Nic for MockNic with recv(self, timeout~) {
  ignore(timeout)
  if !self.is_open {
    raise @hal.EcError::LinkDown
  }
  if self.buffer.is_empty() {
    raise @hal.EcError::RecvTimeout
  }
  self.buffer.remove(0)
}

///|
pub impl @hal.Nic for MockNic with close(self) {
  self.is_open = false
}

///|
/// MockClock provides a controllable clock for deterministic testing.
pub struct MockClock {
  mut current_ns : Int64
}

///|
pub fn MockClock::new() -> MockClock {
  { current_ns: 0L }
}

///|
pub fn MockClock::advance(self : MockClock, ns : Int64) -> Unit {
  self.current_ns = self.current_ns + ns
}

///|
pub impl @hal.Clock for MockClock with now(self) {
  @hal.Timestamp(self.current_ns)
}

///|
pub impl @hal.Clock for MockClock with sleep(self, duration) {
  let @hal.Duration(ns) = duration
  self.current_ns = self.current_ns + ns
}
