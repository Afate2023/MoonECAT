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
let sii_ctrl_read_cmd : Byte = b'\x01'

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
  // Step 1: Wait for SII not busy
  eeprom_wait_ready(nic, station, timeout)
  // Step 2: Write word address (2 bytes LE) to SII address register
  let addr_buf = Bytes::from_array([
    (word_address & 0xFFU).to_byte(),
    ((word_address >> 8) & 0xFFU).to_byte(),
  ])
  let _ = write_register_fp(nic, station, reg_sii_address, addr_buf, timeout)
  // Step 3: Write read command to SII control register
  let ctrl_buf = Bytes::from_array([sii_ctrl_read_cmd, b'\x00'])
  let _ = write_register_fp(nic, station, reg_sii_control, ctrl_buf, timeout)
  // Step 4: Wait for SII not busy
  eeprom_wait_ready(nic, station, timeout)
  // Step 5: Read 4 bytes from SII data register
  let pdu = read_register_fp(nic, station, reg_sii_data, 4, timeout)
  if pdu.data.length() < 4 {
    raise @hal.EcError::SiiReadFailed(
      "SII data register returned fewer than 4 bytes",
    )
  }
  pdu.data
}

///|
/// Wait for the SII controller to become ready (not busy).
fn[N : @hal.Nic] eeprom_wait_ready(
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> Unit raise @hal.EcError {
  for _attempt = 0; _attempt < sii_max_polls; _attempt = _attempt + 1 {
    let pdu = read_register_fp(nic, station, reg_sii_control, 2, timeout)
    if pdu.data.length() >= 2 {
      let status = pdu.data[0].to_uint() | (pdu.data[1].to_uint() << 8)
      if (status & sii_ctrl_busy) == 0U {
        return
      }
    }
  }
  raise @hal.EcError::SiiReadFailed("SII busy timeout")
}

///|
/// Read a contiguous range of EEPROM data starting at a word address.
/// Returns `word_count * 4` bytes. Each EEPROM word is 4 bytes (32 bits).
pub fn[N : @hal.Nic] eeprom_read(
  nic : N,
  station : UInt,
  start_word : UInt,
  word_count : Int,
  timeout : @hal.Duration,
) -> Bytes raise @hal.EcError {
  let buf = @buffer.new(size_hint=word_count * 4)
  for i = 0; i < word_count; i = i + 1 {
    let word_data = eeprom_read_word(
      nic,
      station,
      start_word + i.reinterpret_as_uint(),
      timeout,
    )
    for j = 0; j < word_data.length(); j = j + 1 {
      buf.write_byte(word_data[j])
    }
  }
  buf.to_bytes()
}
