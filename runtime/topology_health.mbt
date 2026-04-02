///|
/// 4.3 Topology Health Analyzer
///
/// 分析 EtherCAT 网络拓扑健康状态：每个从站链路质量评估、
/// 线缆长度估算（基于传播延迟）、瓶颈检测、综合拓扑健康评分。

///|
/// 单个从站的链路健康快照
pub(all) struct SlaveHealthSnapshot {
  /// 从站地址
  station : UInt
  /// 链路位置 (0-based)
  position : Int
  /// 传播延迟 (ns)
  propagation_delay_ns : Int64
  /// 估算线缆长度 (m)，基于传播延迟
  estimated_cable_length_m : Double
  /// 发送帧数
  tx_frames : Int64
  /// 接收帧数
  rx_frames : Int64
  /// 超时次数
  timeouts : Int64
  /// WKC 错误次数
  wkc_errors : Int64
  /// 丢包率 (千分比)
  loss_rate_permille : Int
  /// 链路健康评分 (0-1000，1000=完美)
  health_score : Int
  /// 链路评级
  grade : LinkGrade
}

///|
/// 链路评级
pub enum LinkGrade {
  /// 优秀：无错误
  Excellent
  /// 良好：偶尔错误
  Good
  /// 一般：可接受的错误率
  Fair
  /// 差：频繁错误
  Poor
  /// 故障：链路不可用
  Critical
} derive(Eq, Show)

///|
/// 拓扑健康分析结果
pub(all) struct TopologyHealthReport {
  /// 每个从站的健康快照
  slaves : Array[SlaveHealthSnapshot]
  /// 瓶颈从站索引 (健康分最低)
  bottleneck_index : Int?
  /// 系统总体健康分 (0-1000)
  system_health_score : Int
  /// 系统评级
  system_grade : LinkGrade
  /// 最大传播延迟 (ns)
  max_propagation_delay_ns : Int64
  /// 总估算链路长度 (m)
  total_cable_length_m : Double
  /// 警告信息
  warnings : Array[String]
}

///|
/// 铜缆传播速率：约 5.0 ns/m（典型 CAT5e 速度因子 0.64c）
let cable_propagation_ns_per_meter : Double = 5.0

///|
/// 拓扑健康分析器
pub struct TopologyHealthAnalyzer {
  /// 每个从站的统计
  slave_stats : Array[SlaveHealthAccumulator]
  /// 链路评分权重
  weight_loss : Int
  weight_timeout : Int
  weight_wkc : Int
}

///|
/// 单个从站的统计累加器
pub(all) struct SlaveHealthAccumulator {
  station : UInt
  position : Int
  propagation_delay_ns : Int64
  mut tx_frames : Int64
  mut rx_frames : Int64
  mut timeouts : Int64
  mut wkc_errors : Int64
}

///|
pub fn TopologyHealthAnalyzer::new(
  weight_loss? : Int = 400,
  weight_timeout? : Int = 350,
  weight_wkc? : Int = 250,
) -> TopologyHealthAnalyzer {
  { slave_stats: [], weight_loss, weight_timeout, weight_wkc }
}

///|
/// 添加一个从站到分析器
pub fn TopologyHealthAnalyzer::add_slave(
  self : TopologyHealthAnalyzer,
  station : UInt,
  position : Int,
  propagation_delay_ns : Int64,
) -> Unit {
  self.slave_stats.push({
    station,
    position,
    propagation_delay_ns,
    tx_frames: 0L,
    rx_frames: 0L,
    timeouts: 0L,
    wkc_errors: 0L,
  })
}

///|
/// 记录一个周期的通信结果
pub fn TopologyHealthAnalyzer::record_cycle(
  self : TopologyHealthAnalyzer,
  slave_index : Int,
  tx : Int64,
  rx : Int64,
  timeout : Bool,
  wkc_ok : Bool,
) -> Unit {
  if slave_index >= 0 && slave_index < self.slave_stats.length() {
    let s = self.slave_stats[slave_index]
    s.tx_frames = s.tx_frames + tx
    s.rx_frames = s.rx_frames + rx
    if timeout {
      s.timeouts = s.timeouts + 1L
    }
    if !wkc_ok {
      s.wkc_errors = s.wkc_errors + 1L
    }
  }
}

///|
/// 批量录入遥测数据（从 Telemetry 快照）
pub fn TopologyHealthAnalyzer::ingest_telemetry(
  self : TopologyHealthAnalyzer,
  slave_index : Int,
  tx_total : Int64,
  rx_total : Int64,
  timeouts_total : Int64,
  wkc_errors_total : Int64,
) -> Unit {
  if slave_index >= 0 && slave_index < self.slave_stats.length() {
    let s = self.slave_stats[slave_index]
    s.tx_frames = tx_total
    s.rx_frames = rx_total
    s.timeouts = timeouts_total
    s.wkc_errors = wkc_errors_total
  }
}

///|
/// 从传播延迟估算线缆长度 (m)
pub fn estimate_cable_length(propagation_delay_ns : Int64) -> Double {
  propagation_delay_ns.to_double() / cable_propagation_ns_per_meter
}

///|
/// 计算单个从站的链路健康分 (0-1000)
fn compute_link_health_score(
  tx : Int64,
  rx : Int64,
  timeouts : Int64,
  wkc_errors : Int64,
  weight_loss : Int,
  weight_timeout : Int,
  weight_wkc : Int,
) -> Int {
  if tx == 0L {
    return 1000
  }
  // 丢包率 (千分比)
  let lost = if tx > rx { tx - rx } else { 0L }
  let loss_permille = (lost * 1000L / tx).to_int()
  // 超时率 (千分比)
  let timeout_permille = (timeouts * 1000L / tx).to_int()
  // WKC 错误率 (千分比)
  let wkc_permille = (wkc_errors * 1000L / tx).to_int()
  // 加权扣分，每千分之一扣 weight/1000 的分
  let loss_deduction = loss_permille * weight_loss / 1000
  let timeout_deduction = timeout_permille * weight_timeout / 1000
  let wkc_deduction = wkc_permille * weight_wkc / 1000
  let total_deduction = loss_deduction + timeout_deduction + wkc_deduction
  let score = 1000 - total_deduction
  if score < 0 {
    0
  } else {
    score
  }
}

///|
/// 从评分推导评级
pub fn grade_from_score(score : Int) -> LinkGrade {
  if score >= 950 {
    Excellent
  } else if score >= 800 {
    Good
  } else if score >= 600 {
    Fair
  } else if score >= 300 {
    Poor
  } else {
    Critical
  }
}

///|
/// 生成拓扑健康分析报告
pub fn TopologyHealthAnalyzer::analyze(
  self : TopologyHealthAnalyzer,
) -> TopologyHealthReport {
  let snapshots : Array[SlaveHealthSnapshot] = []
  let warnings : Array[String] = []
  let mut worst_score = 1001
  let mut worst_index : Int? = None
  let mut max_delay = 0L
  let mut total_cable = 0.0
  for i = 0; i < self.slave_stats.length(); i = i + 1 {
    let s = self.slave_stats[i]
    let cable_m = estimate_cable_length(s.propagation_delay_ns)
    let lost = if s.tx_frames > s.rx_frames {
      s.tx_frames - s.rx_frames
    } else {
      0L
    }
    let loss_permille = if s.tx_frames > 0L {
      (lost * 1000L / s.tx_frames).to_int()
    } else {
      0
    }
    let score = compute_link_health_score(
      s.tx_frames,
      s.rx_frames,
      s.timeouts,
      s.wkc_errors,
      self.weight_loss,
      self.weight_timeout,
      self.weight_wkc,
    )
    let grade = grade_from_score(score)
    snapshots.push({
      station: s.station,
      position: s.position,
      propagation_delay_ns: s.propagation_delay_ns,
      estimated_cable_length_m: cable_m,
      tx_frames: s.tx_frames,
      rx_frames: s.rx_frames,
      timeouts: s.timeouts,
      wkc_errors: s.wkc_errors,
      loss_rate_permille: loss_permille,
      health_score: score,
      grade,
    })
    if score < worst_score {
      worst_score = score
      worst_index = Some(i)
    }
    if s.propagation_delay_ns > max_delay {
      max_delay = s.propagation_delay_ns
    }
    total_cable = total_cable + cable_m
    // 警告生成
    if grade is (Poor | Critical) {
      warnings.push(
        "Station " +
        s.station.to_string() +
        " (pos " +
        s.position.to_string() +
        "): link grade " +
        grade.to_string() +
        ", score " +
        score.to_string(),
      )
    }
    if cable_m > 100.0 {
      warnings.push(
        "Station " +
        s.station.to_string() +
        ": estimated cable " +
        cable_m.to_int().to_string() +
        "m exceeds EtherCAT 100m limit",
      )
    }
  }
  let sys_score = if snapshots.length() > 0 {
    let mut sum = 0
    for snap in snapshots {
      sum = sum + snap.health_score
    }
    sum / snapshots.length()
  } else {
    1000
  }
  {
    slaves: snapshots,
    bottleneck_index: worst_index,
    system_health_score: sys_score,
    system_grade: grade_from_score(sys_score),
    max_propagation_delay_ns: max_delay,
    total_cable_length_m: total_cable,
    warnings,
  }
}

///|
/// 输出拓扑健康报告 JSON
pub fn TopologyHealthReport::to_json(self : TopologyHealthReport) -> String {
  let buf = @buffer.new()
  buf.write_string("{\n")
  buf.write_string("  \"system_health_score\": ")
  buf.write_string(self.system_health_score.to_string())
  buf.write_string(",\n  \"system_grade\": \"")
  buf.write_string(self.system_grade.to_string())
  buf.write_string("\",\n  \"max_propagation_delay_ns\": ")
  buf.write_string(self.max_propagation_delay_ns.to_string())
  buf.write_string(",\n  \"total_cable_length_m\": ")
  buf.write_string(self.total_cable_length_m.to_int().to_string())
  buf.write_string(",\n  \"bottleneck_index\": ")
  match self.bottleneck_index {
    Some(i) => buf.write_string(i.to_string())
    None => buf.write_string("null")
  }
  buf.write_string(",\n  \"slaves\": [\n")
  for i = 0; i < self.slaves.length(); i = i + 1 {
    let s = self.slaves[i]
    if i > 0 {
      buf.write_string(",\n")
    }
    buf.write_string("    { \"station\": ")
    buf.write_string(s.station.to_string())
    buf.write_string(", \"position\": ")
    buf.write_string(s.position.to_string())
    buf.write_string(", \"propagation_delay_ns\": ")
    buf.write_string(s.propagation_delay_ns.to_string())
    buf.write_string(", \"cable_length_m\": ")
    buf.write_string(s.estimated_cable_length_m.to_int().to_string())
    buf.write_string(", \"tx\": ")
    buf.write_string(s.tx_frames.to_string())
    buf.write_string(", \"rx\": ")
    buf.write_string(s.rx_frames.to_string())
    buf.write_string(", \"timeouts\": ")
    buf.write_string(s.timeouts.to_string())
    buf.write_string(", \"wkc_errors\": ")
    buf.write_string(s.wkc_errors.to_string())
    buf.write_string(", \"loss_permille\": ")
    buf.write_string(s.loss_rate_permille.to_string())
    buf.write_string(", \"health_score\": ")
    buf.write_string(s.health_score.to_string())
    buf.write_string(", \"grade\": \"")
    buf.write_string(s.grade.to_string())
    buf.write_string("\" }")
  }
  buf.write_string("\n  ],\n  \"warnings\": [\n")
  for i = 0; i < self.warnings.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    buf.write_string("    \"")
    buf.write_string(self.warnings[i])
    buf.write_string("\"")
  }
  buf.write_string("\n  ]\n}")
  buf.to_string()
}
