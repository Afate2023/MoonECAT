///|
/// RunMode controls how the cyclic loop synchronizes.
pub(all) enum RunMode {
  /// Free-running: no DC synchronization.
  FreeRun
  /// DC-synchronized: locks to distributed clock.
  DcSync
} derive(Eq, Show)

///|
/// RuntimeState tracks the overall master state.
pub(all) enum RuntimeState {
  Idle
  Scanning
  Configuring
  Running(RunMode)
  Stopping
  Error(@hal.EcError)
} derive(Show)

///|
/// Telemetry holds runtime diagnostic counters.
pub(all) struct Telemetry {
  mut cycles : Int64
  mut tx_frames : Int64
  mut rx_frames : Int64
  mut timeouts : Int64
  mut retries : Int64
  mut wkc_errors : Int64
  mut irq_events : Int64
  mut dc_delay_updates : Int64
  mut emergency_events : Int64
} derive(Eq, Show)

///|
pub fn Telemetry::new() -> Telemetry {
  {
    cycles: 0L,
    tx_frames: 0L,
    rx_frames: 0L,
    timeouts: 0L,
    retries: 0L,
    wkc_errors: 0L,
    irq_events: 0L,
    dc_delay_updates: 0L,
    emergency_events: 0L,
  }
}

///|
pub fn Telemetry::reset(self : Telemetry) -> Unit {
  self.cycles = 0L
  self.tx_frames = 0L
  self.rx_frames = 0L
  self.timeouts = 0L
  self.retries = 0L
  self.wkc_errors = 0L
  self.irq_events = 0L
  self.dc_delay_updates = 0L
  self.emergency_events = 0L
}
