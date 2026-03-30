///|
/// FaultType defines the kinds of faults that can be injected at the NIC boundary.
/// These model real-world network/hardware failures that a robust EtherCAT master
/// must handle gracefully.
pub(all) enum FaultType {
  /// recv returns RecvTimeout — models cable disconnect, slave power loss, EMI burst
  RecvTimeout
  /// send raises SendFailed — models NIC driver failure, buffer overflow
  SendFailure(String)
  /// Corrupt a byte in the response frame at the given offset —
  /// can cause WKC mismatch, invalid PDU, CRC error depending on offset
  FrameCorrupt(offset~ : Int, value~ : Byte)
  /// Silently drop the response (no frame queued) — models frame loss on wire
  FrameDrop
  /// Corrupt the WKC field in the first PDU of the response by adding delta —
  /// directly triggers WKC mismatch detection in the runtime
  WkcCorrupt(delta~ : Int)
} derive(Show)

///|
/// FaultSchedule controls when a fault rule fires.
pub(all) enum FaultSchedule {
  /// Fire on every matching operation
  Always
  /// Fire once, then auto-deactivate
  Once
  /// Fire N times, then auto-deactivate
  CountDown(Int)
  /// Remain dormant for N operations, then activate permanently
  AfterN(Int)
  /// Fire only at the exact operation count (0-based)
  AtCycle(Int)
} derive(Show)

///|
/// FaultRule binds a fault type to a schedule.
pub struct FaultRule {
  fault : FaultType
  mut schedule : FaultSchedule
  mut active : Bool
  mut fired_count : Int
} derive(Show)

///|
pub fn FaultRule::new(fault : FaultType, schedule : FaultSchedule) -> FaultRule {
  { fault, schedule, active: true, fired_count: 0 }
}

///|
/// Check whether this rule should fire at the given operation count,
/// and if so, advance its internal state. Returns true if the fault fires.
pub fn FaultRule::should_fire(self : FaultRule, op_count : Int) -> Bool {
  if !self.active {
    return false
  }
  match self.schedule {
    Always => {
      self.fired_count += 1
      true
    }
    Once => {
      self.active = false
      self.fired_count += 1
      true
    }
    CountDown(n) => {
      if n <= 1 {
        self.active = false
      } else {
        self.schedule = CountDown(n - 1)
      }
      self.fired_count += 1
      true
    }
    AfterN(n) =>
      if op_count >= n {
        self.fired_count += 1
        true
      } else {
        false
      }
    AtCycle(target) =>
      if op_count == target {
        self.active = false
        self.fired_count += 1
        true
      } else {
        false
      }
  }
}

///|
/// FaultInjector manages a collection of fault rules and tracks operation counts.
pub struct FaultInjector {
  rules : Array[FaultRule]
  mut send_count : Int
  mut recv_count : Int
} derive(Show)

///|
pub fn FaultInjector::new() -> FaultInjector {
  { rules: [], send_count: 0, recv_count: 0 }
}

///|
/// Add a fault rule to the injector.
pub fn FaultInjector::add_rule(self : FaultInjector, rule : FaultRule) -> Unit {
  self.rules.push(rule)
}

///|
/// Convenience: add a fault with a schedule.
pub fn FaultInjector::add(
  self : FaultInjector,
  fault : FaultType,
  schedule : FaultSchedule,
) -> Unit {
  self.rules.push(FaultRule::new(fault, schedule))
}

///|
/// Check send-phase faults. Returns the first matching SendFailure fault, if any.
/// Increments send_count.
pub fn FaultInjector::check_send(self : FaultInjector) -> FaultType? {
  let count = self.send_count
  self.send_count += 1
  for rule in self.rules {
    match rule.fault {
      SendFailure(_) => if rule.should_fire(count) { return Some(rule.fault) }
      _ => ()
    }
  }
  None
}

///|
/// Check recv-phase faults. Returns the first matching recv-affecting fault, if any.
/// Increments recv_count.
pub fn FaultInjector::check_recv(self : FaultInjector) -> FaultType? {
  let count = self.recv_count
  self.recv_count += 1
  for rule in self.rules {
    match rule.fault {
      RecvTimeout | FrameDrop | FrameCorrupt(..) | WkcCorrupt(..) =>
        if rule.should_fire(count) {
          return Some(rule.fault)
        }
      SendFailure(_) => ()
    }
  }
  None
}

///|
/// Apply a frame-level fault to response data. Returns modified data or None (for drop/timeout).
pub fn apply_frame_fault(fault : FaultType, data : Bytes) -> Bytes? {
  match fault {
    RecvTimeout | FrameDrop => None
    SendFailure(_) => Some(data)
    FrameCorrupt(offset~, value~) =>
      if offset >= 0 && offset < data.length() {
        let buf = FixedArray::make(data.length(), b'\x00')
        for i in 0..<data.length() {
          buf[i] = data[i]
        }
        buf[offset] = value
        Some(Bytes::from_array(buf))
      } else {
        Some(data)
      }
    WkcCorrupt(delta~) =>
      // WKC is the last 2 bytes of each PDU in the EtherCAT payload.
      // For simplicity, corrupt the last 2 bytes of the frame (before Ethernet padding).
      // EtherCAT frame: 14 (eth hdr) + 2 (ecat hdr) + PDU payload + 2 (wkc)
      // The WKC of the last PDU ends at the frame data boundary.
      if data.length() >= 18 {
        let buf = FixedArray::make(data.length(), b'\x00')
        for i in 0..<data.length() {
          buf[i] = data[i]
        }
        // Find PDU WKC: it's at offset (frame_len - 2) for single-PDU frames
        let wkc_offset = data.length() - 2
        let wkc_lo = data[wkc_offset].to_int()
        let wkc_hi = data[wkc_offset + 1].to_int()
        let wkc = wkc_lo | (wkc_hi << 8)
        let new_wkc = wkc + delta
        buf[wkc_offset] = (new_wkc & 0xFF).to_byte()
        buf[wkc_offset + 1] = ((new_wkc >> 8) & 0xFF).to_byte()
        Some(Bytes::from_array(buf))
      } else {
        Some(data)
      }
  }
}

///|
/// Reset all rules to their initial active state and zero counters.
pub fn FaultInjector::reset(self : FaultInjector) -> Unit {
  self.send_count = 0
  self.recv_count = 0
  for rule in self.rules {
    rule.active = true
    rule.fired_count = 0
  }
}

///|
/// Get total number of faults that have fired.
pub fn FaultInjector::total_fired(self : FaultInjector) -> Int {
  let mut total = 0
  for rule in self.rules {
    total += rule.fired_count
  }
  total
}
