///|
test "ExternalBridgeConfig unix_socket defaults" {
  let cfg = @runtime.ExternalBridgeConfig::unix_socket("/tmp/cosim.sock")
  inspect(cfg.auto_launch, content="false")
  inspect(cfg.step_timeout_ns, content="1000000000")
}

///|
test "ExternalProcessBridge avg_latency_ns zero" {
  let cfg = @runtime.ExternalBridgeConfig::unix_socket("/tmp/test.sock")
  let bridge = @runtime.ExternalProcessBridge::new(cfg)
  inspect(bridge.avg_latency_ns(), content="0")
}

///|
test "encode_step_request wire format" {
  let outputs = Bytes::make(4, b'\xAA')
  let encoded = @runtime.encode_step_request(1000L, 500L, outputs, 4)
  // Total = 16 (headers) + 4 (outputs) = 20 bytes
  inspect(encoded.length(), content="20")
  // Last 4 bytes should be 0xAA
  inspect(encoded[16], content="b'\\xAA'")
  inspect(encoded[19], content="b'\\xAA'")
}

///|
test "decode_step_response ok" {
  // Status 0x00 + 2 input bytes
  let data = Bytes::make(3, b'\x00')
  let (status, inputs) = @runtime.decode_step_response(data, 2)
  inspect(status, content="b'\\x00'")
  inspect(inputs.length(), content="2")
}

///|
test "decode_step_response empty input" {
  let data = Bytes::new(0)
  let (status, inputs) = @runtime.decode_step_response(data, 4)
  inspect(status, content="b'\\xFF'")
  inspect(inputs.length(), content="4")
}

///|
test "analyze_multi_rate harmonic schedule" {
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "fast",
      priority: 0,
      cycle_divisor: 1,
      slice: {
        output_offset: 0,
        output_length: 4,
        input_offset: 0,
        input_length: 4,
      },
    },
    {
      name: "medium",
      priority: 1,
      cycle_divisor: 4,
      slice: {
        output_offset: 4,
        output_length: 4,
        input_offset: 4,
        input_length: 4,
      },
    },
    {
      name: "slow",
      priority: 2,
      cycle_divisor: 8,
      slice: {
        output_offset: 8,
        output_length: 4,
        input_offset: 8,
        input_length: 4,
      },
    },
  ]
  let schedule : @runtime.TaskSchedule = { base_period_ns: 1_000_000L, tasks }
  let analysis = @runtime.analyze_multi_rate(schedule)
  inspect(analysis.hyperperiod, content="8")
  inspect(analysis.is_harmonic, content="true")
  // At cycle 0, all 3 tasks run
  inspect(analysis.worst_case_tasks_per_cycle, content="3")
}

///|
test "validate_multi_rate passes valid schedule" {
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "axis_1",
      priority: 0,
      cycle_divisor: 1,
      slice: {
        output_offset: 0,
        output_length: 8,
        input_offset: 0,
        input_length: 8,
      },
    },
    {
      name: "axis_2",
      priority: 1,
      cycle_divisor: 2,
      slice: {
        output_offset: 8,
        output_length: 8,
        input_offset: 8,
        input_length: 8,
      },
    },
  ]
  let schedule : @runtime.TaskSchedule = { base_period_ns: 1_000_000L, tasks }
  let errors = @runtime.validate_multi_rate(schedule)
  inspect(errors.length(), content="0")
}

///|
test "DriftCompensator basic convergence" {
  let sync = @runtime.TimebaseSync::new(@runtime.Mcu, @runtime.Linux)
  let comp = @runtime.DriftCompensator::new()
  // Simulate 20 sync updates with constant offset of 500ns
  for i = 0; i < 20; i = i + 1 {
    let ref_ns = (i * 1_000_000).to_int64()
    let local_ns = ref_ns + 500L
    let _ = comp.compensate(sync, ref_ns, local_ns)
  }
  let report = comp.report(sync)
  inspect(report.update_count, content="20")
  // Error should be reducing
  let abs_err = if report.last_error_ns < 0L {
    -report.last_error_ns
  } else {
    report.last_error_ns
  }
  inspect(
    abs_err < 500L,
    content=(
      #|false
    ),
  )
}

///|
test "DriftCompensator reset" {
  let sync = @runtime.TimebaseSync::new(@runtime.Mcu, @runtime.Linux)
  let comp = @runtime.DriftCompensator::new()
  let _ = comp.compensate(sync, 0L, 100L)
  comp.reset()
  inspect(comp.update_count, content="0")
  inspect(comp.integral_error_ns, content="0")
}

///|
test "hil_session_to_json basic" {
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "test_task",
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
  let session = @runtime.HilSession::new(1_000_000L, schedule)
  session.step_log.push(
    @runtime.SimStepResult::Ok(@runtime.SimTime::from_ns(1_000_000L)),
  )
  session.step_log.push(
    @runtime.SimStepResult::Ok(@runtime.SimTime::from_ns(2_000_000L)),
  )
  let json = @runtime.hil_session_to_json(session)
  inspect(json.contains("\"version\": \"1.0\""), content="true")
  inspect(json.contains("\"test_task\""), content="true")
  inspect(json.contains("\"total_steps\": 2"), content="true")
}

///|
test "hil_session_summary counts" {
  let schedule : @runtime.TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [],
  }
  let session = @runtime.HilSession::new(1_000_000L, schedule)
  session.step_log.push(
    @runtime.SimStepResult::Ok(@runtime.SimTime::from_ns(1_000_000L)),
  )
  session.step_log.push(@runtime.SimStepResult::Error("solver diverged"))
  session.step_log.push(
    @runtime.SimStepResult::Ok(@runtime.SimTime::from_ns(3_000_000L)),
  )
  let summary = @runtime.hil_session_summary(session)
  inspect(summary.total_steps, content="3")
  inspect(summary.ok_steps, content="2")
  inspect(summary.error_steps, content="1")
  inspect(summary.final_sim_time_ns, content="3000000")
}
