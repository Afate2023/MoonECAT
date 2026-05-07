///|
test "validate_recommendations negative propagation from whitebox" {
  let config : AutoTuneConfig = {
    probe_iterations: 5,
    probe_timeout_ns: 5_000_000L,
    strategy: Balanced,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 0L,
    sync1_enabled: false,
    sync1_delta_ns: 0L,
    safety_margin_permille: 0,
  }
  let avg : ProbeResult = {
    station: 0x1001U,
    forward_delay_ns: -500L,
    reverse_delay_ns: 500L,
    round_trip_ns: 0L,
    recv_time_port0: 0L,
    recv_time_port1: 0L,
  }
  let rec = compute_sync_offsets(config, avg)
  let result : AutoTuneResult = {
    recommendations: [rec],
    probe_data: [avg],
    reference_station: 0x1001U,
    measurement_duration_ns: 0L,
    success: true,
    messages: [],
  }
  let errors = validate_recommendations(result, 10_000_000L)
  assert_true(errors.iter().any(fn(s) { s.contains("negative propagation") }))
}

///|
test "isqrt64 zero and negative" {
  assert_eq(isqrt64(0L), 0L)
  assert_eq(isqrt64(-5L), 0L)
}

///|
test "compute_sync_offsets with sync1 enabled" {
  let config : AutoTuneConfig = {
    probe_iterations: 10,
    probe_timeout_ns: 5_000_000L,
    strategy: Balanced,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 1_000_000L,
    sync1_enabled: true,
    sync1_delta_ns: 500_000L,
    safety_margin_permille: 100,
  }
  let probe : ProbeResult = {
    station: 0x1001U,
    forward_delay_ns: 100_000L,
    reverse_delay_ns: 100_000L,
    round_trip_ns: 200_000L,
    recv_time_port0: 0L,
    recv_time_port1: 0L,
  }
  let rec = compute_sync_offsets(config, probe)
  assert_true(rec.sync1_offset_ns > 0L)
  assert_eq(rec.sync1_offset_ns, rec.sync0_offset_ns + 500_000L)
}

///|
test "validate_recommendations sync1 over limit from whitebox" {
  let config : AutoTuneConfig = {
    probe_iterations: 5,
    probe_timeout_ns: 5_000_000L,
    strategy: Balanced,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 1_000_000L,
    sync1_enabled: true,
    sync1_delta_ns: 9_000_000L,
    safety_margin_permille: 100,
  }
  let avg : ProbeResult = {
    station: 0x1001U,
    forward_delay_ns: 100_000L,
    reverse_delay_ns: 100_000L,
    round_trip_ns: 200_000L,
    recv_time_port0: 0L,
    recv_time_port1: 0L,
  }
  let rec = compute_sync_offsets(config, avg)
  let tuner = PdoAutoTuner::new(config~)
  let result = tuner.analyze([0x1001U], [
    [
      {
        station: 0x1001U,
        forward_delay_ns: 100_000L,
        reverse_delay_ns: 100_000L,
        round_trip_ns: 200_000L,
        recv_time_port0: 100_000L,
        recv_time_port1: 200_000L,
      },
    ],
  ])
  let errors = validate_recommendations(result, 2_000_000L)
  assert_true(
    errors.iter().any(fn(s) { s.contains("Sync1") && s.contains("exceeds") }),
  )
  ignore(rec)
}

///|
test "compute_link_health_score with zero tx" {
  let score = compute_link_health_score(0L, 0L, 0L, 0L, 300, 300, 300)
  assert_eq(score, 1000)
}

///|
test "compute_link_health_score perfect" {
  let score = compute_link_health_score(1000L, 1000L, 0L, 0L, 300, 300, 300)
  assert_eq(score, 1000)
}

///|
test "compute_link_health_score with losses" {
  let score = compute_link_health_score(1000L, 500L, 0L, 0L, 300, 300, 300)
  assert_eq(score, 850)
}

///|
test "compute_link_health_score clamps to zero" {
  let score = compute_link_health_score(1L, 0L, 1L, 1L, 1000, 1000, 1000)
  assert_eq(score, 0)
}

///|
test "AutoTuneResult to_json with multiple recommendations" {
  let result : AutoTuneResult = {
    success: true,
    reference_station: 0x1001U,
    recommendations: [
      {
        station: 0x1001U,
        sync0_offset_ns: 100L,
        sync1_offset_ns: 200L,
        sync0_cycle_ns: 1_000_000L,
        propagation_delay_ns: 50L,
      },
      {
        station: 0x1002U,
        sync0_offset_ns: 300L,
        sync1_offset_ns: 400L,
        sync0_cycle_ns: 1_000_000L,
        propagation_delay_ns: 150L,
      },
    ],
    probe_data: [],
    measurement_duration_ns: 50_000_000L,
    messages: ["msg1", "msg2"],
  }
  let json = result.to_json()
  assert_true(json.contains("msg1"))
  assert_true(json.contains("msg2"))
}

///|
test "TopologyHealthReport to_json with bottleneck and warnings" {
  let report : TopologyHealthReport = {
    system_health_score: 900,
    system_grade: Excellent,
    max_propagation_delay_ns: 1000L,
    total_cable_length_m: 10.0,
    bottleneck_index: None,
    slaves: [],
    warnings: [],
  }
  let json = report.to_json()
  assert_true(json.contains("null"))

  let report2 : TopologyHealthReport = {
    system_health_score: 800,
    system_grade: Good,
    max_propagation_delay_ns: 2000L,
    total_cable_length_m: 20.0,
    bottleneck_index: Some(0),
    slaves: [
      {
        station: 0x1001U,
        position: 0,
        propagation_delay_ns: 100L,
        estimated_cable_length_m: 1.0,
        tx_frames: 100L,
        rx_frames: 99L,
        timeouts: 0L,
        wkc_errors: 0L,
        loss_rate_permille: 10,
        health_score: 950,
        grade: Excellent,
      },
      {
        station: 0x1002U,
        position: 1,
        propagation_delay_ns: 200L,
        estimated_cable_length_m: 2.0,
        tx_frames: 100L,
        rx_frames: 98L,
        timeouts: 1L,
        wkc_errors: 0L,
        loss_rate_permille: 20,
        health_score: 900,
        grade: Good,
      },
    ],
    warnings: ["warning1", "warning2"],
  }
  let json2 = report2.to_json()
  assert_true(json2.contains("warning1"))
  assert_true(json2.contains("warning2"))
  assert_true(json2.contains("4098"))
}
