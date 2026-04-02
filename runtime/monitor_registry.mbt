///|
/// Composable monitor registration and user-defined monitor trait (B-11).
///
/// Extends the built-in monitor system with:
///   - MonitorFn type for lightweight function-based monitors
///   - MonitorRegistry for composable monitor registration
///   - Support for user-defined monitors via the same interface

///|
/// MonitorFn — the function signature for a runtime monitor.
/// Each monitor takes a Runtime snapshot and returns a MonitorResult.
pub(all) struct MonitorFn {
  run : (Runtime) -> MonitorResult
}

///|
/// MonitorRegistry manages a composable set of monitors.
/// Both built-in and user-defined monitors are registered uniformly.
pub(all) struct MonitorRegistry {
  monitors : Array[(String, MonitorFn)]
}

///|
pub fn MonitorRegistry::new() -> MonitorRegistry {
  { monitors: [] }
}

///|
/// Create a registry pre-loaded with all built-in monitors.
pub fn MonitorRegistry::with_defaults() -> MonitorRegistry {
  let reg = MonitorRegistry::new()
  reg.register("consecutive_timeouts", {
    run: fn(rt) { monitor_consecutive_timeouts(rt) },
  })
  reg.register("wkc_errors", { run: fn(rt) { monitor_wkc_errors(rt) } })
  reg.register("dc_drift", { run: fn(rt) { monitor_dc_drift(rt) } })
  reg.register("startup_state", { run: fn(rt) { monitor_startup_state(rt) } })
  reg.register("pdo_configured", { run: fn(rt) { monitor_pdo_configured(rt) } })
  reg.register("cycle_success_rate", {
    run: fn(rt) { monitor_cycle_success_rate(rt, 80) },
  })
  reg
}

///|
/// Register a named monitor function.
pub fn MonitorRegistry::register(
  self : MonitorRegistry,
  name : String,
  f : MonitorFn,
) -> Unit {
  self.monitors.push((name, f))
}

///|
/// Remove a monitor by name (for overriding defaults).
pub fn MonitorRegistry::unregister(
  self : MonitorRegistry,
  name : String,
) -> Unit {
  let filtered : Array[(String, MonitorFn)] = []
  for entry in self.monitors {
    if entry.0 != name {
      filtered.push(entry)
    }
  }
  // Replace contents
  self.monitors.clear()
  for entry in filtered {
    self.monitors.push(entry)
  }
}

///|
/// Run all registered monitors and return results with aggregate worst verdict.
pub fn MonitorRegistry::run(
  self : MonitorRegistry,
  rt : Runtime,
) -> (Array[MonitorResult], Verdict) {
  let results : Array[MonitorResult] = []
  for entry in self.monitors {
    let (_, f) = entry
    results.push((f.run)(rt))
  }
  let worst = worst_verdict(results)
  (results, worst)
}

///|
/// Count of registered monitors.
pub fn MonitorRegistry::len(self : MonitorRegistry) -> Int {
  self.monitors.length()
}
