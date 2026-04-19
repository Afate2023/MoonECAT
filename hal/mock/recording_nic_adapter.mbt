///|
/// RecordingNicAdapter wraps any concrete `@hal.Nic` implementation and records
/// every send/recv outcome into a `NicEventLog`. Unlike `RecordingNic` which is
/// hard-wired to `VirtualNic`, this adapter is generic and therefore usable as
/// the recording boundary on top of `NativeNic` for real-device traces.
///
/// The captured log can be exported via `to_ndjson` / `to_ndjson_with_header`
/// and later replayed through `ReplayNic::from_log`.
pub(all) struct RecordingNicAdapter[N] {
  inner : N
  log : NicEventLog
}

///|
pub fn[N] RecordingNicAdapter::wrap(inner : N) -> RecordingNicAdapter[N] {
  { inner, log: NicEventLog::new() }
}

///|
pub fn[N] RecordingNicAdapter::get_log(
  self : RecordingNicAdapter[N],
) -> NicEventLog {
  self.log
}

///|
pub impl[N : @hal.Nic] @hal.Nic for RecordingNicAdapter[N] with open_(name) {
  let inner = N::open_(name)
  RecordingNicAdapter::wrap(inner)
}

///|
pub impl[N : @hal.Nic] @hal.Nic for RecordingNicAdapter[N] with send(self, data) {
  let result : Result[Int, @hal.EcError] = Ok(N::send(self.inner, data)) catch {
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
pub impl[N : @hal.Nic] @hal.Nic for RecordingNicAdapter[N] with recv(
  self,
  timeout~,
) {
  let result : Result[Bytes, @hal.EcError] = Ok(N::recv(self.inner, timeout~)) catch {
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
pub impl[N : @hal.Nic] @hal.Nic for RecordingNicAdapter[N] with close(self) {
  N::close(self.inner)
}
