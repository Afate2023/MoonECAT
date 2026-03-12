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
  let payload = diagnosis_timeout_step(
    try? @protocol.sdo_upload_retry_ap(
      nic, position, station, mb_config, rmsm, 0x1001U, b'\x00', timeout,
    ),
    "AP CoE 0x1001:0 upload",
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
  let payload = diagnosis_timeout_step(
    try? @protocol.sdo_upload_retry_ap(
      nic, position, station, mb_config, rmsm, 0x10F3U, b'\x00', timeout,
    ),
    "AP CoE 0x10F3:0 upload",
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
fn[T] diagnosis_timeout_step(
  result : Result[T, Error],
  stage : String,
) -> T raise @hal.EcError {
  match result {
    Ok(value) => value
    Err(@hal.EcError::RecvTimeout) =>
      raise @hal.EcError::Internal("timeout at " + stage + " (RecvTimeout)")
    Err(@hal.EcError::MailboxTimeout) =>
      raise @hal.EcError::Internal(
        "timeout at " + stage + " (MailboxTimeout)",
      )
    Err(@hal.EcError::Internal(message)) if message.contains("timeout at ") =>
      raise @hal.EcError::Internal(stage + " -> " + message)
    Err(err) => raise @hal.EcError::Internal(err.to_string())
  }
}
