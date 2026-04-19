///|
/// 4.1 DC Jitter Profiling — DC 抖动图
///
/// 旁路监听带有硬件时间戳的 Rx/Tx Event 流，实时计算主站发包抖动与
/// 从站同步时钟漂移量，输出纳秒级抖动直方图。

///|
/// 抖动样本：一个周期的时间戳差异
pub struct JitterSample {
  /// 第几个周期
  cycle : Int64
  /// 实际周期 (ns)
  actual_ns : Int64
  /// 与标称周期的偏差 (ns)，正=迟，负=早
  deviation_ns : Int64
}

///|
/// 桶式直方图——将抖动偏差分到 [bin_min, bin_min+bin_width) 范围的桶中
pub struct JitterHistogram {
  /// 每个桶的宽度 (ns)
  bin_width : Int64
  /// 中心桶对应 deviation=0 的下标
  center_index : Int
  /// 每个桶的计数
  counts : Array[Int64]
  /// 总样本数
  mut total : Int64
  /// 桶覆盖范围下界 (ns)
  range_min_ns : Int64
  /// 桶覆盖范围上界 (ns)
  range_max_ns : Int64
}

///|
pub fn JitterHistogram::new(
  bin_width? : Int64 = 100L,
  num_bins? : Int = 201,
) -> JitterHistogram {
  let center = num_bins / 2
  let range_min = -center.to_int64() * bin_width
  let range_max = (num_bins - center).to_int64() * bin_width
  {
    bin_width,
    center_index: center,
    counts: Array::make(num_bins, 0L),
    total: 0L,
    range_min_ns: range_min,
    range_max_ns: range_max,
  }
}

///|
/// 将一个偏差值录入直方图
pub fn JitterHistogram::record(
  self : JitterHistogram,
  deviation_ns : Int64,
) -> Unit {
  let idx = (deviation_ns / self.bin_width).to_int() + self.center_index
  let clamped = if idx < 0 {
    0
  } else if idx >= self.counts.length() {
    self.counts.length() - 1
  } else {
    idx
  }
  self.counts[clamped] = self.counts[clamped] + 1L
  self.total = self.total + 1L
}

///|
/// 从直方图中查询某百分位对应的偏差值 (ns)
pub fn JitterHistogram::percentile(self : JitterHistogram, pct : Int) -> Int64 {
  if self.total == 0L {
    return 0L
  }
  let threshold = (self.total * pct.to_int64() + 99L) / 100L
  let mut cumulative = 0L
  for i = 0; i < self.counts.length(); i = i + 1 {
    cumulative = cumulative + self.counts[i]
    if cumulative >= threshold {
      return (i - self.center_index).to_int64() * self.bin_width
    }
  }
  self.range_max_ns
}

///|
/// 抖动统计摘要
pub struct JitterStats {
  /// 样本数
  count : Int64
  /// 最小偏差 (ns)
  min_ns : Int64
  /// 最大偏差 (ns)
  max_ns : Int64
  /// 累计偏差 (用于平均)
  sum_ns : Int64
  /// 累计偏差平方 (用于方差)
  sum_sq_ns : Int64
  /// 平均偏差 (ns)
  mean_ns : Int64
  /// p50 (ns)
  p50_ns : Int64
  /// p95 (ns)
  p95_ns : Int64
  /// p99 (ns)
  p99_ns : Int64
  /// peak-to-peak (max - min)
  peak_to_peak_ns : Int64
}

///|
/// DC 抖动分析器
pub struct DcJitterProfiler {
  /// 标称周期 (ns)
  nominal_period_ns : Int64
  /// 直方图
  histogram : JitterHistogram
  /// 最近 N 个样本 (环形缓冲)
  recent_samples : Array[JitterSample]
  /// 环形写指针
  mut write_pos : Int
  /// 统计量
  mut count : Int64
  mut min_dev : Int64
  mut max_dev : Int64
  mut sum_dev : Int64
  mut sum_sq_dev : Int64
  /// 上一次时间戳
  mut last_timestamp_ns : Int64
  /// 是否已收到首帧
  mut started : Bool
}

///|
pub fn DcJitterProfiler::new(
  nominal_period_ns : Int64,
  bin_width? : Int64 = 100L,
  num_bins? : Int = 201,
  recent_capacity? : Int = 256,
) -> DcJitterProfiler {
  {
    nominal_period_ns,
    histogram: JitterHistogram::new(bin_width~, num_bins~),
    recent_samples: Array::make(recent_capacity, {
      cycle: 0L,
      actual_ns: 0L,
      deviation_ns: 0L,
    }),
    write_pos: 0,
    count: 0L,
    min_dev: 9223372036854775807L,
    max_dev: -9223372036854775807L,
    sum_dev: 0L,
    sum_sq_dev: 0L,
    last_timestamp_ns: 0L,
    started: false,
  }
}

///|
/// 接收一个硬件时间戳 (ns)，计算与上一帧的间隔并统计抖动
pub fn DcJitterProfiler::record_timestamp(
  self : DcJitterProfiler,
  timestamp_ns : Int64,
) -> Unit {
  if !self.started {
    self.last_timestamp_ns = timestamp_ns
    self.started = true
    return
  }
  let actual = timestamp_ns - self.last_timestamp_ns
  let deviation = actual - self.nominal_period_ns
  self.last_timestamp_ns = timestamp_ns
  // 更新统计
  self.count = self.count + 1L
  if deviation < self.min_dev {
    self.min_dev = deviation
  }
  if deviation > self.max_dev {
    self.max_dev = deviation
  }
  self.sum_dev = self.sum_dev + deviation
  self.sum_sq_dev = self.sum_sq_dev + deviation * deviation
  // 记录直方图
  self.histogram.record(deviation)
  // 环形缓冲记录
  let sample : JitterSample = {
    cycle: self.count,
    actual_ns: actual,
    deviation_ns: deviation,
  }
  self.recent_samples[self.write_pos] = sample
  self.write_pos = (self.write_pos + 1) % self.recent_samples.length()
}

///|
/// 生成统计摘要
pub fn DcJitterProfiler::stats(self : DcJitterProfiler) -> JitterStats {
  if self.count == 0L {
    return {
      count: 0L,
      min_ns: 0L,
      max_ns: 0L,
      sum_ns: 0L,
      sum_sq_ns: 0L,
      mean_ns: 0L,
      p50_ns: 0L,
      p95_ns: 0L,
      p99_ns: 0L,
      peak_to_peak_ns: 0L,
    }
  }
  let mean = self.sum_dev / self.count
  {
    count: self.count,
    min_ns: self.min_dev,
    max_ns: self.max_dev,
    sum_ns: self.sum_dev,
    sum_sq_ns: self.sum_sq_dev,
    mean_ns: mean,
    p50_ns: self.histogram.percentile(50),
    p95_ns: self.histogram.percentile(95),
    p99_ns: self.histogram.percentile(99),
    peak_to_peak_ns: self.max_dev - self.min_dev,
  }
}

///|
/// 重置分析器
pub fn DcJitterProfiler::reset(self : DcJitterProfiler) -> Unit {
  self.count = 0L
  self.min_dev = 9223372036854775807L
  self.max_dev = -9223372036854775807L
  self.sum_dev = 0L
  self.sum_sq_dev = 0L
  self.last_timestamp_ns = 0L
  self.started = false
  self.write_pos = 0
  for i = 0; i < self.histogram.counts.length(); i = i + 1 {
    self.histogram.counts[i] = 0L
  }
  self.histogram.total = 0L
}

///|
/// 判断抖动是否在可接受范围内
pub fn DcJitterProfiler::is_within_tolerance(
  self : DcJitterProfiler,
  max_peak_to_peak_ns : Int64,
  max_p99_abs_ns : Int64,
) -> Bool {
  if self.count == 0L {
    return true
  }
  let pk2pk = self.max_dev - self.min_dev
  let p99 = self.histogram.percentile(99)
  let p99_abs = if p99 < 0L { -p99 } else { p99 }
  pk2pk <= max_peak_to_peak_ns && p99_abs <= max_p99_abs_ns
}

///|
/// 输出抖动分析报告 JSON
pub fn DcJitterProfiler::to_json(self : DcJitterProfiler) -> String {
  let s = self.stats()
  let buf = @buffer.new()
  buf.write_string("{\n")
  buf.write_string("  \"nominal_period_ns\": ")
  buf.write_string(self.nominal_period_ns.to_string())
  buf.write_string(",\n  \"sample_count\": ")
  buf.write_string(s.count.to_string())
  buf.write_string(",\n  \"min_deviation_ns\": ")
  buf.write_string(s.min_ns.to_string())
  buf.write_string(",\n  \"max_deviation_ns\": ")
  buf.write_string(s.max_ns.to_string())
  buf.write_string(",\n  \"mean_deviation_ns\": ")
  buf.write_string(s.mean_ns.to_string())
  buf.write_string(",\n  \"peak_to_peak_ns\": ")
  buf.write_string(s.peak_to_peak_ns.to_string())
  buf.write_string(",\n  \"p50_ns\": ")
  buf.write_string(s.p50_ns.to_string())
  buf.write_string(",\n  \"p95_ns\": ")
  buf.write_string(s.p95_ns.to_string())
  buf.write_string(",\n  \"p99_ns\": ")
  buf.write_string(s.p99_ns.to_string())
  buf.write_string("\n}")
  buf.to_string()
}

///|
/// 多通道抖动分析器——同时跟踪主站 Tx、从站 Rx 等多路时间戳流
pub struct MultiChannelJitterProfiler {
  /// 通道名 -> 分析器
  channels : Array[(String, DcJitterProfiler)]
}

///|
pub fn MultiChannelJitterProfiler::new() -> MultiChannelJitterProfiler {
  { channels: [] }
}

///|
pub fn MultiChannelJitterProfiler::add_channel(
  self : MultiChannelJitterProfiler,
  name : String,
  nominal_period_ns : Int64,
  bin_width? : Int64 = 100L,
) -> Unit {
  let p = DcJitterProfiler::new(nominal_period_ns, bin_width~)
  self.channels.push((name, p))
}

///|
pub fn MultiChannelJitterProfiler::record(
  self : MultiChannelJitterProfiler,
  channel_index : Int,
  timestamp_ns : Int64,
) -> Unit {
  if channel_index >= 0 && channel_index < self.channels.length() {
    let (_, profiler) = self.channels[channel_index]
    profiler.record_timestamp(timestamp_ns)
  }
}

///|
pub fn MultiChannelJitterProfiler::summary_json(
  self : MultiChannelJitterProfiler,
) -> String {
  let buf = @buffer.new()
  buf.write_string("{ \"channels\": [\n")
  for i = 0; i < self.channels.length(); i = i + 1 {
    let (name, profiler) = self.channels[i]
    if i > 0 {
      buf.write_string(",\n")
    }
    buf.write_string("  { \"name\": \"")
    buf.write_string(name)
    buf.write_string("\", \"profile\": ")
    buf.write_string(profiler.to_json())
    buf.write_string(" }")
  }
  buf.write_string("\n] }")
  buf.to_string()
}
