///|
// ── C-1: CycleHook tests ──────────────────────────────────────────────

///|
test "NullCycleHook on_pre_cycle returns Continue" {
  let hook = @runtime.NullCycleHook::new()
  let snap : @runtime.CycleSnapshot = {
    cycle: 0L,
    result: None,
    dc_state: @runtime.Disabled,
    recovery_pending: false,
  }
  let ctx = @protocol.PdoContext::build([], 0x1000U)
  assert_eq(hook.on_pre_cycle(snap, ctx), @runtime.Continue)
}

///|
test "NullCycleHook on_post_cycle returns Continue" {
  let hook = @runtime.NullCycleHook::new()
  let snap : @runtime.CycleSnapshot = {
    cycle: 42L,
    result: Some({ wkc: 3U, expected_wkc: 3U, ok: true }),
    dc_state: @runtime.Locked,
    recovery_pending: false,
  }
  let ctx = @protocol.PdoContext::build([], 0x1000U)
  assert_eq(hook.on_post_cycle(snap, ctx), @runtime.Continue)
}

///|
test "NullCycleHook on_fault returns Continue" {
  let hook = @runtime.NullCycleHook::new()
  let snap : @runtime.CycleSnapshot = {
    cycle: 1L,
    result: None,
    dc_state: @runtime.Disabled,
    recovery_pending: true,
  }
  assert_eq(hook.on_fault(snap, @hal.EcError::RecvTimeout), @runtime.Continue)
}

///|
test "CycleDirective equality" {
  assert_eq(@runtime.Continue, @runtime.Continue)
  assert_eq(@runtime.SkipCycle, @runtime.SkipCycle)
  assert_eq(@runtime.StopGraceful, @runtime.StopGraceful)
  assert_true(@runtime.Continue != @runtime.SkipCycle)
  assert_true(@runtime.Continue != @runtime.StopGraceful)
}

// ── C-2: TaskPartition tests ──────────────────────────────────────────

///|
test "slice_from_mapping valid mapping" {
  let mapping : @protocol.PdoMapping = {
    station: 1U,
    output_logical: 0U,
    output_offset: 0,
    output_length: 4,
    input_logical: 4U,
    input_offset: 0,
    input_length: 2,
  }
  let image = @protocol.ProcessImage::new(8, 8)
  guard @runtime.slice_from_mapping(mapping, image) is Some(slice) else {
    fail("expected Some")
  }
  assert_eq(slice.output_offset, 0)
  assert_eq(slice.output_length, 4)
  assert_eq(slice.input_offset, 0)
  assert_eq(slice.input_length, 2)
}

///|
test "slice_from_mapping rejects out-of-bounds output" {
  let mapping : @protocol.PdoMapping = {
    station: 1U,
    output_logical: 0U,
    output_offset: 6,
    output_length: 4,
    input_logical: 0U,
    input_offset: 0,
    input_length: 2,
  }
  let image = @protocol.ProcessImage::new(8, 8)
  assert_true(@runtime.slice_from_mapping(mapping, image) is None)
}

///|
test "slice_from_mapping rejects out-of-bounds input" {
  let mapping : @protocol.PdoMapping = {
    station: 1U,
    output_logical: 0U,
    output_offset: 0,
    output_length: 4,
    input_logical: 0U,
    input_offset: 7,
    input_length: 4,
  }
  let image = @protocol.ProcessImage::new(8, 8)
  assert_true(@runtime.slice_from_mapping(mapping, image) is None)
}

///|
test "partition_by_slave returns per-slave slices" {
  let ctx = @protocol.PdoContext::build(
    [
      (
        { sm_configs: [], fmmu_configs: [], output_bytes: 4, input_bytes: 2 },
        0x1001U,
      ),
      (
        { sm_configs: [], fmmu_configs: [], output_bytes: 2, input_bytes: 4 },
        0x1002U,
      ),
    ],
    0x1000U,
  )
  let parts = @runtime.partition_by_slave(ctx)
  assert_eq(parts.length(), 2)
  assert_eq(parts[0].0, 0x1001U)
  assert_eq(parts[0].1.output_offset, 0)
  assert_eq(parts[0].1.output_length, 4)
  assert_eq(parts[1].0, 0x1002U)
  assert_eq(parts[1].1.output_offset, 4)
  assert_eq(parts[1].1.output_length, 2)
}

///|
test "build_task_schedule rejects zero divisor" {
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "t1",
      priority: 0,
      cycle_divisor: 0,
      slice: {
        output_offset: 0,
        output_length: 4,
        input_offset: 0,
        input_length: 4,
      },
    },
  ]
  assert_true(@runtime.build_task_schedule(1_000_000L, tasks) is None)
}

///|
test "build_task_schedule rejects duplicate names" {
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "dup",
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
      name: "dup",
      priority: 1,
      cycle_divisor: 1,
      slice: {
        output_offset: 4,
        output_length: 2,
        input_offset: 4,
        input_length: 2,
      },
    },
  ]
  assert_true(@runtime.build_task_schedule(1_000_000L, tasks) is None)
}

///|
test "build_task_schedule rejects overlapping output slices" {
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "a",
      priority: 0,
      cycle_divisor: 1,
      slice: {
        output_offset: 0,
        output_length: 4,
        input_offset: 0,
        input_length: 2,
      },
    },
    {
      name: "b",
      priority: 1,
      cycle_divisor: 1,
      slice: {
        output_offset: 2,
        output_length: 4,
        input_offset: 4,
        input_length: 2,
      },
    },
  ]
  assert_true(@runtime.build_task_schedule(1_000_000L, tasks) is None)
}

///|
test "build_task_schedule rejects overlapping input slices" {
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "a",
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
      name: "b",
      priority: 1,
      cycle_divisor: 1,
      slice: {
        output_offset: 4,
        output_length: 4,
        input_offset: 2,
        input_length: 4,
      },
    },
  ]
  assert_true(@runtime.build_task_schedule(1_000_000L, tasks) is None)
}

///|
test "build_task_schedule sorts by priority" {
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "low",
      priority: 10,
      cycle_divisor: 1,
      slice: {
        output_offset: 4,
        output_length: 4,
        input_offset: 4,
        input_length: 4,
      },
    },
    {
      name: "high",
      priority: 0,
      cycle_divisor: 1,
      slice: {
        output_offset: 0,
        output_length: 4,
        input_offset: 0,
        input_length: 4,
      },
    },
  ]
  guard @runtime.build_task_schedule(1_000_000L, tasks) is Some(sched) else {
    fail("expected Some")
  }
  assert_eq(sched.tasks[0].name, "high")
  assert_eq(sched.tasks[1].name, "low")
}

///|
test "tasks_due_at_cycle respects divisor" {
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "every",
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
      name: "half",
      priority: 1,
      cycle_divisor: 2,
      slice: {
        output_offset: 2,
        output_length: 2,
        input_offset: 2,
        input_length: 2,
      },
    },
    {
      name: "quarter",
      priority: 2,
      cycle_divisor: 4,
      slice: {
        output_offset: 4,
        output_length: 2,
        input_offset: 4,
        input_length: 2,
      },
    },
  ]
  guard @runtime.build_task_schedule(1_000_000L, tasks) is Some(sched) else {
    fail("expected Some")
  }
  // Cycle 0: all due
  let due0 = @runtime.tasks_due_at_cycle(sched, 0L)
  assert_eq(due0.length(), 3)
  // Cycle 1: only "every"
  let due1 = @runtime.tasks_due_at_cycle(sched, 1L)
  assert_eq(due1.length(), 1)
  assert_eq(due1[0].name, "every")
  // Cycle 2: "every" + "half"
  let due2 = @runtime.tasks_due_at_cycle(sched, 2L)
  assert_eq(due2.length(), 2)
  // Cycle 4: all three
  let due4 = @runtime.tasks_due_at_cycle(sched, 4L)
  assert_eq(due4.length(), 3)
}

///|
test "read_slice_inputs reads correct region" {
  let image = @protocol.ProcessImage::new(0, 8)
  // Manually set inputs
  image.inputs = Bytes::makei(8, fn(i) { i.to_byte() })
  let slice : @runtime.ProcessImageSlice = {
    output_offset: 0,
    output_length: 0,
    input_offset: 2,
    input_length: 4,
  }
  let data = @runtime.read_slice_inputs(image, slice)
  assert_eq(data.length(), 4)
  assert_eq(data[0], b'\x02')
  assert_eq(data[1], b'\x03')
  assert_eq(data[2], b'\x04')
  assert_eq(data[3], b'\x05')
}

///|
test "read_slice_inputs with zero length returns empty bytes" {
  let image = @protocol.ProcessImage::new(0, 8)
  let slice : @runtime.ProcessImageSlice = {
    output_offset: 0,
    output_length: 0,
    input_offset: 0,
    input_length: 0,
  }
  let data = @runtime.read_slice_inputs(image, slice)
  assert_eq(data.length(), 0)
}

///|
test "write_slice_outputs writes correct region" {
  let image = @protocol.ProcessImage::new(8, 0)
  // Fill outputs with 0xFF
  image.outputs = Bytes::makei(8, fn(_i) { b'\xFF' })
  let slice : @runtime.ProcessImageSlice = {
    output_offset: 2,
    output_length: 3,
    input_offset: 0,
    input_length: 0,
  }
  let data = Bytes::makei(3, fn(i) { (i + 0xA0).to_byte() })
  @runtime.write_slice_outputs(image, slice, data)
  // Bytes outside slice should remain 0xFF
  assert_eq(image.outputs[0], b'\xFF')
  assert_eq(image.outputs[1], b'\xFF')
  // Bytes inside slice should be written
  assert_eq(image.outputs[2], b'\xA0')
  assert_eq(image.outputs[3], b'\xA1')
  assert_eq(image.outputs[4], b'\xA2')
  // Bytes after slice should remain 0xFF
  assert_eq(image.outputs[5], b'\xFF')
}

// ── C-3: CoSimAdapter tests ──────────────────────────────────────────

///|
test "SimTime arithmetic" {
  let t0 = @runtime.SimTime::zero()
  assert_eq(t0.to_ns(), 0L)
  let t1 = t0.advance(1_000_000L)
  assert_eq(t1.to_ns(), 1_000_000L)
  let t2 = @runtime.SimTime::from_ns(5_000_000L)
  assert_eq(t2.to_ns(), 5_000_000L)
  assert_true(t0 < t2)
}

///|
test "LoopbackCoSimAdapter copies outputs to inputs" {
  let adapter = @runtime.LoopbackCoSimAdapter::new()
  let config : @runtime.CoSimConfig = {
    cycle_period_ns: 1_000_000L,
    slave_count: 1,
    output_size: 4,
    input_size: 4,
  }
  adapter.init_(config)
  let image = @protocol.ProcessImage::new(4, 4)
  image.outputs = Bytes::makei(4, fn(i) { (i + 1).to_byte() })
  let slice : @runtime.ProcessImageSlice = {
    output_offset: 0,
    output_length: 4,
    input_offset: 0,
    input_length: 4,
  }
  adapter.write_outputs(image, slice)
  let result = adapter.step(@runtime.SimTime::zero(), 1_000_000L)
  assert_true(result is @runtime.Ok(_))
  adapter.read_inputs(image, slice)
  // After loopback, inputs should mirror outputs
  assert_eq(image.inputs[0], b'\x01')
  assert_eq(image.inputs[1], b'\x02')
  assert_eq(image.inputs[2], b'\x03')
  assert_eq(image.inputs[3], b'\x04')
}

///|
test "LoopbackCoSimAdapter step advances sim time" {
  let adapter = @runtime.LoopbackCoSimAdapter::new()
  let r1 = adapter.step(@runtime.SimTime::zero(), 1_000_000L)
  guard r1 is @runtime.Ok(t1) else { fail("expected Ok") }
  assert_eq(t1.to_ns(), 1_000_000L)
  let r2 = adapter.step(t1, 1_000_000L)
  guard r2 is @runtime.Ok(t2) else { fail("expected Ok") }
  assert_eq(t2.to_ns(), 2_000_000L)
}

///|
test "LoopbackCoSimAdapter shutdown is safe" {
  let adapter = @runtime.LoopbackCoSimAdapter::new()
  adapter.shutdown()
}

// ── C-4: HilLoop tests ──────────────────────────────────────────────

///|
test "HilSession initial state" {
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "axis1",
      priority: 0,
      cycle_divisor: 1,
      slice: {
        output_offset: 0,
        output_length: 4,
        input_offset: 0,
        input_length: 4,
      },
    },
  ]
  guard @runtime.build_task_schedule(1_000_000L, tasks) is Some(sched) else {
    fail("expected schedule")
  }
  let session = @runtime.HilSession::new(1_000_000L, sched)
  assert_eq(session.sim_time.to_ns(), 0L)
  assert_eq(session.terminated, false)
  assert_eq(session.step_log.length(), 0)
}

///|
test "HilCycleHook on_pre_cycle returns Continue" {
  let adapter = @runtime.LoopbackCoSimAdapter::new()
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "axis1",
      priority: 0,
      cycle_divisor: 1,
      slice: {
        output_offset: 0,
        output_length: 4,
        input_offset: 0,
        input_length: 4,
      },
    },
  ]
  guard @runtime.build_task_schedule(1_000_000L, tasks) is Some(sched) else {
    fail("expected schedule")
  }
  let session = @runtime.HilSession::new(1_000_000L, sched)
  let hook = @runtime.HilCycleHook::new(adapter, session)
  let snap : @runtime.CycleSnapshot = {
    cycle: 0L,
    result: None,
    dc_state: @runtime.Disabled,
    recovery_pending: false,
  }
  let ctx = @protocol.PdoContext::build(
    [
      (
        { sm_configs: [], fmmu_configs: [], output_bytes: 4, input_bytes: 4 },
        0x1001U,
      ),
    ],
    0x1000U,
  )
  assert_eq(hook.on_pre_cycle(snap, ctx), @runtime.Continue)
}

///|
test "HilCycleHook on_post_cycle advances sim time via adapter" {
  let adapter = @runtime.LoopbackCoSimAdapter::new()
  let tasks : Array[@runtime.TaskDescriptor] = [
    {
      name: "axis1",
      priority: 0,
      cycle_divisor: 1,
      slice: {
        output_offset: 0,
        output_length: 4,
        input_offset: 0,
        input_length: 4,
      },
    },
  ]
  guard @runtime.build_task_schedule(1_000_000L, tasks) is Some(sched) else {
    fail("expected schedule")
  }
  let session = @runtime.HilSession::new(1_000_000L, sched)
  let hook = @runtime.HilCycleHook::new(adapter, session)
  let snap : @runtime.CycleSnapshot = {
    cycle: 0L,
    result: Some({ wkc: 1U, expected_wkc: 1U, ok: true }),
    dc_state: @runtime.Disabled,
    recovery_pending: false,
  }
  let ctx = @protocol.PdoContext::build(
    [
      (
        { sm_configs: [], fmmu_configs: [], output_bytes: 4, input_bytes: 4 },
        0x1001U,
      ),
    ],
    0x1000U,
  )
  let directive = hook.on_post_cycle(snap, ctx)
  assert_eq(directive, @runtime.Continue)
  assert_eq(hook.session.sim_time.to_ns(), 1_000_000L)
  assert_eq(hook.session.step_log.length(), 1)
}

///|
test "HilCycleHook on_fault returns Continue" {
  let adapter = @runtime.LoopbackCoSimAdapter::new()
  let tasks : Array[@runtime.TaskDescriptor] = []
  guard @runtime.build_task_schedule(1_000_000L, tasks) is Some(sched) else {
    fail("expected schedule")
  }
  let session = @runtime.HilSession::new(1_000_000L, sched)
  let hook = @runtime.HilCycleHook::new(adapter, session)
  let snap : @runtime.CycleSnapshot = {
    cycle: 0L,
    result: None,
    dc_state: @runtime.Disabled,
    recovery_pending: false,
  }
  assert_eq(hook.on_fault(snap, @hal.EcError::RecvTimeout), @runtime.Continue)
}

///|
test "HilCycleHook returns StopGraceful when terminated" {
  let adapter = @runtime.LoopbackCoSimAdapter::new()
  let tasks : Array[@runtime.TaskDescriptor] = []
  guard @runtime.build_task_schedule(1_000_000L, tasks) is Some(sched) else {
    fail("expected schedule")
  }
  let session = @runtime.HilSession::new(1_000_000L, sched)
  session.terminated = true
  let hook = @runtime.HilCycleHook::new(adapter, session)
  let snap : @runtime.CycleSnapshot = {
    cycle: 0L,
    result: None,
    dc_state: @runtime.Disabled,
    recovery_pending: false,
  }
  let ctx = @protocol.PdoContext::build([], 0x1000U)
  assert_eq(hook.on_pre_cycle(snap, ctx), @runtime.StopGraceful)
  assert_eq(hook.on_post_cycle(snap, ctx), @runtime.StopGraceful)
}

// ── C-5: Timebase tests ──────────────────────────────────────────────

///|
test "VirtualTimebase starts at zero and advances" {
  let tb = @runtime.VirtualTimebase::new()
  assert_eq(tb.now_ns(), 0L)
  assert_eq(tb.domain(), @runtime.Virtual)
  assert_true(tb.is_monotonic())
  assert_eq(tb.resolution_ns(), 1L)
  tb.advance(1_000_000L)
  assert_eq(tb.now_ns(), 1_000_000L)
  tb.advance(500_000L)
  assert_eq(tb.now_ns(), 1_500_000L)
}

///|
test "VirtualTimebase set overrides current time" {
  let tb = @runtime.VirtualTimebase::new()
  tb.set(42_000_000L)
  assert_eq(tb.now_ns(), 42_000_000L)
}

///|
test "TimebaseSync initial state is zero offset" {
  let sync = @runtime.TimebaseSync::new(@runtime.Mcu, @runtime.Linux)
  assert_eq(sync.offset_ns, 0L)
  assert_eq(sync.drift_ppb, 0L)
  assert_eq(sync.sync_count, 0L)
}

///|
test "TimebaseSync update computes offset" {
  let sync = @runtime.TimebaseSync::new(@runtime.Mcu, @runtime.Linux)
  // First measurement: reference=1000, local=1050 → offset=50
  sync.update(1000L, 1050L)
  assert_eq(sync.offset_ns, 50L)
  assert_eq(sync.sync_count, 1L)
  // Drift not computed on first sample
  assert_eq(sync.drift_ppb, 0L)
}

///|
test "TimebaseSync update computes drift" {
  let sync = @runtime.TimebaseSync::new(@runtime.Mcu, @runtime.Linux)
  sync.update(1_000_000L, 1_000_100L) // offset=100, last_sync_ns=1_000_000
  // After 1ms, local drifted to offset=200 → drift = 100ns/1_000_000ns * 1e9 = 100_000 ppb
  sync.update(2_000_000L, 2_000_200L)
  assert_eq(sync.offset_ns, 200L)
  assert_eq(sync.drift_ppb, 100_000L)
}

///|
test "TimebaseSync to_local and to_reference are inverse" {
  let sync = @runtime.TimebaseSync::new(@runtime.Mcu, @runtime.Linux)
  sync.update(0L, 500L) // offset=500
  let local_ = sync.to_local(1000L)
  assert_eq(local_, 1500L)
  let ref_ = sync.to_reference(1500L)
  assert_eq(ref_, 1000L)
}

///|
test "ClockDomain equality" {
  assert_eq(@runtime.Mcu, @runtime.Mcu)
  assert_eq(@runtime.Linux, @runtime.Linux)
  assert_eq(@runtime.Fpga, @runtime.Fpga)
  assert_eq(@runtime.Virtual, @runtime.Virtual)
  assert_true(@runtime.Mcu != @runtime.Linux)
}

///|
test "CycleTimingReport jitter calculation" {
  let report = @runtime.cycle_timing_report(
    1_000_000L,
    0L,
    1_000_500L,
    @runtime.Mcu,
  )
  assert_eq(report.nominal_period_ns, 1_000_000L)
  assert_eq(report.actual_period_ns, 1_000_500L)
  assert_eq(report.jitter_ns, 500L)
  assert_eq(report.domain, @runtime.Mcu)
}

///|
test "CycleTimingReport negative jitter normalized to positive" {
  let report = @runtime.cycle_timing_report(
    1_000_000L,
    0L,
    999_500L,
    @runtime.Linux,
  )
  assert_eq(report.actual_period_ns, 999_500L)
  assert_eq(report.jitter_ns, 500L)
}
