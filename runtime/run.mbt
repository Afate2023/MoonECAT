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
    error_indication~ : Bool?,
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
  startup_outputs : Bytes?
}

///|
pub(all) struct RunStartupPreparation {
  pdo_ctx : @protocol.PdoContext
  expected_wkc : UInt
  dc_cycle_period_ns : Int64?
}

///|
let startup_eeprom_word_count : Int = 128

///|
pub fn required_sii_read_word_count(
  initial_eeprom : Bytes,
  initial_word_count : Int,
) -> Int {
  let metadata : Result[@mailbox.SiiStandardMetadata, Error] = try? @mailbox.parse_sii_standard_metadata(
    initial_eeprom,
  )
  match metadata {
    Ok(value) => {
      let required_word_count = ((value.eeprom_size_bytes() + 3U) / 4U).reinterpret_as_int()
      if required_word_count > initial_word_count {
        required_word_count
      } else {
        initial_word_count
      }
    }
    Err(_) => initial_word_count
  }
}

///|
pub fn[N : @hal.Nic] read_sii_with_metadata_fp(
  nic : N,
  station : UInt,
  initial_word_count : Int,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let initial_eeprom = @protocol.eeprom_read(
    nic,
    station,
    0U,
    initial_word_count,
    timeout,
  )
  let total_word_count = required_sii_read_word_count(
    initial_eeprom,
    initial_word_count,
  )
  if total_word_count <= initial_word_count {
    initial_eeprom
  } else {
    @protocol.eeprom_read(nic, station, 0U, total_word_count, timeout)
  }
}

///|
pub fn[N : @hal.Nic] read_sii_with_metadata_ap(
  nic : N,
  position : UInt,
  initial_word_count : Int,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let initial_eeprom = @protocol.eeprom_read_ap(
    nic,
    position,
    0U,
    initial_word_count,
    timeout,
  )
  let total_word_count = required_sii_read_word_count(
    initial_eeprom,
    initial_word_count,
  )
  if total_word_count <= initial_word_count {
    initial_eeprom
  } else {
    @protocol.eeprom_read_ap(nic, position, 0U, total_word_count, timeout)
  }
}

///|
enum OperationalStartupStep {
  TransitionToSafeOp
  DcPreconfigure
  WarmupProcessData
  TransitionToOp
} derive(Eq, Show)

///|
enum StartupRecoveryStrategy {
  RetryTargetPath
  RollbackToInit
  HoldSafeOp
} derive(Eq, Show)

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
  let startup_outputs : Array[(UInt, Bytes)] = []
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
    match preparation.startup_outputs {
      Some(outputs) => startup_outputs.push((slave.station_address, outputs))
      None => ()
    }
    dc_cycle_period_ns = prefer_dc_cycle_period(
      dc_cycle_period_ns,
      preparation.dc_cycle_period_ns,
    )
    current_logical_base = current_logical_base +
      preparation.mapping.output_bytes.reinterpret_as_uint() +
      preparation.mapping.input_bytes.reinterpret_as_uint()
  }
  let pdo_ctx = @protocol.PdoContext::build(slave_mappings, logical_base)
  for i = 0; i < startup_outputs.length(); i = i + 1 {
    let (station, outputs) = startup_outputs[i]
    pdo_ctx.set_slave_outputs(station, outputs)
  }
  {
    pdo_ctx,
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
  let eeprom = read_sii_with_metadata_fp(
    nic,
    station,
    eeprom_word_count,
    timeout,
  )
  let mapping = @mailbox.calculate_slave_mapping(eeprom, logical_base)
  let categories = @mailbox.parse_sii_categories(eeprom)
  {
    mapping,
    dc_cycle_period_ns: preferred_dc_cycle_period_from_categories(categories),
    startup_outputs: derive_startup_outputs(mapping, categories),
  }
}

///|
fn derive_startup_outputs(
  mapping : @mailbox.SlaveMapping,
  categories : Array[@mailbox.SiiCategoryEntry],
) -> Bytes? {
  if mapping.output_bytes <= 0 {
    return None
  }
  let general = collect_sii_general(categories)
  guard general is Some(general) else { return None }
  if general.ds402_channels == b'\x00' {
    return None
  }
  let rx_pdos = collect_sii_pdos(categories, @mailbox.RxPdo)
  let seed = Array::make(mapping.output_bytes, b'\x00')
  let mut wrote = false
  match find_pdo_entry_byte_offset(rx_pdos, 0x6040U, b'\x00') {
    Some((controlword_offset, controlword_length)) =>
      if controlword_length == 16 &&
        controlword_offset + 1 < mapping.output_bytes {
        seed[controlword_offset] = b'\x06'
        seed[controlword_offset + 1] = b'\x00'
        wrote = true
      }
    _ => ()
  }
  match
    (
      find_pdo_entry_byte_offset(rx_pdos, 0x6060U, b'\x00'),
      preferred_ds402_mode_seed(rx_pdos),
    ) {
    (Some((mode_offset, mode_length)), Some(mode_value)) =>
      if mode_length == 8 &&
        mode_offset < mapping.output_bytes &&
        mode_value != b'\x00' {
        seed[mode_offset] = mode_value
        wrote = true
      }
    _ => ()
  }
  if not(wrote) {
    return None
  }
  Some(Bytes::from_array(seed))
}

///|
fn preferred_ds402_mode_seed(rx_pdos : Array[@mailbox.SiiPdo]) -> Byte? {
  guard find_pdo_entry_byte_offset(rx_pdos, 0x6060U, b'\x00') is Some(_) else {
    return None
  }
  if find_pdo_entry_byte_offset(rx_pdos, 0x607AU, b'\x00') is Some(_) {
    return Some(b'\x08')
  }
  if find_pdo_entry_byte_offset(rx_pdos, 0x60FFU, b'\x00') is Some(_) {
    return Some(b'\x09')
  }
  None
}

///|
fn collect_sii_general(
  categories : Array[@mailbox.SiiCategoryEntry],
) -> @mailbox.SiiGeneral? {
  for category in categories {
    if category.category == @mailbox.General {
      let parsed : Result[@mailbox.SiiGeneral, Error] = try? @mailbox.parse_sii_general(
        category.data,
      )
      match parsed {
        Ok(general) => return Some(general)
        Err(_) => ()
      }
    }
  }
  None
}

///|
fn collect_sii_pdos(
  categories : Array[@mailbox.SiiCategoryEntry],
  target : @mailbox.SiiCategory,
) -> Array[@mailbox.SiiPdo] {
  let pdos : Array[@mailbox.SiiPdo] = []
  for category in categories {
    if category.category == target {
      let parsed = @mailbox.parse_sii_pdo(category.data)
      for pdo in parsed {
        pdos.push(pdo)
      }
    }
  }
  pdos
}

///|
fn find_pdo_entry_byte_offset(
  pdos : Array[@mailbox.SiiPdo],
  entry_index : UInt,
  subindex : Byte,
) -> (Int, Int)? {
  let mut bit_offset = 0
  for pdo in pdos {
    for entry in pdo.entries {
      let bit_length = entry.bit_length.to_int()
      if entry.entry_index == entry_index && entry.subindex == subindex {
        if bit_length <= 0 || bit_offset % 8 != 0 || bit_length % 8 != 0 {
          return None
        }
        return Some((bit_offset / 8, bit_length))
      }
      bit_offset = bit_offset + bit_length
    }
  }
  None
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
/// Write only mailbox SyncManager configuration derived from SII.
pub fn[N : @hal.Nic] write_mailbox_mapping(
  nic : N,
  station : UInt,
  mapping : @mailbox.SlaveMapping,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  for i = 0; i < mapping.sm_configs.length(); i = i + 1 {
    let sm = mapping.sm_configs[i]
    match sm.sm_type {
      @mailbox.MailboxOut | @mailbox.MailboxIn => {
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
}

///|
/// Write process-data SyncManager and FMMU configuration derived from SII.
/// Call this only after mailbox configuration is accepted and the station is
/// already in PreOp.
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
  let stations = scan_report.slaves.map(fn(slave) { slave.station_address })

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

  if has_discovered_slaves {
    let startup_fault = transition_stations_for_startup(
      nic, stations, startup_state, pdo_ctx, run_config, timeout,
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

  let rt = Runtime::new(run_config)
  rt.configure_pdo(pdo_ctx, expected_wkc)

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
        ignore(transition_stations_to_target(nic, stations, target, timeout))
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
fn build_operational_startup_steps(
  dc_enabled : Bool,
  has_process_data : Bool,
) -> Array[OperationalStartupStep] {
  let steps : Array[OperationalStartupStep] = [TransitionToSafeOp]
  if dc_enabled {
    steps.push(DcPreconfigure)
  }
  if has_process_data {
    steps.push(WarmupProcessData)
  }
  steps.push(TransitionToOp)
  steps
}

///|
/// Recovery policy is driven by the AL Status Code observed before the caller
/// acknowledges the pending error. Low-stage configuration failures should be
/// reinitialized from Init, while SafeOp->Op readiness failures should remain
/// in SafeOp so the caller can continue after fixing the missing condition.
fn classify_startup_recovery_strategy(
  current : @protocol.EsmState?,
  target : @protocol.EsmState,
  status_code : UInt?,
) -> StartupRecoveryStrategy {
  match status_code {
    Some(0x0016U) | Some(0x001DU) | Some(0x001EU) | Some(0x0070U) =>
      RollbackToInit
    Some(0x001BU) | Some(0x002DU) | Some(0x002EU) | Some(0x0030U) =>
      if target == @protocol.Op || current == Some(@protocol.SafeOp) {
        HoldSafeOp
      } else {
        RetryTargetPath
      }
    _ =>
      if target == @protocol.Op && current == Some(@protocol.SafeOp) {
        HoldSafeOp
      } else {
        RetryTargetPath
      }
  }
}

///|
fn[N : @hal.Nic] stabilize_failed_startup_station(
  nic : N,
  station : UInt,
  strategy : StartupRecoveryStrategy,
  timeout : @hal.Duration,
) -> Unit {
  let stabilize_target = match strategy {
    RollbackToInit => Some(@protocol.Init)
    HoldSafeOp => Some(@protocol.SafeOp)
    RetryTargetPath => None
  }
  match stabilize_target {
    Some(target) => {
      let snapshot = Some(
        @protocol.read_al_status_snapshot(nic, station, timeout),
      ) catch {
        _ => None
      }
      match snapshot {
        Some(status) if status.error_indication =>
          ignore(try? @protocol.clear_al_error(nic, station, timeout))
        _ => ()
      }
      ignore(
        try? @protocol.transition_to_target_strict(
          nic, station, target, timeout,
        ),
      )
    }
    None => ()
  }
}

///|
fn[N : @hal.Nic] read_startup_fault_details(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> @protocol.EsmStatusSnapshot? {
  Some(@protocol.read_al_status_snapshot(nic, station, timeout)) catch {
    _ => None
  }
}

///|
fn[N : @hal.Nic] transition_stations_for_startup(
  nic : N,
  stations : Array[UInt],
  startup_state : @protocol.EsmState,
  pdo_ctx : @protocol.PdoContext,
  run_config : @hal.MasterConfig,
  timeout : @hal.Duration,
) -> RunFault? {
  if startup_state == @protocol.PreOp {
    return transition_stations_to_preop_with_mailbox(nic, stations, timeout)
  }
  if startup_state == @protocol.SafeOp {
    return transition_stations_to_safeop_with_process_mapping(
      nic, stations, pdo_ctx, timeout,
    )
  }
  if startup_state != @protocol.Op {
    return transition_stations_to_target(nic, stations, startup_state, timeout)
  }

  let safeop_fault = transition_stations_to_safeop_with_process_mapping(
    nic, stations, pdo_ctx, timeout,
  )
  match safeop_fault {
    Some(_) => return safeop_fault
    None => ()
  }

  let steps = build_operational_startup_steps(
    run_config.dc_enabled,
    pdo_ctx.logical_size > 0,
  )
  for step in steps {
    match step {
      TransitionToSafeOp => ()
      DcPreconfigure =>
        ignore(
          try? @protocol.dc_configure_linear(
            nic,
            stations,
            run_config.cycle_period_ns.to_int().reinterpret_as_uint(),
            timeout,
            static_sync_iterations=32,
          ),
        )
      WarmupProcessData => warmup_process_data_for_op(nic, pdo_ctx, timeout)
      TransitionToOp => {
        let fault = transition_stations_to_op_with_process_data(
          nic, stations, pdo_ctx, timeout,
        )
        match fault {
          Some(_) => return fault
          None => ()
        }
      }
    }
  }
  None
}

///|
fn[N : @hal.Nic] transition_stations_to_preop_with_mailbox(
  nic : N,
  stations : Array[UInt],
  timeout : @hal.Duration,
) -> RunFault? {
  for station in stations {
    let fault = transition_slave_to_preop_with_mailbox(nic, station, timeout)
    match fault {
      Some(_) => return fault
      None => ()
    }
  }
  None
}

///|
fn[N : @hal.Nic] transition_stations_to_safeop_with_process_mapping(
  nic : N,
  stations : Array[UInt],
  pdo_ctx : @protocol.PdoContext,
  timeout : @hal.Duration,
) -> RunFault? {
  let preop_fault = transition_stations_to_preop_with_mailbox(
    nic, stations, timeout,
  )
  match preop_fault {
    Some(_) => return preop_fault
    None => ()
  }
  for station in stations {
    let process_fault = configure_slave_process_mapping_from_pdo_ctx(
      nic, station, pdo_ctx, timeout,
    )
    match process_fault {
      Some(_) => return process_fault
      None => ()
    }
  }
  transition_stations_to_target(nic, stations, @protocol.SafeOp, timeout)
}

///|
fn[N : @hal.Nic] transition_stations_to_target(
  nic : N,
  stations : Array[UInt],
  target : @protocol.EsmState,
  timeout : @hal.Duration,
) -> RunFault? {
  for station in stations {
    let fault = transition_slave_to_target(nic, station, target, timeout)
    match fault {
      Some(_) => return fault
      None => ()
    }
  }
  None
}

///|
fn[N : @hal.Nic] transition_stations_to_op_with_process_data(
  nic : N,
  stations : Array[UInt],
  pdo_ctx : @protocol.PdoContext,
  timeout : @hal.Duration,
) -> RunFault? {
  for station in stations {
    let fault = transition_slave_to_op_with_process_data(
      nic, station, pdo_ctx, timeout,
    )
    match fault {
      Some(_) => return fault
      None => ()
    }
  }
  None
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
    let snapshot = read_startup_fault_details(nic, station, timeout)
    let strategy = classify_startup_recovery_strategy(
      snapshot.map(fn(value) { value.state }),
      target,
      snapshot.bind(fn(value) { value.status_code }),
    )
    stabilize_failed_startup_station(nic, station, strategy, timeout)
    if strategy == RetryTargetPath &&
      attempt_transition_slave_to_target(nic, station, target, timeout) {
      None
    } else {
      Some(
        RunFault::StartupTransitionFailed(
          station~,
          target~,
          current=snapshot.map(fn(value) { value.state }),
          error_indication=snapshot.map(fn(value) { value.error_indication }),
          status_code=snapshot.bind(fn(value) { value.status_code }),
        ),
      )
    }
  }
}

///|
fn[N : @hal.Nic] transition_slave_to_preop_with_mailbox(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> RunFault? {
  let preparation = prepare_slave_startup(
    nic, station, 0U, startup_eeprom_word_count, timeout,
  ) catch {
    _ =>
      return Some(
        RunFault::StartupTransitionFailed(
          station~,
          target=@protocol.PreOp,
          current=None,
          error_indication=None,
          status_code=None,
        ),
      )
  }
  ignore(write_mailbox_mapping(nic, station, preparation.mapping, timeout)) catch {
    _ =>
      return Some(
        RunFault::StartupTransitionFailed(
          station~,
          target=@protocol.PreOp,
          current=None,
          error_indication=None,
          status_code=None,
        ),
      )
  }
  transition_slave_to_target(nic, station, @protocol.PreOp, timeout)
}

///|
fn pdo_logical_base_for_station(
  pdo_ctx : @protocol.PdoContext,
  station : UInt,
) -> UInt? {
  for mapping in pdo_ctx.mappings {
    if mapping.station == station {
      return Some(mapping.output_logical)
    }
  }
  None
}

///|
fn[N : @hal.Nic] configure_slave_process_mapping_from_pdo_ctx(
  nic : N,
  station : UInt,
  pdo_ctx : @protocol.PdoContext,
  timeout : @hal.Duration,
) -> RunFault? {
  let logical_base = match pdo_logical_base_for_station(pdo_ctx, station) {
    Some(value) => value
    None => 0U
  }
  let preparation = prepare_slave_startup(
    nic, station, logical_base, startup_eeprom_word_count, timeout,
  ) catch {
    _ =>
      return Some(
        RunFault::StartupTransitionFailed(
          station~,
          target=@protocol.SafeOp,
          current=None,
          error_indication=None,
          status_code=None,
        ),
      )
  }
  ignore(write_process_data_mapping(nic, station, preparation.mapping, timeout)) catch {
    _ =>
      return Some(
        RunFault::StartupTransitionFailed(
          station~,
          target=@protocol.SafeOp,
          current=None,
          error_indication=None,
          status_code=None,
        ),
      )
  }
  None
}

///|
fn[N : @hal.Nic] transition_slave_to_op_with_process_data(
  nic : N,
  station : UInt,
  pdo_ctx : @protocol.PdoContext,
  timeout : @hal.Duration,
) -> RunFault? {
  let snapshot = Some(
    @protocol.request_state_with_process_data_snapshot(
      nic,
      station,
      @protocol.Op,
      pdo_ctx,
      timeout,
    ),
  ) catch {
    _ => None
  }
  if snapshot is Some(observed) && observed.state == @protocol.Op {
    None
  } else {
    let fault_snapshot = match snapshot {
      Some(observed) => Some(observed)
      None => read_startup_fault_details(nic, station, timeout)
    }
    let strategy = classify_startup_recovery_strategy(
      fault_snapshot.map(fn(value) { value.state }),
      @protocol.Op,
      fault_snapshot.bind(fn(value) { value.status_code }),
    )
    stabilize_failed_startup_station(nic, station, strategy, timeout)
    Some(
      RunFault::StartupTransitionFailed(
        station~,
        target=@protocol.Op,
        current=fault_snapshot.map(fn(value) { value.state }),
        error_indication=fault_snapshot.map(fn(value) { value.error_indication }),
        status_code=fault_snapshot.bind(fn(value) { value.status_code }),
      ),
    )
  }
}

///|
fn[N : @hal.Nic] attempt_transition_slave_to_target(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  timeout : @hal.Duration,
) -> Bool {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout) catch {
    _ => return false
  }
  if snapshot.error_indication {
    ignore(@protocol.clear_al_error(nic, station, timeout)) catch {
      _ => return false
    }
  }
  let final_state = @protocol.transition_to_target_strict(
    nic, station, target, timeout,
  ) catch {
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
    StartupTransitionFailed(
      station~,
      target~,
      current~,
      error_indication~,
      status_code~
    ) => {
      let current_text = match current {
        Some(state) => state.to_string()
        None => "unknown"
      }
      let error_text = match error_indication {
        Some(true) => "set"
        Some(false) => "clear"
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
      " error_flag=" +
      error_text +
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
