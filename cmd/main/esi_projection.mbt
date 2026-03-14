///|
fn run_esi_sii_command(
  args : Array[String],
  as_json : Bool,
) -> Unit raise @hal.EcError {
  if has_flag(args, "--xml") {
    raise @hal.EcError::ConfigMismatch(
      "esi-sii no longer accepts --xml directly; run moon run cmd/eni_json -- --input <esi.xml> --kind esi --output <esi.json> and then pass --esi-json <esi.json>",
    )
  }
  let json_path = require_cli_file_flag(args, "--esi-json", "ESI JSON")
  let device_index = require_int_flag(args, "--device-index", 0)
  if device_index < 0 {
    raise @hal.EcError::ConfigMismatch(
      "device index for --device-index must be >= 0",
    )
  }
  let json_content = read_cli_text_file(json_path, "ESI JSON")
  let report = @runtime.offline_sii_report_from_esi_json(
    json_content, device_index,
  )
  if as_json {
    println(offline_sii_json(report).stringify(indent=2))
  } else {
    println(offline_sii_text(report))
  }
}

///|
fn require_cli_file_flag(
  args : Array[String],
  flag : String,
  label : String,
) -> String raise @hal.EcError {
  match flag_value(args, flag) {
    Some(value) => value
    None =>
      raise @hal.EcError::ConfigMismatch(
        "missing required flag " + flag + " for " + label,
      )
  }
}

///|
fn read_cli_text_file(
  path : String,
  label : String,
) -> String raise @hal.EcError {
  let content_result : Result[String, Error] = try? @fs.read_file_to_string(
    path,
  )
  match content_result {
    Ok(content) => content
    Err(err) =>
      raise @hal.EcError::ConfigMismatch(
        "failed to read " + label + " file " + path + ": " + err.to_string(),
      )
  }
}

///|
fn offline_sii_json(report : @runtime.EsiOfflineSiiReport) -> Json {
  read_sii_json(
    report.position,
    report.word_count,
    report.preamble,
    report.standard,
    report.header,
    report.general,
    report.strings,
    report.fmmu,
    report.sync_managers,
    report.dc_clocks,
    report.tx_pdo,
    report.rx_pdo,
    report.categories,
  )
}

///|
fn offline_sii_text(report : @runtime.EsiOfflineSiiReport) -> String {
  read_sii_text(
    report.position,
    report.word_count,
    report.eeprom,
    report.preamble,
    report.standard,
    report.header,
    report.general,
    report.strings,
    report.categories,
  )
}
