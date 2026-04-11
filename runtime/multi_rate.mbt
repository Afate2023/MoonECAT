///|
/// Multi-rate TaskSchedule validation and analysis.
///
/// C-12: Validates and analyzes multi-rate task schedules with mixed
/// cycle_divisor values (2/4/8 etc.) to ensure deterministic behavior
/// and detect scheduling conflicts before real-time execution.
///
/// Key validations:
/// - Hyperperiod calculation (LCM of all cycle_divisors)
/// - Worst-case cycle utilization analysis
/// - Phase alignment check (no two high-priority tasks collide)

///|
/// MultiRateAnalysis — result of analyzing a multi-rate schedule.
pub(all) struct MultiRateAnalysis {
  /// The hyperperiod in base cycles (LCM of all divisors).
  hyperperiod : Int
  /// Maximum number of tasks executing in any single cycle.
  worst_case_tasks_per_cycle : Int
  /// Cycle numbers within the hyperperiod that have peak load.
  peak_cycles : Array[Int]
  /// Whether all divisors are powers of 2 (harmonic schedule).
  is_harmonic : Bool
  /// Total output bytes that could be written in the worst-case cycle.
  worst_case_output_bytes : Int
  /// Total input bytes that could be read in the worst-case cycle.
  worst_case_input_bytes : Int
} derive(Debug)

///|
fn gcd(a : Int, b : Int) -> Int {
  let mut x = if a < 0 { -a } else { a }
  let mut y = if b < 0 { -b } else { b }
  while y != 0 {
    let t = y
    y = x % y
    x = t
  }
  x
}

///|
fn lcm(a : Int, b : Int) -> Int {
  if a == 0 || b == 0 {
    return 0
  }
  let g = gcd(a, b)
  a / g * b
}

///|
/// Analyze a multi-rate TaskSchedule for worst-case behavior.
pub fn analyze_multi_rate(schedule : TaskSchedule) -> MultiRateAnalysis {
  if schedule.tasks.length() == 0 {
    return {
      hyperperiod: 1,
      worst_case_tasks_per_cycle: 0,
      peak_cycles: [],
      is_harmonic: true,
      worst_case_output_bytes: 0,
      worst_case_input_bytes: 0,
    }
  }
  // Compute hyperperiod (LCM of all divisors)
  let mut hp = 1
  for t in schedule.tasks {
    hp = lcm(hp, t.cycle_divisor)
  }
  // Check harmonic (all divisors are powers of 2)
  let is_harmonic = schedule.tasks
    .iter()
    .all(fn(t) {
      let d = t.cycle_divisor
      d > 0 && d.land(d - 1) == 0
    })
  // Simulate one hyperperiod to find worst-case
  let mut worst = 0
  let mut worst_out = 0
  let mut worst_in = 0
  let peaks : Array[Int] = []
  for cycle = 0; cycle < hp; cycle = cycle + 1 {
    let mut count = 0
    let mut out_bytes = 0
    let mut in_bytes = 0
    for t in schedule.tasks {
      if cycle % t.cycle_divisor == 0 {
        count = count + 1
        out_bytes = out_bytes + t.slice.output_length
        in_bytes = in_bytes + t.slice.input_length
      }
    }
    if count > worst {
      worst = count
      worst_out = out_bytes
      worst_in = in_bytes
      peaks.clear()
      peaks.push(cycle)
    } else if count == worst {
      peaks.push(cycle)
      if out_bytes > worst_out {
        worst_out = out_bytes
      }
      if in_bytes > worst_in {
        worst_in = in_bytes
      }
    }
  }
  {
    hyperperiod: hp,
    worst_case_tasks_per_cycle: worst,
    peak_cycles: peaks,
    is_harmonic,
    worst_case_output_bytes: worst_out,
    worst_case_input_bytes: worst_in,
  }
}

///|
/// Validate that a multi-rate schedule is safe for real-time execution.
///
/// Checks:
///   1. All divisors > 0 (already enforced by build_task_schedule)
///   2. Hyperperiod is bounded (≤ max_hyperperiod)
///   3. No cycle exceeds max_tasks_per_cycle
///   4. Total worst-case I/O fits within frame budget
///
/// Returns a list of validation messages (empty = all OK).
pub fn validate_multi_rate(
  schedule : TaskSchedule,
  max_hyperperiod? : Int = 1024,
  max_tasks_per_cycle? : Int = 8,
  max_io_bytes_per_cycle? : Int = 1486,
) -> Array[String] {
  let errors : Array[String] = []
  let analysis = analyze_multi_rate(schedule)
  if analysis.hyperperiod > max_hyperperiod {
    errors.push(
      "Hyperperiod " +
      analysis.hyperperiod.to_string() +
      " exceeds limit " +
      max_hyperperiod.to_string(),
    )
  }
  if analysis.worst_case_tasks_per_cycle > max_tasks_per_cycle {
    errors.push(
      "Peak tasks per cycle " +
      analysis.worst_case_tasks_per_cycle.to_string() +
      " exceeds limit " +
      max_tasks_per_cycle.to_string(),
    )
  }
  let total_io = analysis.worst_case_output_bytes +
    analysis.worst_case_input_bytes
  if total_io > max_io_bytes_per_cycle {
    errors.push(
      "Worst-case I/O " +
      total_io.to_string() +
      " bytes exceeds frame budget " +
      max_io_bytes_per_cycle.to_string(),
    )
  }
  if !analysis.is_harmonic {
    // Warning, not error
    errors.push(
      "Schedule is non-harmonic; consider using power-of-2 divisors for predictability",
    )
  }
  errors
}
