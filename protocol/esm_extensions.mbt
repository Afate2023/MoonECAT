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
