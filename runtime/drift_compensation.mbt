///|
/// Online drift compensation for TimebaseSync.
///
/// C-13: Extends TimebaseSync with online drift compensation using
/// a simple PI (Proportional-Integral) controller that continuously
/// adjusts the offset to minimize synchronization error between
/// MCU and Linux clock domains.
///
/// Algorithm:
///   1. Measure reference_ns and local_ns at each sync point
///   2. Compute instantaneous error = (local_ns - reference_ns) - target_offset
///   3. Apply PI correction: correction = Kp * error + Ki * integral_error
///   4. Adjust offset_ns by the correction
///
/// Convergence: Targets ≤1μs steady-state error after ~100 sync updates.

///|
/// PI controller gains for drift compensation.
pub(all) struct DriftCompensationGains {
  /// Proportional gain (dimensionless, typical: 0.1 – 0.5).
  /// Maps to fixed-point: kp_num / kp_den.
  kp_num : Int64
  kp_den : Int64
  /// Integral gain (dimensionless, typical: 0.01 – 0.05).
  /// Maps to fixed-point: ki_num / ki_den.
  ki_num : Int64
  ki_den : Int64
} derive(Eq, Show)

///|
pub fn DriftCompensationGains::default() -> DriftCompensationGains {
  // Kp = 0.25 (1/4), Ki = 0.02 (1/50)
  { kp_num: 1L, kp_den: 4L, ki_num: 1L, ki_den: 50L }
}

///|
pub fn DriftCompensationGains::aggressive() -> DriftCompensationGains {
  // Kp = 0.5 (1/2), Ki = 0.05 (1/20) — faster convergence, more jitter
  { kp_num: 1L, kp_den: 2L, ki_num: 1L, ki_den: 20L }
}

///|
pub fn DriftCompensationGains::conservative() -> DriftCompensationGains {
  // Kp = 0.1 (1/10), Ki = 0.01 (1/100) — slow convergence, less jitter
  { kp_num: 1L, kp_den: 10L, ki_num: 1L, ki_den: 100L }
}

///|
/// DriftCompensator — online PI-based drift compensation state.
pub(all) struct DriftCompensator {
  gains : DriftCompensationGains
  /// Target offset (what we want local - reference to be).
  target_offset_ns : Int64
  /// Accumulated integral error (in ns).
  mut integral_error_ns : Int64
  /// Last measured error (in ns).
  mut last_error_ns : Int64
  /// Total correction applied (for diagnostics).
  mut total_correction_ns : Int64
  /// Number of updates.
  mut update_count : Int64
  /// Maximum allowed integral error (anti-windup, in ns).
  max_integral_ns : Int64
  /// Whether compensation is active.
  mut active : Bool
} derive(Show)

///|
pub fn DriftCompensator::new(
  gains? : DriftCompensationGains = DriftCompensationGains::default(),
  target_offset_ns? : Int64 = 0L,
  max_integral_ns? : Int64 = 1_000_000L,
) -> DriftCompensator {
  {
    gains,
    target_offset_ns,
    integral_error_ns: 0L,
    last_error_ns: 0L,
    total_correction_ns: 0L,
    update_count: 0L,
    max_integral_ns,
    active: true,
  }
}

///|
/// Compute the correction for the current sync measurement
/// and update the given TimebaseSync's offset.
///
/// Returns the applied correction in nanoseconds.
pub fn DriftCompensator::compensate(
  self : DriftCompensator,
  sync : TimebaseSync,
  reference_ns : Int64,
  local_ns : Int64,
) -> Int64 {
  if !self.active {
    sync.update(reference_ns, local_ns)
    return 0L
  }
  // Compute current error
  let measured_offset = local_ns - reference_ns
  let error = measured_offset - self.target_offset_ns
  // Update integral with anti-windup clamping
  self.integral_error_ns = self.integral_error_ns + error
  if self.integral_error_ns > self.max_integral_ns {
    self.integral_error_ns = self.max_integral_ns
  } else if self.integral_error_ns < -self.max_integral_ns {
    self.integral_error_ns = -self.max_integral_ns
  }
  // PI correction (fixed-point arithmetic)
  let p_term = error * self.gains.kp_num / self.gains.kp_den
  let i_term = self.integral_error_ns * self.gains.ki_num / self.gains.ki_den
  let correction = p_term + i_term
  // Apply correction: adjust the local timestamp before updating sync
  let corrected_local = local_ns - correction
  sync.update(reference_ns, corrected_local)
  self.last_error_ns = error
  self.total_correction_ns = self.total_correction_ns + correction
  self.update_count = self.update_count + 1L
  correction
}

///|
/// Reset the compensator state (e.g., after a large discontinuity).
pub fn DriftCompensator::reset(self : DriftCompensator) -> Unit {
  self.integral_error_ns = 0L
  self.last_error_ns = 0L
  self.total_correction_ns = 0L
  self.update_count = 0L
}

///|
/// DriftCompensationReport — diagnostic snapshot.
pub(all) struct DriftCompensationReport {
  update_count : Int64
  last_error_ns : Int64
  integral_error_ns : Int64
  total_correction_ns : Int64
  estimated_drift_ppb : Int64
  converged : Bool
} derive(Show)

///|
/// Generate a diagnostic report of the current compensation state.
pub fn DriftCompensator::report(
  self : DriftCompensator,
  sync : TimebaseSync,
) -> DriftCompensationReport {
  let abs_error = if self.last_error_ns < 0L {
    -self.last_error_ns
  } else {
    self.last_error_ns
  }
  {
    update_count: self.update_count,
    last_error_ns: self.last_error_ns,
    integral_error_ns: self.integral_error_ns,
    total_correction_ns: self.total_correction_ns,
    estimated_drift_ppb: sync.drift_ppb,
    converged: self.update_count > 10L && abs_error <= 1000L,
  }
}
