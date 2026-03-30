///|
/// ReplayNic replays a previously recorded NicEventLog.
/// On each send/recv call it returns the next recorded event,
/// producing the exact same Nic behaviour as the original session.
pub struct ReplayNic {
  log : NicEventLog
  mut cursor : Int
}

///|
pub fn ReplayNic::from_log(log : NicEventLog) -> ReplayNic {
  { log, cursor: 0 }
}

///|
pub fn ReplayNic::remaining(self : ReplayNic) -> Int {
  self.log.len() - self.cursor
}

///|
pub fn ReplayNic::is_exhausted(self : ReplayNic) -> Bool {
  self.cursor >= self.log.len()
}

///|
pub impl @hal.Nic for ReplayNic with open_(name) {
  ignore(name)
  ReplayNic::from_log(NicEventLog::new())
}

///|
pub impl @hal.Nic for ReplayNic with send(self, _data) {
  if self.cursor >= self.log.len() {
    raise @hal.EcError::SendFailed("replay log exhausted")
  }
  match self.log.events[self.cursor] {
    Sent(_recorded, n) => {
      self.cursor += 1
      n
    }
    SendFailed(msg) => {
      self.cursor += 1
      raise @hal.EcError::SendFailed(msg)
    }
    _ =>
      raise @hal.EcError::SendFailed(
        "replay: expected Sent event at cursor " + self.cursor.to_string(),
      )
  }
}

///|
pub impl @hal.Nic for ReplayNic with recv(self, timeout~) {
  ignore(timeout)
  if self.cursor >= self.log.len() {
    raise @hal.EcError::RecvTimeout
  }
  match self.log.events[self.cursor] {
    Received(data) => {
      self.cursor += 1
      data
    }
    RecvTimeout => {
      self.cursor += 1
      raise @hal.EcError::RecvTimeout
    }
    _ =>
      raise @hal.EcError::RecvFailed(
        "replay: expected Received event at cursor " + self.cursor.to_string(),
      )
  }
}

///|
pub impl @hal.Nic for ReplayNic with close(self) {
  self.cursor = self.log.len()
}
