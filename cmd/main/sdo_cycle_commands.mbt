///|
/// Periodic CoE SDO upload and download commands.

///|
struct CyclicSdoReadSettings {
  index : UInt
  subindex : Byte
  cycles : Int
  period_ms : Int
}

///|
struct CyclicSdoReadSample {
  cycle : Int
  value_hex : String?
  value_u32 : UInt?
  error_category : String?
  error_detail : String?
  abort_code : UInt?
}

///|
struct CyclicSdoReadReport {
  station_address : UInt
  index : UInt
  subindex : Byte
  cycles_requested : Int
  period_ms : Int
  samples : Array[CyclicSdoReadSample]
}

///|
fn resolve_cyclic_sdo_read_settings(
  args : Array[String],
) -> CyclicSdoReadSettings raise @hal.EcError {
  let index = match optional_uint_flag(args, "--index") {
    Some(value) => value
    None => raise @hal.EcError::ConfigMismatch("sdo-read requires --index <n>")
  }
  let subindex = match optional_byte_flag(args, "--subindex") {
    Some(value) => value
    None => b'\x00'
  }
  let cycles = require_int_flag(args, "--cycles", 10)
  if cycles <= 0 {
    raise @hal.EcError::ConfigMismatch("cycle value for --cycles must be > 0")
  }
  let period_ms = require_int_flag(args, "--cycle-period-ms", 100)
  if period_ms <= 0 {
    raise @hal.EcError::ConfigMismatch(
      "period value for --cycle-period-ms must be > 0",
    )
  }
  { index, subindex, cycles, period_ms }
}

///|
async fn[N : @hal.Nic] run_cyclic_sdo_read_command(
  nic : N,
  args : Array[String],
  settings : CyclicSdoReadSettings,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit {
  let report_result : Result[CyclicSdoReadReport, Error] = Result::Ok(
    compute_cyclic_sdo_read_report(nic, args, settings, timeout),
  ) catch {
    err => Result::Err(err)
  }
  nic.close()
  let report = match report_result {
    Ok(value) => value
    Err(err) => raise err
  }
  if as_json {
    println(cyclic_sdo_read_report_json(report).stringify(indent=2))
  } else {
    println(cyclic_sdo_read_report_text(report))
  }
}

///|
async fn[N : @hal.Nic] compute_cyclic_sdo_read_report(
  nic : N,
  args : Array[String],
  settings : CyclicSdoReadSettings,
  timeout : @hal.Duration,
) -> CyclicSdoReadReport {
  let scan_report = od_stage(
    Result::Ok(@runtime.scan(nic, timeout)) catch {
      err => Result::Err(err)
    },
    "sdo-read.scan",
  )
  let target_slave = resolve_cli_slave(
    scan_report,
    optional_uint_flag(args, "--station"),
  )
  let station = target_slave.station_address
  let position = target_slave.position.reinterpret_as_uint()
  let mailbox_session = od_stage(
    Result::Ok(
      @runtime.prepare_slave_mailbox_ap(nic, position, station, timeout),
    ) catch {
      err => Result::Err(err)
    },
    "sdo-read.prepare",
  )
  let rmsm = @mailbox.Rmsm::new(max_retries=0)
  let samples : Array[CyclicSdoReadSample] = []
  for cycle in 0..<settings.cycles {
    let payload_result : Result[Bytes, @hal.EcError] = Result::Ok(
      @protocol.sdo_upload_retry(
        nic,
        station,
        mailbox_session.mailbox_config,
        rmsm,
        settings.index,
        settings.subindex,
        timeout,
      ),
    ) catch {
      err => Result::Err(err)
    }
    match payload_result {
      Ok(payload) =>
        samples.push({
          cycle: cycle + 1,
          value_hex: Some(bytes_hex(payload)),
          value_u32: decode_payload_u32_le(payload),
          error_category: None,
          error_detail: None,
          abort_code: None,
        })
      Err(err) => {
        samples.push({
          cycle: cycle + 1,
          value_hex: None,
          value_u32: None,
          error_category: Some(od_error_category(err)),
          error_detail: Some(@debug.to_string(err)),
          abort_code: match err {
            @hal.EcError::SdoAbort(code) => Some(code)
            _ => None
          },
        })
        rmsm.reset()
      }
    }
    if cycle + 1 < settings.cycles {
      @async.sleep(settings.period_ms)
    }
  }
  if mailbox_session.original_state != @protocol.PreOp {
    ignore(
      od_stage(
        Result::Ok(
          @runtime.restore_slave_mailbox_state(
            nic,
            station,
            mailbox_session.original_state,
            timeout,
          ),
        ) catch {
          err => Result::Err(err)
        },
        "sdo-read.restore",
      ),
    )
  }
  {
    station_address: station,
    index: settings.index,
    subindex: settings.subindex,
    cycles_requested: settings.cycles,
    period_ms: settings.period_ms,
    samples,
  }
}

///|
fn cyclic_sdo_read_success_count(report : CyclicSdoReadReport) -> Int {
  let mut count = 0
  for sample in report.samples {
    if sample.error_category is None {
      count = count + 1
    }
  }
  count
}

///|
fn cyclic_sdo_read_sample_json(sample : CyclicSdoReadSample) -> Json {
  Json::object({
    "cycle": Json::number(sample.cycle.to_double()),
    "value": match sample.value_hex {
      Some(value_hex) =>
        Json::object({
          "hex": Json::string(value_hex),
          "u32_le": match sample.value_u32 {
            Some(value) => Json::number(value.to_double())
            None => Json::null()
          },
        })
      None => Json::null()
    },
    "error": match sample.error_category {
      Some(category) =>
        Json::object({
          "category": Json::string(category),
          "detail": match sample.error_detail {
            Some(detail) => Json::string(detail)
            None => Json::null()
          },
          "abort_code": match sample.abort_code {
            Some(code) => Json::number(code.to_double())
            None => Json::null()
          },
          "abort_code_description": match sample.abort_code {
            Some(code) =>
              Json::string(@mailbox.sdo_abort_code_description(code))
            None => Json::null()
          },
        })
      None => Json::null()
    },
  })
}

///|
fn cyclic_sdo_read_report_json(report : CyclicSdoReadReport) -> Json {
  let success_count = cyclic_sdo_read_success_count(report)
  Json::object({
    "command": Json::string("sdo-read"),
    "station": Json::number(report.station_address.to_double()),
    "index": Json::number(report.index.to_double()),
    "subindex": Json::number(report.subindex.to_uint().to_double()),
    "cycles_requested": Json::number(report.cycles_requested.to_double()),
    "cycles_completed": Json::number(report.samples.length().to_double()),
    "success_count": Json::number(success_count.to_double()),
    "failure_count": Json::number(
      (report.samples.length() - success_count).to_double(),
    ),
    "cycle_period_ms": Json::number(report.period_ms.to_double()),
    "samples": Json::array(
      report.samples.map(fn(sample) { cyclic_sdo_read_sample_json(sample) }),
    ),
  })
}

///|
fn cyclic_sdo_read_report_text(report : CyclicSdoReadReport) -> String {
  let success_count = cyclic_sdo_read_success_count(report)
  let buf = StringBuilder(size_hint=256)
  buf.write_string("Periodic EtherCAT SDO Read\n")
  buf.write_string("===========================\n")
  buf.write_string("Station: " + report.station_address.to_string() + "\n")
  buf.write_string("Index: " + format_hex(report.index, 4) + "\n")
  buf.write_string("Subindex: " + report.subindex.to_uint().to_string() + "\n")
  buf.write_string("Cycle Period: " + report.period_ms.to_string() + " ms\n")
  buf.write_string("Samples:\n")
  for sample in report.samples {
    buf.write_string("  [" + sample.cycle.to_string() + "] ")
    match sample.value_hex {
      Some(value_hex) => {
        buf.write_string(value_hex)
        match sample.value_u32 {
          Some(value) =>
            buf.write_string(" (u32 le: " + value.to_string() + ")")
          None => ()
        }
        buf.write_string("\n")
      }
      None => {
        let category = match sample.error_category {
          Some(value) => value
          None => "command-failure"
        }
        buf.write_string("ERROR " + category)
        match sample.abort_code {
          Some(code) =>
            buf.write_string(
              " " +
              format_hex(code, 8) +
              " (" +
              @mailbox.sdo_abort_code_description(code) +
              ")",
            )
          None => ()
        }
        match sample.error_detail {
          Some(detail) => buf.write_string(": " + detail)
          None => ()
        }
        buf.write_string("\n")
      }
    }
  }
  buf.write_string(
    "Summary: " +
    success_count.to_string() +
    " succeeded, " +
    (report.samples.length() - success_count).to_string() +
    " failed\n",
  )
  buf.to_string()
}

///|
struct CyclicSdoWriteSettings {
  station : UInt
  index : UInt
  subindex : Byte
  data : Bytes
  cycles : Int
  period_ms : Int
}

///|
struct CyclicSdoWriteSample {
  cycle : Int
  error_category : String?
  error_detail : String?
  abort_code : UInt?
}

///|
struct CyclicSdoWriteReport {
  station_address : UInt
  index : UInt
  subindex : Byte
  data : Bytes
  cycles_requested : Int
  period_ms : Int
  samples : Array[CyclicSdoWriteSample]
}

///|
fn cli_hex_digit_value(ch : Byte, flag : String) -> UInt raise @hal.EcError {
  if ch >= b'0' && ch <= b'9' {
    return ch.to_uint() - b'0'.to_uint()
  }
  if ch >= b'a' && ch <= b'f' {
    return 10U + (ch.to_uint() - b'a'.to_uint())
  }
  if ch >= b'A' && ch <= b'F' {
    return 10U + (ch.to_uint() - b'A'.to_uint())
  }
  raise @hal.EcError::ConfigMismatch("invalid hexadecimal digit for " + flag)
}

///|
fn parse_cli_hex_bytes(
  text : String,
  flag : String,
) -> Bytes raise @hal.EcError {
  let encoded = @utf8.encode(text)
  let start = if encoded.length() >= 2 &&
    encoded[0] == b'0' &&
    (encoded[1] == b'x' || encoded[1] == b'X') {
    2
  } else {
    0
  }
  let digit_count = encoded.length() - start
  if digit_count <= 0 {
    raise @hal.EcError::ConfigMismatch(flag + " must not be empty")
  }
  if digit_count % 2 != 0 {
    raise @hal.EcError::ConfigMismatch(
      "hexadecimal byte string for " + flag + " must have an even length",
    )
  }
  let values : Array[Byte] = []
  for i = start; i < encoded.length(); i = i + 2 {
    let high = cli_hex_digit_value(encoded[i], flag)
    let low = cli_hex_digit_value(encoded[i + 1], flag)
    values.push(((high << 4) | low).to_byte())
  }
  Bytes::from_array(values)
}

///|
fn resolve_cyclic_sdo_write_settings(
  args : Array[String],
) -> CyclicSdoWriteSettings raise @hal.EcError {
  let station = match optional_uint_flag(args, "--station") {
    Some(value) => value
    None =>
      raise @hal.EcError::ConfigMismatch(
        "sdo-write requires --station <configured-address>",
      )
  }
  let index = match optional_uint_flag(args, "--index") {
    Some(value) => value
    None => raise @hal.EcError::ConfigMismatch("sdo-write requires --index <n>")
  }
  let subindex = match optional_byte_flag(args, "--subindex") {
    Some(value) => value
    None => b'\x00'
  }
  let data = match flag_value(args, "--data-hex") {
    Some(value) => parse_cli_hex_bytes(value, "--data-hex")
    None =>
      raise @hal.EcError::ConfigMismatch("sdo-write requires --data-hex <hex>")
  }
  let cycles = require_int_flag(args, "--cycles", 10)
  if cycles <= 0 {
    raise @hal.EcError::ConfigMismatch("cycle value for --cycles must be > 0")
  }
  let period_ms = require_int_flag(args, "--cycle-period-ms", 100)
  if period_ms <= 0 {
    raise @hal.EcError::ConfigMismatch(
      "period value for --cycle-period-ms must be > 0",
    )
  }
  { station, index, subindex, data, cycles, period_ms }
}

///|
async fn[N : @hal.Nic] run_cyclic_sdo_write_command(
  nic : N,
  settings : CyclicSdoWriteSettings,
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit {
  let report_result : Result[CyclicSdoWriteReport, Error] = Result::Ok(
    compute_cyclic_sdo_write_report(nic, settings, timeout),
  ) catch {
    err => Result::Err(err)
  }
  nic.close()
  let report = match report_result {
    Ok(value) => value
    Err(err) => raise err
  }
  if as_json {
    println(cyclic_sdo_write_report_json(report).stringify(indent=2))
  } else {
    println(cyclic_sdo_write_report_text(report))
  }
}

///|
async fn[N : @hal.Nic] compute_cyclic_sdo_write_report(
  nic : N,
  settings : CyclicSdoWriteSettings,
  timeout : @hal.Duration,
) -> CyclicSdoWriteReport {
  let scan_report = od_stage(
    Result::Ok(@runtime.scan(nic, timeout)) catch {
      err => Result::Err(err)
    },
    "sdo-write.scan",
  )
  let target_slave = resolve_cli_slave(scan_report, Some(settings.station))
  let station = target_slave.station_address
  let position = target_slave.position.reinterpret_as_uint()
  let mailbox_session = od_stage(
    Result::Ok(
      @runtime.prepare_slave_mailbox_ap(nic, position, station, timeout),
    ) catch {
      err => Result::Err(err)
    },
    "sdo-write.prepare",
  )
  let rmsm = @mailbox.Rmsm::new(max_retries=0)
  let samples : Array[CyclicSdoWriteSample] = []
  for cycle in 0..<settings.cycles {
    let write_result : Result[Unit, @hal.EcError] = Result::Ok(
      @protocol.sdo_download_retry(
        nic,
        station,
        mailbox_session.mailbox_config,
        rmsm,
        settings.index,
        settings.subindex,
        settings.data,
        timeout,
      ),
    ) catch {
      err => Result::Err(err)
    }
    match write_result {
      Ok(_) =>
        samples.push({
          cycle: cycle + 1,
          error_category: None,
          error_detail: None,
          abort_code: None,
        })
      Err(err) => {
        samples.push({
          cycle: cycle + 1,
          error_category: Some(od_error_category(err)),
          error_detail: Some(@debug.to_string(err)),
          abort_code: match err {
            @hal.EcError::SdoAbort(code) => Some(code)
            _ => None
          },
        })
        rmsm.reset()
      }
    }
    if cycle + 1 < settings.cycles {
      @async.sleep(settings.period_ms)
    }
  }
  if mailbox_session.original_state != @protocol.PreOp {
    ignore(
      od_stage(
        Result::Ok(
          @runtime.restore_slave_mailbox_state(
            nic,
            station,
            mailbox_session.original_state,
            timeout,
          ),
        ) catch {
          err => Result::Err(err)
        },
        "sdo-write.restore",
      ),
    )
  }
  {
    station_address: station,
    index: settings.index,
    subindex: settings.subindex,
    data: settings.data,
    cycles_requested: settings.cycles,
    period_ms: settings.period_ms,
    samples,
  }
}

///|
fn cyclic_sdo_write_success_count(report : CyclicSdoWriteReport) -> Int {
  let mut count = 0
  for sample in report.samples {
    if sample.error_category is None {
      count = count + 1
    }
  }
  count
}

///|
fn cyclic_sdo_write_sample_json(sample : CyclicSdoWriteSample) -> Json {
  Json::object({
    "cycle": Json::number(sample.cycle.to_double()),
    "success": Json::boolean(sample.error_category is None),
    "error": match sample.error_category {
      Some(category) =>
        Json::object({
          "category": Json::string(category),
          "detail": match sample.error_detail {
            Some(detail) => Json::string(detail)
            None => Json::null()
          },
          "abort_code": match sample.abort_code {
            Some(code) => Json::number(code.to_double())
            None => Json::null()
          },
          "abort_code_description": match sample.abort_code {
            Some(code) =>
              Json::string(@mailbox.sdo_abort_code_description(code))
            None => Json::null()
          },
        })
      None => Json::null()
    },
  })
}

///|
fn cyclic_sdo_write_report_json(report : CyclicSdoWriteReport) -> Json {
  let success_count = cyclic_sdo_write_success_count(report)
  Json::object({
    "command": Json::string("sdo-write"),
    "station": Json::number(report.station_address.to_double()),
    "index": Json::number(report.index.to_double()),
    "subindex": Json::number(report.subindex.to_uint().to_double()),
    "data_hex": Json::string(bytes_hex(report.data)),
    "cycles_requested": Json::number(report.cycles_requested.to_double()),
    "cycles_completed": Json::number(report.samples.length().to_double()),
    "success_count": Json::number(success_count.to_double()),
    "failure_count": Json::number(
      (report.samples.length() - success_count).to_double(),
    ),
    "cycle_period_ms": Json::number(report.period_ms.to_double()),
    "samples": Json::array(
      report.samples.map(fn(sample) { cyclic_sdo_write_sample_json(sample) }),
    ),
  })
}

///|
fn cyclic_sdo_write_report_text(report : CyclicSdoWriteReport) -> String {
  let success_count = cyclic_sdo_write_success_count(report)
  let buf = StringBuilder(size_hint=256)
  buf.write_string("Periodic EtherCAT SDO Write\n")
  buf.write_string("============================\n")
  buf.write_string("Station: " + report.station_address.to_string() + "\n")
  buf.write_string("Index: " + format_hex(report.index, 4) + "\n")
  buf.write_string("Subindex: " + report.subindex.to_uint().to_string() + "\n")
  buf.write_string("Data: " + bytes_hex(report.data) + "\n")
  buf.write_string("Cycle Period: " + report.period_ms.to_string() + " ms\n")
  buf.write_string("Samples:\n")
  for sample in report.samples {
    buf.write_string("  [" + sample.cycle.to_string() + "] ")
    match sample.error_category {
      None => buf.write_string("OK\n")
      Some(category) => {
        buf.write_string("ERROR " + category)
        match sample.abort_code {
          Some(code) =>
            buf.write_string(
              " " +
              format_hex(code, 8) +
              " (" +
              @mailbox.sdo_abort_code_description(code) +
              ")",
            )
          None => ()
        }
        match sample.error_detail {
          Some(detail) => buf.write_string(": " + detail)
          None => ()
        }
        buf.write_string("\n")
      }
    }
  }
  buf.write_string(
    "Summary: " +
    success_count.to_string() +
    " succeeded, " +
    (report.samples.length() - success_count).to_string() +
    " failed\n",
  )
  buf.to_string()
}
