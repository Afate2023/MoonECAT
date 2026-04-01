///|
/// Distributed Clock (DC) support.
///
/// Design notes:
/// - Uses ETG DC register map (0x0900-0x09A4).
/// - Implements a practical startup flow inspired by SOEM/ethercrab:
///   1) Latch DC receive times
///   2) Select first configured slave as DC reference
///   3) Write per-slave DC offset and delay
///   4) Configure SYNC0 cycle
///   5) Run static FRMW drift pre-compensation
///
/// This implementation intentionally stays transport-only and topology-agnostic,
/// so it can run with the current MoonECAT data model and HAL.

///|
let dc_sync_start_delay_ns : UInt = 100_000_000U

///|
let dc_default_static_sync_frames : Int = 2000

///|
/// Default smoothing factor numerator for delay update: new =
/// (old * (dc_delay_smoothing_den - dc_delay_smoothing_num) + measured * dc_delay_smoothing_num) / den.
let dc_delay_smoothing_num : UInt = 1U

///|
let dc_delay_smoothing_den : UInt = 4U

///|
/// Result of DC initialization.
pub(all) struct DcInitResult {
  reference_station : UInt
  configured_count : Int
} derive(Eq, Show)

///|
fn le_u32(data : Bytes) -> UInt {
  if data.length() < 4 {
    return 0U
  }
  data[0].to_uint() |
  (data[1].to_uint() << 8) |
  (data[2].to_uint() << 16) |
  (data[3].to_uint() << 24)
}

///|
fn write_u32(value : UInt) -> Bytes {
  Bytes::from_array([
    (value & 0xFFU).to_byte(),
    ((value >> 8) & 0xFFU).to_byte(),
    ((value >> 16) & 0xFFU).to_byte(),
    ((value >> 24) & 0xFFU).to_byte(),
  ])
}

///|
/// Encode a signed 64-bit value where only low 32-bit magnitude is used.
/// High 32-bit is sign extension, matching ESC's two's complement expectation.
fn write_i64_from_i32(v : Int) -> Bytes {
  let lo = v.reinterpret_as_uint()
  let hi : UInt = if v < 0 { 0xFFFF_FFFFU } else { 0U }
  Bytes::from_array([
    (lo & 0xFFU).to_byte(),
    ((lo >> 8) & 0xFFU).to_byte(),
    ((lo >> 16) & 0xFFU).to_byte(),
    ((lo >> 24) & 0xFFU).to_byte(),
    (hi & 0xFFU).to_byte(),
    ((hi >> 8) & 0xFFU).to_byte(),
    ((hi >> 16) & 0xFFU).to_byte(),
    ((hi >> 24) & 0xFFU).to_byte(),
  ])
}

///|
fn abs_diff_u32(a : UInt, b : UInt) -> UInt {
  if a >= b {
    a - b
  } else {
    b - a
  }
}

///|
fn le_u64(data : Bytes) -> UInt64 {
  if data.length() < 8 {
    return 0UL
  }
  data[0].to_uint().to_uint64() |
  (data[1].to_uint().to_uint64() << 8) |
  (data[2].to_uint().to_uint64() << 16) |
  (data[3].to_uint().to_uint64() << 24) |
  (data[4].to_uint().to_uint64() << 32) |
  (data[5].to_uint().to_uint64() << 40) |
  (data[6].to_uint().to_uint64() << 48) |
  (data[7].to_uint().to_uint64() << 56)
}

///|
fn write_u64(value : UInt64) -> Bytes {
  Bytes::from_array([
    (value & 0xFFUL).to_byte(),
    ((value >> 8) & 0xFFUL).to_byte(),
    ((value >> 16) & 0xFFUL).to_byte(),
    ((value >> 24) & 0xFFUL).to_byte(),
    ((value >> 32) & 0xFFUL).to_byte(),
    ((value >> 40) & 0xFFUL).to_byte(),
    ((value >> 48) & 0xFFUL).to_byte(),
    ((value >> 56) & 0xFFUL).to_byte(),
  ])
}

///|
/// Latch DC receive times on all slaves by broadcast-writing to 0x0900.
pub fn[N : @hal.Nic] dc_latch_times(
  nic : N,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let _ = transact_pdu(
    nic,
    EcCommand::BWR,
    broadcast_address(reg_dc_time0),
    write_u32(0U),
    timeout,
  )
}

///|
/// Read latched DC receive time (port 0 timestamp) of one slave.
pub fn[N : @hal.Nic] dc_read_receive_time(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_dc_time0, 4, timeout)
  le_u32(pdu.data)
}

///|
/// Per-port DC receive times (all 4 ports).
pub(all) struct DcPortTimes {
  port0 : UInt
  port1 : UInt
  port2 : UInt
  port3 : UInt
} derive(Eq, Show)

///|
/// Read all 4 port receive times in a single FPRD (16 bytes from 0x0900).
pub fn[N : @hal.Nic] dc_read_port_times(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> DcPortTimes raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_dc_time0, 16, timeout)
  let d = pdu.data
  let read_u32_at = fn(offset : Int) -> UInt {
    if d.length() < offset + 4 {
      return 0U
    }
    d[offset].to_uint() |
    (d[offset + 1].to_uint() << 8) |
    (d[offset + 2].to_uint() << 16) |
    (d[offset + 3].to_uint() << 24)
  }
  {
    port0: read_u32_at(0),
    port1: read_u32_at(4),
    port2: read_u32_at(8),
    port3: read_u32_at(12),
  }
}

///|
/// Check whether a slave supports Distributed Clocks.
/// Reads DL Information register (0x0008) bit 2.
pub fn[N : @hal.Nic] dc_check_support(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_dl_information, 2, timeout)
  if pdu.data.length() < 1 {
    return false
  }
  (pdu.data[0] & b'\x04') != b'\x00'
}

///|
/// Read the full 64-bit DC system time from a slave (0x0910, 8 bytes).
pub fn[N : @hal.Nic] dc_read_system_time_64(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> UInt64 raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_dc_system_time, 8, timeout)
  le_u64(pdu.data)
}

///|
/// Read the 64-bit DC Start of Frame register (0x0918, 8 bytes).
pub fn[N : @hal.Nic] dc_read_sof(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> UInt64 raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_dc_sof, 8, timeout)
  le_u64(pdu.data)
}

///|
/// Read DC sync window / system difference register (0x092C).
pub fn[N : @hal.Nic] dc_read_sync_window(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_dc_system_diff, 4, timeout)
  le_u32(pdu.data)
}

///|
/// Configure SYNC0 output for one slave.
/// Uses full 64-bit DC system time to choose a future aligned start tick.
/// When `sync1_cycle_ns` > 0, also configures SYNC1 and activates both
/// (activation byte 0x07 instead of 0x03).
pub fn[N : @hal.Nic] dc_configure_sync0(
  nic : N,
  station : UInt,
  cycle_ns : UInt,
  timeout : @hal.Duration,
  shift_ns? : Int = 0,
  sync1_cycle_ns? : UInt = 0U,
) -> Unit raise @hal.EcError {
  // Stop cyclic operation
  let _ = write_register_fp(
    nic,
    station,
    reg_dc_sync_act,
    Bytes::from_array([b'\x00']),
    timeout,
  )
  // CUC = 0 (ECAT writes DC registers)
  let _ = write_register_fp(
    nic,
    station,
    reg_dc_cuc,
    Bytes::from_array([b'\x00']),
    timeout,
  )
  // Read DC system time full 64-bit
  let t_now = dc_read_system_time_64(nic, station, timeout)
  let delay64 = dc_sync_start_delay_ns.to_uint64()
  let cycle64 = cycle_ns.to_uint64()
  let shift64 = shift_ns.to_int64().reinterpret_as_uint64()
  let start : UInt64 = if cycle64 > 0UL {
    ((t_now + delay64) / cycle64 + 1UL) * cycle64 + shift64
  } else {
    t_now + delay64 + shift64
  }
  let _ = write_register_fp(
    nic,
    station,
    reg_dc_start0,
    write_u64(start),
    timeout,
  )
  let _ = write_register_fp(
    nic,
    station,
    reg_dc_cycle0,
    write_u32(cycle_ns),
    timeout,
  )
  // Write SYNC1 cycle time if requested
  if sync1_cycle_ns > 0U {
    let _ = write_register_fp(
      nic,
      station,
      reg_dc_cycle1,
      write_u32(sync1_cycle_ns),
      timeout,
    )
  }
  // Activate cyclic + SYNC0 (+ SYNC1 if configured)
  let act : Byte = if sync1_cycle_ns > 0U { b'\x07' } else { b'\x03' }
  let _ = write_register_fp(
    nic,
    station,
    reg_dc_sync_act,
    Bytes::from_array([act]),
    timeout,
  )
}

///|
/// Send one FRMW DC frame to distribute reference system time.
pub fn[N : @hal.Nic] dc_compensate_cycle(
  nic : N,
  reference_station : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let _ = transact_pdu(
    nic,
    EcCommand::FRMW,
    configured_address(reference_station, reg_dc_system_time),
    Bytes::new(8),
    timeout,
  )
}

///|
/// Run static FRMW pre-compensation during startup.
pub fn[N : @hal.Nic] dc_static_sync(
  nic : N,
  reference_station : UInt,
  iterations : Int,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  for _i = 0; _i < iterations; _i = _i + 1 {
    dc_compensate_cycle(nic, reference_station, timeout)
  }
}

///|
/// Configure DC for a set of configured station addresses.
/// Returns None when station list is empty.
pub fn[N : @hal.Nic] dc_configure_linear(
  nic : N,
  stations : Array[UInt],
  cycle_ns : UInt,
  timeout : @hal.Duration,
  static_sync_iterations? : Int = dc_default_static_sync_frames,
) -> DcInitResult? raise @hal.EcError {
  if stations.length() == 0 {
    return None
  }
  dc_latch_times(nic, timeout)
  let reference_station = stations[0]
  let reference_time = dc_read_receive_time(nic, reference_station, timeout)

  for i = 0; i < stations.length(); i = i + 1 {
    let station = stations[i]
    let recv_time = dc_read_receive_time(nic, station, timeout)
    let offset_i = reference_time.reinterpret_as_int() -
      recv_time.reinterpret_as_int()
    // DC system offset and delay
    let _ = write_register_fp(
      nic,
      station,
      reg_dc_system_offset,
      write_i64_from_i32(offset_i),
      timeout,
    )
    // Topology-aware approximation: use per-station receive-time delta
    // against the selected reference station as propagation delay estimate.
    let pdelay = abs_diff_u32(recv_time, reference_time)
    let _ = write_register_fp(
      nic,
      station,
      reg_dc_system_delay,
      write_u32(pdelay),
      timeout,
    )
    // Configure SYNC0 for cyclic operation.
    dc_configure_sync0(nic, station, cycle_ns, timeout)
  }

  dc_static_sync(nic, reference_station, static_sync_iterations, timeout)
  Some({ reference_station, configured_count: stations.length() })
}

///|
/// Re-estimate and update propagation delay during runtime.
/// This closes the loop for ETG.1500 #1102 by periodically updating 0x0928.
pub fn[N : @hal.Nic] dc_reestimate_propagation_delays(
  nic : N,
  reference_station : UInt,
  stations : Array[UInt],
  timeout : @hal.Duration,
  smoothing_num? : UInt = dc_delay_smoothing_num,
  smoothing_den? : UInt = dc_delay_smoothing_den,
) -> Unit raise @hal.EcError {
  if stations.length() == 0 {
    return
  }
  dc_latch_times(nic, timeout)
  let reference_time = dc_read_receive_time(nic, reference_station, timeout)

  for station in stations {
    let recv_time = dc_read_receive_time(nic, station, timeout)
    let measured = abs_diff_u32(recv_time, reference_time)
    let old_pdu = read_register_fp(
      nic, station, reg_dc_system_delay, 4, timeout,
    )
    let old_delay = le_u32(old_pdu.data)
    let blended = if smoothing_den == 0U {
      measured
    } else {
      let keep = smoothing_den - smoothing_num
      (old_delay * keep + measured * smoothing_num) / smoothing_den
    }
    let _ = write_register_fp(
      nic,
      station,
      reg_dc_system_delay,
      write_u32(blended),
      timeout,
    )
  }
}

///|
/// Deactivate DC sync for a single slave.
/// Writes 0 to the sync activation register and clears cycle times.
pub fn[N : @hal.Nic] dc_deactivate_sync(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let _ = write_register_fp(
    nic,
    station,
    reg_dc_sync_act,
    Bytes::from_array([b'\x00']),
    timeout,
  )
  let _ = write_register_fp(nic, station, reg_dc_cycle0, write_u32(0U), timeout)
  let _ = write_register_fp(nic, station, reg_dc_cycle1, write_u32(0U), timeout)
}

///|
/// Broadcast-deactivate DC sync on all slaves.
pub fn[N : @hal.Nic] dc_deactivate_sync_all(
  nic : N,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let _ = transact_pdu(
    nic,
    EcCommand::BWR,
    broadcast_address(reg_dc_sync_act),
    Bytes::from_array([b'\x00']),
    timeout,
  )
}

///|
/// Broadcast read DC System Time Difference (0x092C) across all slaves.
///
/// Per ETG.1500 §5.13.3 (#1103), a BRD to register 0x092C returns the
/// bitwise-OR of all slaves' System Time Difference values. The master
/// compares this against a limit to monitor DC synchronisation quality.
///
/// Returns the ORed 32-bit system time difference value and the working
/// counter (number of DC slaves that responded).
pub fn[N : @hal.Nic] dc_broadcast_sync_window(
  nic : N,
  timeout : @hal.Duration,
) -> (UInt, UInt) raise @hal.EcError {
  let pdu = transact_pdu(
    nic,
    EcCommand::BRD,
    broadcast_address(reg_dc_system_diff),
    Bytes::new(4),
    timeout,
  )
  (le_u32(pdu.data), pdu.wkc)
}

///|
/// Check whether the broadcast sync window is within an acceptable limit.
///
/// The `limit_ns` parameter is the maximum tolerable clock deviation in
/// nanoseconds. Returns true when the ORed system time difference from
/// all DC slaves is below the limit.
pub fn[N : @hal.Nic] dc_check_sync_window(
  nic : N,
  limit_ns : UInt,
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
  let (diff, _wkc) = dc_broadcast_sync_window(nic, timeout)
  // System Time Difference is a signed 32-bit value; compare magnitude.
  let magnitude = if (diff & 0x8000_0000U) != 0U {
    // Negative: two's complement
    (diff ^ 0xFFFF_FFFFU) + 1U
  } else {
    diff
  }
  magnitude <= limit_ns
}
