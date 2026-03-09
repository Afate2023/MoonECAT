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
  let response = nic.recv(timeout~)
  EcFrame::decode(response)
}

///|
/// Send a single PDU transaction and return the response PDU.
/// Convenience wrapper that builds a frame, sends, receives, and locates the PDU by index.
pub fn[N : @hal.Nic] transact_pdu(
  nic : N,
  command : EcCommand,
  address : UInt,
  data : Bytes,
  timeout : @hal.Duration,
) -> Pdu raise @hal.EcError {
  let builder = FrameBuilder::new()
  let idx = builder.add(command, address, data)
  let frame = builder.build()
  let response = transact(nic, frame, timeout)
  match find_pdu_by_index(response, idx) {
    Some(pdu) => pdu
    None => raise @hal.EcError::InvalidPdu("response PDU not found for index")
  }
}

///|
/// Send a single PDU and retry up to max_retries times on RecvTimeout.
pub fn[N : @hal.Nic] transact_pdu_retry(
  nic : N,
  command : EcCommand,
  address : UInt,
  data : Bytes,
  timeout : @hal.Duration,
  max_retries : Int,
) -> Pdu raise @hal.EcError {
  let mut last_err : @hal.EcError = @hal.EcError::RecvTimeout
  for i = 0; i <= max_retries; i = i + 1 {
    let result = try? transact_pdu(nic, command, address, data, timeout)
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
