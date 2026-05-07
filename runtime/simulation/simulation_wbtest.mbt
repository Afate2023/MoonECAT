///|
test "slices_overlap_output zero length" {
  let a : ProcessImageSlice = {
    output_offset: 0,
    output_length: 0,
    input_offset: 0,
    input_length: 10,
  }
  let b : ProcessImageSlice = {
    output_offset: 0,
    output_length: 10,
    input_offset: 0,
    input_length: 10,
  }
  assert_true(slices_overlap_output(a, b) == false)
}

///|
test "slices_overlap_input zero length" {
  let a : ProcessImageSlice = {
    output_offset: 0,
    output_length: 10,
    input_offset: 0,
    input_length: 0,
  }
  let b : ProcessImageSlice = {
    output_offset: 0,
    output_length: 10,
    input_offset: 0,
    input_length: 10,
  }
  assert_true(slices_overlap_input(a, b) == false)
}

///|
test "lcm with zero" {
  assert_eq(lcm(0, 5), 0)
  assert_eq(lcm(5, 0), 0)
}

///|
test "analyze_multi_rate non-harmonic schedule" {
  let schedule : TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 3,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 4,
        },
      },
      {
        name: "t2",
        priority: 1,
        cycle_divisor: 2,
        slice: {
          output_offset: 4,
          output_length: 8,
          input_offset: 4,
          input_length: 8,
        },
      },
    ],
  }
  let analysis = analyze_multi_rate(schedule)
  assert_eq(analysis.hyperperiod, 6)
  assert_eq(analysis.is_harmonic, false)
  assert_eq(analysis.worst_case_tasks_per_cycle, 2)
  assert_eq(analysis.peak_cycles, [0])
}

///|
test "analyze_multi_rate with multiple peak cycles" {
  let schedule : TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 2,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 4,
        },
      },
    ],
  }
  let analysis = analyze_multi_rate(schedule)
  assert_eq(analysis.hyperperiod, 2)
  assert_eq(analysis.is_harmonic, true)
  assert_eq(analysis.worst_case_tasks_per_cycle, 1)
  assert_eq(analysis.peak_cycles, [0])
}

///|
test "validate_multi_rate detects excessive hyperperiod" {
  let schedule : TaskSchedule = {
    base_period_ns: 1_000_000L,
    tasks: [
      {
        name: "t1",
        priority: 0,
        cycle_divisor: 7,
        slice: {
          output_offset: 0,
          output_length: 4,
          input_offset: 0,
          input_length: 4,
        },
      },
      {
        name: "t2",
        priority: 1,
        cycle_divisor: 13,
        slice: {
          output_offset: 4,
          output_length: 8,
          input_offset: 4,
          input_length: 8,
        },
      },
    ],
  }
  let errors = validate_multi_rate(schedule, max_hyperperiod=8)
  assert_true(errors.length() > 0)
}
