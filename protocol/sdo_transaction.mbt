///|
/// SDO transaction layer: complete SDO Upload/Download using
/// mailbox transport, RMSM counter management, and CoE encoding/decoding.
/// Implements ETG.1500 #501 (SDO Up/Download shall).

///|
fn rmsm_begin_transaction(
  rmsm : @mailbox.Rmsm,
  retry : Bool,
) -> Byte raise @hal.EcError {
  if retry {
    rmsm.begin_retry_transaction()
  } else {
    rmsm.begin_transaction()
  }
}

///|
fn[N : @hal.Nic] sdo_download_once(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  data : Bytes,
  timeout : @hal.Duration,
  retry : Bool,
) -> Unit raise @hal.EcError {
  if data.length() > 4 {
    return sdo_download_segmented(
      nic,
      station,
      mb_config,
      rmsm,
      index,
      subindex,
      data,
      timeout,
      false,
      retry,
    )
  }

  let counter = rmsm_begin_transaction(rmsm, retry)
  let txn = @mailbox.build_sdo_download(counter, station, index, subindex, data)
  let frame = txn.encode()
  mailbox_send(nic, station, mb_config, frame, timeout)
  let response_raw = mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
  let (mbh, resp) = @mailbox.decode_sdo_response(response_raw)
  let _ = rmsm.validate_response(mbh.counter)
  if resp.command != @mailbox.SdoCommand::DownloadResponse {
    raise @hal.EcError::MailboxProtocol(
      "SDO download: expected DownloadResponse, got " + resp.command.to_string(),
    )
  }
  if resp.index != index || resp.subindex != subindex {
    raise @hal.EcError::MailboxProtocol(
      "SDO download: index/subindex mismatch in response",
    )
  }
}

///|
fn[N : @hal.Nic] sdo_upload_once(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
  retry : Bool,
) -> Bytes raise @hal.EcError {
  let counter = rmsm_begin_transaction(rmsm, retry)
  let txn = @mailbox.build_sdo_upload(counter, station, index, subindex)
  let frame = txn.encode()
  mailbox_send(nic, station, mb_config, frame, timeout)
  let response_raw = mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
  let (mbh, resp) = @mailbox.decode_sdo_response(response_raw)
  let _ = rmsm.validate_response(mbh.counter)
  if resp.command != @mailbox.SdoCommand::UploadResponse {
    raise @hal.EcError::MailboxProtocol(
      "SDO upload: expected UploadResponse, got " + resp.command.to_string(),
    )
  }
  if resp.index != index || resp.subindex != subindex {
    raise @hal.EcError::MailboxProtocol(
      "SDO upload: index/subindex mismatch in response",
    )
  }
  if not(resp.segmented) {
    return resp.data
  }

  sdo_upload_collect_segmented(
    nic,
    station,
    mb_config,
    rmsm,
    timeout,
    resp,
    "SDO upload",
    retry,
  )
}

///|
fn[N : @hal.Nic] sdo_upload_ap_once(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
  retry : Bool,
) -> Bytes raise @hal.EcError {
  let counter = rmsm_begin_transaction(rmsm, retry)
  let txn = @mailbox.build_sdo_upload(counter, station, index, subindex)
  let frame = txn.encode()
  mailbox_send_ap(nic, position, mb_config, frame, timeout)
  let response_raw = mailbox_recv_ap_rmsm(
    nic, position, mb_config, rmsm, timeout,
  )
  let (mbh, resp) = @mailbox.decode_sdo_response(response_raw)
  let _ = rmsm.validate_response(mbh.counter)
  if resp.command != @mailbox.SdoCommand::UploadResponse {
    raise @hal.EcError::MailboxProtocol(
      "SDO upload: expected UploadResponse, got " + resp.command.to_string(),
    )
  }
  if resp.index != index || resp.subindex != subindex {
    raise @hal.EcError::MailboxProtocol(
      "SDO upload: index/subindex mismatch in response",
    )
  }
  if not(resp.segmented) {
    return resp.data
  }

  sdo_upload_collect_segmented_ap(
    nic,
    position,
    station,
    mb_config,
    rmsm,
    timeout,
    resp,
    "SDO upload",
    retry,
  )
}

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
  sdo_download_once(
    nic, station, mb_config, rmsm, index, subindex, data, timeout, false,
  )
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
  sdo_upload_once(
    nic, station, mb_config, rmsm, index, subindex, timeout, false,
  )
}

///|
/// Execute an SDO Upload using auto-increment mailbox transport.
pub fn[N : @hal.Nic] sdo_upload_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  sdo_upload_ap_once(
    nic,
    position,
    station,
    mb_config,
    rmsm,
    index,
    subindex,
    timeout,
    false,
  )
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
  for ;; {
    if not(rmsm.record_timeout()) {
      raise @hal.EcError::MailboxTimeout
    }
    rmsm.reset_for_retry()
    let result = try? sdo_download_once(
      nic, station, mb_config, rmsm, index, subindex, data, timeout, true,
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
  for ;; {
    if not(rmsm.record_timeout()) {
      raise @hal.EcError::MailboxTimeout
    }
    rmsm.reset_for_retry()
    let result = try? sdo_upload_once(
      nic, station, mb_config, rmsm, index, subindex, timeout, true,
    )
    match result {
      Ok(data) => return data
      Err(@hal.EcError::MailboxTimeout) => continue
      Err(e) => raise e
    }
  }
}

///|
/// Execute an SDO Upload with RMSM retry support using auto-increment transport.
pub fn[N : @hal.Nic] sdo_upload_retry_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let result = try? sdo_upload_ap(
    nic, position, station, mb_config, rmsm, index, subindex, timeout,
  )
  match result {
    Ok(data) => return data
    Err(@hal.EcError::MailboxTimeout) => ()
    Err(e) => raise e
  }
  for ;; {
    if not(rmsm.record_timeout()) {
      raise @hal.EcError::MailboxTimeout
    }
    rmsm.reset_for_retry()
    let retry = try? sdo_upload_ap_once(
      nic,
      position,
      station,
      mb_config,
      rmsm,
      index,
      subindex,
      timeout,
      true,
    )
    match retry {
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
  if data.length() > 4 {
    return sdo_download_segmented(
      nic,
      station,
      mb_config,
      rmsm,
      index,
      subindex,
      data,
      timeout,
      true,
      false,
    )
  }

  let counter = rmsm.begin_transaction()
  let txn = @mailbox.build_sdo_download_ca(
    counter, station, index, subindex, data,
  )
  let frame = txn.encode()
  mailbox_send(nic, station, mb_config, frame, timeout)
  let response_raw = mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
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
  let response_raw = mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
  let (mbh, resp) = @mailbox.decode_sdo_response(response_raw)
  let _ = rmsm.validate_response(mbh.counter)
  if resp.command != @mailbox.SdoCommand::UploadResponse {
    raise @hal.EcError::MailboxProtocol(
      "SDO CA upload: expected UploadResponse, got " + resp.command.to_string(),
    )
  }
  if not(resp.segmented) {
    return resp.data
  }

  sdo_upload_collect_segmented(
    nic,
    station,
    mb_config,
    rmsm,
    timeout,
    resp,
    "SDO CA upload",
    false,
  )
}

///|
/// Read CoE SDO Info OD list and return object indices.
pub fn[N : @hal.Nic] sdo_info_get_od_list(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  list_type : UInt,
  timeout : @hal.Duration,
) -> Array[UInt] raise @hal.EcError {
  let counter = rmsm.begin_transaction()
  let req = @mailbox.build_sdo_info_get_od_list_request(
    counter, station, list_type,
  )
  let payload = sdo_info_collect_payload(
    nic, station, mb_config, rmsm, req, b'\x02', 2, timeout, "Get OD List",
  )
  @mailbox.decode_sdo_info_od_list_payload(payload)
}

///|
/// Read SDO Info Get OD (object description) for one object index.
pub fn[N : @hal.Nic] sdo_info_get_od_description(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  timeout : @hal.Duration,
) -> @mailbox.SdoInfoObjectDescription raise @hal.EcError {
  let counter = rmsm.begin_transaction()
  let req = @mailbox.build_sdo_info_get_od_request(counter, station, index)
  let payload = sdo_info_collect_payload(
    nic, station, mb_config, rmsm, req, b'\x04', 0, timeout, "Get OD",
  )
  @mailbox.decode_sdo_info_od_description_payload(payload)
}

///|
/// Read SDO Info Get OE (entry description) for one object entry.
pub fn[N : @hal.Nic] sdo_info_get_oe_description(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  value_info : Byte,
  timeout : @hal.Duration,
) -> @mailbox.SdoInfoEntryDescription raise @hal.EcError {
  let counter = rmsm.begin_transaction()
  let req = @mailbox.build_sdo_info_get_oe_request(
    counter, station, index, subindex, value_info,
  )
  let payload = sdo_info_collect_payload(
    nic, station, mb_config, rmsm, req, b'\x06', 0, timeout, "Get OE",
  )
  @mailbox.decode_sdo_info_oe_description_payload(payload)
}

///|
fn[N : @hal.Nic] sdo_upload_collect_segmented(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
  initial : @mailbox.SdoResponse,
  context : String,
  retry : Bool,
) -> Bytes raise @hal.EcError {
  let acc = @buffer.new(
    size_hint=match initial.complete_size {
      Some(sz) => sz.reinterpret_as_int()
      None => 64
    },
  )
  for b in initial.data {
    acc.write_byte(b)
  }

  let mut current = initial
  let mut toggle = false
  while not(current.last_segment) {
    let seg_counter = rmsm_begin_transaction(rmsm, retry)
    let seg_req = @mailbox.build_sdo_upload_segment_request(
      seg_counter, station, toggle,
    )
    mailbox_send(nic, station, mb_config, seg_req, timeout)
    let seg_raw = mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
    let (seg_mbh, seg_resp) = @mailbox.decode_sdo_response(seg_raw)
    let _ = rmsm.validate_response(seg_mbh.counter)
    if seg_resp.command != @mailbox.SdoCommand::UploadResponse ||
      not(seg_resp.segmented) {
      raise @hal.EcError::MailboxProtocol(
        context + ": expected segmented UploadResponse",
      )
    }
    if seg_resp.toggle != toggle {
      raise @hal.EcError::MailboxProtocol(context + ": segment toggle mismatch")
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
fn[N : @hal.Nic] sdo_upload_collect_segmented_ap(
  nic : N,
  position : UInt,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
  initial : @mailbox.SdoResponse,
  context : String,
  retry : Bool,
) -> Bytes raise @hal.EcError {
  let acc = @buffer.new(
    size_hint=match initial.complete_size {
      Some(sz) => sz.reinterpret_as_int()
      None => 64
    },
  )
  for b in initial.data {
    acc.write_byte(b)
  }

  let mut current = initial
  let mut toggle = false
  while not(current.last_segment) {
    let seg_counter = rmsm_begin_transaction(rmsm, retry)
    let seg_req = @mailbox.build_sdo_upload_segment_request(
      seg_counter, station, toggle,
    )
    mailbox_send_ap(nic, position, mb_config, seg_req, timeout)
    let seg_raw = mailbox_recv_ap_rmsm(nic, position, mb_config, rmsm, timeout)
    let (seg_mbh, seg_resp) = @mailbox.decode_sdo_response(seg_raw)
    let _ = rmsm.validate_response(seg_mbh.counter)
    if seg_resp.command != @mailbox.SdoCommand::UploadResponse ||
      not(seg_resp.segmented) {
      raise @hal.EcError::MailboxProtocol(
        context + ": expected segmented UploadResponse",
      )
    }
    if seg_resp.toggle != toggle {
      raise @hal.EcError::MailboxProtocol(context + ": segment toggle mismatch")
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
fn[N : @hal.Nic] sdo_download_segmented(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  index : UInt,
  subindex : Byte,
  data : Bytes,
  timeout : @hal.Duration,
  complete_access : Bool,
  retry : Bool,
) -> Unit raise @hal.EcError {
  let total_len = data.length().reinterpret_as_uint()
  let size_payload = Bytes::from_array([
    (total_len & 0xFFU).to_byte(),
    ((total_len >> 8) & 0xFFU).to_byte(),
    ((total_len >> 16) & 0xFFU).to_byte(),
    ((total_len >> 24) & 0xFFU).to_byte(),
  ])
  let init_counter = rmsm_begin_transaction(rmsm, retry)
  let init_txn = if complete_access {
    @mailbox.build_sdo_download_ca(
      init_counter, station, index, subindex, size_payload,
    )
  } else {
    @mailbox.build_sdo_download(
      init_counter, station, index, subindex, size_payload,
    )
  }
  mailbox_send(nic, station, mb_config, init_txn.encode(), timeout)
  let init_raw = mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
  let (init_mbh, init_resp) = @mailbox.decode_sdo_response(init_raw)
  let _ = rmsm.validate_response(init_mbh.counter)
  if init_resp.command != @mailbox.SdoCommand::DownloadResponse {
    raise @hal.EcError::MailboxProtocol(
      "SDO download segmented: expected DownloadResponse for initiate",
    )
  }

  let mut offset = 0
  let mut toggle = false
  while offset < data.length() {
    let remain = data.length() - offset
    let chunk_len = if remain > 7 { 7 } else { remain }
    let chunk = Bytes::makei(chunk_len, fn(i) { data[offset + i] })
    let last = offset + chunk_len >= data.length()
    let seg_counter = rmsm_begin_transaction(rmsm, retry)
    let seg_frame = @mailbox.build_sdo_download_segment_request(
      seg_counter, station, toggle, last, chunk,
    )
    mailbox_send(nic, station, mb_config, seg_frame, timeout)
    let seg_raw = mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
    let (seg_mbh, seg_resp) = @mailbox.decode_sdo_response(seg_raw)
    let _ = rmsm.validate_response(seg_mbh.counter)
    if seg_resp.command != @mailbox.SdoCommand::DownloadResponse ||
      not(seg_resp.segmented) {
      raise @hal.EcError::MailboxProtocol(
        "SDO download segmented: expected segmented DownloadResponse",
      )
    }
    if seg_resp.toggle != toggle {
      raise @hal.EcError::MailboxProtocol(
        "SDO download segmented: segment toggle mismatch",
      )
    }
    offset += chunk_len
    toggle = not(toggle)
  }
}

///|
fn[N : @hal.Nic] sdo_info_collect_payload(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  request_frame : Bytes,
  expected_opcode : Byte,
  first_fragment_skip : Int,
  timeout : @hal.Duration,
  context : String,
) -> Bytes raise @hal.EcError {
  mailbox_send(nic, station, mb_config, request_frame, timeout)
  let acc = @buffer.new(size_hint=64)
  let mut first = true
  let mut done = false
  while not(done) {
    let raw = mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
    let (mbh, info) = @mailbox.decode_sdo_info_response(raw)
    let _ = rmsm.validate_response(mbh.counter)
    if info.opcode != expected_opcode {
      raise @hal.EcError::MailboxProtocol(
        "SDO Info " +
        context +
        ": unexpected opcode " +
        info.opcode.to_int().to_string(),
      )
    }
    let payload = if first && first_fragment_skip > 0 {
      first = false
      if info.payload.length() < first_fragment_skip {
        raise @hal.EcError::MailboxProtocol(
          "SDO Info " + context + ": payload too short",
        )
      }
      Bytes::makei(info.payload.length() - first_fragment_skip, fn(i) {
        info.payload[first_fragment_skip + i]
      })
    } else {
      first = false
      info.payload
    }
    for b in payload {
      acc.write_byte(b)
    }
    done = not(info.incomplete)
  }
  acc.to_bytes()
}
