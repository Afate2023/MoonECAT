///|
/// Timebase contract for MCU + Linux cooperative HIL systems.
///
/// This module defines the clock discipline interface between:
///   - A hard-real-time MCU domain (RZ/N2L, HPM6E00, etc.)
///   - A soft-real-time Linux domain (ARM Cortex-A, x86, etc.)
///   - An optional FPGA/PRU domain (absolute-precision event generator)
///
/// Design principles:
///   - Each clock domain is an independent Timebase implementation
///   - Cross-domain synchronization uses explicit epoch + drift measurement
///   - No implicit shared mutable state between domains
///   - Lock-free event passing at domain boundaries
///
/// Clock hierarchy:
///   FPGA/PRU (if present)  →  Reference timebase
///   MCU (EtherCAT master)  →  Primary execution timebase
///   Linux (supervisor)     →  Observation/logging timebase

///|
/// ClockDomain identifies the source of a timestamp.
pub(all) enum ClockDomain {
  /// Hard-real-time MCU domain (TCM/ILM, sub-microsecond jitter).
  Mcu
  /// Soft-real-time Linux domain (kernel timer, microsecond-class jitter).
  Linux
  /// FPGA/PRU domain (cycle-exact, no jitter).
  Fpga
  /// Simulated/virtual domain (deterministic replay).
  Virtual
} derive(Eq, Debug)

///|
/// DomainTimestamp pairs a raw nanosecond value with its clock domain.
pub(all) struct DomainTimestamp {
  domain : ClockDomain
  ns : Int64
} derive(Eq, Debug)

///|
/// Timebase — the trait each clock domain implements.
///
/// All methods are non-blocking and must execute in bounded time.
/// MCU implementations typically read a hardware timer register.
/// Linux implementations use clock_gettime(CLOCK_MONOTONIC).
/// Virtual implementations advance from an explicit schedule.
pub(open) trait Timebase {
  /// Return the clock domain identifier.
  domain(Self) -> ClockDomain

  /// Read the current time in this domain.
  now_ns(Self) -> Int64

  /// Return the timer resolution in nanoseconds.
  /// MCU: typically 1-10 ns. Linux: typically 1000 ns.
  resolution_ns(Self) -> Int64

  /// Monotonicity guarantee: returns true if this timebase never goes backward.
  is_monotonic(Self) -> Bool
}

///|
/// TimebaseSync captures the synchronization state between two clock domains.
pub(all) struct TimebaseSync {
  /// The reference (master) clock domain.
  reference_domain : ClockDomain
  /// The local (slave) clock domain.
  local_domain : ClockDomain
  /// Measured offset: local_ns = reference_ns + offset_ns.
  mut offset_ns : Int64
  /// Estimated drift rate in ppb (parts per billion).
  /// Positive = local runs faster than reference.
  mut drift_ppb : Int64
  /// Number of synchronization samples taken.
  mut sync_count : Int64
  /// Nanosecond timestamp of last sync measurement (in reference domain).
  mut last_sync_ns : Int64
} derive(Eq, Debug)

///|
pub fn TimebaseSync::new(
  reference_domain : ClockDomain,
  local_domain : ClockDomain,
) -> TimebaseSync {
  {
    reference_domain,
    local_domain,
    offset_ns: 0L,
    drift_ppb: 0L,
    sync_count: 0L,
    last_sync_ns: 0L,
  }
}

///|
/// Update the sync state with a new measurement pair.
pub fn TimebaseSync::update(
  self : TimebaseSync,
  reference_ns : Int64,
  local_ns : Int64,
) -> Unit {
  let new_offset = local_ns - reference_ns
  if self.sync_count > 0L && self.last_sync_ns > 0L {
    let dt = reference_ns - self.last_sync_ns
    if dt > 0L {
      let offset_change = new_offset - self.offset_ns
      // drift_ppb = (offset_change / dt) * 1e9
      self.drift_ppb = offset_change * 1_000_000_000L / dt
    }
  }
  self.offset_ns = new_offset
  self.last_sync_ns = reference_ns
  self.sync_count = self.sync_count + 1L
}

///|
/// Convert a reference-domain timestamp to the local domain.
pub fn TimebaseSync::to_local(
  self : TimebaseSync,
  reference_ns : Int64,
) -> Int64 {
  reference_ns + self.offset_ns
}

///|
/// Convert a local-domain timestamp to the reference domain.
pub fn TimebaseSync::to_reference(
  self : TimebaseSync,
  local_ns : Int64,
) -> Int64 {
  local_ns - self.offset_ns
}

///|
/// VirtualTimebase — deterministic timebase for testing and replay.
/// Time only advances when explicitly stepped.
pub struct VirtualTimebase {
  mut current_ns : Int64
}

///|
pub fn VirtualTimebase::new() -> VirtualTimebase {
  { current_ns: 0L }
}

///|
pub fn VirtualTimebase::set(self : VirtualTimebase, ns : Int64) -> Unit {
  self.current_ns = ns
}

///|
pub fn VirtualTimebase::advance(
  self : VirtualTimebase,
  delta_ns : Int64,
) -> Unit {
  self.current_ns = self.current_ns + delta_ns
}

///|
pub impl Timebase for VirtualTimebase with domain(self) {
  ignore(self)
  Virtual
}

///|
pub impl Timebase for VirtualTimebase with now_ns(self) {
  self.current_ns
}

///|
pub impl Timebase for VirtualTimebase with resolution_ns(self) {
  ignore(self)
  1L
}

///|
pub impl Timebase for VirtualTimebase with is_monotonic(self) {
  ignore(self)
  true
}

///|
/// CycleTimingReport captures per-cycle timing quality metrics.
pub(all) struct CycleTimingReport {
  /// Nominal cycle period in nanoseconds.
  nominal_period_ns : Int64
  /// Measured cycle period in nanoseconds (wall-clock delta).
  actual_period_ns : Int64
  /// Jitter = |actual - nominal| in nanoseconds.
  jitter_ns : Int64
  /// Which clock domain produced the measurement.
  domain : ClockDomain
} derive(Eq, Debug)

///|
/// Compute a CycleTimingReport from two consecutive timestamps.
pub fn cycle_timing_report(
  nominal_period_ns : Int64,
  prev_ns : Int64,
  curr_ns : Int64,
  domain : ClockDomain,
) -> CycleTimingReport {
  let actual = curr_ns - prev_ns
  let jitter = if actual > nominal_period_ns {
    actual - nominal_period_ns
  } else {
    nominal_period_ns - actual
  }
  { nominal_period_ns, actual_period_ns: actual, jitter_ns: jitter, domain }
}
