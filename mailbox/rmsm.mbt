///|
/// Resilient Mailbox State Machine (RMSM) per ETG.1000.4.
/// Tracks per-slave mailbox state, manages counter correlation,
/// and provides retry logic for lost/stale frames.

///|
/// RMSM state for a single slave's mailbox channel.
pub(all) enum RmsmState {
  /// No pending transaction; ready to send.
  Idle
  /// Waiting for a response with the given counter value.
  WaitingForResponse(Byte)
  /// Transaction completed with an error; can be reset.
  Error(String)
} derive(Eq, Show)

///|
/// Per-slave Resilient Mailbox State Machine.
/// Manages counter correlation and repeat detection.
pub(all) struct Rmsm {
  /// Mailbox counter (cycles 1–15).
  counter : MailboxCounter
  /// Current state.
  mut state : RmsmState
  /// Maximum retries for a single transaction.
  max_retries : Int
  /// Current retry count within the active transaction.
  mut retries : Int
  /// Last received counter value for repeat detection.
  mut last_recv_counter : Byte
} derive(Show)

///|
pub fn Rmsm::new(max_retries? : Int = 3) -> Rmsm {
  {
    counter: MailboxCounter::new(),
    state: Idle,
    max_retries,
    retries: 0,
    last_recv_counter: b'\x00',
  }
}

///|
/// Begin a new mailbox transaction. Returns the counter value to embed.
/// Transitions from Idle → WaitingForResponse.
pub fn Rmsm::begin_transaction(self : Rmsm) -> Byte raise @hal.EcError {
  guard self.state is Idle else {
    raise @hal.EcError::MailboxProtocol(
      "RMSM: cannot begin transaction in state " + self.state.to_string(),
    )
  }
  let cnt = self.counter.next()
  self.state = WaitingForResponse(cnt)
  self.retries = 0
  cnt
}

///|
/// Validate a received mailbox response counter.
/// Returns true if this is a valid (new) response; false if it's a repeat.
pub fn Rmsm::validate_response(
  self : Rmsm,
  recv_counter : Byte,
) -> Bool raise @hal.EcError {
  guard self.state is WaitingForResponse(expected) else {
    raise @hal.EcError::MailboxProtocol(
      "RMSM: unexpected response in state " + self.state.to_string(),
    )
  }
  // Check for repeat (same counter as last received)
  if recv_counter == self.last_recv_counter && recv_counter != b'\x00' {
    return false // Repeat frame, discard
  }
  // Validate counter matches expectation
  if recv_counter != expected && recv_counter != b'\x00' {
    // Counter 0 = slave doesn't support counters, always accept
    self.state = Error(
      "RMSM: counter mismatch: expected " +
      expected.to_int().to_string() +
      " got " +
      recv_counter.to_int().to_string(),
    )
    raise @hal.EcError::MailboxProtocol(
      "RMSM: counter mismatch: expected " +
      expected.to_int().to_string() +
      " got " +
      recv_counter.to_int().to_string(),
    )
  }
  self.last_recv_counter = recv_counter
  self.state = Idle
  true
}

///|
/// Record a timeout and check if we should retry.
/// Returns true if a retry is allowed, false if retries exhausted.
pub fn Rmsm::record_timeout(self : Rmsm) -> Bool {
  self.retries = self.retries + 1
  if self.retries > self.max_retries {
    self.state = Error(
      "RMSM: retries exhausted (" + self.max_retries.to_string() + ")",
    )
    false
  } else {
    // Stay in WaitingForResponse; caller should resend
    true
  }
}

///|
/// Reset the RMSM to Idle state, discarding any pending transaction.
pub fn Rmsm::reset(self : Rmsm) -> Unit {
  self.state = Idle
  self.retries = 0
}

///|
/// Check if the RMSM is ready for a new transaction.
pub fn Rmsm::is_idle(self : Rmsm) -> Bool {
  self.state is Idle
}

///|
/// Get the current counter value that would be used for the next send
/// (without actually beginning a transaction). For repeat sends.
pub fn Rmsm::current_counter(self : Rmsm) -> Byte {
  guard self.state is WaitingForResponse(cnt) else { return b'\x00' }
  cnt
}
