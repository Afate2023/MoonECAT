///|
/// Structured run-loop progress snapshot emitted during long-running execution.
pub(all) struct RunProgress {
  cycles_completed : Int64
  cycles_ok : Int
  cycles_requested : Int?
  until_fault : Bool
  cycle_period_ns : Int64
  output_period_ns : Int
  telemetry : Telemetry
  consecutive_timeouts : Int
} derive(Debug)

///|
/// RunProgressSink receives structured run-loop progress events.
pub(open) trait RunProgressSink {
  emit(Self, RunProgress) -> Unit
}

///|
/// Default no-op sink for library callers that do not need progress events.
pub struct NullRunProgressSink {
  _unused : Unit
}

///|
pub fn NullRunProgressSink::new() -> NullRunProgressSink {
  { _unused: () }
}

///|
pub impl RunProgressSink for NullRunProgressSink with emit(self, progress) {
  ignore(self)
  ignore(progress)
}
