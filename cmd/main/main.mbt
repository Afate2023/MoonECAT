///|
enum CliBackend {
  Mock
  NativeAuto
  NativeWindowsNpcap
  NativeLinuxRaw
} derive(Eq, Debug)

///|
enum RunProgressOutput {
  Silent
  Text
  Ndjson
} derive(Eq, Debug)

///|
let pdo_logical_base : UInt = 0x1000U

///|
let process_data_eeprom_word_count : Int = 128

///|
/// MoonECAT CLI entry point.
/// Commands: list-if, scan, validate, run, run-zc, run-virtual, read-sii, esi-sii, state, diagnosis, od, master-od, esc-regs, expected-regs, startup-diff, mailbox-readback, startup-trace, replay, scenario, jitter-profile, auto-tune, topo-health, cycle-perf, comm-quality.
fn main {
  let _ = cli_main() catch {
    err => {
      println("moonecat error: " + err.to_string())
      ()
    }
  }
}

///|
fn cli_main() -> Unit raise @hal.EcError {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  let command = args[1]
  let as_json = has_flag(args, "--json")
  let timeout = resolve_timeout(args)
  let backend = parse_backend(args)

  if try_handle_local_cli_command(command, args, backend, as_json, timeout) {
    return
  }

  if try_handle_native_cli_command(command, args, backend, as_json, timeout) {
    return
  }

  if try_handle_run_cli_command(command, args, backend, as_json, timeout) {
    return
  }

  run_default_cli_command(command, args, backend, as_json, timeout)
}

///|

///|
fn[N : @hal.Nic] compute_state_transition_report(
  nic : N,
  args : Array[String],
  target : @protocol.EsmState,
  station : UInt?,
  use_path : Bool,
  timeout : @hal.Duration,
) -> StateTransitionReport raise @hal.EcError {
  match station {
    Some(configured_station) =>
      compute_station_transition_report(
        nic, args, target, configured_station, use_path, timeout,
      )
    None => {
      let wkc = @protocol.broadcast_state(nic, target, timeout)
      {
        mode: "broadcast",
        target,
        station: None,
        current: None,
        final_state: None,
        al_error_flag: None,
        status_code: None,
        raw_status_code: None,
        control_wkc: None,
        wkc: Some(wkc),
        pdo_audit: None,
      }
    }
  }
}

///|
fn[N : @hal.Nic] compute_station_transition_report(
  nic : N,
  args : Array[String],
  target : @protocol.EsmState,
  station : UInt,
  use_path : Bool,
  timeout : @hal.Duration,
) -> StateTransitionReport raise @hal.EcError {
  let current = @protocol.read_al_status_snapshot(nic, station, timeout).state
  let pdo_decision = if use_path &&
    target_requires_process_data_configuration(target) {
    Some(
      resolve_station_startup_decision(
        nic, args, station, pdo_logical_base, timeout,
      ),
    )
  } else {
    None
  }
  let path_preparation = if use_path && current != target {
    match pdo_decision {
      Some(decision) => Some(decision.preparation)
      None =>
        Some(
          prepare_station_startup_from_args(
            nic, args, station, pdo_logical_base, timeout,
          ),
        )
    }
  } else {
    None
  }
  match path_preparation {
    Some(preparation) =>
      startup_trace_drain_mailbox(nic, station, preparation.mailbox_config)
    None => ()
  }
  if use_path && target == @protocol.Op && current != @protocol.Op {
    let initial_preparation = match path_preparation {
      Some(preparation) => preparation
      None =>
        prepare_station_startup_from_args(
          nic, args, station, pdo_logical_base, timeout,
        )
    }
    let (final_observation, kick_wkc) = transition_station_to_op_with_preparation(
      nic, station, current, initial_preparation, timeout,
    )
    return {
      mode: "station-path",
      target,
      station: Some(station),
      current: Some(current),
      final_state: Some(final_observation.state),
      al_error_flag: Some(final_observation.error_indication),
      status_code: final_observation.status_code,
      raw_status_code: final_observation.raw_status_code,
      control_wkc: Some(final_observation.control_wkc),
      wkc: kick_wkc,
      pdo_audit: pdo_decision.map(fn(decision) { decision.pdo_audit }),
    }
  }
  if use_path &&
    target == @protocol.SafeOp &&
    current != @protocol.SafeOp &&
    current != @protocol.Op {
    let preparation = match path_preparation {
      Some(preparation) => preparation
      None =>
        prepare_station_startup_from_args(
          nic, args, station, pdo_logical_base, timeout,
        )
    }
    let final_observation = transition_station_to_safeop_with_process_mapping_observe(
      nic, station, current, preparation, timeout,
    )
    let final_snapshot = try? @protocol.read_al_status_snapshot(
      nic, station, timeout,
    )
    return {
      mode: "station-path",
      target,
      station: Some(station),
      current: Some(current),
      final_state: match final_observation {
        Some(observed) => Some(observed.state)
        None =>
          match final_snapshot {
            Ok(snapshot) => Some(snapshot.state)
            Err(_) => Some(current)
          }
      },
      al_error_flag: match final_observation {
        Some(observed) => Some(observed.error_indication)
        None =>
          match final_snapshot {
            Ok(snapshot) => Some(snapshot.error_indication)
            Err(_) => None
          }
      },
      status_code: match final_observation {
        Some(observed) => observed.status_code
        None =>
          match final_snapshot {
            Ok(snapshot) => snapshot.status_code
            Err(_) => None
          }
      },
      raw_status_code: final_observation.bind(fn(observed) {
        observed.raw_status_code
      }),
      control_wkc: final_observation.map(fn(observed) { observed.control_wkc }),
      wkc: None,
      pdo_audit: pdo_decision.map(fn(decision) { decision.pdo_audit }),
    }
  }
  let final_observation = if use_path {
    match path_preparation {
      Some(preparation) =>
        transition_station_to_target_with_preparation_observe(
          nic, station, target, preparation, timeout,
        )
      None =>
        transition_station_to_target_strict_after_recovery_observe(
          nic, station, target, timeout,
        )
    }
  } else {
    Some(@protocol.request_state_observe(nic, station, target, timeout))
  }
  let final_snapshot = try? @protocol.read_al_status_snapshot(
    nic, station, timeout,
  )
  {
    mode: if use_path {
      "station-path"
    } else {
      "station-direct"
    },
    target,
    station: Some(station),
    current: Some(current),
    final_state: match final_observation {
      Some(observed) => Some(observed.state)
      None =>
        match final_snapshot {
          Ok(snapshot) => Some(snapshot.state)
          Err(_) => Some(current)
        }
    },
    al_error_flag: match final_observation {
      Some(observed) => Some(observed.error_indication)
      None =>
        match final_snapshot {
          Ok(snapshot) => Some(snapshot.error_indication)
          Err(_) => None
        }
    },
    status_code: match final_observation {
      Some(observed) => observed.status_code
      None =>
        match final_snapshot {
          Ok(snapshot) => snapshot.status_code
          Err(_) => None
        }
    },
    raw_status_code: final_observation.bind(fn(observed) {
      observed.raw_status_code
    }),
    control_wkc: final_observation.map(fn(observed) { observed.control_wkc }),
    wkc: None,
    pdo_audit: pdo_decision.map(fn(decision) { decision.pdo_audit }),
  }
}

///|
fn[N : @hal.Nic] transition_station_to_target_strict_after_recovery_observe(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  timeout : @hal.Duration,
) -> @protocol.EsmStateRequestObservation? raise @hal.EcError {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  if snapshot.error_indication {
    ignore(@protocol.recover_al_error_for_transition(nic, station, timeout))
  }
  @protocol.transition_to_target_strict_observe(nic, station, target, timeout)
}

///|
fn[N : @hal.Nic] transition_station_to_target_strict_after_recovery(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  timeout : @hal.Duration,
) -> @protocol.EsmState raise @hal.EcError {
  match
    transition_station_to_target_strict_after_recovery_observe(
      nic, station, target, timeout,
    ) {
    Some(observed) => observed.state
    None => @protocol.read_al_status_snapshot(nic, station, timeout).state
  }
}

///|
fn[N : @hal.Nic] transition_station_to_op_after_recovery_observe(
  nic : N,
  station : UInt,
  pdo_ctx : @protocol.PdoContext,
  timeout : @hal.Duration,
) -> @protocol.EsmStateRequestObservation raise @hal.EcError {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  if snapshot.error_indication {
    ignore(@protocol.recover_al_error_for_transition(nic, station, timeout))
  }
  @protocol.request_state_with_process_data_observe(
    nic,
    station,
    @protocol.Op,
    pdo_ctx,
    timeout,
  )
}

///|
fn startup_mailbox_transition_from_route(
  current : @protocol.EsmState,
  target : @protocol.EsmState,
) -> @runtime.StartupCommandTransition? {
  match (current, target) {
    (@protocol.Init, @protocol.PreOp) => Some(@runtime.InitToPreOp)
    (@protocol.Init, @protocol.Boot) => Some(@runtime.InitToBoot)
    (@protocol.PreOp, @protocol.Init) => Some(@runtime.PreOpToInit)
    (@protocol.PreOp, @protocol.SafeOp) => Some(@runtime.PreOpToSafeOp)
    (@protocol.SafeOp, @protocol.Init) => Some(@runtime.SafeOpToInit)
    (@protocol.SafeOp, @protocol.PreOp) => Some(@runtime.SafeOpToPreOp)
    (@protocol.SafeOp, @protocol.Op) => Some(@runtime.SafeOpToOp)
    (@protocol.Op, @protocol.Init) => Some(@runtime.OpToInit)
    (@protocol.Op, @protocol.PreOp) => Some(@runtime.OpToPreOp)
    (@protocol.Op, @protocol.SafeOp) => Some(@runtime.OpToSafeOp)
    (@protocol.Boot, @protocol.Init) => Some(@runtime.BootToInit)
    _ => None
  }
}

///|
fn[N : @hal.Nic] transition_station_with_startup_mailbox_route_observe(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> @protocol.EsmStateRequestObservation? raise @hal.EcError {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  if snapshot.error_indication {
    ignore(@protocol.recover_al_error_for_transition(nic, station, timeout))
  }
  let current = @protocol.read_al_status_snapshot(nic, station, timeout).state
  let path = @protocol.build_strict_transition_route(current, target)
  let mut path_state = path[0]
  let mut last_observation : @protocol.EsmStateRequestObservation? = None
  for i = 1; i < path.length(); i = i + 1 {
    let next = path[i]
    match startup_mailbox_transition_from_route(path_state, next) {
      Some(transition) =>
        @runtime.apply_startup_mailbox_commands(
          nic,
          station,
          preparation.mailbox_config,
          preparation.startup_mailbox_commands,
          transition,
          timeout,
        )
      None => ()
    }
    let observed = @protocol.request_state_observe(nic, station, next, timeout)
    path_state = observed.state
    last_observation = Some(observed)
  }
  last_observation
}

///|
fn[N : @hal.Nic] transition_station_to_target_with_preparation_observe(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> @protocol.EsmStateRequestObservation? raise @hal.EcError {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  if snapshot.state == target {
    return None
  }
  if snapshot.state == @protocol.Init || snapshot.state == @protocol.Boot {
    ignore(
      @runtime.write_mailbox_mapping(nic, station, preparation.mapping, timeout),
    )
  }
  transition_station_with_startup_mailbox_route_observe(
    nic, station, target, preparation, timeout,
  )
}

///|
fn[N : @hal.Nic] transition_station_to_preop_with_mailbox(
  nic : N,
  station : UInt,
  current : @protocol.EsmState,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> @protocol.EsmState raise @hal.EcError {
  if current == @protocol.PreOp ||
    current == @protocol.SafeOp ||
    current == @protocol.Op {
    return current
  }
  match
    transition_station_to_target_with_preparation_observe(
      nic,
      station,
      @protocol.PreOp,
      preparation,
      timeout,
    ) {
    Some(observed) => observed.state
    None => @protocol.read_al_status_snapshot(nic, station, timeout).state
  }
}

///|
fn[N : @hal.Nic] transition_station_to_safeop_with_process_mapping(
  nic : N,
  station : UInt,
  current : @protocol.EsmState,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> @protocol.EsmState raise @hal.EcError {
  match
    transition_station_to_safeop_with_process_mapping_observe(
      nic, station, current, preparation, timeout,
    ) {
    Some(observed) => observed.state
    None => current
  }
}

///|
fn[N : @hal.Nic] transition_station_to_safeop_with_process_mapping_observe(
  nic : N,
  station : UInt,
  current : @protocol.EsmState,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> @protocol.EsmStateRequestObservation? raise @hal.EcError {
  if current == @protocol.SafeOp || current == @protocol.Op {
    return None
  }
  let preop_state = transition_station_to_preop_with_mailbox(
    nic, station, current, preparation, timeout,
  )
  if preop_state == @protocol.SafeOp || preop_state == @protocol.Op {
    return None
  }
  let process_preparation = refine_station_startup_preparation_in_preop_if_needed(
    nic,
    station,
    Some(preop_state),
    preparation,
    timeout,
  )
  @runtime.apply_presafeop_startup_mailbox_commands(
    nic,
    station,
    process_preparation.mailbox_config,
    process_preparation.startup_mailbox_commands,
    timeout,
  )
  ignore(
    @runtime.write_process_data_mapping(
      nic,
      station,
      process_preparation.mapping,
      timeout,
    ),
  )
  transition_station_to_target_strict_after_recovery_observe(
    nic,
    station,
    @protocol.SafeOp,
    timeout,
  )
}

///|
fn[N : @hal.Nic] transition_station_to_op_with_preparation(
  nic : N,
  station : UInt,
  current : @protocol.EsmState,
  initial_preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> (@protocol.EsmStateRequestObservation, UInt?) raise @hal.EcError {
  let state_before_process_mapping = transition_station_to_preop_with_mailbox(
    nic, station, current, initial_preparation, timeout,
  )
  let preparation = refine_station_startup_preparation_in_preop_if_needed(
    nic,
    station,
    Some(state_before_process_mapping),
    initial_preparation,
    timeout,
  )
  let pdo_ctx = @protocol.PdoContext::build(
    [(preparation.mapping, station)],
    pdo_logical_base,
  )
  match preparation.startup_outputs {
    Some(outputs) => pdo_ctx.set_slave_outputs(station, outputs)
    None => ()
  }
  let has_process_data = preparation.mapping.output_bytes > 0 ||
    preparation.mapping.input_bytes > 0
  let state_before_op = transition_station_to_safeop_with_process_mapping(
    nic, station, state_before_process_mapping, preparation, timeout,
  )
  @runtime.apply_startup_mailbox_commands(
    nic,
    station,
    preparation.mailbox_config,
    preparation.startup_mailbox_commands,
    @runtime.SafeOpToOp,
    timeout,
  )
  match preparation.dc_cycle_period_ns {
    Some(cycle_period_ns) =>
      ignore(
        @protocol.dc_configure_linear(
          nic,
          [station],
          cycle_period_ns.to_int().reinterpret_as_uint(),
          timeout,
          static_sync_iterations=32,
        ),
      )
    None => ()
  }
  let kick_before_op = if has_process_data {
    Some(@protocol.pdo_exchange(nic, pdo_ctx, timeout))
  } else {
    None
  }
  let final_observation : @protocol.EsmStateRequestObservation = if state_before_op ==
    @protocol.Op {
    {
      state: state_before_op,
      error_indication: false,
      status_code: None,
      raw_status_code: None,
      control_wkc: 0U,
    }
  } else if has_process_data {
    transition_station_to_op_after_recovery_observe(
      nic, station, pdo_ctx, timeout,
    )
  } else {
    match
      transition_station_to_target_strict_after_recovery_observe(
        nic,
        station,
        @protocol.Op,
        timeout,
      ) {
      Some(observed) => observed
      None => {
        let final_snapshot = @protocol.read_al_status_snapshot(
          nic, station, timeout,
        ) catch {
          _ =>
            { state: @protocol.Op, error_indication: false, status_code: None }
        }
        {
          state: final_snapshot.state,
          error_indication: final_snapshot.error_indication,
          status_code: final_snapshot.status_code,
          raw_status_code: None,
          control_wkc: 0U,
        }
      }
    }
  }
  let final_wkc = if final_observation.state == @protocol.Op && has_process_data {
    Some(@protocol.pdo_exchange(nic, pdo_ctx, timeout))
  } else {
    kick_before_op
  }
  (final_observation, final_wkc)
}

///|
struct StateTransitionReport {
  mode : String
  target : @protocol.EsmState
  station : UInt?
  current : @protocol.EsmState?
  final_state : @protocol.EsmState?
  al_error_flag : Bool?
  status_code : UInt?
  raw_status_code : UInt?
  control_wkc : UInt?
  wkc : UInt?
  pdo_audit : PdoAuditReport?
}

///|
struct PdoMappingObjectReport {
  index : UInt
  entries : Array[UInt]
}

///|
struct PdoDirectionReport {
  assignment_index : UInt
  assigned_pdos : Array[UInt]
  objects : Array[PdoMappingObjectReport]
}

///|
struct PdoAuditReport {
  plan_source : String
  policy : String
  effective_source : String
  live_detected : Bool?
  live_differs_from_plan : Bool?
  live_read_error : String?
  configured_rx : PdoDirectionReport
  configured_tx : PdoDirectionReport
  live_rx : PdoDirectionReport?
  live_tx : PdoDirectionReport?
  mismatches : Array[String]
}

///|
struct StationStartupDecision {
  preparation : @runtime.SlaveStartupPreparation
  pdo_audit : PdoAuditReport
}

///|
struct EscSyncManagerRegisterReport {
  index : Int
  register_offset : UInt
  raw_hex : String
  physical_start : UInt
  length : UInt
  control : Byte
  status : Byte
  activate : Byte
}

///|
struct EscFmmuRegisterReport {
  index : Int
  register_offset : UInt
  raw_hex : String
  logical_start : UInt
  length : UInt
  logical_start_bit : Byte
  logical_end_bit : Byte
  physical_start : UInt
  physical_start_bit : Byte
  type_register : Byte
  activate : Byte
}

///|
struct EscRegisterReport {
  station : UInt
  al_state : @protocol.EsmState
  al_error_flag : Bool
  al_status_code : UInt?
  sync_managers : Array[EscSyncManagerRegisterReport]
  fmmus : Array[EscFmmuRegisterReport]
}

///|
struct ExpectedEscRegisterReport {
  station : UInt
  sync_managers : Array[EscSyncManagerRegisterReport]
  fmmus : Array[EscFmmuRegisterReport]
}

///|
struct StartupDiffReport {
  station : UInt
  offline_expected : ExpectedEscRegisterReport
  online_expected : ExpectedEscRegisterReport?
  online_expected_error : String?
  actual_esc : EscRegisterReport?
  actual_esc_error : String?
  offline_mailbox_commands : Array[@runtime.StartupMailboxCommand]
  online_mailbox_commands : Array[@runtime.StartupMailboxCommand]
  differences : Array[String]
}

///|
struct MailboxReadbackEntry {
  index : Int
  register_offset : UInt
  expected : EscSyncManagerRegisterReport
  actual : EscSyncManagerRegisterReport
  matches : Bool
}

///|
struct MailboxReadbackReport {
  station : UInt
  source : String
  entries : Array[MailboxReadbackEntry]
  mismatches : Array[String]
}

///|
struct StartupTraceOdEntry {
  subindex : Byte
  value_hex : String?
  value_u32 : UInt?
  error_detail : String?
  abort_code : UInt?
}

///|
struct StartupTraceOdObject {
  index : UInt
  subindex_count : UInt?
  entries : Array[StartupTraceOdEntry]
  error_detail : String?
  abort_code : UInt?
}

///|
struct StartupTracePhase {
  name : String
  al_state : @protocol.EsmState?
  al_error_flag : Bool?
  al_status_code : UInt?
  sync_managers : Array[EscSyncManagerRegisterReport]
  fmmus : Array[EscFmmuRegisterReport]
  od_objects : Array[StartupTraceOdObject]
  notes : Array[String]
}

///|
struct StartupTraceReport {
  station : UInt
  source : String
  initial_state : @protocol.EsmState?
  final_state : @protocol.EsmState?
  phases : Array[StartupTracePhase]
  transition_error : String?
  pdo_audit : PdoAuditReport?
}

///|
fn[N : @hal.Nic] read_esc_register_report(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> EscRegisterReport raise @hal.EcError {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  let sync_managers : Array[EscSyncManagerRegisterReport] = []
  for index = 2; index <= 3; index = index + 1 {
    let register_offset = @protocol.reg_sm_base +
      index.reinterpret_as_uint() *
      @protocol.sm_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.sm_entry_size, timeout,
      ).data
    sync_managers.push(
      decode_esc_sync_manager_window(index, register_offset, window),
    )
  }
  let fmmus : Array[EscFmmuRegisterReport] = []
  for index = 0; index <= 1; index = index + 1 {
    let register_offset = @protocol.reg_fmmu_base +
      index.reinterpret_as_uint() *
      @protocol.fmmu_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.fmmu_entry_size, timeout,
      ).data
    fmmus.push(decode_esc_fmmu_window(index, register_offset, window))
  }
  {
    station,
    al_state: snapshot.state,
    al_error_flag: snapshot.error_indication,
    al_status_code: snapshot.status_code,
    sync_managers,
    fmmus,
  }
}

///|
fn[N : @hal.Nic] build_expected_esc_register_report(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> ExpectedEscRegisterReport raise @hal.EcError {
  let initial = prepare_station_startup(nic, station, pdo_logical_base, timeout)
  let refined = @runtime.refine_startup_preparation_in_preop(
    nic, station, pdo_logical_base, initial, timeout,
  )
  build_expected_esc_register_report_from_mapping(station, refined.mapping)
}

///|
fn build_expected_esc_register_report_from_mapping(
  station : UInt,
  mapping : @mailbox.SlaveMapping,
) -> ExpectedEscRegisterReport raise @hal.EcError {
  {
    station,
    sync_managers: expected_sync_manager_register_reports(mapping),
    fmmus: expected_fmmu_register_reports(mapping),
  }
}

///|
fn require_esi_json_startup_preparation(
  args : Array[String],
  logical_base : UInt,
) -> @runtime.SlaveStartupPreparation raise @hal.EcError {
  match optional_esi_json_startup_preparation(args, logical_base) {
    Some(preparation) => preparation
    None =>
      raise @hal.EcError::ConfigMismatch(
        "startup-diff requires --esi-json <path>",
      )
  }
}

///|
fn[N : @hal.Nic] build_startup_diff_report(
  nic : N,
  args : Array[String],
  station : UInt,
  timeout : @hal.Duration,
) -> StartupDiffReport raise @hal.EcError {
  let offline = require_esi_json_startup_preparation(args, pdo_logical_base)
  let offline_expected = build_expected_esc_register_report_from_mapping(
    station,
    offline.mapping,
  )
  let actual_esc_result : Result[EscRegisterReport, @hal.EcError] = try? read_esc_register_report(
    nic, station, timeout,
  )
  let actual_esc = match actual_esc_result {
    Ok(report) => Some(report)
    Err(_) => None
  }
  let actual_esc_error = match actual_esc_result {
    Ok(_) => None
    Err(err) => Some(err.to_string())
  }
  let online_refined_result : Result[
    @runtime.SlaveStartupPreparation,
    @hal.EcError,
  ] = try? ({
    let online_initial = prepare_station_startup(
      nic, station, pdo_logical_base, timeout,
    )
    @runtime.refine_startup_preparation_in_preop(
      nic, station, pdo_logical_base, online_initial, timeout,
    )
  })
  let online_expected = match online_refined_result {
    Ok(preparation) =>
      Some(
        build_expected_esc_register_report_from_mapping(
          station,
          preparation.mapping,
        ),
      )
    Err(_) => None
  }
  let online_expected_error = match online_refined_result {
    Ok(_) => None
    Err(err) => Some(err.to_string())
  }
  let online_mailbox_commands = match online_refined_result {
    Ok(preparation) => preparation.startup_mailbox_commands
    Err(_) => []
  }
  {
    station,
    offline_expected,
    online_expected,
    online_expected_error,
    actual_esc,
    actual_esc_error,
    offline_mailbox_commands: offline.startup_mailbox_commands,
    online_mailbox_commands,
    differences: startup_diff_messages(
      offline_expected,
      online_expected,
      online_expected_error,
      actual_esc,
      actual_esc_error,
      offline.startup_mailbox_commands,
      online_mailbox_commands,
    ),
  }
}

///|
fn pdo_policy_name(prefer_live_pdo_state : Bool) -> String {
  if prefer_live_pdo_state {
    "prefer-live"
  } else {
    "force-configured"
  }
}

///|
fn pdo_effective_source(
  plan_source : String,
  prefer_live_pdo_state : Bool,
  live_detected : Bool,
) -> String {
  if !prefer_live_pdo_state {
    if plan_source == "esi-json" {
      "forced-esi"
    } else {
      "forced-online-sii"
    }
  } else if live_detected {
    "live"
  } else {
    plan_source
  }
}

///|
fn pdo_mapping_entry_raw(entry : @mailbox.SiiPdoEntry) -> UInt {
  entry.entry_index |
  (entry.subindex.to_uint() << 16) |
  (entry.bit_length.to_uint() << 24)
}

///|
fn normalize_pdo_mapping_entry_raw(raw : UInt) -> UInt {
  let entry_index = (raw >> 16) & 0xFFFFU
  let subindex = (raw >> 8) & 0xFFU
  let bit_length = raw & 0xFFU
  entry_index | (subindex << 16) | (bit_length << 24)
}

///|
fn pdo_direction_from_sii(
  pdos : Array[@mailbox.SiiPdo],
  assignment_index : UInt,
) -> PdoDirectionReport {
  {
    assignment_index,
    assigned_pdos: pdos.map(fn(pdo) { pdo.pdo_index }),
    objects: pdos.map(fn(pdo) {
      {
        index: pdo.pdo_index,
        entries: pdo.entries.map(fn(entry) { pdo_mapping_entry_raw(entry) }),
      }
    }),
  }
}

///|
fn[N : @hal.Nic] pdo_sdo_u32(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let payload = startup_trace_sdo_upload(
    nic, station, mailbox_config, index, subindex, timeout,
  )
  match decode_payload_u32_le(payload) {
    Some(value) => value
    None =>
      raise @hal.EcError::MailboxProtocol(
        "pdo audit: empty payload at 0x" +
        format_hex(index, 4) +
        ":" +
        format_hex(subindex.to_uint(), 2),
      )
  }
}

///|
fn[N : @hal.Nic] read_live_pdo_direction(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  assignment_index : UInt,
  timeout : @hal.Duration,
) -> PdoDirectionReport raise @hal.EcError {
  let count = pdo_sdo_u32(
    nic, station, mailbox_config, assignment_index, b'\x00', timeout,
  ).reinterpret_as_int()
  let assigned_pdos : Array[UInt] = []
  let objects : Array[PdoMappingObjectReport] = []
  for i = 1; i <= count; i = i + 1 {
    let pdo_index = pdo_sdo_u32(
        nic,
        station,
        mailbox_config,
        assignment_index,
        i.to_byte(),
        timeout,
      ) &
      0xFFFFU
    assigned_pdos.push(pdo_index)
    let entry_count = pdo_sdo_u32(
      nic, station, mailbox_config, pdo_index, b'\x00', timeout,
    ).reinterpret_as_int()
    let entries : Array[UInt] = []
    for entry_index = 1
        entry_index <= entry_count
        entry_index = entry_index + 1 {
      entries.push(
        normalize_pdo_mapping_entry_raw(
          pdo_sdo_u32(
            nic,
            station,
            mailbox_config,
            pdo_index,
            entry_index.to_byte(),
            timeout,
          ),
        ),
      )
    }
    objects.push({ index: pdo_index, entries })
  }
  { assignment_index, assigned_pdos, objects }
}

///|
fn[N : @hal.Nic] read_live_pdo_reports(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> (PdoDirectionReport, PdoDirectionReport) raise @hal.EcError {
  let scan_report = @runtime.scan(nic, timeout)
  let slave = resolve_cli_slave(scan_report, Some(station))
  let mailbox_session = @runtime.prepare_slave_mailbox_ap(
    nic,
    slave.position.reinterpret_as_uint(),
    station,
    timeout,
  )
  let rx = read_live_pdo_direction(
    nic,
    station,
    mailbox_session.mailbox_config,
    0x1C12U,
    timeout,
  )
  let tx = read_live_pdo_direction(
    nic,
    station,
    mailbox_session.mailbox_config,
    0x1C13U,
    timeout,
  )
  if mailbox_session.original_state != @protocol.PreOp {
    ignore(
      try? @runtime.restore_slave_mailbox_state(
        nic,
        station,
        mailbox_session.original_state,
        timeout,
      ),
    )
  }
  (rx, tx)
}

///|
fn pdo_uint_arrays_equal(lhs : Array[UInt], rhs : Array[UInt]) -> Bool {
  if lhs.length() != rhs.length() {
    return false
  }
  for i = 0; i < lhs.length(); i = i + 1 {
    if lhs[i] != rhs[i] {
      return false
    }
  }
  true
}

///|
fn pdo_append_unique(indices : Array[UInt], value : UInt) -> Unit {
  for existing in indices {
    if existing == value {
      return
    }
  }
  indices.push(value)
}

///|
fn pdo_direction_object_entries(
  direction : PdoDirectionReport,
  index : UInt,
) -> Array[UInt]? {
  for object in direction.objects {
    if object.index == index {
      return Some(object.entries)
    }
  }
  None
}

///|
fn pdo_assignment_indices_text(indices : Array[UInt]) -> String {
  "[" +
  join_strings(indices.map(fn(index) { format_hex(index, 4) }), ", ") +
  "]"
}

///|
fn pdo_mapping_entry_summary(raw : UInt) -> String {
  format_hex(raw & 0xFFFFU, 4) +
  ":" +
  format_hex((raw >> 16) & 0xFFU, 2) +
  "/" +
  ((raw >> 24) & 0xFFU).to_string()
}

///|
fn pdo_mapping_entries_text(entries : Array[UInt]) -> String {
  "[" +
  join_strings(
    entries.map(fn(entry) { pdo_mapping_entry_summary(entry) }),
    ", ",
  ) +
  "]"
}

///|
fn pdo_direction_mismatch_messages(
  configured : PdoDirectionReport,
  live : PdoDirectionReport,
) -> Array[String] {
  let mismatches : Array[String] = []
  if !pdo_uint_arrays_equal(configured.assigned_pdos, live.assigned_pdos) {
    mismatches.push(
      "assignment " +
      format_hex(configured.assignment_index, 4) +
      " expected=" +
      pdo_assignment_indices_text(configured.assigned_pdos) +
      " actual=" +
      pdo_assignment_indices_text(live.assigned_pdos),
    )
  }
  let object_indices : Array[UInt] = []
  for index in configured.assigned_pdos {
    pdo_append_unique(object_indices, index)
  }
  for index in live.assigned_pdos {
    pdo_append_unique(object_indices, index)
  }
  for index in object_indices {
    let configured_entries = match
      pdo_direction_object_entries(configured, index) {
      Some(entries) => entries
      None => []
    }
    let live_entries = match pdo_direction_object_entries(live, index) {
      Some(entries) => entries
      None => []
    }
    if !pdo_uint_arrays_equal(configured_entries, live_entries) {
      mismatches.push(
        "mapping " +
        format_hex(index, 4) +
        " expected=" +
        pdo_mapping_entries_text(configured_entries) +
        " actual=" +
        pdo_mapping_entries_text(live_entries),
      )
    }
  }
  mismatches
}

///|
fn[N : @hal.Nic] build_pdo_audit_report(
  nic : N,
  args : Array[String],
  station : UInt,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> PdoAuditReport {
  let plan_source = configured_startup_source(args)
  let configured_rx = pdo_direction_from_sii(preparation.sii.rx_pdo, 0x1C12U)
  let configured_tx = pdo_direction_from_sii(preparation.sii.tx_pdo, 0x1C13U)
  let live_result : Result[
    (PdoDirectionReport, PdoDirectionReport),
    @hal.EcError,
  ] = try? read_live_pdo_reports(nic, station, timeout)
  match live_result {
    Ok((live_rx, live_tx)) => {
      let mismatches = pdo_direction_mismatch_messages(configured_rx, live_rx)
      for message in pdo_direction_mismatch_messages(configured_tx, live_tx) {
        mismatches.push(message)
      }
      let live_detected = !live_rx.assigned_pdos.is_empty() ||
        !live_tx.assigned_pdos.is_empty()
      {
        plan_source,
        policy: pdo_policy_name(preparation.prefer_live_pdo_state),
        effective_source: pdo_effective_source(
          plan_source,
          preparation.prefer_live_pdo_state,
          live_detected,
        ),
        live_detected: Some(live_detected),
        live_differs_from_plan: Some(!mismatches.is_empty()),
        live_read_error: None,
        configured_rx,
        configured_tx,
        live_rx: Some(live_rx),
        live_tx: Some(live_tx),
        mismatches,
      }
    }
    Err(err) => {
      let live_detected = false
      {
        plan_source,
        policy: pdo_policy_name(preparation.prefer_live_pdo_state),
        effective_source: pdo_effective_source(
          plan_source,
          preparation.prefer_live_pdo_state,
          live_detected,
        ),
        live_detected: None,
        live_differs_from_plan: None,
        live_read_error: Some(err.to_string()),
        configured_rx,
        configured_tx,
        live_rx: None,
        live_tx: None,
        mismatches: [],
      }
    }
  }
}

///|
fn[N : @hal.Nic] resolve_station_startup_decision(
  nic : N,
  args : Array[String],
  station : UInt,
  logical_base : UInt,
  timeout : @hal.Duration,
) -> StationStartupDecision raise @hal.EcError {
  let preparation = prepare_station_startup_from_args(
    nic, args, station, logical_base, timeout,
  )
  {
    preparation,
    pdo_audit: build_pdo_audit_report(nic, args, station, preparation, timeout),
  }
}

///|
fn mailbox_readback_source(args : Array[String]) -> String {
  configured_startup_source(args)
}

///|
fn startup_trace_source(args : Array[String]) -> String {
  configured_startup_source(args)
}

///|
fn startup_command_reconfigures_pdo_mapping(
  command : @runtime.StartupMailboxCommand,
) -> Bool {
  if command.transition != @runtime.PreOpToSafeOp {
    return false
  }
  if command.index == 0x1C12U || command.index == 0x1C13U {
    return true
  }
  (command.index >= 0x1600U && command.index <= 0x17FFU) ||
  (command.index >= 0x1A00U && command.index <= 0x1BFFU)
}

///|
fn startup_mailbox_commands_need_preop_refinement(
  commands : Array[@runtime.StartupMailboxCommand],
) -> Bool {
  for command in commands {
    if startup_command_reconfigures_pdo_mapping(command) {
      return true
    }
  }
  false
}

///|
fn[N : @hal.Nic] refine_station_startup_preparation_in_preop_if_needed(
  nic : N,
  station : UInt,
  state : @protocol.EsmState?,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> @runtime.SlaveStartupPreparation {
  if state == Some(@protocol.PreOp) &&
    startup_mailbox_commands_need_preop_refinement(
      preparation.startup_mailbox_commands,
    ) {
    @runtime.refine_startup_preparation_in_preop(
      nic, station, pdo_logical_base, preparation, timeout,
    )
  } else {
    preparation
  }
}

///|
fn mailbox_sm_window_matches(expected : Bytes, actual : Bytes) -> Bool {
  if expected.length() < @protocol.sm_entry_size ||
    actual.length() < @protocol.sm_entry_size {
    return false
  }
  expected[0] == actual[0] &&
  expected[1] == actual[1] &&
  expected[2] == actual[2] &&
  expected[3] == actual[3] &&
  expected[4] == actual[4] &&
  expected[6] == actual[6]
}

///|
fn build_mailbox_readback_mismatch(entry : MailboxReadbackEntry) -> String {
  "SM" +
  entry.index.to_string() +
  " expected=" +
  entry.expected.raw_hex +
  " actual=" +
  entry.actual.raw_hex
}

///|
fn[N : @hal.Nic] build_mailbox_readback_report(
  nic : N,
  args : Array[String],
  station : UInt,
  timeout : @hal.Duration,
) -> MailboxReadbackReport raise @hal.EcError {
  let preparation = prepare_station_startup_from_args(
    nic, args, station, pdo_logical_base, timeout,
  )
  let entries : Array[MailboxReadbackEntry] = []
  let mismatches : Array[String] = []
  for i = 0; i < preparation.mapping.sm_configs.length(); i = i + 1 {
    let sm = preparation.mapping.sm_configs[i]
    match sm.sm_type {
      @mailbox.MailboxOut | @mailbox.MailboxIn => {
        let register_offset = @protocol.reg_sm_base +
          i.reinterpret_as_uint() *
          @protocol.sm_entry_size.reinterpret_as_uint()
        let expected_window = sm.to_bytes()
        ignore(
          @protocol.write_register_fp(
            nic, station, register_offset, expected_window, timeout,
          ),
        )
        let actual_window = @protocol.read_register_fp(
            nic, station, register_offset, @protocol.sm_entry_size, timeout,
          ).data
        let entry = {
          index: i,
          register_offset,
          expected: decode_esc_sync_manager_window(
            i, register_offset, expected_window,
          ),
          actual: decode_esc_sync_manager_window(
            i, register_offset, actual_window,
          ),
          matches: mailbox_sm_window_matches(expected_window, actual_window),
        }
        if !entry.matches {
          mismatches.push(build_mailbox_readback_mismatch(entry))
        }
        entries.push(entry)
      }
      _ => ()
    }
  }
  { station, source: mailbox_readback_source(args), entries, mismatches }
}

///|
fn[N : @hal.Nic] read_sync_manager_reports(
  nic : N,
  station : UInt,
  start_index : Int,
  end_index : Int,
  timeout : @hal.Duration,
) -> Array[EscSyncManagerRegisterReport] raise @hal.EcError {
  let reports : Array[EscSyncManagerRegisterReport] = []
  for index = start_index; index <= end_index; index = index + 1 {
    let register_offset = @protocol.reg_sm_base +
      index.reinterpret_as_uint() *
      @protocol.sm_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.sm_entry_size, timeout,
      ).data
    reports.push(decode_esc_sync_manager_window(index, register_offset, window))
  }
  reports
}

///|
fn[N : @hal.Nic] read_fmmu_reports(
  nic : N,
  station : UInt,
  start_index : Int,
  end_index : Int,
  timeout : @hal.Duration,
) -> Array[EscFmmuRegisterReport] raise @hal.EcError {
  let reports : Array[EscFmmuRegisterReport] = []
  for index = start_index; index <= end_index; index = index + 1 {
    let register_offset = @protocol.reg_fmmu_base +
      index.reinterpret_as_uint() *
      @protocol.fmmu_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.fmmu_entry_size, timeout,
      ).data
    reports.push(decode_esc_fmmu_window(index, register_offset, window))
  }
  reports
}

///|
fn[N : @hal.Nic] capture_startup_trace_phase(
  nic : N,
  station : UInt,
  name : String,
  timeout : @hal.Duration,
) -> StartupTracePhase {
  let al_result : Result[@protocol.EsmStatusSnapshot, @hal.EcError] = try? @protocol.read_al_status_snapshot(
    nic, station, timeout,
  )
  let sm_result : Result[Array[EscSyncManagerRegisterReport], @hal.EcError] = try? read_sync_manager_reports(
    nic, station, 0, 3, timeout,
  )
  let fmmu_result : Result[Array[EscFmmuRegisterReport], @hal.EcError] = try? read_fmmu_reports(
    nic, station, 0, 1, timeout,
  )
  let notes : Array[String] = []
  let (al_state, al_error_flag, al_status_code) = match al_result {
    Ok(snapshot) =>
      (
        Some(snapshot.state),
        Some(snapshot.error_indication),
        snapshot.status_code,
      )
    Err(err) => {
      notes.push("al snapshot unavailable: " + err.to_string())
      (None, None, None)
    }
  }
  let sync_managers = match sm_result {
    Ok(value) => value
    Err(err) => {
      notes.push("sync manager snapshot unavailable: " + err.to_string())
      []
    }
  }
  let fmmus = match fmmu_result {
    Ok(value) => value
    Err(err) => {
      notes.push("fmmu snapshot unavailable: " + err.to_string())
      []
    }
  }
  {
    name,
    al_state,
    al_error_flag,
    al_status_code,
    sync_managers,
    fmmus,
    od_objects: [],
    notes,
  }
}

///|
fn startup_trace_phase_with_notes(
  phase : StartupTracePhase,
  extra_notes : Array[String],
) -> StartupTracePhase {
  if extra_notes.is_empty() {
    return phase
  }
  let notes = phase.notes
  for note in extra_notes {
    notes.push(note)
  }
  { ..phase, notes, }
}

///|
fn startup_trace_od_indices() -> Array[UInt] {
  [0x1602U, 0x1A02U, 0x1C12U, 0x1C13U]
}

///|
let startup_trace_mailbox_max_polls : Int = 32

///|
let startup_trace_mailbox_drain_limit : Int = 4

///|
let startup_trace_sdo_max_attempts : Int = 3

///|
fn startup_trace_should_retry_od_read(err : @hal.EcError) -> Bool {
  match err {
    @hal.EcError::MailboxTimeout => true
    @hal.EcError::MailboxProtocol(message) =>
      message.contains("stale") || message.contains("counter mismatch")
    _ => false
  }
}

///|
fn[N : @hal.Nic] startup_trace_drain_mailbox(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
) -> Unit {
  let zero_timeout = @hal.Duration(0L)
  for _drain = 0
      _drain < startup_trace_mailbox_drain_limit
      _drain = _drain + 1 {
    let poll_result : Result[Bool, @hal.EcError] = try? @protocol.mailbox_poll(
      nic, station, mailbox_config, zero_timeout,
    )
    match poll_result {
      Ok(true) =>
        ignore(
          try? @protocol.mailbox_recv(
            nic,
            station,
            mailbox_config,
            zero_timeout,
            max_polls=1,
          ),
        )
      _ => return
    }
  }
}

///|
fn[N : @hal.Nic] startup_trace_sdo_upload_once(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let rmsm = @mailbox.Rmsm::new(max_retries=0)
  let counter = rmsm.begin_transaction()
  let txn = @mailbox.build_sdo_upload(counter, station, index, subindex)
  let frame = txn.encode()
  startup_trace_drain_mailbox(nic, station, mailbox_config)
  @protocol.mailbox_send(nic, station, mailbox_config, frame, timeout)
  for _stale_attempt = 0
      _stale_attempt < startup_trace_mailbox_drain_limit
      _stale_attempt = _stale_attempt + 1 {
    let response_raw = @protocol.mailbox_recv_rmsm(
      nic,
      station,
      mailbox_config,
      rmsm,
      timeout,
      max_polls=startup_trace_mailbox_max_polls,
    )
    let (mbh, resp) = @mailbox.decode_sdo_response(response_raw)
    if !rmsm.validate_response(mbh.counter) {
      continue
    }
    if resp.command != @mailbox.SdoCommand::UploadResponse {
      raise @hal.EcError::MailboxProtocol(
        "startup-trace od read: expected UploadResponse, got " +
        resp.command.to_string(),
      )
    }
    if resp.index != index || resp.subindex != subindex {
      raise @hal.EcError::MailboxProtocol(
        "startup-trace od read: index/subindex mismatch in response",
      )
    }
    if resp.segmented {
      raise @hal.EcError::MailboxProtocol(
        "startup-trace od read: segmented response is not supported",
      )
    }
    return resp.data
  }
  raise @hal.EcError::MailboxProtocol("RMSM: too many stale frames received")
}

///|
fn[N : @hal.Nic] startup_trace_sdo_upload(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let mut last_err : @hal.EcError? = None
  for _attempt = 0
      _attempt < startup_trace_sdo_max_attempts
      _attempt = _attempt + 1 {
    let result : Result[Bytes, @hal.EcError] = try? startup_trace_sdo_upload_once(
      nic, station, mailbox_config, index, subindex, timeout,
    )
    match result {
      Ok(payload) => return payload
      Err(err) => {
        let should_retry = startup_trace_should_retry_od_read(err)
        last_err = Some(err)
        if !should_retry {
          raise err
        }
      }
    }
  }
  match last_err {
    Some(err) => raise err
    None =>
      raise @hal.EcError::Internal("startup-trace od read exhausted retries")
  }
}

///|
fn startup_trace_od_entry_failure(
  subindex : Byte,
  err : @hal.EcError,
) -> StartupTraceOdEntry {
  {
    subindex,
    value_hex: None,
    value_u32: None,
    error_detail: Some(err.to_string()),
    abort_code: match err {
      @hal.EcError::SdoAbort(code) => Some(code)
      _ => None
    },
  }
}

///|
fn startup_trace_od_entry_success(
  subindex : Byte,
  payload : Bytes,
) -> StartupTraceOdEntry {
  {
    subindex,
    value_hex: Some(bytes_hex(payload)),
    value_u32: decode_payload_u32_le(payload),
    error_detail: None,
    abort_code: None,
  }
}

///|
fn[N : @hal.Nic] read_startup_trace_od_object(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  index : UInt,
  timeout : @hal.Duration,
) -> StartupTraceOdObject {
  let count_result : Result[Bytes, @hal.EcError] = try? startup_trace_sdo_upload(
    nic, station, mailbox_config, index, b'\x00', timeout,
  )
  match count_result {
    Err(err) =>
      {
        index,
        subindex_count: None,
        entries: [startup_trace_od_entry_failure(b'\x00', err)],
        error_detail: Some(err.to_string()),
        abort_code: match err {
          @hal.EcError::SdoAbort(code) => Some(code)
          _ => None
        },
      }
    Ok(payload) => {
      let entries : Array[StartupTraceOdEntry] = [
        startup_trace_od_entry_success(b'\x00', payload),
      ]
      let subindex_count = decode_payload_u32_le(payload)
      match subindex_count {
        Some(count) =>
          for i = 1; i <= count.reinterpret_as_int(); i = i + 1 {
            let subindex = i.to_byte()
            let entry_result : Result[Bytes, @hal.EcError] = try? startup_trace_sdo_upload(
              nic, station, mailbox_config, index, subindex, timeout,
            )
            match entry_result {
              Ok(entry_payload) =>
                entries.push(
                  startup_trace_od_entry_success(subindex, entry_payload),
                )
              Err(err) =>
                entries.push(startup_trace_od_entry_failure(subindex, err))
            }
          }
        None => ()
      }
      { index, subindex_count, entries, error_detail: None, abort_code: None }
    }
  }
}

///|
fn[N : @hal.Nic] read_startup_trace_od_objects(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Array[StartupTraceOdObject] {
  let scan_result : Result[@runtime.ScanReport, @hal.EcError] = try? @runtime.scan(
    nic, timeout,
  )
  let target_slave = match scan_result {
    Ok(scan_report) =>
      Some(resolve_cli_slave(scan_report, Some(station))) catch {
        _ => None
      }
    Err(_) => None
  }
  let objects : Array[StartupTraceOdObject] = []
  guard target_slave is Some(slave) else {
    let err = @hal.EcError::ConfigMismatch(
      "startup-trace od snapshot station not found in current scan: " +
      station.to_string(),
    )
    for index in startup_trace_od_indices() {
      objects.push({
        index,
        subindex_count: None,
        entries: [startup_trace_od_entry_failure(b'\x00', err)],
        error_detail: Some(err.to_string()),
        abort_code: None,
      })
    }
    return objects
  }
  let mailbox_session_result : Result[@runtime.MailboxSession, @hal.EcError] = try? @runtime.prepare_slave_mailbox_ap(
    nic,
    slave.position.reinterpret_as_uint(),
    station,
    timeout,
  )
  match mailbox_session_result {
    Err(err) =>
      for index in startup_trace_od_indices() {
        objects.push({
          index,
          subindex_count: None,
          entries: [startup_trace_od_entry_failure(b'\x00', err)],
          error_detail: Some(err.to_string()),
          abort_code: None,
        })
      }
    Ok(mailbox_session) => {
      for index in startup_trace_od_indices() {
        objects.push(
          read_startup_trace_od_object(
            nic,
            station,
            mailbox_session.mailbox_config,
            index,
            timeout,
          ),
        )
      }
      if mailbox_session.original_state != @protocol.PreOp {
        ignore(
          try? @runtime.restore_slave_mailbox_state(
            nic,
            station,
            mailbox_session.original_state,
            timeout,
          ),
        )
      }
    }
  }
  objects
}

///|
fn[N : @hal.Nic] startup_trace_phase_with_od(
  nic : N,
  station : UInt,
  name : String,
  timeout : @hal.Duration,
) -> StartupTracePhase {
  {
    ..capture_startup_trace_phase(nic, station, name, timeout),
    od_objects: read_startup_trace_od_objects(nic, station, timeout),
  }
}

///|
fn[N : @hal.Nic] startup_trace_reset_notes(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Array[String] {
  let notes : Array[String] = []
  let recover_result : Result[@protocol.EsmStatusSnapshot, @hal.EcError] = try? @protocol.recover_al_error_for_transition(
    nic, station, timeout,
  )
  match recover_result {
    Ok(snapshot) =>
      notes.push(
        "recover-al-error state=" +
        snapshot.state.to_string() +
        " error=" +
        snapshot.error_indication.to_string(),
      )
    Err(err) => notes.push("recover-al-error failed: " + err.to_string())
  }
  let request_init_result : Result[@protocol.EsmState, @hal.EcError] = try? @protocol.request_state(
    nic,
    station,
    @protocol.Init,
    timeout,
  )
  match request_init_result {
    Ok(state) => notes.push("request-init confirmed=" + state.to_string())
    Err(err) => {
      notes.push("request-init failed: " + err.to_string())
      let broadcast_result : Result[UInt, @hal.EcError] = try? @protocol.broadcast_state(
        nic,
        @protocol.Init,
        timeout,
      )
      match broadcast_result {
        Ok(wkc) => notes.push("broadcast-init wkc=" + wkc.to_string())
        Err(broadcast_err) =>
          notes.push("broadcast-init failed: " + broadcast_err.to_string())
      }
    }
  }
  let scan_result : Result[@runtime.ScanReport, @hal.EcError] = try? @runtime.scan(
    nic, timeout,
  )
  match scan_result {
    Ok(report) => {
      let stations = report.slaves.map(fn(slave) {
        slave.station_address.to_string()
      })
      notes.push(
        "scan slave_count=" +
        report.slave_count.to_string() +
        " stations=[" +
        join_strings(stations, ",") +
        "]",
      )
    }
    Err(err) => notes.push("scan failed: " + err.to_string())
  }
  notes
}

///|
fn[N : @hal.Nic] build_startup_trace_report(
  nic : N,
  args : Array[String],
  station : UInt,
  timeout : @hal.Duration,
) -> StartupTraceReport raise @hal.EcError {
  let decision = resolve_station_startup_decision(
    nic, args, station, pdo_logical_base, timeout,
  )
  let pdo_audit = decision.pdo_audit
  let source = startup_trace_source(args)
  let initial_preparation = decision.preparation
  let phases : Array[StartupTracePhase] = []
  phases.push(capture_startup_trace_phase(nic, station, "initial", timeout))
  if has_flag(args, "--reset-init") {
    let reset_notes = startup_trace_reset_notes(nic, station, timeout)
    phases.push(
      startup_trace_phase_with_notes(
        capture_startup_trace_phase(nic, station, "after_reset_init", timeout),
        reset_notes,
      ),
    )
  }
  let initial_state = phases[0].al_state
  let mut phase_state = phases[phases.length() - 1].al_state
  let mut transition_error : String? = None
  let mut preparation = initial_preparation
  let needs_mailbox_path = match phase_state {
    Some(@protocol.PreOp) | Some(@protocol.SafeOp) | Some(@protocol.Op) => false
    _ => true
  }
  if needs_mailbox_path {
    let mailbox_write_result : Result[Unit, @hal.EcError] = try? @runtime.write_mailbox_mapping(
      nic,
      station,
      preparation.mapping,
      timeout,
    )
    phases.push(
      capture_startup_trace_phase(nic, station, "after_mailbox_write", timeout),
    )
    match mailbox_write_result {
      Ok(_) => ()
      Err(err) => {
        transition_error = Some("mailbox write failed: " + err.to_string())
        return {
          station,
          source,
          initial_state,
          final_state: phases[phases.length() - 1].al_state,
          phases,
          transition_error,
          pdo_audit: Some(pdo_audit),
        }
      }
    }
    let preop_result : Result[@protocol.EsmState, @hal.EcError] = try? (match
      transition_station_with_startup_mailbox_route_observe(
        nic,
        station,
        @protocol.PreOp,
        preparation,
        timeout,
      ) {
      Some(observed) => observed.state
      None => @protocol.read_al_status_snapshot(nic, station, timeout).state
    })
    phases.push(
      startup_trace_phase_with_od(nic, station, "after_preop_request", timeout),
    )
    match preop_result {
      Ok(value) => phase_state = Some(value)
      Err(err) => {
        transition_error = Some("preop request failed: " + err.to_string())
        return {
          station,
          source,
          initial_state,
          final_state: phases[phases.length() - 1].al_state,
          phases,
          transition_error,
          pdo_audit: Some(pdo_audit),
        }
      }
    }
  }
  preparation = refine_station_startup_preparation_in_preop_if_needed(
    nic, station, phase_state, preparation, timeout,
  )
  let needs_process_path = match phase_state {
    Some(@protocol.SafeOp) | Some(@protocol.Op) => false
    _ => true
  }
  if needs_process_path {
    let presafeop_mailbox_result : Result[Unit, @hal.EcError] = try? @runtime.apply_presafeop_startup_mailbox_commands(
      nic,
      station,
      preparation.mailbox_config,
      preparation.startup_mailbox_commands,
      timeout,
    )
    phases.push(
      startup_trace_phase_with_od(
        nic, station, "after_presafeop_mailbox_commands", timeout,
      ),
    )
    match presafeop_mailbox_result {
      Ok(_) => ()
      Err(err) => {
        transition_error = Some(
          "presafeop mailbox commands failed: " + err.to_string(),
        )
        return {
          station,
          source,
          initial_state,
          final_state: phases[phases.length() - 1].al_state,
          phases,
          transition_error,
          pdo_audit: Some(pdo_audit),
        }
      }
    }
    let process_result : Result[Unit, @hal.EcError] = try? @runtime.write_process_data_mapping(
      nic,
      station,
      preparation.mapping,
      timeout,
    )
    phases.push(
      startup_trace_phase_with_od(
        nic, station, "after_process_mapping_write", timeout,
      ),
    )
    match process_result {
      Ok(_) => ()
      Err(err) => {
        transition_error = Some(
          "process mapping write failed: " + err.to_string(),
        )
        return {
          station,
          source,
          initial_state,
          final_state: phases[phases.length() - 1].al_state,
          phases,
          transition_error,
          pdo_audit: Some(pdo_audit),
        }
      }
    }
    phases.push(
      startup_trace_phase_with_od(
        nic, station, "before_safeop_request", timeout,
      ),
    )
    let safeop_result : Result[@protocol.EsmState, @hal.EcError] = try? transition_station_to_target_strict_after_recovery(
      nic,
      station,
      @protocol.SafeOp,
      timeout,
    )
    phases.push(
      startup_trace_phase_with_od(nic, station, "after_safeop_request", timeout),
    )
    match safeop_result {
      Ok(value) => phase_state = Some(value)
      Err(err) =>
        transition_error = Some("safeop request failed: " + err.to_string())
    }
  }
  {
    station,
    source,
    initial_state,
    final_state: phases[phases.length() - 1].al_state,
    phases,
    transition_error,
    pdo_audit: Some(pdo_audit),
  }
}

///|
fn expected_sync_manager_register_reports(
  mapping : @mailbox.SlaveMapping,
) -> Array[EscSyncManagerRegisterReport] raise @hal.EcError {
  let reports : Array[EscSyncManagerRegisterReport] = []
  for index = 2; index <= 3; index = index + 1 {
    reports.push(expected_sync_manager_register_report(mapping, index))
  }
  reports
}

///|
fn expected_sync_manager_register_report(
  mapping : @mailbox.SlaveMapping,
  index : Int,
) -> EscSyncManagerRegisterReport raise @hal.EcError {
  let register_offset = @protocol.reg_sm_base +
    index.reinterpret_as_uint() * @protocol.sm_entry_size.reinterpret_as_uint()
  let window = if index >= 0 && index < mapping.sm_configs.length() {
    mapping.sm_configs[index].to_bytes()
  } else {
    Bytes::new(@protocol.sm_entry_size)
  }
  decode_esc_sync_manager_window(index, register_offset, window)
}

///|
fn expected_fmmu_register_reports(
  mapping : @mailbox.SlaveMapping,
) -> Array[EscFmmuRegisterReport] raise @hal.EcError {
  let reports : Array[EscFmmuRegisterReport] = []
  for index = 0; index <= 1; index = index + 1 {
    reports.push(expected_fmmu_register_report(mapping, index))
  }
  reports
}

///|
fn expected_fmmu_register_report(
  mapping : @mailbox.SlaveMapping,
  index : Int,
) -> EscFmmuRegisterReport raise @hal.EcError {
  let register_offset = @protocol.reg_fmmu_base +
    index.reinterpret_as_uint() *
    @protocol.fmmu_entry_size.reinterpret_as_uint()
  let window = if index >= 0 && index < mapping.fmmu_configs.length() {
    mapping.fmmu_configs[index].to_bytes()
  } else {
    Bytes::new(@protocol.fmmu_entry_size)
  }
  decode_esc_fmmu_window(index, register_offset, window)
}

///|
fn decode_esc_sync_manager_window(
  index : Int,
  register_offset : UInt,
  window : Bytes,
) -> EscSyncManagerRegisterReport raise @hal.EcError {
  if window.length() < @protocol.sm_entry_size {
    raise @hal.EcError::Internal(
      "short SyncManager register window at 0x" +
      format_hex(register_offset, 4) +
      ": expected " +
      @protocol.sm_entry_size.to_string() +
      " bytes, got " +
      window.length().to_string(),
    )
  }
  {
    index,
    register_offset,
    raw_hex: bytes_hex(window),
    physical_start: decode_u16_le(window, 0),
    length: decode_u16_le(window, 2),
    control: window[4],
    status: window[5],
    activate: window[6],
  }
}

///|
fn decode_esc_fmmu_window(
  index : Int,
  register_offset : UInt,
  window : Bytes,
) -> EscFmmuRegisterReport raise @hal.EcError {
  if window.length() < @protocol.fmmu_entry_size {
    raise @hal.EcError::Internal(
      "short FMMU register window at 0x" +
      format_hex(register_offset, 4) +
      ": expected " +
      @protocol.fmmu_entry_size.to_string() +
      " bytes, got " +
      window.length().to_string(),
    )
  }
  {
    index,
    register_offset,
    raw_hex: bytes_hex(window),
    logical_start: decode_u32_le(window, 0),
    length: decode_u16_le(window, 4),
    logical_start_bit: window[6],
    logical_end_bit: window[7],
    physical_start: decode_u16_le(window, 8),
    physical_start_bit: window[10],
    type_register: window[11],
    activate: window[12],
  }
}

///|
fn esc_register_report_json(report : EscRegisterReport) -> Json {
  Json::object({
    "station": Json::number(report.station.to_double()),
    "al_state": Json::string(report.al_state.to_string()),
    "al_error_flag": Json::boolean(report.al_error_flag),
    "al_status_code": option_uint_json(report.al_status_code),
    "al_status_code_description": match report.al_status_code {
      Some(code) => Json::string(@protocol.al_status_code_description(code))
      None => Json::null()
    },
    "sync_managers": Json::array(
      report.sync_managers.map(fn(sm) {
        Json::object({
          "index": Json::number(sm.index.to_double()),
          "register_offset": Json::number(sm.register_offset.to_double()),
          "raw_hex": Json::string(sm.raw_hex),
          "physical_start": Json::number(sm.physical_start.to_double()),
          "length": Json::number(sm.length.to_double()),
          "control": Json::number(sm.control.to_uint().to_double()),
          "status": Json::number(sm.status.to_uint().to_double()),
          "activate": Json::number(sm.activate.to_uint().to_double()),
          "enabled": Json::boolean((sm.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
    "fmmus": Json::array(
      report.fmmus.map(fn(fmmu) {
        Json::object({
          "index": Json::number(fmmu.index.to_double()),
          "register_offset": Json::number(fmmu.register_offset.to_double()),
          "raw_hex": Json::string(fmmu.raw_hex),
          "logical_start": Json::number(fmmu.logical_start.to_double()),
          "length": Json::number(fmmu.length.to_double()),
          "logical_start_bit": Json::number(
            fmmu.logical_start_bit.to_uint().to_double(),
          ),
          "logical_end_bit": Json::number(
            fmmu.logical_end_bit.to_uint().to_double(),
          ),
          "physical_start": Json::number(fmmu.physical_start.to_double()),
          "physical_start_bit": Json::number(
            fmmu.physical_start_bit.to_uint().to_double(),
          ),
          "type_register": Json::number(
            fmmu.type_register.to_uint().to_double(),
          ),
          "type_description": Json::string(
            esc_fmmu_type_description(fmmu.type_register),
          ),
          "activate": Json::number(fmmu.activate.to_uint().to_double()),
          "enabled": Json::boolean((fmmu.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
  })
}

///|
fn expected_esc_register_report_json(
  report : ExpectedEscRegisterReport,
) -> Json {
  Json::object({
    "station": Json::number(report.station.to_double()),
    "sync_managers": Json::array(
      report.sync_managers.map(fn(sm) {
        Json::object({
          "index": Json::number(sm.index.to_double()),
          "register_offset": Json::number(sm.register_offset.to_double()),
          "raw_hex": Json::string(sm.raw_hex),
          "physical_start": Json::number(sm.physical_start.to_double()),
          "length": Json::number(sm.length.to_double()),
          "control": Json::number(sm.control.to_uint().to_double()),
          "status": Json::number(sm.status.to_uint().to_double()),
          "activate": Json::number(sm.activate.to_uint().to_double()),
          "enabled": Json::boolean((sm.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
    "fmmus": Json::array(
      report.fmmus.map(fn(fmmu) {
        Json::object({
          "index": Json::number(fmmu.index.to_double()),
          "register_offset": Json::number(fmmu.register_offset.to_double()),
          "raw_hex": Json::string(fmmu.raw_hex),
          "logical_start": Json::number(fmmu.logical_start.to_double()),
          "length": Json::number(fmmu.length.to_double()),
          "logical_start_bit": Json::number(
            fmmu.logical_start_bit.to_uint().to_double(),
          ),
          "logical_end_bit": Json::number(
            fmmu.logical_end_bit.to_uint().to_double(),
          ),
          "physical_start": Json::number(fmmu.physical_start.to_double()),
          "physical_start_bit": Json::number(
            fmmu.physical_start_bit.to_uint().to_double(),
          ),
          "type_register": Json::number(
            fmmu.type_register.to_uint().to_double(),
          ),
          "type_description": Json::string(
            esc_fmmu_type_description(fmmu.type_register),
          ),
          "activate": Json::number(fmmu.activate.to_uint().to_double()),
          "enabled": Json::boolean((fmmu.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
  })
}

///|
fn esc_register_report_text(report : EscRegisterReport) -> String {
  let buf = @buffer.new(size_hint=768)
  let al_error_flag_text = if report.al_error_flag { "set" } else { "clear" }
  let al_status_code_text = match report.al_status_code {
    Some(code) =>
      format_hex(code, 4) +
      " (" +
      @protocol.al_status_code_description(code) +
      ")"
    None => "not set"
  }
  buf.write_string("EtherCAT ESC Register Snapshot\n")
  buf.write_string("============================\n")
  buf.write_string("Station: " + report.station.to_string() + "\n")
  buf.write_string("AL State: " + report.al_state.to_string() + "\n")
  buf.write_string("AL Error Flag: " + al_error_flag_text + "\n")
  buf.write_string("AL Status Code: " + al_status_code_text + "\n\n")
  buf.write_string("SyncManagers\n")
  buf.write_string("------------\n")
  for sm in report.sync_managers {
    buf.write_string(
      "SM" +
      sm.index.to_string() +
      " @ " +
      format_hex(sm.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + sm.raw_hex + "\n")
    buf.write_string(
      "  Physical Start: ... " + format_hex(sm.physical_start, 4) + "\n",
    )
    buf.write_string("  Length: ........... " + sm.length.to_string() + "\n")
    buf.write_string(
      "  Control: .......... " + format_hex(sm.control.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Status: ........... " + format_hex(sm.status.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(sm.activate.to_uint(), 2) + "\n",
    )
  }
  buf.write_string("\nFMMU\n")
  buf.write_string("----\n")
  for fmmu in report.fmmus {
    buf.write_string(
      "FMMU" +
      fmmu.index.to_string() +
      " @ " +
      format_hex(fmmu.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + fmmu.raw_hex + "\n")
    buf.write_string(
      "  Logical Start: .... " + format_hex(fmmu.logical_start, 8) + "\n",
    )
    buf.write_string("  Length: ........... " + fmmu.length.to_string() + "\n")
    buf.write_string(
      "  Logical Bits: ..... " +
      fmmu.logical_start_bit.to_uint().to_string() +
      "-" +
      fmmu.logical_end_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Physical Start: ... " + format_hex(fmmu.physical_start, 4) + "\n",
    )
    buf.write_string(
      "  Physical Bit: ..... " +
      fmmu.physical_start_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Type Register: .... " +
      format_hex(fmmu.type_register.to_uint(), 2) +
      " (" +
      esc_fmmu_type_description(fmmu.type_register) +
      ")\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(fmmu.activate.to_uint(), 2) + "\n",
    )
  }
  buf.to_string()
}

///|
fn expected_esc_register_report_text(
  report : ExpectedEscRegisterReport,
) -> String {
  let buf = @buffer.new(size_hint=640)
  buf.write_string("Expected EtherCAT ESC Process Mapping\n")
  buf.write_string("====================================\n")
  buf.write_string("Station: " + report.station.to_string() + "\n\n")
  buf.write_string("SyncManagers\n")
  buf.write_string("------------\n")
  for sm in report.sync_managers {
    buf.write_string(
      "SM" +
      sm.index.to_string() +
      " @ " +
      format_hex(sm.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + sm.raw_hex + "\n")
    buf.write_string(
      "  Physical Start: ... " + format_hex(sm.physical_start, 4) + "\n",
    )
    buf.write_string("  Length: ........... " + sm.length.to_string() + "\n")
    buf.write_string(
      "  Control: .......... " + format_hex(sm.control.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Status: ........... " + format_hex(sm.status.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(sm.activate.to_uint(), 2) + "\n",
    )
  }
  buf.write_string("\nFMMU\n")
  buf.write_string("----\n")
  for fmmu in report.fmmus {
    buf.write_string(
      "FMMU" +
      fmmu.index.to_string() +
      " @ " +
      format_hex(fmmu.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + fmmu.raw_hex + "\n")
    buf.write_string(
      "  Logical Start: .... " + format_hex(fmmu.logical_start, 8) + "\n",
    )
    buf.write_string("  Length: ........... " + fmmu.length.to_string() + "\n")
    buf.write_string(
      "  Logical Bits: ..... " +
      fmmu.logical_start_bit.to_uint().to_string() +
      ".." +
      fmmu.logical_end_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Physical Start: ... " + format_hex(fmmu.physical_start, 4) + "\n",
    )
    buf.write_string(
      "  Physical Bit: ..... " +
      fmmu.physical_start_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Type: ............. " +
      format_hex(fmmu.type_register.to_uint(), 2) +
      " (" +
      esc_fmmu_type_description(fmmu.type_register) +
      ")\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(fmmu.activate.to_uint(), 2) + "\n",
    )
  }
  buf.to_string()
}

///|
fn startup_mailbox_command_json(
  command : @runtime.StartupMailboxCommand,
) -> Json {
  Json::object({
    "transition": Json::string(command.transition.to_string()),
    "index": Json::number(command.index.to_double()),
    "subindex": Json::number(command.subindex.to_uint().to_double()),
    "data_hex": Json::string(bytes_hex(command.data)),
  })
}

///|
fn mailbox_readback_entry_json(entry : MailboxReadbackEntry) -> Json {
  Json::object({
    "index": Json::number(entry.index.to_double()),
    "register_offset": Json::number(entry.register_offset.to_double()),
    "expected": Json::object({
      "index": Json::number(entry.expected.index.to_double()),
      "register_offset": Json::number(
        entry.expected.register_offset.to_double(),
      ),
      "raw_hex": Json::string(entry.expected.raw_hex),
      "physical_start": Json::number(entry.expected.physical_start.to_double()),
      "length": Json::number(entry.expected.length.to_double()),
      "control": Json::number(entry.expected.control.to_uint().to_double()),
      "status": Json::number(entry.expected.status.to_uint().to_double()),
      "activate": Json::number(entry.expected.activate.to_uint().to_double()),
      "enabled": Json::boolean((entry.expected.activate & b'\x01') != b'\x00'),
    }),
    "actual": Json::object({
      "index": Json::number(entry.actual.index.to_double()),
      "register_offset": Json::number(entry.actual.register_offset.to_double()),
      "raw_hex": Json::string(entry.actual.raw_hex),
      "physical_start": Json::number(entry.actual.physical_start.to_double()),
      "length": Json::number(entry.actual.length.to_double()),
      "control": Json::number(entry.actual.control.to_uint().to_double()),
      "status": Json::number(entry.actual.status.to_uint().to_double()),
      "activate": Json::number(entry.actual.activate.to_uint().to_double()),
      "enabled": Json::boolean((entry.actual.activate & b'\x01') != b'\x00'),
    }),
    "matches": Json::boolean(entry.matches),
  })
}

///|
fn mailbox_readback_report_json(report : MailboxReadbackReport) -> Json {
  Json::object({
    "station": Json::number(report.station.to_double()),
    "source": Json::string(report.source),
    "entries": Json::array(report.entries.map(mailbox_readback_entry_json)),
    "mismatches": Json::array(report.mismatches.map(item => Json::string(item))),
  })
}

///|
fn pdo_mapping_entry_json(entry : UInt) -> Json {
  Json::object({
    "raw": Json::number(entry.to_double()),
    "raw_hex": Json::string(format_hex(entry, 8)),
    "summary": Json::string(pdo_mapping_entry_summary(entry)),
  })
}

///|
fn pdo_mapping_object_report_json(object : PdoMappingObjectReport) -> Json {
  Json::object({
    "index": Json::number(object.index.to_double()),
    "index_hex": Json::string(format_hex(object.index, 4)),
    "entries": Json::array(object.entries.map(pdo_mapping_entry_json)),
  })
}

///|
fn pdo_direction_report_json(direction : PdoDirectionReport) -> Json {
  Json::object({
    "assignment_index": Json::number(direction.assignment_index.to_double()),
    "assignment_index_hex": Json::string(
      format_hex(direction.assignment_index, 4),
    ),
    "assigned_pdos": Json::array(
      direction.assigned_pdos.map(fn(index) {
        Json::object({
          "index": Json::number(index.to_double()),
          "index_hex": Json::string(format_hex(index, 4)),
        })
      }),
    ),
    "objects": Json::array(
      direction.objects.map(pdo_mapping_object_report_json),
    ),
  })
}

///|
fn pdo_audit_report_json(report : PdoAuditReport) -> Json {
  Json::object({
    "plan_source": Json::string(report.plan_source),
    "policy": Json::string(report.policy),
    "effective_source": Json::string(report.effective_source),
    "live_detected": option_bool_json(report.live_detected),
    "live_differs_from_plan": option_bool_json(report.live_differs_from_plan),
    "live_read_error": option_string_json(report.live_read_error),
    "configured_rx": pdo_direction_report_json(report.configured_rx),
    "configured_tx": pdo_direction_report_json(report.configured_tx),
    "live_rx": match report.live_rx {
      Some(value) => pdo_direction_report_json(value)
      None => Json::null()
    },
    "live_tx": match report.live_tx {
      Some(value) => pdo_direction_report_json(value)
      None => Json::null()
    },
    "mismatches": Json::array(report.mismatches.map(item => Json::string(item))),
  })
}

///|
fn startup_trace_phase_json(phase : StartupTracePhase) -> Json {
  Json::object({
    "name": Json::string(phase.name),
    "al_state": option_esm_state_json(phase.al_state),
    "al_error_flag": option_bool_json(phase.al_error_flag),
    "al_status_code": option_uint_json(phase.al_status_code),
    "al_status_code_description": match phase.al_status_code {
      Some(code) => Json::string(@protocol.al_status_code_description(code))
      None => Json::null()
    },
    "sync_managers": Json::array(
      phase.sync_managers.map(fn(sm) {
        Json::object({
          "index": Json::number(sm.index.to_double()),
          "register_offset": Json::number(sm.register_offset.to_double()),
          "raw_hex": Json::string(sm.raw_hex),
          "physical_start": Json::number(sm.physical_start.to_double()),
          "length": Json::number(sm.length.to_double()),
          "control": Json::number(sm.control.to_uint().to_double()),
          "status": Json::number(sm.status.to_uint().to_double()),
          "activate": Json::number(sm.activate.to_uint().to_double()),
          "enabled": Json::boolean((sm.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
    "fmmus": Json::array(
      phase.fmmus.map(fn(fmmu) {
        Json::object({
          "index": Json::number(fmmu.index.to_double()),
          "register_offset": Json::number(fmmu.register_offset.to_double()),
          "raw_hex": Json::string(fmmu.raw_hex),
          "logical_start": Json::number(fmmu.logical_start.to_double()),
          "length": Json::number(fmmu.length.to_double()),
          "logical_start_bit": Json::number(
            fmmu.logical_start_bit.to_uint().to_double(),
          ),
          "logical_end_bit": Json::number(
            fmmu.logical_end_bit.to_uint().to_double(),
          ),
          "physical_start": Json::number(fmmu.physical_start.to_double()),
          "physical_start_bit": Json::number(
            fmmu.physical_start_bit.to_uint().to_double(),
          ),
          "type_register": Json::number(
            fmmu.type_register.to_uint().to_double(),
          ),
          "activate": Json::number(fmmu.activate.to_uint().to_double()),
          "enabled": Json::boolean((fmmu.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
    "od_objects": Json::array(
      phase.od_objects.map(fn(obj) {
        Json::object({
          "index": Json::number(obj.index.to_double()),
          "subindex_count": option_uint_json(obj.subindex_count),
          "entries": Json::array(
            obj.entries.map(fn(entry) {
              Json::object({
                "subindex": Json::number(entry.subindex.to_uint().to_double()),
                "value_hex": option_string_json(entry.value_hex),
                "value_u32": option_uint_json(entry.value_u32),
                "error_detail": option_string_json(entry.error_detail),
                "abort_code": option_uint_json(entry.abort_code),
                "abort_code_description": match entry.abort_code {
                  Some(code) =>
                    Json::string(@mailbox.sdo_abort_code_description(code))
                  None => Json::null()
                },
              })
            }),
          ),
          "error_detail": option_string_json(obj.error_detail),
          "abort_code": option_uint_json(obj.abort_code),
          "abort_code_description": match obj.abort_code {
            Some(code) =>
              Json::string(@mailbox.sdo_abort_code_description(code))
            None => Json::null()
          },
        })
      }),
    ),
    "notes": Json::array(phase.notes.map(item => Json::string(item))),
  })
}

///|
fn startup_trace_report_json(report : StartupTraceReport) -> Json {
  Json::object({
    "station": Json::number(report.station.to_double()),
    "source": Json::string(report.source),
    "initial_state": option_esm_state_json(report.initial_state),
    "final_state": option_esm_state_json(report.final_state),
    "transition_error": option_string_json(report.transition_error),
    "pdo_audit": match report.pdo_audit {
      Some(value) => pdo_audit_report_json(value)
      None => Json::null()
    },
    "phases": Json::array(report.phases.map(startup_trace_phase_json)),
  })
}

///|
fn startup_diff_report_json(report : StartupDiffReport) -> Json {
  let online_expected_json = match report.online_expected {
    Some(value) => expected_esc_register_report_json(value)
    None => Json::null()
  }
  let actual_esc_json = match report.actual_esc {
    Some(value) => esc_register_report_json(value)
    None => Json::null()
  }
  Json::object({
    "station": Json::number(report.station.to_double()),
    "offline_expected": expected_esc_register_report_json(
      report.offline_expected,
    ),
    "online_expected": online_expected_json,
    "online_expected_error": option_string_json(report.online_expected_error),
    "actual_esc": actual_esc_json,
    "actual_esc_error": option_string_json(report.actual_esc_error),
    "offline_mailbox_commands": Json::array(
      report.offline_mailbox_commands.map(startup_mailbox_command_json),
    ),
    "online_mailbox_commands": Json::array(
      report.online_mailbox_commands.map(startup_mailbox_command_json),
    ),
    "differences": Json::array(
      report.differences.map(item => Json::string(item)),
    ),
  })
}

///|
fn startup_diff_report_text(report : StartupDiffReport) -> String {
  let buf = @buffer.new(size_hint=2048)
  let online_error_text = match report.online_expected_error {
    Some(err) => err
    None => "unknown error"
  }
  let actual_error_text = match report.actual_esc_error {
    Some(err) => err
    None => "unknown error"
  }
  buf.write_string("Startup Plan Diff\n")
  buf.write_string("=================\n")
  buf.write_string("Station: " + report.station.to_string() + "\n\n")
  buf.write_string("Offline Mailbox Commands\n")
  buf.write_string("------------------------\n")
  for command in report.offline_mailbox_commands {
    buf.write_string(startup_mailbox_command_text(command) + "\n")
  }
  buf.write_string("\nOnline Mailbox Commands\n")
  buf.write_string("-----------------------\n")
  for command in report.online_mailbox_commands {
    buf.write_string(startup_mailbox_command_text(command) + "\n")
  }
  buf.write_string("\nOffline Expected Registers\n")
  buf.write_string("--------------------------\n")
  buf.write_string(expected_esc_register_report_text(report.offline_expected))
  buf.write_string("\n\nOnline Expected Registers\n")
  buf.write_string("-------------------------\n")
  match report.online_expected {
    Some(value) => buf.write_string(expected_esc_register_report_text(value))
    None => buf.write_string("Unavailable: " + online_error_text + "\n")
  }
  buf.write_string("\n\nActual ESC Registers\n")
  buf.write_string("--------------------\n")
  match report.actual_esc {
    Some(value) => buf.write_string(esc_register_report_text(value))
    None => buf.write_string("Unavailable: " + actual_error_text + "\n")
  }
  buf.write_string("\n\nDifferences\n")
  buf.write_string("-----------\n")
  if report.differences.is_empty() {
    buf.write_string("No differences\n")
  } else {
    for item in report.differences {
      buf.write_string("- " + item + "\n")
    }
  }
  buf.to_string()
}

///|
fn mailbox_readback_report_text(report : MailboxReadbackReport) -> String {
  let buf = @buffer.new(size_hint=1024)
  buf.write_string("Mailbox SyncManager Readback\n")
  buf.write_string("==========================\n")
  buf.write_string("Station: " + report.station.to_string() + "\n")
  buf.write_string("Source: " + report.source + "\n\n")
  for entry in report.entries {
    buf.write_string(
      "SM" +
      entry.index.to_string() +
      " @ " +
      format_hex(entry.register_offset, 4) +
      "\n",
    )
    buf.write_string(
      "  Match: ............ " + entry.matches.to_string() + "\n",
    )
    buf.write_string("  Expected Raw: ..... " + entry.expected.raw_hex + "\n")
    buf.write_string("  Actual Raw: ....... " + entry.actual.raw_hex + "\n")
    buf.write_string(
      "  Expected Start: ... " +
      format_hex(entry.expected.physical_start, 4) +
      "\n",
    )
    buf.write_string(
      "  Actual Start: ..... " +
      format_hex(entry.actual.physical_start, 4) +
      "\n",
    )
    buf.write_string(
      "  Expected Length: .. " + entry.expected.length.to_string() + "\n",
    )
    buf.write_string(
      "  Actual Length: .... " + entry.actual.length.to_string() + "\n",
    )
    buf.write_string(
      "  Expected Control: . " +
      format_hex(entry.expected.control.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Actual Control: ... " +
      format_hex(entry.actual.control.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Expected Status: .. " +
      format_hex(entry.expected.status.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Actual Status: .... " +
      format_hex(entry.actual.status.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Expected Activate:  " +
      format_hex(entry.expected.activate.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Actual Activate: .. " +
      format_hex(entry.actual.activate.to_uint(), 2) +
      "\n\n",
    )
  }
  buf.write_string("Mismatches\n")
  buf.write_string("----------\n")
  if report.mismatches.is_empty() {
    buf.write_string("No mismatches\n")
  } else {
    for item in report.mismatches {
      buf.write_string("- " + item + "\n")
    }
  }
  buf.to_string()
}

///|
fn startup_trace_report_text(report : StartupTraceReport) -> String {
  let buf = @buffer.new(size_hint=2048)
  let initial_state_text = match report.initial_state {
    Some(value) => value.to_string()
    None => "unknown"
  }
  let final_state_text = match report.final_state {
    Some(value) => value.to_string()
    None => "unknown"
  }
  buf.write_string("Startup Trace\n")
  buf.write_string("=============\n")
  buf.write_string("Station: " + report.station.to_string() + "\n")
  buf.write_string("Source: " + report.source + "\n")
  buf.write_string("Initial State: " + initial_state_text + "\n")
  buf.write_string("Final State: " + final_state_text + "\n")
  match report.transition_error {
    Some(err) => buf.write_string("Transition Error: " + err + "\n\n")
    None => buf.write_string("Transition Error: none\n\n")
  }
  match report.pdo_audit {
    Some(value) => {
      buf.write_string(pdo_audit_report_text(value))
      buf.write_string("\n")
    }
    None => ()
  }
  for phase in report.phases {
    let phase_state = match phase.al_state {
      Some(value) => value.to_string()
      None => "unknown"
    }
    let phase_error = match phase.al_error_flag {
      Some(value) => value.to_string()
      None => "unknown"
    }
    let phase_status = match phase.al_status_code {
      Some(value) =>
        format_hex(value, 4) +
        " (" +
        @protocol.al_status_code_description(value) +
        ")"
      None => "not set"
    }
    buf.write_string(phase.name + "\n")
    buf.write_string(trace_separator(phase.name.length()) + "\n")
    buf.write_string("AL State: " + phase_state + "\n")
    buf.write_string("AL Error Flag: " + phase_error + "\n")
    buf.write_string("AL Status Code: " + phase_status + "\n")
    for sm in phase.sync_managers {
      buf.write_string(
        "SM" +
        sm.index.to_string() +
        " @ " +
        format_hex(sm.register_offset, 4) +
        ": " +
        sm.raw_hex +
        "\n",
      )
    }
    for fmmu in phase.fmmus {
      buf.write_string(
        "FMMU" +
        fmmu.index.to_string() +
        " @ " +
        format_hex(fmmu.register_offset, 4) +
        ": " +
        fmmu.raw_hex +
        "\n",
      )
    }
    for obj in phase.od_objects {
      let count_text = match obj.subindex_count {
        Some(value) => value.to_string()
        None => "unknown"
      }
      buf.write_string(
        "OD " +
        format_hex(obj.index, 4) +
        " subindex_count=" +
        count_text +
        "\n",
      )
      match obj.error_detail {
        Some(detail) => buf.write_string("  object error: " + detail + "\n")
        None => ()
      }
      for entry in obj.entries {
        let entry_hex = match entry.value_hex {
          Some(value) => value
          None => "n/a"
        }
        buf.write_string(
          "  sub " + entry.subindex.to_uint().to_string() + ": " + entry_hex,
        )
        match entry.value_u32 {
          Some(value) => buf.write_string(" (u32=" + value.to_string() + ")")
          None => ()
        }
        match entry.error_detail {
          Some(detail) => buf.write_string(" error=" + detail)
          None => ()
        }
        buf.write_string("\n")
      }
    }
    for note in phase.notes {
      buf.write_string("note: " + note + "\n")
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
fn startup_mailbox_command_text(
  command : @runtime.StartupMailboxCommand,
) -> String {
  command.transition.to_string() +
  " 0x" +
  format_hex(command.index, 4) +
  ":" +
  command.subindex.to_uint().to_string() +
  " = " +
  bytes_hex(command.data)
}

///|
fn startup_diff_messages(
  offline_expected : ExpectedEscRegisterReport,
  online_expected : ExpectedEscRegisterReport?,
  online_expected_error : String?,
  actual_esc : EscRegisterReport?,
  actual_esc_error : String?,
  offline_mailbox_commands : Array[@runtime.StartupMailboxCommand],
  online_mailbox_commands : Array[@runtime.StartupMailboxCommand],
) -> Array[String] {
  let differences : Array[String] = []
  let online_error_text = match online_expected_error {
    Some(err) => err
    None => "unknown error"
  }
  let actual_error_text = match actual_esc_error {
    Some(err) => err
    None => "unknown error"
  }
  match actual_esc {
    Some(actual) =>
      match online_expected {
        Some(value) => {
          append_startup_mailbox_differences(
            differences, "offline", offline_mailbox_commands, "online", online_mailbox_commands,
          )
          append_sm_differences(
            differences,
            "offline",
            offline_expected.sync_managers,
            "online",
            value.sync_managers,
          )
          append_sm_differences(
            differences,
            "online",
            value.sync_managers,
            "actual",
            actual.sync_managers,
          )
          append_fmmu_differences(
            differences,
            "offline",
            offline_expected.fmmus,
            "online",
            value.fmmus,
          )
          append_fmmu_differences(
            differences,
            "online",
            value.fmmus,
            "actual",
            actual.fmmus,
          )
        }
        None => {
          differences.push("online expected unavailable: " + online_error_text)
          append_sm_differences(
            differences,
            "offline",
            offline_expected.sync_managers,
            "actual",
            actual.sync_managers,
          )
          append_fmmu_differences(
            differences,
            "offline",
            offline_expected.fmmus,
            "actual",
            actual.fmmus,
          )
        }
      }
    None => {
      differences.push("actual esc unavailable: " + actual_error_text)
      match online_expected {
        Some(value) => {
          append_startup_mailbox_differences(
            differences, "offline", offline_mailbox_commands, "online", online_mailbox_commands,
          )
          append_sm_differences(
            differences,
            "offline",
            offline_expected.sync_managers,
            "online",
            value.sync_managers,
          )
          append_fmmu_differences(
            differences,
            "offline",
            offline_expected.fmmus,
            "online",
            value.fmmus,
          )
        }
        None =>
          differences.push("online expected unavailable: " + online_error_text)
      }
    }
  }
  differences
}

///|
fn append_startup_mailbox_differences(
  differences : Array[String],
  left_name : String,
  left : Array[@runtime.StartupMailboxCommand],
  right_name : String,
  right : Array[@runtime.StartupMailboxCommand],
) -> Unit {
  if left.length() != right.length() {
    differences.push(
      left_name +
      " mailbox command count=" +
      left.length().to_string() +
      ", " +
      right_name +
      "=" +
      right.length().to_string(),
    )
  }
  let limit = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i = 0; i < limit; i = i + 1 {
    if left[i] != right[i] {
      differences.push(
        left_name +
        " mailbox[" +
        i.to_string() +
        "]=" +
        startup_mailbox_command_text(left[i]) +
        ", " +
        right_name +
        "=" +
        startup_mailbox_command_text(right[i]),
      )
    }
  }
}

///|
fn append_sm_differences(
  differences : Array[String],
  left_name : String,
  left : Array[EscSyncManagerRegisterReport],
  right_name : String,
  right : Array[EscSyncManagerRegisterReport],
) -> Unit {
  let limit = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  if left.length() != right.length() {
    differences.push(
      left_name +
      " sync manager count=" +
      left.length().to_string() +
      ", " +
      right_name +
      "=" +
      right.length().to_string(),
    )
  }
  for i = 0; i < limit; i = i + 1 {
    if left[i].raw_hex != right[i].raw_hex {
      differences.push(
        left_name +
        " SM" +
        left[i].index.to_string() +
        " raw=" +
        left[i].raw_hex +
        ", " +
        right_name +
        " raw=" +
        right[i].raw_hex,
      )
    }
  }
}

///|
fn append_fmmu_differences(
  differences : Array[String],
  left_name : String,
  left : Array[EscFmmuRegisterReport],
  right_name : String,
  right : Array[EscFmmuRegisterReport],
) -> Unit {
  let limit = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  if left.length() != right.length() {
    differences.push(
      left_name +
      " FMMU count=" +
      left.length().to_string() +
      ", " +
      right_name +
      "=" +
      right.length().to_string(),
    )
  }
  for i = 0; i < limit; i = i + 1 {
    if left[i].raw_hex != right[i].raw_hex {
      differences.push(
        left_name +
        " FMMU" +
        left[i].index.to_string() +
        " raw=" +
        left[i].raw_hex +
        ", " +
        right_name +
        " raw=" +
        right[i].raw_hex,
      )
    }
  }
}

///|
fn general_json(info : @mailbox.SiiGeneral, strings : Array[String]) -> Json {
  Json::object({
    "group_idx": Json::number(info.group_idx.to_uint().to_double()),
    "group_name": Json::string(resolved_sii_string(strings, info.group_idx)),
    "image_idx": Json::number(info.image_idx.to_uint().to_double()),
    "image_name": Json::string(resolved_sii_string(strings, info.image_idx)),
    "order_idx": Json::number(info.order_idx.to_uint().to_double()),
    "order_name": Json::string(resolved_sii_string(strings, info.order_idx)),
    "name_idx": Json::number(info.name_idx.to_uint().to_double()),
    "name": Json::string(resolved_sii_string(strings, info.name_idx)),
    "coe_details": Json::object({
      "raw": Json::number(info.coe_details.to_uint().to_double()),
      "enable_sdo": Json::boolean(info.supports_coe_sdo()),
      "enable_sdo_info": Json::boolean(info.supports_coe_sdo_info()),
      "enable_pdo_assign": Json::boolean(info.supports_coe_pdo_assign()),
      "enable_pdo_configuration": Json::boolean(
        info.supports_coe_pdo_configuration(),
      ),
      "enable_upload_at_startup": Json::boolean(
        info.supports_coe_upload_at_startup(),
      ),
      "enable_sdo_complete_access": Json::boolean(
        info.supports_coe_complete_access(),
      ),
    }),
    "foe_supported": Json::boolean(info.foe_supported),
    "eoe_supported": Json::boolean(info.eoe_supported),
    "soe_supported": Json::boolean(info.soe_supported),
    "soe_channels": Json::number(info.soe_channels.to_uint().to_double()),
    "ds402_channels": Json::number(info.ds402_channels.to_uint().to_double()),
    "sysman_class": Json::number(info.sysman_class.to_uint().to_double()),
    "flags": Json::object({
      "raw": Json::number(info.flags.to_uint().to_double()),
      "safe_op": Json::boolean(info.is_op_only()),
      "not_lrw": Json::boolean(info.prefers_not_lrw()),
      "mailbox_data_link_layer": Json::boolean(
        info.supports_mailbox_data_link_layer(),
      ),
      "ident_al_status": Json::boolean(info.supports_identification_ado()),
      "ident_physical_memory": Json::boolean(
        info.supports_identification_physical_memory(),
      ),
    }),
    "current_on_ebus": Json::number(info.current_on_ebus.to_double()),
    "physical_ports": Json::array([
      Json::string(physical_port_name(info.physical_port_0)),
      Json::string(physical_port_name(info.physical_port_1)),
      Json::string(physical_port_name(info.physical_port_2)),
      Json::string(physical_port_name(info.physical_port_3)),
    ]),
    "physical_memory_address": Json::number(
      info.physical_memory_address.to_double(),
    ),
  })
}

///|
fn pdo_json(pdo : @mailbox.SiiPdo, strings : Array[String]) -> Json {
  let entries_json = pdo.entries.map(fn(entry) {
    Json::object({
      "entry_index": Json::number(entry.entry_index.to_double()),
      "subindex": Json::number(entry.subindex.to_uint().to_double()),
      "name_idx": Json::number(entry.name_idx.to_uint().to_double()),
      "name": Json::string(resolved_sii_string(strings, entry.name_idx)),
      "data_type": Json::number(entry.data_type.to_uint().to_double()),
      "bit_length": Json::number(entry.bit_length.to_uint().to_double()),
      "flags": Json::number(entry.flags.to_double()),
    })
  })
  Json::object({
    "pdo_index": Json::number(pdo.pdo_index.to_double()),
    "entry_count": Json::number(pdo.entry_count.to_uint().to_double()),
    "sync_manager": Json::number(pdo.sync_manager.to_uint().to_double()),
    "synchronization": Json::number(pdo.synchronization.to_uint().to_double()),
    "name_idx": Json::number(pdo.name_idx.to_uint().to_double()),
    "name": Json::string(resolved_sii_string(strings, pdo.name_idx)),
    "flags": Json::number(pdo.flags.to_double()),
    "entries": Json::array(entries_json),
  })
}

///|
fn read_sii_json(
  position : UInt,
  word_count : Int,
  sii : @mailbox.SiiFullInfo,
) -> Json {
  let preamble = sii.preamble
  let standard = sii.standard
  let header = sii.header
  let general = sii.general
  let strings = sii.strings
  let fmmu = sii.fmmu
  let sync_managers = sii.sync_managers
  let dc_clocks = sii.dc_clocks
  let tx_pdo = sii.tx_pdo
  let rx_pdo = sii.rx_pdo
  let categories = sii.categories
  let categories_json = categories.map(fn(entry) {
    let category_class = entry.category_class().label()
    let (overlay_key, overlay_status, overlay_decoder) = match
      entry.overlay_candidate() {
      Some(candidate) =>
        (
          Json::string(candidate.dispatch_key()),
          Json::string(candidate.status_label()),
          match candidate.decoder_name() {
            Some(name) => Json::string(name)
            None => Json::null()
          },
        )
      None => (Json::null(), Json::null(), Json::null())
    }
    Json::object({
      "category": Json::string(entry.category.to_string()),
      "title": Json::string(sii_category_title(entry.category, entry.type_code)),
      "category_code": Json::number(entry.type_code.to_double()),
      "category_class": Json::string(category_class),
      "overlay_key": overlay_key,
      "overlay_status": overlay_status,
      "overlay_decoder": overlay_decoder,
      "known": Json::boolean(entry.category != @mailbox.Raw),
      "byte_length": Json::number(entry.data.length().to_double()),
      "preview_hex": Json::string(bytes_preview_hex(entry.data, 16)),
    })
  })
  let strings_json = strings.map(fn(text) { Json::string(text) })
  let general_json = match general {
    Some(info) => general_json(info, strings)
    None => Json::null()
  }
  let fmmu_json = fmmu.map(fn(direction) {
    Json::object({
      "usage": Json::string(direction.to_string()),
      "description": Json::string(fmmu_usage_name(direction)),
    })
  })
  let fmmu_ex_json = sii.fmmu_ex.map(fn(entry) {
    Json::object({
      "op_only": Json::boolean(entry.op_only),
      "sm_defined": Json::boolean(entry.sm_defined),
      "su_defined": Json::boolean(entry.su_defined),
      "sync_manager": Json::number(entry.sync_manager.to_uint().to_double()),
      "sync_unit": Json::number(entry.sync_unit.to_uint().to_double()),
    })
  })
  let sm_json = sync_managers.map(fn(sm) {
    Json::object({
      "physical_start": Json::number(sm.physical_start.to_double()),
      "length": Json::number(sm.length.to_double()),
      "control": Json::number(sm.control.to_uint().to_double()),
      "status": Json::number(sm.status.to_uint().to_double()),
      "activate": Json::number(sm.activate.to_uint().to_double()),
      "sm_type": Json::string(sm.sm_type.to_string()),
    })
  })
  let sync_units_json = sii.sync_units.map(fn(entry) {
    Json::object({
      "separate_su": Json::boolean(entry.separate_su),
      "separate_frame": Json::boolean(entry.separate_frame),
      "depend_on_input_state": Json::boolean(entry.depend_on_input_state),
      "frame_repeat_support": Json::boolean(entry.frame_repeat_support),
      "raw_flags": Json::number(entry.raw_flags.to_uint().to_double()),
    })
  })
  let dc_json = dc_clocks.map(fn(dc) {
    Json::object({
      "cycle_time_0": Json::number(dc.cycle_time_0.to_double()),
      "shift_time_0": Json::number(dc.shift_time_0.to_double()),
      "shift_time_1": Json::number(dc.shift_time_1.to_double()),
      "sync1_cycle_factor": Json::number(dc.sync1_cycle_factor.to_double()),
      "assign_activate": Json::number(dc.assign_activate.to_double()),
      "sync0_cycle_factor": Json::number(dc.sync0_cycle_factor.to_double()),
      "name_idx": Json::number(dc.name_idx.to_uint().to_double()),
      "name": Json::string(resolved_sii_string(strings, dc.name_idx)),
      "description_idx": Json::number(dc.description_idx.to_uint().to_double()),
      "description": Json::string(
        resolved_sii_string(strings, dc.description_idx),
      ),
    })
  })
  let tx_pdo_json = tx_pdo.map(fn(pdo) { pdo_json(pdo, strings) })
  let rx_pdo_json = rx_pdo.map(fn(pdo) { pdo_json(pdo, strings) })
  let timeouts_json = match sii.timeouts {
    Some(value) =>
      Json::object({
        "preop_timeout_ms": Json::number(value.preop_timeout_ms.to_double()),
        "safeop_op_timeout_ms": Json::number(
          value.safeop_op_timeout_ms.to_double(),
        ),
        "back_to_init_timeout_ms": Json::number(
          value.back_to_init_timeout_ms.to_double(),
        ),
        "back_to_safeop_timeout_ms": Json::number(
          value.back_to_safeop_timeout_ms.to_double(),
        ),
        "mailbox_request_timeout_ms": Json::number(
          value.mailbox_request_timeout_ms.to_double(),
        ),
        "mailbox_response_timeout_ms": Json::number(
          value.mailbox_response_timeout_ms.to_double(),
        ),
      })
    None => Json::null()
  }
  Json::object({
    "position": Json::number(position.to_double()),
    "word_count": Json::number(word_count.to_double()),
    "preamble": Json::object({
      "pdi_control": Json::number(preamble.pdi_control.to_double()),
      "pdi_config": Json::number(preamble.pdi_config.to_double()),
      "sync_impulse_length_raw": Json::number(
        preamble.sync_impulse_length_raw.to_double(),
      ),
      "sync_impulse_length_ns": Json::number(
        preamble.sync_impulse_length_ns().to_double(),
      ),
      "pdi_config2": Json::number(preamble.pdi_config2.to_double()),
      "configured_station_alias": Json::number(
        preamble.configured_station_alias.to_double(),
      ),
      "checksum": Json::number(preamble.checksum.to_double()),
      "checksum_ok": Json::boolean(preamble.checksum_ok),
    }),
    "header": Json::object({
      "vendor_id": Json::number(header.vendor_id.to_double()),
      "product_code": Json::number(header.product_code.to_double()),
      "revision": Json::number(header.revision.to_double()),
      "serial": Json::number(header.serial.to_double()),
      "bootstrap_rx_offset": Json::number(
        header.bootstrap_rx_offset.to_double(),
      ),
      "bootstrap_rx_size": Json::number(header.bootstrap_rx_size.to_double()),
      "bootstrap_tx_offset": Json::number(
        header.bootstrap_tx_offset.to_double(),
      ),
      "bootstrap_tx_size": Json::number(header.bootstrap_tx_size.to_double()),
      "mailbox_rx_offset": Json::number(header.mailbox_rx_offset.to_double()),
      "mailbox_rx_size": Json::number(header.mailbox_rx_size.to_double()),
      "mailbox_tx_offset": Json::number(header.mailbox_tx_offset.to_double()),
      "mailbox_tx_size": Json::number(header.mailbox_tx_size.to_double()),
      "mailbox_protocols": Json::number(header.mailbox_protocols.to_double()),
      "firmware_version": Json::number(header.firmware_version.to_double()),
      "hardware_version": Json::number(header.hardware_version.to_double()),
      "production_date_raw": Json::number(
        header.production_date_raw.to_double(),
      ),
      "production_year": Json::number(header.production_year().to_double()),
      "production_weekday": Json::number(
        header.production_weekday().to_double(),
      ),
      "production_week": Json::number(header.production_week().to_double()),
      "esc_config_b_present": Json::boolean(header.esc_config_b_present),
      "pdi_control_1": Json::number(header.pdi_control_1.to_uint().to_double()),
      "esc_config_b0": Json::number(header.esc_config_b0.to_uint().to_double()),
      "pdi_config_1": Json::number(header.pdi_config_1.to_double()),
      "pdi_config_1_ext": Json::number(header.pdi_config_1_ext.to_double()),
      "esc_config_b4": Json::number(header.esc_config_b4.to_double()),
      "esc_config_b5": Json::number(header.esc_config_b5.to_double()),
      "esc_config_b6": Json::number(header.esc_config_b6.to_double()),
      "checksum_b": Json::number(header.checksum_b.to_double()),
    }),
    "supported_mailboxes": Json::object({
      "aoe": Json::boolean(header.supports_aoe()),
      "coe": Json::boolean(header.supports_coe()),
      "eoe": Json::boolean(header.supports_eoe()),
      "foe": Json::boolean(header.supports_foe()),
      "soe": Json::boolean(header.supports_soe()),
      "voe": Json::boolean(header.supports_voe()),
    }),
    "standard_metadata": Json::object({
      "eeprom_size_raw": Json::number(standard.eeprom_size_raw.to_double()),
      "eeprom_size_bytes": Json::number(
        standard.eeprom_size_bytes().to_double(),
      ),
      "version": Json::number(standard.version.to_double()),
    }),
    "general": general_json,
    "strings": Json::array(strings_json),
    "fmmu": Json::array(fmmu_json),
    "fmmu_ex": Json::array(fmmu_ex_json),
    "sync_managers": Json::array(sm_json),
    "sync_units": Json::array(sync_units_json),
    "dc_clocks": Json::array(dc_json),
    "timeouts": timeouts_json,
    "tx_pdo": Json::array(tx_pdo_json),
    "rx_pdo": Json::array(rx_pdo_json),
    "categories": Json::array(categories_json),
  })
}

///|
fn sii_category_title(
  category : @mailbox.SiiCategory,
  type_code : UInt,
) -> String {
  match category {
    Strings => "Strings"
    DataTypes => "DataTypes"
    General => "General"
    Fmmu => "FMMU"
    SyncManager => "SyncManager"
    FmmuEx => "FMMU_EX"
    SyncUnit => "SyncUnit"
    TxPdo => "TX PDO"
    RxPdo => "RX PDO"
    Dc => "DC CLOCK"
    Timeouts => "Timeouts"
    Dictionary => "Dictionary"
    Hardware => "Hardware"
    VendorInformation => "Vendor Information"
    Images => "Images"
    Raw => "Raw Category " + format_hex(type_code, 4)
  }
}

///|
fn append_sii_strings_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string(
    "  Size: " +
    entry.data.length().to_string() +
    " Bytes with " +
    strings.length().to_string() +
    " strings\n",
  )
  buf.write_string("  ID   Size (Bytes)    String\n")
  for i = 0; i < strings.length(); i = i + 1 {
    let text = strings[i]
    buf.write_string(
      "  " +
      (i + 1).to_string() +
      ": (" +
      text.length().to_string() +
      ") ......... '" +
      text +
      "'\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_general_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  info : @mailbox.SiiGeneral,
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Vendor Specific (Index of String)\n")
  buf.write_string(
    "    Name  Index: " +
    info.name_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.name_idx) +
    "\n",
  )
  buf.write_string(
    "    Group Index: " +
    info.group_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.group_idx) +
    "\n",
  )
  buf.write_string(
    "    Image Index: " +
    info.image_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.image_idx) +
    "\n",
  )
  buf.write_string(
    "    Order Index: " +
    info.order_idx.to_uint().to_string() +
    ": ............. " +
    resolved_sii_string(strings, info.order_idx) +
    "\n\n",
  )
  buf.write_string("  CoE Details:\n")
  buf.write_string(
    "    Enable SDO: .................. " +
    bool_yes_no(info.supports_coe_sdo()) +
    "\n",
  )
  buf.write_string(
    "    Enable SDO Info: ............. " +
    bool_yes_no(info.supports_coe_sdo_info()) +
    "\n",
  )
  buf.write_string(
    "    Enable PDO Assign: ........... " +
    bool_yes_no(info.supports_coe_pdo_assign()) +
    "\n",
  )
  buf.write_string(
    "    Enable PDO Configuration: .... " +
    bool_yes_no(info.supports_coe_pdo_configuration()) +
    "\n",
  )
  buf.write_string(
    "    Enable Upload at Startup: .... " +
    bool_yes_no(info.supports_coe_upload_at_startup()) +
    "\n",
  )
  buf.write_string(
    "    Enable SDO complete access: .. " +
    bool_yes_no(info.supports_coe_complete_access()) +
    "\n",
  )
  buf.write_string(
    "  FoE Details: ................... " +
    bool_enabled_text(info.foe_supported) +
    "\n",
  )
  buf.write_string(
    "  EoE Details: ................... " +
    bool_enabled_text(info.eoe_supported) +
    "\n\n",
  )
  buf.write_string(
    "  Flag SafeOp: ................... " +
    bool_enabled_text(info.is_op_only()) +
    "\n",
  )
  buf.write_string(
    "  Flag notLRW: ................... " +
    bool_enabled_text(info.prefers_not_lrw()) +
    "\n",
  )
  buf.write_string(
    "  Flag MBox Data Link Layer ...... " +
    bool_enabled_text(info.supports_mailbox_data_link_layer()) +
    "\n",
  )
  buf.write_string(
    "  Flag Ident AL Status ........... " +
    bool_enabled_text(info.supports_identification_ado()) +
    "\n",
  )
  buf.write_string(
    "  Flag Ident Physical Memory ..... " +
    bool_enabled_text(info.supports_identification_physical_memory()) +
    "\n\n",
  )
  buf.write_string(
    "  CurrentOnEBus: ................. " +
    info.current_on_ebus.to_string() +
    " mA\n",
  )
  buf.write_string("\n  Physical Ports:\n")
  buf.write_string(
    "     Port 0: ..................... " +
    physical_port_name(info.physical_port_0) +
    "\n",
  )
  buf.write_string(
    "     Port 1: ..................... " +
    physical_port_name(info.physical_port_1) +
    "\n",
  )
  buf.write_string(
    "     Port 2: ..................... " +
    physical_port_name(info.physical_port_2) +
    "\n",
  )
  buf.write_string(
    "     Port 3: ..................... " +
    physical_port_name(info.physical_port_3) +
    "\n\n",
  )
  buf.write_string(
    "  Physical Memory Address ........ " +
    format_hex(info.physical_memory_address, 4) +
    "\n\n",
  )
}

///|
fn append_sii_fmmu_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  fmmu : Array[@mailbox.FmmuDirection],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Number of FMMUs: " + fmmu.length().to_string() + "\n")
  for i = 0; i < fmmu.length(); i = i + 1 {
    buf.write_string(
      "    FMMU" + i.to_string() + ": " + fmmu_usage_name(fmmu[i]) + "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_fmmu_ex_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  fmmu_ex : Array[@mailbox.SiiFmmuEx],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Number of FMMU_EX entries: " + fmmu_ex.length().to_string() + "\n",
  )
  for i = 0; i < fmmu_ex.length(); i = i + 1 {
    let current = fmmu_ex[i]
    buf.write_string("    FMMU" + i.to_string() + "\n")
    buf.write_string(
      "      opOnly: ............... " + bool_yes_no(current.op_only) + "\n",
    )
    buf.write_string(
      "      syncManager defined: .. " + bool_yes_no(current.sm_defined) + "\n",
    )
    buf.write_string(
      "      syncUnit defined: ..... " + bool_yes_no(current.su_defined) + "\n",
    )
    buf.write_string(
      "      syncManager index: .... " +
      current.sync_manager.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "      syncUnit index: ....... " +
      current.sync_unit.to_uint().to_string() +
      "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_sm_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  sms : Array[@mailbox.SiiSmEntry],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Number of SyncManager: " + sms.length().to_string() + "\n",
  )
  for i = 0; i < sms.length(); i = i + 1 {
    let sm = sms[i]
    buf.write_string("  SyncManager SM" + i.to_string() + "\n")
    buf.write_string(
      "    Physical Startaddress: ... " +
      format_hex(sm.physical_start, 4) +
      "\n",
    )
    buf.write_string(
      "    Length: .................. " + sm.length.to_string() + "\n",
    )
    buf.write_string(
      "    Control Register: ........ " +
      format_hex(sm.control.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "    Status Register: ......... " +
      format_hex(sm.status.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "    Enable byte: ............. " +
      format_hex(sm.activate.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "    SM Type: ................. " + sm_type_name(sm.sm_type) + "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_dc_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  dc : @mailbox.SiiDcClock,
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Cycle Time 0 .................. " + dc.cycle_time_0.to_string() + "\n",
  )
  buf.write_string(
    "  Shift Time 0 .................. " + dc.shift_time_0.to_string() + "\n",
  )
  buf.write_string(
    "  Shift Time 1 .................. " + dc.shift_time_1.to_string() + "\n",
  )
  buf.write_string(
    "  Sync1 Cycle Factor ............ " +
    dc.sync1_cycle_factor.to_string() +
    "\n",
  )
  buf.write_string(
    "  Assign Activate ............... " + dc.assign_activate.to_string() + "\n",
  )
  buf.write_string(
    "  Sync0 Cylce Factor ............ " +
    dc.sync0_cycle_factor.to_string() +
    "\n",
  )
  buf.write_string(
    "  Name Index .................... " +
    dc.name_idx.to_uint().to_string() +
    " (" +
    resolved_sii_string(strings, dc.name_idx) +
    ")\n",
  )
  buf.write_string(
    "  Description Index ............. " +
    dc.description_idx.to_uint().to_string() +
    " (" +
    resolved_sii_string(strings, dc.description_idx) +
    ")\n\n",
  )
}

///|
fn append_sii_timeouts_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  timeouts : @mailbox.SiiTimeouts,
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  INIT -> PREOP/BOOT Timeout ... " +
    timeouts.preop_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  SAFEOP -> OP Timeout ........ " +
    timeouts.safeop_op_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  Back To INIT Timeout ........ " +
    timeouts.back_to_init_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  OP -> SAFEOP Timeout ........ " +
    timeouts.back_to_safeop_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  Mailbox Request Timeout ..... " +
    timeouts.mailbox_request_timeout_ms.to_string() +
    " ms\n",
  )
  buf.write_string(
    "  Mailbox Response Timeout .... " +
    timeouts.mailbox_response_timeout_ms.to_string() +
    " ms\n\n",
  )
}

///|
fn append_sii_sync_unit_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  sync_units : Array[@mailbox.SiiSyncUnit],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string(
    "  Number of SyncUnits: " + sync_units.length().to_string() + "\n",
  )
  for i = 0; i < sync_units.length(); i = i + 1 {
    let current = sync_units[i]
    buf.write_string("    SyncUnit " + i.to_string() + "\n")
    buf.write_string(
      "      separateSu: ........... " + bool_yes_no(current.separate_su) + "\n",
    )
    buf.write_string(
      "      separateFrame: ........ " +
      bool_yes_no(current.separate_frame) +
      "\n",
    )
    buf.write_string(
      "      dependOnInputState: ... " +
      bool_yes_no(current.depend_on_input_state) +
      "\n",
    )
    buf.write_string(
      "      frameRepeatSupport: ... " +
      bool_yes_no(current.frame_repeat_support) +
      "\n",
    )
    buf.write_string(
      "      raw flags: ............ " +
      format_hex(current.raw_flags.to_uint(), 2) +
      "\n",
    )
  }
  buf.write_string("\n")
}

///|
fn append_sii_pdo_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
  pdos : Array[@mailbox.SiiPdo],
  strings : Array[String],
) -> Unit {
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Number of PDOs: " + pdos.length().to_string() + "\n")
  for i = 0; i < pdos.length(); i = i + 1 {
    let pdo = pdos[i]
    buf.write_string(
      "  PDO " +
      i.to_string() +
      ": index=" +
      format_hex(pdo.pdo_index, 4) +
      ", name=" +
      resolved_sii_string(strings, pdo.name_idx) +
      "\n",
    )
    buf.write_string(
      "    Sync Manager: ............ " +
      pdo.sync_manager.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "    Synchronization: ......... " +
      pdo.synchronization.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "    Entry Count: ............. " +
      pdo.entry_count.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "    Flags: ................... " + format_hex(pdo.flags, 4) + "\n",
    )
    for j = 0; j < pdo.entries.length(); j = j + 1 {
      let pdo_entry = pdo.entries[j]
      buf.write_string(
        "    Entry " +
        j.to_string() +
        ": " +
        format_hex(pdo_entry.entry_index, 4) +
        ":" +
        pdo_entry.subindex.to_uint().to_string() +
        " " +
        resolved_sii_string(strings, pdo_entry.name_idx) +
        " (" +
        pdo_entry.bit_length.to_uint().to_string() +
        " bits, type=" +
        format_hex(pdo_entry.data_type.to_uint(), 2) +
        ", flags=" +
        format_hex(pdo_entry.flags, 4) +
        ")\n",
      )
    }
  }
  buf.write_string("\n")
}

///|
fn append_sii_raw_category_section(
  buf : @buffer.Buffer,
  entry : @mailbox.SiiCategoryEntry,
) -> Unit {
  let category_class = entry.category_class().label()
  let (overlay_key, overlay_status, overlay_decoder) = match
    entry.overlay_candidate() {
    Some(candidate) =>
      (
        candidate.dispatch_key(),
        candidate.status_label(),
        match candidate.decoder_name() {
          Some(name) => name
          None => ""
        },
      )
    None => ("", "", "")
  }
  buf.write_string(
    "Print Categorie: " +
    sii_category_title(entry.category, entry.type_code) +
    " (" +
    format_hex(entry.type_code, 4) +
    ")\n",
  )
  buf.write_string("  Size: " + entry.data.length().to_string() + " Bytes\n")
  buf.write_string("  Class: " + category_class + "\n")
  if overlay_key != "" {
    buf.write_string("  Overlay Key: " + overlay_key + "\n")
    buf.write_string("  Overlay Status: " + overlay_status + "\n")
  }
  if overlay_decoder != "" {
    buf.write_string("  Overlay Decoder: " + overlay_decoder + "\n")
  }
  buf.write_string(
    "  Raw Preview: " + bytes_preview_hex(entry.data, 24) + "\n\n",
  )
}

///|
fn read_sii_text(
  position : UInt,
  word_count : Int,
  sii : @mailbox.SiiFullInfo,
) -> String {
  let eeprom = sii.eeprom
  let preamble = sii.preamble
  let standard = sii.standard
  let header = sii.header
  let general = sii.general
  let strings = sii.strings
  let categories = sii.categories
  let buf = @buffer.new(size_hint=2048)
  buf.write_string("First print preamble and config\n")
  buf.write_string(
    "Position: ................... " + position.to_string() + "\n",
  )
  buf.write_string(
    "Words requested: ............ " + word_count.to_string() + "\n",
  )
  buf.write_string(
    "Bytes read: ................. " + eeprom.length().to_string() + "\n",
  )
  buf.write_string("Preamble:\n")
  buf.write_string(
    "PDI Control: ................ " +
    format_hex(preamble.pdi_control, 4) +
    "\n",
  )
  buf.write_string(
    "PDI Config: ................. " + format_hex(preamble.pdi_config, 4) + "\n",
  )
  buf.write_string(
    "Sync Impulse Length: ........ " +
    preamble.sync_impulse_length_ns().to_string() +
    " ns (raw: " +
    format_hex(preamble.sync_impulse_length_raw, 4) +
    ")\n",
  )
  buf.write_string(
    "PDI Config 2: ............... " +
    format_hex(preamble.pdi_config2, 4) +
    "\n",
  )
  buf.write_string(
    "Configured Station Alias: ... " +
    format_hex(preamble.configured_station_alias, 4) +
    "\n",
  )
  buf.write_string(
    "Checksum of Preamble: ....... " +
    format_hex(preamble.checksum, 4) +
    " (" +
    (if preamble.checksum_ok { "ok" } else { "wrong" }) +
    ")\n\n",
  )
  buf.write_string("Identity:\n")
  buf.write_string(
    "  Vendor ID: ................ " + format_hex(header.vendor_id, 8) + "\n",
  )
  buf.write_string(
    "  Product ID: ............... " + format_hex(header.product_code, 8) + "\n",
  )
  buf.write_string(
    "  Revision ID: .............. " + format_hex(header.revision, 8) + "\n",
  )
  buf.write_string(
    "  Serial Number: ............ " + format_hex(header.serial, 8) + "\n\n",
  )
  buf.write_string("Default mailbox settings:\n")
  buf.write_string("  Bootstrap Mailbox:\n")
  buf.write_string(
    "  Received Mailbox Offset: .. " +
    format_hex(header.bootstrap_rx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Received Mailbox Size: .... " +
    header.bootstrap_rx_size.to_string() +
    "\n",
  )
  buf.write_string(
    "  Send Mailbox Offset: ...... " +
    format_hex(header.bootstrap_tx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Send Mailbox Size: ........ " +
    header.bootstrap_tx_size.to_string() +
    "\n",
  )
  buf.write_string("\n  Mailbox Settings:\n")
  buf.write_string(
    "  Received Mailbox Offset: .. " +
    format_hex(header.mailbox_rx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Received Mailbox Size: .... " + header.mailbox_rx_size.to_string() + "\n",
  )
  buf.write_string(
    "  Send Mailbox Offset: ...... " +
    format_hex(header.mailbox_tx_offset, 4) +
    "\n",
  )
  buf.write_string(
    "  Send Mailbox Size: ........ " +
    header.mailbox_tx_size.to_string() +
    "\n\n",
  )
  buf.write_string("Supported Mailboxes:\n")
  buf.write_string(
    "  AoE ....................... " +
    bool_true_false(header.supports_aoe()) +
    "\n",
  )
  buf.write_string(
    "  CoE ....................... " +
    bool_true_false(header.supports_coe()) +
    "\n",
  )
  buf.write_string(
    "  EoE ....................... " +
    bool_true_false(header.supports_eoe()) +
    "\n",
  )
  buf.write_string(
    "  FoE ....................... " +
    bool_true_false(header.supports_foe()) +
    "\n",
  )
  buf.write_string(
    "  SoE ....................... " +
    bool_true_false(header.supports_soe()) +
    "\n",
  )
  buf.write_string(
    "  VoE ....................... " +
    bool_true_false(header.supports_voe()) +
    "\n\n",
  )
  buf.write_string("Vendor Info:\n")
  buf.write_string(
    "  Firmware Version: ......... " +
    format_hex(header.firmware_version, 4) +
    "\n",
  )
  buf.write_string(
    "  Hardware Version: ......... " +
    format_hex(header.hardware_version, 4) +
    "\n",
  )
  buf.write_string(
    "  Production Date Raw: ...... " +
    format_hex(header.production_date_raw, 4) +
    "\n",
  )
  buf.write_string(
    "  Production Year: .......... " +
    header.production_year().to_string() +
    "\n",
  )
  buf.write_string(
    "  Production Weekday: ....... " +
    production_weekday_name(header.production_weekday()) +
    "\n",
  )
  buf.write_string(
    "  Production Week: .......... " +
    header.production_week().to_string() +
    "\n\n",
  )
  buf.write_string("ESC Configuration Area B:\n")
  buf.write_string(
    "  Present: .................. " +
    bool_yes_no(header.esc_config_b_present) +
    "\n",
  )
  buf.write_string(
    "  PDI1 Control: ............. " +
    format_hex(header.pdi_control_1.to_uint(), 2) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B0: ............ " +
    format_hex(header.esc_config_b0.to_uint(), 2) +
    "\n",
  )
  buf.write_string(
    "  PDI1 Configuration: ....... " + format_hex(header.pdi_config_1, 4) + "\n",
  )
  buf.write_string(
    "  Extended PDI1 Config: ..... " +
    format_hex(header.pdi_config_1_ext, 4) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B4: ............ " +
    format_hex(header.esc_config_b4, 4) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B5: ............ " +
    format_hex(header.esc_config_b5, 4) +
    "\n",
  )
  buf.write_string(
    "  ESC Config B6: ............ " +
    format_hex(header.esc_config_b6, 4) +
    "\n",
  )
  buf.write_string(
    "  Checksum B: ............... " + format_hex(header.checksum_b, 4) + "\n\n",
  )
  buf.write_string(
    "EEPROM size: ................ " +
    standard.eeprom_size_bytes().to_string() +
    " bytes\n",
  )
  buf.write_string(
    "Version: .................... " + standard.version.to_string() + "\n\n",
  )
  let fmmu = sii.fmmu
  let fmmu_ex = sii.fmmu_ex
  let sync_managers = sii.sync_managers
  let sync_units = sii.sync_units
  let mut dc_index = 0
  for entry in categories {
    match entry.category {
      Strings => append_sii_strings_section(buf, entry, strings)
      DataTypes => append_sii_raw_category_section(buf, entry)
      General =>
        match general {
          Some(info) => append_sii_general_section(buf, entry, info, strings)
          None => ()
        }
      Fmmu => append_sii_fmmu_section(buf, entry, fmmu)
      FmmuEx => append_sii_fmmu_ex_section(buf, entry, fmmu_ex)
      SyncManager => append_sii_sm_section(buf, entry, sync_managers)
      SyncUnit => append_sii_sync_unit_section(buf, entry, sync_units)
      TxPdo =>
        append_sii_pdo_section(
          buf,
          entry,
          @mailbox.parse_sii_pdo(entry.data),
          strings,
        )
      RxPdo =>
        append_sii_pdo_section(
          buf,
          entry,
          @mailbox.parse_sii_pdo(entry.data),
          strings,
        )
      Dc =>
        if dc_index < sii.dc_clocks.length() {
          append_sii_dc_section(buf, entry, sii.dc_clocks[dc_index], strings)
          dc_index = dc_index + 1
        }
      Timeouts =>
        match sii.timeouts {
          Some(timeouts) => append_sii_timeouts_section(buf, entry, timeouts)
          None => ()
        }
      Dictionary => append_sii_raw_category_section(buf, entry)
      Hardware => append_sii_raw_category_section(buf, entry)
      VendorInformation => append_sii_raw_category_section(buf, entry)
      Images => append_sii_raw_category_section(buf, entry)
      Raw => append_sii_raw_category_section(buf, entry)
    }
  }
  buf.to_string()
}

///|
fn expected_from_scan(scan : @runtime.ScanReport) -> Array[@hal.SlaveConfig] {
  scan.slaves.map(fn(s) {
    {
      position: s.position.reinterpret_as_uint(),
      expected_identity: Some({
        vendor_id: s.vendor_id,
        product_code: s.product_code,
        revision: s.revision,
        serial: s.serial,
      }),
      expected_identification: Some(s.identification),
      expected_alias_address: s.alias_address,
      configured_address: s.station_address,
      presence: @hal.Mandatory,
    }
  })
}

///|
fn scan_report_json(report : @runtime.ScanReport) -> Json {
  let items = report.slaves.map(fn(s) {
    Json::object({
      "position": Json::number(s.position.to_double()),
      "station_address": Json::number(s.station_address.to_double()),
      "alias_address": option_uint_json(s.alias_address),
      "vendor_id": Json::number(s.vendor_id.to_double()),
      "product_code": Json::number(s.product_code.to_double()),
      "revision": Json::number(s.revision.to_double()),
      "serial": Json::number(s.serial.to_double()),
      "identification": Json::number(s.identification.to_double()),
    })
  })
  Json::object({
    "slave_count": Json::number(report.slave_count.to_double()),
    "slaves": Json::array(items),
  })
}

///|
fn option_uint_json(value : UInt?) -> Json {
  match value {
    Some(number) => Json::number(number.to_double())
    None => Json::null()
  }
}

///|
fn option_bool_json(value : Bool?) -> Json {
  match value {
    Some(flag) => Json::boolean(flag)
    None => Json::null()
  }
}

///|
fn option_esm_state_json(value : @protocol.EsmState?) -> Json {
  match value {
    Some(state) => Json::string(state.to_string())
    None => Json::null()
  }
}

///|
fn option_string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

///|
fn identity_json(identity : @hal.SlaveIdentity) -> Json {
  Json::object({
    "vendor_id": Json::number(identity.vendor_id.to_double()),
    "product_code": Json::number(identity.product_code.to_double()),
    "revision": Json::number(identity.revision.to_double()),
    "serial": Json::number(identity.serial.to_double()),
  })
}

///|
fn option_identity_json(value : @hal.SlaveIdentity?) -> Json {
  match value {
    Some(identity) => identity_json(identity)
    None => Json::null()
  }
}

///|
fn mailbox_protocols_json(
  protocols : @runtime.ConfigurationMailboxProtocols,
) -> Json {
  Json::object({
    "aoe": Json::boolean(protocols.aoe),
    "coe": Json::boolean(protocols.coe),
    "eoe": Json::boolean(protocols.eoe),
    "foe": Json::boolean(protocols.foe),
    "soe": Json::boolean(protocols.soe),
    "voe": Json::boolean(protocols.voe),
  })
}

///|
fn process_data_summary_json(
  summary : @runtime.ConfigurationProcessDataSummary,
) -> Json {
  Json::object({
    "sync_manager_count": Json::number(summary.sync_manager_count.to_double()),
    "fmmu_count": Json::number(summary.fmmu_count.to_double()),
    "rx_pdo_count": Json::number(summary.rx_pdo_count.to_double()),
    "tx_pdo_count": Json::number(summary.tx_pdo_count.to_double()),
    "mailbox_protocols": match summary.mailbox_protocols {
      Some(protocols) => mailbox_protocols_json(protocols)
      None => Json::null()
    },
    "dc_op_mode_count": Json::number(summary.dc_op_mode_count.to_double()),
    "dc_assign_activate_count": Json::number(
      summary.dc_assign_activate_count.to_double(),
    ),
  })
}

///|
fn configuration_difference_json(
  diff : @runtime.ConfigurationDifference,
) -> Json {
  match diff {
    @runtime.Missing(position~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("missing"),
        "position": Json::number(position.to_double()),
      })
    @runtime.OptionalMissing(position~, group_id~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("optional-missing"),
        "position": Json::number(position.to_double()),
        "group_id": option_uint_json(group_id),
      })
    @runtime.Extra(position~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("extra"),
        "position": Json::number(position.to_double()),
      })
    @runtime.StationAddressMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("station-address-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_uint_json(expected),
        "actual": option_uint_json(actual),
      })
    @runtime.AliasAddressMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("alias-address-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_uint_json(expected),
        "actual": option_uint_json(actual),
      })
    @runtime.IdentityMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("identity-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_identity_json(expected),
        "actual": option_identity_json(actual),
      })
    @runtime.IdentificationMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("identification-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": option_uint_json(expected),
        "actual": option_uint_json(actual),
      })
    @runtime.ProcessDataSummaryMismatch(position~, expected~, actual~) =>
      Json::object({
        "category": Json::string(
          @runtime.validation_difference_category(diff).to_string(),
        ),
        "grade": Json::string(
          @runtime.validation_difference_grade(diff).to_string(),
        ),
        "type": Json::string("process-data-summary-mismatch"),
        "position": Json::number(position.to_double()),
        "expected": process_data_summary_json(expected),
        "actual": process_data_summary_json(actual),
      })
  }
}

///|
fn validate_report_json(report : @runtime.ValidateReport) -> Json {
  Json::object({
    "expected_source": Json::string(report.expected_source.to_string()),
    "actual_source": Json::string(report.actual_source.to_string()),
    "total_expected": Json::number(report.total_expected.to_double()),
    "total_found": Json::number(report.total_found.to_double()),
    "all_ok": Json::boolean(report.all_ok),
    "grade": Json::string(report.grade.to_string()),
    "result_count": Json::number(report.results.length().to_double()),
    "difference_count": Json::number(report.differences.length().to_double()),
    "differences": Json::array(
      report.differences.map(fn(diff) { configuration_difference_json(diff) }),
    ),
  })
}

///|
fn validate_output_json(
  scan : @runtime.ScanReport,
  report : @runtime.ValidateReport,
) -> Json {
  Json::object({
    "expected_source": Json::string(report.expected_source.to_string()),
    "actual_source": Json::string(report.actual_source.to_string()),
    "total_expected": Json::number(report.total_expected.to_double()),
    "total_found": Json::number(report.total_found.to_double()),
    "all_ok": Json::boolean(report.all_ok),
    "grade": Json::string(report.grade.to_string()),
    "result_count": Json::number(report.results.length().to_double()),
    "difference_count": Json::number(report.differences.length().to_double()),
    "differences": Json::array(
      report.differences.map(fn(diff) { configuration_difference_json(diff) }),
    ),
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_validate(scan, report),
    ),
  })
}

///|
fn run_report_json(report : @runtime.RunReport) -> Json {
  let tel = report.telemetry
  Json::object({
    "scan": scan_report_json(report.scan),
    "validation": validate_report_json(report.validation),
    "cycles_requested": Json::number(report.cycles_requested.to_double()),
    "cycles_ok": Json::number(report.cycles_ok.to_double()),
    "until_fault": Json::boolean(report.until_fault),
    "cycle_period_ns": Json::number(report.cycle_period_ns.to_double()),
    "output_period_ns": match report.output_period_ns {
      Some(output_period_ns) => Json::number(output_period_ns.to_double())
      None => Json::null()
    },
    "final_phase": Json::string(report.final_phase.to_string()),
    "fault": match report.fault {
      Some(fault) => run_fault_json(fault)
      None => Json::null()
    },
    "telemetry": Json::object({
      "cycles": Json::number(tel.cycles.to_double()),
      "tx_frames": Json::number(tel.tx_frames.to_double()),
      "rx_frames": Json::number(tel.rx_frames.to_double()),
      "timeouts": Json::number(tel.timeouts.to_double()),
      "retries": Json::number(tel.retries.to_double()),
      "wkc_errors": Json::number(tel.wkc_errors.to_double()),
      "irq_events": Json::number(tel.irq_events.to_double()),
      "dc_delay_updates": Json::number(tel.dc_delay_updates.to_double()),
      "emergency_events": Json::number(tel.emergency_events.to_double()),
    }),
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_run(report),
    ),
  })
}

///|
fn run_report_ndjson(report : @runtime.RunReport) -> Json {
  Json::object({
    "kind": Json::string("run-summary"),
    "summary": run_report_json(report),
  })
}

///|
fn run_progress_json(progress : @runtime.RunProgress) -> Json {
  Json::object({
    "kind": Json::string("run-progress"),
    "cycles_completed": Json::number(progress.cycles_completed.to_double()),
    "cycles_ok": Json::number(progress.cycles_ok.to_double()),
    "cycles_requested": match progress.cycles_requested {
      Some(cycles_requested) => Json::number(cycles_requested.to_double())
      None => Json::null()
    },
    "until_fault": Json::boolean(progress.until_fault),
    "cycle_period_ns": Json::number(progress.cycle_period_ns.to_double()),
    "output_period_ns": Json::number(progress.output_period_ns.to_double()),
    "telemetry": Json::object({
      "cycles": Json::number(progress.telemetry.cycles.to_double()),
      "tx_frames": Json::number(progress.telemetry.tx_frames.to_double()),
      "rx_frames": Json::number(progress.telemetry.rx_frames.to_double()),
      "timeouts": Json::number(progress.telemetry.timeouts.to_double()),
      "retries": Json::number(progress.telemetry.retries.to_double()),
      "wkc_errors": Json::number(progress.telemetry.wkc_errors.to_double()),
      "irq_events": Json::number(progress.telemetry.irq_events.to_double()),
      "dc_delay_updates": Json::number(
        progress.telemetry.dc_delay_updates.to_double(),
      ),
      "emergency_events": Json::number(
        progress.telemetry.emergency_events.to_double(),
      ),
    }),
    "consecutive_timeouts": Json::number(
      progress.consecutive_timeouts.to_double(),
    ),
  })
}

///|
fn run_progress_text(progress : @runtime.RunProgress) -> String {
  "run progress: cycles=" +
  progress.cycles_completed.to_string() +
  " ok=" +
  progress.cycles_ok.to_string() +
  " timeouts=" +
  progress.telemetry.timeouts.to_string() +
  " consecutive_timeouts=" +
  progress.consecutive_timeouts.to_string() +
  " wkc_errors=" +
  progress.telemetry.wkc_errors.to_string()
}

///|
struct CliTextRunProgressSink {
  _unused : Unit
}

///|
fn CliTextRunProgressSink::new() -> CliTextRunProgressSink {
  { _unused: () }
}

///|
pub impl @runtime.RunProgressSink for CliTextRunProgressSink with emit(
  self,
  progress,
) {
  ignore(self)
  println(run_progress_text(progress))
}

///|
struct CliNdjsonRunProgressSink {
  _unused : Unit
}

///|
fn CliNdjsonRunProgressSink::new() -> CliNdjsonRunProgressSink {
  { _unused: () }
}

///|
pub impl @runtime.RunProgressSink for CliNdjsonRunProgressSink with emit(
  self,
  progress,
) {
  ignore(self)
  println(run_progress_json(progress).stringify())
}

///|
fn run_fault_json(fault : @runtime.RunFault) -> Json {
  match fault {
    StartupTransitionFailed(
      station~,
      target~,
      current~,
      error_indication~,
      status_code~,
      raw_status_code~,
      control_wkc~
    ) =>
      Json::object({
        "kind": Json::string("startup-transition-failed"),
        "station": Json::number(station.to_double()),
        "target": Json::string(target.to_string()),
        "current": match current {
          Some(state) => Json::string(state.to_string())
          None => Json::null()
        },
        "al_error_flag": match error_indication {
          Some(flag) => Json::boolean(flag)
          None => Json::null()
        },
        "status_code": match status_code {
          Some(code) => Json::number(code.to_double())
          None => Json::null()
        },
        "raw_status_code": match raw_status_code {
          Some(code) => Json::number(code.to_double())
          None => Json::null()
        },
        "control_wkc": match control_wkc {
          Some(wkc) => Json::number(wkc.to_double())
          None => Json::null()
        },
      })
    TimeoutRecoveryRequired(observed_timeouts~, consecutive_timeouts~) =>
      Json::object({
        "kind": Json::string("timeout-recovery-required"),
        "observed_timeouts": Json::number(observed_timeouts.to_double()),
        "consecutive_timeouts": Json::number(consecutive_timeouts.to_double()),
      })
    RuntimeRecoveryRequired(expected_wkc~, observed_wkc_errors~) =>
      Json::object({
        "kind": Json::string("runtime-recovery-required"),
        "expected_wkc": Json::number(expected_wkc.to_double()),
        "observed_wkc_errors": Json::number(observed_wkc_errors.to_double()),
      })
    DcDrift(delta_ns~) =>
      Json::object({
        "kind": Json::string("dc-drift"),
        "delta_ns": Json::number(delta_ns.to_double()),
      })
  }
}

///|
fn state_transition_report_json(report : StateTransitionReport) -> Json {
  Json::object({
    "mode": Json::string(report.mode),
    "target_state": Json::string(report.target.to_string()),
    "station": match report.station {
      Some(station) => Json::number(station.to_double())
      None => Json::null()
    },
    "current_state": match report.current {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "final_state": match report.final_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_error_flag": match report.al_error_flag {
      Some(flag) => Json::boolean(flag)
      None => Json::null()
    },
    "status_code": match report.status_code {
      Some(code) => Json::number(code.to_double())
      None => Json::null()
    },
    "raw_status_code": match report.raw_status_code {
      Some(code) => Json::number(code.to_double())
      None => Json::null()
    },
    "control_wkc": match report.control_wkc {
      Some(wkc) => Json::number(wkc.to_double())
      None => Json::null()
    },
    "wkc": match report.wkc {
      Some(wkc) => Json::number(wkc.to_double())
      None => Json::null()
    },
    "pdo_audit": match report.pdo_audit {
      Some(value) => pdo_audit_report_json(value)
      None => Json::null()
    },
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_state_transition(
        report.station,
        report.target,
        report.current,
        report.final_state,
        report.al_error_flag,
        report.status_code,
        match report.control_wkc {
          Some(wkc) => Some(wkc)
          None => report.wkc
        },
      ),
    ),
  })
}

///|
fn state_surface_summary_json(summary : @runtime.StateSurfaceSummary) -> Json {
  Json::object({
    "target_state": match summary.target_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "current_state": match summary.current_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "final_state": match summary.final_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_state": match summary.al_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_error_flag": match summary.al_error_flag {
      Some(flag) => Json::boolean(flag)
      None => Json::null()
    },
    "al_status_code": match summary.al_status_code {
      Some(code) => Json::number(code.to_double())
      None => Json::null()
    },
    "al_status_code_description": match summary.al_status_code {
      Some(code) => Json::string(@protocol.al_status_code_description(code))
      None => Json::null()
    },
    "wkc": match summary.wkc {
      Some(wkc) => Json::number(wkc.to_double())
      None => Json::null()
    },
  })
}

///|
fn configuration_surface_summary_json(
  summary : @runtime.ConfigurationSurfaceSummary,
) -> Json {
  Json::object({
    "slave_count": Json::number(summary.slave_count.to_double()),
    "station_addresses": Json::array(
      summary.station_addresses.map(fn(station) {
        Json::number(station.to_double())
      }),
    ),
    "expected_source": match summary.expected_source {
      Some(source) => Json::string(source.to_string())
      None => Json::null()
    },
    "actual_source": match summary.actual_source {
      Some(source) => Json::string(source.to_string())
      None => Json::null()
    },
    "validation_grade": match summary.validation_grade {
      Some(grade) => Json::string(grade.to_string())
      None => Json::null()
    },
    "difference_count": Json::number(summary.difference_count.to_double()),
  })
}

///|
fn runtime_metrics_summary_json(
  summary : @runtime.RuntimeMetricsSummary,
) -> Json {
  Json::object({
    "cycles": Json::number(summary.cycles.to_double()),
    "tx_frames": Json::number(summary.tx_frames.to_double()),
    "rx_frames": Json::number(summary.rx_frames.to_double()),
    "timeouts": Json::number(summary.timeouts.to_double()),
    "retries": Json::number(summary.retries.to_double()),
    "wkc_errors": Json::number(summary.wkc_errors.to_double()),
    "irq_events": Json::number(summary.irq_events.to_double()),
    "dc_delay_updates": Json::number(summary.dc_delay_updates.to_double()),
    "emergency_events": Json::number(summary.emergency_events.to_double()),
  })
}

///|
fn diagnostic_issue_json(issue : @runtime.DiagnosticIssue) -> Json {
  Json::object({
    "source": Json::string(issue.source.to_string()),
    "category": Json::string(issue.category.to_string()),
    "level": Json::string(issue.level.to_string()),
    "detail": Json::string(issue.detail),
  })
}

///|
fn diagnostic_surface_json(surface : @runtime.DiagnosticSurface) -> Json {
  Json::object({
    "station": match surface.station_address {
      Some(station) => Json::number(station.to_double())
      None => Json::null()
    },
    "overall_level": Json::string(surface.overall_level.to_string()),
    "state": state_surface_summary_json(surface.state_summary),
    "configuration": match surface.configuration_summary {
      Some(summary) => configuration_surface_summary_json(summary)
      None => Json::null()
    },
    "error_register": match surface.error_register {
      Some(value) => Json::number(value.to_uint().to_double())
      None => Json::null()
    },
    "diagnosis_counter": match surface.diagnosis_counter {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
    "runtime_metrics": match surface.runtime_metrics {
      Some(summary) => runtime_metrics_summary_json(summary)
      None => Json::null()
    },
    "issues": Json::array(
      surface.issues.map(fn(issue) { diagnostic_issue_json(issue) }),
    ),
    "monitor_verdicts": match surface.monitor_verdicts {
      Some(results) =>
        Json::array(
          results.map(fn(r) {
            Json::object({
              "name": Json::string(r.name),
              "verdict": Json::string(r.verdict.to_string()),
            })
          }),
        )
      None => Json::null()
    },
    "overall_verdict": match surface.overall_verdict {
      Some(v) => Json::string(v.to_string())
      None => Json::null()
    },
    "topology_fingerprint": match surface.topology_fingerprint {
      Some(fp) =>
        Json::object({
          "slave_count": Json::number(fp.slave_count.to_double()),
          "identity_hash": Json::number(fp.identity_hash.to_double()),
        })
      None => Json::null()
    },
  })
}

///|
fn state_transition_report_text(report : StateTransitionReport) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("EtherCAT State Transition\n")
  buf.write_string("=========================\n")
  buf.write_string("Mode: " + report.mode + "\n")
  buf.write_string("Target: " + report.target.to_string() + "\n")
  match report.station {
    Some(station) =>
      buf.write_string("Station: " + format_hex(station, 4) + "\n")
    None => ()
  }
  match report.current {
    Some(state) => buf.write_string("Current: " + state.to_string() + "\n")
    None => ()
  }
  match report.final_state {
    Some(state) => buf.write_string("Final: " + state.to_string() + "\n")
    None => ()
  }
  match report.al_error_flag {
    Some(true) => buf.write_string("AL Error Flag: set\n")
    Some(false) => buf.write_string("AL Error Flag: clear\n")
    None => ()
  }
  match report.status_code {
    Some(code) =>
      buf.write_string("AL Status Code: " + format_hex(code, 4) + "\n")
    None => ()
  }
  match report.raw_status_code {
    Some(code) =>
      buf.write_string("Raw AL Status Code: " + format_hex(code, 4) + "\n")
    None => ()
  }
  match report.control_wkc {
    Some(wkc) => buf.write_string("AL Control WKC: " + wkc.to_string() + "\n")
    None => ()
  }
  match report.wkc {
    Some(wkc) => buf.write_string("WKC: " + wkc.to_string() + "\n")
    None => ()
  }
  match report.pdo_audit {
    Some(value) => buf.write_string("\n" + pdo_audit_report_text(value))
    None => ()
  }
  buf.to_string()
}

///|
fn pdo_direction_objects_text(direction : PdoDirectionReport) -> String {
  join_strings(
    direction.objects.map(fn(object) {
      format_hex(object.index, 4) +
      "=" +
      pdo_mapping_entries_text(object.entries)
    }),
    "; ",
  )
}

///|
fn pdo_audit_report_text(report : PdoAuditReport) -> String {
  let buf = @buffer.new(size_hint=1024)
  buf.write_string("PDO Audit\n")
  buf.write_string("---------\n")
  buf.write_string("Plan Source: " + report.plan_source + "\n")
  buf.write_string("Policy: " + report.policy + "\n")
  buf.write_string("Effective Source: " + report.effective_source + "\n")
  match report.live_detected {
    Some(value) =>
      buf.write_string(
        "Live Detected: " + (if value { "yes" } else { "no" }) + "\n",
      )
    None => ()
  }
  match report.live_differs_from_plan {
    Some(value) =>
      buf.write_string(
        "Live Differs From Plan: " + (if value { "yes" } else { "no" }) + "\n",
      )
    None => ()
  }
  match report.live_read_error {
    Some(err) => buf.write_string("Live Read Error: " + err + "\n")
    None => ()
  }
  buf.write_string(
    "Configured Rx: " +
    format_hex(report.configured_rx.assignment_index, 4) +
    " -> " +
    pdo_assignment_indices_text(report.configured_rx.assigned_pdos) +
    "\n",
  )
  if !report.configured_rx.objects.is_empty() {
    buf.write_string(
      "Configured Rx Objects: " +
      pdo_direction_objects_text(report.configured_rx) +
      "\n",
    )
  }
  buf.write_string(
    "Configured Tx: " +
    format_hex(report.configured_tx.assignment_index, 4) +
    " -> " +
    pdo_assignment_indices_text(report.configured_tx.assigned_pdos) +
    "\n",
  )
  if !report.configured_tx.objects.is_empty() {
    buf.write_string(
      "Configured Tx Objects: " +
      pdo_direction_objects_text(report.configured_tx) +
      "\n",
    )
  }
  match report.live_rx {
    Some(direction) => {
      buf.write_string(
        "Live Rx: " +
        format_hex(direction.assignment_index, 4) +
        " -> " +
        pdo_assignment_indices_text(direction.assigned_pdos) +
        "\n",
      )
      if !direction.objects.is_empty() {
        buf.write_string(
          "Live Rx Objects: " + pdo_direction_objects_text(direction) + "\n",
        )
      }
    }
    None => ()
  }
  match report.live_tx {
    Some(direction) => {
      buf.write_string(
        "Live Tx: " +
        format_hex(direction.assignment_index, 4) +
        " -> " +
        pdo_assignment_indices_text(direction.assigned_pdos) +
        "\n",
      )
      if !direction.objects.is_empty() {
        buf.write_string(
          "Live Tx Objects: " + pdo_direction_objects_text(direction) + "\n",
        )
      }
    }
    None => ()
  }
  if report.mismatches.is_empty() {
    buf.write_string("Mismatches: none\n")
  } else {
    buf.write_string("Mismatches:\n")
    for item in report.mismatches {
      buf.write_string("- " + item + "\n")
    }
  }
  buf.to_string()
}
