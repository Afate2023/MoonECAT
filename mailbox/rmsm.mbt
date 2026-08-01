///|
/// MainDevice-side mailbox session tracker.
///
/// `Rmsm` is retained as a legacy API name. It is not the SubDevice Receive
/// Mailbox State Machine from ETG.1000.4, and reset/reset_for_retry only reset
/// this local transaction tracker; they never reset an ESC state machine.
/// MainDevice transmit Cnt and SubDevice transmit Cnt are independent.

///|
/// RMSM state for a single slave's mailbox channel.
pub(all) enum RmsmState {
  /// No pending transaction; ready to send.
  Idle
  /// Waiting for a response after sending with the given MainDevice counter.
  WaitingForResponse(Byte)
  /// Transaction completed with an error; can be reset.
  Error(String)
} derive(Eq, Debug)

///|
/// Per-slave MainDevice mailbox session state.
/// Manages the local transmit sequence, independent receive repeat detection,
/// timeout budget, and SyncManager Repeat Request/RepeatAck recovery.
pub(all) struct Rmsm {
  /// MainDevice transmit mailbox counter (cycles 1-7).
  counter : MailboxCounter
  /// Current state.
  mut state : RmsmState
  /// Maximum retries for a single transaction.
  max_retries : Int
  /// Current retry count within the active transaction.
  mut retries : Int
  /// Last SubDevice transmit counter value for repeat detection. This sequence
  /// is independent from `counter`.
  mut last_recv_counter : Byte
  /// Current Repeat Request toggle value tracked for mailbox-read replay.
  mut repeat_request : Bool
  /// True while waiting for the SubDevice to mirror RepeatAck.
  mut awaiting_repeat_ack : Bool
} derive(Debug)

///|
/// Preferred name for the MainDevice-side mailbox session tracker.
/// `Rmsm` remains available for source compatibility.
pub type MailboxSession = Rmsm

///|
pub fn Rmsm::new(max_retries? : Int = 3) -> Rmsm {
  {
    counter: MailboxCounter::new(),
    state: Idle,
    max_retries,
    retries: 0,
    last_recv_counter: b'\x00',
    repeat_request: false,
    awaiting_repeat_ack: false,
  }
}

///|
/// Begin a new mailbox transaction. Returns the counter value to embed.
/// Transitions from Idle → WaitingForResponse.
pub fn Rmsm::begin_transaction(self : Rmsm) -> Byte raise @hal.EcError {
  guard self.state is Idle else {
    raise @hal.EcError::MailboxProtocol(
      "mailbox session: cannot begin transaction in state " +
      @debug.to_string(self.state),
    )
  }
  let cnt = self.counter.next()
  self.state = WaitingForResponse(cnt)
  self.retries = 0
  self.awaiting_repeat_ack = false
  cnt
}

///|
/// Begin a timeout retry transaction without clearing the accumulated retry
/// budget for the surrounding operation.
pub fn Rmsm::begin_retry_transaction(self : Rmsm) -> Byte raise @hal.EcError {
  guard self.state is Idle else {
    raise @hal.EcError::MailboxProtocol(
      "mailbox session: cannot begin retry transaction in state " +
      @debug.to_string(self.state),
    )
  }
  let cnt = self.counter.next()
  self.state = WaitingForResponse(cnt)
  self.awaiting_repeat_ack = false
  cnt
}

///|
/// Validate a received SubDevice mailbox counter.
/// Returns true if this is a valid (new) response; false if it's a stale or
/// repeat frame that the caller should discard and continue polling.
pub fn Rmsm::validate_response(
  self : Rmsm,
  recv_counter : Byte,
) -> Bool raise @hal.EcError {
  guard self.state is WaitingForResponse(_) else {
    raise @hal.EcError::MailboxProtocol(
      "mailbox session: unexpected response in state " +
      @debug.to_string(self.state),
    )
  }
  // Check for repeat (same counter as last received)
  if recv_counter == self.last_recv_counter && recv_counter != b'\x00' {
    return false // Repeat frame, discard
  }
  // ETG.1000.4 defines MainDevice and SubDevice Cnt sequences independently;
  // a response is not required to echo the request Cnt.
  self.last_recv_counter = recv_counter
  self.state = Idle
  self.awaiting_repeat_ack = false
  true
}

///|
/// Toggle Repeat Request in the SyncManager activate byte to recover a lost
/// mailbox read frame. The returned byte is ready to write back to SMx+0x06.
pub fn Rmsm::begin_read_repeat(
  self : Rmsm,
  activate : Byte,
) -> Byte raise @hal.EcError {
  guard self.state is WaitingForResponse(_) else {
    raise @hal.EcError::MailboxProtocol(
      "mailbox session: cannot request mailbox repeat in state " +
      @debug.to_string(self.state),
    )
  }
  self.repeat_request = !self.repeat_request
  self.awaiting_repeat_ack = true
  { request: self.repeat_request, acknowledge: false }.apply_to_activate_byte(
    activate,
  )
}

///|
/// Check whether the SubDevice has mirrored the RepeatAck bit for the current
/// read-repeat sequence. Returns true exactly when the expected toggle is seen.
pub fn Rmsm::observe_repeat_ack(self : Rmsm, pdi_control : Byte) -> Bool {
  let repeat = MailboxRepeatState::from_sync_manager_bytes(b'\x00', pdi_control)
  if self.awaiting_repeat_ack && repeat.acknowledge == self.repeat_request {
    self.awaiting_repeat_ack = false
    true
  } else {
    false
  }
}

///|
/// Report whether a mailbox-read repeat is currently waiting for RepeatAck.
pub fn Rmsm::awaits_repeat_ack(self : Rmsm) -> Bool {
  self.awaiting_repeat_ack
}

///|
/// Record a timeout and check if we should retry.
/// Returns true if a retry is allowed, false if retries exhausted.
pub fn Rmsm::record_timeout(self : Rmsm) -> Bool {
  self.retries = self.retries + 1
  if self.retries > self.max_retries {
    self.state = Error(
      "mailbox session: retries exhausted (" +
      self.max_retries.to_string() +
      ")",
    )
    false
  } else {
    // Stay in WaitingForResponse; caller should resend
    true
  }
}

///|
/// Reset this local tracker to Idle between retry attempts while preserving
/// the retry budget already spent by the caller. This does not reset the ESC.
pub fn Rmsm::reset_for_retry(self : Rmsm) -> Unit {
  self.state = Idle
  self.awaiting_repeat_ack = false
}

///|
/// Reset this local tracker to Idle, discarding any pending transaction.
/// This does not reset the SubDevice Receive Mailbox State Machine or ESM.
pub fn Rmsm::reset(self : Rmsm) -> Unit {
  self.state = Idle
  self.retries = 0
  self.awaiting_repeat_ack = false
}

///|
/// Check if the local mailbox session is ready for a new transaction.
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
