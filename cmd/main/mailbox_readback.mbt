///|
struct MailboxReadbackEntry {
  index : Int
  register_offset : UInt
  expected : EscSyncManagerRegisterReport
  actual : EscSyncManagerRegisterReport
  matches : Bool
}

///|
struct MailboxReadbackReport {
  station : UInt
  source : String
  entries : Array[MailboxReadbackEntry]
  mismatches : Array[String]
}

///|
fn mailbox_readback_source(args : Array[String]) -> String {
  configured_startup_source(args)
}

///|
fn mailbox_sm_window_matches(expected : Bytes, actual : Bytes) -> Bool {
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
fn build_mailbox_readback_mismatch(entry : MailboxReadbackEntry) -> String {
  "SM" +
  entry.index.to_string() +
  " expected=" +
  entry.expected.raw_hex +
  " actual=" +
  entry.actual.raw_hex
}

///|
fn mailbox_readback_entry_json(entry : MailboxReadbackEntry) -> Json {
  Json::object({
    "index": Json::number(entry.index.to_double()),
    "register_offset": Json::number(entry.register_offset.to_double()),
    "expected": Json::object({
      "index": Json::number(entry.expected.index.to_double()),
      "register_offset": Json::number(
        entry.expected.register_offset.to_double(),
      ),
      "raw_hex": Json::string(entry.expected.raw_hex),
      "physical_start": Json::number(entry.expected.physical_start.to_double()),
      "length": Json::number(entry.expected.length.to_double()),
      "control": Json::number(entry.expected.control.to_uint().to_double()),
      "status": Json::number(entry.expected.status.to_uint().to_double()),
      "activate": Json::number(entry.expected.activate.to_uint().to_double()),
      "enabled": Json::boolean((entry.expected.activate & b'\x01') != b'\x00'),
    }),
    "actual": Json::object({
      "index": Json::number(entry.actual.index.to_double()),
      "register_offset": Json::number(entry.actual.register_offset.to_double()),
      "raw_hex": Json::string(entry.actual.raw_hex),
      "physical_start": Json::number(entry.actual.physical_start.to_double()),
      "length": Json::number(entry.actual.length.to_double()),
      "control": Json::number(entry.actual.control.to_uint().to_double()),
      "status": Json::number(entry.actual.status.to_uint().to_double()),
      "activate": Json::number(entry.actual.activate.to_uint().to_double()),
      "enabled": Json::boolean((entry.actual.activate & b'\x01') != b'\x00'),
    }),
    "matches": Json::boolean(entry.matches),
  })
}

///|
fn mailbox_readback_report_json(report : MailboxReadbackReport) -> Json {
  Json::object({
    "station": Json::number(report.station.to_double()),
    "source": Json::string(report.source),
    "entries": Json::array(report.entries.map(mailbox_readback_entry_json)),
    "mismatches": Json::array(report.mismatches.map(item => Json::string(item))),
  })
}

///|
fn mailbox_readback_report_text(report : MailboxReadbackReport) -> String {
  let buf = @buffer.new(size_hint=1024)
  buf.write_string("Mailbox SyncManager Readback\n")
  buf.write_string("==========================\n")
  buf.write_string("Station: " + report.station.to_string() + "\n")
  buf.write_string("Source: " + report.source + "\n\n")
  for entry in report.entries {
    buf.write_string(
      "SM" +
      entry.index.to_string() +
      " @ " +
      format_hex(entry.register_offset, 4) +
      "\n",
    )
    buf.write_string(
      "  Match: ............ " + entry.matches.to_string() + "\n",
    )
    buf.write_string("  Expected Raw: ..... " + entry.expected.raw_hex + "\n")
    buf.write_string("  Actual Raw: ....... " + entry.actual.raw_hex + "\n")
    buf.write_string(
      "  Expected Start: ... " +
      format_hex(entry.expected.physical_start, 4) +
      "\n",
    )
    buf.write_string(
      "  Actual Start: ..... " +
      format_hex(entry.actual.physical_start, 4) +
      "\n",
    )
    buf.write_string(
      "  Expected Length: .. " + entry.expected.length.to_string() + "\n",
    )
    buf.write_string(
      "  Actual Length: .... " + entry.actual.length.to_string() + "\n",
    )
    buf.write_string(
      "  Expected Control: . " +
      format_hex(entry.expected.control.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Actual Control: ... " +
      format_hex(entry.actual.control.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Expected Status: .. " +
      format_hex(entry.expected.status.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Actual Status: .... " +
      format_hex(entry.actual.status.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Expected Activate:  " +
      format_hex(entry.expected.activate.to_uint(), 2) +
      "\n",
    )
    buf.write_string(
      "  Actual Activate: .. " +
      format_hex(entry.actual.activate.to_uint(), 2) +
      "\n\n",
    )
  }
  buf.write_string("Mismatches\n")
  buf.write_string("----------\n")
  if report.mismatches.is_empty() {
    buf.write_string("No mismatches\n")
  } else {
    for item in report.mismatches {
      buf.write_string("- " + item + "\n")
    }
  }
  buf.to_string()
}

///|
fn[N : @hal.Nic] build_mailbox_readback_report(
  nic : N,
  args : Array[String],
  station : UInt,
  timeout : @hal.Duration,
) -> MailboxReadbackReport raise @hal.EcError {
  let preparation = prepare_station_startup_from_args(
    nic, args, station, pdo_logical_base, timeout,
  )
  let entries : Array[MailboxReadbackEntry] = []
  let mismatches : Array[String] = []
  for i = 0; i < preparation.mapping.sm_configs.length(); i = i + 1 {
    let sm = preparation.mapping.sm_configs[i]
    match sm.sm_type {
      @mailbox.MailboxOut | @mailbox.MailboxIn => {
        let register_offset = @protocol.reg_sm_base +
          i.reinterpret_as_uint() *
          @protocol.sm_entry_size.reinterpret_as_uint()
        let expected_window = sm.to_bytes()
        ignore(
          @protocol.write_register_fp(
            nic, station, register_offset, expected_window, timeout,
          ),
        )
        let actual_window = @protocol.read_register_fp(
            nic, station, register_offset, @protocol.sm_entry_size, timeout,
          ).data
        let entry = {
          index: i,
          register_offset,
          expected: decode_esc_sync_manager_window(
            i, register_offset, expected_window,
          ),
          actual: decode_esc_sync_manager_window(
            i, register_offset, actual_window,
          ),
          matches: mailbox_sm_window_matches(expected_window, actual_window),
        }
        if !entry.matches {
          mismatches.push(build_mailbox_readback_mismatch(entry))
        }
        entries.push(entry)
      }
      _ => ()
    }
  }
  { station, source: mailbox_readback_source(args), entries, mismatches }
}
