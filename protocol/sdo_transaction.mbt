///|
/// SDO transaction layer: complete SDO Upload/Download using
/// mailbox transport, RMSM counter management, and CoE encoding/decoding.
/// Implements ETG.1500 #501 (SDO Up/Download shall).

///|
/// Execute an SDO Download (write to slave Object Dictionary).
/// Encodes the request, sends via mailbox, waits for response, validates.
/// Supports expedited transfer (data ≤ 4 bytes).
pub fn[N : @hal.Nic] sdo_download(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  data : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let counter = rmsm.begin_transaction()
  let txn = @mailbox.build_sdo_download(counter, station, index, subindex, data)
  let frame = txn.encode()
  // Send request via mailbox SM
  mailbox_send(nic, station, mb_config, frame, timeout)
  // Wait for response
  let response_raw = mailbox_recv(nic, station, mb_config, timeout)
  // Decode and validate
  let (mbh, resp) = @mailbox.decode_sdo_response(response_raw)
  // Validate RMSM counter
  let _ = rmsm.validate_response(mbh.counter)
  // Check for expected Download Response
  if resp.command != @mailbox.SdoCommand::DownloadResponse {
    raise @hal.EcError::MailboxProtocol(
      "SDO download: expected DownloadResponse, got " + resp.command.to_string(),
    )
  }
  // Verify index/subindex match
  if resp.index != index || resp.subindex != subindex {
    raise @hal.EcError::MailboxProtocol(
      "SDO download: index/subindex mismatch in response",
    )
  }
}

///|
/// Execute an SDO Upload (read from slave Object Dictionary).
/// Encodes the request, sends via mailbox, waits for response, returns data.
/// Supports expedited transfer (data ≤ 4 bytes).
pub fn[N : @hal.Nic] sdo_upload(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let counter = rmsm.begin_transaction()
  let txn = @mailbox.build_sdo_upload(counter, station, index, subindex)
  let frame = txn.encode()
  // Send request via mailbox SM
  mailbox_send(nic, station, mb_config, frame, timeout)
  // Wait for response
  let response_raw = mailbox_recv(nic, station, mb_config, timeout)
  // Decode and validate
  let (mbh, resp) = @mailbox.decode_sdo_response(response_raw)
  // Validate RMSM counter
  let _ = rmsm.validate_response(mbh.counter)
  // Check for expected Upload Response
  if resp.command != @mailbox.SdoCommand::UploadResponse {
    raise @hal.EcError::MailboxProtocol(
      "SDO upload: expected UploadResponse, got " + resp.command.to_string(),
    )
  }
  // Verify index/subindex match
  if resp.index != index || resp.subindex != subindex {
    raise @hal.EcError::MailboxProtocol(
      "SDO upload: index/subindex mismatch in response",
    )
  }
  if not(resp.segmented) {
    return resp.data
  }

  // Segmented upload: collect all upload segment responses.
  let acc = @buffer.new(
    size_hint=match resp.complete_size {
      Some(sz) => sz.reinterpret_as_int()
      None => 64
    },
  )
  for b in resp.data {
    acc.write_byte(b)
  }

  let mut current = resp
  let mut toggle = false
  while not(current.last_segment) {
    let seg_counter = rmsm.begin_transaction()
    let seg_req = @mailbox.build_sdo_upload_segment_request(
      seg_counter, station, toggle,
    )
    mailbox_send(nic, station, mb_config, seg_req, timeout)
    let seg_raw = mailbox_recv(nic, station, mb_config, timeout)
    let (seg_mbh, seg_resp) = @mailbox.decode_sdo_response(seg_raw)
    let _ = rmsm.validate_response(seg_mbh.counter)
    if seg_resp.command != @mailbox.SdoCommand::UploadResponse ||
      not(seg_resp.segmented) {
      raise @hal.EcError::MailboxProtocol(
        "SDO upload: expected segmented UploadResponse",
      )
    }
    if seg_resp.toggle != toggle {
      raise @hal.EcError::MailboxProtocol("SDO upload: segment toggle mismatch")
    }
    for b in seg_resp.data {
      acc.write_byte(b)
    }
    current = seg_resp
    toggle = not(toggle)
  }

  let out = acc.to_bytes()
  match current.complete_size {
    Some(sz) =>
      if out.length() >= sz.reinterpret_as_int() {
        Bytes::makei(sz.reinterpret_as_int(), fn(i) { out[i] })
      } else {
        out
      }
    None => out
  }
}

///|
/// Execute an SDO Download with RMSM retry support.
/// Retries on MailboxTimeout up to RMSM's max_retries limit.
pub fn[N : @hal.Nic] sdo_download_retry(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  data : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  // First attempt
  let result = try? sdo_download(
    nic, station, mb_config, rmsm, index, subindex, data, timeout,
  )
  match result {
    Ok(_) => return
    Err(@hal.EcError::MailboxTimeout) => ()
    Err(e) => raise e
  }
  // Retry loop
  for {
    if not(rmsm.record_timeout()) {
      raise @hal.EcError::MailboxTimeout
    }
    rmsm.reset()
    let result = try? sdo_download(
      nic, station, mb_config, rmsm, index, subindex, data, timeout,
    )
    match result {
      Ok(_) => return
      Err(@hal.EcError::MailboxTimeout) => continue
      Err(e) => raise e
    }
  }
}

///|
/// Execute an SDO Upload with RMSM retry support.
/// Retries on MailboxTimeout up to RMSM's max_retries limit.
pub fn[N : @hal.Nic] sdo_upload_retry(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  // First attempt
  let result = try? sdo_upload(
    nic, station, mb_config, rmsm, index, subindex, timeout,
  )
  match result {
    Ok(data) => return data
    Err(@hal.EcError::MailboxTimeout) => ()
    Err(e) => raise e
  }
  // Retry loop
  for {
    if not(rmsm.record_timeout()) {
      raise @hal.EcError::MailboxTimeout
    }
    rmsm.reset()
    let result = try? sdo_upload(
      nic, station, mb_config, rmsm, index, subindex, timeout,
    )
    match result {
      Ok(data) => return data
      Err(@hal.EcError::MailboxTimeout) => continue
      Err(e) => raise e
    }
  }
}

///|
/// Execute an SDO Download with Complete Access enabled.
pub fn[N : @hal.Nic] sdo_download_complete_access(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  data : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let counter = rmsm.begin_transaction()
  let txn = @mailbox.build_sdo_download_ca(
    counter, station, index, subindex, data,
  )
  let frame = txn.encode()
  mailbox_send(nic, station, mb_config, frame, timeout)
  let response_raw = mailbox_recv(nic, station, mb_config, timeout)
  let (mbh, resp) = @mailbox.decode_sdo_response(response_raw)
  let _ = rmsm.validate_response(mbh.counter)
  if resp.command != @mailbox.SdoCommand::DownloadResponse {
    raise @hal.EcError::MailboxProtocol(
      "SDO CA download: expected DownloadResponse, got " +
      resp.command.to_string(),
    )
  }
}

///|
/// Execute an SDO Upload with Complete Access enabled.
pub fn[N : @hal.Nic] sdo_upload_complete_access(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let counter = rmsm.begin_transaction()
  let txn = @mailbox.build_sdo_upload_ca(counter, station, index, subindex)
  let frame = txn.encode()
  mailbox_send(nic, station, mb_config, frame, timeout)
  let response_raw = mailbox_recv(nic, station, mb_config, timeout)
  let (mbh, resp) = @mailbox.decode_sdo_response(response_raw)
  let _ = rmsm.validate_response(mbh.counter)
  if resp.command != @mailbox.SdoCommand::UploadResponse {
    raise @hal.EcError::MailboxProtocol(
      "SDO CA upload: expected UploadResponse, got " + resp.command.to_string(),
    )
  }
  if resp.segmented {
    raise @hal.EcError::MailboxProtocol(
      "SDO CA upload segmented continuation is not implemented yet",
    )
  } else {
    resp.data
  }
}
