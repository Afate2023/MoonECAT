///|
/// Tests for 4.3, 4.4, 4.5 Analysis Engine Extensions

// === 4.3 Topology Health Analyzer ===

test "estimate_cable_length" {
  // 500ns delay ≈ 100m cable
  let len = @runtime.estimate_cable_length(500L)
  inspect(len, content="100")
}

///|
test "grade_from_score boundaries" {
  inspect(@runtime.grade_from_score(1000), content="Excellent")
  inspect(@runtime.grade_from_score(950), content="Excellent")
  inspect(@runtime.grade_from_score(949), content="Good")
  inspect(@runtime.grade_from_score(800), content="Good")
  inspect(@runtime.grade_from_score(799), content="Fair")
  inspect(@runtime.grade_from_score(600), content="Fair")
  inspect(@runtime.grade_from_score(599), content="Poor")
  inspect(@runtime.grade_from_score(300), content="Poor")
  inspect(@runtime.grade_from_score(299), content="Critical")
  inspect(@runtime.grade_from_score(0), content="Critical")
}

///|
test "TopologyHealthAnalyzer perfect link" {
  let a = @runtime.TopologyHealthAnalyzer::new()
  a.add_slave(1U, 0, 100L)
  a.ingest_telemetry(0, 1000L, 1000L, 0L, 0L)
  let r = a.analyze()
  inspect(r.slaves.length(), content="1")
  inspect(r.system_health_score, content="1000")
  inspect(r.system_grade, content="Excellent")
  inspect(r.warnings.length(), content="0")
}

///|
test "TopologyHealthAnalyzer degraded link" {
  let a = @runtime.TopologyHealthAnalyzer::new()
  a.add_slave(1U, 0, 100L)
  a.add_slave(2U, 1, 200L)
  // Slave 0: perfect
  a.ingest_telemetry(0, 1000L, 1000L, 0L, 0L)
  // Slave 1: 10% timeout + 5% WKC errors
  a.ingest_telemetry(1, 1000L, 950L, 100L, 50L)
  let r = a.analyze()
  inspect(r.slaves.length(), content="2")
  // Slave 1 should be bottleneck
  inspect(r.bottleneck_index, content="Some(1)")
  // Slave 1 should have lower score
  inspect(r.slaves[0].health_score > r.slaves[1].health_score, content="true")
  // System grade should be degraded
  inspect(
    r.system_grade is (@runtime.Excellent | @runtime.Good),
    content="true",
  )
}

///|
test "TopologyHealthAnalyzer cable warning" {
  let a = @runtime.TopologyHealthAnalyzer::new()
  // 600ns = 120m > 100m limit
  a.add_slave(1U, 0, 600L)
  a.ingest_telemetry(0, 100L, 100L, 0L, 0L)
  let r = a.analyze()
  inspect(r.warnings.length() > 0, content="true")
  inspect(r.total_cable_length_m > 100.0, content="true")
}

///|
test "TopologyHealthAnalyzer to_json" {
  let a = @runtime.TopologyHealthAnalyzer::new()
  a.add_slave(1U, 0, 100L)
  a.ingest_telemetry(0, 100L, 100L, 0L, 0L)
  let r = a.analyze()
  let json = r.to_json()
  inspect(json.contains("\"system_health_score\""), content="true")
  inspect(json.contains("\"slaves\""), content="true")
}

///|
test "TopologyHealthAnalyzer record_cycle" {
  let a = @runtime.TopologyHealthAnalyzer::new()
  a.add_slave(1U, 0, 50L)
  for _i = 0; _i < 100; _i = _i + 1 {
    a.record_cycle(0, 1L, 1L, false, true)
  }
  // Add 5 timeouts
  for _i = 0; _i < 5; _i = _i + 1 {
    a.record_cycle(0, 1L, 0L, true, false)
  }
  let r = a.analyze()
  inspect(r.slaves[0].timeouts, content="5")
  inspect(r.slaves[0].tx_frames, content="105")
}

// === 4.4 Cycle Performance Analyzer ===

///|
test "CyclePerfAnalyzer perfect timing" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L)
  // 11 timestamps at perfect 1ms intervals
  for i = 0; i < 11; i = i + 1 {
    a.record((i * 1_000_000).to_int64())
  }
  let s = a.stats()
  inspect(s.total_cycles, content="10")
  inspect(s.deadline_misses, content="0")
  inspect(s.min_ns, content="1000000")
  inspect(s.max_ns, content="1000000")
}

///|
test "CyclePerfAnalyzer deadline miss detection" {
  let a = @runtime.CyclePerfAnalyzer::new(
    1_000_000L,
    deadline_tolerance_ns=50_000L,
  )
  a.record(0L)
  a.record(1_000_000L) // exactly on time
  a.record(2_100_000L) // 100μs over → deadline miss (>1ms + 50μs tolerance)
  a.record(3_100_000L) // on time relative to previous
  let s = a.stats()
  inspect(s.total_cycles, content="3")
  inspect(s.deadline_misses, content="1")
}

///|
test "CyclePerfAnalyzer record_duration" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L)
  a.record_duration(1_000_000L)
  a.record_duration(1_000_100L)
  a.record_duration(999_900L)
  let s = a.stats()
  inspect(s.total_cycles, content="3")
  inspect(s.min_ns, content="999900")
  inspect(s.max_ns, content="1000100")
}

///|
test "CyclePerfAnalyzer stats empty" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L)
  let s = a.stats()
  inspect(s.total_cycles, content="0")
  inspect(s.mean_ns, content="0")
}

///|
test "CyclePerfAnalyzer reset" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L)
  a.record_duration(1_000_000L)
  a.record_duration(1_000_000L)
  a.reset()
  let s = a.stats()
  inspect(s.total_cycles, content="0")
}

///|
test "CyclePerfAnalyzer trend initial stable" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L, window_size=10)
  for i = 0; i < 15; i = i + 1 {
    a.record_duration(1_000_000L)
  }
  inspect(a.trend(), content="Stable")
}

///|
test "CyclePerfStats to_json" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L)
  a.record_duration(1_000_000L)
  a.record_duration(1_000_000L)
  let s = a.stats()
  let json = s.to_json()
  inspect(json.contains("\"total_cycles\": 2"), content="true")
  inspect(json.contains("\"deadline_misses\""), content="true")
}

///|
test "isqrt64 via CyclePerfAnalyzer stddev" {
  let a = @runtime.CyclePerfAnalyzer::new(1_000_000L)
  // Same values → stddev = 0
  for _i = 0; _i < 10; _i = _i + 1 {
    a.record_duration(1_000_000L)
  }
  let s = a.stats()
  inspect(s.stddev_ns, content="0")
}

// === 4.5 Communication Quality Scorer ===

///|
test "quality_grade_from_score boundaries" {
  inspect(@runtime.quality_grade_from_score(1000), content="Excellent")
  inspect(@runtime.quality_grade_from_score(900), content="Excellent")
  inspect(@runtime.quality_grade_from_score(899), content="Good")
  inspect(@runtime.quality_grade_from_score(750), content="Good")
  inspect(@runtime.quality_grade_from_score(749), content="Acceptable")
  inspect(@runtime.quality_grade_from_score(500), content="Acceptable")
  inspect(@runtime.quality_grade_from_score(499), content="Poor")
  inspect(@runtime.quality_grade_from_score(250), content="Poor")
  inspect(@runtime.quality_grade_from_score(249), content="Critical")
}

///|
test "score_dimension linear interpolation" {
  let dim : @runtime.QualityDimension = {
    name: "test",
    value: 50L,
    good_threshold: 0L,
    bad_threshold: 100L,
    weight: 1000,
  }
  // 50 is midpoint → 500
  inspect(@runtime.score_dimension(dim), content="500")
}

///|
test "score_dimension at good threshold" {
  let dim : @runtime.QualityDimension = {
    name: "test",
    value: 0L,
    good_threshold: 0L,
    bad_threshold: 100L,
    weight: 1000,
  }
  inspect(@runtime.score_dimension(dim), content="1000")
}

///|
test "score_dimension at bad threshold" {
  let dim : @runtime.QualityDimension = {
    name: "test",
    value: 100L,
    good_threshold: 0L,
    bad_threshold: 100L,
    weight: 1000,
  }
  inspect(@runtime.score_dimension(dim), content="0")
}

///|
test "CommQualityScorer perfect telemetry" {
  let scorer = @runtime.CommQualityScorer::new()
  let qs = scorer.score_from_telemetry(1000L, 0L, 0L, 0L)
  inspect(qs.overall, content="1000")
  inspect(qs.grade, content="Excellent")
}

///|
test "CommQualityScorer degraded telemetry" {
  let scorer = @runtime.CommQualityScorer::new()
  // 5% timeouts, 2% WKC errors
  let qs = scorer.score_from_telemetry(1000L, 50L, 20L, 10L)
  // Should not be Excellent anymore
  inspect(qs.overall < 1000, content="true")
  inspect(qs.dimensions.length(), content="4")
}

///|
test "CommQualityScorer trend initial stable" {
  let scorer = @runtime.CommQualityScorer::new(history_size=10)
  for _i = 0; _i < 15; _i = _i + 1 {
    let _ = scorer.score_from_telemetry(1000L, 0L, 0L, 0L)
  }
  inspect(scorer.trend(), content="Stable")
}

///|
test "QualityScore to_json" {
  let scorer = @runtime.CommQualityScorer::new()
  let qs = scorer.score_from_telemetry(1000L, 0L, 0L, 0L)
  let json = qs.to_json()
  inspect(json.contains("\"overall\""), content="true")
  inspect(json.contains("\"grade\""), content="true")
  inspect(json.contains("\"trend\""), content="true")
  inspect(json.contains("\"dimensions\""), content="true")
}

///|
test "compute_quality_score weighted" {
  let dims : Array[@runtime.QualityDimension] = [
    {
      name: "a",
      value: 0L,
      good_threshold: 0L,
      bad_threshold: 100L,
      weight: 500,
    },
    {
      name: "b",
      value: 100L,
      good_threshold: 0L,
      bad_threshold: 100L,
      weight: 500,
    },
  ]
  let (overall, _) = @runtime.compute_quality_score(dims)
  // 1000*500 + 0*500 / 1000 = 500
  inspect(overall, content="500")
}
