///|
struct EscSyncManagerRegisterReport {
  index : Int
  register_offset : UInt
  raw_hex : String
  physical_start : UInt
  length : UInt
  control : Byte
  status : Byte
  activate : Byte
}

///|
struct EscFmmuRegisterReport {
  index : Int
  register_offset : UInt
  raw_hex : String
  logical_start : UInt
  length : UInt
  logical_start_bit : Byte
  logical_end_bit : Byte
  physical_start : UInt
  physical_start_bit : Byte
  type_register : Byte
  activate : Byte
}

///|
struct EscRegisterReport {
  station : UInt
  al_state : @protocol.EsmState
  al_error_flag : Bool
  al_status_code : UInt?
  sync_managers : Array[EscSyncManagerRegisterReport]
  fmmus : Array[EscFmmuRegisterReport]
}

///|
struct ExpectedEscRegisterReport {
  station : UInt
  sync_managers : Array[EscSyncManagerRegisterReport]
  fmmus : Array[EscFmmuRegisterReport]
}

///|
fn[N : @hal.Nic] read_esc_register_report(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> EscRegisterReport raise @hal.EcError {
  let snapshot = @protocol.read_al_status_snapshot(nic, station, timeout)
  let sync_managers : Array[EscSyncManagerRegisterReport] = []
  for index = 2; index <= 3; index = index + 1 {
    let register_offset = @protocol.reg_sm_base +
      index.reinterpret_as_uint() *
      @protocol.sm_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.sm_entry_size, timeout,
      ).data
    sync_managers.push(
      decode_esc_sync_manager_window(index, register_offset, window),
    )
  }
  let fmmus : Array[EscFmmuRegisterReport] = []
  for index = 0; index <= 1; index = index + 1 {
    let register_offset = @protocol.reg_fmmu_base +
      index.reinterpret_as_uint() *
      @protocol.fmmu_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.fmmu_entry_size, timeout,
      ).data
    fmmus.push(decode_esc_fmmu_window(index, register_offset, window))
  }
  {
    station,
    al_state: snapshot.state,
    al_error_flag: snapshot.error_indication,
    al_status_code: snapshot.status_code,
    sync_managers,
    fmmus,
  }
}

///|
fn[N : @hal.Nic] build_expected_esc_register_report(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> ExpectedEscRegisterReport raise @hal.EcError {
  let initial = prepare_station_startup(nic, station, pdo_logical_base, timeout)
  let refined = @runtime.refine_startup_preparation_in_preop(
    nic, station, pdo_logical_base, initial, timeout,
  )
  build_expected_esc_register_report_from_mapping(station, refined.mapping)
}

///|
fn build_expected_esc_register_report_from_mapping(
  station : UInt,
  mapping : @mailbox.SlaveMapping,
) -> ExpectedEscRegisterReport raise @hal.EcError {
  {
    station,
    sync_managers: expected_sync_manager_register_reports(mapping),
    fmmus: expected_fmmu_register_reports(mapping),
  }
}

///|
fn expected_sync_manager_register_reports(
  mapping : @mailbox.SlaveMapping,
) -> Array[EscSyncManagerRegisterReport] raise @hal.EcError {
  let reports : Array[EscSyncManagerRegisterReport] = []
  for index = 2; index <= 3; index = index + 1 {
    reports.push(expected_sync_manager_register_report(mapping, index))
  }
  reports
}

///|
fn expected_sync_manager_register_report(
  mapping : @mailbox.SlaveMapping,
  index : Int,
) -> EscSyncManagerRegisterReport raise @hal.EcError {
  let register_offset = @protocol.reg_sm_base +
    index.reinterpret_as_uint() * @protocol.sm_entry_size.reinterpret_as_uint()
  let window = if index >= 0 && index < mapping.sm_configs.length() {
    mapping.sm_configs[index].to_bytes()
  } else {
    Bytes::new(@protocol.sm_entry_size)
  }
  decode_esc_sync_manager_window(index, register_offset, window)
}

///|
fn expected_fmmu_register_reports(
  mapping : @mailbox.SlaveMapping,
) -> Array[EscFmmuRegisterReport] raise @hal.EcError {
  let reports : Array[EscFmmuRegisterReport] = []
  for index = 0; index <= 1; index = index + 1 {
    reports.push(expected_fmmu_register_report(mapping, index))
  }
  reports
}

///|
fn expected_fmmu_register_report(
  mapping : @mailbox.SlaveMapping,
  index : Int,
) -> EscFmmuRegisterReport raise @hal.EcError {
  let register_offset = @protocol.reg_fmmu_base +
    index.reinterpret_as_uint() *
    @protocol.fmmu_entry_size.reinterpret_as_uint()
  let window = if index >= 0 && index < mapping.fmmu_configs.length() {
    mapping.fmmu_configs[index].to_bytes()
  } else {
    Bytes::new(@protocol.fmmu_entry_size)
  }
  decode_esc_fmmu_window(index, register_offset, window)
}

///|
fn decode_esc_sync_manager_window(
  index : Int,
  register_offset : UInt,
  window : Bytes,
) -> EscSyncManagerRegisterReport raise @hal.EcError {
  if window.length() < @protocol.sm_entry_size {
    raise @hal.EcError::Internal(
      "short SyncManager register window at 0x" +
      format_hex(register_offset, 4) +
      ": expected " +
      @protocol.sm_entry_size.to_string() +
      " bytes, got " +
      window.length().to_string(),
    )
  }
  {
    index,
    register_offset,
    raw_hex: bytes_hex(window),
    physical_start: decode_u16_le(window, 0),
    length: decode_u16_le(window, 2),
    control: window[4],
    status: window[5],
    activate: window[6],
  }
}

///|
fn decode_esc_fmmu_window(
  index : Int,
  register_offset : UInt,
  window : Bytes,
) -> EscFmmuRegisterReport raise @hal.EcError {
  if window.length() < @protocol.fmmu_entry_size {
    raise @hal.EcError::Internal(
      "short FMMU register window at 0x" +
      format_hex(register_offset, 4) +
      ": expected " +
      @protocol.fmmu_entry_size.to_string() +
      " bytes, got " +
      window.length().to_string(),
    )
  }
  {
    index,
    register_offset,
    raw_hex: bytes_hex(window),
    logical_start: decode_u32_le(window, 0),
    length: decode_u16_le(window, 4),
    logical_start_bit: window[6],
    logical_end_bit: window[7],
    physical_start: decode_u16_le(window, 8),
    physical_start_bit: window[10],
    type_register: window[11],
    activate: window[12],
  }
}

///|
fn esc_register_report_json(report : EscRegisterReport) -> Json {
  Json::object({
    "station": Json::number(report.station.to_double()),
    "al_state": Json::string(report.al_state.to_string()),
    "al_error_flag": Json::boolean(report.al_error_flag),
    "al_status_code": option_uint_json(report.al_status_code),
    "al_status_code_description": match report.al_status_code {
      Some(code) => Json::string(@protocol.al_status_code_description(code))
      None => Json::null()
    },
    "sync_managers": Json::array(
      report.sync_managers.map(fn(sm) {
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
      report.fmmus.map(fn(fmmu) {
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
          "type_description": Json::string(
            esc_fmmu_type_description(fmmu.type_register),
          ),
          "activate": Json::number(fmmu.activate.to_uint().to_double()),
          "enabled": Json::boolean((fmmu.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
  })
}

///|
fn expected_esc_register_report_json(
  report : ExpectedEscRegisterReport,
) -> Json {
  Json::object({
    "station": Json::number(report.station.to_double()),
    "sync_managers": Json::array(
      report.sync_managers.map(fn(sm) {
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
      report.fmmus.map(fn(fmmu) {
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
          "type_description": Json::string(
            esc_fmmu_type_description(fmmu.type_register),
          ),
          "activate": Json::number(fmmu.activate.to_uint().to_double()),
          "enabled": Json::boolean((fmmu.activate & b'\x01') != b'\x00'),
        })
      }),
    ),
  })
}

///|
fn esc_register_report_text(report : EscRegisterReport) -> String {
  let buf = @buffer.new(size_hint=768)
  let al_error_flag_text = if report.al_error_flag { "set" } else { "clear" }
  let al_status_code_text = match report.al_status_code {
    Some(code) =>
      format_hex(code, 4) +
      " (" +
      @protocol.al_status_code_description(code) +
      ")"
    None => "not set"
  }
  buf.write_string("EtherCAT ESC Register Snapshot\n")
  buf.write_string("============================\n")
  buf.write_string("Station: " + report.station.to_string() + "\n")
  buf.write_string("AL State: " + report.al_state.to_string() + "\n")
  buf.write_string("AL Error Flag: " + al_error_flag_text + "\n")
  buf.write_string("AL Status Code: " + al_status_code_text + "\n\n")
  buf.write_string("SyncManagers\n")
  buf.write_string("------------\n")
  for sm in report.sync_managers {
    buf.write_string(
      "SM" +
      sm.index.to_string() +
      " @ " +
      format_hex(sm.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + sm.raw_hex + "\n")
    buf.write_string(
      "  Physical Start: ... " + format_hex(sm.physical_start, 4) + "\n",
    )
    buf.write_string("  Length: ........... " + sm.length.to_string() + "\n")
    buf.write_string(
      "  Control: .......... " + format_hex(sm.control.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Status: ........... " + format_hex(sm.status.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(sm.activate.to_uint(), 2) + "\n",
    )
  }
  buf.write_string("\nFMMU\n")
  buf.write_string("----\n")
  for fmmu in report.fmmus {
    buf.write_string(
      "FMMU" +
      fmmu.index.to_string() +
      " @ " +
      format_hex(fmmu.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + fmmu.raw_hex + "\n")
    buf.write_string(
      "  Logical Start: .... " + format_hex(fmmu.logical_start, 8) + "\n",
    )
    buf.write_string("  Length: ........... " + fmmu.length.to_string() + "\n")
    buf.write_string(
      "  Logical Bits: ..... " +
      fmmu.logical_start_bit.to_uint().to_string() +
      "-" +
      fmmu.logical_end_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Physical Start: ... " + format_hex(fmmu.physical_start, 4) + "\n",
    )
    buf.write_string(
      "  Physical Bit: ..... " +
      fmmu.physical_start_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Type Register: .... " +
      format_hex(fmmu.type_register.to_uint(), 2) +
      " (" +
      esc_fmmu_type_description(fmmu.type_register) +
      ")\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(fmmu.activate.to_uint(), 2) + "\n",
    )
  }
  buf.to_string()
}

///|
fn expected_esc_register_report_text(
  report : ExpectedEscRegisterReport,
) -> String {
  let buf = @buffer.new(size_hint=640)
  buf.write_string("Expected EtherCAT ESC Process Mapping\n")
  buf.write_string("====================================\n")
  buf.write_string("Station: " + report.station.to_string() + "\n\n")
  buf.write_string("SyncManagers\n")
  buf.write_string("------------\n")
  for sm in report.sync_managers {
    buf.write_string(
      "SM" +
      sm.index.to_string() +
      " @ " +
      format_hex(sm.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + sm.raw_hex + "\n")
    buf.write_string(
      "  Physical Start: ... " + format_hex(sm.physical_start, 4) + "\n",
    )
    buf.write_string("  Length: ........... " + sm.length.to_string() + "\n")
    buf.write_string(
      "  Control: .......... " + format_hex(sm.control.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Status: ........... " + format_hex(sm.status.to_uint(), 2) + "\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(sm.activate.to_uint(), 2) + "\n",
    )
  }
  buf.write_string("\nFMMU\n")
  buf.write_string("----\n")
  for fmmu in report.fmmus {
    buf.write_string(
      "FMMU" +
      fmmu.index.to_string() +
      " @ " +
      format_hex(fmmu.register_offset, 4) +
      "\n",
    )
    buf.write_string("  Raw: .............. " + fmmu.raw_hex + "\n")
    buf.write_string(
      "  Logical Start: .... " + format_hex(fmmu.logical_start, 8) + "\n",
    )
    buf.write_string("  Length: ........... " + fmmu.length.to_string() + "\n")
    buf.write_string(
      "  Logical Bits: ..... " +
      fmmu.logical_start_bit.to_uint().to_string() +
      ".." +
      fmmu.logical_end_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Physical Start: ... " + format_hex(fmmu.physical_start, 4) + "\n",
    )
    buf.write_string(
      "  Physical Bit: ..... " +
      fmmu.physical_start_bit.to_uint().to_string() +
      "\n",
    )
    buf.write_string(
      "  Type: ............. " +
      format_hex(fmmu.type_register.to_uint(), 2) +
      " (" +
      esc_fmmu_type_description(fmmu.type_register) +
      ")\n",
    )
    buf.write_string(
      "  Activate: ......... " + format_hex(fmmu.activate.to_uint(), 2) + "\n",
    )
  }
  buf.to_string()
}

///|
fn[N : @hal.Nic] read_sync_manager_reports(
  nic : N,
  station : UInt,
  start_index : Int,
  end_index : Int,
  timeout : @hal.Duration,
) -> Array[EscSyncManagerRegisterReport] raise @hal.EcError {
  let reports : Array[EscSyncManagerRegisterReport] = []
  for index = start_index; index <= end_index; index = index + 1 {
    let register_offset = @protocol.reg_sm_base +
      index.reinterpret_as_uint() *
      @protocol.sm_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.sm_entry_size, timeout,
      ).data
    reports.push(decode_esc_sync_manager_window(index, register_offset, window))
  }
  reports
}

///|
fn[N : @hal.Nic] read_fmmu_reports(
  nic : N,
  station : UInt,
  start_index : Int,
  end_index : Int,
  timeout : @hal.Duration,
) -> Array[EscFmmuRegisterReport] raise @hal.EcError {
  let reports : Array[EscFmmuRegisterReport] = []
  for index = start_index; index <= end_index; index = index + 1 {
    let register_offset = @protocol.reg_fmmu_base +
      index.reinterpret_as_uint() *
      @protocol.fmmu_entry_size.reinterpret_as_uint()
    let window = @protocol.read_register_fp(
        nic, station, register_offset, @protocol.fmmu_entry_size, timeout,
      ).data
    reports.push(decode_esc_fmmu_window(index, register_offset, window))
  }
  reports
}
