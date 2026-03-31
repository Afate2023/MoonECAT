///|
/// 4.2 PDO 同步时间参数在线识别 (Online PDO Auto-Tuning)
///
/// 启动阶段自动发送探测帧，结合硬件时间戳计算菊花链拓扑延迟与传输延迟，
/// 自动推算并写入最优 Sync0/Sync1 偏移量。

///|
/// 探测结果：单个从站的传播延迟测量
pub struct ProbeResult {
  /// 从站地址
  station : UInt
  /// 正向传播延迟 (ns)
  forward_delay_ns : Int64
  /// 反向传播延迟 (ns)
  reverse_delay_ns : Int64
  /// 双程往返延迟 (ns)
  round_trip_ns : Int64
  /// 端口0 接收时间戳
  recv_time_port0 : Int64
  /// 端口1/2/3 接收时间戳 (如果有)
  recv_time_port1 : Int64
}

///|
/// 单个从站的 Sync0/Sync1 偏移推荐
pub struct SyncOffsetRecommendation {
  /// 从站地址
  station : UInt
  /// 推荐 Sync0 偏移 (ns)
  sync0_offset_ns : Int64
  /// 推荐 Sync1 偏移 (ns，0 = 不使用 Sync1)
  sync1_offset_ns : Int64
  /// 推荐 Sync0 周期 (ns)
  sync0_cycle_ns : Int64
  /// 该从站到参考时钟的传播延迟 (ns)
  propagation_delay_ns : Int64
}

///|
/// 自动调优策略
pub enum TuningStrategy {
  /// 保守：合格即停，大 margin
  Conservative
  /// 平衡：中等 margin
  Balanced
  /// 激进：最小 margin，追求最低延迟
  Aggressive
}

///|
/// 自动调优配置
pub struct AutoTuneConfig {
  /// 探测迭代次数 (多次取平均)
  probe_iterations : Int
  /// 探测帧超时 (ns)
  probe_timeout_ns : Int64
  /// 调优策略
  strategy : TuningStrategy
  /// 主站周期时间 (ns)
  cycle_time_ns : Int64
  /// Sync0 起始偏移基准 (ns)，通常等于 cycle_time
  sync0_base_offset_ns : Int64
  /// Sync1 使能
  sync1_enabled : Bool
  /// Sync1 与 Sync0 的固定偏移 (ns)
  sync1_delta_ns : Int64
  /// 安全裕度因子 (千分比)，如 100 表示 10%
  safety_margin_permille : Int
}

///|
pub fn AutoTuneConfig::default() -> AutoTuneConfig {
  {
    probe_iterations: 10,
    probe_timeout_ns: 5_000_000L,
    strategy: Balanced,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 1_000_000L,
    sync1_enabled: false,
    sync1_delta_ns: 0L,
    safety_margin_permille: 100,
  }
}

///|
pub fn AutoTuneConfig::conservative() -> AutoTuneConfig {
  {
    probe_iterations: 20,
    probe_timeout_ns: 10_000_000L,
    strategy: Conservative,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 1_000_000L,
    sync1_enabled: false,
    sync1_delta_ns: 0L,
    safety_margin_permille: 200,
  }
}

///|
pub fn AutoTuneConfig::aggressive() -> AutoTuneConfig {
  {
    probe_iterations: 5,
    probe_timeout_ns: 2_000_000L,
    strategy: Aggressive,
    cycle_time_ns: 1_000_000L,
    sync0_base_offset_ns: 1_000_000L,
    sync1_enabled: false,
    sync1_delta_ns: 0L,
    safety_margin_permille: 50,
  }
}

///|
/// 自动调优结果
pub struct AutoTuneResult {
  /// 每个从站的偏移推荐
  recommendations : Array[SyncOffsetRecommendation]
  /// 每个从站的探测原始数据
  probe_data : Array[ProbeResult]
  /// 参考站地址
  reference_station : UInt
  /// 总测量时间 (ns)
  measurement_duration_ns : Int64
  /// 是否全部成功
  success : Bool
  /// 错误/警告信息
  messages : Array[String]
}

///|
/// PDO 自动调优器
pub struct PdoAutoTuner {
  config : AutoTuneConfig
  /// 每个从站的历次探测数据
  probe_history : Array[Array[ProbeResult]]
  /// 最终推荐
  mut result : AutoTuneResult?
}

///|
pub fn PdoAutoTuner::new(
  config? : AutoTuneConfig = AutoTuneConfig::default(),
) -> PdoAutoTuner {
  { config, probe_history: [], result: None }
}

///|
/// 模拟探测：从已有的接收时间戳计算传播延迟
/// 在实际系统中这会调用 dc_read_receive_time / dc_latch_times
pub fn compute_probe_result(
  station : UInt,
  recv_time_port0 : Int64,
  recv_time_port1 : Int64,
  reference_time : Int64,
) -> ProbeResult {
  let forward = recv_time_port0 - reference_time
  let reverse = recv_time_port1 - recv_time_port0
  let round_trip = forward + reverse
  {
    station,
    forward_delay_ns: forward,
    reverse_delay_ns: reverse,
    round_trip_ns: round_trip,
    recv_time_port0,
    recv_time_port1,
  }
}

///|
/// 从多次探测取平均
pub fn average_probe(probes : Array[ProbeResult]) -> ProbeResult {
  if probes.length() == 0 {
    return {
      station: 0U,
      forward_delay_ns: 0L,
      reverse_delay_ns: 0L,
      round_trip_ns: 0L,
      recv_time_port0: 0L,
      recv_time_port1: 0L,
    }
  }
  let n = probes.length().to_int64()
  let station = probes[0].station
  let mut sum_fwd = 0L
  let mut sum_rev = 0L
  let mut sum_rt = 0L
  for i = 0; i < probes.length(); i = i + 1 {
    sum_fwd = sum_fwd + probes[i].forward_delay_ns
    sum_rev = sum_rev + probes[i].reverse_delay_ns
    sum_rt = sum_rt + probes[i].round_trip_ns
  }
  {
    station,
    forward_delay_ns: sum_fwd / n,
    reverse_delay_ns: sum_rev / n,
    round_trip_ns: sum_rt / n,
    recv_time_port0: probes[0].recv_time_port0,
    recv_time_port1: probes[0].recv_time_port1,
  }
}

///|
/// 根据策略和平均延迟推算 Sync0/Sync1 偏移
pub fn compute_sync_offsets(
  config : AutoTuneConfig,
  avg_probe : ProbeResult,
) -> SyncOffsetRecommendation {
  let prop_delay = avg_probe.forward_delay_ns
  // 安全裕度
  let margin = prop_delay * config.safety_margin_permille.to_int64() / 1000L
  // Sync0 偏移 = 基准偏移 + 传播延迟 + 裕度
  let sync0 = config.sync0_base_offset_ns + prop_delay + margin
  let sync1 = if config.sync1_enabled {
    sync0 + config.sync1_delta_ns
  } else {
    0L
  }
  {
    station: avg_probe.station,
    sync0_offset_ns: sync0,
    sync1_offset_ns: sync1,
    sync0_cycle_ns: config.cycle_time_ns,
    propagation_delay_ns: prop_delay,
  }
}

///|
/// 离线分析：给定预采集的探测数据，计算所有从站的最优偏移
pub fn PdoAutoTuner::analyze(
  self : PdoAutoTuner,
  stations : Array[UInt],
  probe_data : Array[Array[ProbeResult]],
) -> AutoTuneResult {
  let recommendations : Array[SyncOffsetRecommendation] = []
  let averaged : Array[ProbeResult] = []
  let messages : Array[String] = []
  let mut all_ok = true
  let reference = if stations.length() > 0 { stations[0] } else { 0U }
  for i = 0; i < stations.length(); i = i + 1 {
    if i < probe_data.length() && probe_data[i].length() > 0 {
      let avg = average_probe(probe_data[i])
      averaged.push(avg)
      let rec = compute_sync_offsets(self.config, avg)
      recommendations.push(rec)
      // 检查往返延迟是否在合理范围
      if avg.round_trip_ns > self.config.cycle_time_ns {
        let msg = "WARNING: Station " +
          stations[i].to_string() +
          " round-trip (" +
          avg.round_trip_ns.to_string() +
          "ns) exceeds cycle time"
        messages.push(msg)
      }
    } else {
      messages.push(
        "ERROR: No probe data for station " + stations[i].to_string(),
      )
      all_ok = false
    }
  }
  let result : AutoTuneResult = {
    recommendations,
    probe_data: averaged,
    reference_station: reference,
    measurement_duration_ns: 0L,
    success: all_ok,
    messages,
  }
  self.result = Some(result)
  result
}

///|
/// 验证推荐偏移是否合理
pub fn validate_recommendations(
  result : AutoTuneResult,
  max_offset_ns : Int64,
) -> Array[String] {
  let errors : Array[String] = []
  for i = 0; i < result.recommendations.length(); i = i + 1 {
    let rec = result.recommendations[i]
    if rec.sync0_offset_ns > max_offset_ns {
      let msg = "Station " +
        rec.station.to_string() +
        " Sync0 offset (" +
        rec.sync0_offset_ns.to_string() +
        "ns) exceeds limit (" +
        max_offset_ns.to_string() +
        "ns)"
      errors.push(msg)
    }
    if rec.sync1_offset_ns > max_offset_ns && rec.sync1_offset_ns != 0L {
      let msg = "Station " +
        rec.station.to_string() +
        " Sync1 offset (" +
        rec.sync1_offset_ns.to_string() +
        "ns) exceeds limit"
      errors.push(msg)
    }
    if rec.propagation_delay_ns < 0L {
      errors.push(
        "Station " + rec.station.to_string() + " has negative propagation delay",
      )
    }
  }
  errors
}

///|
/// 输出调优结果 JSON
pub fn AutoTuneResult::to_json(self : AutoTuneResult) -> String {
  let buf = @buffer.new()
  buf.write_string("{\n")
  buf.write_string("  \"success\": ")
  buf.write_string(self.success.to_string())
  buf.write_string(",\n  \"reference_station\": ")
  buf.write_string(self.reference_station.to_string())
  buf.write_string(",\n  \"recommendations\": [\n")
  for i = 0; i < self.recommendations.length(); i = i + 1 {
    let r = self.recommendations[i]
    if i > 0 {
      buf.write_string(",\n")
    }
    buf.write_string("    { \"station\": ")
    buf.write_string(r.station.to_string())
    buf.write_string(", \"sync0_offset_ns\": ")
    buf.write_string(r.sync0_offset_ns.to_string())
    buf.write_string(", \"sync1_offset_ns\": ")
    buf.write_string(r.sync1_offset_ns.to_string())
    buf.write_string(", \"sync0_cycle_ns\": ")
    buf.write_string(r.sync0_cycle_ns.to_string())
    buf.write_string(", \"propagation_delay_ns\": ")
    buf.write_string(r.propagation_delay_ns.to_string())
    buf.write_string(" }")
  }
  buf.write_string("\n  ],\n  \"messages\": [\n")
  for i = 0; i < self.messages.length(); i = i + 1 {
    if i > 0 {
      buf.write_string(",\n")
    }
    buf.write_string("    \"")
    buf.write_string(self.messages[i])
    buf.write_string("\"")
  }
  buf.write_string("\n  ]\n}")
  buf.to_string()
}
