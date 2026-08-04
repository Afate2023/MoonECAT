///|
/// Format bounded raw-frame windows around recorded receive timeouts.
fn nic_timeout_windows_text(
  log : @mock.NicEventLog,
  context_events : Int,
) -> String {
  let timeout_indices : Array[Int] = []
  for i, event in log.events {
    if event is @mock.RecvTimeout {
      timeout_indices.push(i)
    }
  }
  if timeout_indices.length() == 0 {
    return ""
  }
  let context = if context_events < 0 { 0 } else { context_events }
  let out = StringBuilder::new()
  out.write_string(
    "\nFrame Trace Around RecvTimeout\n================================\n",
  )
  for timeout_number, timeout_index in timeout_indices {
    if timeout_number > 0 {
      out.write_string("\n")
    }
    out.write_string(
      "Timeout " +
      (timeout_number + 1).to_string() +
      " at event " +
      (timeout_index + 1).to_string() +
      ":\n",
    )
    let start = if timeout_index > context {
      timeout_index - context
    } else {
      0
    }
    let wanted_end = timeout_index + context + 1
    let end = if wanted_end < log.events.length() {
      wanted_end
    } else {
      log.events.length()
    }
    for i = start; i < end; i = i + 1 {
      out.write_string("  [")
      out.write_string((i + 1).to_string())
      out.write_string("] ")
      out.write_string(nic_event_trace_text(log.events[i]))
      out.write_string("\n")
    }
  }
  out.to_string()
}

///|
fn nic_event_trace_text(event : @mock.NicEvent) -> String {
  match event {
    @mock.Sent(data, sent_len) =>
      frame_trace_text("TX", data) + " sent_len=" + sent_len.to_string()
    @mock.Received(data) => frame_trace_text("RX", data)
    @mock.RecvTimeout => "RX TIMEOUT"
    @mock.RecvFailed(message) => "RX FAILED " + message
    @mock.LinkDown => "LINK DOWN"
    @mock.SendFailed(message) => "TX FAILED " + message
  }
}

///|
fn frame_trace_text(direction : String, data : Bytes) -> String {
  let raw = bytes_preview_hex(data, 64)
  let decoded : Result[@protocol.EcFrame, @hal.EcError] = Result::Ok(
    @protocol.EcFrame::decode(data),
  ) catch {
    error => Result::Err(error)
  }
  match decoded {
    Err(error) =>
      direction +
      " raw_len=" +
      data.length().to_string() +
      " decode_error=" +
      @debug.to_string(error) +
      " raw=" +
      raw
    Ok(frame) => {
      let out = StringBuilder::new()
      out.write_string(direction)
      out.write_string(" raw_len=")
      out.write_string(data.length().to_string())
      for pdu_index, pdu in frame.pdus {
        if pdu_index == 0 {
          out.write_string(" ")
        } else {
          out.write_string(" | ")
        }
        out.write_string(@debug.to_string(pdu.header.command))
        out.write_string(" idx=")
        out.write_string(pdu.header.index.to_int().to_string())
        out.write_string(" addr=")
        out.write_string(format_hex(pdu.header.address, 8))
        out.write_string(" adp=")
        out.write_string(
          format_hex(@protocol.address_station(pdu.header.address), 4),
        )
        out.write_string(" ado=")
        out.write_string(
          format_hex(@protocol.address_offset(pdu.header.address), 4),
        )
        out.write_string(" data_len=")
        out.write_string(pdu.data.length().to_string())
        out.write_string(" wkc=")
        out.write_string(pdu.wkc.to_string())
      }
      out.write_string(" raw=")
      out.write_string(raw)
      out.to_string()
    }
  }
}

///|
/// Persist the complete raw NIC event stream for offline packet inspection.
fn write_nic_event_log(
  path : String,
  log : @mock.NicEventLog,
) -> Unit raise @hal.EcError {
  let result : Result[Unit, Error] = Result::Ok(
    @fs.write_string_to_file(path, log.to_ndjson_with_datagram_session_header()),
  ) catch {
    error => Result::Err(error)
  }
  match result {
    Ok(_) => ()
    Err(error) =>
      raise @hal.EcError::ConfigMismatch(
        "failed to write NIC trace NDJSON " + path + ": " + error.to_string(),
      )
  }
}
