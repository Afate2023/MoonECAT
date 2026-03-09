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
