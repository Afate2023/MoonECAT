///|
test "simulation facade exposes task scheduling" {
  let tasks : Array[@simulation.TaskDescriptor] = [
    {
      name: "fast",
      priority: 0,
      cycle_divisor: 1,
      slice: {
        output_offset: 0,
        output_length: 2,
        input_offset: 0,
        input_length: 2,
      },
    },
    {
      name: "slow",
      priority: 1,
      cycle_divisor: 2,
      slice: {
        output_offset: 2,
        output_length: 2,
        input_offset: 2,
        input_length: 2,
      },
    },
  ]
  guard @simulation.build_task_schedule(1_000_000L, tasks) is Some(schedule) else {
    fail("expected schedule")
  }
  let analysis = @simulation.analyze_multi_rate(schedule)
  inspect(analysis.hyperperiod, content="2")
  inspect(@simulation.validate_multi_rate(schedule).length(), content="0")
}

///|
test "simulation facade exposes timebase drift helpers" {
  let sync = @simulation.TimebaseSync::new(Mcu, Linux)
  let compensator = @simulation.DriftCompensator::new()
  let _ = compensator.compensate(sync, 0L, 100L)
  let report = compensator.report(sync)
  inspect(report.update_count, content="1")

  let clock = @simulation.VirtualTimebase::new()
  clock.set(10L)
  clock.advance(5L)
  let timing = @simulation.cycle_timing_report(5L, 10L, 15L, Virtual)
  inspect(timing.jitter_ns, content="0")
}

///|
test "simulation facade exposes bridge codec" {
  let encoded = @simulation.encode_step_request(
    1L,
    2L,
    Bytes::make(2, b'\xAA'),
    2,
  )
  let (status, inputs) = @simulation.decode_step_response(
    Bytes::makei(3, fn(i) { if i == 0 { b'\x00' } else { b'\x11' } }),
    2,
  )
  inspect(encoded.length(), content="18")
  inspect(status, content="b'\\x00'")
  inspect(inputs[0], content="b'\\x11'")
}
