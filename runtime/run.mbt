///|
/// CLI run command: full EtherCAT lifecycle — scan, validate, transition
/// slaves to Operational, run PDO cycles, and return a diagnostic summary.

///|
/// RunPhase describes which phase the run command is in.
pub(all) enum RunPhase {
  Scanning
  Validating
  Configuring
  Operational
  Stopping
  Done
} derive(Eq, Show)

///|
pub(all) enum RunFault {
  StartupTransitionFailed(
    station~ : UInt,
    target~ : @protocol.EsmState,
    current~ : @protocol.EsmState?,
    status_code~ : UInt?
  )
  TimeoutRecoveryRequired(
    observed_timeouts~ : Int64,
    consecutive_timeouts~ : Int
  )
  RuntimeRecoveryRequired(expected_wkc~ : UInt, observed_wkc_errors~ : Int64)
  DcDrift(delta_ns~ : Int64)
} derive(Eq, Show)

///|
/// RunLoopSettings controls runtime loop behavior beyond startup/shutdown
/// state sequencing.
pub(all) struct RunLoopSettings {
  cycles : Int
  until_fault : Bool
  cycle_period_ns : Int64?
  output_period_ns : Int64?
  max_consecutive_timeouts : Int
} derive(Eq, Show)

///|
pub fn RunLoopSettings::fixed_cycles(cycles : Int) -> RunLoopSettings {
  {
    cycles,
    until_fault: false,
    cycle_period_ns: None,
    output_period_ns: None,
    max_consecutive_timeouts: 5,
  }
}

///|
pub fn RunLoopSettings::until_fault() -> RunLoopSettings {
  {
    cycles: 0,
    until_fault: true,
    cycle_period_ns: None,
    output_period_ns: None,
    max_consecutive_timeouts: 5,
  }
}

///|
/// RunReport summarizes the outcome of a full run cycle.
pub(all) struct RunReport {
  scan : ScanReport
  validation : ValidateReport
  cycles_requested : Int
  cycles_ok : Int
  until_fault : Bool
  cycle_period_ns : Int64
  output_period_ns : Int64?
  telemetry : Telemetry
  final_phase : RunPhase
  fault : RunFault?
} derive(Show)

///|
pub(all) struct SlaveStartupPreparation {
  mapping : @mailbox.SlaveMapping
  dc_cycle_period_ns : Int64?
}

///|
pub(all) struct RunStartupPreparation {
  pdo_ctx : @protocol.PdoContext
  expected_wkc : UInt
  dc_cycle_period_ns : Int64?
}

///|
pub fn master_config_with_optional_dc(
  dc_cycle_period_ns : Int64?,
) -> @hal.MasterConfig {
  match dc_cycle_period_ns {
    Some(cycle_period_ns) =>
      { ..@hal.MasterConfig::default(), dc_enabled: true, cycle_period_ns }
    None => @hal.MasterConfig::default()
  }
}

///|
pub fn[N : @hal.Nic] build_run_startup_preparation(
  nic : N,
  scan_report : ScanReport,
  logical_base : UInt,
  eeprom_word_count : Int,
  timeout : @hal.Duration,
) -> RunStartupPreparation raise @hal.EcError {
  let slave_mappings : Array[(@mailbox.SlaveMapping, UInt)] = []
  let mut current_logical_base = logical_base
  let mut dc_cycle_period_ns : Int64? = None
  for slave in scan_report.slaves {
    let preparation = prepare_slave_startup(
      nic,
      slave.station_address,
      current_logical_base,
      eeprom_word_count,
      timeout,
    )
    slave_mappings.push((preparation.mapping, slave.station_address))
    dc_cycle_period_ns = prefer_dc_cycle_period(
      dc_cycle_period_ns,
      preparation.dc_cycle_period_ns,
    )
    current_logical_base = current_logical_base +
      preparation.mapping.output_bytes.reinterpret_as_uint() +
      preparation.mapping.input_bytes.reinterpret_as_uint()
  }
  {
    pdo_ctx: @protocol.PdoContext::build(slave_mappings, logical_base),
    expected_wkc: expected_wkc_from_slave_mappings(slave_mappings),
    dc_cycle_period_ns,
  }
}

///|
pub fn[N : @hal.Nic] prepare_slave_startup(
  nic : N,
  station : UInt,
  logical_base : UInt,
  eeprom_word_count : Int,
  timeout : @hal.Duration,
) -> SlaveStartupPreparation raise @hal.EcError {
  let eeprom = @protocol.eeprom_read(
    nic, station, 0U, eeprom_word_count, timeout,
  )
  let mapping = @mailbox.calculate_slave_mapping(eeprom, logical_base)
  write_process_data_mapping(nic, station, mapping, timeout)
  let categories = @mailbox.parse_sii_categories(eeprom)
  {
    mapping,
    dc_cycle_period_ns: preferred_dc_cycle_period_from_categories(categories),
  }
}

///|
pub fn preferred_dc_cycle_period_from_categories(
  categories : Array[@mailbox.SiiCategoryEntry],
) -> Int64? {
  match preferred_sii_dc_clock(collect_sii_dc(categories)) {
    Some(clock) => dc_cycle_period_ns(clock)
    None => None
  }
}

///|
fn collect_sii_dc(
  categories : Array[@mailbox.SiiCategoryEntry],
) -> Array[@mailbox.SiiDcClock] {
  let dc_clocks : Array[@mailbox.SiiDcClock] = []
  for category in categories {
    if category.category == @mailbox.Dc {
      let parsed : Result[@mailbox.SiiDcClock, Error] = try? @mailbox.parse_sii_dc(
        category.data,
      )
      match parsed {
        Ok(clock) => dc_clocks.push(clock)
        Err(_) => ()
      }
    }
  }
  dc_clocks
}

///|
pub fn preferred_sii_dc_clock(
  dc_clocks : Array[@mailbox.SiiDcClock],
) -> @mailbox.SiiDcClock? {
  for clock in dc_clocks {
    if clock.assign_activate != 0U {
      return Some(clock)
    }
  }
  if dc_clocks.is_empty() {
    None
  } else {
    Some(dc_clocks[0])
  }
}

///|
pub fn dc_cycle_period_ns(clock : @mailbox.SiiDcClock) -> Int64? {
  if clock.cycle_time_0 == 0U {
    return None
  }
  Some(clock.cycle_time_0.reinterpret_as_int().to_int64())
}

///|
pub fn[N : @hal.Nic] write_process_data_mapping(
  nic : N,
  station : UInt,
  mapping : @mailbox.SlaveMapping,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  for i = 0; i < mapping.sm_configs.length(); i = i + 1 {
    let sm = mapping.sm_configs[i]
    match sm.sm_type {
      @mailbox.ProcessDataOut | @mailbox.ProcessDataIn => {
        let sm_addr = @protocol.reg_sm_base +
          i.reinterpret_as_uint() *
          @protocol.sm_entry_size.reinterpret_as_uint()
        let _ = @protocol.write_register_fp(
          nic,
          station,
          sm_addr,
          sm.to_bytes(),
          timeout,
        )
      }
      _ => ()
    }
  }
  for i = 0; i < mapping.fmmu_configs.length(); i = i + 1 {
    let fmmu_addr = @protocol.reg_fmmu_base +
      i.reinterpret_as_uint() * @protocol.fmmu_entry_size.reinterpret_as_uint()
    let _ = @protocol.write_register_fp(
      nic,
      station,
      fmmu_addr,
      mapping.fmmu_configs[i].to_bytes(),
      timeout,
    )
  }
}

///|
fn prefer_dc_cycle_period(current : Int64?, candidate : Int64?) -> Int64? {
  match current {
    Some(_) => current
    None => candidate
  }
}

///|
fn expected_wkc_from_slave_mappings(
  slave_mappings : Array[(@mailbox.SlaveMapping, UInt)],
) -> UInt {
  let mut total = 0U
  for i = 0; i < slave_mappings.length(); i = i + 1 {
    let (mapping, _) = slave_mappings[i]
    if mapping.output_bytes > 0 {
      total = total + 1U
    }
    if mapping.input_bytes > 0 {
      total = total + 1U
    }
  }
  total
}

///|
/// Execute a full EtherCAT run workflow:
/// 1. Scan the bus to discover slaves.
/// 2. Validate discovered slaves against expected configuration.
/// 3. Transition all slaves to Operational.
/// 4. Run PDO cycles.
/// 5. Transition slaves back to Init.
/// 6. Return a summary report.
pub fn[N : @hal.Nic] run(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  cycles : Int,
  timeout : @hal.Duration,
) -> RunReport raise @hal.EcError {
  run_with_states_and_settings(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    RunLoopSettings::fixed_cycles(cycles),
    @protocol.Op,
    Some(@protocol.Init),
    timeout,
  )
}

///|
pub fn[N : @hal.Nic] run_with_settings(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  settings : RunLoopSettings,
  timeout : @hal.Duration,
) -> RunReport raise @hal.EcError {
  run_with_states_and_settings(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    settings,
    @protocol.Op,
    Some(@protocol.Init),
    timeout,
  )
}

///|
pub fn[N : @hal.Nic, S : RunProgressSink] run_with_settings_reporting_to(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  settings : RunLoopSettings,
  timeout : @hal.Duration,
  sink : S,
) -> RunReport raise @hal.EcError {
  run_with_states_and_settings_reporting_to(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    settings,
    @protocol.Op,
    Some(@protocol.Init),
    timeout,
    sink,
  )
}

///|
pub fn[N : @hal.Nic] run_until_fault(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  timeout : @hal.Duration,
) -> RunReport raise @hal.EcError {
  run_with_states_and_settings(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    RunLoopSettings::until_fault(),
    @protocol.Op,
    Some(@protocol.Init),
    timeout,
  )
}

///|
pub fn[N : @hal.Nic] run_with_states(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  cycles : Int,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  timeout : @hal.Duration,
) -> RunReport raise @hal.EcError {
  run_with_states_and_settings(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    RunLoopSettings::fixed_cycles(cycles),
    startup_state,
    shutdown_state,
    timeout,
  )
}

///|
pub fn[N : @hal.Nic] run_with_states_until_fault(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  timeout : @hal.Duration,
) -> RunReport raise @hal.EcError {
  run_with_states_and_settings(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    RunLoopSettings::until_fault(),
    startup_state,
    shutdown_state,
    timeout,
  )
}

///|
pub fn[N : @hal.Nic] run_with_states_and_settings(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  settings : RunLoopSettings,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  timeout : @hal.Duration,
) -> RunReport raise @hal.EcError {
  run_with_states_and_settings_reporting_to(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    settings,
    startup_state,
    shutdown_state,
    timeout,
    NullRunProgressSink::new(),
  )
}

///|
pub fn[N : @hal.Nic, S : RunProgressSink] run_with_states_and_settings_reporting_to(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  settings : RunLoopSettings,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  timeout : @hal.Duration,
  sink : S,
) -> RunReport raise @hal.EcError {
  let run_config = resolve_run_loop_config(config, settings)
  let progress_every_cycles = resolve_progress_every_cycles(
    run_config, settings,
  )
  let scan_report = scan(nic, timeout)
  let has_discovered_slaves = scan_report.slave_count > 0

  let validate_report = validate(scan_report, expected)
  if not(validate_report.all_ok) {
    return {
      scan: scan_report,
      validation: validate_report,
      cycles_requested: settings.cycles,
      cycles_ok: 0,
      until_fault: settings.until_fault,
      cycle_period_ns: run_config.cycle_period_ns,
      output_period_ns: settings.output_period_ns,
      telemetry: Telemetry::new(),
      final_phase: Validating,
      fault: None,
    }
  }

  let pre_run_state = if startup_state == @protocol.Op {
    @protocol.SafeOp
  } else {
    startup_state
  }
  if has_discovered_slaves {
    for slave in scan_report.slaves {
      let startup_fault = transition_slave_to_target(
        nic,
        slave.station_address,
        pre_run_state,
        timeout,
      )
      match startup_fault {
        Some(fault) =>
          return {
            scan: scan_report,
            validation: validate_report,
            cycles_requested: settings.cycles,
            cycles_ok: 0,
            until_fault: settings.until_fault,
            cycle_period_ns: run_config.cycle_period_ns,
            output_period_ns: settings.output_period_ns,
            telemetry: Telemetry::new(),
            final_phase: Configuring,
            fault: Some(fault),
          }
        None => ()
      }
    }
  }

  if has_discovered_slaves && startup_state == @protocol.Op {
    warmup_process_data_for_op(nic, pdo_ctx, timeout)
    for slave in scan_report.slaves {
      let startup_fault = transition_slave_to_target(
        nic,
        slave.station_address,
        startup_state,
        timeout,
      )
      match startup_fault {
        Some(fault) =>
          return {
            scan: scan_report,
            validation: validate_report,
            cycles_requested: settings.cycles,
            cycles_ok: 0,
            until_fault: settings.until_fault,
            cycle_period_ns: run_config.cycle_period_ns,
            output_period_ns: settings.output_period_ns,
            telemetry: Telemetry::new(),
            final_phase: Configuring,
            fault: Some(fault),
          }
        None => ()
      }
    }
  }

  let rt = Runtime::new(run_config)
  rt.configure_pdo(pdo_ctx, expected_wkc)
  let stations = expected.map(fn(s) { s.configured_address })

  if has_discovered_slaves &&
    startup_state == @protocol.Op &&
    run_config.dc_enabled {
    ignore(
      try? @protocol.dc_configure_linear(
        nic,
        stations,
        run_config.cycle_period_ns.to_int().reinterpret_as_uint(),
        timeout,
        static_sync_iterations=32,
      ),
    )
  }

  let dc_ok = rt.init_dc(nic, stations, timeout) catch { _ => false }
  rt.set_timeout_threshold(settings.max_consecutive_timeouts)
  rt.set_state(Running(if dc_ok { DcSync } else { FreeRun }))
  let ok_count = if settings.until_fault {
    rt.run_until_fault_with_reporting_to(
      nic,
      timeout,
      progress_every_cycles,
      settings.output_period_ns.map(fn(period_ns) { period_ns.to_int() }),
      sink,
    )
  } else {
    rt.run_cycles_with_reporting_to(
      nic,
      settings.cycles,
      timeout,
      progress_every_cycles,
      settings.output_period_ns.map(fn(period_ns) { period_ns.to_int() }),
      sink,
    )
  }
  let telemetry = rt.get_telemetry()
  let runtime_fault = runtime_fault_from_runtime(rt)

  if has_discovered_slaves {
    match shutdown_state {
      Some(target) =>
        for slave in scan_report.slaves {
          ignore(
            transition_slave_to_target(
              nic,
              slave.station_address,
              target,
              timeout,
            ),
          )
        }
      None => ()
    }
  }
  rt.set_state(Idle)

  {
    scan: scan_report,
    validation: validate_report,
    cycles_requested: if settings.until_fault {
      telemetry.cycles.to_int()
    } else {
      settings.cycles
    },
    cycles_ok: ok_count,
    until_fault: settings.until_fault,
    cycle_period_ns: run_config.cycle_period_ns,
    output_period_ns: settings.output_period_ns,
    telemetry,
    final_phase: match runtime_fault {
      Some(_) => Operational
      None => Done
    },
    fault: runtime_fault,
  }
}

///|
fn[N : @hal.Nic] transition_slave_to_target(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  timeout : @hal.Duration,
) -> RunFault? {
  if attempt_transition_slave_to_target(nic, station, target, timeout) {
    None
  } else {
    ignore(try? @protocol.broadcast_state(nic, target, timeout))
    if attempt_transition_slave_to_target(nic, station, target, timeout) {
      None
    } else {
      Some(startup_transition_fault(nic, station, target, timeout))
    }
  }
}

///|
fn[N : @hal.Nic] attempt_transition_slave_to_target(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  timeout : @hal.Duration,
) -> Bool {
  let current = @protocol.read_al_status(nic, station, timeout) catch {
    _ => return false
  }
  let path = @protocol.build_transition_route(current, target)
  let final_state = @protocol.transition_through(nic, station, path, timeout) catch {
    _ => return false
  }
  final_state == target
}

///|
fn[N : @hal.Nic] warmup_process_data_for_op(
  nic : N,
  pdo_ctx : @protocol.PdoContext,
  timeout : @hal.Duration,
) -> Unit {
  if pdo_ctx.logical_size > 0 {
    ignore(try? @protocol.pdo_exchange_result(nic, pdo_ctx, timeout))
  }
}

///|
fn[N : @hal.Nic] startup_transition_fault(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  timeout : @hal.Duration,
) -> RunFault {
  let current = Some(@protocol.read_al_status(nic, station, timeout)) catch {
    _ => None
  }
  let status_code = Some(@protocol.read_al_status_code(nic, station, timeout)) catch {
    _ => None
  }
  RunFault::StartupTransitionFailed(station~, target~, current~, status_code~)
}

///|
fn runtime_fault_from_runtime(rt : Runtime) -> RunFault? {
  match rt.dc_state {
    Drifting(delta_ns) => Some(DcDrift(delta_ns~))
    _ =>
      if rt.consecutive_timeouts >= rt.max_consecutive_timeouts {
        Some(
          TimeoutRecoveryRequired(
            observed_timeouts=rt.telemetry.timeouts,
            consecutive_timeouts=rt.consecutive_timeouts,
          ),
        )
      } else if rt.needs_recovery() || rt.state is Error(_) {
        Some(
          RuntimeRecoveryRequired(
            expected_wkc=rt.expected_wkc,
            observed_wkc_errors=rt.telemetry.wkc_errors,
          ),
        )
      } else {
        None
      }
  }
}

///|
fn resolve_run_loop_config(
  config : @hal.MasterConfig,
  settings : RunLoopSettings,
) -> @hal.MasterConfig {
  match settings.cycle_period_ns {
    Some(cycle_period_ns) => { ..config, cycle_period_ns, }
    None => config
  }
}

///|
fn resolve_progress_every_cycles(
  config : @hal.MasterConfig,
  settings : RunLoopSettings,
) -> Int? {
  match settings.output_period_ns {
    Some(output_period_ns) =>
      if output_period_ns > 0L {
        Some(
          ((output_period_ns + config.cycle_period_ns - 1L) /
          config.cycle_period_ns).to_int(),
        )
      } else {
        None
      }
    _ => None
  }
}

///|
fn run_fault_text(fault : RunFault) -> String {
  match fault {
    StartupTransitionFailed(station~, target~, current~, status_code~) => {
      let current_text = match current {
        Some(state) => state.to_string()
        None => "unknown"
      }
      let status_text = match status_code {
        Some(code) => code.to_string()
        None => "unknown"
      }
      "startup transition failed: station=" +
      station.to_string() +
      " target=" +
      target.to_string() +
      " current=" +
      current_text +
      " status_code=" +
      status_text
    }
    TimeoutRecoveryRequired(observed_timeouts~, consecutive_timeouts~) =>
      "timeout recovery required: timeouts=" +
      observed_timeouts.to_string() +
      " consecutive_timeouts=" +
      consecutive_timeouts.to_string()
    RuntimeRecoveryRequired(expected_wkc~, observed_wkc_errors~) =>
      "runtime recovery required: expected_wkc=" +
      expected_wkc.to_string() +
      " wkc_errors=" +
      observed_wkc_errors.to_string()
    DcDrift(delta_ns~) => "dc drift detected: delta_ns=" + delta_ns.to_string()
  }
}

///|
/// Format a RunReport as a human-readable summary.
pub fn RunReport::format(self : RunReport) -> String {
  let buf = @buffer.new(size_hint=512)
  let fault_text = match self.fault {
    Some(fault) => run_fault_text(fault)
    None => "none"
  }
  let output_period_text = match self.output_period_ns {
    Some(output_period_ns) => output_period_ns.to_string()
    None => "none"
  }
  buf.write_string("MoonECAT Run Report\n")
  buf.write_string("===================\n")
  buf.write_string("Slaves found: " + self.scan.slave_count.to_string() + "\n")
  buf.write_string(
    "Validation: " +
    (if self.validation.all_ok { "PASS" } else { "FAIL" }) +
    "\n",
  )
  buf.write_string(
    "Mode: " +
    (if self.until_fault { "UntilFault" } else { "FixedCycles" }) +
    "\n",
  )
  buf.write_string("CyclePeriodNs: " + self.cycle_period_ns.to_string() + "\n")
  buf.write_string("OutputPeriodNs: " + output_period_text + "\n")
  buf.write_string(
    "Cycles: " +
    self.cycles_ok.to_string() +
    "/" +
    self.cycles_requested.to_string() +
    " OK\n",
  )
  buf.write_string("Phase: " + self.final_phase.to_string() + "\n")
  let tel = self.telemetry
  buf.write_string(
    "Telemetry: tx=" +
    tel.tx_frames.to_string() +
    " rx=" +
    tel.rx_frames.to_string() +
    " timeouts=" +
    tel.timeouts.to_string() +
    " irq_events=" +
    tel.irq_events.to_string() +
    " dc_delay_updates=" +
    tel.dc_delay_updates.to_string() +
    " wkc_errors=" +
    tel.wkc_errors.to_string() +
    "\n",
  )
  buf.write_string("Fault: " + fault_text + "\n")
  buf.to_string()
}
