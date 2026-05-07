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
