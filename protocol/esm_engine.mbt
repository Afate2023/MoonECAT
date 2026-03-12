///|
/// ESM (EtherCAT State Machine) transition engine.
/// Drives slave state transitions with confirmation and error rollback.

///|
let request_state_max_polls : Int = 32

///|
/// Request an ESM state transition on a specific slave (by configured address).
/// Writes AL Control, then reads AL Status to confirm.
/// Returns the confirmed state or raises an error.
pub fn[N : @hal.Nic] request_state(
  nic : N,
  station : UInt,
  target : EsmState,
  timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  let current_status = read_al_status_raw_fp(nic, station, timeout)
  if (current_status & b'\x10') != b'\x00' {
    ignore(
      request_state_control_fp(
        nic,
        station,
        (current_status & b'\x0F') | b'\x10',
        timeout,
      ),
    )
  }
  let target_byte = target.to_byte()
  let _ = request_state_control_fp(nic, station, target_byte, timeout)
  let status = wait_for_state_fp(nic, station, target, timeout)
  let actual_state = EsmState::from_byte(status)
  if actual_state != target && (status & b'\x10') != b'\x00' {
    let _ = request_state_control_fp(
      nic,
      station,
      target_byte | b'\x10',
      timeout,
    )
    let acknowledged = wait_for_state_fp(nic, station, target, timeout)
    return EsmState::from_byte(acknowledged)
  }
  actual_state
}

///|
/// Request an ESM state transition using auto-increment addressing.
pub fn[N : @hal.Nic] request_state_ap(
  nic : N,
  position : UInt,
  target : EsmState,
  timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  let current_status = read_al_status_raw_ap(nic, position, timeout)
  if (current_status & b'\x10') != b'\x00' {
    ignore(
      request_state_control_ap(
        nic,
        position,
        (current_status & b'\x0F') | b'\x10',
        timeout,
      ),
    )
  }
  let target_byte = target.to_byte()
  let _ = request_state_control_ap(nic, position, target_byte, timeout)
  let status = wait_for_state_ap(nic, position, target, timeout)
  let actual_state = EsmState::from_byte(status)
  if actual_state != target && (status & b'\x10') != b'\x00' {
    let _ = request_state_control_ap(
      nic,
      position,
      target_byte | b'\x10',
      timeout,
    )
    let acknowledged = wait_for_state_ap(nic, position, target, timeout)
    return EsmState::from_byte(acknowledged)
  }
  actual_state
}

///|
fn[N : @hal.Nic] wait_for_state_fp(
  nic : N,
  station : UInt,
  target : EsmState,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let mut last_status = b'\x00'
  for _attempt = 0; _attempt < request_state_max_polls; _attempt = _attempt + 1 {
    last_status = read_al_status_raw_fp(nic, station, timeout)
    if (last_status & b'\x0F') == target.to_byte() {
      return last_status
    }
  }
  last_status
}

///|
fn[N : @hal.Nic] wait_for_state_ap(
  nic : N,
  position : UInt,
  target : EsmState,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let mut last_status = b'\x00'
  for _attempt = 0; _attempt < request_state_max_polls; _attempt = _attempt + 1 {
    last_status = read_al_status_raw_ap(nic, position, timeout)
    if (last_status & b'\x0F') == target.to_byte() {
      return last_status
    }
  }
  last_status
}

///|
fn[N : @hal.Nic] request_state_control_fp(
  nic : N,
  station : UInt,
  control : Byte,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let buf = Bytes::from_array([control, b'\x00'])
  let _ = write_register_fp(nic, station, reg_al_control, buf, timeout)
  let status_pdu = read_register_fp(nic, station, reg_al_status, 2, timeout)
  if status_pdu.data.length() < 1 {
    raise @hal.EcError::EsmStateError("empty AL Status response")
  }
  status_pdu.data[0]
}

///|
fn[N : @hal.Nic] read_al_status_raw_fp(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let status_pdu = read_register_fp(nic, station, reg_al_status, 2, timeout)
  if status_pdu.data.length() < 1 {
    raise @hal.EcError::EsmStateError("empty AL Status response")
  }
  status_pdu.data[0]
}

///|
fn[N : @hal.Nic] request_state_control_ap(
  nic : N,
  position : UInt,
  control : Byte,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let buf = Bytes::from_array([control, b'\x00'])
  let _ = write_register_ap(nic, position, reg_al_control, buf, timeout)
  let status_pdu = read_register_ap(nic, position, reg_al_status, 2, timeout)
  if status_pdu.data.length() < 1 {
    raise @hal.EcError::EsmStateError("empty AL Status response")
  }
  status_pdu.data[0]
}

///|
fn[N : @hal.Nic] read_al_status_raw_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let status_pdu = read_register_ap(nic, position, reg_al_status, 2, timeout)
  if status_pdu.data.length() < 1 {
    raise @hal.EcError::EsmStateError("empty AL Status response")
  }
  status_pdu.data[0]
}

///|
/// Optional per-target ESM transition timeout overrides.
///
/// Fields map to the target state of each transition step.
/// If a field is None, ETG-based default timeout is used.
pub(all) struct EsmTimeoutPolicy {
  init : @hal.Duration?
  preop : @hal.Duration?
  safeop : @hal.Duration?
  op : @hal.Duration?
  boot : @hal.Duration?
} derive(Eq, Show)

///|
/// Return the baseline ESM transition timeout for a given target state.
///
/// Defaults are aligned with common EtherCAT master practice and can be
/// overridden by SII/ESI-derived values through EsmTimeoutPolicy.
pub fn esm_default_timeout(target : EsmState) -> @hal.Duration {
  match target {
    Init => @hal.Duration(5_000_000_000L)
    PreOp => @hal.Duration(3_000_000_000L)
    SafeOp => @hal.Duration(10_000_000_000L)
    Op => @hal.Duration(10_000_000_000L)
    Boot => @hal.Duration(5_000_000_000L)
  }
}

///|
/// Build a timeout policy that uses ETG-based defaults for all transitions.
pub fn default_esm_timeout_policy() -> EsmTimeoutPolicy {
  { init: None, preop: None, safeop: None, op: None, boot: None }
}

///|
/// Resolve transition timeout for a target state using policy override first,
/// then falling back to ETG-based defaults.
pub fn esm_timeout_for(
  target : EsmState,
  policy : EsmTimeoutPolicy,
) -> @hal.Duration {
  let timeout_override = match target {
    Init => policy.init
    PreOp => policy.preop
    SafeOp => policy.safeop
    Op => policy.op
    Boot => policy.boot
  }
  match timeout_override {
    Some(timeout) => timeout
    None => esm_default_timeout(target)
  }
}

///|
/// Transition a slave through a sequence of ESM states.
/// Each step validates `can_transition` before issuing the request.
/// On failure it attempts rollback to the previous state.
pub fn[N : @hal.Nic] transition_through(
  nic : N,
  station : UInt,
  path : Array[EsmState],
  timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  if path.is_empty() {
    raise @hal.EcError::Internal("empty transition path")
  }
  let mut current = path[0]
  for i = 1; i < path.length(); i = i + 1 {
    let target = path[i]
    if not(current.can_transition(target)) {
      raise @hal.EcError::EsmTransitionFailed(
        from=current.to_string(),
        to=target.to_string(),
      )
    }
    let confirmed = request_state(nic, station, target, timeout) catch {
      err => {
        // Attempt rollback to previous state
        let _ = try? request_state(nic, station, current, timeout)
        raise err
      }
    }
    current = confirmed
  }
  current
}

///|
/// Transition through an ESM path using per-target timeout policy.
///
/// Callers may feed SII/ESI-derived timeouts through `policy` while retaining
/// sane defaults for missing entries.
pub fn[N : @hal.Nic] transition_through_with_timeout_policy(
  nic : N,
  station : UInt,
  path : Array[EsmState],
  policy : EsmTimeoutPolicy,
) -> EsmState raise @hal.EcError {
  if path.is_empty() {
    raise @hal.EcError::Internal("empty transition path")
  }
  let mut current = path[0]
  for i = 1; i < path.length(); i = i + 1 {
    let target = path[i]
    if not(current.can_transition(target)) {
      raise @hal.EcError::EsmTransitionFailed(
        from=current.to_string(),
        to=target.to_string(),
      )
    }
    let step_timeout = esm_timeout_for(target, policy)
    let rollback_timeout = esm_timeout_for(current, policy)
    let confirmed = request_state(nic, station, target, step_timeout) catch {
      err => {
        let _ = try? request_state(nic, station, current, rollback_timeout)
        raise err
      }
    }
    current = confirmed
  }
  current
}

///|
/// Build the standard forward transition path from Init to a target state.
pub fn build_transition_path(target : EsmState) -> Array[EsmState] {
  match target {
    Init => [Init]
    PreOp => [Init, PreOp]
    SafeOp => [Init, PreOp, SafeOp]
    Op => [Init, PreOp, SafeOp, Op]
    Boot => [Init, Boot]
  }
}

///|
/// Build the safe shutdown path from a current state to Init.
pub fn build_shutdown_path(current : EsmState) -> Array[EsmState] {
  match current {
    Init => [Init]
    PreOp => [PreOp, Init]
    SafeOp => [SafeOp, PreOp, Init]
    Op => [Op, SafeOp, PreOp, Init]
    Boot => [Boot, Init]
  }
}

///|
/// Read the current ESM state from a slave.
pub fn[N : @hal.Nic] read_al_status(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_al_status, 2, timeout)
  if pdu.data.length() < 1 {
    raise @hal.EcError::EsmStateError("empty AL Status response")
  }
  EsmState::from_byte(pdu.data[0])
}

///|
/// Read the current ESM state using auto-increment addressing.
pub fn[N : @hal.Nic] read_al_status_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  let pdu = read_register_ap(nic, position, reg_al_status, 2, timeout)
  if pdu.data.length() < 1 {
    raise @hal.EcError::EsmStateError("empty AL Status response")
  }
  EsmState::from_byte(pdu.data[0])
}

///|
/// Read the AL Status Code from a slave (error code for failed transitions).
pub fn[N : @hal.Nic] read_al_status_code(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let pdu = read_register_fp(nic, station, reg_al_status_code, 2, timeout)
  if pdu.data.length() < 2 {
    return 0U
  }
  pdu.data[0].to_int().reinterpret_as_uint() |
  (pdu.data[1].to_int().reinterpret_as_uint() << 8)
}

///|
/// Request all slaves to transition to a target state via broadcast.
/// Uses BWR to AL Control register. Returns the working counter.
pub fn[N : @hal.Nic] broadcast_state(
  nic : N,
  target : EsmState,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let target_byte = target.to_byte()
  let buf = Bytes::from_array([target_byte, b'\x00'])
  let addr = broadcast_address(reg_al_control)
  let pdu = transact_pdu(nic, EcCommand::BWR, addr, buf, timeout)
  pdu.wkc
}
