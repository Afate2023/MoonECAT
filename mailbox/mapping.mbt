///|
/// FMMU and Sync Manager mapping calculation.
/// Converts SII EEPROM metadata into hardware-ready FmmuConfig / SmConfig
/// register arrays that can be written to slave registers.

///|
/// Result of FMMU / SM mapping calculation for one slave.
pub(all) struct SlaveMapping {
  /// Sync Manager configs for register programming (SM0, SM1, …).
  sm_configs : Array[SmConfig]
  /// FMMU configs for register programming (FMMU0, FMMU1, …).
  fmmu_configs : Array[FmmuConfig]
  /// Total bytes of output (master→slave) process data for this slave.
  output_bytes : Int
  /// Total bytes of input (slave→master) process data for this slave.
  input_bytes : Int
} derive(Show, Eq)

///|
/// Compute SmConfig array from SII SM entries and mailbox header info.
/// Mailbox SM entries use the SII header offsets/sizes; process-data SM
/// entries keep the physical addresses from the SII SM category.
pub fn calculate_sm_configs(
  sii_header : SiiData,
  sii_sm_entries : Array[SiiSmEntry],
) -> Array[SmConfig] {
  let configs : Array[SmConfig] = []
  for i = 0; i < sii_sm_entries.length(); i = i + 1 {
    let e = sii_sm_entries[i]
    let (phys, len) : (UInt, UInt) = match e.sm_type {
      MailboxOut => (sii_header.mailbox_rx_offset, sii_header.mailbox_rx_size)
      MailboxIn => (sii_header.mailbox_tx_offset, sii_header.mailbox_tx_size)
      _ => (e.physical_start, e.length)
    }
    configs.push({
      physical_start: phys,
      length: len,
      control: e.control,
      status: b'\x00',
      activate: e.activate,
      sm_type: e.sm_type,
    })
  }
  configs
}

///|
fn pdo_bit_length_for_sync_manager(
  pdos : Array[SiiPdo],
  sync_manager : Byte,
) -> Int {
  let mut total_bits = 0
  for pdo in pdos {
    if pdo.sync_manager == sync_manager {
      for entry in pdo.entries {
        total_bits = total_bits + entry.bit_length.to_int()
      }
    }
  }
  total_bits
}

///|
pub fn apply_pdo_lengths_to_sm_configs(
  sm_configs : Array[SmConfig],
  tx_pdos : Array[SiiPdo],
  rx_pdos : Array[SiiPdo],
) -> Array[SmConfig] {
  let updated : Array[SmConfig] = []
  for i = 0; i < sm_configs.length(); i = i + 1 {
    let sm = sm_configs[i]
    let patched = if sm.length == 0U {
      let total_bits = match sm.sm_type {
        ProcessDataOut | DynamicProcessDataOut =>
          pdo_bit_length_for_sync_manager(rx_pdos, i.to_byte())
        ProcessDataIn | DynamicProcessDataIn =>
          pdo_bit_length_for_sync_manager(tx_pdos, i.to_byte())
        _ => 0
      }
      if total_bits > 0 {
        { ..sm, length: ((total_bits + 7) / 8).reinterpret_as_uint() }
      } else {
        sm
      }
    } else {
      sm
    }
    updated.push(patched)
  }
  updated
}

///|
/// Compute FmmuConfig array from SII FMMU directions and the calculated
/// SM configs.  Each FMMU entry maps a contiguous block of logical address
/// space to the physical address of the corresponding process-data SM.
///
/// `logical_base` — starting logical address for this slave's mapped I/O.
///
/// Returns `(fmmu_configs, output_bytes, input_bytes)`.
pub fn calculate_fmmu_configs(
  fmmu_directions : Array[FmmuDirection],
  sm_configs : Array[SmConfig],
  logical_base : UInt,
) -> (Array[FmmuConfig], Int, Int) {
  let fmmus : Array[FmmuConfig] = []
  let mut current_offset = logical_base
  let mut total_output = 0
  let mut total_input = 0
  // Match each FMMU direction to the first SM of the appropriate
  // process-data type that hasn't been assigned yet.
  let sm_used : Array[Bool] = Array::make(sm_configs.length(), false)
  for i = 0; i < fmmu_directions.length(); i = i + 1 {
    let dir = fmmu_directions[i]
    let target_type : SmType = match dir {
      Outputs => ProcessDataOut
      Inputs => ProcessDataIn
      MailboxState => continue
    }
    // find matching SM
    let sm_idx = find_unassigned_sm(sm_configs, sm_used, target_type)
    match sm_idx {
      Some(idx) => {
        sm_used[idx] = true
        let sm = sm_configs[idx]
        let length = sm.length
        fmmus.push({
          logical_start: current_offset,
          length,
          logical_start_bit: b'\x00',
          logical_end_bit: b'\x07',
          physical_start: sm.physical_start,
          physical_start_bit: b'\x00',
          direction: dir,
          activate: true,
        })
        let byte_len = length.reinterpret_as_int()
        match dir {
          Outputs => total_output = total_output + byte_len
          Inputs => total_input = total_input + byte_len
          MailboxState => ()
        }
        current_offset = current_offset + length
      }
      None =>
        // If there is an FMMU direction but no matching process-data SM is
        // available, try to match a mailbox SM as a fallback (some slaves
        // use FMMU for mailbox).
        match dir {
          Outputs => {
            let mb_idx = find_unassigned_sm(sm_configs, sm_used, MailboxOut)
            match mb_idx {
              Some(idx) => {
                sm_used[idx] = true
                let sm = sm_configs[idx]
                fmmus.push({
                  logical_start: current_offset,
                  length: sm.length,
                  logical_start_bit: b'\x00',
                  logical_end_bit: b'\x07',
                  physical_start: sm.physical_start,
                  physical_start_bit: b'\x00',
                  direction: dir,
                  activate: true,
                })
                current_offset = current_offset + sm.length
              }
              None => ()
            }
          }
          Inputs => {
            let mb_idx = find_unassigned_sm(sm_configs, sm_used, MailboxIn)
            match mb_idx {
              Some(idx) => {
                sm_used[idx] = true
                let sm = sm_configs[idx]
                fmmus.push({
                  logical_start: current_offset,
                  length: sm.length,
                  logical_start_bit: b'\x00',
                  logical_end_bit: b'\x07',
                  physical_start: sm.physical_start,
                  physical_start_bit: b'\x00',
                  direction: dir,
                  activate: true,
                })
                current_offset = current_offset + sm.length
              }
              None => ()
            }
          }
          MailboxState => ()
        }
    }
  }
  (fmmus, total_output, total_input)
}

///|
/// Find the first unassigned SM whose type matches.
fn find_unassigned_sm(
  sm_configs : Array[SmConfig],
  sm_used : Array[Bool],
  target : SmType,
) -> Int? {
  for i = 0; i < sm_configs.length(); i = i + 1 {
    let matches = match (target, sm_configs[i].sm_type) {
      (ProcessDataOut, ProcessDataOut | DynamicProcessDataOut) => true
      (ProcessDataIn, ProcessDataIn | DynamicProcessDataIn) => true
      _ => sm_configs[i].sm_type == target
    }
    if matches && not(sm_used[i]) {
      return Some(i)
    }
  }
  None
}

///|
/// High-level helper: compute the full mapping for a slave from its raw SII
/// EEPROM data and a logical base address.
pub fn calculate_slave_mapping(
  eeprom : Bytes,
  logical_base : UInt,
) -> SlaveMapping raise @hal.EcError {
  let sii_header = parse_sii_header(eeprom)
  let categories = parse_sii_categories(eeprom)
  // Extract FMMU and SM category data
  let mut fmmu_dirs : Array[FmmuDirection] = []
  let mut sm_entries : Array[SiiSmEntry] = []
  let mut tx_pdos : Array[SiiPdo] = []
  let mut rx_pdos : Array[SiiPdo] = []
  for i = 0; i < categories.length(); i = i + 1 {
    match categories[i].category {
      Fmmu => fmmu_dirs = parse_sii_fmmu(categories[i].data)
      SyncManager => sm_entries = parse_sii_sm(categories[i].data)
      TxPdo => tx_pdos = parse_sii_pdo(categories[i].data)
      RxPdo => rx_pdos = parse_sii_pdo(categories[i].data)
      _ => ()
    }
  }
  let sm_configs = apply_pdo_lengths_to_sm_configs(
    calculate_sm_configs(sii_header, sm_entries),
    tx_pdos,
    rx_pdos,
  )
  let (fmmu_configs, output_bytes, input_bytes) = calculate_fmmu_configs(
    fmmu_dirs, sm_configs, logical_base,
  )
  { sm_configs, fmmu_configs, output_bytes, input_bytes }
}

///|
/// Encode an SmConfig into 8 bytes suitable for writing to SM registers.
pub fn SmConfig::to_bytes(self : SmConfig) -> Bytes {
  let buf = @buffer.new(size_hint=8)
  // Bytes 0-1: physical start address (LE)
  buf.write_byte((self.physical_start & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(
    ((self.physical_start >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
  )
  // Bytes 2-3: length (LE)
  buf.write_byte((self.length & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((self.length >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  // Byte 4: control
  buf.write_byte(self.control)
  // Byte 5: status (always 0 for writes)
  buf.write_byte(self.status)
  // Byte 6: activation register, preserve all SII-provided bits.
  buf.write_byte(self.activate)
  // Byte 7: reserved
  buf.write_byte(b'\x00')
  buf.to_bytes()
}

///|
/// Encode an FmmuConfig into 16 bytes suitable for writing to FMMU registers.
pub fn FmmuConfig::to_bytes(self : FmmuConfig) -> Bytes {
  let buf = @buffer.new(size_hint=16)
  // Bytes 0-3: logical start address (LE 32-bit)
  buf.write_byte((self.logical_start & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(
    ((self.logical_start >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
  )
  buf.write_byte(
    ((self.logical_start >> 16) & 0xFFU).reinterpret_as_int().to_byte(),
  )
  buf.write_byte(
    ((self.logical_start >> 24) & 0xFFU).reinterpret_as_int().to_byte(),
  )
  // Bytes 4-5: length (LE 16-bit)
  buf.write_byte((self.length & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((self.length >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  // Byte 6: logical start bit
  buf.write_byte(self.logical_start_bit)
  // Byte 7: logical end bit
  buf.write_byte(self.logical_end_bit)
  // Bytes 8-9: physical start address (LE 16-bit)
  buf.write_byte((self.physical_start & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(
    ((self.physical_start >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
  )
  // Byte 10: physical start bit
  buf.write_byte(self.physical_start_bit)
  // Byte 11: FMMU type register — 0x02 = write access (outputs, master→slave),
  // 0x01 = read access (inputs, slave→master). Per ESC register spec.
  let dir_byte : Byte = match self.direction {
    Outputs => b'\x02'
    Inputs => b'\x01'
    MailboxState => b'\x00'
  }
  buf.write_byte(dir_byte)
  // Byte 12: activate
  buf.write_byte(if self.activate { b'\x01' } else { b'\x00' })
  // Bytes 13-15: reserved
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.to_bytes()
}
