///|
/// SII EEPROM word addresses for fixed fields.
/// These are word offsets (each word = 2 bytes).

///|
/// Vendor ID (words 8-9, 32-bit).
let sii_vendor_id : Int = 8

///|
/// Product Code (words 10-11, 32-bit).
let sii_product_code : Int = 10

///|
/// PDI control word (word 0).
let sii_pdi_control : Int = 0

///|
/// PDI config word (word 1).
let sii_pdi_config : Int = 1

///|
/// Sync impulse length (word 2), stored in units of 10 ns.
let sii_sync_impulse_length : Int = 2

///|
/// PDI config 2 word (word 3).
let sii_pdi_config2 : Int = 3

///|
/// Configured station alias (word 4).
let sii_configured_station_alias : Int = 4

///|
/// Preamble checksum (word 7).
let sii_preamble_checksum : Int = 7

///|
/// Revision Number (words 12-13, 32-bit).
let sii_revision : Int = 12

///|
/// Serial Number (words 14-15, 32-bit).
let sii_serial : Int = 14

///|
/// Bootstrap Receive Mailbox Offset (word 20).
let sii_bootstrap_rx_offset : Int = 20

///|
/// Bootstrap Receive Mailbox Size (word 21).
let sii_bootstrap_rx_size : Int = 21

///|
/// Bootstrap Send Mailbox Offset (word 22).
let sii_bootstrap_tx_offset : Int = 22

///|
/// Bootstrap Send Mailbox Size (word 23).
let sii_bootstrap_tx_size : Int = 23

///|
/// Standard Receive Mailbox Offset (word 24).
let sii_std_rx_offset : Int = 24

///|
/// Standard Receive Mailbox Size (word 25).
let sii_std_rx_size : Int = 25

///|
/// Standard Send Mailbox Offset (word 26).
let sii_std_tx_offset : Int = 26

///|
/// Standard Send Mailbox Size (word 27).
let sii_std_tx_size : Int = 27

///|
/// Mailbox Protocol word (word 28).
let sii_mailbox_protocol : Int = 28

///|
/// Encoded EEPROM size word (word 62).
let sii_eeprom_size : Int = 62

///|
/// SII version word (word 63).
let sii_eeprom_version : Int = 63

///|
/// First category header starts at word 64.
pub let sii_category_start : Int = 64

///|
/// Category type codes.
let sii_cat_strings : UInt = 10U

///|
let sii_cat_general : UInt = 30U

///|
let sii_cat_fmmu : UInt = 40U

///|
let sii_cat_sm : UInt = 41U

///|
let sii_cat_txpdo : UInt = 50U

///|
let sii_cat_rxpdo : UInt = 51U

///|
let sii_cat_dc : UInt = 60U

///|
/// End marker for SII categories.
let sii_cat_end : UInt = 0x7FFFU

///|
/// Helper: read a little-endian UInt16 from a Bytes at a word offset.
fn read_sii_word(data : Bytes, word_offset : Int) -> UInt {
  let byte_offset = word_offset * 2
  if byte_offset + 1 >= data.length() {
    return 0U
  }
  data[byte_offset].to_int().reinterpret_as_uint() |
  (data[byte_offset + 1].to_int().reinterpret_as_uint() << 8)
}

///|
/// Helper: read a little-endian UInt32 from two consecutive words.
fn read_sii_dword(data : Bytes, word_offset : Int) -> UInt {
  read_sii_word(data, word_offset) |
  (read_sii_word(data, word_offset + 1) << 16)
}

///|
fn read_sii_word_at_byte(data : Bytes, byte_offset : Int) -> UInt {
  if byte_offset + 1 >= data.length() {
    return 0U
  }
  data[byte_offset].to_int().reinterpret_as_uint() |
  (data[byte_offset + 1].to_int().reinterpret_as_uint() << 8)
}

///|
fn read_sii_dword_at_byte(data : Bytes, byte_offset : Int) -> UInt {
  read_sii_word_at_byte(data, byte_offset) |
  (read_sii_word_at_byte(data, byte_offset + 2) << 16)
}

///|
fn read_sii_i16_at_byte(data : Bytes, byte_offset : Int) -> Int {
  let value = read_sii_word_at_byte(data, byte_offset).reinterpret_as_int()
  if value >= 0x8000 {
    value - 0x10000
  } else {
    value
  }
}

///|
fn crc8_update(crc : Int, value : Byte) -> Int {
  let mut current = (crc ^ value.to_int()) & 0xFF
  for _ in 0..<8 {
    current = if (current & 0x80) != 0 {
      ((current << 1) & 0xFF) ^ 0x07
    } else {
      (current << 1) & 0xFF
    }
  }
  current
}

///|
/// Parse the fixed SII preamble.
pub fn parse_sii_preamble(data : Bytes) -> SiiPreamble raise @hal.EcError {
  if data.length() < 16 {
    raise @hal.EcError::SiiReadFailed(
      "SII preamble too short: " + data.length().to_string() + " bytes",
    )
  }
  let mut crc = 0xFF
  for i = 0; i < 16; i = i + 1 {
    crc = crc8_update(crc, data[i])
  }
  {
    pdi_control: read_sii_word(data, sii_pdi_control),
    pdi_config: read_sii_word(data, sii_pdi_config),
    sync_impulse_length_raw: read_sii_word(data, sii_sync_impulse_length),
    pdi_config2: read_sii_word(data, sii_pdi_config2),
    configured_station_alias: read_sii_word(data, sii_configured_station_alias),
    checksum: read_sii_word(data, sii_preamble_checksum),
    checksum_ok: crc == 0,
  }
}

///|
/// Parse the fixed SII header fields from raw EEPROM data.
pub fn parse_sii_header(data : Bytes) -> SiiData raise @hal.EcError {
  // Minimum: need at least 29 words (58 bytes) for the standard header
  if data.length() < 58 {
    raise @hal.EcError::SiiReadFailed(
      "SII data too short: " + data.length().to_string() + " bytes",
    )
  }
  {
    vendor_id: read_sii_dword(data, sii_vendor_id),
    product_code: read_sii_dword(data, sii_product_code),
    revision: read_sii_dword(data, sii_revision),
    serial: read_sii_dword(data, sii_serial),
    bootstrap_rx_offset: read_sii_word(data, sii_bootstrap_rx_offset),
    bootstrap_rx_size: read_sii_word(data, sii_bootstrap_rx_size),
    bootstrap_tx_offset: read_sii_word(data, sii_bootstrap_tx_offset),
    bootstrap_tx_size: read_sii_word(data, sii_bootstrap_tx_size),
    mailbox_rx_offset: read_sii_word(data, sii_std_rx_offset),
    mailbox_rx_size: read_sii_word(data, sii_std_rx_size),
    mailbox_tx_offset: read_sii_word(data, sii_std_tx_offset),
    mailbox_tx_size: read_sii_word(data, sii_std_tx_size),
    mailbox_protocols: read_sii_word(data, sii_mailbox_protocol),
  }
}

///|
/// Parse standard SII metadata fields after the mailbox configuration block.
pub fn parse_sii_standard_metadata(
  data : Bytes,
) -> SiiStandardMetadata raise @hal.EcError {
  if data.length() < 128 {
    raise @hal.EcError::SiiReadFailed(
      "SII metadata too short: " + data.length().to_string() + " bytes",
    )
  }
  {
    eeprom_size_raw: read_sii_word(data, sii_eeprom_size),
    version: read_sii_word(data, sii_eeprom_version),
  }
}

///|
/// A parsed SII category with its type tag and raw data.
pub(all) struct SiiCategoryEntry {
  category : SiiCategory
  data : Bytes
} derive(Show)

///|
/// Convert a category type code to the SiiCategory enum.
fn category_from_code(code : UInt) -> SiiCategory? {
  match code {
    c if c == sii_cat_strings => Some(Strings)
    c if c == sii_cat_general => Some(General)
    c if c == sii_cat_fmmu => Some(Fmmu)
    c if c == sii_cat_sm => Some(SyncManager)
    c if c == sii_cat_txpdo => Some(TxPdo)
    c if c == sii_cat_rxpdo => Some(RxPdo)
    c if c == sii_cat_dc => Some(Dc)
    _ => None
  }
}

///|
/// Parse all SII categories from the category area of EEPROM data.
pub fn parse_sii_categories(data : Bytes) -> Array[SiiCategoryEntry] {
  let categories : Array[SiiCategoryEntry] = []
  let mut word_offset = sii_category_start
  while word_offset * 2 + 3 < data.length() {
    let cat_type = read_sii_word(data, word_offset)
    let cat_size_words = read_sii_word(data, word_offset + 1)
    if cat_type == sii_cat_end || cat_type == 0U {
      break
    }
    let cat_size_bytes = cat_size_words.reinterpret_as_int() * 2
    let cat_data_start = (word_offset + 2) * 2
    if cat_data_start + cat_size_bytes <= data.length() {
      match category_from_code(cat_type) {
        Some(cat) =>
          categories.push({
            category: cat,
            data: Bytes::makei(cat_size_bytes, fn(i) {
              data[cat_data_start + i]
            }),
          })
        None => () // Skip unknown categories
      }
    }
    word_offset = word_offset + 2 + cat_size_words.reinterpret_as_int()
  }
  categories
}

///|
/// General category data extracted from SII.
pub(all) struct SiiGeneral {
  group_idx : Byte
  image_idx : Byte
  order_idx : Byte
  name_idx : Byte
  coe_details : Byte
  foe_supported : Bool
  eoe_supported : Bool
  soe_supported : Bool
  soe_channels : Byte
  ds402_channels : Byte
  sysman_class : Byte
  flags : Byte
  current_on_ebus : UInt
  physical_port_0 : Byte
  physical_port_1 : Byte
  physical_port_2 : Byte
  physical_port_3 : Byte
  physical_memory_address : UInt
} derive(Eq, Show)

///|
/// Parse the General category data.
pub fn parse_sii_general(data : Bytes) -> SiiGeneral raise @hal.EcError {
  if data.length() < 16 {
    raise @hal.EcError::EsiParseFailed(
      "General category too short: " + data.length().to_string(),
    )
  }
  {
    group_idx: data[0],
    image_idx: data[1],
    order_idx: data[2],
    name_idx: data[3],
    coe_details: data[5],
    foe_supported: (data[6].to_int() & 0x01) != 0,
    eoe_supported: (data[7].to_int() & 0x01) != 0,
    soe_supported: data[8] != b'\x00',
    soe_channels: if data.length() > 8 {
      data[8]
    } else {
      b'\x00'
    },
    ds402_channels: if data.length() > 9 {
      data[9]
    } else {
      b'\x00'
    },
    sysman_class: if data.length() > 10 {
      data[10]
    } else {
      b'\x00'
    },
    flags: data[11],
    current_on_ebus: read_sii_word(data, 6),
    physical_port_0: if data.length() > 16 {
      data[16] & b'\x0F'
    } else {
      b'\x00'
    },
    physical_port_1: if data.length() > 16 {
      (data[16].to_int() >> 4).to_byte() & b'\x0F'
    } else {
      b'\x00'
    },
    physical_port_2: if data.length() > 17 {
      data[17] & b'\x0F'
    } else {
      b'\x00'
    },
    physical_port_3: if data.length() > 17 {
      (data[17].to_int() >> 4).to_byte() & b'\x0F'
    } else {
      b'\x00'
    },
    physical_memory_address: if data.length() > 19 {
      read_sii_word_at_byte(data, 18)
    } else {
      0U
    },
  }
}

///|
/// Parse the FMMU category data. Each entry is 1 byte indicating FMMU usage.
/// Per ETG1000.6 Table 22: 0x01 = Outputs, 0x02 = Inputs, 0x03 = mailbox state.
pub fn parse_sii_fmmu(data : Bytes) -> Array[FmmuDirection] {
  let result : Array[FmmuDirection] = []
  for i = 0; i < data.length(); i = i + 1 {
    match data[i] {
      b'\x01' => result.push(Outputs)
      b'\x02' => result.push(Inputs)
      b'\x03' => result.push(MailboxState)
      _ => ()
    }
  }
  result
}

///|
/// SM info from SII SM category. Each SM entry is 8 bytes.
pub(all) struct SiiSmEntry {
  physical_start : UInt
  length : UInt
  control : Byte
  status : Byte
  activate : Byte
  sm_type : SmType
} derive(Eq, Show)

///|
/// Parse the SyncManager category data.
pub fn parse_sii_sm(data : Bytes) -> Array[SiiSmEntry] {
  let result : Array[SiiSmEntry] = []
  let entry_size = 8
  let mut offset = 0
  while offset + entry_size <= data.length() {
    let phys = read_sii_word(data, offset / 2)
    let length = read_sii_word(data, offset / 2 + 1)
    let control = data[offset + 4]
    let status = data[offset + 5]
    let activate = data[offset + 6]
    let type_byte = data[offset + 7]
    let sm_type : SmType = match type_byte {
      b'\x01' => MailboxOut
      b'\x02' => MailboxIn
      b'\x03' => ProcessDataOut
      b'\x04' => ProcessDataIn
      _ => Unused
    }
    result.push({
      physical_start: phys,
      length,
      control,
      status,
      activate,
      sm_type,
    })
    offset = offset + entry_size
  }
  result
}

///|
/// Parse the Strings category data (ETG1000.6 Table 20).
/// Returns an array of strings indexed from 1 (index 0 is unused by convention).
pub fn parse_sii_strings(data : Bytes) -> Array[String] {
  let result : Array[String] = []
  if data.length() < 1 {
    return result
  }
  let n_strings = data[0].to_int()
  let mut offset = 1
  for _i = 0; _i < n_strings; _i = _i + 1 {
    if offset >= data.length() {
      break
    }
    let str_len = data[offset].to_int()
    offset = offset + 1
    if offset + str_len > data.length() {
      break
    }
    let bytes = Bytes::makei(str_len, fn(j) { data[offset + j] })
    let decoded : Result[String, Error] = try? @utf8.decode(bytes)
    match decoded {
      Ok(text) => result.push(text)
      Err(_) => result.push(bytes.to_unchecked_string())
    }
    offset = offset + str_len
  }
  result
}

///|
/// Parse TxPdo or RxPdo category data (ETG1000.6 Tables 24+25).
/// Each PDO has a fixed 8-byte header followed by nEntry × 8-byte entries.
pub fn parse_sii_pdo(data : Bytes) -> Array[SiiPdo] {
  let result : Array[SiiPdo] = []
  let mut offset = 0
  while offset + 8 <= data.length() {
    let pdo_index = read_sii_word(data, offset / 2)
    let entry_count = data[offset + 2]
    let sync_manager = data[offset + 3]
    let synchronization = data[offset + 4]
    let name_idx = data[offset + 5]
    let flags = read_sii_word(data, (offset + 6) / 2)
    let n_entries = entry_count.to_int()
    offset = offset + 8
    let entries : Array[SiiPdoEntry] = []
    for _j = 0; _j < n_entries; _j = _j + 1 {
      if offset + 8 > data.length() {
        break
      }
      let entry_index = read_sii_word(data, offset / 2)
      let subindex = data[offset + 2]
      let entry_name_idx = data[offset + 3]
      let data_type = data[offset + 4]
      let bit_length = data[offset + 5]
      let entry_flags = read_sii_word(data, (offset + 6) / 2)
      entries.push({
        entry_index,
        subindex,
        name_idx: entry_name_idx,
        data_type,
        bit_length,
        flags: entry_flags,
      })
      offset = offset + 8
    }
    result.push({
      pdo_index,
      entry_count,
      sync_manager,
      synchronization,
      name_idx,
      flags,
      entries,
    })
  }
  result
}

///|
/// Parse a DC clock category entry.
pub fn parse_sii_dc(data : Bytes) -> SiiDcClock raise @hal.EcError {
  if data.length() < 24 {
    raise @hal.EcError::EsiParseFailed(
      "DC category too short: " + data.length().to_string(),
    )
  }
  {
    cycle_time_0: read_sii_dword_at_byte(data, 0),
    shift_time_0: read_sii_dword_at_byte(data, 4),
    shift_time_1: read_sii_dword_at_byte(data, 8),
    sync1_cycle_factor: read_sii_i16_at_byte(data, 12),
    assign_activate: read_sii_word_at_byte(data, 14),
    sync0_cycle_factor: read_sii_i16_at_byte(data, 16),
    name_idx: data[18],
    description_idx: data[19],
  }
}
