///|
/// Runtime diagnosis helpers that expose standard EtherCAT diagnostics
/// objects to applications via CoE SDO.

///|
/// SlaveDiagnosis aggregates a minimal diagnosis snapshot for one slave.
pub(all) struct SlaveDiagnosis {
  station_address : UInt
  /// CiA-301 Error Register (0x1001:0)
  error_register : Byte
  /// Diagnosis history object counter (0x10F3:0), when available.
  diagnosis_counter : UInt?
} derive(Eq, Show)

///|
/// DiagnosisSession captures the state needed around a diagnosis run.
pub(all) struct DiagnosisSession {
  original_state : @protocol.EsmState
  mailbox_config : @mailbox.MailboxConfig
}

///|
let diagnosis_mailbox_max_polls : Int = 32

///|
let diagnosis_sm_window_size : Int = 8

///|
let diagnosis_sdo_max_attempts : Int = 3

///|
let diagnosis_sii_word_count : Int = 128

///|
/// Parse a one-byte error register payload.
pub fn parse_error_register_payload(payload : Bytes) -> Byte raise @hal.EcError {
  if payload.length() < 1 {
    raise @hal.EcError::MailboxProtocol(
      "diagnosis: error register payload too short",
    )
  }
  payload[0]
}

///|
/// Parse a little-endian UInt32 payload.
pub fn parse_u32_payload(payload : Bytes) -> UInt raise @hal.EcError {
  if payload.length() < 4 {
    raise @hal.EcError::MailboxProtocol("diagnosis: u32 payload too short")
  }
  payload[0].to_uint() |
  (payload[1].to_uint() << 8) |
  (payload[2].to_uint() << 16) |
  (payload[3].to_uint() << 24)
}

///|
/// Read Error Register (0x1001:0) from one slave.
pub fn[N : @hal.Nic] read_error_register(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let payload = diagnosis_timeout_step(
    try? @protocol.sdo_upload_retry(
      nic, station, mb_config, rmsm, 0x1001U, b'\x00', timeout,
    ),
    "CoE 0x1001:0 upload",
  )
  parse_error_register_payload(payload)
}

///|
/// Read diagnosis object counter (0x10F3:0) from one slave.
/// Some slaves may not implement this object; callers can handle errors.
pub fn[N : @hal.Nic] read_diagnosis_counter(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let payload = diagnosis_timeout_step(
    try? @protocol.sdo_upload_retry(
      nic, station, mb_config, rmsm, 0x10F3U, b'\x00', timeout,
    ),
    "CoE 0x10F3:0 upload",
  )
  parse_u32_payload(payload)
}

///|
/// Read Error Register (0x1001:0) from one slave via AP mailbox transport.
pub fn[N : @hal.Nic] read_error_register_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> Byte raise @hal.EcError {
  let payload = diagnosis_sdo_upload_ap(
    nic, position, station, mb_config, rmsm, 0x1001U, b'\x00', timeout, "AP CoE 0x1001:0 upload",
  )
  parse_error_register_payload(payload)
}

///|
/// Read diagnosis object counter (0x10F3:0) via AP mailbox transport.
pub fn[N : @hal.Nic] read_diagnosis_counter_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let payload = diagnosis_sdo_upload_ap(
    nic, position, station, mb_config, rmsm, 0x10F3U, b'\x00', timeout, "AP CoE 0x10F3:0 upload",
  )
  parse_u32_payload(payload)
}

///|
/// Read a diagnosis snapshot for one slave.
/// If 0x10F3 is unavailable, the counter is returned as None.
pub fn[N : @hal.Nic] read_slave_diagnosis(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> SlaveDiagnosis raise @hal.EcError {
  let err = read_error_register(nic, station, mb_config, rmsm, timeout)
  let diag = Some(
    read_diagnosis_counter(nic, station, mb_config, rmsm, timeout),
  ) catch {
    _ => None
  }
  { station_address: station, error_register: err, diagnosis_counter: diag }
}

///|
/// Read a diagnosis snapshot for one slave via AP mailbox transport.
pub fn[N : @hal.Nic] read_slave_diagnosis_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> SlaveDiagnosis raise @hal.EcError {
  let err = read_error_register_ap(
    nic, position, station, mb_config, rmsm, timeout,
  )
  let diag = Some(
    read_diagnosis_counter_ap(nic, position, station, mb_config, rmsm, timeout),
  ) catch {
    _ => None
  }
  { station_address: station, error_register: err, diagnosis_counter: diag }
}

///|
/// Prepare one slave for mailbox-based diagnosis via AP discovery and FP state control.
///
/// This flow is intentionally diagnosis-specific: it normalizes the slave back to
/// Init before entering PreOp so mailbox SM programming happens from a known base state.
pub fn[N : @hal.Nic] prepare_slave_diagnosis_ap(
  nic : N,
  position : UInt,
  station : UInt,
  timeout : @hal.Duration,
) -> DiagnosisSession raise @hal.EcError {
  let original_state_result : Result[@protocol.EsmState, Error] = try? diagnosis_timeout_step(
    try? @protocol.read_al_status(nic, station, timeout),
    "diagnosis.prepare.read_al_status_fp",
  )
  let original_state = match original_state_result {
    Ok(state) => state
    Err(_) => @protocol.Init
  }
  let eeprom = diagnosis_timeout_step(
    try? @protocol.eeprom_read_ap(
      nic, position, 0U, diagnosis_sii_word_count, timeout,
    ),
    "diagnosis.prepare.eeprom_read_ap",
  )
  let sii = @mailbox.parse_sii_header(eeprom)
  let mailbox_config = @mailbox.MailboxConfig::from_sii(sii)
  if not(mailbox_config.is_valid()) {
    raise @hal.EcError::ConfigMismatch(
      "diagnosis requires mailbox-capable slave at station " +
      station.to_string(),
    )
  }
  configure_diagnosis_mailbox_sms(nic, station, eeprom, timeout)
  enter_diagnosis_preop(nic, station, original_state, timeout)
  { original_state, mailbox_config }
}

///|
/// Restore a slave after diagnosis using a legal path from PreOp back to the original state.
pub fn[N : @hal.Nic] restore_slave_diagnosis_state(
  nic : N,
  station : UInt,
  original_state : @protocol.EsmState,
  timeout : @hal.Duration,
) -> @protocol.EsmState raise @hal.EcError {
  let restore_path = diagnosis_restore_path(original_state)
  diagnosis_timeout_step(
    try? @protocol.transition_through(nic, station, restore_path, timeout),
    "diagnosis.restore_original_state_fp",
  )
}

///|
/// Build the diagnosis-specific restore path from PreOp back to the target state.
pub fn diagnosis_restore_path(
  target : @protocol.EsmState,
) -> Array[@protocol.EsmState] {
  match target {
    @protocol.PreOp => [@protocol.PreOp]
    @protocol.SafeOp => [@protocol.PreOp, @protocol.SafeOp]
    @protocol.Op => [@protocol.PreOp, @protocol.SafeOp, @protocol.Op]
    @protocol.Init => [@protocol.PreOp, @protocol.Init]
    @protocol.Boot => [@protocol.PreOp, @protocol.Init, @protocol.Boot]
  }
}

///|
fn[T] diagnosis_timeout_step(
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
fn[N : @hal.Nic] configure_diagnosis_mailbox_sms(
  nic : N,
  station : UInt,
  eeprom : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let mapping = @mailbox.calculate_slave_mapping(eeprom, 0U)
  for i = 0; i < mapping.sm_configs.length(); i = i + 1 {
    let sm = mapping.sm_configs[i]
    match sm.sm_type {
      @mailbox.MailboxOut | @mailbox.MailboxIn => {
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
}

///|
fn[N : @hal.Nic] enter_diagnosis_preop(
  nic : N,
  station : UInt,
  original_state : @protocol.EsmState,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  if original_state != @protocol.Init {
    ignore(
      diagnosis_timeout_step(
        try? @protocol.transition_through(
          nic,
          station,
          @protocol.build_shutdown_path(original_state),
          timeout,
        ),
        "diagnosis.prepare.request_init_fp",
      ),
    )
  }
  let confirmed_preop = diagnosis_timeout_step(
    try? @protocol.transition_through(
      nic,
      station,
      @protocol.build_transition_path(@protocol.PreOp),
      timeout,
    ),
    "diagnosis.prepare.request_preop_fp",
  )
  if confirmed_preop != @protocol.PreOp {
    let status_code = try? @protocol.read_al_status_code(nic, station, timeout)
    let status_code_text = match status_code {
      Ok(code) => code.to_string()
      Err(err) => err.to_string()
    }
    raise @hal.EcError::Internal(
      "diagnosis failed to enter PreOp: actual=" +
      confirmed_preop.to_string() +
      ", AL status code=" +
      status_code_text,
    )
  }
}

///|
fn[N : @hal.Nic] diagnosis_sdo_upload_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
  stage : String,
) -> Bytes raise @hal.EcError {
  for attempt = 0; attempt < diagnosis_sdo_max_attempts; attempt = attempt + 1 {
    let result = try? diagnosis_sdo_upload_ap_once(
      nic, position, station, mb_config, rmsm, index, subindex, timeout, stage,
    )
    match result {
      Ok(payload) => return payload
      Err(@hal.EcError::Internal(message)) =>
        if message.contains("MailboxTimeout") &&
          attempt + 1 < diagnosis_sdo_max_attempts {
          rmsm.reset()
          diagnosis_drain_mailbox_fp(nic, station, mb_config)
        } else {
          raise @hal.EcError::Internal(message)
        }
      Err(@hal.EcError::MailboxTimeout) =>
        if attempt + 1 < diagnosis_sdo_max_attempts {
          rmsm.reset()
          diagnosis_drain_mailbox_fp(nic, station, mb_config)
        } else {
          raise @hal.EcError::MailboxTimeout
        }
      Err(err) => raise err
    }
  }
  raise @hal.EcError::MailboxTimeout
}

///|
fn[N : @hal.Nic] diagnosis_sdo_upload_ap_once(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
  stage : String,
) -> Bytes raise @hal.EcError {
  ignore(position)
  let counter = diagnosis_timeout_step(
    try? rmsm.begin_transaction(),
    stage + ".begin_transaction",
  )
  let txn = @mailbox.build_sdo_upload(counter, station, index, subindex)
  let frame = txn.encode()
  diagnosis_drain_mailbox_fp(nic, station, mb_config)
  let _ = diagnosis_timeout_step(
    try? @protocol.mailbox_send(nic, station, mb_config, frame, timeout),
    stage + ".mailbox_send_fp",
  )
  let response_raw = diagnosis_mailbox_recv_fp(
    nic,
    station,
    mb_config,
    timeout,
    stage + ".mailbox_recv_fp",
  )
  let decoded = diagnosis_timeout_step(
    try? @mailbox.decode_sdo_response(response_raw),
    stage + ".decode_sdo_response",
  )
  let (mbh, resp) = decoded
  diagnosis_accept_response_counter(rmsm, mbh.counter)
  if resp.command != @mailbox.SdoCommand::UploadResponse {
    raise @hal.EcError::MailboxProtocol(
      stage + ": expected UploadResponse, got " + resp.command.to_string(),
    )
  }
  if resp.index != index || resp.subindex != subindex {
    raise @hal.EcError::MailboxProtocol(
      stage + ": index/subindex mismatch in response",
    )
  }
  if resp.segmented {
    raise @hal.EcError::MailboxProtocol(
      stage + ": segmented response is not supported in diagnosis path",
    )
  }
  resp.data
}

///|
fn[N : @hal.Nic] diagnosis_mailbox_recv_fp(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  timeout : @hal.Duration,
  stage : String,
) -> Bytes raise @hal.EcError {
  for _attempt = 0
      _attempt < diagnosis_mailbox_max_polls
      _attempt = _attempt + 1 {
    let ready = diagnosis_timeout_step(
      try? @protocol.mailbox_poll(nic, station, mb_config, timeout),
      stage + ".poll_status",
    )
    if ready {
      return diagnosis_timeout_step(
        try? @protocol.mailbox_recv(
          nic,
          station,
          mb_config,
          timeout,
          max_polls=1,
        ),
        stage + ".read_frame",
      )
    }
  }
  let sm0_status = diagnosis_register_snapshot(
    try? @protocol.read_register_fp(
      nic, station, @protocol.reg_sm_base, diagnosis_sm_window_size, timeout,
    ),
  )
  let sm1_status = diagnosis_register_snapshot(
    try? @protocol.read_register_fp(
      nic,
      station,
      @protocol.reg_sm_base + @protocol.sm_entry_size.reinterpret_as_uint(),
      diagnosis_sm_window_size,
      timeout,
    ),
  )
  let al_status = diagnosis_register_snapshot(
    try? @protocol.read_register_fp(
      nic, station, @protocol.reg_al_status, 2, timeout,
    ),
  )
  raise @hal.EcError::Internal(
    "timeout at " +
    stage +
    ".poll_status (MailboxTimeout; SM0=" +
    sm0_status +
    "; SM1=" +
    sm1_status +
    "; AL=" +
    al_status +
    ")",
  )
}

///|
fn[N : @hal.Nic] diagnosis_drain_mailbox_fp(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
) -> Unit {
  let zero_timeout = @hal.Duration(0L)
  let poll_result = try? @protocol.mailbox_poll(
    nic, station, mb_config, zero_timeout,
  )
  match poll_result {
    Ok(true) =>
      ignore(
        try? @protocol.mailbox_recv(
          nic,
          station,
          mb_config,
          zero_timeout,
          max_polls=1,
        ),
      )
    _ => ()
  }
}

///|
fn diagnosis_register_snapshot(result : Result[@protocol.Pdu, Error]) -> String {
  match result {
    Ok(pdu) => diagnosis_bytes_preview(pdu.data)
    Err(err) => "error=" + err.to_string()
  }
}

///|
fn diagnosis_accept_response_counter(
  rmsm : @mailbox.Rmsm,
  counter : Byte,
) -> Unit raise @hal.EcError {
  let validation = try? rmsm.validate_response(counter)
  match validation {
    Ok(_) => ()
    Err(@hal.EcError::MailboxProtocol(message)) =>
      if message.contains("counter mismatch") {
        rmsm.reset()
      } else {
        raise @hal.EcError::MailboxProtocol(message)
      }
    Err(err) => raise err
  }
}

///|
fn diagnosis_bytes_preview(data : Bytes) -> String {
  if data.length() == 0 {
    return "<empty>"
  }
  let mut rendered = ""
  for i = 0; i < data.length(); i = i + 1 {
    if i > 0 {
      rendered = rendered + " "
    }
    rendered = rendered + diagnosis_hex_byte(data[i])
  }
  rendered
}

///|
fn diagnosis_hex_byte(value : Byte) -> String {
  "0x" +
  diagnosis_hex_digit((value.to_int() >> 4) & 0xF) +
  diagnosis_hex_digit(value.to_int() & 0xF)
}

///|
fn diagnosis_hex_digit(value : Int) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "A"
    11 => "B"
    12 => "C"
    13 => "D"
    14 => "E"
    _ => "F"
  }
}
