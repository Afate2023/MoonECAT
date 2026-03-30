///|
/// VirtualSlave models a single EtherCAT slave ESC for mock testing.
/// It holds registers, SII EEPROM data, and ESM state, and responds to
/// EtherCAT PDU commands according to ETG.1000.4 addressing rules.
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
} derive(Show)

///|
/// Maximum ESC register space to model (covers 0x0000..0x0FFF).
let esc_reg_size : Int = 4096

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
  let slave : VirtualSlave = {
    position,
    registers: regs,
    sii_eeprom,
    al_state: b'\x01', // Init
    station_address: 0U,
  }
  // Write SII word 8-9 identity match comes from parsing the eeprom.
  // No need to duplicate — the SII eeprom already has identity fields.
  ignore(identity)
  slave
}

///|
/// Read a register range from this slave.
pub fn VirtualSlave::read_reg(
  self : VirtualSlave,
  offset : Int,
  length : Int,
) -> Bytes {
  let buf = FixedArray::make(length, b'\x00')
  for i in 0..<length {
    let addr = offset + i
    if addr < esc_reg_size {
      buf[i] = self.registers[addr]
    }
  }
  Bytes::makei(length, fn(i) { buf[i] })
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
}

///|
/// Handle SII EEPROM access triggered by writing to the SII control register.
fn VirtualSlave::handle_sii_access(self : VirtualSlave) -> Unit {
  let control = self.registers[0x0502]
  let cmd = (control.to_int() >> 0) & 0x07
  // Bit 0 = Read, Bit 1 = Write (simplified: we only handle read)
  if (cmd & 0x01) != 0 {
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
    // Clear busy bit, set command-complete/ready
    self.registers[0x0502] = b'\x00'
  }
}
