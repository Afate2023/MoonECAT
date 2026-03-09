///|
test "MailboxType display" {
  inspect(@mailbox.MailboxType::CoE, content="CoE")
  inspect(@mailbox.MailboxType::SoE, content="SoE")
}

///|
test "SiiCategory display" {
  inspect(@mailbox.SiiCategory::General, content="General")
  inspect(@mailbox.SiiCategory::TxPdo, content="TxPdo")
}

///|
test "FmmuDirection display" {
  inspect(@mailbox.FmmuDirection::Read, content="Read")
  inspect(@mailbox.FmmuDirection::Write, content="Write")
}

///|
test "SmType display" {
  inspect(@mailbox.SmType::ProcessDataIn, content="ProcessDataIn")
  inspect(@mailbox.SmType::MailboxOut, content="MailboxOut")
}

///|
test "SdoCommand display" {
  inspect(@mailbox.SdoCommand::UploadRequest, content="UploadRequest")
  inspect(@mailbox.SdoCommand::DownloadResponse, content="DownloadResponse")
}

///|
test "parse_sii_header from fixture" {
  let eeprom = @fixtures.sample_sii_eeprom()
  let sii = @mailbox.parse_sii_header(eeprom)
  assert_eq(sii.vendor_id, 0x2U) // Beckhoff
  assert_eq(sii.product_code, 0x044C2C52U)
  assert_eq(sii.revision, 0x00110000U)
  assert_eq(sii.serial, 0U)
  assert_eq(sii.mailbox_rx_offset, 0x1000U)
  assert_eq(sii.mailbox_rx_size, 128U)
  assert_eq(sii.mailbox_tx_offset, 0x1080U)
  assert_eq(sii.mailbox_tx_size, 128U)
  assert_eq(sii.mailbox_protocols, 0x000CU) // CoE + FoE
}

///|
test "parse_sii_header rejects short data" {
  let short = Bytes::new(10)
  let result = try? @mailbox.parse_sii_header(short)
  assert_true(result is Err(_))
}

///|
test "parse_sii_categories from fixture" {
  let eeprom = @fixtures.sample_sii_eeprom()
  let categories = @mailbox.parse_sii_categories(eeprom)
  // Should find: General, FMMU, SM (3 categories)
  assert_eq(categories.length(), 3)
  assert_eq(categories[0].category, @mailbox.SiiCategory::General)
  assert_eq(categories[1].category, @mailbox.SiiCategory::Fmmu)
  assert_eq(categories[2].category, @mailbox.SiiCategory::SyncManager)
}

///|
test "parse_sii_general from fixture" {
  let eeprom = @fixtures.sample_sii_eeprom()
  let categories = @mailbox.parse_sii_categories(eeprom)
  let general_data = categories[0].data
  let general = @mailbox.parse_sii_general(general_data)
  assert_eq(general.group_idx, b'\x01')
  assert_eq(general.image_idx, b'\x02')
  assert_eq(general.order_idx, b'\x03')
  assert_eq(general.name_idx, b'\x04')
  assert_true(general.foe_supported)
  assert_true(general.eoe_supported)
}

///|
test "parse_sii_fmmu from fixture" {
  let eeprom = @fixtures.sample_sii_eeprom()
  let categories = @mailbox.parse_sii_categories(eeprom)
  let fmmu_data = categories[1].data
  let fmmu_dirs = @mailbox.parse_sii_fmmu(fmmu_data)
  assert_eq(fmmu_dirs.length(), 2)
  assert_eq(fmmu_dirs[0], @mailbox.FmmuDirection::Read)
  assert_eq(fmmu_dirs[1], @mailbox.FmmuDirection::Write)
}

///|
test "parse_sii_sm from fixture" {
  let eeprom = @fixtures.sample_sii_eeprom()
  let categories = @mailbox.parse_sii_categories(eeprom)
  let sm_data = categories[2].data
  let sm_entries = @mailbox.parse_sii_sm(sm_data)
  assert_eq(sm_entries.length(), 2)
  assert_eq(sm_entries[0].physical_start, 0x1000U)
  assert_eq(sm_entries[0].length, 128U)
  assert_eq(sm_entries[0].sm_type, @mailbox.SmType::MailboxOut)
  assert_true(sm_entries[0].enable)
  assert_eq(sm_entries[1].physical_start, 0x1080U)
  assert_eq(sm_entries[1].sm_type, @mailbox.SmType::MailboxIn)
}

///|
test "calculate_sm_configs uses sii header for mailbox" {
  let sii_header : @mailbox.SiiData = {
    vendor_id: 2U,
    product_code: 0U,
    revision: 0U,
    serial: 0U,
    mailbox_rx_offset: 0x1000U,
    mailbox_rx_size: 128U,
    mailbox_tx_offset: 0x1080U,
    mailbox_tx_size: 128U,
    mailbox_protocols: 0xCU,
  }
  let sm_entries : Array[@mailbox.SiiSmEntry] = [
    {
      physical_start: 0U,
      length: 0U,
      control: b'\x26',
      enable: true,
      sm_type: @mailbox.SmType::MailboxOut,
    },
    {
      physical_start: 0U,
      length: 0U,
      control: b'\x22',
      enable: true,
      sm_type: @mailbox.SmType::MailboxIn,
    },
  ]
  let configs = @mailbox.calculate_sm_configs(sii_header, sm_entries)
  assert_eq(configs.length(), 2)
  // Mailbox SM should use header offsets, not the SII SM entry values
  assert_eq(configs[0].physical_start, 0x1000U)
  assert_eq(configs[0].length, 128U)
  assert_eq(configs[1].physical_start, 0x1080U)
  assert_eq(configs[1].length, 128U)
}

///|
test "calculate_fmmu_configs maps process data" {
  let sm_configs : Array[@mailbox.SmConfig] = [
    {
      physical_start: 0x1000U,
      length: 128U,
      control: b'\x26',
      status: b'\x00',
      enable: true,
      sm_type: @mailbox.SmType::MailboxOut,
    },
    {
      physical_start: 0x1080U,
      length: 128U,
      control: b'\x22',
      status: b'\x00',
      enable: true,
      sm_type: @mailbox.SmType::MailboxIn,
    },
    {
      physical_start: 0x1100U,
      length: 32U,
      control: b'\x64',
      status: b'\x00',
      enable: true,
      sm_type: @mailbox.SmType::ProcessDataOut,
    },
    {
      physical_start: 0x1200U,
      length: 16U,
      control: b'\x20',
      status: b'\x00',
      enable: true,
      sm_type: @mailbox.SmType::ProcessDataIn,
    },
  ]
  let fmmu_dirs : Array[@mailbox.FmmuDirection] = [
    @mailbox.FmmuDirection::Read,
    @mailbox.FmmuDirection::Write,
  ]
  let (fmmus, output_bytes, input_bytes) = @mailbox.calculate_fmmu_configs(
    fmmu_dirs, sm_configs, 0x00000000U,
  )
  assert_eq(fmmus.length(), 2)
  // FMMU0: Read -> maps to ProcessDataOut SM at 0x1100
  assert_eq(fmmus[0].physical_start, 0x1100U)
  assert_eq(fmmus[0].length, 32U)
  assert_eq(fmmus[0].logical_start, 0U)
  assert_eq(fmmus[0].direction, @mailbox.FmmuDirection::Read)
  // FMMU1: Write -> maps to ProcessDataIn SM at 0x1200
  assert_eq(fmmus[1].physical_start, 0x1200U)
  assert_eq(fmmus[1].length, 16U)
  assert_eq(fmmus[1].logical_start, 32U) // offset by previous 32 bytes
  assert_eq(fmmus[1].direction, @mailbox.FmmuDirection::Write)
  assert_eq(output_bytes, 32)
  assert_eq(input_bytes, 16)
}

///|
test "calculate_slave_mapping end-to-end" {
  let eeprom = @fixtures.sample_sii_eeprom_with_pdo()
  let mapping = @mailbox.calculate_slave_mapping(eeprom, 0x10000U)
  assert_eq(mapping.sm_configs.length(), 4)
  assert_eq(mapping.fmmu_configs.length(), 2)
  assert_eq(mapping.output_bytes, 32)
  assert_eq(mapping.input_bytes, 16)
  // First FMMU should start at logical base
  assert_eq(mapping.fmmu_configs[0].logical_start, 0x10000U)
  // Second FMMU starts after first
  assert_eq(mapping.fmmu_configs[1].logical_start, 0x10020U) // 0x10000 + 32
}

///|
test "SmConfig to_bytes roundtrip" {
  let sm : @mailbox.SmConfig = {
    physical_start: 0x1000U,
    length: 128U,
    control: b'\x26',
    status: b'\x00',
    enable: true,
    sm_type: @mailbox.SmType::MailboxOut,
  }
  let encoded = sm.to_bytes()
  assert_eq(encoded.length(), 8)
  // Physical start LE: 0x00, 0x10
  assert_eq(encoded[0], b'\x00')
  assert_eq(encoded[1], b'\x10')
  // Length LE: 0x80, 0x00
  assert_eq(encoded[2], b'\x80')
  assert_eq(encoded[3], b'\x00')
  // Control
  assert_eq(encoded[4], b'\x26')
  // Enable
  assert_eq(encoded[6], b'\x01')
}

///|
test "FmmuConfig to_bytes roundtrip" {
  let fmmu : @mailbox.FmmuConfig = {
    logical_start: 0x00010000U,
    length: 32U,
    logical_start_bit: b'\x00',
    logical_end_bit: b'\x07',
    physical_start: 0x1100U,
    physical_start_bit: b'\x00',
    direction: @mailbox.FmmuDirection::Read,
    activate: true,
  }
  let encoded = fmmu.to_bytes()
  assert_eq(encoded.length(), 16)
  // Logical start LE: 0x00, 0x00, 0x01, 0x00
  assert_eq(encoded[0], b'\x00')
  assert_eq(encoded[1], b'\x00')
  assert_eq(encoded[2], b'\x01')
  assert_eq(encoded[3], b'\x00')
  // Length LE: 0x20, 0x00
  assert_eq(encoded[4], b'\x20')
  assert_eq(encoded[5], b'\x00')
  // Physical start LE: 0x00, 0x11
  assert_eq(encoded[8], b'\x00')
  assert_eq(encoded[9], b'\x11')
  // Direction: Read = 0x01
  assert_eq(encoded[11], b'\x01')
  // Activate
  assert_eq(encoded[12], b'\x01')
}

///|
test "calculate_slave_mapping mailbox-only slave" {
  // The basic fixture has only mailbox SMs, no process data SMs
  let eeprom = @fixtures.sample_sii_eeprom()
  let mapping = @mailbox.calculate_slave_mapping(eeprom, 0U)
  assert_eq(mapping.sm_configs.length(), 2)
  // FMMU should fall back to mailbox SMs
  assert_eq(mapping.fmmu_configs.length(), 2)
  assert_eq(mapping.output_bytes, 0) // mailbox doesn't count as PDO
  assert_eq(mapping.input_bytes, 0)
}
