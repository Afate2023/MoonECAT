///|
/// ESM extensions for Device Emulation and OpOnly flag handling.
/// Implements ETG.1500 #103 (Device Emulation shall) and §5.3.4 (OpOnly).

///|
/// Read the Type register (0x0000) from a slave and check if
/// the Device Emulation flag (bit 7 of byte 0) is set.
pub fn[N : @hal.Nic] read_device_emulation(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_type, 1, timeout)
  if pdu.data.length() < 1 {
    return false
  }
  (pdu.data[0] & b'\x80') != b'\x00'
}

///|
/// Request an ESM state transition with Device Emulation awareness.
/// For slaves with Device Emulation:
///   - Clear Error Indication in AL Control (bit 4) before transition.
///   - Write AL Control with Acknowledge bit when in error state.
/// For normal slaves, behaves identically to request_state.
pub fn[N : @hal.Nic] request_state_aware(
  nic : N,
  station : UInt,
  target : EsmState,
  device_emulation? : Bool = false,
  timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  if device_emulation {
    // For Device Emulation slaves: first acknowledge any error indication
    // by writing current state with bit 4 (Error Indication Ack) set
    let current_pdu = read_register_fp(nic, station, reg_al_status, 2, timeout)
    if current_pdu.data.length() >= 2 {
      let current_status = current_pdu.data[0]
      // Check bit 4 of AL Status (Error Indication)
      if (current_status & b'\x10') != b'\x00' {
        // Acknowledge error: write current state | 0x10 to AL Control
        let ack_byte = (current_status & b'\x0F') | b'\x10'
        let ack_buf = Bytes::from_array([ack_byte, b'\x00'])
        let _ = write_register_fp(
          nic, station, reg_al_control, ack_buf, timeout,
        )
      }
    }
  }
  // Proceed with normal state request
  request_state(nic, station, target, timeout)
}

///|
/// Enable or disable a specific Sync Manager.
/// Used for OpOnly handling: disable output SM when not in Op state.
///
/// SM activate register is at: SM_base + SM_index * 8 + 6
pub fn[N : @hal.Nic] set_sm_enable(
  nic : N,
  station : UInt,
  sm_index : Int,
  enable : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let sm_activate_addr = reg_sm_base +
    sm_index.reinterpret_as_uint() * sm_entry_size.reinterpret_as_uint() +
    6U
  let value : Byte = if enable { b'\x01' } else { b'\x00' }
  let _ = write_register_fp(
    nic,
    station,
    sm_activate_addr,
    Bytes::from_array([value]),
    timeout,
  )
}

///|
/// Apply OpOnly policy for a slave during ESM state transitions.
/// When op_only is true and target state is not Op, disables the output
/// process data SMs (typically SM2). When transitioning to Op, enables them.
pub fn[N : @hal.Nic] apply_op_only_policy(
  nic : N,
  station : UInt,
  target : EsmState,
  op_only : Bool,
  output_sm_indices : Array[Int],
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  if not(op_only) {
    return
  }
  let enable = target is Op
  for i = 0; i < output_sm_indices.length(); i = i + 1 {
    set_sm_enable(nic, station, output_sm_indices[i], enable, timeout)
  }
}

///|
/// SM Watchdog configuration snapshot read from ESC registers.
pub(all) struct SmWatchdogConfig {
  /// Watchdog divider value (register 0x0400). Default 0x09C2 = 100µs base.
  divider : UInt
  /// PDI watchdog time (register 0x0410). In watchdog base-time multiples.
  pdi_time : UInt
  /// Process Data watchdog time (register 0x0420). In watchdog base-time multiples.
  pdata_time : UInt
  /// Process Data watchdog status (register 0x0440). Bit 0: 0=expired, 1=active.
  pdata_status : Bool
  /// Process Data watchdog counter (register 0x0442). Increments on each event.
  pdata_counter : UInt
} derive(Eq, Show)

///|
/// Read SM Watchdog configuration from ESC registers.
pub fn[N : @hal.Nic] read_sm_watchdog_config(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> SmWatchdogConfig raise @hal.EcError {
  let div_pdu = read_register_fp(nic, station, reg_watchdog_divider, 2, timeout)
  let divider = if div_pdu.data.length() >= 2 {
    div_pdu.data[0].to_uint() | (div_pdu.data[1].to_uint() << 8)
  } else {
    0U
  }
  let pdi_pdu = read_register_fp(
    nic, station, reg_watchdog_time_pdi, 2, timeout,
  )
  let pdi_time = if pdi_pdu.data.length() >= 2 {
    pdi_pdu.data[0].to_uint() | (pdi_pdu.data[1].to_uint() << 8)
  } else {
    0U
  }
  let pd_pdu = read_register_fp(
    nic, station, reg_watchdog_time_pdata, 2, timeout,
  )
  let pdata_time = if pd_pdu.data.length() >= 2 {
    pd_pdu.data[0].to_uint() | (pd_pdu.data[1].to_uint() << 8)
  } else {
    0U
  }
  let status_pdu = read_register_fp(
    nic, station, reg_watchdog_status_pdata, 2, timeout,
  )
  let pdata_status = if status_pdu.data.length() >= 1 {
    (status_pdu.data[0] & b'\x01') != b'\x00'
  } else {
    false
  }
  let counter_pdu = read_register_fp(
    nic, station, reg_watchdog_counter_pdata, 1, timeout,
  )
  let pdata_counter = if counter_pdu.data.length() >= 1 {
    counter_pdu.data[0].to_uint()
  } else {
    0U
  }
  { divider, pdi_time, pdata_time, pdata_status, pdata_counter }
}

///|
/// Per-port error counters from ESC DL registers.
pub(all) struct PortErrorCounters {
  /// Frame errors (invalid FCS / length) detected on this port.
  frame_errors : UInt
  /// Physical layer errors (invalid symbols) detected on this port.
  physical_errors : UInt
  /// Forwarded RX errors (previously forwarded bad frames) on this port.
  forwarded_rx_errors : UInt
  /// Lost link events on this port (link-down transitions).
  lost_link_count : UInt
} derive(Eq, Show)

///|
/// DL/Physical layer error counters snapshot (ESC registers 0x0300–0x0313).
pub(all) struct DlErrorCounters {
  /// Per-port error counters [port0, port1, port2, port3].
  ports : FixedArray[PortErrorCounters]
  /// EtherCAT Processing Unit error counter (register 0x030C).
  ecat_pu_errors : UInt
  /// PDI interface error counter (register 0x030D).
  pdi_errors : UInt
} derive(Eq, Show)

///|
/// Read DL/Physical layer error counters from ESC registers using configured station addressing.
/// Reads registers 0x0300–0x030D (RX Error, Forwarded RX Error, EPU, PDI)
/// and 0x0310–0x0313 (Lost Link).
pub fn[N : @hal.Nic] read_dl_error_counters(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> DlErrorCounters raise @hal.EcError {
  // Read RX Error Counters (0x0300–0x0307, 8 bytes: frame+physical per port)
  let rx_pdu = read_register_fp(nic, station, reg_rx_error_counter, 8, timeout)
  // Read Forwarded RX Error Counters (0x0308–0x030B, 4 bytes) + EPU (0x030C) + PDI (0x030D)
  let fwd_pdu = read_register_fp(
    nic, station, reg_fwd_rx_error_counter, 6, timeout,
  )
  // Read Lost Link Counters (0x0310–0x0313, 4 bytes)
  let lost_pdu = read_register_fp(
    nic, station, reg_lost_link_counter, 4, timeout,
  )
  decode_dl_error_counters(rx_pdu.data, fwd_pdu.data, lost_pdu.data)
}

///|
/// Read DL/Physical layer error counters using auto-increment (AP) addressing.
pub fn[N : @hal.Nic] read_dl_error_counters_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> DlErrorCounters raise @hal.EcError {
  let rx_pdu = read_register_ap(nic, position, reg_rx_error_counter, 8, timeout)
  let fwd_pdu = read_register_ap(
    nic, position, reg_fwd_rx_error_counter, 6, timeout,
  )
  let lost_pdu = read_register_ap(
    nic, position, reg_lost_link_counter, 4, timeout,
  )
  decode_dl_error_counters(rx_pdu.data, fwd_pdu.data, lost_pdu.data)
}

///|
fn decode_dl_error_counters(
  rx_data : Bytes,
  fwd_data : Bytes,
  lost_data : Bytes,
) -> DlErrorCounters {
  let ports : FixedArray[PortErrorCounters] = FixedArray::make(4, {
    frame_errors: 0U,
    physical_errors: 0U,
    forwarded_rx_errors: 0U,
    lost_link_count: 0U,
  })
  for i = 0; i < 4; i = i + 1 {
    let frame = if rx_data.length() > i * 2 {
      rx_data[i * 2].to_uint()
    } else {
      0U
    }
    let physical = if rx_data.length() > i * 2 + 1 {
      rx_data[i * 2 + 1].to_uint()
    } else {
      0U
    }
    let fwd = if fwd_data.length() > i { fwd_data[i].to_uint() } else { 0U }
    let lost = if lost_data.length() > i { lost_data[i].to_uint() } else { 0U }
    ports[i] = {
      frame_errors: frame,
      physical_errors: physical,
      forwarded_rx_errors: fwd,
      lost_link_count: lost,
    }
  }
  let ecat_pu = if fwd_data.length() > 4 { fwd_data[4].to_uint() } else { 0U }
  let pdi = if fwd_data.length() > 5 { fwd_data[5].to_uint() } else { 0U }
  { ports, ecat_pu_errors: ecat_pu, pdi_errors: pdi }
}
