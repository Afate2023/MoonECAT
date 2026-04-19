///|
test "analysis facade exposes jitter profiler" {
  let profiler = @analysis.DcJitterProfiler::new(1_000_000L)
  profiler.record_timestamp(0L)
  profiler.record_timestamp(1_000_050L)
  let stats = profiler.stats()
  inspect(stats.count, content="1")
  inspect(stats.max_ns, content="50")
}

///|
test "analysis facade exposes auto tune" {
  let tuner = @analysis.PdoAutoTuner::new()
  let result = tuner.analyze([1U], [
    [@analysis.compute_probe_result(1U, 100L, 200L, 0L)],
  ])
  inspect(result.success, content="true")
  inspect(result.recommendations[0].propagation_delay_ns, content="100")
}

///|
test "analysis facade exposes health and quality scoring" {
  let analyzer = @analysis.TopologyHealthAnalyzer::new()
  analyzer.add_slave(1U, 0, 100L)
  analyzer.ingest_telemetry(0, 100L, 100L, 0L, 0L)
  let report = analyzer.analyze()
  inspect(report.system_grade, content="Excellent")

  let scorer = @analysis.CommQualityScorer::new()
  let score = scorer.score_from_telemetry(100L, 0L, 0L, 0L)
  inspect(score.grade, content="Excellent")
}
