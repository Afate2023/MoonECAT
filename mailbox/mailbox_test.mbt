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
  inspect(@mailbox.FmmuDirection::Outputs, content="Outputs")
  inspect(@mailbox.FmmuDirection::Inputs, content="Inputs")
  inspect(@mailbox.FmmuDirection::MailboxState, content="MailboxState")
}

///|
test "parse_sii_preamble from fixed bytes" {
  let bytes = Bytes::from_array([
    b'\x80', b'\x0E', b'\x44', b'\xEE', b'\x10', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\xCB', b'\x00',
  ])
  let preamble = @mailbox.parse_sii_preamble(bytes)
  assert_eq(preamble.pdi_control, 0x0E80U)
  assert_eq(preamble.pdi_config, 0xEE44U)
  assert_eq(preamble.sync_impulse_length_raw, 0x0010U)
  assert_eq(preamble.sync_impulse_length_ns(), 160U)
  assert_eq(preamble.checksum, 0x00CBU)
  assert_true(preamble.checksum_ok)
}

///|
test "parse_sii_standard_metadata from fixed bytes" {
  let bytes = Bytes::makei(128, fn(i) {
    match i {
      124 => b'\x0F'
      125 => b'\x00'
      126 => b'\x01'
      127 => b'\x00'
      _ => b'\x00'
    }
  })
  let metadata = @mailbox.parse_sii_standard_metadata(bytes)
  assert_eq(metadata.eeprom_size_raw, 15U)
  assert_eq(metadata.eeprom_size_bytes(), 2048U)
  assert_eq(metadata.version, 1U)
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
  assert_eq(general.soe_channels, b'\x00')
}

///|
test "parse_sii_fmmu from fixture" {
  let eeprom = @fixtures.sample_sii_eeprom()
  let categories = @mailbox.parse_sii_categories(eeprom)
  let fmmu_data = categories[1].data
  let fmmu_dirs = @mailbox.parse_sii_fmmu(fmmu_data)
  assert_eq(fmmu_dirs.length(), 2)
  assert_eq(fmmu_dirs[0], @mailbox.FmmuDirection::Outputs)
  assert_eq(fmmu_dirs[1], @mailbox.FmmuDirection::Inputs)
}

///|
test "parse_sii_fmmu retains mailbox state entry" {
  let fmmu_dirs = @mailbox.parse_sii_fmmu(
    Bytes::from_array([b'\x01', b'\x02', b'\x03']),
  )
  assert_eq(fmmu_dirs.length(), 3)
  assert_eq(fmmu_dirs[2], @mailbox.FmmuDirection::MailboxState)
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
  assert_eq(sm_entries[0].status, b'\x00')
  assert_true(sm_entries[0].enable)
  assert_eq(sm_entries[1].physical_start, 0x1080U)
  assert_eq(sm_entries[1].sm_type, @mailbox.SmType::MailboxIn)
}

///|
test "parse_sii_dc decodes siitool layout" {
  let dc = @mailbox.parse_sii_dc(
    Bytes::from_array([
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
      b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x03', b'\x00', b'\x00',
      b'\x03', b'\x04', b'\x00', b'\x00', b'\x00', b'\x00',
    ]),
  )
  assert_eq(dc.assign_activate, 0x0300U)
  assert_eq(dc.name_idx, b'\x03')
  assert_eq(dc.description_idx, b'\x04')
}

///|
test "calculate_sm_configs uses sii header for mailbox" {
  let sii_header : @mailbox.SiiData = {
    vendor_id: 2U,
    product_code: 0U,
    revision: 0U,
    serial: 0U,
    bootstrap_rx_offset: 0U,
    bootstrap_rx_size: 0U,
    bootstrap_tx_offset: 0U,
    bootstrap_tx_size: 0U,
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
      status: b'\x00',
      enable: true,
      sm_type: @mailbox.SmType::MailboxOut,
    },
    {
      physical_start: 0U,
      length: 0U,
      control: b'\x22',
      status: b'\x00',
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
    @mailbox.FmmuDirection::Outputs,
    @mailbox.FmmuDirection::Inputs,
  ]
  let (fmmus, output_bytes, input_bytes) = @mailbox.calculate_fmmu_configs(
    fmmu_dirs, sm_configs, 0x00000000U,
  )
  assert_eq(fmmus.length(), 2)
  // FMMU0: Outputs -> maps to ProcessDataOut SM at 0x1100
  assert_eq(fmmus[0].physical_start, 0x1100U)
  assert_eq(fmmus[0].length, 32U)
  assert_eq(fmmus[0].logical_start, 0U)
  assert_eq(fmmus[0].direction, @mailbox.FmmuDirection::Outputs)
  // FMMU1: Inputs -> maps to ProcessDataIn SM at 0x1200
  assert_eq(fmmus[1].physical_start, 0x1200U)
  assert_eq(fmmus[1].length, 16U)
  assert_eq(fmmus[1].logical_start, 32U) // offset by previous 32 bytes
  assert_eq(fmmus[1].direction, @mailbox.FmmuDirection::Inputs)
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
    direction: @mailbox.FmmuDirection::Outputs,
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
  // Direction: Outputs = 0x02 (write access in ESC register)
  assert_eq(encoded[11], b'\x02')
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

///|
test "parse_sii_header identity consistency with fixture" {
  let eeprom = @fixtures.sample_sii_eeprom()
  let sii = @mailbox.parse_sii_header(eeprom)
  let expected = @fixtures.sample_ek1100_identity()
  // SII header identity should match the fixture identity
  assert_eq(sii.vendor_id, expected.vendor_id)
  assert_eq(sii.product_code, expected.product_code)
  assert_eq(sii.revision, expected.revision)
}

///|
test "parse_sii_categories empty EEPROM returns empty" {
  // 128 bytes of zeros - word 64 starts at byte 128 which doesn't exist
  let data = Bytes::new(128)
  let categories = @mailbox.parse_sii_categories(data)
  assert_eq(categories.length(), 0)
}

///|
test "parse_sii_general rejects short data" {
  let short = Bytes::new(4)
  let result = try? @mailbox.parse_sii_general(short)
  assert_true(result is Err(_))
}

///|
test "parse_sii_fmmu empty data" {
  let data = Bytes::new(0)
  let dirs = @mailbox.parse_sii_fmmu(data)
  assert_eq(dirs.length(), 0)
}

///|
test "parse_sii_sm empty data" {
  let data = Bytes::new(0)
  let entries = @mailbox.parse_sii_sm(data)
  assert_eq(entries.length(), 0)
}

///|
test "calculate_fmmu_configs with no FMMU directions" {
  let sm_configs : Array[@mailbox.SmConfig] = [
    {
      physical_start: 0x1100U,
      length: 32U,
      control: b'\x64',
      status: b'\x00',
      enable: true,
      sm_type: @mailbox.SmType::ProcessDataOut,
    },
  ]
  let (fmmus, out, inp) = @mailbox.calculate_fmmu_configs([], sm_configs, 0U)
  assert_eq(fmmus.length(), 0)
  assert_eq(out, 0)
  assert_eq(inp, 0)
}

///|
test "calculate_fmmu_configs with no matching SM" {
  // FMMU directions exist but no matching SM types
  let fmmu_dirs = [
    @mailbox.FmmuDirection::Outputs,
    @mailbox.FmmuDirection::Inputs,
  ]
  let (fmmus, out, inp) = @mailbox.calculate_fmmu_configs(fmmu_dirs, [], 0U)
  assert_eq(fmmus.length(), 0)
  assert_eq(out, 0)
  assert_eq(inp, 0)
}

///|
test "calculate_slave_mapping with PDO fixture - logical address chaining" {
  // Test that two slaves can have sequential logical addresses
  let eeprom = @fixtures.sample_sii_eeprom_with_pdo()
  let mapping1 = @mailbox.calculate_slave_mapping(eeprom, 0U)
  let next_base = (mapping1.output_bytes + mapping1.input_bytes).reinterpret_as_uint()
  let mapping2 = @mailbox.calculate_slave_mapping(eeprom, next_base)
  // Second slave's logical addresses should start after first slave's
  assert_eq(mapping2.fmmu_configs[0].logical_start, next_base)
  assert_true(mapping2.fmmu_configs[0].logical_start > 0U)
}

///|
test "SlaveMapping equality" {
  let eeprom = @fixtures.sample_sii_eeprom_with_pdo()
  let m1 = @mailbox.calculate_slave_mapping(eeprom, 0U)
  let m2 = @mailbox.calculate_slave_mapping(eeprom, 0U)
  assert_eq(m1, m2)
}

///|
test "SmConfig to_bytes length is always 8" {
  let configs : Array[@mailbox.SmConfig] = [
    {
      physical_start: 0U,
      length: 0U,
      control: b'\x00',
      status: b'\x00',
      enable: false,
      sm_type: @mailbox.SmType::Unused,
    },
    {
      physical_start: 0xFFFFU,
      length: 0xFFFFU,
      control: b'\xFF',
      status: b'\xFF',
      enable: true,
      sm_type: @mailbox.SmType::ProcessDataIn,
    },
  ]
  for cfg in configs {
    assert_eq(cfg.to_bytes().length(), 8)
  }
}

///|
test "FmmuConfig to_bytes length is always 16" {
  let fmmu : @mailbox.FmmuConfig = {
    logical_start: 0xFFFFFFFFU,
    length: 0xFFFFU,
    logical_start_bit: b'\x07',
    logical_end_bit: b'\x07',
    physical_start: 0xFFFFU,
    physical_start_bit: b'\x07',
    direction: @mailbox.FmmuDirection::Inputs,
    activate: true,
  }
  assert_eq(fmmu.to_bytes().length(), 16)
  // Direction Inputs = 0x01 (read access in ESC register)
  assert_eq(fmmu.to_bytes()[11], b'\x01')
}

// ========== CoE/SDO Engine Tests ==========

///|
test "MailboxHeader encode/decode roundtrip" {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: 0x1001U,
    channel: b'\x01',
    priority: b'\x02',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x05',
  }
  let encoded = mbh.to_bytes()
  assert_eq(encoded.length(), 6)
  let decoded = @mailbox.MailboxHeader::from_bytes(encoded)
  assert_eq(decoded.length, 10U)
  assert_eq(decoded.address, 0x1001U)
  assert_eq(decoded.channel, b'\x01')
  assert_eq(decoded.priority, b'\x02')
  assert_eq(decoded.mb_type, @mailbox.MailboxType::CoE)
  assert_eq(decoded.counter, b'\x05')
}

///|
test "MailboxHeader::from_bytes rejects short data" {
  let short = Bytes::new(3)
  let result = try? @mailbox.MailboxHeader::from_bytes(short)
  assert_true(result is Err(_))
}

///|
test "MailboxCounter cycles 1 through 15" {
  let ctr = @mailbox.MailboxCounter::new()
  let mut last = b'\x00'
  for _i = 0; _i < 30; _i = _i + 1 {
    let v = ctr.next()
    assert_true(v >= b'\x01' && v <= b'\x0F')
    last = v
  }
  // After 30 calls it should have wrapped at least once
  ignore(last)
}

///|
test "MailboxCounter never returns 0" {
  let ctr = @mailbox.MailboxCounter::new()
  for _i = 0; _i < 100; _i = _i + 1 {
    let v = ctr.next()
    assert_true(v != b'\x00')
  }
}

///|
test "SdoTransaction encode produces correct frame size" {
  let txn = @mailbox.build_sdo_download(
    b'\x01', 0x1001U, 0x6040U, b'\x00', b"\x06\x00\x00\x00",
  )
  let frame = txn.encode()
  // 6 (mbh) + 2 (coe) + 8 (sdo) = 16 bytes
  assert_eq(frame.length(), 16)
}

///|
test "SdoTransaction encode mailbox header fields" {
  let txn = @mailbox.build_sdo_download(
    b'\x03', 0x2002U, 0x6040U, b'\x01', b"\xFF\x00\x00\x00",
  )
  let frame = txn.encode()
  // Decode back the mailbox header
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::CoE)
  assert_eq(mbh.counter, b'\x03')
  assert_eq(mbh.address, 0x2002U)
  assert_eq(mbh.length, 10U) // 2 + 8
}

///|
test "SdoTransaction upload request encode" {
  let txn = @mailbox.build_sdo_upload(b'\x01', 0x1001U, 0x1018U, b'\x01')
  let frame = txn.encode()
  assert_eq(frame.length(), 16)
  // SDO command byte should be 0x40 (upload request)
  assert_eq(frame[8], b'\x40')
  // Index should be 0x1018 LE
  assert_eq(frame[9], b'\x18')
  assert_eq(frame[10], b'\x10')
  // Subindex
  assert_eq(frame[11], b'\x01')
}

///|
test "decode_sdo_response roundtrip with download response" {
  // Manually build a download response frame
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: 0x1001U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x01',
  }
  let hdr = mbh.to_bytes()
  // CoE header: SDO Response service (3) in bits [15:12]
  let coe_lo : Byte = b'\x00'
  let coe_hi : Byte = b'\x30' // 3 << 4 = 0x30
  // SDO: download response command = 0x60, index 0x6040, subindex 0x00
  let frame = Bytes::makei(16, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      coe_lo
    } else if i == 7 {
      coe_hi
    } else if i == 8 {
      b'\x60' // download response
    } else if i == 9 {
      b'\x40' // index lo
    } else if i == 10 {
      b'\x60' // index hi
    } else if i == 11 {
      b'\x00' // subindex
    } else {
      b'\x00'
    }
  })
  let (decoded_mbh, resp) = @mailbox.decode_sdo_response(frame)
  assert_eq(decoded_mbh.counter, b'\x01')
  assert_eq(resp.index, 0x6040U)
  assert_eq(resp.subindex, b'\x00')
  assert_eq(resp.command, @mailbox.SdoCommand::DownloadResponse)
  assert_true(not(resp.segmented))
}

///|
test "decode_sdo_response supports initiate segmented upload response" {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: 0x1001U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x01',
  }
  let hdr = mbh.to_bytes()
  let frame = Bytes::makei(16, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00'
    } else if i == 7 {
      b'\x30' // CoE SdoResponse
    } else if i == 8 {
      b'\x41' // upload response, non-expedited, size indicated
    } else if i == 9 {
      b'\x18' // index lo
    } else if i == 10 {
      b'\x10' // index hi
    } else if i == 11 {
      b'\x01' // subindex
    } else if i == 12 {
      b'\x08' // complete size = 8
    } else {
      b'\x00'
    }
  })
  let (_mbh, resp) = @mailbox.decode_sdo_response(frame)
  assert_eq(resp.command, @mailbox.SdoCommand::UploadResponse)
  assert_true(resp.segmented)
  assert_true(not(resp.last_segment))
  assert_true(resp.complete_size is Some(8U))
}

///|
test "decode_sdo_response supports upload segment response" {
  let mbh : @mailbox.MailboxHeader = {
    length: 6U,
    address: 0x1001U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x02',
  }
  let hdr = mbh.to_bytes()
  let frame = Bytes::makei(12, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00'
    } else if i == 7 {
      b'\x30' // CoE SdoResponse
    } else if i == 8 {
      b'\x19' // toggle=1, n=4, last=1 => 3 bytes payload
    } else if i == 9 {
      b'\xAA'
    } else if i == 10 {
      b'\xBB'
    } else if i == 11 {
      b'\xCC'
    } else {
      b'\x00'
    }
  })
  let (_mbh, resp) = @mailbox.decode_sdo_response(frame)
  assert_eq(resp.command, @mailbox.SdoCommand::UploadResponse)
  assert_true(resp.segmented)
  assert_true(resp.toggle)
  assert_true(resp.last_segment)
  assert_eq(resp.data, b"\xAA\xBB\xCC")
}

///|
test "decode_sdo_response detects abort" {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: 0x1001U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x01',
  }
  let hdr = mbh.to_bytes()
  // SDO abort frame
  let frame = Bytes::makei(16, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00'
    } else if i == 7 {
      b'\x20' // SDO Request service (2) << 4
    } else if i == 8 {
      b'\x80' // abort command
    } else if i == 12 {
      b'\x01' // abort code low byte
    } else if i == 13 {
      b'\x00'
    } else if i == 14 {
      b'\x00'
    } else if i == 15 {
      b'\x06' // 0x06000001 abort code
    } else {
      b'\x00'
    }
  })
  let result = try? @mailbox.decode_sdo_response(frame)
  assert_true(result is Err(@hal.EcError::SdoAbort(_)))
}

///|
test "decode_sdo_response rejects non-CoE mailbox" {
  // Build a frame with AoE mailbox type
  let frame = Bytes::makei(16, fn(i) {
    if i == 5 {
      b'\x11' // type=AoE(1), counter=1
    } else {
      b'\x00'
    }
  })
  let result = try? @mailbox.decode_sdo_response(frame)
  assert_true(result is Err(_))
}

///|
test "decode_sdo_response rejects short frame" {
  let short = Bytes::new(10)
  let result = try? @mailbox.decode_sdo_response(short)
  assert_true(result is Err(_))
}

///|
test "build_sdo_download creates correct request" {
  let txn = @mailbox.build_sdo_download(
    b'\x02', 0x1001U, 0x6040U, b'\x00', b"\x06\x00\x00\x00",
  )
  assert_eq(txn.counter, b'\x02')
  assert_eq(txn.station, 0x1001U)
  assert_eq(txn.request.index, 0x6040U)
  assert_eq(txn.request.subindex, b'\x00')
  assert_eq(txn.request.command, @mailbox.SdoCommand::DownloadRequest)
  assert_eq(txn.request.data.length(), 4)
}

///|
test "build_sdo_upload creates correct request" {
  let txn = @mailbox.build_sdo_upload(b'\x01', 0x1001U, 0x1018U, b'\x01')
  assert_eq(txn.request.command, @mailbox.SdoCommand::UploadRequest)
  assert_eq(txn.request.data.length(), 0)
  assert_eq(txn.request.complete_access, false)
}

///|
test "SdoTransaction encode sets complete access bit for download" {
  let txn = @mailbox.build_sdo_download_ca(
    b'\x02', 0x1001U, 0x1A00U, b'\x00', b"\x01\x02\x03\x04",
  )
  let frame = txn.encode()
  assert_eq(frame[8], b'\x31') // 0x21 | bit4
  assert_true(txn.request.complete_access)
}

///|
test "SdoTransaction encode sets complete access bit for upload" {
  let txn = @mailbox.build_sdo_upload_ca(b'\x03', 0x1001U, 0x1A00U, b'\x01')
  let frame = txn.encode()
  assert_eq(frame[8], b'\x50') // 0x40 | bit4
  assert_true(txn.request.complete_access)
}

///|
test "build_sdo_upload_segment_request encodes toggle bit" {
  let frame0 = @mailbox.build_sdo_upload_segment_request(
    b'\x02', 0x1001U, false,
  )
  let frame1 = @mailbox.build_sdo_upload_segment_request(b'\x03', 0x1001U, true)
  assert_eq(frame0.length(), 16)
  assert_eq(frame1.length(), 16)
  assert_eq(frame0[8], b'\x60')
  assert_eq(frame1[8], b'\x70')
}

///|
test "build_sdo_download_segment_request encodes segment header" {
  let frame = @mailbox.build_sdo_download_segment_request(
    b'\x06', 0x1001U, true, true, b"\xDE\xAD\xBE",
  )
  assert_eq(frame.length(), 12) // 6 + 2 + 1 + 3
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::CoE)
  assert_eq(mbh.length, 6U)
  // cmd: toggle=1, n_unused=4, last=1 -> 0x19
  assert_eq(frame[8], b'\x19')
  assert_eq(frame[9], b'\xDE')
  assert_eq(frame[10], b'\xAD')
  assert_eq(frame[11], b'\xBE')
}

///|
test "build_sdo_download_segment_request rejects payload over 7 bytes" {
  let result = try? @mailbox.build_sdo_download_segment_request(
    b'\x01', 0x1001U, false, false, b"\x00\x01\x02\x03\x04\x05\x06\x07",
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_response supports download segment response" {
  let mbh : @mailbox.MailboxHeader = {
    length: 3U,
    address: 0x1001U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x07',
  }
  let hdr = mbh.to_bytes()
  let frame = Bytes::makei(9, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00'
    } else if i == 7 {
      b'\x30' // CoE SdoResponse
    } else if i == 8 {
      b'\x30' // segmented download response, toggle=1
    } else {
      b'\x00'
    }
  })
  let (_mbh, resp) = @mailbox.decode_sdo_response(frame)
  assert_eq(resp.command, @mailbox.SdoCommand::DownloadResponse)
  assert_true(resp.segmented)
  assert_true(resp.toggle)
  assert_eq(resp.data.length(), 0)
}

///|
test "build_sdo_info_get_od_list_request encodes mailbox and opcode" {
  let frame = @mailbox.build_sdo_info_get_od_list_request(b'\x04', 0x1001U, 0U)
  assert_eq(frame.length(), 14) // 6 + 2 + 4 + 2
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::CoE)
  assert_eq(mbh.counter, b'\x04')
  assert_eq(mbh.length, 8U)
  assert_eq(frame[7], b'\x80') // CoE service=0x08 in high nibble
  assert_eq(frame[8], b'\x01') // opcode=Get OD List req
}

///|
test "build_sdo_info_get_od_request encodes index and opcode" {
  let frame = @mailbox.build_sdo_info_get_od_request(b'\x04', 0x1001U, 0x1C13U)
  assert_eq(frame.length(), 14)
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_eq(mbh.length, 8U)
  assert_eq(frame[8], b'\x03')
  assert_eq(frame[12], b'\x13')
  assert_eq(frame[13], b'\x1C')
}

///|
test "build_sdo_info_get_oe_request encodes subindex and value_info" {
  let frame = @mailbox.build_sdo_info_get_oe_request(
    b'\x05', 0x1001U, 0x1A00U, b'\x02', b'\x07',
  )
  assert_eq(frame.length(), 16)
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_eq(mbh.length, 10U)
  assert_eq(frame[8], b'\x05')
  assert_eq(frame[12], b'\x00')
  assert_eq(frame[13], b'\x1A')
  assert_eq(frame[14], b'\x02')
  assert_eq(frame[15], b'\x07')
}

///|
test "decode_sdo_info_response parses header and payload" {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U, // 2 + 4 + 4 payload
    address: 0x1001U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x05',
  }
  let hdr = mbh.to_bytes()
  let frame = Bytes::makei(16, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00'
    } else if i == 7 {
      b'\x80' // SDO Info service
    } else if i == 8 {
      b'\x82' // opcode=0x02, incomplete=1
    } else if i == 9 {
      b'\x00'
    } else if i == 10 {
      b'\x03' // fragments_left = 3
    } else if i == 11 {
      b'\x00'
    } else if i == 12 {
      b'\x11'
    } else if i == 13 {
      b'\x22'
    } else if i == 14 {
      b'\x33'
    } else if i == 15 {
      b'\x44'
    } else {
      b'\x00'
    }
  })
  let (_mbh, info) = @mailbox.decode_sdo_info_response(frame)
  assert_eq(info.opcode, b'\x02')
  assert_true(info.incomplete)
  assert_eq(info.fragments_left, 3U)
  assert_eq(info.payload, b"\x11\x22\x33\x44")
}

///|
test "decode_sdo_info_od_list_payload parses little-endian indices" {
  let indices = @mailbox.decode_sdo_info_od_list_payload(
    b"\x00\x10\x13\x1C\x00\x1A",
  )
  assert_eq(indices.length(), 3)
  assert_eq(indices[0], 0x1000U)
  assert_eq(indices[1], 0x1C13U)
  assert_eq(indices[2], 0x1A00U)
}

///|
test "decode_sdo_info_od_description_payload parses fixed fields and name" {
  let desc = @mailbox.decode_sdo_info_od_description_payload(
    b"\x13\x1C\x07\x00\x03\x09MapPDO",
  )
  assert_eq(desc.index, 0x1C13U)
  assert_eq(desc.data_type, 0x0007U)
  assert_eq(desc.max_subindex, b'\x03')
  assert_eq(desc.object_code, b'\x09')
  assert_eq(desc.name, "MapPDO")
}

///|
test "decode_sdo_info_oe_description_payload parses fields and name" {
  let entry = @mailbox.decode_sdo_info_oe_description_payload(
    b"\x00\x1A\x02\x07\x05\x00\x10\x00\x3F\x00Entry2",
  )
  assert_eq(entry.index, 0x1A00U)
  assert_eq(entry.subindex, b'\x02')
  assert_eq(entry.value_info, b'\x07')
  assert_eq(entry.data_type, 0x0005U)
  assert_eq(entry.bit_length, 0x0010U)
  assert_eq(entry.access, 0x003FU)
  assert_eq(entry.name, "Entry2")
}

// ========== MailboxConfig Tests ==========

///|
test "MailboxConfig::from_sii extracts SM addresses" {
  let sii : @mailbox.SiiData = {
    vendor_id: 0x02U,
    product_code: 0x044C2C52U,
    revision: 0x120000U,
    serial: 0U,
    bootstrap_rx_offset: 0U,
    bootstrap_rx_size: 0U,
    bootstrap_tx_offset: 0U,
    bootstrap_tx_size: 0U,
    mailbox_rx_offset: 0x1000U,
    mailbox_rx_size: 128U,
    mailbox_tx_offset: 0x1080U,
    mailbox_tx_size: 128U,
    mailbox_protocols: 0x0CU,
  }
  let cfg = @mailbox.MailboxConfig::from_sii(sii)
  assert_eq(cfg.out_address, 0x1000U)
  assert_eq(cfg.out_size, 128U)
  assert_eq(cfg.out_sm_index, 0)
  assert_eq(cfg.in_address, 0x1080U)
  assert_eq(cfg.in_size, 128U)
  assert_eq(cfg.in_sm_index, 1)
}

///|
test "MailboxConfig::is_valid returns true for non-zero sizes" {
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0x1000U,
    out_size: 128U,
    out_sm_index: 0,
    in_address: 0x1080U,
    in_size: 128U,
    in_sm_index: 1,
  }
  assert_true(cfg.is_valid())
}

///|
test "MailboxConfig::is_valid returns false for zero sizes" {
  let cfg : @mailbox.MailboxConfig = {
    out_address: 0U,
    out_size: 0U,
    out_sm_index: 0,
    in_address: 0U,
    in_size: 0U,
    in_sm_index: 1,
  }
  assert_true(not(cfg.is_valid()))
}

// ========== RMSM Tests ==========

///|
test "Rmsm new starts in Idle" {
  let rmsm = @mailbox.Rmsm::new()
  assert_true(rmsm.is_idle())
  assert_eq(rmsm.current_counter(), b'\x00')
}

///|
test "Rmsm begin_transaction transitions to WaitingForResponse" {
  let rmsm = @mailbox.Rmsm::new()
  let cnt = rmsm.begin_transaction()
  assert_true(cnt >= b'\x01' && cnt <= b'\x0F')
  assert_true(not(rmsm.is_idle()))
}

///|
test "Rmsm begin_transaction fails when not Idle" {
  let rmsm = @mailbox.Rmsm::new()
  let _ = rmsm.begin_transaction()
  let result = try? rmsm.begin_transaction()
  assert_true(result is Err(_))
}

///|
test "Rmsm validate_response succeeds with matching counter" {
  let rmsm = @mailbox.Rmsm::new()
  let cnt = rmsm.begin_transaction()
  let valid = rmsm.validate_response(cnt)
  assert_true(valid)
  assert_true(rmsm.is_idle())
}

///|
test "Rmsm validate_response accepts counter 0 (slave doesn't support)" {
  let rmsm = @mailbox.Rmsm::new()
  let _ = rmsm.begin_transaction()
  let valid = rmsm.validate_response(b'\x00')
  assert_true(valid)
  assert_true(rmsm.is_idle())
}

///|
test "Rmsm validate_response detects counter mismatch" {
  let rmsm = @mailbox.Rmsm::new()
  let cnt = rmsm.begin_transaction()
  let wrong_cnt = if cnt == b'\x0F' { b'\x01' } else { cnt + b'\x01' }
  let result = try? rmsm.validate_response(wrong_cnt)
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

///|
test "Rmsm validate_response detects repeat frame" {
  let rmsm = @mailbox.Rmsm::new()
  // First transaction: succeed
  let cnt1 = rmsm.begin_transaction()
  let _ = rmsm.validate_response(cnt1)
  // Second transaction: same counter should be a repeat
  let cnt2 = rmsm.begin_transaction()
  ignore(cnt2)
  let is_new = rmsm.validate_response(cnt1)
  assert_true(not(is_new)) // Repeat detected
}

///|
test "Rmsm record_timeout allows retries up to max" {
  let rmsm = @mailbox.Rmsm::new(max_retries=2)
  let _ = rmsm.begin_transaction()
  assert_true(rmsm.record_timeout())
  assert_true(rmsm.record_timeout())
  assert_true(not(rmsm.record_timeout())) // Third retry exceeds max
}

///|
test "Rmsm reset returns to Idle" {
  let rmsm = @mailbox.Rmsm::new()
  let _ = rmsm.begin_transaction()
  rmsm.reset()
  assert_true(rmsm.is_idle())
}

// ========== Emergency Message Tests ==========

///|
test "decode_emergency parses valid payload" {
  // error_code = 0x1234, error_register = 0xAB, data = [01,02,03,04,05]
  let payload = Bytes::from_array([
    b'\x34', b'\x12', b'\xAB', b'\x01', b'\x02', b'\x03', b'\x04', b'\x05',
  ])
  let emg = @mailbox.decode_emergency(payload)
  assert_eq(emg.error_code, 0x1234U)
  assert_eq(emg.error_register, b'\xAB')
  assert_eq(emg.data[0], b'\x01')
  assert_eq(emg.data[4], b'\x05')
}

///|
test "decode_emergency rejects short payload" {
  let short = Bytes::new(5)
  let result = try? @mailbox.decode_emergency(short)
  assert_true(result is Err(_))
}

///|
test "decode_emergency_frame parses valid frame" {
  // Build: mbh (6) + CoE hdr emergency (2) + emergency payload (8) = 16 bytes
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: 0x1001U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x03',
  }
  let hdr = mbh.to_bytes()
  // CoE header: service type = 1 (Emergency) in bits [15:12] → high byte = 0x10
  let frame = Bytes::makei(16, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00' // CoE lo
    } else if i == 7 {
      b'\x10' // CoE hi: service type 1 << 4
    } else if i == 8 {
      b'\x78' // error code lo
    } else if i == 9 {
      b'\x56' // error code hi
    } else if i == 10 {
      b'\xAA' // error register
    } else {
      b'\x00' // data
    }
  })
  let (decoded_mbh, emg) = @mailbox.decode_emergency_frame(frame)
  assert_eq(decoded_mbh.counter, b'\x03')
  assert_eq(emg.error_code, 0x5678U)
  assert_eq(emg.error_register, b'\xAA')
}

///|
test "decode_emergency_frame rejects non-CoE" {
  // Build a frame with AoE mailbox type
  let frame = Bytes::makei(16, fn(i) {
    if i == 5 {
      b'\x11' // type = AoE(1), counter=1
    } else {
      b'\x00'
    }
  })
  let result = try? @mailbox.decode_emergency_frame(frame)
  assert_true(result is Err(_))
}

///|
test "decode_emergency_frame rejects wrong CoE service type" {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: 0U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x01',
  }
  let hdr = mbh.to_bytes()
  // CoE header: service type = 3 (SDO Response, not Emergency)
  let frame = Bytes::makei(16, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 7 {
      b'\x30' // service type 3 << 4
    } else {
      b'\x00'
    }
  })
  let result = try? @mailbox.decode_emergency_frame(frame)
  assert_true(result is Err(_))
}

// ========== SiiGeneral Flags Tests ==========

///|
test "SiiGeneral::is_op_only detects flag bit 0" {
  let gen : @mailbox.SiiGeneral = {
    group_idx: b'\x00',
    image_idx: b'\x00',
    order_idx: b'\x00',
    name_idx: b'\x00',
    coe_details: b'\x00',
    foe_supported: false,
    eoe_supported: false,
    soe_supported: false,
    soe_channels: b'\x00',
    ds402_channels: b'\x00',
    sysman_class: b'\x00',
    flags: b'\x01', // bit 0 set = OpOnly
    current_on_ebus: 0U,
    physical_port_0: b'\x00',
    physical_port_1: b'\x00',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  }
  assert_true(gen.is_op_only())
  assert_true(not(gen.prefers_not_lrw()))
  assert_true(not(gen.supports_identification_ado()))
}

///|
test "SiiGeneral::prefers_not_lrw detects flag bit 1" {
  let gen : @mailbox.SiiGeneral = {
    group_idx: b'\x00',
    image_idx: b'\x00',
    order_idx: b'\x00',
    name_idx: b'\x00',
    coe_details: b'\x00',
    foe_supported: false,
    eoe_supported: false,
    soe_supported: false,
    soe_channels: b'\x00',
    ds402_channels: b'\x00',
    sysman_class: b'\x00',
    flags: b'\x02', // bit 1 set = NotLRW
    current_on_ebus: 0U,
    physical_port_0: b'\x00',
    physical_port_1: b'\x00',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  }
  assert_true(not(gen.is_op_only()))
  assert_true(gen.prefers_not_lrw())
}

///|
test "SiiGeneral::supports_identification_ado detects flag bit 3" {
  let gen : @mailbox.SiiGeneral = {
    group_idx: b'\x00',
    image_idx: b'\x00',
    order_idx: b'\x00',
    name_idx: b'\x00',
    coe_details: b'\x00',
    foe_supported: false,
    eoe_supported: false,
    soe_supported: false,
    soe_channels: b'\x00',
    ds402_channels: b'\x00',
    sysman_class: b'\x00',
    flags: b'\x08', // bit 3 set = IdentificationAdo
    current_on_ebus: 0U,
    physical_port_0: b'\x00',
    physical_port_1: b'\x00',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  }
  assert_true(gen.supports_identification_ado())
}

///|
test "SiiGeneral all flags clear" {
  let gen : @mailbox.SiiGeneral = {
    group_idx: b'\x00',
    image_idx: b'\x00',
    order_idx: b'\x00',
    name_idx: b'\x00',
    coe_details: b'\x00',
    foe_supported: false,
    eoe_supported: false,
    soe_supported: false,
    soe_channels: b'\x00',
    ds402_channels: b'\x00',
    sysman_class: b'\x00',
    flags: b'\x00',
    current_on_ebus: 0U,
    physical_port_0: b'\x00',
    physical_port_1: b'\x00',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  }
  assert_true(not(gen.is_op_only()))
  assert_true(not(gen.prefers_not_lrw()))
  assert_true(not(gen.supports_identification_ado()))
}
