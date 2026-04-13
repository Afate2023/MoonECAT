///|
/// VirtualSlave models a single EtherCAT slave ESC for mock testing.
/// It holds registers, SII EEPROM data, and ESM state, and responds to
/// EtherCAT PDU commands according to ETG.1000.4 addressing rules.
///
/// Inspired by SOES (Simple Open EtherCAT Slave) architecture:
/// - AL state machine with proper transition validation
/// - SM (Sync Manager) 0-3 register handling (0x0800-0x081F)
/// - FMMU register handling (0x0600-0x06FF) for logical addressing
/// - Process data memory for SM2/SM3 PDO exchange
/// - SII EEPROM read via register 0x0502
pub struct VirtualSlave {
  /// Position on the daisy-chain (0-based).
  position : Int
  /// ESC register file (64 KB address space, sparse).
  registers : FixedArray[Byte]
  /// SII EEPROM content (word-addressable, stored as bytes).
  sii_eeprom : Bytes
  /// Current ESM state (mirrored in AL Status register 0x0130).
  mut al_state : Byte
  /// Configured station address (mirrored in register 0x0010).
  mut station_address : UInt
  /// Process data memory backing SM2/SM3 (separate from register file).
  /// Indexed by physical address relative to SM physical_start.
  process_data : FixedArray[Byte]
  /// CoE mailbox object dictionary and response state.
  mailbox : VirtualMailbox
  /// Mailbox defaults parsed from SII, used before SM0/SM1 are rewritten.
  default_mailbox_config : @mailbox.MailboxConfig
  /// True when a mailbox response is ready in SM1.
  mut mailbox_ready : Bool
  /// Pending mailbox response frame, padded to the SM1 size on demand.
  mut pending_mailbox_response : Bytes
} derive(Debug)

///|
/// Maximum ESC register space to model (covers 0x0000..0x0FFF).
let esc_reg_size : Int = 4096

///|
/// Process data memory size (covers SM2/SM3 at typical physical addresses
/// like 0x1000-0x1FFF used in SOES-style ESCs).
let process_data_size : Int = 8192

///|
/// FMMU control register constants.
let fmmu_base : Int = 0x0600

///|
let fmmu_entry_size : Int = 16

///|
/// Max FMMU entries in an ESC (typically 8 or 16).
let max_fmmu_entries : Int = 8

///|
let sm_window_size : Int = @protocol.sm_entry_size

///|
let sm_status_offset : Int = 5

///|
let sm_activate_offset : Int = 6

///|
let mailbox_status_bit : Byte = b'\x08'

// SM constants (0x0800 base, 8-byte stride, 4 entries max)
// are reserved for future SM validation logic.

///|
/// Create a new VirtualSlave at the given bus position with identity and SII.
pub fn VirtualSlave::new(
  position : Int,
  identity : @hal.SlaveIdentity,
  sii_eeprom : Bytes,
) -> VirtualSlave {
  let regs = FixedArray::make(esc_reg_size, b'\x00')
  // Reg 0x0000: Type = 0x02 (generic ESC)
  regs[0x0000] = b'\x02'
  // Reg 0x0001: Revision
  regs[0x0001] = b'\x01'
  // Reg 0x0130-0x0131: AL Status = Init (0x01)
  regs[0x0130] = b'\x01'
  // Reg 0x0110-0x0111: DL Status = link up on port 0+1
  regs[0x0110] = b'\x35'
  regs[0x0111] = b'\x00'
  // Store identity in SII words but also keep station_address
  let default_mailbox_config = try @mailbox.parse_sii_header(sii_eeprom) catch {
    _ => zero_mailbox_config()
  } noraise {
    sii => @mailbox.MailboxConfig::from_sii(sii)
  }
  let slave : VirtualSlave = {
    position,
    registers: regs,
    sii_eeprom,
    al_state: b'\x01', // Init
    station_address: 0U,
    process_data: FixedArray::make(process_data_size, b'\x00'),
    mailbox: VirtualMailbox::new(),
    default_mailbox_config,
    mailbox_ready: false,
    pending_mailbox_response: Bytes::new(0),
  }
  // Write SII word 8-9 identity match comes from parsing the eeprom.
  // No need to duplicate — the SII eeprom already has identity fields.
  ignore(identity)
  slave.initialize_mailbox_sm_registers()
  slave
}

///|
fn zero_mailbox_config() -> @mailbox.MailboxConfig {
  {
    out_address: 0U,
    out_size: 0U,
    out_sm_index: 0,
    in_address: 0U,
    in_size: 0U,
    in_sm_index: 1,
  }
}

///|
fn sm_window_base(sm_index : Int) -> Int {
  @protocol.reg_sm_base.reinterpret_as_int() + sm_index * sm_window_size
}

///|
fn read_u16_le_from_registers(
  registers : FixedArray[Byte],
  offset : Int,
) -> UInt {
  registers[offset].to_uint() | (registers[offset + 1].to_uint() << 8)
}

///|
fn VirtualSlave::initialize_mailbox_sm_registers(self : VirtualSlave) -> Unit {
  if !self.default_mailbox_config.is_valid() {
    return
  }
  self.set_sm_window(
    self.default_mailbox_config.out_sm_index,
    self.default_mailbox_config.out_address,
    self.default_mailbox_config.out_size,
    b'\x26',
    false,
  )
  self.set_sm_window(
    self.default_mailbox_config.in_sm_index,
    self.default_mailbox_config.in_address,
    self.default_mailbox_config.in_size,
    b'\x22',
    false,
  )
}

///|
fn VirtualSlave::set_sm_window(
  self : VirtualSlave,
  sm_index : Int,
  start : UInt,
  length : UInt,
  control : Byte,
  ready : Bool,
) -> Unit {
  let base = sm_window_base(sm_index)
  if base + sm_window_size > esc_reg_size {
    return
  }
  self.registers[base] = (start & 0xFFU).to_byte()
  self.registers[base + 1] = ((start >> 8) & 0xFFU).to_byte()
  self.registers[base + 2] = (length & 0xFFU).to_byte()
  self.registers[base + 3] = ((length >> 8) & 0xFFU).to_byte()
  self.registers[base + 4] = control
  self.registers[base + sm_status_offset] = if ready {
    mailbox_status_bit
  } else {
    b'\x00'
  }
  self.registers[base + sm_activate_offset] = b'\x01'
  self.registers[base + 7] = b'\x00'
}

///|
fn VirtualSlave::current_mailbox_config(
  self : VirtualSlave,
) -> @mailbox.MailboxConfig {
  let out_base = sm_window_base(0)
  let in_base = sm_window_base(1)
  if in_base + sm_window_size <= esc_reg_size {
    let out_address = read_u16_le_from_registers(self.registers, out_base)
    let out_size = read_u16_le_from_registers(self.registers, out_base + 2)
    let in_address = read_u16_le_from_registers(self.registers, in_base)
    let in_size = read_u16_le_from_registers(self.registers, in_base + 2)
    let current : @mailbox.MailboxConfig = {
      out_address,
      out_size,
      out_sm_index: 0,
      in_address,
      in_size,
      in_sm_index: 1,
    }
    if current.is_valid() {
      return current
    }
  }
  self.default_mailbox_config
}

///|
fn mailbox_range_overlaps(
  offset : Int,
  length : Int,
  start : UInt,
  size : UInt,
) -> Bool {
  let range_start = start.reinterpret_as_int()
  let range_end = range_start + size.reinterpret_as_int()
  offset < range_end && offset + length > range_start
}

///|
fn VirtualSlave::update_mailbox_sm_status(self : VirtualSlave) -> Unit {
  let cfg = self.current_mailbox_config()
  if !cfg.is_valid() {
    return
  }
  let out_base = sm_window_base(cfg.out_sm_index)
  let in_base = sm_window_base(cfg.in_sm_index)
  if out_base + sm_status_offset < esc_reg_size {
    self.registers[out_base + sm_status_offset] = b'\x00'
  }
  if in_base + sm_status_offset < esc_reg_size {
    self.registers[in_base + sm_status_offset] = if self.mailbox_ready {
      mailbox_status_bit
    } else {
      b'\x00'
    }
  }
}

///|
fn VirtualSlave::write_physical_range(
  self : VirtualSlave,
  offset : Int,
  data : Bytes,
) -> Unit {
  for i in 0..<data.length() {
    let addr = offset + i
    if addr >= 0 && addr < process_data_size {
      self.process_data[addr] = data[i]
    }
  }
}

///|
fn pad_mailbox_frame(frame : Bytes, size : Int) -> Bytes {
  Bytes::makei(size, fn(i) {
    if i < frame.length() {
      frame[i]
    } else {
      b'\x00'
    }
  })
}

///|
fn VirtualSlave::download_request_data_length(
  self : VirtualSlave,
  index : UInt,
  subindex : Byte,
) -> Int {
  match self.mailbox.find_od(index, subindex) {
    Some(entry) if entry.data.length() > 0 && entry.data.length() < 4 =>
      entry.data.length()
    _ => 4
  }
}

///|
fn VirtualSlave::load_pending_mailbox_response(
  self : VirtualSlave,
  cfg : @mailbox.MailboxConfig,
) -> Unit {
  if !cfg.is_valid() || self.pending_mailbox_response.length() <= 0 {
    return
  }
  self.write_physical_range(
    cfg.in_address.reinterpret_as_int(),
    self.pending_mailbox_response,
  )
}

///|
fn VirtualSlave::handle_mailbox_request(
  self : VirtualSlave,
  cfg : @mailbox.MailboxConfig,
) -> Unit {
  if !cfg.is_valid() {
    return
  }
  let request = self.read_process_data(
    cfg.out_address.reinterpret_as_int(),
    cfg.out_size.reinterpret_as_int(),
  )
  let response = try @mailbox.MailboxHeader::from_bytes(request) catch {
    _ => Bytes::new(0)
  } noraise {
    mbh =>
      if mbh.mb_type == @mailbox.MailboxType::CoE && request.length() >= 12 {
        let command = request[8]
        let index = request[9].to_uint() | (request[10].to_uint() << 8)
        let subindex = request[11]
        if command == b'\x40' {
          match self.mailbox.handle_sdo_upload(index, subindex) {
            Some(frame) => frame
            None => Bytes::new(0)
          }
        } else if ((command >> 5) & b'\x07') == b'\x01' {
          let data_len = self.download_request_data_length(index, subindex)
          let payload = Bytes::makei(data_len, fn(i) {
            if 12 + i < request.length() {
              request[12 + i]
            } else {
              b'\x00'
            }
          })
          self.mailbox.handle_sdo_download(index, subindex, payload)
        } else {
          Bytes::new(0)
        }
      } else {
        Bytes::new(0)
      }
  }
  self.pending_mailbox_response = if response.length() > 0 {
    pad_mailbox_frame(response, cfg.in_size.reinterpret_as_int())
  } else {
    Bytes::new(0)
  }
  self.mailbox_ready = self.pending_mailbox_response.length() > 0
  self.load_pending_mailbox_response(cfg)
  self.update_mailbox_sm_status()
}

///|
fn VirtualSlave::clear_mailbox_response_if_read(
  self : VirtualSlave,
  cfg : @mailbox.MailboxConfig,
  offset : Int,
  length : Int,
) -> Unit {
  if !self.mailbox_ready || !cfg.is_valid() {
    return
  }
  if mailbox_range_overlaps(offset, length, cfg.in_address, cfg.in_size) {
    self.mailbox_ready = false
    self.pending_mailbox_response = Bytes::new(0)
    self.update_mailbox_sm_status()
  }
}

///|
/// Read a register range from this slave.
pub fn VirtualSlave::read_reg(
  self : VirtualSlave,
  offset : Int,
  length : Int,
) -> Bytes {
  let cfg = self.current_mailbox_config()
  self.update_mailbox_sm_status()
  if self.mailbox_ready &&
    mailbox_range_overlaps(offset, length, cfg.in_address, cfg.in_size) {
    self.load_pending_mailbox_response(cfg)
  }
  let buf = FixedArray::make(length, b'\x00')
  for i in 0..<length {
    let addr = offset + i
    if addr < esc_reg_size {
      buf[i] = self.registers[addr]
    } else if addr >= 0 && addr < process_data_size {
      buf[i] = self.process_data[addr]
    }
  }
  let result = Bytes::makei(length, fn(i) { buf[i] })
  self.clear_mailbox_response_if_read(cfg, offset, length)
  result
}

///|
/// Write a register range on this slave, applying ESM and SII side-effects.
pub fn VirtualSlave::write_reg(
  self : VirtualSlave,
  offset : Int,
  data : Bytes,
) -> Unit {
  for i in 0..<data.length() {
    let addr = offset + i
    if addr < esc_reg_size {
      self.registers[addr] = data[i]
    } else if addr >= 0 && addr < process_data_size {
      self.process_data[addr] = data[i]
    }
  }
  // Side-effect: station address write at 0x0010
  if offset <= 0x0010 && offset + data.length() > 0x0010 {
    self.station_address = self.registers[0x0010].to_uint() |
      (self.registers[0x0011].to_uint() << 8)
  }
  // Side-effect: AL Control write at 0x0120 → update AL Status at 0x0130
  if offset <= 0x0120 && offset + data.length() > 0x0120 {
    let requested = self.registers[0x0120] & b'\x0F'
    // Accept all valid transitions; set error bit on invalid ones
    let current = self.al_state & b'\x0F'
    let valid = match (current.to_int(), requested.to_int()) {
      (0x01, 0x02) => true // Init → PreOp
      (0x01, 0x03) => true // Init → Boot
      (0x02, 0x04) => true // PreOp → SafeOp
      (0x02, 0x01) => true // PreOp → Init
      (0x04, 0x08) => true // SafeOp → Op
      (0x04, 0x02) => true // SafeOp → PreOp
      (0x04, 0x01) => true // SafeOp → Init
      (0x08, 0x04) => true // Op → SafeOp
      (0x08, 0x02) => true // Op → PreOp
      (0x08, 0x01) => true // Op → Init
      (0x03, 0x01) => true // Boot → Init
      _ => false
    }
    if valid {
      self.al_state = requested
      self.registers[0x0130] = requested
      self.registers[0x0131] = b'\x00'
      // Clear AL Status Code on success
      self.registers[0x0134] = b'\x00'
      self.registers[0x0135] = b'\x00'
    } else {
      // Set error indication (bit 4) + keep current state
      self.registers[0x0130] = self.al_state | b'\x10'
      self.registers[0x0131] = b'\x00'
      // AL Status Code = 0x0001 (Unspecified error)
      self.registers[0x0134] = b'\x01'
      self.registers[0x0135] = b'\x00'
    }
  }
  // Side-effect: SII control write at 0x0502 → handle EEPROM read
  if offset <= 0x0502 && offset + data.length() > 0x0502 {
    self.handle_sii_access()
  }
  let cfg = self.current_mailbox_config()
  if mailbox_range_overlaps(
      offset,
      data.length(),
      cfg.out_address,
      cfg.out_size,
    ) {
    self.handle_mailbox_request(cfg)
  }
}

///|
/// Handle SII EEPROM access triggered by writing to the SII control register.
fn VirtualSlave::handle_sii_access(self : VirtualSlave) -> Unit {
  let control = self.registers[0x0502].to_int() |
    (self.registers[0x0503].to_int() << 8)
  // Bit 8 = Read (ETG.1000.4 SII Control/Status, 0x0100 in 16-bit word).
  // Also accept bit 0 for single-byte legacy trigger (0x01 at 0x0502).
  let is_read = (control & 0x0100) != 0 || (control & 0x01) != 0
  if is_read {
    // Read command: word address from 0x0504-0x0507
    let word_addr = self.registers[0x0504].to_int() |
      (self.registers[0x0505].to_int() << 8) |
      (self.registers[0x0506].to_int() << 16) |
      (self.registers[0x0507].to_int() << 24)
    let byte_addr = word_addr * 2
    // Read up to 8 bytes from EEPROM into SII data registers 0x0508-0x050F
    for i in 0..<8 {
      if byte_addr + i < self.sii_eeprom.length() {
        self.registers[0x0508 + i] = self.sii_eeprom[byte_addr + i]
      } else {
        self.registers[0x0508 + i] = b'\xFF'
      }
    }
    // Clear busy/command bits
    self.registers[0x0502] = b'\x00'
    self.registers[0x0503] = b'\x00'
  }
}

///|
/// Parsed FMMU entry from registers.
pub(all) struct FmmuEntry {
  logical_start : UInt
  length : UInt
  logical_start_bit : Int
  logical_end_bit : Int
  physical_start : UInt
  physical_start_bit : Int
  /// 0x01 = read (slave→master), 0x02 = write (master→slave)
  direction : Int
  activate : Bool
} derive(Debug)

///|
/// Read and parse FMMU entry n from the register file.
pub fn VirtualSlave::get_fmmu(self : VirtualSlave, n : Int) -> FmmuEntry {
  let base = fmmu_base + n * fmmu_entry_size
  let logical_start = self.registers[base].to_uint() |
    (self.registers[base + 1].to_uint() << 8) |
    (self.registers[base + 2].to_uint() << 16) |
    (self.registers[base + 3].to_uint() << 24)
  let length = self.registers[base + 4].to_uint() |
    (self.registers[base + 5].to_uint() << 8)
  let logical_start_bit = self.registers[base + 6].to_int()
  let logical_end_bit = self.registers[base + 7].to_int()
  let physical_start = self.registers[base + 8].to_uint() |
    (self.registers[base + 9].to_uint() << 8)
  let physical_start_bit = self.registers[base + 10].to_int()
  let direction = self.registers[base + 11].to_int()
  let activate = self.registers[base + 12] != b'\x00'
  {
    logical_start,
    length,
    logical_start_bit,
    logical_end_bit,
    physical_start,
    physical_start_bit,
    direction,
    activate,
  }
}

///|
/// Get all active FMMU entries for this slave.
pub fn VirtualSlave::active_fmmus(self : VirtualSlave) -> Array[FmmuEntry] {
  let result : Array[FmmuEntry] = []
  for i in 0..<max_fmmu_entries {
    let fmmu = self.get_fmmu(i)
    if fmmu.activate && fmmu.length > 0U {
      result.push(fmmu)
    }
  }
  result
}

///|
/// Read process data at the given physical address (relative).
/// Addresses map to the process_data backing store.
pub fn VirtualSlave::read_process_data(
  self : VirtualSlave,
  physical_start : Int,
  length : Int,
) -> Bytes {
  let buf = FixedArray::make(length, b'\x00')
  for i in 0..<length {
    let addr = physical_start + i
    if addr >= 0 && addr < process_data_size {
      buf[i] = self.process_data[addr]
    }
  }
  Bytes::makei(length, fn(i) { buf[i] })
}

///|
/// Write process data at the given physical address (relative).
pub fn VirtualSlave::write_process_data(
  self : VirtualSlave,
  physical_start : Int,
  data : FixedArray[Byte],
  offset : Int,
  length : Int,
) -> Unit {
  for i in 0..<length {
    let addr = physical_start + i
    if addr >= 0 && addr < process_data_size {
      self.process_data[addr] = data[offset + i]
    }
  }
}

///|
/// Handle an LRW/LRD/LWR logical address access through FMMU mapping.
/// Returns (did_read, did_write) to compute WKC increment.
pub fn VirtualSlave::process_logical(
  self : VirtualSlave,
  logical_addr : UInt,
  data_len : Int,
  pdu_data : FixedArray[Byte],
  out_data : FixedArray[Byte],
  is_read : Bool,
  is_write : Bool,
) -> (Bool, Bool) {
  let mut did_read = false
  let mut did_write = false
  for i in 0..<max_fmmu_entries {
    let fmmu = self.get_fmmu(i)
    if !fmmu.activate || fmmu.length == 0U {
      continue
    }
    let fmmu_logical_end = fmmu.logical_start + fmmu.length
    let pdu_logical_end = logical_addr + data_len.reinterpret_as_uint()
    // Check overlap between [logical_addr, pdu_logical_end) and [fmmu.logical_start, fmmu_logical_end)
    if logical_addr >= fmmu_logical_end || pdu_logical_end <= fmmu.logical_start {
      continue
    }
    let overlap_start = if logical_addr > fmmu.logical_start {
      logical_addr
    } else {
      fmmu.logical_start
    }
    let overlap_end = if pdu_logical_end < fmmu_logical_end {
      pdu_logical_end
    } else {
      fmmu_logical_end
    }
    let pdu_offset = (overlap_start - logical_addr).reinterpret_as_int()
    let phys_offset = (overlap_start - fmmu.logical_start).reinterpret_as_int() +
      fmmu.physical_start.reinterpret_as_int()
    let count = (overlap_end - overlap_start).reinterpret_as_int()
    // direction: 0x01 = read (slave→master, inputs), 0x02 = write (master→slave, outputs)
    if is_read && (fmmu.direction & 0x01) != 0 {
      // Read: copy from process_data to out_data
      for j in 0..<count {
        let addr = phys_offset + j
        if addr >= 0 && addr < process_data_size {
          out_data[pdu_offset + j] = self.process_data[addr]
        }
      }
      did_read = true
    }
    if is_write && (fmmu.direction & 0x02) != 0 {
      // Write: copy from pdu_data to process_data
      for j in 0..<count {
        let addr = phys_offset + j
        if addr >= 0 && addr < process_data_size {
          self.process_data[addr] = pdu_data[pdu_offset + j]
        }
      }
      did_write = true
    }
  }
  (did_read, did_write)
}
