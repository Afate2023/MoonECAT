///|
struct PdoMappingObjectReport {
  index : UInt
  entries : Array[UInt]
}

///|
struct PdoDirectionReport {
  assignment_index : UInt
  assigned_pdos : Array[UInt]
  objects : Array[PdoMappingObjectReport]
}

///|
struct PdoAuditReport {
  plan_source : String
  policy : String
  effective_source : String
  live_detected : Bool?
  live_differs_from_plan : Bool?
  live_read_error : String?
  configured_rx : PdoDirectionReport
  configured_tx : PdoDirectionReport
  live_rx : PdoDirectionReport?
  live_tx : PdoDirectionReport?
  mismatches : Array[String]
}

///|
fn pdo_policy_name(prefer_live_pdo_state : Bool) -> String {
  if prefer_live_pdo_state {
    "prefer-live"
  } else {
    "force-configured"
  }
}

///|
fn pdo_effective_source(
  plan_source : String,
  prefer_live_pdo_state : Bool,
  live_detected : Bool,
) -> String {
  if !prefer_live_pdo_state {
    if plan_source == "esi-json" {
      "forced-esi"
    } else {
      "forced-online-sii"
    }
  } else if live_detected {
    "live"
  } else {
    plan_source
  }
}

///|
fn pdo_mapping_entry_raw(entry : @mailbox.SiiPdoEntry) -> UInt {
  entry.entry_index |
  (entry.subindex.to_uint() << 16) |
  (entry.bit_length.to_uint() << 24)
}

///|
fn normalize_pdo_mapping_entry_raw(raw : UInt) -> UInt {
  let entry_index = (raw >> 16) & 0xFFFFU
  let subindex = (raw >> 8) & 0xFFU
  let bit_length = raw & 0xFFU
  entry_index | (subindex << 16) | (bit_length << 24)
}

///|
fn pdo_direction_from_sii(
  pdos : Array[@mailbox.SiiPdo],
  assignment_index : UInt,
) -> PdoDirectionReport {
  {
    assignment_index,
    assigned_pdos: pdos.map(fn(pdo) { pdo.pdo_index }),
    objects: pdos.map(fn(pdo) {
      {
        index: pdo.pdo_index,
        entries: pdo.entries.map(fn(entry) { pdo_mapping_entry_raw(entry) }),
      }
    }),
  }
}

///|
fn pdo_uint_arrays_equal(lhs : Array[UInt], rhs : Array[UInt]) -> Bool {
  if lhs.length() != rhs.length() {
    return false
  }
  for i = 0; i < lhs.length(); i = i + 1 {
    if lhs[i] != rhs[i] {
      return false
    }
  }
  true
}

///|
fn pdo_append_unique(indices : Array[UInt], value : UInt) -> Unit {
  for existing in indices {
    if existing == value {
      return
    }
  }
  indices.push(value)
}

///|
fn pdo_direction_object_entries(
  direction : PdoDirectionReport,
  index : UInt,
) -> Array[UInt]? {
  for object in direction.objects {
    if object.index == index {
      return Some(object.entries)
    }
  }
  None
}

///|
fn pdo_assignment_indices_text(indices : Array[UInt]) -> String {
  "[" +
  join_strings(indices.map(fn(index) { format_hex(index, 4) }), ", ") +
  "]"
}

///|
fn pdo_mapping_entry_summary(raw : UInt) -> String {
  format_hex(raw & 0xFFFFU, 4) +
  ":" +
  format_hex((raw >> 16) & 0xFFU, 2) +
  "/" +
  ((raw >> 24) & 0xFFU).to_string()
}

///|
fn pdo_mapping_entries_text(entries : Array[UInt]) -> String {
  "[" +
  join_strings(
    entries.map(fn(entry) { pdo_mapping_entry_summary(entry) }),
    ", ",
  ) +
  "]"
}

///|
fn pdo_direction_mismatch_messages(
  configured : PdoDirectionReport,
  live : PdoDirectionReport,
) -> Array[String] {
  let mismatches : Array[String] = []
  if !pdo_uint_arrays_equal(configured.assigned_pdos, live.assigned_pdos) {
    mismatches.push(
      "assignment " +
      format_hex(configured.assignment_index, 4) +
      " expected=" +
      pdo_assignment_indices_text(configured.assigned_pdos) +
      " actual=" +
      pdo_assignment_indices_text(live.assigned_pdos),
    )
  }
  let object_indices : Array[UInt] = []
  for index in configured.assigned_pdos {
    pdo_append_unique(object_indices, index)
  }
  for index in live.assigned_pdos {
    pdo_append_unique(object_indices, index)
  }
  for index in object_indices {
    let configured_entries = match
      pdo_direction_object_entries(configured, index) {
      Some(entries) => entries
      None => []
    }
    let live_entries = match pdo_direction_object_entries(live, index) {
      Some(entries) => entries
      None => []
    }
    if !pdo_uint_arrays_equal(configured_entries, live_entries) {
      mismatches.push(
        "mapping " +
        format_hex(index, 4) +
        " expected=" +
        pdo_mapping_entries_text(configured_entries) +
        " actual=" +
        pdo_mapping_entries_text(live_entries),
      )
    }
  }
  mismatches
}

///|
fn pdo_mapping_entry_json(entry : UInt) -> Json {
  Json::object({
    "raw": Json::number(entry.to_double()),
    "raw_hex": Json::string(format_hex(entry, 8)),
    "summary": Json::string(pdo_mapping_entry_summary(entry)),
  })
}

///|
fn pdo_mapping_object_report_json(object : PdoMappingObjectReport) -> Json {
  Json::object({
    "index": Json::number(object.index.to_double()),
    "index_hex": Json::string(format_hex(object.index, 4)),
    "entries": Json::array(object.entries.map(pdo_mapping_entry_json)),
  })
}

///|
fn pdo_direction_report_json(direction : PdoDirectionReport) -> Json {
  Json::object({
    "assignment_index": Json::number(direction.assignment_index.to_double()),
    "assignment_index_hex": Json::string(
      format_hex(direction.assignment_index, 4),
    ),
    "assigned_pdos": Json::array(
      direction.assigned_pdos.map(fn(index) {
        Json::object({
          "index": Json::number(index.to_double()),
          "index_hex": Json::string(format_hex(index, 4)),
        })
      }),
    ),
    "objects": Json::array(
      direction.objects.map(pdo_mapping_object_report_json),
    ),
  })
}

///|
fn pdo_audit_report_json(report : PdoAuditReport) -> Json {
  Json::object({
    "plan_source": Json::string(report.plan_source),
    "policy": Json::string(report.policy),
    "effective_source": Json::string(report.effective_source),
    "live_detected": option_bool_json(report.live_detected),
    "live_differs_from_plan": option_bool_json(report.live_differs_from_plan),
    "live_read_error": option_string_json(report.live_read_error),
    "configured_rx": pdo_direction_report_json(report.configured_rx),
    "configured_tx": pdo_direction_report_json(report.configured_tx),
    "live_rx": match report.live_rx {
      Some(value) => pdo_direction_report_json(value)
      None => Json::null()
    },
    "live_tx": match report.live_tx {
      Some(value) => pdo_direction_report_json(value)
      None => Json::null()
    },
    "mismatches": Json::array(report.mismatches.map(item => Json::string(item))),
  })
}

///|
fn pdo_direction_objects_text(direction : PdoDirectionReport) -> String {
  join_strings(
    direction.objects.map(fn(object) {
      format_hex(object.index, 4) +
      "=" +
      pdo_mapping_entries_text(object.entries)
    }),
    "; ",
  )
}

///|
fn pdo_audit_report_text(report : PdoAuditReport) -> String {
  let buf = @buffer.new(size_hint=1024)
  buf.write_string("PDO Audit\n")
  buf.write_string("---------\n")
  buf.write_string("Plan Source: " + report.plan_source + "\n")
  buf.write_string("Policy: " + report.policy + "\n")
  buf.write_string("Effective Source: " + report.effective_source + "\n")
  match report.live_detected {
    Some(value) =>
      buf.write_string(
        "Live Detected: " + (if value { "yes" } else { "no" }) + "\n",
      )
    None => ()
  }
  match report.live_differs_from_plan {
    Some(value) =>
      buf.write_string(
        "Live Differs From Plan: " + (if value { "yes" } else { "no" }) + "\n",
      )
    None => ()
  }
  match report.live_read_error {
    Some(err) => buf.write_string("Live Read Error: " + err + "\n")
    None => ()
  }
  buf.write_string(
    "Configured Rx: " +
    format_hex(report.configured_rx.assignment_index, 4) +
    " -> " +
    pdo_assignment_indices_text(report.configured_rx.assigned_pdos) +
    "\n",
  )
  if !report.configured_rx.objects.is_empty() {
    buf.write_string(
      "Configured Rx Objects: " +
      pdo_direction_objects_text(report.configured_rx) +
      "\n",
    )
  }
  buf.write_string(
    "Configured Tx: " +
    format_hex(report.configured_tx.assignment_index, 4) +
    " -> " +
    pdo_assignment_indices_text(report.configured_tx.assigned_pdos) +
    "\n",
  )
  if !report.configured_tx.objects.is_empty() {
    buf.write_string(
      "Configured Tx Objects: " +
      pdo_direction_objects_text(report.configured_tx) +
      "\n",
    )
  }
  match report.live_rx {
    Some(direction) => {
      buf.write_string(
        "Live Rx: " +
        format_hex(direction.assignment_index, 4) +
        " -> " +
        pdo_assignment_indices_text(direction.assigned_pdos) +
        "\n",
      )
      if !direction.objects.is_empty() {
        buf.write_string(
          "Live Rx Objects: " + pdo_direction_objects_text(direction) + "\n",
        )
      }
    }
    None => ()
  }
  match report.live_tx {
    Some(direction) => {
      buf.write_string(
        "Live Tx: " +
        format_hex(direction.assignment_index, 4) +
        " -> " +
        pdo_assignment_indices_text(direction.assigned_pdos) +
        "\n",
      )
      if !direction.objects.is_empty() {
        buf.write_string(
          "Live Tx Objects: " + pdo_direction_objects_text(direction) + "\n",
        )
      }
    }
    None => ()
  }
  if report.mismatches.is_empty() {
    buf.write_string("Mismatches: none\n")
  } else {
    buf.write_string("Mismatches:\n")
    for item in report.mismatches {
      buf.write_string("- " + item + "\n")
    }
  }
  buf.to_string()
}

///|
fn[N : @hal.Nic] pdo_sdo_u32(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let payload = startup_trace_sdo_upload(
    nic, station, mailbox_config, index, subindex, timeout,
  )
  match decode_payload_u32_le(payload) {
    Some(value) => value
    None =>
      raise @hal.EcError::MailboxProtocol(
        "pdo audit: empty payload at 0x" +
        format_hex(index, 4) +
        ":" +
        format_hex(subindex.to_uint(), 2),
      )
  }
}

///|
fn[N : @hal.Nic] read_live_pdo_direction(
  nic : N,
  station : UInt,
  mailbox_config : @mailbox.MailboxConfig,
  assignment_index : UInt,
  timeout : @hal.Duration,
) -> PdoDirectionReport raise @hal.EcError {
  let count = pdo_sdo_u32(
    nic, station, mailbox_config, assignment_index, b'\x00', timeout,
  ).reinterpret_as_int()
  let assigned_pdos : Array[UInt] = []
  let objects : Array[PdoMappingObjectReport] = []
  for i = 1; i <= count; i = i + 1 {
    let pdo_index = pdo_sdo_u32(
        nic,
        station,
        mailbox_config,
        assignment_index,
        i.to_byte(),
        timeout,
      ) &
      0xFFFFU
    assigned_pdos.push(pdo_index)
    let entry_count = pdo_sdo_u32(
      nic, station, mailbox_config, pdo_index, b'\x00', timeout,
    ).reinterpret_as_int()
    let entries : Array[UInt] = []
    for entry_index = 1
        entry_index <= entry_count
        entry_index = entry_index + 1 {
      entries.push(
        normalize_pdo_mapping_entry_raw(
          pdo_sdo_u32(
            nic,
            station,
            mailbox_config,
            pdo_index,
            entry_index.to_byte(),
            timeout,
          ),
        ),
      )
    }
    objects.push({ index: pdo_index, entries })
  }
  { assignment_index, assigned_pdos, objects }
}

///|
fn[N : @hal.Nic] read_live_pdo_reports(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> (PdoDirectionReport, PdoDirectionReport) raise @hal.EcError {
  let scan_report = @runtime.scan(nic, timeout)
  let slave = resolve_cli_slave(scan_report, Some(station))
  let mailbox_session = @runtime.prepare_slave_mailbox_ap(
    nic,
    slave.position.reinterpret_as_uint(),
    station,
    timeout,
  )
  let rx = read_live_pdo_direction(
    nic,
    station,
    mailbox_session.mailbox_config,
    0x1C12U,
    timeout,
  )
  let tx = read_live_pdo_direction(
    nic,
    station,
    mailbox_session.mailbox_config,
    0x1C13U,
    timeout,
  )
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
  (rx, tx)
}

///|
fn[N : @hal.Nic] build_pdo_audit_report(
  nic : N,
  args : Array[String],
  station : UInt,
  preparation : @runtime.SlaveStartupPreparation,
  timeout : @hal.Duration,
) -> PdoAuditReport {
  let plan_source = configured_startup_source(args)
  let configured_rx = pdo_direction_from_sii(preparation.sii.rx_pdo, 0x1C12U)
  let configured_tx = pdo_direction_from_sii(preparation.sii.tx_pdo, 0x1C13U)
  let live_result : Result[
    (PdoDirectionReport, PdoDirectionReport),
    @hal.EcError,
  ] = try? read_live_pdo_reports(nic, station, timeout)
  match live_result {
    Ok((live_rx, live_tx)) => {
      let mismatches = pdo_direction_mismatch_messages(configured_rx, live_rx)
      for message in pdo_direction_mismatch_messages(configured_tx, live_tx) {
        mismatches.push(message)
      }
      let live_detected = !live_rx.assigned_pdos.is_empty() ||
        !live_tx.assigned_pdos.is_empty()
      {
        plan_source,
        policy: pdo_policy_name(preparation.prefer_live_pdo_state),
        effective_source: pdo_effective_source(
          plan_source,
          preparation.prefer_live_pdo_state,
          live_detected,
        ),
        live_detected: Some(live_detected),
        live_differs_from_plan: Some(!mismatches.is_empty()),
        live_read_error: None,
        configured_rx,
        configured_tx,
        live_rx: Some(live_rx),
        live_tx: Some(live_tx),
        mismatches,
      }
    }
    Err(err) => {
      let live_detected = false
      {
        plan_source,
        policy: pdo_policy_name(preparation.prefer_live_pdo_state),
        effective_source: pdo_effective_source(
          plan_source,
          preparation.prefer_live_pdo_state,
          live_detected,
        ),
        live_detected: None,
        live_differs_from_plan: None,
        live_read_error: Some(err.to_string()),
        configured_rx,
        configured_tx,
        live_rx: None,
        live_tx: None,
        mismatches: [],
      }
    }
  }
}

///|
fn[N : @hal.Nic] resolve_station_startup_decision(
  nic : N,
  args : Array[String],
  station : UInt,
  logical_base : UInt,
  timeout : @hal.Duration,
) -> StationStartupDecision raise @hal.EcError {
  let preparation = prepare_station_startup_from_args(
    nic, args, station, logical_base, timeout,
  )
  {
    preparation,
    pdo_audit: build_pdo_audit_report(nic, args, station, preparation, timeout),
  }
}
