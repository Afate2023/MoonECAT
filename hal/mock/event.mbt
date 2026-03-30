///|
/// NicEvent represents a single observable event at the Nic boundary.
/// Recording a sequence of NicEvents enables deterministic replay:
/// State' = f(State, Event).
pub(all) enum NicEvent {
  Sent(Bytes, Int)
  Received(Bytes)
  RecvTimeout
  SendFailed(String)
} derive(Eq, Show)

///|
/// NicEventLog is an ordered sequence of NicEvents captured during
/// a Nic session. Pass to ReplayNic to reproduce the session.
pub(all) struct NicEventLog {
  events : Array[NicEvent]
} derive(Show)

///|
pub fn NicEventLog::new() -> NicEventLog {
  { events: [] }
}

///|
pub fn NicEventLog::append(self : NicEventLog, event : NicEvent) -> Unit {
  self.events.push(event)
}

///|
pub fn NicEventLog::len(self : NicEventLog) -> Int {
  self.events.length()
}
