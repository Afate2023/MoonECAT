///|
test "step_result_to_parts ok" {
  let (status, msg, ns) = step_result_to_parts(
    @simulation.SimStepResult::Ok(@simulation.SimTime::from_ns(12345L)),
  )
  assert_eq(status, "ok")
  assert_eq(msg, "")
  assert_eq(ns, 12345L)
}

///|
test "step_result_to_parts terminated" {
  let (status, msg, ns) = step_result_to_parts(
    @simulation.SimStepResult::Terminated("done"),
  )
  assert_eq(status, "terminated")
  assert_eq(msg, "done")
  assert_eq(ns, 0L)
}

///|
test "step_result_to_parts error" {
  let (status, msg, ns) = step_result_to_parts(
    @simulation.SimStepResult::Error("boom"),
  )
  assert_eq(status, "error")
  assert_eq(msg, "boom")
  assert_eq(ns, 0L)
}

///|
struct TerminatingAdapter {
  mut call_count : Int
  terminate_at : Int
}

///|
pub impl @simulation.CoSimAdapter for TerminatingAdapter with init_(
  self,
  _config,
) {
  ignore(self)
}

///|
pub impl @simulation.CoSimAdapter for TerminatingAdapter with write_outputs(
  self,
  _image,
  _slice,
) {
  ignore(self)
}

///|
pub impl @simulation.CoSimAdapter for TerminatingAdapter with step(
  self,
  current,
  dt,
) {
  self.call_count += 1
  if self.call_count >= self.terminate_at {
    @simulation.SimStepResult::Terminated("limit reached")
  } else {
    @simulation.SimStepResult::Ok(current.advance(dt))
  }
}

///|
pub impl @simulation.CoSimAdapter for TerminatingAdapter with read_inputs(
  self,
  _image,
  _slice,
) {
  ignore(self)
}

///|
pub impl @simulation.CoSimAdapter for TerminatingAdapter with shutdown(self) {
  ignore(self)
}

///|
test "HilCycleHook on_post_cycle terminated path" {
  let adapter : TerminatingAdapter = { call_count: 0, terminate_at: 1 }
  let schedule : @simulation.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [],
  }
  let session = HilSession::new(1_000_000L, schedule)
  let hook = HilCycleHook::new(adapter, session)
  let image = @protocol.ProcessImage::new(0, 0)
  let ctx : @protocol.PdoContext = {
    image,
    mappings: [],
    logical_base: 0U,
    logical_size: 0,
    block_lrw: false,
  }
  let snap : CycleSnapshot = {
    cycle: 0L,
    result: None,
    dc_state: Disabled,
    recovery_pending: false,
  }
  let directive = hook.on_post_cycle(snap, ctx)
  assert_eq(directive, StopGraceful)
  assert_true(hook.session.terminated)
  assert_eq(hook.session.termination_reason, "limit reached")
}

///|
struct ErrorAdapter {
  mut call_count : Int
  error_at : Int
}

///|
pub impl @simulation.CoSimAdapter for ErrorAdapter with init_(self, _config) {
  ignore(self)
}

///|
pub impl @simulation.CoSimAdapter for ErrorAdapter with write_outputs(
  self,
  _image,
  _slice,
) {
  ignore(self)
}

///|
pub impl @simulation.CoSimAdapter for ErrorAdapter with step(self, current, dt) {
  self.call_count += 1
  if self.call_count >= self.error_at {
    @simulation.SimStepResult::Error("solver diverged")
  } else {
    @simulation.SimStepResult::Ok(current.advance(dt))
  }
}

///|
pub impl @simulation.CoSimAdapter for ErrorAdapter with read_inputs(
  self,
  _image,
  _slice,
) {
  ignore(self)
}

///|
pub impl @simulation.CoSimAdapter for ErrorAdapter with shutdown(self) {
  ignore(self)
}

///|
test "HilCycleHook on_post_cycle error path" {
  let adapter : ErrorAdapter = { call_count: 0, error_at: 1 }
  let schedule : @simulation.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [],
  }
  let session = HilSession::new(1_000_000L, schedule)
  let hook = HilCycleHook::new(adapter, session)
  let image = @protocol.ProcessImage::new(0, 0)
  let ctx : @protocol.PdoContext = {
    image,
    mappings: [],
    logical_base: 0U,
    logical_size: 0,
    block_lrw: false,
  }
  let snap : CycleSnapshot = {
    cycle: 0L,
    result: None,
    dc_state: Disabled,
    recovery_pending: false,
  }
  let directive = hook.on_post_cycle(snap, ctx)
  assert_eq(directive, StopGraceful)
  assert_true(hook.session.terminated)
  assert_eq(hook.session.termination_reason, "solver diverged")
}
