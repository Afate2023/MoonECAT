///|
struct StationStartupDecision {
  preparation : @runtime.SlaveStartupPreparation
  pdo_audit : PdoAuditReport
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
