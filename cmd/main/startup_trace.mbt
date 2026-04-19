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
fn startup_trace_source(args : Array[String]) -> String {
  configured_startup_source(args)
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
