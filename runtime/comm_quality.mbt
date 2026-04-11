///|
/// 4.5 Communication Quality Scorer
///
/// 加权综合评分系统，将抖动、丢包、WKC 错误、超时等维度合成为
/// 单一通信质量分数 (0-1000)，支持 per-slave 与系统级评分，
/// 以及滑动窗口趋势检测（恶化/稳定/改善）。

///|
/// 单个维度的评分输入
pub(all) struct QualityDimension {
  /// 维度名称
  name : String
  /// 当前值 (千分比或直接计数)
  value : Int64
  /// 该维度的满分阈值（低于此值得满分）
  good_threshold : Int64
  /// 该维度的零分阈值（高于此值得零分）
  bad_threshold : Int64
  /// 权重 (千分比，所有维度权重之和应为 1000)
  weight : Int
}

///|
/// 通信质量评分结果
pub(all) struct QualityScore {
  /// 综合分 (0-1000)
  overall : Int
  /// 各维度的分项得分 (0-1000)
  dimensions : Array[(String, Int)]
  /// 趋势
  trend : QualityTrend
  /// 评级
  grade : QualityGrade
}

///|
/// 质量趋势
pub enum QualityTrend {
  /// 持续改善
  Improving
  /// 基本稳定
  Stable
  /// 正在恶化
  Degrading
} derive(Eq, Debug)

///|
/// 质量评级
pub enum QualityGrade {
  /// 优 (≥900)
  Excellent
  /// 良 (≥750)
  Good
  /// 中 (≥500)
  Acceptable
  /// 差 (≥250)
  Poor
  /// 严重 (<250)
  Critical
} derive(Eq, Debug)

///|
/// 从综合分推导评级
pub fn quality_grade_from_score(score : Int) -> QualityGrade {
  if score >= 900 {
    Excellent
  } else if score >= 750 {
    Good
  } else if score >= 500 {
    Acceptable
  } else if score >= 250 {
    Poor
  } else {
    Critical
  }
}

///|
/// 通信质量评分器
pub struct CommQualityScorer {
  /// 评分历史 (滑动窗口)
  history : Array[Int]
  mut history_pos : Int
  history_size : Int
  /// 上一窗口平均分
  mut prev_window_avg : Int
  /// 当前累计样本数
  mut sample_count : Int64
}

///|
pub fn CommQualityScorer::new(history_size? : Int = 50) -> CommQualityScorer {
  {
    history: Array::make(history_size, 0),
    history_pos: 0,
    history_size,
    prev_window_avg: 1000,
    sample_count: 0L,
  }
}

///|
/// 计算单个维度的分数 (0-1000)
/// 线性插值：value ≤ good → 1000, value ≥ bad → 0
pub fn score_dimension(dim : QualityDimension) -> Int {
  if dim.value <= dim.good_threshold {
    return 1000
  }
  if dim.value >= dim.bad_threshold {
    return 0
  }
  let range = dim.bad_threshold - dim.good_threshold
  if range <= 0L {
    return 0
  }
  let excess = dim.value - dim.good_threshold
  let score = 1000L - excess * 1000L / range
  score.to_int()
}

///|
/// 从多个维度计算加权综合分
pub fn compute_quality_score(
  dimensions : Array[QualityDimension],
) -> (Int, Array[(String, Int)]) {
  let mut weighted_sum = 0
  let mut total_weight = 0
  let dim_scores : Array[(String, Int)] = []
  for d in dimensions {
    let s = score_dimension(d)
    dim_scores.push((d.name, s))
    weighted_sum = weighted_sum + s * d.weight
    total_weight = total_weight + d.weight
  }
  let overall = if total_weight > 0 {
    weighted_sum / total_weight
  } else {
    1000
  }
  (overall, dim_scores)
}

///|
/// 记录一次评分并更新趋势窗口
pub fn CommQualityScorer::record_score(
  self : CommQualityScorer,
  score : Int,
) -> Unit {
  self.history[self.history_pos] = score
  self.history_pos = (self.history_pos + 1) % self.history_size
  self.sample_count = self.sample_count + 1L
  // 每窗口更新
  if self.sample_count > 0L &&
    self.sample_count % self.history_size.to_int64() == 0L {
    let mut sum = 0
    for i = 0; i < self.history_size; i = i + 1 {
      sum = sum + self.history[i]
    }
    self.prev_window_avg = sum / self.history_size
  }
}

///|
/// 检测当前趋势
pub fn CommQualityScorer::trend(self : CommQualityScorer) -> QualityTrend {
  if self.sample_count < self.history_size.to_int64() * 2L {
    return Stable
  }
  let mut sum = 0
  for i = 0; i < self.history_size; i = i + 1 {
    sum = sum + self.history[i]
  }
  let current_avg = sum / self.history_size
  let threshold = 50 // 50分变化视为趋势
  if current_avg + threshold < self.prev_window_avg {
    Degrading
  } else if current_avg > self.prev_window_avg + threshold {
    Improving
  } else {
    Stable
  }
}

///|
/// 从 Telemetry 快照一站式评分
pub fn CommQualityScorer::score_from_telemetry(
  self : CommQualityScorer,
  cycles : Int64,
  timeouts : Int64,
  wkc_errors : Int64,
  retries : Int64,
  jitter_p99_abs_ns? : Int64 = 0L,
  nominal_period_ns? : Int64 = 1_000_000L,
) -> QualityScore {
  // 超时率（千分比）
  let timeout_permille = if cycles > 0L {
    timeouts * 1000L / cycles
  } else {
    0L
  }
  // WKC 错误率（千分比）
  let wkc_permille = if cycles > 0L { wkc_errors * 1000L / cycles } else { 0L }
  // 重试率（千分比）
  let retry_permille = if cycles > 0L { retries * 1000L / cycles } else { 0L }
  // 抖动率（p99 占标称周期千分比）
  let jitter_permille = if nominal_period_ns > 0L {
    jitter_p99_abs_ns * 1000L / nominal_period_ns
  } else {
    0L
  }
  let dims : Array[QualityDimension] = [
    {
      name: "timeout_rate",
      value: timeout_permille,
      good_threshold: 0L,
      bad_threshold: 100L,
      weight: 300,
    },
    {
      name: "wkc_error_rate",
      value: wkc_permille,
      good_threshold: 0L,
      bad_threshold: 50L,
      weight: 300,
    },
    {
      name: "retry_rate",
      value: retry_permille,
      good_threshold: 0L,
      bad_threshold: 200L,
      weight: 150,
    },
    {
      name: "jitter_ratio",
      value: jitter_permille,
      good_threshold: 10L,
      bad_threshold: 200L,
      weight: 250,
    },
  ]
  let (overall, dim_scores) = compute_quality_score(dims)
  self.record_score(overall)
  {
    overall,
    dimensions: dim_scores,
    trend: self.trend(),
    grade: quality_grade_from_score(overall),
  }
}

///|
/// 输出质量评分 JSON
pub fn QualityScore::to_json(self : QualityScore) -> String {
  let buf = @buffer.new()
  buf.write_string("{\n")
  buf.write_string("  \"overall\": ")
  buf.write_string(self.overall.to_string())
  buf.write_string(",\n  \"grade\": \"")
  buf.write_string(self.grade.to_string())
  buf.write_string("\",\n  \"trend\": \"")
  buf.write_string(self.trend.to_string())
  buf.write_string("\",\n  \"dimensions\": {\n")
  for i = 0; i < self.dimensions.length(); i = i + 1 {
    let (name, score) = self.dimensions[i]
    if i > 0 {
      buf.write_string(",\n")
    }
    buf.write_string("    \"")
    buf.write_string(name)
    buf.write_string("\": ")
    buf.write_string(score.to_string())
  }
  buf.write_string("\n  }\n}")
  buf.to_string()
}
