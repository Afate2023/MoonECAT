///|
/// Tests for 4.1 DC Jitter Profiling and 4.2 PDO Auto-Tuning

// === 4.1 DC Jitter Profiling ===

test "JitterHistogram basic record" {
  let h = @analysis.JitterHistogram::new(bin_width=100L, num_bins=101)
  h.record(0L)
  h.record(50L)
  h.record(-50L)
  inspect(h.total, content="3")
}

///|
test "JitterHistogram percentile empty" {
  let h = @analysis.JitterHistogram::new()
  inspect(h.percentile(50), content="0")
}

///|
test "JitterHistogram percentile centered" {
  let h = @analysis.JitterHistogram::new(bin_width=100L, num_bins=101)
  // Record 100 samples at deviation=0
  for _i = 0; _i < 100; _i = _i + 1 {
    h.record(0L)
  }
  inspect(h.percentile(50), content="0")
  inspect(h.percentile(99), content="0")
}

///|
test "JitterHistogram percentile spread" {
  let h = @analysis.JitterHistogram::new(bin_width=100L, num_bins=201)
  // Record deviations from -1000 to +1000 in steps of 100
  for d = -1000; d <= 1000; d = d + 100 {
    h.record(d.to_int64())
  }
  // p50 should be near 0
  let p50 = h.percentile(50)
  inspect(p50 >= -100L && p50 <= 100L, content="true")
}

///|
test "DcJitterProfiler record timestamps with no jitter" {
  let p = @analysis.DcJitterProfiler::new(1_000_000L)
  // Perfect 1ms intervals
  for i = 0; i < 11; i = i + 1 {
    p.record_timestamp((i * 1_000_000).to_int64())
  }
  let s = p.stats()
  inspect(s.count, content="10")
  // All deviations should be 0
  inspect(s.min_ns, content="0")
  inspect(s.max_ns, content="0")
  inspect(s.peak_to_peak_ns, content="0")
}

///|
test "DcJitterProfiler record timestamps with jitter" {
  let p = @analysis.DcJitterProfiler::new(1_000_000L, bin_width=10L)
  // Simulate jittery timestamps: 0, 1000050, 1999980, 3000100, 3999900
  p.record_timestamp(0L)
  p.record_timestamp(1_000_050L)
  p.record_timestamp(1_999_980L)
  p.record_timestamp(3_000_100L)
  p.record_timestamp(3_999_900L)
  let s = p.stats()
  inspect(s.count, content="4")
  // deviations: +50, -70, +120, -200
  inspect(s.min_ns, content="-200")
  inspect(s.max_ns, content="120")
  inspect(s.peak_to_peak_ns, content="320")
}

///|
test "DcJitterProfiler stats empty" {
  let p = @analysis.DcJitterProfiler::new(1_000_000L)
  let s = p.stats()
  inspect(s.count, content="0")
  inspect(s.mean_ns, content="0")
}

///|
test "DcJitterProfiler is_within_tolerance" {
  let p = @analysis.DcJitterProfiler::new(1_000_000L)
  // Perfect timing
  for i = 0; i < 101; i = i + 1 {
    p.record_timestamp((i * 1_000_000).to_int64())
  }
  // Should be within any tolerance
  inspect(p.is_within_tolerance(1000L, 1000L), content="true")
}

///|
test "DcJitterProfiler to_json" {
  let p = @analysis.DcJitterProfiler::new(1_000_000L)
  p.record_timestamp(0L)
  p.record_timestamp(1_000_000L)
  p.record_timestamp(2_000_000L)
  let json = p.to_json()
  inspect(json.contains("\"nominal_period_ns\": 1000000"), content="true")
  inspect(json.contains("\"sample_count\": 2"), content="true")
}

///|
test "DcJitterProfiler reset" {
  let p = @analysis.DcJitterProfiler::new(1_000_000L)
  p.record_timestamp(0L)
  p.record_timestamp(1_000_050L)
  p.reset()
  let s = p.stats()
  inspect(s.count, content="0")
}

///|
test "MultiChannelJitterProfiler basic" {
  let mc = @analysis.MultiChannelJitterProfiler::new()
  mc.add_channel("tx", 1_000_000L)
  mc.add_channel("rx", 1_000_000L)
  // Record on channel 0 (tx)
  mc.record(0, 0L)
  mc.record(0, 1_000_000L)
  // Record on channel 1 (rx)
  mc.record(1, 0L)
  mc.record(1, 1_000_100L)
  let json = mc.summary_json()
  inspect(json.contains("\"tx\""), content="true")
  inspect(json.contains("\"rx\""), content="true")
}

// === 4.2 PDO Auto-Tuning ===

///|
test "AutoTuneConfig default values" {
  let cfg = @analysis.AutoTuneConfig::default()
  inspect(cfg.probe_iterations, content="10")
  inspect(cfg.cycle_time_ns, content="1000000")
  inspect(cfg.sync1_enabled, content="false")
}

///|
test "compute_probe_result" {
  let p = @analysis.compute_probe_result(1U, 100L, 250L, 0L)
  inspect(p.forward_delay_ns, content="100")
  inspect(p.reverse_delay_ns, content="150")
  inspect(p.round_trip_ns, content="250")
}

///|
test "average_probe single" {
  let probes : Array[@analysis.ProbeResult] = [
    @analysis.compute_probe_result(1U, 100L, 200L, 0L),
  ]
  let avg = @analysis.average_probe(probes)
  inspect(avg.forward_delay_ns, content="100")
  inspect(avg.round_trip_ns, content="200")
}

///|
test "average_probe multiple" {
  let probes : Array[@analysis.ProbeResult] = [
    @analysis.compute_probe_result(1U, 100L, 200L, 0L),
    @analysis.compute_probe_result(1U, 200L, 400L, 0L),
    @analysis.compute_probe_result(1U, 150L, 300L, 0L),
  ]
  let avg = @analysis.average_probe(probes)
  inspect(avg.forward_delay_ns, content="150")
  inspect(avg.round_trip_ns, content="300")
}

///|
test "PdoAutoTuner analyze single station" {
  let tuner = @analysis.PdoAutoTuner::new()
  let stations : Array[UInt] = [1U]
  let probes : Array[Array[@analysis.ProbeResult]] = [
    [
      @analysis.compute_probe_result(1U, 100L, 200L, 0L),
      @analysis.compute_probe_result(1U, 120L, 240L, 0L),
    ],
  ]
  let result = tuner.analyze(stations, probes)
  inspect(result.success, content="true")
  inspect(result.recommendations.length(), content="1")
  // Sync0 = base(1000000) + prop_delay(110) + margin(110*100/1000=11) = 1000121
  let rec = result.recommendations[0]
  inspect(rec.station, content="1")
  inspect(rec.propagation_delay_ns, content="110")
}

///|
test "PdoAutoTuner analyze missing data" {
  let tuner = @analysis.PdoAutoTuner::new()
  let stations : Array[UInt] = [1U, 2U]
  let probes : Array[Array[@analysis.ProbeResult]] = [
    [@analysis.compute_probe_result(1U, 100L, 200L, 0L)],
  ]
  let result = tuner.analyze(stations, probes)
  inspect(result.success, content="false")
  inspect(result.messages.length() > 0, content="true")
}

///|
test "validate_recommendations within limit" {
  let tuner = @analysis.PdoAutoTuner::new()
  let stations : Array[UInt] = [1U]
  let probes : Array[Array[@analysis.ProbeResult]] = [
    [@analysis.compute_probe_result(1U, 100L, 200L, 0L)],
  ]
  let result = tuner.analyze(stations, probes)
  let errors = @analysis.validate_recommendations(result, 2_000_000L)
  inspect(errors.length(), content="0")
}

///|
test "validate_recommendations exceeds limit" {
  let tuner = @analysis.PdoAutoTuner::new()
  let stations : Array[UInt] = [1U]
  let probes : Array[Array[@analysis.ProbeResult]] = [
    [@analysis.compute_probe_result(1U, 100L, 200L, 0L)],
  ]
  let result = tuner.analyze(stations, probes)
  let errors = @analysis.validate_recommendations(result, 500L)
  inspect(errors.length() > 0, content="true")
}

///|
test "AutoTuneResult to_json" {
  let tuner = @analysis.PdoAutoTuner::new()
  let stations : Array[UInt] = [1U]
  let probes : Array[Array[@analysis.ProbeResult]] = [
    [@analysis.compute_probe_result(1U, 100L, 200L, 0L)],
  ]
  let result = tuner.analyze(stations, probes)
  let json = result.to_json()
  inspect(json.contains("\"success\": true"), content="true")
  inspect(json.contains("\"recommendations\":"), content="true")
}
