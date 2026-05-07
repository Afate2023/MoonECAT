///|
/// 4.4 Cycle Performance Analyzer
///
/// 实时周期性能追踪：周期时间分布统计、截止时间违规检测、
/// 吞吐量分析、滑动窗口趋势检测。

///|
/// 单个周期的性能记录
pub(all) struct CyclePerfSample {
  /// 周期编号
  cycle : Int64
  /// 周期实际耗时 (ns)
  duration_ns : Int64
  /// 是否违反截止时间
  deadline_miss : Bool
  /// 周期内发送帧数
  tx_frames : Int
  /// 周期内接收帧数
  rx_frames : Int
}

///|
/// 周期性能统计摘要
pub(all) struct CyclePerfStats {
  /// 总周期数
  total_cycles : Int64
  /// 最小周期耗时 (ns)
  min_ns : Int64
  /// 最大周期耗时 (ns)
  max_ns : Int64
  /// 平均周期耗时 (ns)
  mean_ns : Int64
  /// 标准差 (ns)，近似值
  stddev_ns : Int64
  /// 截止时间违规次数
  deadline_misses : Int64
  /// 截止时间违规率 (千分比)
  deadline_miss_rate_permille : Int
  /// 总发送帧数
  total_tx : Int64
  /// 总接收帧数
  total_rx : Int64
  /// p50 周期耗时 (ns)
  p50_ns : Int64
  /// p95 周期耗时 (ns)
  p95_ns : Int64
  /// p99 周期耗时 (ns)
  p99_ns : Int64
}

///|
/// 滑动窗口趋势
pub enum PerfTrend {
  /// 性能稳定
  Stable
  /// 性能改善
  Improving
  /// 性能恶化
  Degrading
} derive(Eq, Debug)

///|
/// 周期性能分析器
pub struct CyclePerfAnalyzer {
  /// 标称周期 (ns)
  nominal_period_ns : Int64
  /// 截止时间容差 (ns)：实际周期超过 nominal + tolerance 视为违规
  deadline_tolerance_ns : Int64
  /// 周期耗时直方图
  histogram : JitterHistogram
  /// 统计量
  mut total_cycles : Int64
  mut min_ns : Int64
  mut max_ns : Int64
  mut sum_ns : Int64
  mut sum_sq_ns : Int64
  mut deadline_misses : Int64
  mut total_tx : Int64
  mut total_rx : Int64
  /// 上一次时间戳
  mut last_ts : Int64
  mut started : Bool
  /// 滑动窗口 (最近 N 个周期耗时)
  window : Array[Int64]
  mut window_pos : Int
  window_size : Int
  /// 上一窗口的平均值，用于比较趋势
  mut prev_window_mean : Int64
}

///|
pub fn CyclePerfAnalyzer::new(
  nominal_period_ns : Int64,
  deadline_tolerance_ns? : Int64 = 0L,
  window_size? : Int = 100,
  histogram_bin_width? : Int64 = 1000L,
  histogram_bins? : Int = 201,
) -> CyclePerfAnalyzer {
  let tol = if deadline_tolerance_ns > 0L {
    deadline_tolerance_ns
  } else {
    nominal_period_ns / 10L
  }
  {
    nominal_period_ns,
    deadline_tolerance_ns: tol,
    histogram: JitterHistogram::new(
      bin_width=histogram_bin_width,
      num_bins=histogram_bins,
    ),
    total_cycles: 0L,
    min_ns: 9223372036854775807L,
    max_ns: 0L,
    sum_ns: 0L,
    sum_sq_ns: 0L,
    deadline_misses: 0L,
    total_tx: 0L,
    total_rx: 0L,
    last_ts: 0L,
    started: false,
    window: Array::make(window_size, 0L),
    window_pos: 0,
    window_size,
    prev_window_mean: 0L,
  }
}

///|
/// 记录一个周期的时间戳和帧计数
pub fn CyclePerfAnalyzer::record(
  self : CyclePerfAnalyzer,
  timestamp_ns : Int64,
  tx_frames? : Int = 1,
  rx_frames? : Int = 1,
) -> Unit {
  if !self.started {
    self.last_ts = timestamp_ns
    self.started = true
    return
  }
  let duration = timestamp_ns - self.last_ts
  self.last_ts = timestamp_ns
  self.total_cycles = self.total_cycles + 1L
  // min/max
  if duration < self.min_ns {
    self.min_ns = duration
  }
  if duration > self.max_ns {
    self.max_ns = duration
  }
  self.sum_ns = self.sum_ns + duration
  self.sum_sq_ns = self.sum_sq_ns + duration * duration
  // 截止违规
  let deadline = self.nominal_period_ns + self.deadline_tolerance_ns
  if duration > deadline {
    self.deadline_misses = self.deadline_misses + 1L
  }
  // 帧统计
  self.total_tx = self.total_tx + tx_frames.to_int64()
  self.total_rx = self.total_rx + rx_frames.to_int64()
  // 直方图 (记录偏差)
  let deviation = duration - self.nominal_period_ns
  self.histogram.record(deviation)
  // 滑动窗口
  self.window[self.window_pos] = duration
  self.window_pos = (self.window_pos + 1) % self.window_size
  // 每窗口更新趋势
  if self.total_cycles > 0L &&
    self.total_cycles % self.window_size.to_int64() == 0L {
    let mut wsum = 0L
    for i = 0; i < self.window_size; i = i + 1 {
      wsum = wsum + self.window[i]
    }
    self.prev_window_mean = wsum / self.window_size.to_int64()
  }
}

///|
/// 直接录入一个周期耗时（不通过时间戳差分）
pub fn CyclePerfAnalyzer::record_duration(
  self : CyclePerfAnalyzer,
  duration_ns : Int64,
) -> Unit {
  self.total_cycles = self.total_cycles + 1L
  if duration_ns < self.min_ns {
    self.min_ns = duration_ns
  }
  if duration_ns > self.max_ns {
    self.max_ns = duration_ns
  }
  self.sum_ns = self.sum_ns + duration_ns
  self.sum_sq_ns = self.sum_sq_ns + duration_ns * duration_ns
  let deadline = self.nominal_period_ns + self.deadline_tolerance_ns
  if duration_ns > deadline {
    self.deadline_misses = self.deadline_misses + 1L
  }
  let deviation = duration_ns - self.nominal_period_ns
  self.histogram.record(deviation)
  self.window[self.window_pos] = duration_ns
  self.window_pos = (self.window_pos + 1) % self.window_size
}

///|
/// 检测当前滑动窗口的性能趋势
pub fn CyclePerfAnalyzer::trend(self : CyclePerfAnalyzer) -> PerfTrend {
  if self.total_cycles < self.window_size.to_int64() * 2L {
    return Stable
  }
  let mut wsum = 0L
  for i = 0; i < self.window_size; i = i + 1 {
    wsum = wsum + self.window[i]
  }
  let current_mean = wsum / self.window_size.to_int64()
  // 趋势阈值：5%
  let threshold = self.nominal_period_ns / 20L
  if current_mean > self.prev_window_mean + threshold {
    Degrading
  } else if current_mean + threshold < self.prev_window_mean {
    Improving
  } else {
    Stable
  }
}

///|
/// 生成性能统计摘要
pub fn CyclePerfAnalyzer::stats(self : CyclePerfAnalyzer) -> CyclePerfStats {
  if self.total_cycles == 0L {
    return {
      total_cycles: 0L,
      min_ns: 0L,
      max_ns: 0L,
      mean_ns: 0L,
      stddev_ns: 0L,
      deadline_misses: 0L,
      deadline_miss_rate_permille: 0,
      total_tx: self.total_tx,
      total_rx: self.total_rx,
      p50_ns: 0L,
      p95_ns: 0L,
      p99_ns: 0L,
    }
  }
  let n = self.total_cycles
  let mean = self.sum_ns / n
  // stddev = sqrt(E[X^2] - E[X]^2)
  let variance = self.sum_sq_ns / n - mean * mean
  let stddev = if variance > 0L { isqrt64(variance) } else { 0L }
  let miss_permille = if n > 0L {
    (self.deadline_misses * 1000L / n).to_int()
  } else {
    0
  }
  {
    total_cycles: n,
    min_ns: self.min_ns,
    max_ns: self.max_ns,
    mean_ns: mean,
    stddev_ns: stddev,
    deadline_misses: self.deadline_misses,
    deadline_miss_rate_permille: miss_permille,
    total_tx: self.total_tx,
    total_rx: self.total_rx,
    p50_ns: self.nominal_period_ns + self.histogram.percentile(50),
    p95_ns: self.nominal_period_ns + self.histogram.percentile(95),
    p99_ns: self.nominal_period_ns + self.histogram.percentile(99),
  }
}

///|
/// 重置分析器
pub fn CyclePerfAnalyzer::reset(self : CyclePerfAnalyzer) -> Unit {
  self.total_cycles = 0L
  self.min_ns = 9223372036854775807L
  self.max_ns = 0L
  self.sum_ns = 0L
  self.sum_sq_ns = 0L
  self.deadline_misses = 0L
  self.total_tx = 0L
  self.total_rx = 0L
  self.last_ts = 0L
  self.started = false
  self.prev_window_mean = 0L
  self.window_pos = 0
  for i = 0; i < self.window_size; i = i + 1 {
    self.window[i] = 0L
  }
  for i = 0; i < self.histogram.counts.length(); i = i + 1 {
    self.histogram.counts[i] = 0L
  }
  self.histogram.total = 0L
}

///|
/// 整数平方根（牛顿法）
fn isqrt64(n : Int64) -> Int64 {
  if n <= 0L {
    return 0L
  }
  let mut x = n
  let mut y = (x + 1L) / 2L
  while y < x {
    x = y
    y = (x + n / x) / 2L
  }
  x
}

///|
/// 输出周期性能报告 JSON
pub fn CyclePerfStats::to_json(self : CyclePerfStats) -> String {
  let buf = @buffer.new()
  buf.write_string("{\n")
  buf.write_string("  \"total_cycles\": ")
  buf.write_string(self.total_cycles.to_string())
  buf.write_string(",\n  \"min_ns\": ")
  buf.write_string(self.min_ns.to_string())
  buf.write_string(",\n  \"max_ns\": ")
  buf.write_string(self.max_ns.to_string())
  buf.write_string(",\n  \"mean_ns\": ")
  buf.write_string(self.mean_ns.to_string())
  buf.write_string(",\n  \"stddev_ns\": ")
  buf.write_string(self.stddev_ns.to_string())
  buf.write_string(",\n  \"p50_ns\": ")
  buf.write_string(self.p50_ns.to_string())
  buf.write_string(",\n  \"p95_ns\": ")
  buf.write_string(self.p95_ns.to_string())
  buf.write_string(",\n  \"p99_ns\": ")
  buf.write_string(self.p99_ns.to_string())
  buf.write_string(",\n  \"deadline_misses\": ")
  buf.write_string(self.deadline_misses.to_string())
  buf.write_string(",\n  \"deadline_miss_rate_permille\": ")
  buf.write_string(self.deadline_miss_rate_permille.to_string())
  buf.write_string(",\n  \"total_tx\": ")
  buf.write_string(self.total_tx.to_string())
  buf.write_string(",\n  \"total_rx\": ")
  buf.write_string(self.total_rx.to_string())
  buf.write_string("\n}")
  buf.to_string()
}
