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
/// RunReport summarizes the outcome of a full run cycle.
pub(all) struct RunReport {
  scan : ScanReport
  validation : ValidateReport
  cycles_requested : Int
  cycles_ok : Int
  telemetry : Telemetry
  final_phase : RunPhase
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
/// 3. Transition all slaves to Operational via ESM broadcast.
/// 4. Run the requested number of PDO cycles.
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
  run_with_states(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    cycles,
    @protocol.Op,
    Some(@protocol.Init),
    timeout,
  )
}

///|
/// Execute a full EtherCAT run workflow with configurable startup and shutdown
/// broadcast states.
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
  // Phase 1: Scan
  let scan_report = scan(nic, timeout)
  let has_discovered_slaves = scan_report.slave_count > 0

  // Phase 2: Validate
  let validate_report = validate(scan_report, expected)
  if not(validate_report.all_ok) {
    return {
      scan: scan_report,
      validation: validate_report,
      cycles_requested: cycles,
      cycles_ok: 0,
      telemetry: Telemetry::new(),
      final_phase: Validating,
    }
  }

  // Phase 3: Configure — transition slaves to Operational
  if has_discovered_slaves {
    ignore(@protocol.broadcast_state(nic, startup_state, timeout))
  }

  // Phase 4: Run PDO cycles
  let rt = Runtime::new(config)
  rt.configure_pdo(pdo_ctx, expected_wkc)
  let stations = expected.map(fn(s) { s.configured_address })
  let dc_ok = rt.init_dc(nic, stations, timeout) catch { _ => false }
  rt.set_state(Running(if dc_ok { DcSync } else { FreeRun }))
  let ok_count = rt.run_cycles(nic, cycles, timeout)

  // Phase 5: Shutdown — transition slaves back to Init
  if has_discovered_slaves {
    match shutdown_state {
      Some(target) =>
        ignore(
          @protocol.broadcast_state(nic, target, timeout) catch {
            _ => 0U // Best-effort shutdown; report already captured
          },
        )
      None => ()
    }
  }
  rt.set_state(Idle)

  {
    scan: scan_report,
    validation: validate_report,
    cycles_requested: cycles,
    cycles_ok: ok_count,
    telemetry: rt.get_telemetry(),
    final_phase: Done,
  }
}

///|
/// Format a RunReport as a human-readable summary.
pub fn RunReport::format(self : RunReport) -> String {
  let buf = @buffer.new(size_hint=512)
  buf.write_string("MoonECAT Run Report\n")
  buf.write_string("===================\n")
  buf.write_string("Slaves found: " + self.scan.slave_count.to_string() + "\n")
  buf.write_string(
    "Validation: " +
    (if self.validation.all_ok { "PASS" } else { "FAIL" }) +
    "\n",
  )
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
  buf.to_string()
}
