///|
/// Runtime scheduler: unified cyclic loop driving PDO exchange,
/// ESM management, timeout governance, and diagnostic collection.

///|
/// CycleResult holds the outcome of one PDO cycle.
pub(all) struct CycleResult {
  /// Working counter from the PDO exchange.
  wkc : UInt
  /// Expected working counter (sum of all mapped slaves).
  expected_wkc : UInt
  /// Whether the cycle succeeded (wkc >= expected_wkc).
  ok : Bool
} derive(Eq, Show)

///|
/// DC (Distributed Clock) synchronization state placeholder.
pub(all) enum DcState {
  /// DC not active.
  Disabled
  /// DC initializing: offsets being measured.
  Measuring
  /// DC synchronized: PLL locked.
  Locked
  /// DC error: PLL lost sync.
  Drifting(Int64)
} derive(Show)

///|
/// Runtime orchestrator: manages the full lifecycle from scan to cyclic PDO.
pub(all) struct Runtime {
  /// Current state of the runtime.
  mut state : RuntimeState
  /// Telemetry counters.
  telemetry : Telemetry
  /// Master configuration.
  config : @hal.MasterConfig
  /// PDO context for cyclic exchange.
  mut pdo_ctx : @protocol.PdoContext?
  /// Expected working counter per cycle.
  mut expected_wkc : UInt
  /// Number of consecutive WKC errors before triggering recovery.
  max_wkc_errors : Int
  /// Current consecutive WKC error count.
  mut consecutive_wkc_errors : Int
  /// Number of consecutive receive timeouts before triggering recovery.
  mut max_consecutive_timeouts : Int
  /// Current consecutive receive timeout count.
  mut consecutive_timeouts : Int
  /// DC synchronization state.
  mut dc_state : DcState
  /// Reference station for FRMW drift compensation.
  mut dc_reference_station : UInt?
  /// DC station set used for runtime delay re-estimation.
  mut dc_stations : Array[UInt]
  /// Per-cycle counter for periodic delay re-estimation.
  mut dc_cycle_counter : Int
} derive(Show)

///|
pub fn Runtime::new(config : @hal.MasterConfig) -> Runtime {
  {
    state: Idle,
    telemetry: Telemetry::new(),
    config,
    pdo_ctx: None,
    expected_wkc: 0U,
    max_wkc_errors: 5,
    consecutive_wkc_errors: 0,
    max_consecutive_timeouts: 5,
    consecutive_timeouts: 0,
    dc_state: Disabled,
    dc_reference_station: None,
    dc_stations: [],
    dc_cycle_counter: 0,
  }
}

///|
/// Configure the threshold for consecutive receive timeouts.
pub fn Runtime::set_timeout_threshold(self : Runtime, threshold : Int) -> Unit {
  self.max_consecutive_timeouts = if threshold > 0 { threshold } else { 1 }
}

///|
/// Initialize distributed clocks for the configured station list.
/// Returns true when DC was initialized and locked.
pub fn[N : @hal.Nic] Runtime::init_dc(
  self : Runtime,
  nic : N,
  stations : Array[UInt],
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
  if not(self.config.dc_enabled) {
    self.dc_state = Disabled
    self.dc_reference_station = None
    self.dc_stations = []
    return false
  }
  if stations.length() == 0 {
    self.dc_state = Disabled
    self.dc_reference_station = None
    self.dc_stations = []
    return false
  }
  self.dc_state = Measuring
  let init = @protocol.dc_configure_linear(
    nic,
    stations,
    self.config.cycle_period_ns.to_int().reinterpret_as_uint(),
    timeout,
    static_sync_iterations=200,
  )
  match init {
    Some(info) => {
      self.dc_reference_station = Some(info.reference_station)
      self.dc_stations = stations
      self.dc_cycle_counter = 0
      self.dc_state = Locked
      true
    }
    None => {
      self.dc_reference_station = None
      self.dc_stations = []
      self.dc_state = Disabled
      false
    }
  }
}

///|
/// Set the PDO context and expected WKC for cyclic operation.
pub fn Runtime::configure_pdo(
  self : Runtime,
  ctx : @protocol.PdoContext,
  expected_wkc : UInt,
) -> Unit {
  self.pdo_ctx = Some(ctx)
  self.expected_wkc = expected_wkc
}

///|
/// Transition the runtime state machine.
pub fn Runtime::set_state(self : Runtime, new_state : RuntimeState) -> Unit {
  self.state = new_state
}

///|
/// Execute one PDO cycle in the runtime loop.
/// Updates telemetry and tracks consecutive errors.
pub fn[N : @hal.Nic] Runtime::run_cycle(
  self : Runtime,
  nic : N,
  timeout : @hal.Duration,
) -> CycleResult raise @hal.EcError {
  guard self.pdo_ctx is Some(ctx) else {
    raise @hal.EcError::Internal("PDO context not configured")
  }
  self.telemetry.cycles = self.telemetry.cycles + 1L
  self.telemetry.tx_frames = self.telemetry.tx_frames + 1L
  // FRMW drift compensation frame before PDO cycle when DC is active.
  if self.config.dc_enabled {
    match self.dc_reference_station {
      Some(station) =>
        @protocol.dc_compensate_cycle(nic, station, timeout) catch {
          _ => self.dc_state = Drifting(1L)
        }
      None => ()
    }
    self.dc_cycle_counter = self.dc_cycle_counter + 1
    if self.dc_cycle_counter >= 100 {
      self.dc_cycle_counter = 0
      match self.dc_reference_station {
        Some(station) =>
          if self.dc_stations.length() > 0 {
            @protocol.dc_reestimate_propagation_delays(
              nic,
              station,
              self.dc_stations,
              timeout,
            ) catch {
              _ => self.dc_state = Drifting(2L)
            }
            self.telemetry.dc_delay_updates = self.telemetry.dc_delay_updates +
              1L
          }
        None => ()
      }
    }
  }
  let pdo_result = @protocol.pdo_exchange_result(nic, ctx, timeout)
  let wkc = pdo_result.wkc
  self.telemetry.rx_frames = self.telemetry.rx_frames + 1L
  if pdo_result.irq != 0U {
    self.telemetry.irq_events = self.telemetry.irq_events + 1L
  }
  self.consecutive_timeouts = 0
  let ok = wkc >= self.expected_wkc
  if ok {
    self.consecutive_wkc_errors = 0
  } else {
    self.consecutive_wkc_errors = self.consecutive_wkc_errors + 1
    self.telemetry.wkc_errors = self.telemetry.wkc_errors + 1L
  }
  { wkc, expected_wkc: self.expected_wkc, ok }
}

///|
/// Check if the runtime needs recovery due to excessive WKC errors.
pub fn Runtime::needs_recovery(self : Runtime) -> Bool {
  self.consecutive_wkc_errors >= self.max_wkc_errors ||
  self.consecutive_timeouts >= self.max_consecutive_timeouts ||
  self.dc_state is Drifting(_)
}

///|
/// Reset the WKC error counter after recovery.
pub fn Runtime::reset_error_counter(self : Runtime) -> Unit {
  self.consecutive_wkc_errors = 0
  self.consecutive_timeouts = 0
}

///|
/// Record a timeout event in telemetry.
pub fn Runtime::record_timeout(self : Runtime) -> Unit {
  self.telemetry.timeouts = self.telemetry.timeouts + 1L
  self.consecutive_timeouts = self.consecutive_timeouts + 1
}

///|
/// Record a retry event in telemetry.
pub fn Runtime::record_retry(self : Runtime) -> Unit {
  self.telemetry.retries = self.telemetry.retries + 1L
}

///|
/// Get a snapshot of the current telemetry.
pub fn Runtime::get_telemetry(self : Runtime) -> Telemetry {
  {
    cycles: self.telemetry.cycles,
    tx_frames: self.telemetry.tx_frames,
    rx_frames: self.telemetry.rx_frames,
    timeouts: self.telemetry.timeouts,
    retries: self.telemetry.retries,
    wkc_errors: self.telemetry.wkc_errors,
    irq_events: self.telemetry.irq_events,
    dc_delay_updates: self.telemetry.dc_delay_updates,
  }
}

///|
/// Run N PDO cycles. Returns the number of successful cycles.
pub fn[N : @hal.Nic] Runtime::run_cycles(
  self : Runtime,
  nic : N,
  count : Int,
  timeout : @hal.Duration,
) -> Int raise @hal.EcError {
  self.run_cycles_with_reporting(nic, count, timeout, None)
}

///|
/// Run N PDO cycles and optionally emit progress snapshots.
pub fn[N : @hal.Nic] Runtime::run_cycles_with_reporting(
  self : Runtime,
  nic : N,
  count : Int,
  timeout : @hal.Duration,
  progress_every_cycles : Int?,
) -> Int raise @hal.EcError {
  let mut success = 0
  for _i = 0; _i < count; _i = _i + 1 {
    let result = self.run_cycle(nic, timeout) catch {
      @hal.EcError::RecvTimeout => {
        self.record_timeout()
        emit_runtime_progress(self, success, progress_every_cycles)
        if self.needs_recovery() {
          self.set_state(Error(@hal.EcError::RecvTimeout))
          break
        }
        continue
      }
      err => raise err
    }
    if result.ok {
      success = success + 1
    }
    emit_runtime_progress(self, success, progress_every_cycles)
    if self.needs_recovery() {
      match self.dc_state {
        Drifting(delta_ns) =>
          self.set_state(
            Error(
              @hal.EcError::Internal(
                "dc drift detected: " + delta_ns.to_string(),
              ),
            ),
          )
        _ =>
          if self.consecutive_timeouts >= self.max_consecutive_timeouts {
            self.set_state(Error(@hal.EcError::RecvTimeout))
          } else {
            self.set_state(
              Error(
                @hal.EcError::UnexpectedWkc(
                  expected=self.expected_wkc.reinterpret_as_int(),
                  actual=0,
                ),
              ),
            )
          }
      }
      break
    }
  }
  success
}

///|
/// Run PDO cycles until a runtime recovery condition occurs.
pub fn[N : @hal.Nic] Runtime::run_until_fault(
  self : Runtime,
  nic : N,
  timeout : @hal.Duration,
) -> Int raise @hal.EcError {
  self.run_until_fault_with_reporting(nic, timeout, None)
}

///|
/// Run PDO cycles until a runtime recovery condition occurs and optionally
/// emit progress snapshots.
pub fn[N : @hal.Nic] Runtime::run_until_fault_with_reporting(
  self : Runtime,
  nic : N,
  timeout : @hal.Duration,
  progress_every_cycles : Int?,
) -> Int raise @hal.EcError {
  let mut success = 0
  while true {
    let result = self.run_cycle(nic, timeout) catch {
      @hal.EcError::RecvTimeout => {
        self.record_timeout()
        emit_runtime_progress(self, success, progress_every_cycles)
        if self.needs_recovery() {
          self.set_state(Error(@hal.EcError::RecvTimeout))
          break
        }
        continue
      }
      err => raise err
    }
    if result.ok {
      success = success + 1
    }
    emit_runtime_progress(self, success, progress_every_cycles)
    if self.needs_recovery() {
      match self.dc_state {
        Drifting(delta_ns) =>
          self.set_state(
            Error(
              @hal.EcError::Internal(
                "dc drift detected: " + delta_ns.to_string(),
              ),
            ),
          )
        _ =>
          if self.consecutive_timeouts >= self.max_consecutive_timeouts {
            self.set_state(Error(@hal.EcError::RecvTimeout))
          } else {
            self.set_state(
              Error(
                @hal.EcError::UnexpectedWkc(
                  expected=self.expected_wkc.reinterpret_as_int(),
                  actual=0,
                ),
              ),
            )
          }
      }
      break
    }
  }
  success
}

///|
fn emit_runtime_progress(
  runtime : Runtime,
  success : Int,
  progress_every_cycles : Int?,
) -> Unit {
  match progress_every_cycles {
    Some(every) =>
      if every > 0 && runtime.telemetry.cycles % every.to_int64() == 0L {
        println(
          "run progress: cycles=" +
          runtime.telemetry.cycles.to_string() +
          " ok=" +
          success.to_string() +
          " timeouts=" +
          runtime.telemetry.timeouts.to_string() +
          " consecutive_timeouts=" +
          runtime.consecutive_timeouts.to_string() +
          " wkc_errors=" +
          runtime.telemetry.wkc_errors.to_string(),
        )
      }
    _ => ()
  }
}
