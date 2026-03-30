///|
/// Mailbox transport layer: SM-level send, receive, and poll operations.
/// Uses FPWR/FPRD to mailbox Sync Manager address ranges for communication
/// with slave mailboxes per ETG.1000.4.

///|
let sm_register_window_size : Int = 8

///|
/// SM status register offset within the SM config register area.
let sm_status_offset : UInt = 5U

///|
/// SM activate register offset within the SM config register area.
let sm_activate_offset : UInt = 6U

///|
/// SM PDI/status register offset within the SM config register area.
let sm_pdi_control_offset : UInt = 7U

///|
/// Mailbox status bit (bit 3) in the SM status register.
/// For SM Input: 1 = mailbox full (data available for master to read).
/// For SM Output: 0 = mailbox empty (ready for master to write).
let mb_status_bit : Byte = b'\x08'

///|
/// Maximum number of poll attempts before returning timeout.
let default_max_polls : Int = 1000

///|
/// Maximum number of polls when waiting for the output mailbox to become empty.
let mailbox_send_wait_max_polls : Int = 32

///|
let sm_control_deactivate_mask : UInt = 0x0100U

///|
let sm_control_repeat_request_mask : UInt = 0x0002U

///|
/// Compute the SM register window base address for a given SM index.
fn sm_register_address(sm_index : Int) -> UInt {
  reg_sm_base +
  sm_index.reinterpret_as_uint() * sm_entry_size.reinterpret_as_uint()
}

///|
fn mailbox_status_from_sm_window(window : Bytes) -> Bool {
  if window.length() <= sm_status_offset.reinterpret_as_int() {
    return false
  }
  (window[sm_status_offset.reinterpret_as_int()] & mb_status_bit) != b'\x00'
}

///|
fn validate_input_mailbox_sm_window(window : Bytes) -> Unit raise @hal.EcError {
  if window.length() < sm_register_window_size {
    return
  }
  let start = read_u16_le(window, 0)
  let length = read_u16_le(window, 2)
  let control_word = read_u16_le(window, 6)
  let deactivated = (control_word & sm_control_deactivate_mask) != 0U
  let repeat_requested = (control_word & sm_control_repeat_request_mask) != 0U
  if deactivated || (start == 0U && length == 0U && repeat_requested) {
    raise @hal.EcError::MailboxProtocol(
      "input mailbox SyncManager is deactivated/reset: start=0x" +
      start.to_string(radix=16) +
      " length=0x" +
      length.to_string(radix=16) +
      " control=0x" +
      control_word.to_string(radix=16),
    )
  }
}

///|
fn read_sm_window_activate_byte(window : Bytes) -> Byte raise @hal.EcError {
  if window.length() <= sm_activate_offset.reinterpret_as_int() {
    raise @hal.EcError::MailboxProtocol(
      "short SyncManager window: missing activate byte",
    )
  }
  window[sm_activate_offset.reinterpret_as_int()]
}

///|
fn read_sm_window_pdi_control_byte(window : Bytes) -> Byte raise @hal.EcError {
  if window.length() <= sm_pdi_control_offset.reinterpret_as_int() {
    raise @hal.EcError::MailboxProtocol(
      "short SyncManager window: missing PDI control byte",
    )
  }
  window[sm_pdi_control_offset.reinterpret_as_int()]
}

///|
fn[N : @hal.Nic] mailbox_repeat_read_fp(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
  max_polls : Int,
) -> Bytes raise @hal.EcError {
  let sm_addr = sm_register_address(mb_config.in_sm_index)
  let sm_window = read_register_fp(
    nic, station, sm_addr, sm_register_window_size, timeout,
  )
  let repeat_activate = rmsm.begin_read_repeat(
    read_sm_window_activate_byte(sm_window.data),
  )
  let _ = write_register_fp(
    nic,
    station,
    sm_addr + sm_activate_offset,
    Bytes::from_array([repeat_activate]),
    timeout,
  )
  let mut ack_seen = false
  for _attempt = 0; _attempt < max_polls; _attempt = _attempt + 1 {
    let poll_window = read_register_fp(
      nic, station, sm_addr, sm_register_window_size, timeout,
    )
    if !ack_seen {
      ack_seen = rmsm.observe_repeat_ack(
        read_sm_window_pdi_control_byte(poll_window.data),
      )
    }
    if ack_seen && mailbox_status_from_sm_window(poll_window.data) {
      let pdu = read_register_fp(
        nic,
        station,
        mb_config.in_address,
        mb_config.in_size.reinterpret_as_int(),
        timeout,
      )
      return pdu.data
    }
  }
  raise @hal.EcError::MailboxTimeout
}

///|
fn[N : @hal.Nic] mailbox_repeat_read_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
  max_polls : Int,
) -> Bytes raise @hal.EcError {
  let sm_addr = sm_register_address(mb_config.in_sm_index)
  let sm_window = read_register_ap(
    nic, position, sm_addr, sm_register_window_size, timeout,
  )
  let repeat_activate = rmsm.begin_read_repeat(
    read_sm_window_activate_byte(sm_window.data),
  )
  let _ = write_register_ap(
    nic,
    position,
    sm_addr + sm_activate_offset,
    Bytes::from_array([repeat_activate]),
    timeout,
  )
  let mut ack_seen = false
  for _attempt = 0; _attempt < max_polls; _attempt = _attempt + 1 {
    let poll_window = read_register_ap(
      nic, position, sm_addr, sm_register_window_size, timeout,
    )
    if !ack_seen {
      ack_seen = rmsm.observe_repeat_ack(
        read_sm_window_pdi_control_byte(poll_window.data),
      )
    }
    if ack_seen && mailbox_status_from_sm_window(poll_window.data) {
      return mailbox_read_ap(nic, position, mb_config, timeout)
    }
  }
  raise @hal.EcError::MailboxTimeout
}

///|
/// Poll a slave's input mailbox (SM In) to check if data is available.
/// Returns true if the mailbox contains data ready to be read.
pub fn[N : @hal.Nic] mailbox_poll(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
  let status_addr = sm_register_address(mb_config.in_sm_index)
  let pdu = read_register_fp(
    nic, station, status_addr, sm_register_window_size, timeout,
  )
  validate_input_mailbox_sm_window(pdu.data)
  if pdu.data.length() <= sm_status_offset.reinterpret_as_int() {
    return false
  }
  (pdu.data[sm_status_offset.reinterpret_as_int()] & mb_status_bit) != b'\x00'
}

///|
/// Poll a slave's input mailbox using auto-increment addressing.
/// Returns true if the mailbox contains data ready to be read.
pub fn[N : @hal.Nic] mailbox_poll_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  timeout : @hal.Duration,
) -> Bool raise @hal.EcError {
  let status_addr = sm_register_address(mb_config.in_sm_index)
  let pdu = read_register_ap(
    nic, position, status_addr, sm_register_window_size, timeout,
  )
  validate_input_mailbox_sm_window(pdu.data)
  if pdu.data.length() <= sm_status_offset.reinterpret_as_int() {
    return false
  }
  (pdu.data[sm_status_offset.reinterpret_as_int()] & mb_status_bit) != b'\x00'
}

///|
/// Send a mailbox frame to a slave by writing to the SM Output address range.
/// This function:
/// 1. Checks that the data fits in the slave's mailbox.
/// 2. Pads the data to the full SM Out size (required by EtherCAT spec).
/// 3. Writes to the SM Out physical address via FPWR.
pub fn[N : @hal.Nic] mailbox_send(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  data : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let out_size = mb_config.out_size.reinterpret_as_int()
  if data.length() > out_size {
    raise @hal.EcError::MailboxProtocol(
      "mailbox data too large: " +
      data.length().to_string() +
      " > " +
      out_size.to_string(),
    )
  }
  // Pad data to full SM Out size (required by protocol)
  let padded = Bytes::makei(out_size, fn(i) {
    if i < data.length() {
      data[i]
    } else {
      b'\x00'
    }
  })
  let status_addr = sm_register_address(mb_config.out_sm_index)
  for _attempt = 0
      _attempt < mailbox_send_wait_max_polls
      _attempt = _attempt + 1 {
    let pdu = read_register_fp(
      nic, station, status_addr, sm_register_window_size, timeout,
    )
    if pdu.data.length() > sm_status_offset.reinterpret_as_int() &&
      (pdu.data[sm_status_offset.reinterpret_as_int()] & mb_status_bit) ==
      b'\x00' {
      let _ = write_register_fp(
        nic,
        station,
        mb_config.out_address,
        padded,
        timeout,
      )
      return
    }
  }
  raise @hal.EcError::MailboxTimeout
}

///|
/// Send a mailbox frame to a slave using auto-increment addressing.
pub fn[N : @hal.Nic] mailbox_send_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  data : Bytes,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let out_size = mb_config.out_size.reinterpret_as_int()
  if data.length() > out_size {
    raise @hal.EcError::MailboxProtocol(
      "mailbox data too large: " +
      data.length().to_string() +
      " > " +
      out_size.to_string(),
    )
  }
  let padded = Bytes::makei(out_size, fn(i) {
    if i < data.length() {
      data[i]
    } else {
      b'\x00'
    }
  })
  let status_addr = sm_register_address(mb_config.out_sm_index)
  for _attempt = 0
      _attempt < mailbox_send_wait_max_polls
      _attempt = _attempt + 1 {
    let pdu = read_register_ap(
      nic, position, status_addr, sm_register_window_size, timeout,
    )
    if pdu.data.length() > sm_status_offset.reinterpret_as_int() &&
      (pdu.data[sm_status_offset.reinterpret_as_int()] & mb_status_bit) ==
      b'\x00' {
      let _ = write_register_ap(
        nic,
        position,
        mb_config.out_address,
        padded,
        timeout,
      )
      return
    }
  }
  raise @hal.EcError::MailboxTimeout
}

///|
/// Receive a mailbox frame from a slave by reading the SM Input address range.
/// This function:
/// 1. Polls the SM In status until data is available (up to max_polls attempts).
/// 2. Reads the full SM In address range via FPRD.
/// 3. Returns the raw mailbox frame bytes.
pub fn[N : @hal.Nic] mailbox_recv(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  timeout : @hal.Duration,
  max_polls? : Int = default_max_polls,
) -> Bytes raise @hal.EcError {
  // Poll until data is available
  for _attempt = 0; _attempt < max_polls; _attempt = _attempt + 1 {
    let ready = mailbox_poll(nic, station, mb_config, timeout)
    if ready {
      // Read the full SM In buffer
      let pdu = read_register_fp(
        nic,
        station,
        mb_config.in_address,
        mb_config.in_size.reinterpret_as_int(),
        timeout,
      )
      return pdu.data
    }
  }
  raise @hal.EcError::MailboxTimeout
}

///|
/// Receive a mailbox frame and use RMSM Repeat/RepeatAck recovery once when
/// the initial mailbox read times out.
pub fn[N : @hal.Nic] mailbox_recv_rmsm(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
  max_polls? : Int = default_max_polls,
) -> Bytes raise @hal.EcError {
  let initial = try? mailbox_recv(nic, station, mb_config, timeout, max_polls~)
  match initial {
    Ok(data) => data
    Err(@hal.EcError::MailboxTimeout) =>
      mailbox_repeat_read_fp(nic, station, mb_config, rmsm, timeout, max_polls)
    Err(err) => raise err
  }
}

///|
/// Read the current AP mailbox input buffer once without polling.
pub fn[N : @hal.Nic] mailbox_read_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let pdu = read_register_ap(
    nic,
    position,
    mb_config.in_address,
    mb_config.in_size.reinterpret_as_int(),
    timeout,
  )
  pdu.data
}

///|
/// Receive a mailbox frame from a slave using auto-increment addressing.
pub fn[N : @hal.Nic] mailbox_recv_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  timeout : @hal.Duration,
  max_polls? : Int = default_max_polls,
) -> Bytes raise @hal.EcError {
  for _attempt = 0; _attempt < max_polls; _attempt = _attempt + 1 {
    let ready = mailbox_poll_ap(nic, position, mb_config, timeout)
    if ready {
      return mailbox_read_ap(nic, position, mb_config, timeout)
    }
  }
  raise @hal.EcError::MailboxTimeout
}

///|
/// Receive a mailbox frame using AP addressing and use RMSM Repeat/RepeatAck
/// recovery once when the initial mailbox read times out.
pub fn[N : @hal.Nic] mailbox_recv_ap_rmsm(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  timeout : @hal.Duration,
  max_polls? : Int = default_max_polls,
) -> Bytes raise @hal.EcError {
  let initial = try? mailbox_recv_ap(
    nic,
    position,
    mb_config,
    timeout,
    max_polls~,
  )
  match initial {
    Ok(data) => data
    Err(@hal.EcError::MailboxTimeout) =>
      mailbox_repeat_read_ap(nic, position, mb_config, rmsm, timeout, max_polls)
    Err(err) => raise err
  }
}

///|
/// Send a mailbox frame and wait for the response.
/// Combines mailbox_send + mailbox_recv into a single round-trip.
pub fn[N : @hal.Nic] mailbox_exchange(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  data : Bytes,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  mailbox_send(nic, station, mb_config, data, timeout)
  mailbox_recv_rmsm(nic, station, mb_config, rmsm, timeout)
}

///|
/// Send a mailbox frame and wait for the response using auto-increment addressing.
pub fn[N : @hal.Nic] mailbox_exchange_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  rmsm : @mailbox.Rmsm,
  data : Bytes,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  mailbox_send_ap(nic, position, mb_config, data, timeout)
  mailbox_recv_ap_rmsm(nic, position, mb_config, rmsm, timeout)
}
