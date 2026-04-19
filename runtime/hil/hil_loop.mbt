///|
/// HIL (Hardware-in-the-Loop) communication closed-loop PoC.
///
/// This module wires CycleHook + CoSimAdapter + TaskSchedule into a
/// concrete, testable closed-loop configuration.
///
/// Architecture:
///   Runtime.run_cycle
///       ↓ on_pre_cycle
///   HilCycleHook
///       → CoSimAdapter.read_inputs (plant → EtherCAT inputs from prev cycle)
///       → tasks_due_at_cycle → for each task: controller logic
///       → CoSimAdapter.write_outputs (EtherCAT outputs → plant)
///       ↓ PDO exchange
///       ↓ on_post_cycle
///   HilCycleHook
///       → CoSimAdapter.step(dt)
///       → verdict / telemetry collection

///|
/// HilSession holds the state for one HIL closed-loop run.
pub(all) struct HilSession {
  /// The co-simulation adapter (plant model).
  mut sim_time : @simulation.SimTime
  /// Cycle period in nanoseconds (from MasterConfig).
  cycle_period_ns : Int64
  /// Task schedule for multi-rate execution.
  schedule : @simulation.TaskSchedule
  /// Accumulated step results for post-analysis.
  step_log : Array[@simulation.SimStepResult]
  /// Whether the session has been terminated by the plant model.
  mut terminated : Bool
  /// Termination reason, if any.
  mut termination_reason : String
}

///|
pub fn HilSession::new(
  cycle_period_ns : Int64,
  schedule : @simulation.TaskSchedule,
) -> HilSession {
  {
    sim_time: @simulation.SimTime::zero(),
    cycle_period_ns,
    schedule,
    step_log: [],
    terminated: false,
    termination_reason: "",
  }
}

///|
/// HilCycleHook — CycleHook implementation that drives a CoSimAdapter.
///
/// Generic over `A : @simulation.CoSimAdapter` so the plant model is monomorphized
/// into the hook → zero dispatch overhead in the PDO hot path.
pub(all) struct HilCycleHook[A] {
  adapter : A
  session : HilSession
}

///|
pub fn[A] HilCycleHook::new(
  adapter : A,
  session : HilSession,
) -> HilCycleHook[A] {
  { adapter, session }
}

///|
pub impl[A : @simulation.CoSimAdapter] CycleHook for HilCycleHook[A] with on_pre_cycle(
  self,
  snap,
  ctx,
) {
  if self.session.terminated {
    return StopGraceful
  }
  // Determine which tasks are due this cycle
  let due = @simulation.tasks_due_at_cycle(self.session.schedule, snap.cycle)
  // For each due task, write outputs from adapter into PI
  for task in due {
    A::write_outputs(self.adapter, ctx.image, task.slice)
  }
  Continue
}

///|
pub impl[A : @simulation.CoSimAdapter] CycleHook for HilCycleHook[A] with on_post_cycle(
  self,
  _snap,
  ctx,
) {
  if self.session.terminated {
    return StopGraceful
  }
  // Read inputs from PI into adapter
  for task in self.session.schedule.tasks {
    A::read_inputs(self.adapter, ctx.image, task.slice)
  }
  // Advance the plant model by one cycle period
  let result = A::step(
    self.adapter,
    self.session.sim_time,
    self.session.cycle_period_ns,
  )
  self.session.step_log.push(result)
  match result {
    @simulation.SimStepResult::Ok(new_time) => {
      self.session.sim_time = new_time
      Continue
    }
    @simulation.SimStepResult::Terminated(reason) => {
      self.session.terminated = true
      self.session.termination_reason = reason
      StopGraceful
    }
    @simulation.SimStepResult::Error(reason) => {
      self.session.terminated = true
      self.session.termination_reason = reason
      StopGraceful
    }
  }
}

///|
pub impl[A : @simulation.CoSimAdapter] CycleHook for HilCycleHook[A] with on_fault(
  self,
  _snap,
  _err,
) {
  ignore(self)
  Continue
}

///|
/// Get the current simulation time from the HIL session.
pub fn HilSession::get_sim_time(self : HilSession) -> @simulation.SimTime {
  self.sim_time
}

///|
/// Check if the HIL session has been terminated.
pub fn HilSession::is_terminated(self : HilSession) -> Bool {
  self.terminated
}

///|
/// Get the termination reason.
pub fn HilSession::get_termination_reason(self : HilSession) -> String {
  self.termination_reason
}

///|
/// Get the number of simulation steps completed.
pub fn HilSession::step_count(self : HilSession) -> Int {
  self.step_log.length()
}
