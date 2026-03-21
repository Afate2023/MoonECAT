///|
/// Provides shared test fixtures across the project.
/// Import this package in test-import sections for common test data.

///|
/// A minimal valid EtherCAT frame (broadcast NOP) for testing.
/// dst(6) + src(6) + ethertype(2) + ecat_header(2) + pdu_header(10) + wkc(2) = 28 bytes
pub fn minimal_nop_frame() -> Bytes {
  Bytes::from_array([
    // Dst MAC: broadcast
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
    // Src MAC: default master
     b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
    // EtherType: 0x88A4 (EtherCAT)
     b'\x88', b'\xA4',
    // EtherCAT header: length=12 (PDU header 10 + WKC 2), type=1
     b'\x0C', b'\x10',
    // PDU: NOP command
     b'\x00', // command: NOP
     b'\x00', // index
     b'\x00', b'\x00', b'\x00', b'\x00', // address
     b'\x00', b'\x00', // len_flags (data_len=0, next=0)
     b'\x00', b'\x00', // IRQ
    // WKC
     b'\x00', b'\x00',
  ])
}

///|
/// A sample slave identity for the Beckhoff EK1100 coupler.
pub fn sample_ek1100_identity() -> @hal.SlaveIdentity {
  {
    vendor_id: 0x2U, // Beckhoff
    product_code: 0x44C2C52U,
    revision: 0x110000U,
    serial: 0x0U,
  }
}

///|
/// Synthetic SII EEPROM image for testing SII parser.
/// Layout: 128 words (256 bytes) with Beckhoff EK1100-like header + categories.
pub fn sample_sii_eeprom() -> Bytes {
  // Create a 256-byte buffer initialized to 0
  let data = FixedArray::make(256, b'\x00')
  // Word 8-9: Vendor ID = 0x00000002 (Beckhoff)
  data[16] = b'\x02'
  data[17] = b'\x00'
  data[18] = b'\x00'
  data[19] = b'\x00'
  // Word 10-11: Product Code = 0x044C2C52
  data[20] = b'\x52'
  data[21] = b'\x2C'
  data[22] = b'\x4C'
  data[23] = b'\x04'
  // Word 12-13: Revision = 0x00110000
  data[24] = b'\x00'
  data[25] = b'\x00'
  data[26] = b'\x11'
  data[27] = b'\x00'
  // Word 14-15: Serial = 0x00000000
  // (already zero)
  // Word 24: Standard RX Mailbox Offset = 0x1000
  data[48] = b'\x00'
  data[49] = b'\x10'
  // Word 25: Standard RX Mailbox Size = 128
  data[50] = b'\x80'
  data[51] = b'\x00'
  // Word 26: Standard TX Mailbox Offset = 0x1080
  data[52] = b'\x80'
  data[53] = b'\x10'
  // Word 27: Standard TX Mailbox Size = 128
  data[54] = b'\x80'
  data[55] = b'\x00'
  // Word 28: Mailbox Protocol = 0x000C (CoE + FoE)
  data[56] = b'\x0C'
  data[57] = b'\x00'
  // Category area starts at word 64 (byte 128)
  // Category 1: General (type=30, size=8 words = 16 bytes)
  data[128] = b'\x1E' // type = 30
  data[129] = b'\x00'
  data[130] = b'\x08' // size = 8 words
  data[131] = b'\x00'
  // General category data (16 bytes starting at byte 132)
  data[132] = b'\x01' // group_idx
  data[133] = b'\x02' // image_idx
  data[134] = b'\x03' // order_idx
  data[135] = b'\x04' // name_idx
  data[136] = b'\x00' // reserved
  data[137] = b'\x07' // coe_details
  data[138] = b'\x01' // FoE Details (byte 6): Bit 0 = Enable FoE
  data[139] = b'\x01' // EoE Details (byte 7): Bit 0 = Enable EoE
  // Category 2: FMMU (type=40, size=1 word = 2 bytes)
  data[148] = b'\x28' // type = 40
  data[149] = b'\x00'
  data[150] = b'\x01' // size = 1 word
  data[151] = b'\x00'
  data[152] = b'\x01' // FMMU0: Outputs (Read)
  data[153] = b'\x02' // FMMU1: Inputs (Write)
  // Category 3: SM (type=41, size=8 words = 16 bytes, 2 SM entries)
  data[154] = b'\x29' // type = 41
  data[155] = b'\x00'
  data[156] = b'\x08' // size = 8 words
  data[157] = b'\x00'
  // SM0: MailboxOut at 0x1000, size 128
  data[158] = b'\x00'
  data[159] = b'\x10' // physical_start = 0x1000
  data[160] = b'\x80'
  data[161] = b'\x00' // length = 128
  data[162] = b'\x26' // control
  // data[163]: status (ignored per spec)
  data[164] = b'\x01' // enable = true
  data[165] = b'\x01' // SM type = MailboxOut (byte 7 per ETG1000.6 Table 23)
  // SM1: MailboxIn at 0x1080, size 128
  data[166] = b'\x80'
  data[167] = b'\x10' // physical_start = 0x1080
  data[168] = b'\x80'
  data[169] = b'\x00' // length = 128
  data[170] = b'\x22' // control
  // data[171]: status (ignored)
  data[172] = b'\x01' // enable = true
  data[173] = b'\x02' // SM type = MailboxIn
  // End marker: 0xFFFF
  data[174] = b'\xFF'
  data[175] = b'\xFF'
  Bytes::makei(data.length(), fn(i) { data[i] })
}

///|
/// Synthetic SII EEPROM image with process-data SM entries for mapping tests.
/// Has 4 SM entries: SM0=MailboxOut, SM1=MailboxIn, SM2=ProcessDataOut(32B), SM3=ProcessDataIn(16B)
/// And 2 FMMU directions: Outputs (master→slave), Inputs (slave→master).
pub fn sample_sii_eeprom_with_pdo() -> Bytes {
  let data = FixedArray::make(320, b'\x00')
  // Word 8-9: Vendor ID = 0x00000002
  data[16] = b'\x02'
  // Word 10-11: Product Code = 0x044C2C52
  data[20] = b'\x52'
  data[21] = b'\x2C'
  data[22] = b'\x4C'
  data[23] = b'\x04'
  // Word 12-13: Revision = 0x00110000
  data[26] = b'\x11'
  // Word 24: RX Mailbox Offset = 0x1000
  data[48] = b'\x00'
  data[49] = b'\x10'
  // Word 25: RX Mailbox Size = 128
  data[50] = b'\x80'
  // Word 26: TX Mailbox Offset = 0x1080
  data[52] = b'\x80'
  data[53] = b'\x10'
  // Word 27: TX Mailbox Size = 128
  data[54] = b'\x80'
  // Word 28: Mailbox Protocol = 0x000C
  data[56] = b'\x0C'
  // Category area at word 64 (byte 128)
  // Category 1: FMMU (type=40, size=1 word = 2 bytes)
  data[128] = b'\x28' // type = 40
  data[130] = b'\x01' // size = 1 word
  data[132] = b'\x01' // FMMU0: Outputs (master→slave)
  data[133] = b'\x02' // FMMU1: Inputs (slave→master)
  // Category 2: SM (type=41, size=16 words = 32 bytes, 4 SM entries)
  data[134] = b'\x29' // type = 41
  data[136] = b'\x10' // size = 16 words
  // SM0: MailboxOut at 0x1000, size 128
  data[138] = b'\x00'
  data[139] = b'\x10' // physical_start
  data[140] = b'\x80' // length = 128
  data[142] = b'\x26' // control
  // data[143]: status (ignored)
  data[144] = b'\x01' // enable
  data[145] = b'\x01' // SM type = MailboxOut (byte 7)
  // SM1: MailboxIn at 0x1080, size 128
  data[146] = b'\x80'
  data[147] = b'\x10'
  data[148] = b'\x80'
  data[150] = b'\x22'
  // data[151]: status (ignored)
  data[152] = b'\x01' // enable
  data[153] = b'\x02' // SM type = MailboxIn
  // SM2: ProcessDataOut at 0x1100, size 32
  data[154] = b'\x00'
  data[155] = b'\x11' // physical_start = 0x1100
  data[156] = b'\x20' // length = 32
  data[158] = b'\x64' // control
  // data[159]: status (ignored)
  data[160] = b'\x01' // enable
  data[161] = b'\x03' // SM type = ProcessDataOut
  // SM3: ProcessDataIn at 0x1200, size 16
  data[162] = b'\x00'
  data[163] = b'\x12' // physical_start = 0x1200
  data[164] = b'\x10' // length = 16
  data[166] = b'\x20' // control
  // data[167]: status (ignored)
  data[168] = b'\x01' // enable
  data[169] = b'\x04' // SM type = ProcessDataIn
  // End marker
  data[170] = b'\xFF'
  data[171] = b'\xFF'
  Bytes::makei(data.length(), fn(i) { data[i] })
}
