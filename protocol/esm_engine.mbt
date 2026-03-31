///|
/// ESM (EtherCAT State Machine) transition engine.
/// Drives slave state transitions with confirmation and error rollback.

///|
let request_state_max_polls : Int = 32

///|
let request_state_extended_max_polls : Int = 4096

///|
pub(all) struct EsmStatusSnapshot {
  state : EsmState
  error_indication : Bool
  status_code : UInt?
} derive(Eq, Show)

///|
fn decode_al_status_snapshot(
  status : Byte,
  status_code : UInt?,
) -> EsmStatusSnapshot raise @hal.EcError {
  let error_indication = (status & b'\x10') != b'\x00'
  {
    state: EsmState::from_byte(status),
    error_indication,
    status_code: if error_indication {
      status_code
    } else {
      None
    },
  }
}

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
/// Request an ESM state transition while continuing cyclic PDO exchange,
/// and return the last confirmed AL snapshot observed during polling.
pub fn[N : @hal.Nic] request_state_with_process_data_snapshot(
  nic : N,
  station : UInt,
  target : EsmState,
  pdo_ctx : PdoContext,
  timeout : @hal.Duration,
) -> EsmStatusSnapshot raise @hal.EcError {
  if pdo_ctx.logical_size <= 0 {
    let _ = request_state(nic, station, target, timeout)
    return read_al_status_snapshot(nic, station, timeout) catch {
      _ => { state: target, error_indication: false, status_code: None }
    }
  }
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
  wait_for_state_fp_with_process_data_snapshot(
    nic, station, target, pdo_ctx, timeout,
  )
}

///|
/// Request an ESM state transition while continuing cyclic PDO exchange.
///
/// This is primarily needed for SAFEOP -> OP on actuator-style devices where
/// the SubDevice only confirms OP once output process data has been received
/// during the confirmation window.
pub fn[N : @hal.Nic] request_state_with_process_data(
  nic : N,
  station : UInt,
  target : EsmState,
  pdo_ctx : PdoContext,
  timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  let snapshot = request_state_with_process_data_snapshot(
    nic, station, target, pdo_ctx, timeout,
  )
  if snapshot.state != target && snapshot.error_indication {
    let _ = request_state_control_fp(
      nic,
      station,
      target.to_byte() | b'\x10',
      timeout,
    )
    return wait_for_state_fp_with_process_data_snapshot(
        nic, station, target, pdo_ctx, timeout,
      ).state
  }
  snapshot.state
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
pub fn[N : @hal.Nic] read_al_status_snapshot(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> EsmStatusSnapshot raise @hal.EcError {
  let status = read_al_status_raw_fp(nic, station, timeout)
  let status_code = if (status & b'\x10') != b'\x00' {
    Some(read_al_status_code(nic, station, timeout))
  } else {
    None
  }
  decode_al_status_snapshot(status, status_code)
}

///|
pub fn[N : @hal.Nic] read_al_status_snapshot_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> EsmStatusSnapshot raise @hal.EcError {
  let status = read_al_status_raw_ap(nic, position, timeout)
  let status_code = if (status & b'\x10') != b'\x00' {
    Some(read_al_status_code_ap(nic, position, timeout))
  } else {
    None
  }
  decode_al_status_snapshot(status, status_code)
}

///|
pub fn[N : @hal.Nic] clear_al_error(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> EsmStatusSnapshot raise @hal.EcError {
  let snapshot = read_al_status_snapshot(nic, station, timeout)
  if not(snapshot.error_indication) {
    return snapshot
  }
  let cleared_status = request_state_control_fp(
    nic,
    station,
    snapshot.state.to_byte() | b'\x10',
    timeout,
  )
  let cleared = decode_al_status_snapshot(cleared_status, None)
  if cleared.error_indication {
    let status_code = Some(read_al_status_code(nic, station, timeout)) catch {
      _ => None
    }
    let status_code_text = match status_code {
      Some(code) =>
        code.to_string() + " (" + al_status_code_description(code) + ")"
      None => "unknown"
    }
    raise @hal.EcError::EsmStateError(
      "failed to clear AL error indication: station=" +
      station.to_string() +
      " state=" +
      cleared.state.to_string() +
      " status_code=" +
      status_code_text,
    )
  }
  cleared
}

///|
fn should_rollback_al_error_to_init(status_code : UInt?) -> Bool {
  match status_code {
    Some(0x0016U) | Some(0x001DU) | Some(0x001EU) | Some(0x0070U) => true
    _ => false
  }
}

///|
/// Recover from a pending AL error before the caller selects a new target
/// state. Configuration-stage failures are stabilized by rolling back to Init;
/// other errors are acknowledged in place.
pub fn[N : @hal.Nic] recover_al_error_for_transition(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> EsmStatusSnapshot raise @hal.EcError {
  let snapshot = read_al_status_snapshot(nic, station, timeout)
  if not(snapshot.error_indication) {
    return snapshot
  }
  if should_rollback_al_error_to_init(snapshot.status_code) &&
    snapshot.state != Init {
    let final_state = request_state(nic, station, Init, timeout)
    return read_al_status_snapshot(nic, station, timeout) catch {
      _ => { state: final_state, error_indication: false, status_code: None }
    }
  }
  clear_al_error(nic, station, timeout)
}

///|
pub fn[N : @hal.Nic] clear_al_error_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> EsmStatusSnapshot raise @hal.EcError {
  let snapshot = read_al_status_snapshot_ap(nic, position, timeout)
  if not(snapshot.error_indication) {
    return snapshot
  }
  let cleared_status = request_state_control_ap(
    nic,
    position,
    snapshot.state.to_byte() | b'\x10',
    timeout,
  )
  let cleared = decode_al_status_snapshot(cleared_status, None)
  if cleared.error_indication {
    let status_code = Some(read_al_status_code_ap(nic, position, timeout)) catch {
      _ => None
    }
    let status_code_text = match status_code {
      Some(code) =>
        code.to_string() + " (" + al_status_code_description(code) + ")"
      None => "unknown"
    }
    raise @hal.EcError::EsmStateError(
      "failed to clear AP AL error indication: position=" +
      position.to_string() +
      " state=" +
      cleared.state.to_string() +
      " status_code=" +
      status_code_text,
    )
  }
  cleared
}

///|
fn[N : @hal.Nic] wait_for_state_fp(
  nic : N,
  station : UInt,
  target : EsmState,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let mut last_status = b'\x00'
  let poll_budget = request_state_poll_budget(target, timeout)
  for _attempt = 0; _attempt < poll_budget; _attempt = _attempt + 1 {
    last_status = read_al_status_raw_fp(nic, station, timeout)
    if (last_status & b'\x0F') == target.to_byte() {
      return last_status
    }
  }
  last_status
}

///|
fn[N : @hal.Nic] snapshot_from_status_fp(
  nic : N,
  station : UInt,
  status : Byte,
  timeout : @hal.Duration,
) -> EsmStatusSnapshot raise @hal.EcError {
  let status_code = if (status & b'\x10') != b'\x00' {
    Some(read_al_status_code(nic, station, timeout))
  } else {
    None
  }
  decode_al_status_snapshot(status, status_code)
}

///|
fn[N : @hal.Nic] wait_for_state_fp_with_process_data_snapshot(
  nic : N,
  station : UInt,
  target : EsmState,
  pdo_ctx : PdoContext,
  timeout : @hal.Duration,
) -> EsmStatusSnapshot raise @hal.EcError {
  let mut last_status = b'\x00'
  let poll_budget = request_state_poll_budget(target, timeout)
  for _attempt = 0; _attempt < poll_budget; _attempt = _attempt + 1 {
    ignore(pdo_exchange_result(nic, pdo_ctx, timeout))
    last_status = read_al_status_raw_fp(nic, station, timeout)
    if (last_status & b'\x0F') == target.to_byte() ||
      (last_status & b'\x10') != b'\x00' {
      return snapshot_from_status_fp(nic, station, last_status, timeout)
    }
  }
  snapshot_from_status_fp(nic, station, last_status, timeout)
}

///|
fn[N : @hal.Nic] wait_for_state_ap(
  nic : N,
  position : UInt,
  target : EsmState,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let mut last_status = b'\x00'
  let poll_budget = request_state_poll_budget(target, timeout)
  for _attempt = 0; _attempt < poll_budget; _attempt = _attempt + 1 {
    last_status = read_al_status_raw_ap(nic, position, timeout)
    if (last_status & b'\x0F') == target.to_byte() {
      return last_status
    }
  }
  last_status
}

///|
fn request_state_poll_budget(target : EsmState, timeout : @hal.Duration) -> Int {
  let @hal.Duration(transport_timeout_ns) = timeout
  let @hal.Duration(transition_timeout_ns) = esm_default_timeout(target)
  let effective_transport_timeout_ns = if transport_timeout_ns > 0L {
    transport_timeout_ns
  } else {
    1L
  }
  let suggested_polls = ((
    transition_timeout_ns + effective_transport_timeout_ns - 1L
  ) /
  effective_transport_timeout_ns).to_int()
  if suggested_polls <= request_state_max_polls {
    request_state_max_polls
  } else if suggested_polls >= request_state_extended_max_polls {
    request_state_extended_max_polls
  } else {
    suggested_polls
  }
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
pub fn[N : @hal.Nic] transition_through_ap(
  nic : N,
  position : UInt,
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
    let confirmed = request_state_ap(nic, position, target, timeout) catch {
      err => {
        let _ = try? request_state_ap(nic, position, current, timeout)
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
/// Build a complete transition route from the current state to a target state.
///
/// This reuses direct transitions when possible and otherwise falls back through
/// the standard shutdown and forward startup paths.
pub fn build_transition_route(
  current : EsmState,
  target : EsmState,
) -> Array[EsmState] {
  if current == target {
    return [current]
  }
  if target == Init {
    return build_shutdown_path(current)
  }
  if current == Init {
    return build_transition_path(target)
  }
  if current.can_transition(target) {
    return [current, target]
  }
  let shutdown_path = build_shutdown_path(current)
  let startup_path = build_transition_path(target)
  if shutdown_path.is_empty() {
    return startup_path
  }
  if startup_path.is_empty() {
    return shutdown_path
  }
  let result = shutdown_path
  for i = 1; i < startup_path.length(); i = i + 1 {
    result.push(startup_path[i])
  }
  result
}

///|
/// Build a strict route that respects ETG-defined legal ESM step directions.
///
/// Callers should use the returned path together with `transition_through`, or
/// use `transition_to_target_strict` for a guarded one-shot operation.
pub fn build_strict_transition_route(
  current : EsmState,
  target : EsmState,
) -> Array[EsmState] {
  build_transition_route(current, target)
}

///|
/// Strict state transition entry point.
///
/// If AL Error Indication is currently set, this function refuses to guess the
/// recovery policy and requires the caller to recover the error first via
/// `recover_al_error_for_transition(...)` (or `clear_al_error(...)` when the
/// caller knows an in-place acknowledge is correct), then explicitly choose
/// the next target state.
pub fn[N : @hal.Nic] transition_to_target_strict(
  nic : N,
  station : UInt,
  target : EsmState,
  timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  let snapshot = read_al_status_snapshot(nic, station, timeout)
  if snapshot.error_indication {
    raise @hal.EcError::EsmStateError(
      "AL error indication is set; clear the error before selecting a new target state",
    )
  }
  let path = build_strict_transition_route(snapshot.state, target)
  transition_through(nic, station, path, timeout)
}

///|
pub fn[N : @hal.Nic] transition_to_target_strict_ap(
  nic : N,
  position : UInt,
  target : EsmState,
  timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  let snapshot = read_al_status_snapshot_ap(nic, position, timeout)
  if snapshot.error_indication {
    raise @hal.EcError::EsmStateError(
      "AL error indication is set; clear the error before selecting a new target state",
    )
  }
  let path = build_strict_transition_route(snapshot.state, target)
  transition_through_ap(nic, position, path, timeout)
}

///|
/// Build an EsmTimeoutPolicy from SII-parsed timeouts (ETG.2010 category 41).
///
/// Mapping:
/// - preop_timeout_ms         → preop (transition TO PreOp)
/// - safeop_op_timeout_ms     → op   (SafeOp→Op transition)
/// - back_to_init_timeout_ms  → init (transition TO Init)
/// - back_to_safeop_timeout_ms → safeop (transition TO SafeOp)
/// - boot                     → None (not specified by SII)
///
/// Returns a default (all-None) policy when timeouts are absent.
pub fn esm_timeout_policy_from_sii_timeouts(
  timeouts : @mailbox.SiiTimeouts?,
) -> EsmTimeoutPolicy {
  match timeouts {
    None => default_esm_timeout_policy()
    Some(t) => {
      let ms_to_duration = fn(ms : UInt) -> @hal.Duration? {
        if ms == 0U {
          None
        } else {
          Some(@hal.Duration(ms.reinterpret_as_int().to_int64() * 1_000_000L))
        }
      }
      {
        init: ms_to_duration(t.back_to_init_timeout_ms),
        preop: ms_to_duration(t.preop_timeout_ms),
        safeop: ms_to_duration(t.back_to_safeop_timeout_ms),
        op: ms_to_duration(t.safeop_op_timeout_ms),
        boot: None,
      }
    }
  }
}

///|
/// Strict transitions via multi-step route with per-target timeout policy.
///
/// Same as `transition_to_target_strict` but resolves per-step timeouts from
/// the supplied policy, allowing SII/ESI-derived timeout overrides.
pub fn[N : @hal.Nic] transition_to_target_strict_with_timeout_policy(
  nic : N,
  station : UInt,
  target : EsmState,
  policy : EsmTimeoutPolicy,
  fallback_timeout : @hal.Duration,
) -> EsmState raise @hal.EcError {
  let snapshot = read_al_status_snapshot(nic, station, fallback_timeout)
  if snapshot.error_indication {
    raise @hal.EcError::EsmStateError(
      "AL error indication is set; clear the error before selecting a new target state",
    )
  }
  let path = build_strict_transition_route(snapshot.state, target)
  transition_through_with_timeout_policy(nic, station, path, policy)
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
pub fn[N : @hal.Nic] read_al_status_code_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let pdu = read_register_ap(nic, position, reg_al_status_code, 2, timeout)
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
