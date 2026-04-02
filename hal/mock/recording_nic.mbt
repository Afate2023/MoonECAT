///|
/// RecordingNic wraps a VirtualNic and records every send/recv
/// outcome into a NicEventLog. The captured log can be replayed
/// through ReplayNic for deterministic reproduction.
pub struct RecordingNic {
  inner : VirtualNic
  log : NicEventLog
}

///|
pub fn RecordingNic::wrap(inner : VirtualNic) -> RecordingNic {
  { inner, log: NicEventLog::new() }
}

///|
pub fn RecordingNic::get_log(self : RecordingNic) -> NicEventLog {
  self.log
}

///|
pub impl @hal.Nic for RecordingNic with open_(name) {
  ignore(name)
  RecordingNic::wrap(VirtualNic::new(VirtualBus::new([])))
}

///|
pub impl @hal.Nic for RecordingNic with send(self, data) {
  let result : Result[Int, @hal.EcError] = Ok(self.inner.send(data)) catch {
    e => Err(e)
  }
  match result {
    Ok(n) => {
      self.log.append(NicEvent::Sent(data, n))
      n
    }
    Err(e) => {
      self.log.append(NicEvent::SendFailed(e.to_string()))
      raise e
    }
  }
}

///|
pub impl @hal.Nic for RecordingNic with recv(self, timeout~) {
  let result : Result[Bytes, @hal.EcError] = Ok(self.inner.recv(timeout~)) catch {
    e => Err(e)
  }
  match result {
    Ok(data) => {
      self.log.append(NicEvent::Received(data))
      data
    }
    Err(@hal.EcError::RecvTimeout) => {
      self.log.append(NicEvent::RecvTimeout)
      raise @hal.EcError::RecvTimeout
    }
    Err(@hal.EcError::LinkDown) => {
      self.log.append(NicEvent::LinkDown)
      raise @hal.EcError::LinkDown
    }
    Err(@hal.EcError::RecvFailed(msg)) => {
      self.log.append(NicEvent::RecvFailed(msg))
      raise @hal.EcError::RecvFailed(msg)
    }
    Err(e) => {
      self.log.append(NicEvent::RecvFailed(e.to_string()))
      raise e
    }
  }
}

///|
pub impl @hal.Nic for RecordingNic with close(self) {
  self.inner.close()
}
