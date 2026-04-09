///|
/// FoE transaction layer: complete FoE Download/Upload using
/// mailbox transport, RMSM counter management, and FoE encoding/decoding.
/// Implements ETG.1000.6 §5.8 (File over EtherCAT).

///|
/// Maximum FoE Busy retries before giving up.
let foe_max_busy_retries : Int = 100

///|
/// Receive and validate a FoE response (FP addressing).
/// Discards stale/repeat frames via RMSM counter validation.
fn[N : @hal.Nic] recv_foe_validated_fp(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> @mailbox.FoeResponse raise @hal.EcError {
  for attempt = 0; attempt < max_stale_retries + 1; attempt = attempt + 1 {
    let response_raw = mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
    let (mbh, resp) = @mailbox.decode_foe_response(response_raw)
    if rmsm.validate_response(mbh.counter) {
      return resp
    }
  }
  raise @hal.EcError::MailboxProtocol("RMSM: too many stale frames received")
}

///|
/// Receive and validate a FoE response (AP addressing).
/// Discards stale/repeat frames via RMSM counter validation.
fn[N : @hal.Nic] recv_foe_validated_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
) -> @mailbox.FoeResponse raise @hal.EcError {
  for attempt = 0; attempt < max_stale_retries + 1; attempt = attempt + 1 {
    let response_raw = mailbox_recv_ap_rmsm(
      nic, position, mb_config, rmsm, timeout,
    )
    let (mbh, resp) = @mailbox.decode_foe_response(response_raw)
    if rmsm.validate_response(mbh.counter) {
      return resp
    }
  }
  raise @hal.EcError::MailboxProtocol("RMSM: too many stale frames received")
}

///|
/// Raise an EcError from a FoE error response.
fn foe_raise_error(
  code : @mailbox.FoeErrorCode,
  text : String,
) -> Unit raise @hal.EcError {
  let suffix = if text.length() > 0 { " - " + text } else { "" }
  raise @hal.EcError::MailboxProtocol("FoE error: " + code.to_string() + suffix)
}

///|
/// Patch the mailbox counter field (byte 5, bits 6:4) in a raw mailbox frame.
fn patch_mailbox_counter(frame : Bytes, new_counter : Byte) -> Bytes {
  Bytes::makei(frame.length(), fn(i) {
    if i == 5 {
      let type_bits = frame[5].to_int() & 0x0F
      let counter_bits = (new_counter.to_int() & 0x07) << 4
      (type_bits | counter_bits).to_byte()
    } else {
      frame[i]
    }
  })
}

///|
/// Handle a FoE response that may be Busy, retrying the given resend closure.
/// Returns the actual response (Data or Ack) when a non-Busy response arrives.
fn[N : @hal.Nic] foe_handle_busy(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  last_frame : Bytes,
  initial_resp : @mailbox.FoeResponse,
  timeout : @hal.Duration,
) -> @mailbox.FoeResponse raise @hal.EcError {
  let mut resp = initial_resp
  for retry = 0; retry < foe_max_busy_retries; retry = retry + 1 {
    guard resp is @mailbox.FoeResponse::FoeBusy else { return resp }
    // Begin a new retry transaction so RMSM expects the next counter
    let new_cnt = rmsm.begin_retry_transaction()
    let patched = patch_mailbox_counter(last_frame, new_cnt)
    mailbox_send(nic, station, mb_config, patched, timeout)
    resp = recv_foe_validated_fp(nic, station, mb_config, rmsm, timeout)
  }
  raise @hal.EcError::MailboxProtocol("FoE: too many Busy retries")
}

///|
/// Handle a FoE response that may be Busy (AP addressing).
fn[N : @hal.Nic] foe_handle_busy_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  last_frame : Bytes,
  initial_resp : @mailbox.FoeResponse,
  timeout : @hal.Duration,
) -> @mailbox.FoeResponse raise @hal.EcError {
  let mut resp = initial_resp
  for retry = 0; retry < foe_max_busy_retries; retry = retry + 1 {
    guard resp is @mailbox.FoeResponse::FoeBusy else { return resp }
    let new_cnt = rmsm.begin_retry_transaction()
    let patched = patch_mailbox_counter(last_frame, new_cnt)
    mailbox_send_ap(nic, position, mb_config, patched, timeout)
    resp = recv_foe_validated_ap(nic, position, mb_config, rmsm, timeout)
  }
  raise @hal.EcError::MailboxProtocol("FoE: too many Busy retries")
}

///|
/// FoE Download (write file to slave) using FP addressing.
///
/// Flow: Write(filename) → Ack(0) → Data(1) → Ack(1) → ... → Data(N) → Ack(N)
/// EOF is indicated when the last Data segment is shorter than max_data_per_segment.
/// If the data is an exact multiple of max_data_per_segment, an empty Data segment
/// is sent to signal EOF.
pub fn[N : @hal.Nic] foe_download(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  filename : String,
  password : UInt,
  data : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  // Max payload per FoE Data segment: SM out size minus mailbox header (6) minus FoE header (6)
  let max_data = mb_config.out_size.reinterpret_as_int() - 12
  if max_data <= 0 {
    raise @hal.EcError::MailboxProtocol(
      "FoE: mailbox too small for FoE transfer",
    )
  }
  // Step 1: Send Write request
  let counter0 = rmsm.begin_transaction()
  let write_frame = @mailbox.encode_foe_write(counter0, password, filename)
  mailbox_send(nic, station, mb_config, write_frame, timeout)
  // Expect Ack(0)
  let resp0 = recv_foe_validated_fp(nic, station, mb_config, rmsm, timeout)
  let resp0 = foe_handle_busy(
    nic, station, mb_config, rmsm, write_frame, resp0, timeout,
  )
  match resp0 {
    @mailbox.FoeResponse::FoeAck(packet_number=pn) =>
      if pn != 0U {
        raise @hal.EcError::MailboxProtocol(
          "FoE download: expected Ack(0), got Ack(" + pn.to_string() + ")",
        )
      }
    @mailbox.FoeResponse::FoeError(code=c, text=t) => foe_raise_error(c, t)
    _ =>
      raise @hal.EcError::MailboxProtocol(
        "FoE download: expected Ack, got " + resp0.to_string(),
      )
  }
  // Step 2: Send Data segments
  let total = data.length()
  let mut offset = 0
  let mut packet_number = 1U
  for ;; {
    let chunk_end = if offset + max_data > total {
      total
    } else {
      offset + max_data
    }
    let chunk = Bytes::makei(chunk_end - offset, fn(i) { data[offset + i] })
    let counter_n = rmsm.begin_transaction()
    let data_frame = @mailbox.encode_foe_data(counter_n, packet_number, chunk)
    mailbox_send(nic, station, mb_config, data_frame, timeout)
    let resp_n = recv_foe_validated_fp(nic, station, mb_config, rmsm, timeout)
    let resp_n = foe_handle_busy(
      nic, station, mb_config, rmsm, data_frame, resp_n, timeout,
    )
    match resp_n {
      @mailbox.FoeResponse::FoeAck(packet_number=ack_pn) =>
        if ack_pn != packet_number {
          raise @hal.EcError::MailboxProtocol(
            "FoE download: expected Ack(" +
            packet_number.to_string() +
            "), got Ack(" +
            ack_pn.to_string() +
            ")",
          )
        }
      @mailbox.FoeResponse::FoeError(code=c, text=t) => foe_raise_error(c, t)
      _ =>
        raise @hal.EcError::MailboxProtocol(
          "FoE download: expected Ack, got " + resp_n.to_string(),
        )
    }
    offset = chunk_end
    // EOF: last segment was shorter than max_data (or was the trailing empty segment)
    if chunk.length() < max_data {
      break
    }
    packet_number = packet_number + 1U
    // Exact multiple: send empty Data to signal EOF on next iteration
  }
}

///|
/// FoE Upload (read file from slave) using FP addressing.
///
/// Flow: Read(filename) → Data(1) → Ack(1) → Data(2) → Ack(2) → ... → Data(N,short) → Ack(N)
/// Returns the assembled file data.
pub fn[N : @hal.Nic] foe_upload(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  filename : String,
  password : UInt,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  // Max payload per FoE Data segment from slave: SM in size minus headers
  let max_data = mb_config.in_size.reinterpret_as_int() - 12
  if max_data <= 0 {
    raise @hal.EcError::MailboxProtocol(
      "FoE: mailbox too small for FoE transfer",
    )
  }
  // Step 1: Send Read request
  let counter0 = rmsm.begin_transaction()
  let read_frame = @mailbox.encode_foe_read(counter0, password, filename)
  mailbox_send(nic, station, mb_config, read_frame, timeout)
  // Step 2: Receive Data segments
  let result = @buffer.new(size_hint=1024)
  let mut expected_pn : UInt = 1U
  for ;; {
    let resp = recv_foe_validated_fp(nic, station, mb_config, rmsm, timeout)
    let resp = foe_handle_busy(
      nic, station, mb_config, rmsm, read_frame, resp, timeout,
    )
    match resp {
      @mailbox.FoeResponse::FoeData(packet_number=pn, data=segment) => {
        if pn != expected_pn {
          raise @hal.EcError::MailboxProtocol(
            "FoE upload: expected Data(" +
            expected_pn.to_string() +
            "), got Data(" +
            pn.to_string() +
            ")",
          )
        }
        for i = 0; i < segment.length(); i = i + 1 {
          result.write_byte(segment[i])
        }
        // Send Ack
        let counter_ack = rmsm.begin_transaction()
        let ack_frame = @mailbox.encode_foe_ack(counter_ack, pn)
        mailbox_send(nic, station, mb_config, ack_frame, timeout)
        // EOF: segment shorter than max_data
        if segment.length() < max_data {
          break
        }
        expected_pn = expected_pn + 1U
      }
      @mailbox.FoeResponse::FoeError(code=c, text=t) => foe_raise_error(c, t)
      _ =>
        raise @hal.EcError::MailboxProtocol(
          "FoE upload: expected Data, got " + resp.to_string(),
        )
    }
  }
  result.to_bytes()
}

///|
/// FoE Download (write file to slave) using AP addressing.
pub fn[N : @hal.Nic] foe_download_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  filename : String,
  password : UInt,
  data : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let max_data = mb_config.out_size.reinterpret_as_int() - 12
  if max_data <= 0 {
    raise @hal.EcError::MailboxProtocol(
      "FoE: mailbox too small for FoE transfer",
    )
  }
  let counter0 = rmsm.begin_transaction()
  let write_frame = @mailbox.encode_foe_write(counter0, password, filename)
  mailbox_send_ap(nic, position, mb_config, write_frame, timeout)
  let resp0 = recv_foe_validated_ap(nic, position, mb_config, rmsm, timeout)
  let resp0 = foe_handle_busy_ap(
    nic, position, mb_config, rmsm, write_frame, resp0, timeout,
  )
  match resp0 {
    @mailbox.FoeResponse::FoeAck(packet_number=pn) =>
      if pn != 0U {
        raise @hal.EcError::MailboxProtocol(
          "FoE download: expected Ack(0), got Ack(" + pn.to_string() + ")",
        )
      }
    @mailbox.FoeResponse::FoeError(code=c, text=t) => foe_raise_error(c, t)
    _ =>
      raise @hal.EcError::MailboxProtocol(
        "FoE download: expected Ack, got " + resp0.to_string(),
      )
  }
  let total = data.length()
  let mut offset = 0
  let mut packet_number = 1U
  for ;; {
    let chunk_end = if offset + max_data > total {
      total
    } else {
      offset + max_data
    }
    let chunk = Bytes::makei(chunk_end - offset, fn(i) { data[offset + i] })
    let counter_n = rmsm.begin_transaction()
    let data_frame = @mailbox.encode_foe_data(counter_n, packet_number, chunk)
    mailbox_send_ap(nic, position, mb_config, data_frame, timeout)
    let resp_n = recv_foe_validated_ap(nic, position, mb_config, rmsm, timeout)
    let resp_n = foe_handle_busy_ap(
      nic, position, mb_config, rmsm, data_frame, resp_n, timeout,
    )
    match resp_n {
      @mailbox.FoeResponse::FoeAck(packet_number=ack_pn) =>
        if ack_pn != packet_number {
          raise @hal.EcError::MailboxProtocol(
            "FoE download: expected Ack(" +
            packet_number.to_string() +
            "), got Ack(" +
            ack_pn.to_string() +
            ")",
          )
        }
      @mailbox.FoeResponse::FoeError(code=c, text=t) => foe_raise_error(c, t)
      _ =>
        raise @hal.EcError::MailboxProtocol(
          "FoE download: expected Ack, got " + resp_n.to_string(),
        )
    }
    offset = chunk_end
    if chunk.length() < max_data {
      break
    }
    packet_number = packet_number + 1U
  }
}

///|
/// FoE Upload (read file from slave) using AP addressing.
/// Returns the assembled file data.
pub fn[N : @hal.Nic] foe_upload_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  filename : String,
  password : UInt,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let max_data = mb_config.in_size.reinterpret_as_int() - 12
  if max_data <= 0 {
    raise @hal.EcError::MailboxProtocol(
      "FoE: mailbox too small for FoE transfer",
    )
  }
  let counter0 = rmsm.begin_transaction()
  let read_frame = @mailbox.encode_foe_read(counter0, password, filename)
  mailbox_send_ap(nic, position, mb_config, read_frame, timeout)
  let result = @buffer.new(size_hint=1024)
  let mut expected_pn : UInt = 1U
  for ;; {
    let resp = recv_foe_validated_ap(nic, position, mb_config, rmsm, timeout)
    let resp = foe_handle_busy_ap(
      nic, position, mb_config, rmsm, read_frame, resp, timeout,
    )
    match resp {
      @mailbox.FoeResponse::FoeData(packet_number=pn, data=segment) => {
        if pn != expected_pn {
          raise @hal.EcError::MailboxProtocol(
            "FoE upload: expected Data(" +
            expected_pn.to_string() +
            "), got Data(" +
            pn.to_string() +
            ")",
          )
        }
        for i = 0; i < segment.length(); i = i + 1 {
          result.write_byte(segment[i])
        }
        let counter_ack = rmsm.begin_transaction()
        let ack_frame = @mailbox.encode_foe_ack(counter_ack, pn)
        mailbox_send_ap(nic, position, mb_config, ack_frame, timeout)
        if segment.length() < max_data {
          break
        }
        expected_pn = expected_pn + 1U
      }
      @mailbox.FoeResponse::FoeError(code=c, text=t) => foe_raise_error(c, t)
      _ =>
        raise @hal.EcError::MailboxProtocol(
          "FoE upload: expected Data, got " + resp.to_string(),
        )
    }
  }
  result.to_bytes()
}
