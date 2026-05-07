///|
fn[N : @hal.Nic] run_diagnosis_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let scan_report = diagnosis_stage(
    try? @runtime.scan(nic, timeout),
    "diagnosis.scan",
  )
  let target_slave = resolve_cli_slave(
    scan_report,
    optional_uint_flag(args, "--station"),
  )
  let station = target_slave.station_address
  let position = target_slave.position.reinterpret_as_uint()
  let diagnosis_session = diagnosis_stage(
    try? @runtime.prepare_slave_diagnosis_ap(nic, position, station, timeout),
    "diagnosis.prepare",
  )
  let diagnosis_rmsm = @mailbox.Rmsm::new(max_retries=0)
  let report = diagnosis_stage(
    try? @runtime.read_slave_diagnosis_ap(
      nic,
      position,
      station,
      diagnosis_session.mailbox_config,
      diagnosis_rmsm,
      timeout,
    ),
    "diagnosis.read_slave_diagnosis_ap",
  )
  let report = {
    ..report,
    al_state: match diagnosis_session.observed_state {
      Some(state) => Some(state)
      None => report.al_state
    },
    al_error_flag: match diagnosis_session.observed_error_flag {
      Some(flag) => Some(flag)
      None => report.al_error_flag
    },
    al_status_code: match diagnosis_session.observed_status_code {
      Some(code) => Some(code)
      None => report.al_status_code
    },
  }
  if diagnosis_session.original_state != @protocol.PreOp {
    ignore(
      diagnosis_stage(
        try? @runtime.restore_slave_diagnosis_state(
          nic,
          station,
          diagnosis_session.original_state,
          timeout,
        ),
        "diagnosis.restore",
      ) catch {
        _ => @protocol.PreOp
      },
    )
  }
  nic.close()
  if as_json {
    println(diagnosis_output_json(scan_report, report).stringify(indent=2))
  } else {
    println(diagnosis_report_text(report))
  }
}

///|
struct OdBrowseQuery {
  list_type : UInt
  index : UInt?
  subindex : Byte?
  read_value : Bool
}

///|
struct OdBrowseReport {
  station_address : UInt?
  mode : String
  list_type : UInt
  index : UInt?
  subindex : Byte?
  indices : Array[UInt]?
  object_description : @mailbox.SdoInfoObjectDescription?
  entry_description : @mailbox.SdoInfoEntryDescription?
  value_hex : String?
  value_u32 : UInt?
  error_category : String?
  error_detail : String?
  abort_code : UInt?
}

///|
fn resolve_od_query(args : Array[String]) -> OdBrowseQuery raise @hal.EcError {
  let index = optional_uint_flag(args, "--index")
  let read_value = has_flag(args, "--read-value")
  let subindex = match optional_byte_flag(args, "--subindex") {
    Some(value) => Some(value)
    None if read_value && index is Some(_) => Some(b'\x00')
    None => None
  }
  if subindex is Some(_) && index is None {
    raise @hal.EcError::ConfigMismatch("--subindex requires --index")
  }
  if read_value && index is None {
    raise @hal.EcError::ConfigMismatch("--read-value requires --index")
  }
  {
    list_type: require_uint_flag(args, "--list-type", 0U),
    index,
    subindex,
    read_value,
  }
}

///|
fn[N : @hal.Nic] run_od_command(
  nic : N,
  args : Array[String],
  as_json : Bool,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let query = resolve_od_query(args)
  let report_result : Result[OdBrowseReport, @hal.EcError] = try? compute_od_report(
    nic, args, query, timeout,
  )
  nic.close()
  let report = match report_result {
    Ok(value) => value
    Err(err) =>
      od_failure_report(optional_uint_flag(args, "--station"), query, err)
  }
  if as_json {
    println(od_report_json(report).stringify(indent=2))
  } else {
    println(od_report_text(report))
  }
}

///|
fn[N : @hal.Nic] compute_od_report(
  nic : N,
  args : Array[String],
  query : OdBrowseQuery,
  timeout : @hal.Duration,
) -> OdBrowseReport raise @hal.EcError {
  let scan_report = od_stage(try? @runtime.scan(nic, timeout), "od.scan")
  let target_slave = resolve_cli_slave(
    scan_report,
    optional_uint_flag(args, "--station"),
  )
  let station = target_slave.station_address
  let position = target_slave.position.reinterpret_as_uint()
  let mailbox_session = od_stage(
    try? @runtime.prepare_slave_mailbox_ap(nic, position, station, timeout),
    "od.prepare",
  )
  let browse_rmsm = @mailbox.Rmsm::new(max_retries=0)
  let report = match (query.index, query.subindex) {
    (None, _) => {
      let indices = od_stage(
        try? @protocol.sdo_info_get_od_list(
          nic,
          station,
          mailbox_session.mailbox_config,
          browse_rmsm,
          query.list_type,
          timeout,
        ),
        "od.get_od_list",
      )
      {
        station_address: Some(station),
        mode: "od-list",
        list_type: query.list_type,
        index: None,
        subindex: None,
        indices: Some(indices),
        object_description: None,
        entry_description: None,
        value_hex: None,
        value_u32: None,
        error_category: None,
        error_detail: None,
        abort_code: None,
      }
    }
    (Some(index), None) => {
      let description = od_stage(
        try? @protocol.sdo_info_get_od_description(
          nic,
          station,
          mailbox_session.mailbox_config,
          browse_rmsm,
          index,
          timeout,
        ),
        "od.get_od_description",
      )
      {
        station_address: Some(station),
        mode: "od-object",
        list_type: query.list_type,
        index: Some(index),
        subindex: None,
        indices: None,
        object_description: Some(description),
        entry_description: None,
        value_hex: None,
        value_u32: None,
        error_category: None,
        error_detail: None,
        abort_code: None,
      }
    }
    (Some(index), Some(subindex)) =>
      if query.read_value {
        let payload = od_stage(
          try? @protocol.sdo_upload_retry(
            nic,
            station,
            mailbox_session.mailbox_config,
            browse_rmsm,
            index,
            subindex,
            timeout,
          ),
          "od.sdo_upload",
        )
        {
          station_address: Some(station),
          mode: "od-value",
          list_type: query.list_type,
          index: Some(index),
          subindex: Some(subindex),
          indices: None,
          object_description: None,
          entry_description: None,
          value_hex: Some(bytes_hex(payload)),
          value_u32: decode_payload_u32_le(payload),
          error_category: None,
          error_detail: None,
          abort_code: None,
        }
      } else {
        let description = od_stage(
          try? @protocol.sdo_info_get_oe_description(
            nic,
            station,
            mailbox_session.mailbox_config,
            browse_rmsm,
            index,
            subindex,
            0xFF,
            timeout,
          ),
          "od.get_oe_description",
        )
        {
          station_address: Some(station),
          mode: "od-entry",
          list_type: query.list_type,
          index: Some(index),
          subindex: Some(subindex),
          indices: None,
          object_description: None,
          entry_description: Some(description),
          value_hex: None,
          value_u32: None,
          error_category: None,
          error_detail: None,
          abort_code: None,
        }
      }
  }
  if mailbox_session.original_state != @protocol.PreOp {
    ignore(
      od_stage(
        try? @runtime.restore_slave_mailbox_state(
          nic,
          station,
          mailbox_session.original_state,
          timeout,
        ),
        "od.restore",
      ) catch {
        _ => @protocol.PreOp
      },
    )
  }
  report
}

///|
fn resolve_cli_slave(
  scan_report : @runtime.ScanReport,
  requested_station : UInt?,
) -> @runtime.SlaveReport raise @hal.EcError {
  match requested_station {
    Some(station) => {
      for slave in scan_report.slaves {
        if slave.station_address == station {
          return slave
        }
      }
      raise @hal.EcError::ConfigMismatch(
        "diagnosis station not found in current scan: " + station.to_string(),
      )
    }
    None =>
      match scan_report.slaves {
        [only] => only
        [] =>
          raise @hal.EcError::ConfigMismatch(
            "diagnosis requires discovered slave or explicit --station",
          )
        _ =>
          raise @hal.EcError::ConfigMismatch(
            "diagnosis requires explicit --station when multiple slaves are present",
          )
      }
  }
}

///|
fn[T] diagnosis_stage(
  result : Result[T, Error],
  stage : String,
) -> T raise @hal.EcError {
  match result {
    Ok(value) => value
    Err(@hal.EcError::RecvTimeout) =>
      raise @hal.EcError::Internal("timeout at " + stage + " (RecvTimeout)")
    Err(@hal.EcError::MailboxTimeout) =>
      raise @hal.EcError::Internal("timeout at " + stage + " (MailboxTimeout)")
    Err(@hal.EcError::Internal(message)) if message.contains("timeout at ") =>
      raise @hal.EcError::Internal(stage + " -> " + message)
    Err(err) => raise @hal.EcError::Internal(err.to_string())
  }
}

///|
fn[T] od_stage(
  result : Result[T, @hal.EcError],
  stage : String,
) -> T raise @hal.EcError {
  match result {
    Ok(value) => value
    Err(@hal.EcError::SendFailed(message)) =>
      raise @hal.EcError::SendFailed(stage + " -> " + message)
    Err(@hal.EcError::RecvFailed(message)) =>
      raise @hal.EcError::RecvFailed(stage + " -> " + message)
    Err(@hal.EcError::InvalidFrame(message)) =>
      raise @hal.EcError::InvalidFrame(stage + " -> " + message)
    Err(@hal.EcError::InvalidPdu(message)) =>
      raise @hal.EcError::InvalidPdu(stage + " -> " + message)
    Err(@hal.EcError::EsmStateError(message)) =>
      raise @hal.EcError::EsmStateError(stage + " -> " + message)
    Err(@hal.EcError::MailboxProtocol(message)) =>
      raise @hal.EcError::MailboxProtocol(stage + " -> " + message)
    Err(@hal.EcError::SiiReadFailed(message)) =>
      raise @hal.EcError::SiiReadFailed(stage + " -> " + message)
    Err(@hal.EcError::EsiParseFailed(message)) =>
      raise @hal.EcError::EsiParseFailed(stage + " -> " + message)
    Err(@hal.EcError::ConfigMismatch(message)) =>
      raise @hal.EcError::ConfigMismatch(stage + " -> " + message)
    Err(@hal.EcError::NotSupported(message)) =>
      raise @hal.EcError::NotSupported(stage + " -> " + message)
    Err(@hal.EcError::Internal(message)) =>
      raise @hal.EcError::Internal(stage + " -> " + message)
    Err(err) => raise err
  }
}

///|
fn diagnosis_output_json(
  scan : @runtime.ScanReport,
  report : @runtime.SlaveDiagnosis,
) -> Json {
  Json::object({
    "station": Json::number(report.station_address.to_double()),
    "al_state": match report.al_state {
      Some(state) => Json::string(state.to_string())
      None => Json::null()
    },
    "al_error_flag": match report.al_error_flag {
      Some(flag) => Json::boolean(flag)
      None => Json::null()
    },
    "al_status_code": match report.al_status_code {
      Some(code) => Json::number(code.to_double())
      None => Json::null()
    },
    "al_status_code_description": match report.al_status_code {
      Some(code) => Json::string(@protocol.al_status_code_description(code))
      None => Json::null()
    },
    "error_register": Json::number(report.error_register.to_uint().to_double()),
    "diagnosis_counter": match report.diagnosis_counter {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
    "dl_error_counters": match report.dl_error_counters {
      Some(dl) => {
        let port_arr : Array[Json] = []
        for i = 0; i < dl.ports.length(); i = i + 1 {
          let p = dl.ports[i]
          port_arr.push(
            Json::object({
              "port": Json::number(i.to_double()),
              "frame_errors": Json::number(p.frame_errors.to_double()),
              "physical_errors": Json::number(p.physical_errors.to_double()),
              "forwarded_rx_errors": Json::number(
                p.forwarded_rx_errors.to_double(),
              ),
              "lost_link_count": Json::number(p.lost_link_count.to_double()),
            }),
          )
        }
        Json::object({
          "ports": Json::array(port_arr),
          "ecat_pu_errors": Json::number(dl.ecat_pu_errors.to_double()),
          "pdi_errors": Json::number(dl.pdi_errors.to_double()),
        })
      }
      None => Json::null()
    },
    "surface": diagnostic_surface_json(
      @runtime.diagnostic_surface_from_slave_diagnosis(scan, report),
    ),
  })
}

///|
fn diagnosis_report_text(report : @runtime.SlaveDiagnosis) -> String {
  let buf = @buffer.new(size_hint=192)
  let al_state_text = match report.al_state {
    Some(state) => state.to_string()
    None => "unknown"
  }
  let al_error_flag_text = match report.al_error_flag {
    Some(true) => "set"
    Some(false) => "clear"
    None => "unknown"
  }
  let al_status_code_text = match report.al_status_code {
    Some(code) =>
      format_hex(code, 4) +
      " (" +
      @protocol.al_status_code_description(code) +
      ")"
    None => "unknown"
  }
  let diagnosis_counter_text = match report.diagnosis_counter {
    Some(value) => value.to_string()
    None => "not available"
  }
  buf.write_string("EtherCAT Slave Diagnosis\n")
  buf.write_string("========================\n")
  buf.write_string("Station: " + report.station_address.to_string() + "\n")
  buf.write_string("AL State: " + al_state_text + "\n")
  buf.write_string("AL Error Flag: " + al_error_flag_text + "\n")
  buf.write_string("AL Status Code: " + al_status_code_text + "\n")
  buf.write_string(
    "Error Register: " + format_hex(report.error_register.to_uint(), 2) + "\n",
  )
  buf.write_string("Diagnosis Counter: " + diagnosis_counter_text + "\n")
  match report.dl_error_counters {
    Some(dl) => {
      buf.write_string("DL Error Counters:\n")
      for i = 0; i < dl.ports.length(); i = i + 1 {
        let p = dl.ports[i]
        buf.write_string(
          "  Port " +
          i.to_string() +
          ": frame=" +
          p.frame_errors.to_string() +
          " physical=" +
          p.physical_errors.to_string() +
          " fwd_rx=" +
          p.forwarded_rx_errors.to_string() +
          " lost_link=" +
          p.lost_link_count.to_string() +
          "\n",
        )
      }
      buf.write_string("  EPU errors: " + dl.ecat_pu_errors.to_string() + "\n")
      buf.write_string("  PDI errors: " + dl.pdi_errors.to_string() + "\n")
    }
    None => buf.write_string("DL Error Counters: not available\n")
  }
  buf.to_string()
}

///|
fn od_report_json(report : OdBrowseReport) -> Json {
  Json::object({
    "station": match report.station_address {
      Some(station) => Json::number(station.to_double())
      None => Json::null()
    },
    "mode": Json::string(report.mode),
    "list_type": Json::number(report.list_type.to_double()),
    "index": match report.index {
      Some(index) => Json::number(index.to_double())
      None => Json::null()
    },
    "subindex": match report.subindex {
      Some(subindex) => Json::number(subindex.to_uint().to_double())
      None => Json::null()
    },
    "indices": match report.indices {
      Some(indices) =>
        Json::array(indices.map(fn(index) { Json::number(index.to_double()) }))
      None => Json::null()
    },
    "object": match report.object_description {
      Some(description) =>
        Json::object({
          "index": Json::number(description.index.to_double()),
          "data_type": Json::number(description.data_type.to_double()),
          "object_code": Json::number(
            description.object_code.to_uint().to_double(),
          ),
          "max_subindex": Json::number(
            description.max_subindex.to_uint().to_double(),
          ),
          "name": Json::string(description.name),
        })
      None => Json::null()
    },
    "entry": match report.entry_description {
      Some(description) =>
        Json::object({
          "index": Json::number(description.index.to_double()),
          "subindex": Json::number(description.subindex.to_uint().to_double()),
          "value_info": Json::number(
            description.value_info.to_uint().to_double(),
          ),
          "data_type": Json::number(description.data_type.to_double()),
          "bit_length": Json::number(description.bit_length.to_double()),
          "access": Json::number(description.access.to_double()),
          "name": Json::string(description.name),
        })
      None => Json::null()
    },
    "value": match report.value_hex {
      Some(value_hex) =>
        Json::object({
          "hex": Json::string(value_hex),
          "u32_le": match report.value_u32 {
            Some(value) => Json::number(value.to_double())
            None => Json::null()
          },
        })
      None => Json::null()
    },
    "error": match report.error_category {
      Some(category) =>
        Json::object({
          "category": Json::string(category),
          "detail": match report.error_detail {
            Some(detail) => Json::string(detail)
            None => Json::null()
          },
          "abort_code": match report.abort_code {
            Some(code) => Json::number(code.to_double())
            None => Json::null()
          },
          "abort_code_description": match report.abort_code {
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
fn od_report_text(report : OdBrowseReport) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("EtherCAT Object Dictionary\n")
  buf.write_string("==========================\n")
  let station_text = match report.station_address {
    Some(station) => station.to_string()
    None => "unknown"
  }
  buf.write_string("Station: " + station_text + "\n")
  buf.write_string("Mode: " + report.mode + "\n")
  match report.error_category {
    Some(category) => {
      buf.write_string("Error Category: " + category + "\n")
      match report.abort_code {
        Some(code) =>
          buf.write_string(
            "Abort Code: " +
            format_hex(code, 8) +
            " (" +
            @mailbox.sdo_abort_code_description(code) +
            ")\n",
          )
        None => ()
      }
      match report.error_detail {
        Some(detail) => buf.write_string("Error Detail: " + detail + "\n")
        None => ()
      }
    }
    None => ()
  }
  match report.indices {
    Some(indices) => {
      buf.write_string("List Type: " + report.list_type.to_string() + "\n")
      buf.write_string("Indices:\n")
      for index in indices {
        buf.write_string("  - " + format_hex(index, 4) + "\n")
      }
    }
    None => ()
  }
  match report.object_description {
    Some(description) => {
      buf.write_string("Index: " + format_hex(description.index, 4) + "\n")
      buf.write_string("Name: " + description.name + "\n")
      buf.write_string(
        "Data Type: " + format_hex(description.data_type, 4) + "\n",
      )
      buf.write_string(
        "Object Code: " +
        format_hex(description.object_code.to_uint(), 2) +
        "\n",
      )
      buf.write_string(
        "Max Subindex: " + description.max_subindex.to_uint().to_string() + "\n",
      )
    }
    None => ()
  }
  match report.entry_description {
    Some(description) => {
      buf.write_string("Index: " + format_hex(description.index, 4) + "\n")
      buf.write_string(
        "Subindex: " + description.subindex.to_uint().to_string() + "\n",
      )
      buf.write_string("Name: " + description.name + "\n")
      buf.write_string(
        "Data Type: " + format_hex(description.data_type, 4) + "\n",
      )
      buf.write_string(
        "Bit Length: " + description.bit_length.to_string() + "\n",
      )
      buf.write_string("Access: " + format_hex(description.access, 4) + "\n")
      buf.write_string(
        "Value Info: " + format_hex(description.value_info.to_uint(), 2) + "\n",
      )
    }
    None => ()
  }
  match report.value_hex {
    Some(value_hex) => {
      let index = match report.index {
        Some(index) => index
        None => 0U
      }
      let subindex = match report.subindex {
        Some(subindex) => subindex
        None => b'\x00'
      }
      buf.write_string("Index: " + format_hex(index, 4) + "\n")
      buf.write_string("Subindex: " + subindex.to_uint().to_string() + "\n")
      buf.write_string("Value (hex): " + value_hex + "\n")
      match report.value_u32 {
        Some(value) =>
          buf.write_string("Value (u32 le): " + value.to_string() + "\n")
        None => ()
      }
    }
    None => ()
  }
  buf.to_string()
}

///|
fn od_failure_report(
  station : UInt?,
  query : OdBrowseQuery,
  err : @hal.EcError,
) -> OdBrowseReport {
  {
    station_address: station,
    mode: od_mode_from_query(query),
    list_type: query.list_type,
    index: query.index,
    subindex: query.subindex,
    indices: None,
    object_description: None,
    entry_description: None,
    value_hex: None,
    value_u32: None,
    error_category: Some(od_error_category(err)),
    error_detail: Some(err.to_string()),
    abort_code: match err {
      @hal.EcError::SdoAbort(code) => Some(code)
      _ => None
    },
  }
}

///|
fn od_mode_from_query(query : OdBrowseQuery) -> String {
  if query.read_value {
    return "od-value"
  }
  match (query.index, query.subindex) {
    (None, _) => "od-list"
    (Some(_), None) => "od-object"
    (Some(_), Some(_)) => "od-entry"
  }
}

///|
fn od_error_category(err : @hal.EcError) -> String {
  match err {
    @hal.EcError::LinkDown => "transport-failure"
    @hal.EcError::SendFailed(_) => "transport-failure"
    @hal.EcError::RecvTimeout => "transport-failure"
    @hal.EcError::RecvFailed(_) => "transport-failure"
    @hal.EcError::MailboxTimeout => "transport-failure"
    @hal.EcError::InvalidFrame(_) => "protocol-failure"
    @hal.EcError::InvalidPdu(_) => "protocol-failure"
    @hal.EcError::UnexpectedWkc(..) => "protocol-failure"
    @hal.EcError::MailboxProtocol(_) => "protocol-failure"
    @hal.EcError::SdoAbort(_) => "protocol-failure"
    @hal.EcError::NotSupported(_) => "unsupported"
    _ => "command-failure"
  }
}
