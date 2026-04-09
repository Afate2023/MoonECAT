///|
/// Wasm-GC fuzzing minimal framework (B-13).
///
/// Generates random NicEvent sequences for fuzz testing the protocol stack.
/// Uses a simple LCG PRNG for deterministic reproducibility from a seed.

///|
/// FuzzRng — simple linear congruential generator for deterministic fuzzing.
pub(all) struct FuzzRng {
  mut state : Int64
} derive(Debug)

///|
pub fn FuzzRng::new(seed : Int64) -> FuzzRng {
  { state: seed }
}

///|
/// Generate next pseudo-random Int64.
pub fn FuzzRng::next(self : FuzzRng) -> Int64 {
  // LCG parameters from Numerical Recipes
  self.state = self.state * 6364136223846793005L + 1442695040888963407L
  self.state
}

///|
/// Generate a random Int in [0, max).
pub fn FuzzRng::next_int(self : FuzzRng, max : Int) -> Int {
  if max <= 0 {
    return 0
  }
  let v = self.next()
  let positive = if v < 0L { -v } else { v }
  (positive % max.to_int64()).to_int()
}

///|
/// Generate random bytes of the given length.
pub fn FuzzRng::next_bytes(self : FuzzRng, len : Int) -> Bytes {
  let arr = FixedArray::make(len, b'\x00')
  for i in 0..<len {
    arr[i] = self.next_int(256).to_byte()
  }
  Bytes::from_array(arr)
}

///|
/// Generate a random NicEvent.
pub fn FuzzRng::next_nic_event(self : FuzzRng) -> NicEvent {
  match self.next_int(4) {
    0 => {
      let len = self.next_int(1500) + 14
      let data = self.next_bytes(len)
      let sent_len = self.next_int(len + 1)
      NicEvent::Sent(data, sent_len)
    }
    1 => {
      let len = self.next_int(1500) + 14
      let data = self.next_bytes(len)
      NicEvent::Received(data)
    }
    2 => NicEvent::RecvTimeout
    _ => NicEvent::SendFailed("fuzz_fault_" + self.next_int(1000).to_string())
  }
}

///|
/// Generate a random NicEventLog of the given length.
pub fn FuzzRng::generate_event_log(self : FuzzRng, count : Int) -> NicEventLog {
  let log = NicEventLog::new()
  for _ in 0..<count {
    log.append(self.next_nic_event())
  }
  log
}

///|
/// FuzzOracle — crash detection callback.
/// Returns true if the system is in a valid (non-crashed) state.
pub(all) struct FuzzOracle {
  check : () -> Bool
}

///|
/// FuzzResult records the outcome of one fuzz run.
pub(all) struct FuzzResult {
  seed : Int64
  event_count : Int
  crashed : Bool
  crash_at : Int
  error_msg : String
} derive(Debug)

///|
/// Run a single fuzz iteration with the given seed and event count.
/// The oracle is called after each event is replayed; if it returns false,
/// the run is marked as crashed.
pub fn fuzz_run(
  seed : Int64,
  event_count : Int,
  oracle : FuzzOracle,
) -> FuzzResult {
  let rng = FuzzRng::new(seed)
  let log = rng.generate_event_log(event_count)
  let replay = ReplayNic::from_log(log)
  // Replay through a ReplayNic and check oracle after each step
  for i in 0..<event_count {
    apply_replay_event(replay, replay.log.events[i])
    if !(oracle.check)() {
      return {
        seed,
        event_count,
        crashed: true,
        crash_at: i,
        error_msg: "oracle returned false at event " + i.to_string(),
      }
    }
  }
  { seed, event_count, crashed: false, crash_at: -1, error_msg: "" }
}

///|
fn apply_replay_event(replay : ReplayNic, event : NicEvent) -> Unit {
  match event {
    Sent(data, _) => ignore(Ok(replay.send(data)) catch { _ => Err(()) })
    SendFailed(_) => ignore(Ok(replay.send(b"")) catch { _ => Err(()) })
    Received(_) =>
      ignore(Ok(replay.recv(timeout=@hal.Duration(0L))) catch { _ => Err(()) })
    RecvTimeout =>
      ignore(Ok(replay.recv(timeout=@hal.Duration(0L))) catch { _ => Err(()) })
    RecvFailed(_) =>
      ignore(Ok(replay.recv(timeout=@hal.Duration(0L))) catch { _ => Err(()) })
    LinkDown =>
      ignore(Ok(replay.recv(timeout=@hal.Duration(0L))) catch { _ => Err(()) })
  }
}

///|
/// Run multiple fuzz iterations with sequential seeds.
pub fn fuzz_campaign(
  base_seed : Int64,
  iterations : Int,
  events_per_run : Int,
  oracle : FuzzOracle,
) -> Array[FuzzResult] {
  let results : Array[FuzzResult] = []
  for i in 0..<iterations {
    let seed = base_seed + i.to_int64()
    let result = fuzz_run(seed, events_per_run, oracle)
    results.push(result)
    if result.crashed {
      break
    }
  }
  results
}
