///|
let max_ignored_rx_frames : Int = 32

///|
/// Retry one receive-only timeout before failing the transaction. This does not
/// resend the EtherCAT datagram, so write commands cannot be duplicated.
let max_recv_timeout_retries : Int = 1

///|
/// Perform a single EtherCAT transaction: build a frame with the given PDUs,
/// send it via the NIC, receive the response, and decode it.
/// Returns the decoded response frame.
pub fn[N : @hal.Nic] transact(
  nic : N,
  frame : EcFrame,
  timeout : @hal.Duration,
) -> EcFrame raise @hal.EcError {
  let raw = frame.encode()
  let _sent = nic.send(raw)
  let mut ignored = 0
  let mut recv_timeouts = 0
  for ;; {
    let response_result : Result[Bytes, @hal.EcError] = Result::Ok(
      nic.recv(timeout~),
    ) catch {
      err => Result::Err(err)
    }
    let response = match response_result {
      Ok(value) => value
      Err(@hal.EcError::RecvTimeout) if recv_timeouts < max_recv_timeout_retries => {
        recv_timeouts = recv_timeouts + 1
        continue
      }
      Err(err) => raise err
    }
    let decoded = Result::Ok(EcFrame::decode(response)) catch {
      err => Result::Err(err)
    }
    match decoded {
      Ok(value) =>
        if response_matches_request(frame, value) {
          return value
        } else {
          ignored = ignored + 1
          if ignored > max_ignored_rx_frames {
            raise @hal.EcError::Internal(
              "timeout at transact.recv: ignored " +
              max_ignored_rx_frames.to_string() +
              " unrelated EtherCAT frames",
            )
          }
        }
      Err(err) if should_ignore_rx_decode_error(err) => {
        ignored = ignored + 1
        if ignored > max_ignored_rx_frames {
          raise @hal.EcError::Internal(
            "timeout at transact.recv: ignored " +
            max_ignored_rx_frames.to_string() +
            " invalid frames; last error=" +
            @debug.to_string(err),
          )
        }
      }
      Err(err) => raise err
    }
  }
}

///|
fn response_matches_request(request : EcFrame, response : EcFrame) -> Bool {
  if response.pdus.length() != request.pdus.length() {
    return false
  }
  // EtherCAT responses preserve datagram order. Match the fields that identify
  // this transaction, but do not compare address (AP commands mutate ADP) or
  // WKC (slaves update it while the frame traverses the bus).
  for i, request_pdu in request.pdus {
    let response_pdu = response.pdus[i]
    if response_pdu.header.index != request_pdu.header.index {
      return false
    }
    if response_pdu.header.command != request_pdu.header.command {
      return false
    }
    if response_pdu.data.length() != request_pdu.data.length() {
      return false
    }
  }
  true
}

///|
fn should_ignore_rx_decode_error(err : @hal.EcError) -> Bool {
  match err {
    @hal.EcError::InvalidFrame(message) =>
      message.contains("frame too short") ||
      message.contains("wrong ethertype") ||
      message.contains("wrong ecat type")
    _ => false
  }
}

///|
/// Send a single PDU transaction and return the response PDU.
/// Convenience wrapper that builds a frame, sends, receives, and locates the PDU by index.
pub fn[N : @hal.Nic + DatagramIndexSource] transact_pdu(
  nic : N,
  command : EcCommand,
  address : UInt,
  data : Bytes,
  timeout : @hal.Duration,
) -> Pdu raise @hal.EcError {
  let idx = DatagramIndexSource::next_datagram_index(nic)
  let builder = FrameBuilder::new()
  builder.add_indexed(idx, command, address, data)
  let frame = builder.build()
  let response = transact(nic, frame, timeout)
  match find_pdu_by_index(response, idx) {
    Some(pdu) => pdu
    None => raise @hal.EcError::InvalidPdu("response PDU not found for index")
  }
}

///|
/// Send a single PDU and retry up to max_retries times on RecvTimeout.
pub fn[N : @hal.Nic + DatagramIndexSource] transact_pdu_retry(
  nic : N,
  command : EcCommand,
  address : UInt,
  data : Bytes,
  timeout : @hal.Duration,
  max_retries : Int,
) -> Pdu raise @hal.EcError {
  let mut last_err : @hal.EcError = @hal.EcError::RecvTimeout
  for i = 0; i <= max_retries; i = i + 1 {
    let result = Result::Ok(transact_pdu(nic, command, address, data, timeout)) catch {
      err => Result::Err(err)
    }
    match result {
      Ok(pdu) => return pdu
      Err(e) =>
        match e {
          @hal.EcError::RecvTimeout => last_err = e
          _ => raise e
        }
    }
  }
  raise last_err
}
