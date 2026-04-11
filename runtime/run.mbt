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
} derive(Eq, Debug)

///|
pub(all) enum RunFault {
  StartupTransitionFailed(
    station~ : UInt,
    target~ : @protocol.EsmState,
    current~ : @protocol.EsmState?,
    error_indication~ : Bool?,
    status_code~ : UInt?,
    raw_status_code~ : UInt?,
    control_wkc~ : UInt?
  )
  TimeoutRecoveryRequired(
    observed_timeouts~ : Int64,
    consecutive_timeouts~ : Int
  )
  RuntimeRecoveryRequired(expected_wkc~ : UInt, observed_wkc_errors~ : Int64)
  DcDrift(delta_ns~ : Int64)
} derive(Eq, Debug)

///|
priv struct TransitionAttemptObservation {
  reached_target : Bool
  observation : @protocol.EsmStateRequestObservation?
}

///|
/// RunLoopSettings controls runtime loop behavior beyond startup/shutdown
/// state sequencing.
pub(all) struct RunLoopSettings {
  cycles : Int
  until_fault : Bool
  cycle_period_ns : Int64?
  output_period_ns : Int64?
  max_consecutive_timeouts : Int
} derive(Eq, Debug)

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
} derive(Debug)

///|
pub(all) struct SlaveStartupPreparation {
  mapping : @mailbox.SlaveMapping
  dc_cycle_period_ns : Int64?
  startup_outputs : Bytes?
  startup_mailbox_commands : Array[StartupMailboxCommand]
  mailbox_config : @mailbox.MailboxConfig
  sii : @mailbox.SiiFullInfo
  sii_categories : Array[@mailbox.SiiCategoryEntry]
  prefer_live_pdo_state : Bool
}

///|
pub(all) enum StartupCommandTransition {
  InitToPreOp
  InitToBoot
  PreOpToInit
  PreOpToSafeOp
  SafeOpToInit
  SafeOpToPreOp
  SafeOpToOp
  OpToInit
  OpToPreOp
  OpToSafeOp
  BootToInit
} derive(Eq, Debug)

///|
pub(all) struct StartupMailboxCommand {
  transition : StartupCommandTransition
  index : UInt
  subindex : Byte
  data : Bytes
} derive(Eq, Debug)

///|
pub(all) struct StationStartupMailboxPlan {
  station : UInt
  mailbox_config : @mailbox.MailboxConfig
  commands : Array[StartupMailboxCommand]
} derive(Eq, Debug)

///|
pub(all) struct RunStartupPreparation {
  pdo_ctx : @protocol.PdoContext
  expected_wkc : UInt
  dc_cycle_period_ns : Int64?
  startup_mailbox_plans : Array[StationStartupMailboxPlan]
  esm_timeout_policies : Array[(UInt, @protocol.EsmTimeoutPolicy)]
  slave_preparations : Array[(UInt, SlaveStartupPreparation)]?
}

///|
/// Look up the ESM timeout policy for a station from an array of policies.
/// Returns the default (all-None) policy when no entry is found.
fn lookup_esm_timeout_policy(
  policies : Array[(UInt, @protocol.EsmTimeoutPolicy)],
  station : UInt,
) -> @protocol.EsmTimeoutPolicy {
  for item in policies {
    let (s, policy) = item
    if s == station {
      return policy
    }
  }
  @protocol.default_esm_timeout_policy()
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
  @protocol.read_sii_bytes(nic, station, initial_word_count, timeout)
}

///|
pub fn[N : @hal.Nic] read_sii_with_metadata_ap(
  nic : N,
  position : UInt,
  initial_word_count : Int,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  @protocol.read_sii_bytes_ap(nic, position, initial_word_count, timeout)
}

///|
enum OperationalStartupStep {
  TransitionToSafeOp
  DcPreconfigure
  WarmupProcessData
  ValidateSmWatchdog
  TransitionToOp
} derive(Eq, Debug)

///|
enum StartupRecoveryStrategy {
  RetryTargetPath
  RollbackToInit
  HoldSafeOp
} derive(Eq, Debug)

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
/// Check if any slave in the SII info set the PreferNotLRW flag.
fn sii_prefers_not_lrw(sii : @mailbox.SiiFullInfo) -> Bool {
  match sii.general {
    Some(general) => general.prefers_not_lrw()
    None => false
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
  let startup_mailbox_plans : Array[StationStartupMailboxPlan] = []
  let esm_timeout_policies : Array[(UInt, @protocol.EsmTimeoutPolicy)] = []
  let mut current_logical_base = logical_base
  let mut dc_cycle_period_ns : Int64? = None
  let mut any_not_lrw = false
  for slave in scan_report.slaves {
    let preparation = prepare_slave_startup(
      nic,
      slave.station_address,
      current_logical_base,
      eeprom_word_count,
      timeout,
    )
    slave_mappings.push((preparation.mapping, slave.station_address))
    if sii_prefers_not_lrw(preparation.sii) {
      any_not_lrw = true
    }
    match preparation.startup_outputs {
      Some(outputs) => startup_outputs.push((slave.station_address, outputs))
      None => ()
    }
    if preparation.startup_mailbox_commands.length() > 0 {
      startup_mailbox_plans.push({
        station: slave.station_address,
        mailbox_config: preparation.mailbox_config,
        commands: preparation.startup_mailbox_commands,
      })
    }
    dc_cycle_period_ns = prefer_dc_cycle_period(
      dc_cycle_period_ns,
      preparation.dc_cycle_period_ns,
    )
    esm_timeout_policies.push(
      (
        slave.station_address,
        @protocol.esm_timeout_policy_from_sii_timeouts(preparation.sii.timeouts),
      ),
    )
    current_logical_base = current_logical_base +
      preparation.mapping.output_bytes.reinterpret_as_uint() +
      preparation.mapping.input_bytes.reinterpret_as_uint()
  }
  let pdo_ctx = @protocol.PdoContext::build(slave_mappings, logical_base)
  pdo_ctx.block_lrw = any_not_lrw
  for i = 0; i < startup_outputs.length(); i = i + 1 {
    let (station, outputs) = startup_outputs[i]
    pdo_ctx.set_slave_outputs(station, outputs)
  }
  {
    pdo_ctx,
    expected_wkc: expected_wkc_from_slave_mappings(slave_mappings),
    dc_cycle_period_ns,
    startup_mailbox_plans,
    esm_timeout_policies,
    slave_preparations: None,
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
    nic, station, eeprom_word_count, timeout,
  )
  let sii = @mailbox.parse_sii_full_info(eeprom)
  let mapping = @mailbox.calculate_slave_mapping_from_sii(sii, logical_base)
  let startup_outputs = derive_startup_outputs(mapping, sii)
  let startup_mailbox_commands = filter_redundant_startup_mailbox_commands(
    derive_startup_mailbox_commands(sii),
    startup_outputs,
    mapping,
    sii,
  )
  {
    mapping,
    dc_cycle_period_ns: preferred_dc_cycle_period(sii),
    startup_outputs,
    startup_mailbox_commands,
    mailbox_config: @mailbox.MailboxConfig::from_sii(sii.header),
    sii,
    sii_categories: sii.categories,
    prefer_live_pdo_state: true,
  }
}

///|
pub fn startup_preparation_from_esi_offline_report(
  report : EsiOfflineSiiReport,
  logical_base : UInt,
) -> SlaveStartupPreparation {
  let mapping = @mailbox.calculate_slave_mapping_from_sii(
    report.sii,
    logical_base,
  )
  let merged_startup_mailbox_commands = merge_startup_mailbox_commands(
    derive_startup_mailbox_commands(report.sii),
    report.startup_mailbox_commands,
  )
  let startup_outputs = derive_startup_outputs_with_commands(
    mapping,
    report.sii,
    merged_startup_mailbox_commands,
  )
  let startup_mailbox_commands = filter_redundant_startup_mailbox_commands(
    merged_startup_mailbox_commands,
    startup_outputs,
    mapping,
    report.sii,
  )
  {
    mapping,
    dc_cycle_period_ns: preferred_dc_cycle_period(report.sii),
    startup_outputs,
    startup_mailbox_commands,
    mailbox_config: @mailbox.MailboxConfig::from_sii(report.header),
    sii: report.sii,
    sii_categories: report.categories,
    prefer_live_pdo_state: true,
  }
}

///|
fn startup_mailbox_command_matches_target(
  lhs : StartupMailboxCommand,
  rhs : StartupMailboxCommand,
) -> Bool {
  lhs.transition == rhs.transition &&
  lhs.index == rhs.index &&
  lhs.subindex == rhs.subindex
}

///|
fn merge_startup_mailbox_commands(
  derived : Array[StartupMailboxCommand],
  explicit : Array[StartupMailboxCommand],
) -> Array[StartupMailboxCommand] {
  let merged : Array[StartupMailboxCommand] = []
  for command in derived {
    merged.push(command)
  }
  for command in explicit {
    let mut replaced = false
    for i = 0; i < merged.length(); i = i + 1 {
      if startup_mailbox_command_matches_target(merged[i], command) {
        if merged[i].data != command.data {
          merged[i] = command
        }
        replaced = true
        break
      }
    }
    if !replaced {
      merged.push(command)
    }
  }
  merged
}

///|
fn startup_command_reconfigures_pdo_mapping(
  command : StartupMailboxCommand,
) -> Bool {
  if command.transition != PreOpToSafeOp {
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
  commands : Array[StartupMailboxCommand],
) -> Bool {
  for command in commands {
    if startup_command_reconfigures_pdo_mapping(command) {
      return true
    }
  }
  false
}

///|
fn filter_live_pdo_reconfiguration_commands(
  commands : Array[StartupMailboxCommand],
) -> Array[StartupMailboxCommand] {
  let filtered : Array[StartupMailboxCommand] = []
  for command in commands {
    if !startup_command_reconfigures_pdo_mapping(command) {
      filtered.push(command)
    }
  }
  filtered
}

///|
pub fn startup_preparation_from_esi_json(
  json_content : String,
  device_index : Int,
  logical_base : UInt,
) -> SlaveStartupPreparation raise @hal.EcError {
  startup_preparation_from_esi_offline_report(
    offline_sii_report_from_esi_json(json_content, device_index),
    logical_base,
  )
}

///|
pub fn run_startup_preparation_from_slave_preparations(
  slave_preparations : Array[(UInt, SlaveStartupPreparation)],
  logical_base : UInt,
) -> RunStartupPreparation raise @hal.EcError {
  let slave_mappings : Array[(@mailbox.SlaveMapping, UInt)] = []
  let startup_outputs : Array[(UInt, Bytes)] = []
  let startup_mailbox_plans : Array[StationStartupMailboxPlan] = []
  let esm_timeout_policies : Array[(UInt, @protocol.EsmTimeoutPolicy)] = []
  let mut dc_cycle_period_ns : Int64? = None
  let mut any_not_lrw = false
  for item in slave_preparations {
    let (station, preparation) = item
    slave_mappings.push((preparation.mapping, station))
    if sii_prefers_not_lrw(preparation.sii) {
      any_not_lrw = true
    }
    match preparation.startup_outputs {
      Some(outputs) => startup_outputs.push((station, outputs))
      None => ()
    }
    if preparation.startup_mailbox_commands.length() > 0 {
      startup_mailbox_plans.push({
        station,
        mailbox_config: preparation.mailbox_config,
        commands: preparation.startup_mailbox_commands,
      })
    }
    dc_cycle_period_ns = prefer_dc_cycle_period(
      dc_cycle_period_ns,
      preparation.dc_cycle_period_ns,
    )
    esm_timeout_policies.push(
      (
        station,
        @protocol.esm_timeout_policy_from_sii_timeouts(preparation.sii.timeouts),
      ),
    )
  }
  let pdo_ctx = @protocol.PdoContext::build(slave_mappings, logical_base)
  pdo_ctx.block_lrw = any_not_lrw
  for i = 0; i < startup_outputs.length(); i = i + 1 {
    let (station, outputs) = startup_outputs[i]
    pdo_ctx.set_slave_outputs(station, outputs)
  }
  {
    pdo_ctx,
    expected_wkc: expected_wkc_from_slave_mappings(slave_mappings),
    dc_cycle_period_ns,
    startup_mailbox_plans,
    esm_timeout_policies,
    slave_preparations: Some(slave_preparations),
  }
}

///|
fn[N : @hal.Nic] refine_run_startup_preparation_override_in_preop(
  nic : N,
  slave_preparations : Array[(UInt, SlaveStartupPreparation)],
  logical_base : UInt,
  timeout : @hal.Duration,
) -> RunStartupPreparation raise @hal.EcError {
  let refined_preparations : Array[(UInt, SlaveStartupPreparation)] = []
  let mut current_logical_base = logical_base
  for item in slave_preparations {
    let (station, preparation) = item
    let snapshot_result : Result[@protocol.EsmStatusSnapshot, Error] = try? @protocol.read_al_status_snapshot(
      nic, station, timeout,
    )
    let refined = match snapshot_result {
      Ok(snapshot) if snapshot.state == @protocol.PreOp &&
        !snapshot.error_indication &&
        startup_mailbox_commands_need_preop_refinement(
          preparation.startup_mailbox_commands,
        ) =>
        refine_startup_preparation_in_preop(
          nic, station, current_logical_base, preparation, timeout,
        )
      _ => preparation
    }
    refined_preparations.push((station, refined))
    current_logical_base = current_logical_base +
      refined.mapping.output_bytes.reinterpret_as_uint() +
      refined.mapping.input_bytes.reinterpret_as_uint()
  }
  run_startup_preparation_from_slave_preparations(
    refined_preparations, logical_base,
  )
}

///|
fn decode_le_u32_payload(payload : Bytes) -> UInt? {
  if payload.length() <= 0 {
    return None
  }
  let mut value = 0U
  let limit = if payload.length() < 4 { payload.length() } else { 4 }
  for i = 0; i < limit; i = i + 1 {
    value = value | (payload[i].to_int().reinterpret_as_uint() << (i * 8))
  }
  Some(value)
}

///|
fn[N : @hal.Nic] sdo_upload_payload_retry(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  @protocol.sdo_upload_retry(
    nic, station, mailbox_config, rmsm, index, subindex, timeout,
  )
}

///|
fn[N : @hal.Nic] sdo_upload_u32_retry(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let payload = sdo_upload_payload_retry(
    nic, station, mailbox_config, rmsm, index, subindex, timeout,
  )
  match decode_le_u32_payload(payload) {
    Some(value) => value
    None =>
      raise @hal.EcError::MailboxProtocol(
        "SDO upload returned empty payload at 0x" +
        index.to_string() +
        ":" +
        subindex.to_int().to_string(),
      )
  }
}

///|
fn[N : @hal.Nic] assigned_pdo_indices(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  assignment_index : UInt,
  timeout : @hal.Duration,
) -> Array[UInt] raise @hal.EcError {
  let count = sdo_upload_u32_retry(
    nic, station, mailbox_config, rmsm, assignment_index, b'\x00', timeout,
  ).reinterpret_as_int()
  let indices : Array[UInt] = []
  for i = 1; i <= count; i = i + 1 {
    let pdo_index = sdo_upload_u32_retry(
      nic,
      station,
      mailbox_config,
      rmsm,
      assignment_index,
      i.to_byte(),
      timeout,
    )
    indices.push(pdo_index & 0xFFFFU)
  }
  indices
}

///|
fn[N : @hal.Nic] mapped_pdo_bit_length(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  pdo_index : UInt,
  timeout : @hal.Duration,
) -> Int raise @hal.EcError {
  let count = sdo_upload_u32_retry(
    nic, station, mailbox_config, rmsm, pdo_index, b'\x00', timeout,
  ).reinterpret_as_int()
  let mut total_bits = 0
  for i = 1; i <= count; i = i + 1 {
    let entry = sdo_upload_u32_retry(
      nic,
      station,
      mailbox_config,
      rmsm,
      pdo_index,
      i.to_byte(),
      timeout,
    )
    total_bits = total_bits + (entry & 0xFFU).reinterpret_as_int()
  }
  total_bits
}

///|
fn[N : @hal.Nic] active_process_data_lengths_in_preop(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  timeout : @hal.Duration,
) -> (Int?, Int?) raise @hal.EcError {
  let rmsm = @mailbox.Rmsm::new()
  let rx_assignments = assigned_pdo_indices(
    nic, station, mailbox_config, rmsm, 0x1C12U, timeout,
  )
  let tx_assignments = assigned_pdo_indices(
    nic, station, mailbox_config, rmsm, 0x1C13U, timeout,
  )
  let mut output_bits = 0
  for pdo_index in rx_assignments {
    output_bits = output_bits +
      mapped_pdo_bit_length(
        nic, station, mailbox_config, rmsm, pdo_index, timeout,
      )
  }
  let mut input_bits = 0
  for pdo_index in tx_assignments {
    input_bits = input_bits +
      mapped_pdo_bit_length(
        nic, station, mailbox_config, rmsm, pdo_index, timeout,
      )
  }
  (
    if output_bits > 0 {
      Some((output_bits + 7) / 8)
    } else {
      None
    },
    if input_bits > 0 {
      Some((input_bits + 7) / 8)
    } else {
      None
    },
  )
}

///|
fn map_with_process_data_lengths(
  mapping : @mailbox.SlaveMapping,
  logical_base : UInt,
  output_bytes : Int?,
  input_bytes : Int?,
) -> @mailbox.SlaveMapping {
  let patched_sm_configs : Array[@mailbox.SmConfig] = []
  for sm in mapping.sm_configs {
    patched_sm_configs.push(
      match sm.sm_type {
        @mailbox.ProcessDataOut | @mailbox.DynamicProcessDataOut =>
          match output_bytes {
            Some(length) => { ..sm, length: length.reinterpret_as_uint() }
            None => sm
          }
        @mailbox.ProcessDataIn | @mailbox.DynamicProcessDataIn =>
          match input_bytes {
            Some(length) => { ..sm, length: length.reinterpret_as_uint() }
            None => sm
          }
        _ => sm
      },
    )
  }
  let directions : Array[@mailbox.FmmuDirection] = []
  for fmmu in mapping.fmmu_configs {
    directions.push(fmmu.direction)
  }
  let (fmmu_configs, total_output, total_input) = @mailbox.calculate_fmmu_configs(
    directions, patched_sm_configs, logical_base,
  )
  {
    sm_configs: patched_sm_configs,
    fmmu_configs,
    output_bytes: total_output,
    input_bytes: total_input,
  }
}

///|
fn has_process_data_length_override(
  output_bytes : Int?,
  input_bytes : Int?,
) -> Bool {
  output_bytes is Some(_) || input_bytes is Some(_)
}

///|
fn should_retry_process_data_lengths_after_mailbox_refresh(
  result : Result[(Int?, Int?), Error],
) -> Bool {
  match result {
    Ok((output_bytes, input_bytes)) =>
      !has_process_data_length_override(output_bytes, input_bytes)
    Err(@hal.EcError::MailboxTimeout) => true
    Err(@hal.EcError::MailboxProtocol(message)) =>
      message.contains("deactivated/reset")
    Err(_) => false
  }
}

///|
fn[N : @hal.Nic] active_process_data_lengths_after_mailbox_refresh(
  nic : N,
  station : UInt,
  preparation : SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> (Int?, Int?) raise @hal.EcError {
  write_mailbox_mapping(nic, station, preparation.mapping, timeout)
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  if snapshot.error_indication {
    ignore(@protocol.recover_al_error_for_transition(nic, station, timeout))
  }
  if snapshot.state != @protocol.PreOp {
    let policy = @protocol.esm_timeout_policy_from_sii_timeouts(
      preparation.sii.timeouts,
    )
    ignore(
      @protocol.transition_to_target_strict_with_timeout_policy(
        nic,
        station,
        @protocol.PreOp,
        policy,
        timeout,
      ),
    )
  }
  return active_process_data_lengths_in_preop(
    nic,
    station,
    preparation.mailbox_config,
    timeout,
  )
}

///|
pub fn[N : @hal.Nic] refine_startup_preparation_in_preop(
  nic : N,
  station : UInt,
  logical_base : UInt,
  preparation : SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> SlaveStartupPreparation {
  if !preparation.prefer_live_pdo_state {
    return preparation
  }
  let direct_lengths_result : Result[(Int?, Int?), Error] = try? active_process_data_lengths_in_preop(
    nic,
    station,
    preparation.mailbox_config,
    timeout,
  )
  let lengths_result : Result[(Int?, Int?), Error] = if should_retry_process_data_lengths_after_mailbox_refresh(
      direct_lengths_result,
    ) {
    try? active_process_data_lengths_after_mailbox_refresh(
      nic, station, preparation, timeout,
    )
  } else {
    direct_lengths_result
  }
  match lengths_result {
    Ok((output_bytes, input_bytes)) => {
      let saw_live_pdo_assignments = output_bytes is Some(_) ||
        input_bytes is Some(_)
      let startup_mailbox_commands = if saw_live_pdo_assignments {
        filter_live_pdo_reconfiguration_commands(
          preparation.startup_mailbox_commands,
        )
      } else {
        preparation.startup_mailbox_commands
      }
      let has_override = has_process_data_length_override(
        output_bytes, input_bytes,
      )
      if !has_override {
        if startup_mailbox_commands.length() ==
          preparation.startup_mailbox_commands.length() {
          preparation
        } else {
          { ..preparation, startup_mailbox_commands, }
        }
      } else {
        let mapping = map_with_process_data_lengths(
          preparation.mapping,
          logical_base,
          output_bytes,
          input_bytes,
        )
        let startup_outputs = derive_startup_outputs_with_commands(
          mapping,
          preparation.sii,
          startup_mailbox_commands,
        )
        {
          ..preparation,
          mapping,
          startup_outputs,
          startup_mailbox_commands: filter_redundant_startup_mailbox_commands(
            startup_mailbox_commands,
            startup_outputs,
            mapping,
            preparation.sii,
          ),
        }
      }
    }
    Err(_) => preparation
  }
}

///|
fn[N : @hal.Nic] build_run_startup_preparation_from_preop(
  nic : N,
  stations : Array[UInt],
  logical_base : UInt,
  timeout : @hal.Duration,
) -> RunStartupPreparation raise @hal.EcError {
  let slave_mappings : Array[(@mailbox.SlaveMapping, UInt)] = []
  let startup_outputs : Array[(UInt, Bytes)] = []
  let startup_mailbox_plans : Array[StationStartupMailboxPlan] = []
  let esm_timeout_policies : Array[(UInt, @protocol.EsmTimeoutPolicy)] = []
  let mut current_logical_base = logical_base
  let mut dc_cycle_period_ns : Int64? = None
  let mut any_not_lrw = false
  for station in stations {
    let initial = prepare_slave_startup(
      nic, station, current_logical_base, startup_eeprom_word_count, timeout,
    )
    let snapshot_result : Result[@protocol.EsmStatusSnapshot, Error] = try? @protocol.read_al_status_snapshot(
      nic, station, timeout,
    )
    let refined = match snapshot_result {
      Ok(snapshot) if snapshot.state == @protocol.PreOp &&
        !snapshot.error_indication &&
        startup_mailbox_commands_need_preop_refinement(
          initial.startup_mailbox_commands,
        ) =>
        refine_startup_preparation_in_preop(
          nic, station, current_logical_base, initial, timeout,
        )
      _ => initial
    }
    slave_mappings.push((refined.mapping, station))
    if sii_prefers_not_lrw(refined.sii) {
      any_not_lrw = true
    }
    match refined.startup_outputs {
      Some(outputs) => startup_outputs.push((station, outputs))
      None => ()
    }
    if refined.startup_mailbox_commands.length() > 0 {
      startup_mailbox_plans.push({
        station,
        mailbox_config: refined.mailbox_config,
        commands: refined.startup_mailbox_commands,
      })
    }
    dc_cycle_period_ns = prefer_dc_cycle_period(
      dc_cycle_period_ns,
      refined.dc_cycle_period_ns,
    )
    esm_timeout_policies.push(
      (
        station,
        @protocol.esm_timeout_policy_from_sii_timeouts(refined.sii.timeouts),
      ),
    )
    current_logical_base = current_logical_base +
      refined.mapping.output_bytes.reinterpret_as_uint() +
      refined.mapping.input_bytes.reinterpret_as_uint()
  }
  let pdo_ctx = @protocol.PdoContext::build(slave_mappings, logical_base)
  pdo_ctx.block_lrw = any_not_lrw
  for i = 0; i < startup_outputs.length(); i = i + 1 {
    let (station, outputs) = startup_outputs[i]
    pdo_ctx.set_slave_outputs(station, outputs)
  }
  {
    pdo_ctx,
    expected_wkc: expected_wkc_from_slave_mappings(slave_mappings),
    dc_cycle_period_ns,
    startup_mailbox_plans,
    esm_timeout_policies,
    slave_preparations: None,
  }
}

///|
fn ds402_mode_command_seed_data(
  commands : Array[StartupMailboxCommand],
  rx_pdos : Array[@mailbox.SiiPdo],
) -> Bytes? {
  let mut explicit_seed : Bytes? = None
  for command in commands {
    if command.transition == SafeOpToOp &&
      command.index == 0x6060U &&
      command.subindex == b'\x00' &&
      command.data.length() > 0 {
      explicit_seed = Some(command.data)
    }
  }
  match explicit_seed {
    Some(_) => explicit_seed
    None =>
      match preferred_ds402_mode_seed(rx_pdos) {
        Some(mode_value) if mode_value != b'\x00' =>
          Some(Bytes::from_array([mode_value]))
        _ => None
      }
  }
}

///|
fn ds402_mode_seed_bytes_for_length(
  mode_data : Bytes,
  mapped_bit_length : Int,
) -> Bytes? {
  if mode_data.length() <= 0 {
    return None
  }
  if mapped_bit_length == 8 {
    return Some(Bytes::from_array([mode_data[0]]))
  }
  if mapped_bit_length == 16 {
    return Some(
      Bytes::from_array([
        mode_data[0],
        if mode_data.length() > 1 {
          mode_data[1]
        } else {
          b'\x00'
        },
      ]),
    )
  }
  None
}

///|
fn bytes_match_at_offset(
  actual : Bytes,
  offset : Int,
  expected : Bytes,
) -> Bool {
  if offset < 0 || offset + expected.length() > actual.length() {
    return false
  }
  for i = 0; i < expected.length(); i = i + 1 {
    if actual[offset + i] != expected[i] {
      return false
    }
  }
  true
}

///|
fn derive_startup_outputs_with_commands(
  mapping : @mailbox.SlaveMapping,
  sii : @mailbox.SiiFullInfo,
  startup_mailbox_commands : Array[StartupMailboxCommand],
) -> Bytes? {
  if mapping.output_bytes <= 0 {
    return None
  }
  guard sii.general is Some(general) else { return None }
  if general.ds402_channels == b'\x00' {
    return None
  }
  let rx_pdos = sii.rx_pdo
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
      ds402_mode_command_seed_data(startup_mailbox_commands, rx_pdos),
    ) {
    (Some((mode_offset, mode_length)), Some(mode_data)) =>
      match ds402_mode_seed_bytes_for_length(mode_data, mode_length) {
        Some(mode_seed) if mode_offset + mode_seed.length() <=
          mapping.output_bytes => {
          for i = 0; i < mode_seed.length(); i = i + 1 {
            seed[mode_offset + i] = mode_seed[i]
          }
          wrote = true
        }
        _ => ()
      }
    _ => ()
  }
  if !wrote {
    return None
  }
  Some(Bytes::from_array(seed))
}

///|
fn derive_startup_outputs(
  mapping : @mailbox.SlaveMapping,
  sii : @mailbox.SiiFullInfo,
) -> Bytes? {
  derive_startup_outputs_with_commands(
    mapping,
    sii,
    derive_startup_mailbox_commands(sii),
  )
}

///|
fn redundant_ds402_mode_command_seeded_in_outputs(
  command : StartupMailboxCommand,
  startup_outputs : Bytes?,
  sii : @mailbox.SiiFullInfo,
) -> Bool {
  if command.transition != SafeOpToOp ||
    command.index != 0x6060U ||
    command.subindex != b'\x00' ||
    command.data.length() <= 0 {
    return false
  }
  guard startup_outputs is Some(outputs) else { return false }
  match find_pdo_entry_byte_offset(sii.rx_pdo, 0x6060U, b'\x00') {
    Some((offset, length)) =>
      match ds402_mode_seed_bytes_for_length(command.data, length) {
        Some(expected_seed) =>
          bytes_match_at_offset(outputs, offset, expected_seed)
        None => false
      }
    None => false
  }
}

///|
fn ds402_mode_command_outside_process_image(
  command : StartupMailboxCommand,
  mapping : @mailbox.SlaveMapping,
  sii : @mailbox.SiiFullInfo,
) -> Bool {
  if command.transition != SafeOpToOp ||
    command.index != 0x6060U ||
    command.subindex != b'\x00' ||
    command.data.length() <= 0 {
    return false
  }
  match find_pdo_entry_byte_offset(sii.rx_pdo, 0x6060U, b'\x00') {
    Some((offset, length)) => offset + (length + 7) / 8 > mapping.output_bytes
    None => false
  }
}

///|
fn filter_redundant_startup_mailbox_commands(
  commands : Array[StartupMailboxCommand],
  startup_outputs : Bytes?,
  mapping : @mailbox.SlaveMapping,
  sii : @mailbox.SiiFullInfo,
) -> Array[StartupMailboxCommand] {
  let filtered : Array[StartupMailboxCommand] = []
  for command in commands {
    if !redundant_ds402_mode_command_seeded_in_outputs(
        command, startup_outputs, sii,
      ) &&
      !ds402_mode_command_outside_process_image(command, mapping, sii) {
      filtered.push(command)
    }
  }
  filtered
}

///|
fn derive_startup_mailbox_commands(
  sii : @mailbox.SiiFullInfo,
) -> Array[StartupMailboxCommand] {
  let commands : Array[StartupMailboxCommand] = []
  if sii.general is Some(general) {
    if general.supports_coe_pdo_configuration() {
      for pdo in sii.rx_pdo {
        commands.push({
          transition: PreOpToSafeOp,
          index: pdo.pdo_index,
          subindex: b'\x00',
          data: pdo_complete_access_data(pdo),
        })
      }
      for pdo in sii.tx_pdo {
        commands.push({
          transition: PreOpToSafeOp,
          index: pdo.pdo_index,
          subindex: b'\x00',
          data: pdo_complete_access_data(pdo),
        })
      }
    }
    if general.supports_coe_pdo_assign() {
      commands.push({
        transition: PreOpToSafeOp,
        index: 0x1C12U,
        subindex: b'\x00',
        data: sm_assignment_complete_access_data(sii.rx_pdo, b'\x02'),
      })
      commands.push({
        transition: PreOpToSafeOp,
        index: 0x1C13U,
        subindex: b'\x00',
        data: sm_assignment_complete_access_data(sii.tx_pdo, b'\x03'),
      })
    }
    if general.ds402_channels != b'\x00' {
      let rx_pdos = sii.rx_pdo
      match preferred_ds402_mode_seed(rx_pdos) {
        Some(mode_value) if mode_value != b'\x00' =>
          commands.push({
            transition: SafeOpToOp,
            index: 0x6060U,
            subindex: b'\x00',
            data: Bytes::from_array([mode_value]),
          })
        _ => ()
      }
    }
  }
  commands
}

///|
fn pdo_mapping_entry_u32(entry : @mailbox.SiiPdoEntry) -> UInt {
  (entry.entry_index << 16) |
  (entry.subindex.to_uint() << 8) |
  entry.bit_length.to_uint()
}

///|
fn pdo_complete_access_data(pdo : @mailbox.SiiPdo) -> Bytes {
  let buf = @buffer.new(size_hint=1 + pdo.entries.length() * 4)
  buf.write_byte(pdo.entry_count)
  for entry in pdo.entries {
    let mapping = pdo_mapping_entry_u32(entry)
    buf.write_byte((mapping & 0xFFU).to_byte())
    buf.write_byte(((mapping >> 8) & 0xFFU).to_byte())
    buf.write_byte(((mapping >> 16) & 0xFFU).to_byte())
    buf.write_byte(((mapping >> 24) & 0xFFU).to_byte())
  }
  buf.to_bytes()
}

///|
fn sm_assignment_complete_access_data(
  pdos : Array[@mailbox.SiiPdo],
  sync_manager : Byte,
) -> Bytes {
  let selected : Array[UInt] = []
  for pdo in pdos {
    if pdo.sync_manager == sync_manager {
      selected.push(pdo.pdo_index)
    }
  }
  let buf = @buffer.new(size_hint=1 + selected.length() * 2)
  buf.write_byte(selected.length().to_byte())
  for index in selected {
    buf.write_byte((index & 0xFFU).to_byte())
    buf.write_byte(((index >> 8) & 0xFFU).to_byte())
  }
  buf.to_bytes()
}

///|
fn startup_command_uses_complete_access(
  command : StartupMailboxCommand,
) -> Bool {
  command.subindex == b'\x00' && command.data.length() > 1
}

///|
fn startup_command_subindex_sequence_entry_width(
  command : StartupMailboxCommand,
) -> Int? {
  if command.subindex != b'\x00' || command.data.length() <= 1 {
    return None
  }
  if command.index == 0x1C12U || command.index == 0x1C13U {
    return Some(2)
  }
  if (command.index >= 0x1600U && command.index <= 0x17FFU) ||
    (command.index >= 0x1A00U && command.index <= 0x1BFFU) {
    return Some(4)
  }
  None
}

///|
fn startup_command_subindex_sequence_count(
  command : StartupMailboxCommand,
  entry_width : Int,
) -> Int raise @hal.EcError {
  let count = command.data[0].to_int()
  let expected_length = 1 + count * entry_width
  if command.data.length() < expected_length {
    raise @hal.EcError::MailboxProtocol(
      "startup mailbox command payload too short for 0x" +
      command.index.to_string(radix=16) +
      ": expected at least " +
      expected_length.to_string() +
      " bytes, got " +
      command.data.length().to_string(),
    )
  }
  count
}

///|
fn startup_command_subindex_sequence_entry_data(
  command : StartupMailboxCommand,
  entry_width : Int,
  index : Int,
) -> Bytes {
  let start = 1 + index * entry_width
  Bytes::makei(entry_width, fn(offset) { command.data[start + offset] })
}

///|
fn[N : @hal.Nic] apply_startup_mailbox_subindex_sequence(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  command : StartupMailboxCommand,
  entry_width : Int,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let count = startup_command_subindex_sequence_count(command, entry_width)
  @protocol.sdo_download_retry(
    nic,
    station,
    mailbox_config,
    rmsm,
    command.index,
    b'\x00',
    Bytes::from_array([b'\x00']),
    timeout,
  )
  for i = 0; i < count; i = i + 1 {
    @protocol.sdo_download_retry(
      nic,
      station,
      mailbox_config,
      rmsm,
      command.index,
      (i + 1).to_byte(),
      startup_command_subindex_sequence_entry_data(command, entry_width, i),
      timeout,
    )
  }
  @protocol.sdo_download_retry(
    nic,
    station,
    mailbox_config,
    rmsm,
    command.index,
    b'\x00',
    Bytes::from_array([count.to_byte()]),
    timeout,
  )
}

///|
fn preferred_ds402_mode_seed(rx_pdos : Array[@mailbox.SiiPdo]) -> Byte? {
  if find_pdo_entry_byte_offset(rx_pdos, 0x607AU, b'\x00') is Some(_) {
    return Some(b'\x08')
  }
  if find_pdo_entry_byte_offset(rx_pdos, 0x60FFU, b'\x00') is Some(_) {
    return Some(b'\x09')
  }
  None
}

///|
let startup_mailbox_drain_limit : Int = 4

///|
fn[N : @hal.Nic] drain_startup_mailbox(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
) -> Unit {
  let zero_timeout = @hal.Duration(0L)
  for _drain = 0; _drain < startup_mailbox_drain_limit; _drain = _drain + 1 {
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
pub fn[N : @hal.Nic] apply_startup_mailbox_commands(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  commands : Array[StartupMailboxCommand],
  transition : StartupCommandTransition,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  if !mailbox_config.is_valid() || commands.length() <= 0 {
    return
  }
  let rmsm = @mailbox.Rmsm::new(max_retries=0)
  for command in commands {
    if command.transition != transition {
      continue
    }
    drain_startup_mailbox(nic, station, mailbox_config)
    match startup_command_subindex_sequence_entry_width(command) {
      Some(entry_width) => {
        apply_startup_mailbox_subindex_sequence(
          nic, station, mailbox_config, rmsm, command, entry_width, timeout,
        )
        continue
      }
      None => ()
    }
    if startup_command_uses_complete_access(command) {
      @protocol.sdo_download_complete_access(
        nic,
        station,
        mailbox_config,
        rmsm,
        command.index,
        command.subindex,
        command.data,
        timeout,
      )
    } else {
      @protocol.sdo_download_retry(
        nic,
        station,
        mailbox_config,
        rmsm,
        command.index,
        command.subindex,
        command.data,
        timeout,
      )
    }
  }
}

///|
pub fn[N : @hal.Nic] apply_presafeop_startup_mailbox_commands(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  commands : Array[StartupMailboxCommand],
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  apply_startup_mailbox_commands(
    nic,
    station,
    mailbox_config,
    commands,
    PreOpToSafeOp,
    timeout,
  )
}

///|
pub fn[N : @hal.Nic] apply_safeop_startup_mailbox_commands(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  commands : Array[StartupMailboxCommand],
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  apply_startup_mailbox_commands(
    nic,
    station,
    mailbox_config,
    commands,
    SafeOpToOp,
    timeout,
  )
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
fn preferred_dc_cycle_period(sii : @mailbox.SiiFullInfo) -> Int64? {
  match preferred_sii_dc_clock(sii.dc_clocks) {
    Some(clock) => dc_cycle_period_ns(clock)
    None => None
  }
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
fn mailbox_sm_field_matches(expected : Bytes, actual : Bytes) -> Bool {
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
fn mailbox_sm_hex_byte(value : Byte) -> String {
  let digits = "0123456789ABCDEF"
  digits[(value.to_int() >> 4) & 0xF].to_string() +
  digits[value.to_int() & 0xF].to_string()
}

///|
fn mailbox_sm_hex(bytes : Bytes) -> String {
  let mut rendered = "0x"
  for i = 0; i < bytes.length(); i = i + 1 {
    rendered = rendered + mailbox_sm_hex_byte(bytes[i])
  }
  rendered
}

///|
fn[N : @hal.Nic] verify_mailbox_sm_readback(
  nic : N,
  station : UInt,
  sm_index : Int,
  expected : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let sm_addr = @protocol.reg_sm_base +
    sm_index.reinterpret_as_uint() *
    @protocol.sm_entry_size.reinterpret_as_uint()
  let actual = @protocol.read_register_fp(
      nic, station, sm_addr, @protocol.sm_entry_size, timeout,
    ).data
  if !mailbox_sm_field_matches(expected, actual) {
    raise @hal.EcError::MailboxProtocol(
      "mailbox SyncManager readback mismatch at SM" +
      sm_index.to_string() +
      ": expected=" +
      mailbox_sm_hex(expected) +
      " actual=" +
      mailbox_sm_hex(actual),
    )
  }
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
        let expected = sm.to_bytes()
        let _ = @protocol.write_register_fp(
          nic, station, sm_addr, expected, timeout,
        )
        verify_mailbox_sm_readback(nic, station, i, expected, timeout)
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
      @mailbox.ProcessDataOut
      | @mailbox.ProcessDataIn
      | @mailbox.DynamicProcessDataOut
      | @mailbox.DynamicProcessDataIn => {
        let sm_addr = @protocol.reg_sm_base +
          i.reinterpret_as_uint() *
          @protocol.sm_entry_size.reinterpret_as_uint()
        let deactivated = { ..sm, activate: sm.activate & b'\xFE' }
        if deactivated.activate != sm.activate {
          let _ = @protocol.write_register_fp(
            nic,
            station,
            sm_addr,
            deactivated.to_bytes(),
            timeout,
          )
        }
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
  run_with_states_and_settings_impl(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    settings,
    @protocol.Op,
    Some(@protocol.Init),
    None,
    None,
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
  run_with_states_and_settings_prepared_reporting_to(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    settings,
    startup_state,
    shutdown_state,
    None,
    timeout,
    NullRunProgressSink::new(),
  )
}

///|
pub fn[N : @hal.Nic, S : RunProgressSink] run_with_states_and_settings_prepared_reporting_to(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  settings : RunLoopSettings,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  startup_preparation_override : RunStartupPreparation?,
  timeout : @hal.Duration,
  sink : S,
) -> RunReport raise @hal.EcError {
  run_with_states_and_settings_impl(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    settings,
    startup_state,
    shutdown_state,
    startup_preparation_override,
    None,
    timeout,
    sink,
  )
}

///|
pub fn[N : @hal.Nic, S : RunProgressSink] run_with_scan_and_states_and_settings_prepared_reporting_to(
  nic : N,
  scan_report : ScanReport,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  settings : RunLoopSettings,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  startup_preparation_override : RunStartupPreparation?,
  timeout : @hal.Duration,
  sink : S,
) -> RunReport raise @hal.EcError {
  run_with_states_and_settings_impl(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    settings,
    startup_state,
    shutdown_state,
    startup_preparation_override,
    Some(scan_report),
    timeout,
    sink,
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
  run_with_states_and_settings_prepared_reporting_to(
    nic,
    config,
    expected,
    pdo_ctx,
    expected_wkc,
    settings,
    startup_state,
    shutdown_state,
    None,
    timeout,
    sink,
  )
}

///|
fn[N : @hal.Nic, S : RunProgressSink] run_with_states_and_settings_impl(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  settings : RunLoopSettings,
  startup_state : @protocol.EsmState,
  shutdown_state : @protocol.EsmState?,
  startup_preparation_override : RunStartupPreparation?,
  scan_report_override : ScanReport?,
  timeout : @hal.Duration,
  sink : S,
) -> RunReport raise @hal.EcError {
  let run_config = resolve_run_loop_config(config, settings)
  let progress_every_cycles = resolve_progress_every_cycles(
    run_config, settings,
  )
  let mut active_pdo_ctx = pdo_ctx
  let mut active_expected_wkc = expected_wkc
  let mut active_startup_mailbox_plans : Array[StationStartupMailboxPlan] = []
  let mut active_startup_slave_preparations : Array[
    (UInt, SlaveStartupPreparation),
  ]? = None
  let mut active_esm_timeout_policies : Array[
    (UInt, @protocol.EsmTimeoutPolicy),
  ] = []
  let mut startup_preop_ready = false
  let scan_report = match scan_report_override {
    Some(report) => report
    None => scan(nic, timeout)
  }
  let has_discovered_slaves = scan_report.slave_count > 0
  let stations = scan_report.slaves.map(fn(slave) { slave.station_address })

  let validate_report = validate(scan_report, expected)
  if !validate_report.all_ok {
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
    if startup_state == @protocol.SafeOp || startup_state == @protocol.Op {
      let preop_fault = match startup_preparation_override {
        Some(prepared) =>
          match prepared.slave_preparations {
            Some(slave_preparations) =>
              transition_stations_to_preop_with_preparations(
                nic,
                slave_preparations,
                timeout,
                prepared.esm_timeout_policies,
              )
            None =>
              transition_stations_to_preop_with_mailbox(
                nic, stations, timeout, active_esm_timeout_policies,
              )
          }
        None =>
          transition_stations_to_preop_with_mailbox(
            nic, stations, timeout, active_esm_timeout_policies,
          )
      }
      match preop_fault {
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
      let resolved_preparation = match startup_preparation_override {
        Some(prepared) =>
          match prepared.slave_preparations {
            Some(slave_preparations) =>
              refine_run_startup_preparation_override_in_preop(
                nic,
                slave_preparations,
                pdo_ctx.logical_base,
                timeout,
              )
            None => prepared
          }
        None =>
          build_run_startup_preparation_from_preop(
            nic,
            stations,
            pdo_ctx.logical_base,
            timeout,
          )
      }
      if resolved_preparation.pdo_ctx.logical_size > 0 ||
        resolved_preparation.expected_wkc > 0U ||
        (active_pdo_ctx.logical_size <= 0 && active_expected_wkc == 0U) {
        active_pdo_ctx = resolved_preparation.pdo_ctx
        active_expected_wkc = resolved_preparation.expected_wkc
      }
      active_startup_mailbox_plans = resolved_preparation.startup_mailbox_plans
      active_startup_slave_preparations = resolved_preparation.slave_preparations
      active_esm_timeout_policies = resolved_preparation.esm_timeout_policies
      startup_preop_ready = true
    }
    let startup_fault = transition_stations_for_startup(
      nic, stations, startup_state, active_pdo_ctx, active_startup_mailbox_plans,
      active_startup_slave_preparations, run_config, timeout, startup_preop_ready,
      active_esm_timeout_policies,
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
  rt.configure_pdo(active_pdo_ctx, active_expected_wkc)
  // Configure emergency polling for all stations with mailbox support.
  let emg_stations : Array[(UInt, @mailbox.MailboxConfig)] = []
  for plan in active_startup_mailbox_plans {
    emg_stations.push((plan.station, plan.mailbox_config))
  }
  rt.configure_emergency_stations(emg_stations)

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
        ignore(
          transition_stations_to_target(
            nic, stations, target, timeout, active_esm_timeout_policies,
          ),
        )
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
  steps.push(ValidateSmWatchdog)
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
          ignore(
            try? @protocol.recover_al_error_for_transition(
              nic, station, timeout,
            ),
          )
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
fn startup_snapshot_from_request_observation(
  observation : @protocol.EsmStateRequestObservation,
) -> @protocol.EsmStatusSnapshot {
  {
    state: observation.state,
    error_indication: observation.error_indication,
    status_code: observation.status_code,
  }
}

///|
fn startup_transition_failed_fault(
  station : UInt,
  target : @protocol.EsmState,
  snapshot : @protocol.EsmStatusSnapshot?,
  observation : @protocol.EsmStateRequestObservation?,
) -> RunFault {
  let current = match snapshot {
    Some(value) => Some(value.state)
    None => observation.map(fn(value) { value.state })
  }
  let error_indication = match snapshot {
    Some(value) => Some(value.error_indication)
    None => observation.map(fn(value) { value.error_indication })
  }
  let status_code = match snapshot {
    Some(value) =>
      match value.status_code {
        Some(_) => value.status_code
        None => observation.bind(fn(item) { item.status_code })
      }
    None => observation.bind(fn(value) { value.status_code })
  }
  RunFault::StartupTransitionFailed(
    station~,
    target~,
    current~,
    error_indication~,
    status_code~,
    raw_status_code=observation.bind(fn(value) { value.raw_status_code }),
    control_wkc=observation.map(fn(value) { value.control_wkc }),
  )
}

///|
fn startup_mailbox_transition_target(
  transition : StartupCommandTransition,
) -> @protocol.EsmState {
  match transition {
    InitToPreOp => @protocol.PreOp
    InitToBoot => @protocol.Boot
    PreOpToInit => @protocol.Init
    PreOpToSafeOp => @protocol.SafeOp
    SafeOpToInit => @protocol.Init
    SafeOpToPreOp => @protocol.PreOp
    SafeOpToOp => @protocol.Op
    OpToInit => @protocol.Init
    OpToPreOp => @protocol.PreOp
    OpToSafeOp => @protocol.SafeOp
    BootToInit => @protocol.Init
  }
}

///|
fn startup_mailbox_transition_current(
  transition : StartupCommandTransition,
) -> @protocol.EsmState? {
  match transition {
    InitToPreOp => Some(@protocol.Init)
    InitToBoot => Some(@protocol.Init)
    PreOpToInit => Some(@protocol.PreOp)
    PreOpToSafeOp => Some(@protocol.PreOp)
    SafeOpToInit => Some(@protocol.SafeOp)
    SafeOpToPreOp => Some(@protocol.SafeOp)
    SafeOpToOp => Some(@protocol.SafeOp)
    OpToInit => Some(@protocol.Op)
    OpToPreOp => Some(@protocol.Op)
    OpToSafeOp => Some(@protocol.Op)
    BootToInit => Some(@protocol.Boot)
  }
}

///|
fn[N : @hal.Nic] startup_mailbox_plan_failed_fault(
  nic : N,
  station : UInt,
  transition : StartupCommandTransition,
  timeout : @hal.Duration,
) -> RunFault {
  let target = startup_mailbox_transition_target(transition)
  let snapshot = read_startup_fault_details(nic, station, timeout)
  match snapshot {
    Some(_) => startup_transition_failed_fault(station, target, snapshot, None)
    None =>
      RunFault::StartupTransitionFailed(
        station~,
        target~,
        current=startup_mailbox_transition_current(transition),
        error_indication=None,
        status_code=None,
        raw_status_code=None,
        control_wkc=None,
      )
  }
}

///|
fn[N : @hal.Nic] transition_stations_for_startup(
  nic : N,
  stations : Array[UInt],
  startup_state : @protocol.EsmState,
  pdo_ctx : @protocol.PdoContext,
  startup_mailbox_plans : Array[StationStartupMailboxPlan],
  startup_slave_preparations : Array[(UInt, SlaveStartupPreparation)]?,
  run_config : @hal.MasterConfig,
  timeout : @hal.Duration,
  preop_ready : Bool,
  esm_policies : Array[(UInt, @protocol.EsmTimeoutPolicy)],
) -> RunFault? {
  if startup_state == @protocol.PreOp {
    if preop_ready {
      return None
    }
    return transition_stations_to_preop_with_mailbox(
      nic, stations, timeout, esm_policies,
    )
  }
  if startup_state == @protocol.SafeOp {
    match startup_slave_preparations {
      Some(slave_preparations) =>
        return transition_stations_to_safeop_with_preparations(
          nic, slave_preparations, timeout, preop_ready, esm_policies,
        )
      None => ()
    }
    return transition_stations_to_safeop_with_process_mapping(
      nic, stations, pdo_ctx, startup_mailbox_plans, timeout, preop_ready, esm_policies,
    )
  }
  if startup_state != @protocol.Op {
    return transition_stations_to_target(
      nic, stations, startup_state, timeout, esm_policies,
    )
  }

  let safeop_fault = match startup_slave_preparations {
    Some(slave_preparations) =>
      transition_stations_to_safeop_with_preparations(
        nic, slave_preparations, timeout, preop_ready, esm_policies,
      )
    None =>
      transition_stations_to_safeop_with_process_mapping(
        nic, stations, pdo_ctx, startup_mailbox_plans, timeout, preop_ready, esm_policies,
      )
  }
  match safeop_fault {
    Some(_) => return safeop_fault
    None => ()
  }

  let startup_mailbox_fault = apply_station_startup_mailbox_plans(
    nic,
    startup_mailbox_plans,
    SafeOpToOp,
    timeout,
  )
  match startup_mailbox_fault {
    Some(_) => return startup_mailbox_fault
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
      ValidateSmWatchdog =>
        validate_sm_watchdog_before_op(nic, stations, timeout)
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
  esm_policies : Array[(UInt, @protocol.EsmTimeoutPolicy)],
) -> RunFault? {
  for station in stations {
    let policy = lookup_esm_timeout_policy(esm_policies, station)
    let fault = transition_slave_to_preop_with_mailbox(
      nic, station, timeout, policy,
    )
    match fault {
      Some(_) => return fault
      None => ()
    }
  }
  None
}

///|
fn[N : @hal.Nic] transition_stations_to_preop_with_preparations(
  nic : N,
  slave_preparations : Array[(UInt, SlaveStartupPreparation)],
  timeout : @hal.Duration,
  esm_policies : Array[(UInt, @protocol.EsmTimeoutPolicy)],
) -> RunFault? {
  for item in slave_preparations {
    let (station, preparation) = item
    let policy = lookup_esm_timeout_policy(esm_policies, station)
    let fault = transition_slave_to_preop_with_preparation(
      nic, station, preparation, timeout, policy,
    )
    match fault {
      Some(_) => return fault
      None => ()
    }
  }
  None
}

///|
fn[N : @hal.Nic] transition_slave_to_target_strict_after_recovery(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  timeout : @hal.Duration,
) -> RunFault? {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout) catch {
    _ =>
      return Some(startup_transition_failed_fault(station, target, None, None))
  }
  if snapshot.error_indication {
    ignore(@protocol.recover_al_error_for_transition(nic, station, timeout)) catch {
      _ =>
        return Some(
          startup_transition_failed_fault(station, target, Some(snapshot), None),
        )
    }
  }
  let observation = @protocol.transition_to_target_strict_observe(
    nic, station, target, timeout,
  ) catch {
    _ => None
  }
  match observation {
    Some(value) if value.state == target => None
    Some(value) =>
      Some(
        startup_transition_failed_fault(
          station,
          target,
          Some(startup_snapshot_from_request_observation(value)),
          Some(value),
        ),
      )
    None => {
      let final_snapshot = read_startup_fault_details(nic, station, timeout)
      match final_snapshot {
        Some(value) if value.state == target => None
        _ =>
          Some(
            startup_transition_failed_fault(
              station,
              target,
              final_snapshot,
              None,
            ),
          )
      }
    }
  }
}

///|
fn[N : @hal.Nic] transition_stations_to_safeop_with_preparations(
  nic : N,
  slave_preparations : Array[(UInt, SlaveStartupPreparation)],
  timeout : @hal.Duration,
  preop_ready : Bool,
  esm_policies : Array[(UInt, @protocol.EsmTimeoutPolicy)],
) -> RunFault? {
  if !preop_ready {
    let preop_fault = transition_stations_to_preop_with_preparations(
      nic, slave_preparations, timeout, esm_policies,
    )
    match preop_fault {
      Some(_) => return preop_fault
      None => ()
    }
  }
  let stations : Array[UInt] = []
  for item in slave_preparations {
    let (station, preparation) = item
    stations.push(station)
    let current_snapshot = read_startup_fault_details(nic, station, timeout)
    match current_snapshot {
      Some(status) if !status.error_indication &&
        (status.state == @protocol.SafeOp || status.state == @protocol.Op) =>
        continue
      Some(status) if status.error_indication =>
        ignore(
          try? @protocol.recover_al_error_for_transition(nic, station, timeout),
        )
      _ => ()
    }
    let mailbox_result : Result[Unit, Error] = try? apply_startup_mailbox_commands(
      nic,
      station,
      preparation.mailbox_config,
      preparation.startup_mailbox_commands,
      PreOpToSafeOp,
      timeout,
    )
    match mailbox_result {
      Ok(_) => ()
      Err(_) =>
        return Some(
          startup_mailbox_plan_failed_fault(
            nic,
            station,
            PreOpToSafeOp,
            timeout,
          ),
        )
    }
    ignore(
      write_process_data_mapping(nic, station, preparation.mapping, timeout),
    ) catch {
      _ =>
        return Some(
          startup_transition_failed_fault(
            station,
            @protocol.SafeOp,
            read_startup_fault_details(nic, station, timeout),
            None,
          ),
        )
    }
    let safeop_fault = transition_slave_to_target_strict_after_recovery(
      nic,
      station,
      @protocol.SafeOp,
      timeout,
    )
    match safeop_fault {
      Some(_) => return safeop_fault
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
  startup_mailbox_plans : Array[StationStartupMailboxPlan],
  timeout : @hal.Duration,
  preop_ready : Bool,
  esm_policies : Array[(UInt, @protocol.EsmTimeoutPolicy)],
) -> RunFault? {
  if !preop_ready {
    let preop_fault = transition_stations_to_preop_with_mailbox(
      nic, stations, timeout, esm_policies,
    )
    match preop_fault {
      Some(_) => return preop_fault
      None => ()
    }
  }
  let presafeop_mailbox_fault = apply_station_startup_mailbox_plans(
    nic,
    startup_mailbox_plans,
    PreOpToSafeOp,
    timeout,
  )
  match presafeop_mailbox_fault {
    Some(_) => return presafeop_mailbox_fault
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
  transition_stations_to_target(
    nic,
    stations,
    @protocol.SafeOp,
    timeout,
    esm_policies,
  )
}

///|
fn[N : @hal.Nic] transition_stations_to_target(
  nic : N,
  stations : Array[UInt],
  target : @protocol.EsmState,
  timeout : @hal.Duration,
  policies : Array[(UInt, @protocol.EsmTimeoutPolicy)],
) -> RunFault? {
  for station in stations {
    let policy = lookup_esm_timeout_policy(policies, station)
    let fault = transition_slave_to_target(
      nic, station, target, timeout, policy,
    )
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
fn[N : @hal.Nic] apply_station_startup_mailbox_plans(
  nic : N,
  plans : Array[StationStartupMailboxPlan],
  transition : StartupCommandTransition,
  timeout : @hal.Duration,
) -> RunFault? {
  for plan in plans {
    let result : Result[Unit, Error] = try? apply_startup_mailbox_commands(
      nic,
      plan.station,
      plan.mailbox_config,
      plan.commands,
      transition,
      timeout,
    )
    guard result is Err(_) else { continue }
    return Some(
      startup_mailbox_plan_failed_fault(nic, plan.station, transition, timeout),
    )
  }
  None
}

///|
fn[N : @hal.Nic] transition_slave_to_target(
  nic : N,
  station : UInt,
  target : @protocol.EsmState,
  timeout : @hal.Duration,
  policy : @protocol.EsmTimeoutPolicy,
) -> RunFault? {
  let attempt = attempt_transition_slave_to_target(
    nic, station, target, timeout, policy,
  )
  if attempt.reached_target {
    None
  } else {
    let snapshot = read_startup_fault_details(nic, station, timeout)
    let strategy = classify_startup_recovery_strategy(
      snapshot.map(fn(value) { value.state }),
      target,
      match snapshot {
        Some(value) =>
          match value.status_code {
            Some(_) => value.status_code
            None => attempt.observation.bind(fn(item) { item.status_code })
          }
        None => attempt.observation.bind(fn(item) { item.status_code })
      },
    )
    stabilize_failed_startup_station(nic, station, strategy, timeout)
    if strategy == RetryTargetPath {
      let retry_attempt = attempt_transition_slave_to_target(
        nic, station, target, timeout, policy,
      )
      if retry_attempt.reached_target {
        None
      } else {
        Some(
          startup_transition_failed_fault(
            station,
            target,
            read_startup_fault_details(nic, station, timeout),
            retry_attempt.observation,
          ),
        )
      }
    } else {
      Some(
        startup_transition_failed_fault(
          station,
          target,
          snapshot,
          attempt.observation,
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
  policy : @protocol.EsmTimeoutPolicy,
) -> RunFault? {
  let preparation = prepare_slave_startup(
    nic, station, 0U, startup_eeprom_word_count, timeout,
  ) catch {
    _ =>
      return Some(
        startup_transition_failed_fault(
          station,
          @protocol.PreOp,
          read_startup_fault_details(nic, station, timeout),
          None,
        ),
      )
  }
  transition_slave_to_preop_with_preparation(
    nic, station, preparation, timeout, policy,
  )
}

///|
fn[N : @hal.Nic] transition_slave_to_preop_with_preparation(
  nic : N,
  station : UInt,
  preparation : SlaveStartupPreparation,
  timeout : @hal.Duration,
  policy : @protocol.EsmTimeoutPolicy,
) -> RunFault? {
  let current_snapshot = read_startup_fault_details(nic, station, timeout)
  match current_snapshot {
    Some(status) if !status.error_indication &&
      (
        status.state == @protocol.PreOp ||
        status.state == @protocol.SafeOp ||
        status.state == @protocol.Op
      ) => return None
    Some(status) if status.error_indication =>
      ignore(
        try? @protocol.recover_al_error_for_transition(nic, station, timeout),
      )
    _ => ()
  }
  ignore(write_mailbox_mapping(nic, station, preparation.mapping, timeout)) catch {
    _ =>
      return Some(
        startup_transition_failed_fault(
          station,
          @protocol.PreOp,
          read_startup_fault_details(nic, station, timeout),
          None,
        ),
      )
  }
  let snapshot = read_startup_fault_details(nic, station, timeout)
  match snapshot {
    Some(status) if status.error_indication =>
      ignore(
        try? @protocol.recover_al_error_for_transition(nic, station, timeout),
      )
    _ => ()
  }
  transition_slave_to_target(nic, station, @protocol.PreOp, timeout, policy)
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
  let initial = prepare_slave_startup(
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
          raw_status_code=None,
          control_wkc=None,
        ),
      )
  }
  let preparation = refine_startup_preparation_in_preop(
    nic, station, logical_base, initial, timeout,
  )
  ignore(write_process_data_mapping(nic, station, preparation.mapping, timeout)) catch {
    _ =>
      return Some(
        RunFault::StartupTransitionFailed(
          station~,
          target=@protocol.SafeOp,
          current=None,
          error_indication=None,
          status_code=None,
          raw_status_code=None,
          control_wkc=None,
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
  let observation = Some(
    @protocol.request_state_with_process_data_observe(
      nic,
      station,
      @protocol.Op,
      pdo_ctx,
      timeout,
    ),
  ) catch {
    _ => None
  }
  if observation is Some(observed) && observed.state == @protocol.Op {
    None
  } else {
    let fault_snapshot = match observation {
      Some(observed) =>
        Some(startup_snapshot_from_request_observation(observed))
      None => read_startup_fault_details(nic, station, timeout)
    }
    let strategy = classify_startup_recovery_strategy(
      fault_snapshot.map(fn(value) { value.state }),
      @protocol.Op,
      fault_snapshot.bind(fn(value) { value.status_code }),
    )
    stabilize_failed_startup_station(nic, station, strategy, timeout)
    Some(
      startup_transition_failed_fault(
        station,
        @protocol.Op,
        fault_snapshot,
        observation,
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
  policy : @protocol.EsmTimeoutPolicy,
) -> TransitionAttemptObservation {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout) catch {
    _ => return { reached_target: false, observation: None }
  }
  let active_snapshot = if snapshot.error_indication {
    @protocol.recover_al_error_for_transition(nic, station, timeout) catch {
      _ => return { reached_target: false, observation: None }
    }
  } else {
    snapshot
  }
  let observation = @protocol.transition_to_target_strict_with_timeout_policy_observe(
    nic, station, target, policy, timeout,
  ) catch {
    _ => return { reached_target: false, observation: None }
  }
  match observation {
    Some(value) =>
      { reached_target: value.state == target, observation: Some(value) }
    None =>
      { reached_target: active_snapshot.state == target, observation: None }
  }
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
/// SM Watchdog validation result for a single station.
pub(all) struct SmWatchdogValidation {
  station : UInt
  config : @protocol.SmWatchdogConfig
  watchdog_active : Bool
} derive(Eq, Debug)

///|
/// Read and validate SM Watchdog configuration for all stations before SafeOp→Op.
/// This is a diagnostic-only step: logs watchdog state per station but does not
/// block the transition. Devices without a configured SM watchdog will still
/// be promoted to Op (the ESC itself enforces watchdog-related faults via
/// AL Status Code 0x001B during runtime).
fn[N : @hal.Nic] validate_sm_watchdog_before_op(
  nic : N,
  stations : Array[UInt],
  timeout : @hal.Duration,
) -> Unit {
  for station in stations {
    let _config = @protocol.read_sm_watchdog_config(nic, station, timeout) catch {
      _ => continue
    }
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
      status_code~,
      raw_status_code~,
      control_wkc~
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
      let raw_status_text = match raw_status_code {
        Some(code) => code.to_string()
        None => "unknown"
      }
      let control_wkc_text = match control_wkc {
        Some(wkc) => wkc.to_string()
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
      status_text +
      " raw_status_code=" +
      raw_status_text +
      " control_wkc=" +
      control_wkc_text
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
