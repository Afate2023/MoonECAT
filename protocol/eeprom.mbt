///|
/// EEPROM (SII) register-level read via ESC registers 0x0502–0x0508.
/// Implements ETG.1500 #305 (EEPROM Read shall).
///
/// Protocol:
///   1. Wait until SII control register bit 15 (busy) = 0
///   2. Write word address to SII address register (0x0504, 2 bytes LE)
///   3. Write read command to SII control register (0x0502): set bit 8 (read)
///   4. Wait until SII control register bit 15 (busy) = 0
///   5. Read 4 bytes from SII data register (0x0508)

///|
/// SII Control/Status register bits.
let sii_ctrl_busy : UInt = 0x8000U

///|
let sii_ctrl_nack : UInt = 0x2000U

///|
let sii_ctrl_r64 : UInt = 0x0040U

///|
let sii_ctrl_error_mask : UInt = 0x7800U

///|
let sii_ctrl_read_cmd : UInt = 0x0100U

///|
let sii_ctrl_nop_cmd : UInt = 0x0000U

///|
let sii_retry_limit : Int = 3

///|
let sii_cfg_force_pdi : Byte = b'\x02'

///|
let sii_cfg_master : Byte = b'\x00'

///|
let sii_cfg_pdi : Byte = b'\x01'

///|
/// EEPROM size word offset inside the fixed SII metadata block.
let sii_eeprom_size_word_offset : Int = 62

///|
/// Minimum bytes needed to read standard metadata and determine total EEPROM size.
let sii_initial_probe_bytes : Int = 128

///|
/// Maximum polls for SII busy flag before timeout.
let sii_max_polls : Int = 1000

///|
/// Read a single 32-bit (4-byte) word from a slave's EEPROM at the given
/// word address. Returns 4 bytes of EEPROM data.
pub fn[N : @hal.Nic] eeprom_read_word(
  nic : N,
  station : UInt,
  word_address : UInt,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  eeprom_prepare_master(nic, station, timeout)
  let data = eeprom_read_word_owned(nic, station, word_address, timeout)
  ignore(eeprom_restore_pdi(nic, station, timeout) catch { _ => () })
  data
}

///|
fn[N : @hal.Nic] eeprom_read_word_owned(
  nic : N,
  station : UInt,
  word_address : UInt,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let chunk = eeprom_read_chunk_owned(nic, station, word_address, timeout)
  if chunk.length() < 4 {
    raise @hal.EcError::SiiReadFailed("SII data chunk shorter than 4 bytes")
  }
  Bytes::makei(4, fn(i) { chunk[i] })
}

///|
fn[N : @hal.Nic] eeprom_read_chunk_owned(
  nic : N,
  station : UInt,
  word_address : UInt,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let ready = eeprom_wait_ready(nic, station, timeout)
  if (ready & sii_ctrl_error_mask) != 0U {
    eeprom_clear_errors(nic, station, timeout)
  }
  for _retry = 0; _retry < sii_retry_limit; _retry = _retry + 1 {
    let ctrl_buf = Bytes::from_array([
      (sii_ctrl_read_cmd & 0xFFU).to_byte(),
      ((sii_ctrl_read_cmd >> 8) & 0xFFU).to_byte(),
      (word_address & 0xFFU).to_byte(),
      ((word_address >> 8) & 0xFFU).to_byte(),
      b'\x00',
      b'\x00',
    ])
    let _ = write_register_fp(nic, station, reg_sii_control, ctrl_buf, timeout)
    let status = eeprom_wait_ready_after_command(nic, station, timeout)
    if (status & sii_ctrl_nack) != 0U {
      continue
    }
    let read_len = if (status & sii_ctrl_r64) != 0U { 8 } else { 4 }
    let pdu = read_register_fp(nic, station, reg_sii_data, read_len, timeout)
    if pdu.data.length() < read_len {
      raise @hal.EcError::SiiReadFailed(
        "SII data register returned fewer than " +
        read_len.to_string() +
        " bytes",
      )
    }
    return pdu.data
  }
  raise @hal.EcError::SiiReadFailed(
    "SII read received NACK for word address " +
    word_address.reinterpret_as_int().to_string(),
  )
}

///|
fn[N : @hal.Nic] eeprom_prepare_master(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  eeprom_write_config(nic, station, sii_cfg_force_pdi, timeout)
  eeprom_write_config(nic, station, sii_cfg_master, timeout)
}

///|
fn[N : @hal.Nic] eeprom_restore_pdi(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  eeprom_write_config(nic, station, sii_cfg_pdi, timeout)
}

///|
fn[N : @hal.Nic] eeprom_write_config(
  nic : N,
  station : UInt,
  value : Byte,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let pdu = write_register_fp(
    nic,
    station,
    reg_sii_config,
    Bytes::from_array([value]),
    timeout,
  )
  if pdu.wkc == 0U {
    raise @hal.EcError::SiiReadFailed(
      "failed to set EEPROM ownership for station " +
      station.reinterpret_as_int().to_string(),
    )
  }
}

///|
/// Wait for the SII controller to become ready (not busy).
fn[N : @hal.Nic] eeprom_wait_ready(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  for _attempt = 0; _attempt < sii_max_polls; _attempt = _attempt + 1 {
    let pdu = read_register_fp(nic, station, reg_sii_control, 2, timeout)
    if pdu.data.length() >= 2 {
      let status = pdu.data[0].to_uint() | (pdu.data[1].to_uint() << 8)
      if (status & sii_ctrl_busy) == 0U {
        return status
      }
    }
  }
  raise @hal.EcError::SiiReadFailed("SII busy timeout")
}

///|
fn[N : @hal.Nic] eeprom_wait_ready_after_command(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let mut saw_busy = false
  let mut last_status = 0U
  for attempt = 0; attempt < sii_max_polls; attempt = attempt + 1 {
    let pdu = read_register_fp(nic, station, reg_sii_control, 2, timeout)
    if pdu.data.length() >= 2 {
      let status = pdu.data[0].to_uint() | (pdu.data[1].to_uint() << 8)
      last_status = status
      if (status & sii_ctrl_busy) != 0U {
        saw_busy = true
        continue
      }
      if saw_busy || attempt > 0 {
        return status
      }
    }
  }
  if last_status != 0U {
    return last_status
  }
  raise @hal.EcError::SiiReadFailed("SII command completion timeout")
}

///|
fn[N : @hal.Nic] eeprom_clear_errors(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let clear_buf = Bytes::from_array([
    (sii_ctrl_nop_cmd & 0xFFU).to_byte(),
    ((sii_ctrl_nop_cmd >> 8) & 0xFFU).to_byte(),
  ])
  let _ = write_register_fp(nic, station, reg_sii_control, clear_buf, timeout)
}

///|
/// Read a contiguous range of EEPROM data starting at a word address.
/// Returns `word_count * 4` bytes. Each read returns one 32-bit SII data window,
/// so consecutive reads advance by two 16-bit EEPROM words.
pub fn[N : @hal.Nic] eeprom_read(
  nic : N,
  station : UInt,
  start_word : UInt,
  word_count : Int,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let target_length = word_count * 4
  let buf = @buffer.new(size_hint=target_length)
  let mut current_word = start_word
  let mut remaining = target_length
  eeprom_prepare_master(nic, station, timeout)
  while remaining > 0 {
    let chunk = eeprom_read_chunk_owned(nic, station, current_word, timeout)
    let copy_len = if chunk.length() < remaining {
      chunk.length()
    } else {
      remaining
    }
    for j = 0; j < copy_len; j = j + 1 {
      buf.write_byte(chunk[j])
    }
    current_word = current_word + (if chunk.length() >= 8 { 4U } else { 2U })
    remaining = remaining - copy_len
  }
  ignore(eeprom_restore_pdi(nic, station, timeout) catch { _ => () })
  buf.to_bytes()
}

///|
fn decode_sii_total_bytes(probe : Bytes) -> Int? {
  if probe.length() < sii_initial_probe_bytes {
    return None
  }
  let byte_offset = sii_eeprom_size_word_offset * 2
  let encoded = probe[byte_offset].to_uint() |
    (probe[byte_offset + 1].to_uint() << 8)
  Some(((encoded << 7) + 0x80U).reinterpret_as_int())
}

///|
fn required_sii_probe_word_count(initial_word_count : Int) -> Int {
  let minimum_probe_words = sii_initial_probe_bytes / 4
  if initial_word_count > minimum_probe_words {
    initial_word_count
  } else {
    minimum_probe_words
  }
}

///|
fn required_sii_total_word_count(
  initial_eeprom : Bytes,
  initial_word_count : Int,
) -> Int {
  match decode_sii_total_bytes(initial_eeprom) {
    Some(total_bytes) => {
      let total_words = (total_bytes + 3) / 4
      if total_words > initial_word_count {
        total_words
      } else {
        initial_word_count
      }
    }
    None => initial_word_count
  }
}

///|
/// Read a complete SII EEPROM image using the fixed metadata block to expand
/// the initial probe to the EEPROM-declared total byte size.
pub fn[N : @hal.Nic] read_sii_bytes(
  nic : N,
  station : UInt,
  initial_word_count : Int,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let probe_word_count = required_sii_probe_word_count(initial_word_count)
  let initial_eeprom = eeprom_read(nic, station, 0U, probe_word_count, timeout)
  let total_word_count = required_sii_total_word_count(
    initial_eeprom, probe_word_count,
  )
  if total_word_count <= probe_word_count {
    initial_eeprom
  } else {
    eeprom_read(nic, station, 0U, total_word_count, timeout)
  }
}

///|
/// Read a contiguous EEPROM range using auto-increment addressing.
/// This is useful during scan while slave positions are stable but configured
/// station addressing may not yet be reliable on all devices.
pub fn[N : @hal.Nic] eeprom_read_ap(
  nic : N,
  position : UInt,
  start_word : UInt,
  word_count : Int,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let target_length = word_count * 4
  let buf = @buffer.new(size_hint=target_length)
  let mut current_word = start_word
  let mut remaining = target_length
  eeprom_prepare_master_ap(nic, position, timeout)
  while remaining > 0 {
    let chunk = eeprom_read_chunk_owned_ap(nic, position, current_word, timeout)
    let copy_len = if chunk.length() < remaining {
      chunk.length()
    } else {
      remaining
    }
    for j = 0; j < copy_len; j = j + 1 {
      buf.write_byte(chunk[j])
    }
    current_word = current_word + (if chunk.length() >= 8 { 4U } else { 2U })
    remaining = remaining - copy_len
  }
  ignore(eeprom_restore_pdi_ap(nic, position, timeout) catch { _ => () })
  buf.to_bytes()
}

///|
/// Read a complete SII EEPROM image using auto-increment addressing.
pub fn[N : @hal.Nic] read_sii_bytes_ap(
  nic : N,
  position : UInt,
  initial_word_count : Int,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let probe_word_count = required_sii_probe_word_count(initial_word_count)
  let initial_eeprom = eeprom_read_ap(
    nic, position, 0U, probe_word_count, timeout,
  )
  let total_word_count = required_sii_total_word_count(
    initial_eeprom, probe_word_count,
  )
  if total_word_count <= probe_word_count {
    initial_eeprom
  } else {
    eeprom_read_ap(nic, position, 0U, total_word_count, timeout)
  }
}

///|
fn[N : @hal.Nic] eeprom_read_chunk_owned_ap(
  nic : N,
  position : UInt,
  word_address : UInt,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let ready = eeprom_wait_ready_ap(nic, position, timeout)
  if (ready & sii_ctrl_error_mask) != 0U {
    eeprom_clear_errors_ap(nic, position, timeout)
  }
  for _retry = 0; _retry < sii_retry_limit; _retry = _retry + 1 {
    let ctrl_buf = Bytes::from_array([
      (sii_ctrl_read_cmd & 0xFFU).to_byte(),
      ((sii_ctrl_read_cmd >> 8) & 0xFFU).to_byte(),
      (word_address & 0xFFU).to_byte(),
      ((word_address >> 8) & 0xFFU).to_byte(),
      b'\x00',
      b'\x00',
    ])
    let _ = write_register_ap(nic, position, reg_sii_control, ctrl_buf, timeout)
    let status = eeprom_wait_ready_after_command_ap(nic, position, timeout)
    if (status & sii_ctrl_nack) != 0U {
      continue
    }
    let read_len = if (status & sii_ctrl_r64) != 0U { 8 } else { 4 }
    let pdu = read_register_ap(nic, position, reg_sii_data, read_len, timeout)
    if pdu.data.length() < read_len {
      raise @hal.EcError::SiiReadFailed(
        "SII data register returned fewer than " +
        read_len.to_string() +
        " bytes",
      )
    }
    return pdu.data
  }
  raise @hal.EcError::SiiReadFailed(
    "SII AP read received NACK for position " +
    position.reinterpret_as_int().to_string(),
  )
}

///|
fn[N : @hal.Nic] eeprom_prepare_master_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  eeprom_write_config_ap(nic, position, sii_cfg_force_pdi, timeout)
  eeprom_write_config_ap(nic, position, sii_cfg_master, timeout)
}

///|
fn[N : @hal.Nic] eeprom_restore_pdi_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  eeprom_write_config_ap(nic, position, sii_cfg_pdi, timeout)
}

///|
fn[N : @hal.Nic] eeprom_write_config_ap(
  nic : N,
  position : UInt,
  value : Byte,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let pdu = write_register_ap(
    nic,
    position,
    reg_sii_config,
    Bytes::from_array([value]),
    timeout,
  )
  if pdu.wkc == 0U {
    raise @hal.EcError::SiiReadFailed(
      "failed to set EEPROM ownership for position " +
      position.reinterpret_as_int().to_string(),
    )
  }
}

///|
fn[N : @hal.Nic] eeprom_wait_ready_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  for _attempt = 0; _attempt < sii_max_polls; _attempt = _attempt + 1 {
    let pdu = read_register_ap(nic, position, reg_sii_control, 2, timeout)
    if pdu.data.length() >= 2 {
      let status = pdu.data[0].to_uint() | (pdu.data[1].to_uint() << 8)
      if (status & sii_ctrl_busy) == 0U {
        return status
      }
    }
  }
  raise @hal.EcError::SiiReadFailed("SII AP busy timeout")
}

///|
fn[N : @hal.Nic] eeprom_wait_ready_after_command_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  let mut saw_busy = false
  let mut last_status = 0U
  for attempt = 0; attempt < sii_max_polls; attempt = attempt + 1 {
    let pdu = read_register_ap(nic, position, reg_sii_control, 2, timeout)
    if pdu.data.length() >= 2 {
      let status = pdu.data[0].to_uint() | (pdu.data[1].to_uint() << 8)
      last_status = status
      if (status & sii_ctrl_busy) != 0U {
        saw_busy = true
        continue
      }
      if saw_busy || attempt > 0 {
        return status
      }
    }
  }
  if last_status != 0U {
    return last_status
  }
  raise @hal.EcError::SiiReadFailed("SII AP command completion timeout")
}

///|
fn[N : @hal.Nic] eeprom_clear_errors_ap(
  nic : N,
  position : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let clear_buf = Bytes::from_array([
    (sii_ctrl_nop_cmd & 0xFFU).to_byte(),
    ((sii_ctrl_nop_cmd >> 8) & 0xFFU).to_byte(),
  ])
  let _ = write_register_ap(nic, position, reg_sii_control, clear_buf, timeout)
}

///|
/// SII write command: bit 9 (write) + bit 0 (write enable).
let sii_ctrl_write_cmd : UInt = 0x0201U

///|
/// Write a single 16-bit word to a slave's EEPROM at the given word address.
/// Implements ETG.1500 #305 (EEPROM Write may).
///
/// Protocol (per SOEM pattern):
///   1. Acquire Master ownership
///   2. Write 16-bit data to SII data register (0x0508)
///   3. Write command (0x0201) + address to SII control register (0x0502)
///   4. Wait for busy flag to clear
///   5. Restore PDI ownership
pub fn[N : @hal.Nic] eeprom_write_word(
  nic : N,
  station : UInt,
  word_address : UInt,
  data : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  eeprom_prepare_master(nic, station, timeout)
  eeprom_write_word_owned(nic, station, word_address, data, timeout)
  ignore(eeprom_restore_pdi(nic, station, timeout) catch { _ => () })
}

///|
fn[N : @hal.Nic] eeprom_write_word_owned(
  nic : N,
  station : UInt,
  word_address : UInt,
  data : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let ready = eeprom_wait_ready(nic, station, timeout)
  if (ready & sii_ctrl_error_mask) != 0U {
    eeprom_clear_errors(nic, station, timeout)
  }
  for _retry = 0; _retry < sii_retry_limit; _retry = _retry + 1 {
    // Write 16-bit data to SII data register BEFORE issuing the write command
    let data_buf = Bytes::from_array([
      (data & 0xFFU).to_byte(),
      ((data >> 8) & 0xFFU).to_byte(),
    ])
    let _ = write_register_fp(nic, station, reg_sii_data, data_buf, timeout)
    // Issue write command + address
    let ctrl_buf = Bytes::from_array([
      (sii_ctrl_write_cmd & 0xFFU).to_byte(),
      ((sii_ctrl_write_cmd >> 8) & 0xFFU).to_byte(),
      (word_address & 0xFFU).to_byte(),
      ((word_address >> 8) & 0xFFU).to_byte(),
      b'\x00',
      b'\x00',
    ])
    let _ = write_register_fp(nic, station, reg_sii_control, ctrl_buf, timeout)
    let status = eeprom_wait_ready_after_command(nic, station, timeout)
    if (status & sii_ctrl_nack) != 0U {
      continue
    }
    return
  }
  raise @hal.EcError::SiiReadFailed(
    "SII write received NACK for word address " +
    word_address.reinterpret_as_int().to_string(),
  )
}

///|
/// Write a single 16-bit word to a slave's EEPROM using auto-increment addressing.
pub fn[N : @hal.Nic] eeprom_write_word_ap(
  nic : N,
  position : UInt,
  word_address : UInt,
  data : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  eeprom_prepare_master_ap(nic, position, timeout)
  eeprom_write_word_owned_ap(nic, position, word_address, data, timeout)
  ignore(eeprom_restore_pdi_ap(nic, position, timeout) catch { _ => () })
}

///|
fn[N : @hal.Nic] eeprom_write_word_owned_ap(
  nic : N,
  position : UInt,
  word_address : UInt,
  data : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  let ready = eeprom_wait_ready_ap(nic, position, timeout)
  if (ready & sii_ctrl_error_mask) != 0U {
    eeprom_clear_errors_ap(nic, position, timeout)
  }
  for _retry = 0; _retry < sii_retry_limit; _retry = _retry + 1 {
    let data_buf = Bytes::from_array([
      (data & 0xFFU).to_byte(),
      ((data >> 8) & 0xFFU).to_byte(),
    ])
    let _ = write_register_ap(nic, position, reg_sii_data, data_buf, timeout)
    let ctrl_buf = Bytes::from_array([
      (sii_ctrl_write_cmd & 0xFFU).to_byte(),
      ((sii_ctrl_write_cmd >> 8) & 0xFFU).to_byte(),
      (word_address & 0xFFU).to_byte(),
      ((word_address >> 8) & 0xFFU).to_byte(),
      b'\x00',
      b'\x00',
    ])
    let _ = write_register_ap(nic, position, reg_sii_control, ctrl_buf, timeout)
    let status = eeprom_wait_ready_after_command_ap(nic, position, timeout)
    if (status & sii_ctrl_nack) != 0U {
      continue
    }
    return
  }
  raise @hal.EcError::SiiReadFailed(
    "SII AP write received NACK for position " +
    position.reinterpret_as_int().to_string(),
  )
}
