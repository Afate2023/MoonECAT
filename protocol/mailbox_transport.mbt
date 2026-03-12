///|
/// Mailbox transport layer: SM-level send, receive, and poll operations.
/// Uses FPWR/FPRD to mailbox Sync Manager address ranges for communication
/// with slave mailboxes per ETG.1000.4.

///|
/// SM status register offset within the SM config register area.
let sm_status_offset : UInt = 5U

///|
/// Mailbox status bit (bit 3) in the SM status register.
/// For SM Input: 1 = mailbox full (data available for master to read).
/// For SM Output: 0 = mailbox empty (ready for master to write).
let mb_status_bit : Byte = b'\x08'

///|
/// Maximum number of poll attempts before returning timeout.
let default_max_polls : Int = 1000

///|
/// Compute the SM status register address for a given SM index.
fn sm_status_address(sm_index : Int) -> UInt {
  reg_sm_base +
  sm_index.reinterpret_as_uint() * sm_entry_size.reinterpret_as_uint() +
  sm_status_offset
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
  let status_addr = sm_status_address(mb_config.in_sm_index)
  let pdu = read_register_fp(nic, station, status_addr, 1, timeout)
  if pdu.data.length() < 1 {
    return false
  }
  (pdu.data[0] & mb_status_bit) != b'\x00'
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
  let status_addr = sm_status_address(mb_config.in_sm_index)
  let pdu = read_register_ap(nic, position, status_addr, 1, timeout)
  if pdu.data.length() < 1 {
    return false
  }
  (pdu.data[0] & mb_status_bit) != b'\x00'
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
  let _ = write_register_fp(
    nic,
    station,
    mb_config.out_address,
    padded,
    timeout,
  )
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
  let _ = write_register_ap(
    nic,
    position,
    mb_config.out_address,
    padded,
    timeout,
  )
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
      let pdu = read_register_ap(
        nic,
        position,
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
/// Send a mailbox frame and wait for the response.
/// Combines mailbox_send + mailbox_recv into a single round-trip.
pub fn[N : @hal.Nic] mailbox_exchange(
  nic : N,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
  data : Bytes,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  mailbox_send(nic, station, mb_config, data, timeout)
  mailbox_recv(nic, station, mb_config, timeout)
}

///|
/// Send a mailbox frame and wait for the response using auto-increment addressing.
pub fn[N : @hal.Nic] mailbox_exchange_ap(
  nic : N,
  position : UInt,
  mb_config : @mailbox.MailboxConfig,
  data : Bytes,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  mailbox_send_ap(nic, position, mb_config, data, timeout)
  mailbox_recv_ap(nic, position, mb_config, timeout)
}
