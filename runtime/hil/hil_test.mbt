///|
test "hil facade exposes session summary" {
  let schedule : @simulation.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "axis",
        priority: 0,
        cycle_divisor: 1,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 4,
        },
      },
    ],
  }
  let session = @hil.HilSession::new(1_000_000L, schedule)
  session.step_log.push(
    @simulation.SimStepResult::Ok(@simulation.SimTime::from_ns(1_000_000L)),
  )
  session.step_log.push(@simulation.SimStepResult::Error("solver diverged"))
  let summary = @hil.hil_session_summary(session)
  inspect(summary.total_steps, content="2")
  inspect(summary.error_steps, content="1")
}

///|
test "hil facade exposes session json export" {
  let schedule : @simulation.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "axis",
        priority: 0,
        cycle_divisor: 1,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 4,
        },
      },
    ],
  }
  let session = @hil.HilSession::new(1_000_000L, schedule)
  session.step_log.push(
    @simulation.SimStepResult::Ok(@simulation.SimTime::from_ns(1_000_000L)),
  )
  let json = @hil.hil_session_to_json(session)
  inspect(json.contains("\"axis\""), content="true")
  inspect(json.contains("\"total_steps\": 1"), content="true")
}
