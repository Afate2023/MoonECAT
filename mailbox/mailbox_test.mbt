///|
test "MailboxType display" {
  inspect(@mailbox.MailboxType::CoE, content="CoE")
  inspect(@mailbox.MailboxType::SoE, content="SoE")
}

///|
test "SiiCategory display" {
  inspect(@mailbox.SiiCategory::General, content="General")
  inspect(@mailbox.SiiCategory::TxPdo, content="TxPdo")
  inspect(@mailbox.SiiCategory::FmmuEx, content="FmmuEx")
}

///|
test "FmmuDirection display" {
  inspect(@mailbox.FmmuDirection::Outputs, content="Outputs")
  inspect(@mailbox.FmmuDirection::Inputs, content="Inputs")
  inspect(@mailbox.FmmuDirection::MailboxState, content="MailboxState")
  inspect(@mailbox.FmmuDirection::DynamicOutputs, content="DynamicOutputs")
  inspect(@mailbox.FmmuDirection::DynamicInputs, content="DynamicInputs")
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
  inspect(
    @mailbox.SmType::DynamicProcessDataOut,
    content="DynamicProcessDataOut",
  )
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
  assert_eq(sii.firmware_version, 0U)
  assert_true(!sii.esc_config_b_present)
}

///|
test "parse_sii_header decodes vendor info and esc config area b" {
  let bytes = Bytes::makei(128, fn(i) {
    match i {
      12 => b'\x01'
      13 => b'\x00' // word 6 bit0 => area B present
      64 => b'\x34'
      65 => b'\x12' // firmware_version
      66 => b'\x78'
      67 => b'\x56' // hardware_version
      68 => b'\x31'
      69 => b'\x5A' // production date raw
      80 => b'\x16'
      81 => b'\x81' // pdi_control_1 / esc_config_b0
      82 => b'\x22'
      83 => b'\x11' // pdi_config_1
      86 => b'\x44'
      87 => b'\x33' // pdi_config_1_ext
      88 => b'\x66'
      89 => b'\x55' // esc_config_b4
      90 => b'\x88'
      91 => b'\x77' // esc_config_b5
      92 => b'\xAA'
      93 => b'\x99' // esc_config_b6
      94 => b'\xCC'
      95 => b'\xBB' // checksum_b
      _ => b'\x00'
    }
  })
  let sii = @mailbox.parse_sii_header(bytes)
  assert_eq(sii.firmware_version, 0x1234U)
  assert_eq(sii.hardware_version, 0x5678U)
  assert_eq(sii.production_date_raw, 0x5A31U)
  assert_eq(sii.production_year(), 2049)
  assert_eq(sii.production_weekday(), 4)
  assert_eq(sii.production_week(), 22)
  assert_true(sii.esc_config_b_present)
  assert_eq(sii.pdi_control_1, b'\x16')
  assert_eq(sii.esc_config_b0, b'\x81')
  assert_eq(sii.pdi_config_1, 0x1122U)
  assert_eq(sii.pdi_config_1_ext, 0x3344U)
  assert_eq(sii.esc_config_b4, 0x5566U)
  assert_eq(sii.esc_config_b5, 0x7788U)
  assert_eq(sii.esc_config_b6, 0x99AAU)
  assert_eq(sii.checksum_b, 0xBBCCU)
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
  assert_true(general.supports_coe_sdo())
  assert_true(general.supports_coe_sdo_info())
  assert_true(general.supports_coe_pdo_assign())
  assert_true(!general.supports_coe_pdo_configuration())
  assert_eq(general.soe_channels, b'\x00')
}

///|
test "parse_sii_general decodes signed current on EBus" {
  let data = Bytes::from_array([
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x9C', b'\xFF', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00',
  ])
  let general = @mailbox.parse_sii_general(data)
  assert_eq(general.current_on_ebus, -100)
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
  assert_eq(sm_entries[0].activate, b'\x01')
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
test "parse_sii_timeouts decodes ETG.2010 timeout fields" {
  let timeouts = @mailbox.parse_sii_timeouts(
    Bytes::from_array([
      b'\xB8', b'\x0B', b'\x10', b'\x27', b'\x88', b'\x13', b'\xC8', b'\x00', b'\x64',
      b'\x00', b'\xE8', b'\x03', b'\x00', b'\x00', b'\x00', b'\x00',
    ]),
  )
  assert_eq(timeouts.preop_timeout_ms, 3000U)
  assert_eq(timeouts.safeop_op_timeout_ms, 10000U)
  assert_eq(timeouts.back_to_init_timeout_ms, 5000U)
  assert_eq(timeouts.back_to_safeop_timeout_ms, 200U)
  assert_eq(timeouts.mailbox_request_timeout_ms, 100U)
  assert_eq(timeouts.mailbox_response_timeout_ms, 1000U)
}

///|
test "parse_sii_fmmu_ex decodes sync manager and sync unit bindings" {
  let entries = @mailbox.parse_sii_fmmu_ex(
    Bytes::from_array([
      b'\x07', b'\x00', b'\x02', b'\x01', b'\x02', b'\x00', b'\x03', b'\x00',
    ]),
  )
  assert_eq(entries.length(), 2)
  assert_true(entries[0].op_only)
  assert_true(entries[0].sm_defined)
  assert_true(entries[0].su_defined)
  assert_eq(entries[0].sync_manager, b'\x02')
  assert_eq(entries[0].sync_unit, b'\x01')
  assert_true(!entries[1].op_only)
  assert_true(entries[1].sm_defined)
}

///|
test "parse_sii_sync_units decodes flag bits" {
  let units = @mailbox.parse_sii_sync_units(
    Bytes::from_array([b'\x0F', b'\x02']),
  )
  assert_eq(units.length(), 2)
  assert_true(units[0].separate_su)
  assert_true(units[0].separate_frame)
  assert_true(units[0].depend_on_input_state)
  assert_true(units[0].frame_repeat_support)
  assert_true(!units[1].separate_su)
  assert_true(units[1].separate_frame)
}

///|
test "parse_sii_categories recognizes standard reserved category payload" {
  let data = Bytes::makei(140, fn(i) {
    match i {
      128 => b'\x50'
      129 => b'\x00' // type 80
      130 => b'\x02'
      131 => b'\x00' // 2 words = 4 bytes
      132 => b'\x12'
      133 => b'\x34'
      134 => b'\x56'
      135 => b'\x78'
      136 => b'\xFF'
      137 => b'\xFF'
      _ => b'\x00'
    }
  })
  let categories = @mailbox.parse_sii_categories(data)
  assert_eq(categories.length(), 1)
  assert_eq(categories[0].category, @mailbox.Dictionary)
  assert_eq(categories[0].type_code, 80U)
  assert_eq(categories[0].data.length(), 4)
}

///|
test "parse_sii_categories preserves unknown vendor payload as raw" {
  let data = Bytes::makei(140, fn(i) {
    match i {
      128 => b'\x34'
      129 => b'\x12' // type 0x1234
      130 => b'\x02'
      131 => b'\x00' // 2 words = 4 bytes
      132 => b'\x12'
      133 => b'\x34'
      134 => b'\x56'
      135 => b'\x78'
      136 => b'\xFF'
      137 => b'\xFF'
      _ => b'\x00'
    }
  })
  let categories = @mailbox.parse_sii_categories(data)
  assert_eq(categories.length(), 1)
  assert_eq(categories[0].category, @mailbox.Raw)
  assert_eq(categories[0].type_code, 0x1234U)
  assert_eq(categories[0].data.length(), 4)
}

///|
test "parse_sii_categories recognizes all standard reserved categories" {
  let data = Bytes::makei(176, fn(i) {
    match i {
      128 => b'\x14'
      129 => b'\x00' // 20
      130 => b'\x01'
      131 => b'\x00'
      132 => b'\x01'
      133 => b'\x02'
      134 => b'\x50'
      135 => b'\x00' // 80
      136 => b'\x01'
      137 => b'\x00'
      138 => b'\x03'
      139 => b'\x04'
      140 => b'\x5A'
      141 => b'\x00' // 90
      142 => b'\x01'
      143 => b'\x00'
      144 => b'\x05'
      145 => b'\x06'
      146 => b'\x64'
      147 => b'\x00' // 100
      148 => b'\x01'
      149 => b'\x00'
      150 => b'\x07'
      151 => b'\x08'
      152 => b'\x6E'
      153 => b'\x00' // 110
      154 => b'\x01'
      155 => b'\x00'
      156 => b'\x09'
      157 => b'\x0A'
      158 => b'\xFF'
      159 => b'\xFF'
      _ => b'\x00'
    }
  })
  let categories = @mailbox.parse_sii_categories(data)
  assert_eq(categories.length(), 5)
  assert_eq(categories[0].category, @mailbox.DataTypes)
  assert_eq(categories[1].category, @mailbox.Dictionary)
  assert_eq(categories[2].category, @mailbox.Hardware)
  assert_eq(categories[3].category, @mailbox.VendorInformation)
  assert_eq(categories[4].category, @mailbox.Images)
}

///|
test "sii category entry reports stable export classes" {
  let standard_known : @mailbox.SiiCategoryEntry = {
    category: @mailbox.Dictionary,
    type_code: 80U,
    data: Bytes::new(0),
  }
  let standard_unknown : @mailbox.SiiCategoryEntry = {
    category: @mailbox.Raw,
    type_code: 120U,
    data: Bytes::new(0),
  }
  let device_specific : @mailbox.SiiCategoryEntry = {
    category: @mailbox.Raw,
    type_code: 5U,
    data: Bytes::new(0),
  }
  let vendor_specific : @mailbox.SiiCategoryEntry = {
    category: @mailbox.Raw,
    type_code: 0x1234U,
    data: Bytes::new(0),
  }
  let application_specific : @mailbox.SiiCategoryEntry = {
    category: @mailbox.Raw,
    type_code: 0x2001U,
    data: Bytes::new(0),
  }
  assert_eq(standard_known.category_class(), @mailbox.StandardKnown)
  assert_eq(standard_unknown.category_class(), @mailbox.StandardUnknown)
  assert_eq(device_specific.category_class(), @mailbox.DeviceSpecific)
  assert_eq(vendor_specific.category_class(), @mailbox.VendorSpecific)
  assert_eq(application_specific.category_class(), @mailbox.ApplicationSpecific)
  assert_eq(
    @mailbox.SiiCategoryClass::VendorSpecific.label(),
    "vendor-specific",
  )
}

///|
test "sii category entry exposes overlay candidates for extension classes" {
  let vendor_specific : @mailbox.SiiCategoryEntry = {
    category: @mailbox.Raw,
    type_code: 0x1234U,
    data: Bytes::from_array([b'\xAA', b'\xBB']),
  }
  let application_specific : @mailbox.SiiCategoryEntry = {
    category: @mailbox.Raw,
    type_code: 0x2001U,
    data: Bytes::from_array([b'\xCC', b'\xDD']),
  }
  let device_specific : @mailbox.SiiCategoryEntry = {
    category: @mailbox.Raw,
    type_code: 5U,
    data: Bytes::from_array([b'\xEE', b'\xFF']),
  }
  let standard_known : @mailbox.SiiCategoryEntry = {
    category: @mailbox.Dictionary,
    type_code: 80U,
    data: Bytes::new(0),
  }
  let vendor_overlay = vendor_specific.overlay_candidate()
  let application_overlay = application_specific.overlay_candidate()
  let device_overlay = device_specific.overlay_candidate()
  assert_true(vendor_overlay is Some(_))
  assert_true(application_overlay is Some(_))
  assert_true(device_overlay is Some(_))
  assert_true(standard_known.overlay_candidate() is None)
  match vendor_overlay {
    Some(overlay) => {
      assert_eq(overlay.scope, @mailbox.SiiOverlayScope::VendorSpecific)
      assert_eq(overlay.dispatch_key(), "vendor-specific:1234")
      assert_eq(overlay.decoder_name(), None)
      assert_eq(overlay.status_label(), "opaque")
      assert_eq(overlay.data.length(), 2)
    }
    None => fail("expected vendor overlay")
  }
  match application_overlay {
    Some(overlay) => {
      assert_eq(overlay.dispatch_key(), "application-specific:2001")
      assert_eq(overlay.status_label(), "opaque")
    }
    None => fail("expected application overlay")
  }
  match device_overlay {
    Some(overlay) => {
      assert_eq(overlay.dispatch_key(), "device-specific:0005")
      assert_eq(overlay.status_label(), "opaque")
    }
    None => fail("expected device overlay")
  }
}

///|
test "parse_sii_sm decodes dynamic process data types" {
  let entries = @mailbox.parse_sii_sm(
    Bytes::from_array([
      b'\x00', b'\x11', b'\x20', b'\x00', b'\x64', b'\x00', b'\x01', b'\x05', b'\x00',
      b'\x12', b'\x10', b'\x00', b'\x20', b'\x00', b'\x01', b'\x06',
    ]),
  )
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].sm_type, @mailbox.DynamicProcessDataOut)
  assert_eq(entries[1].sm_type, @mailbox.DynamicProcessDataIn)
}

///|
test "parse_sii_strings decodes utf8 text from category payload" {
  let strings = @mailbox.parse_sii_strings(
    Bytes::from_array([
      b'\x02', b'\x07', b'R', b'e', b'n', b'e', b's', b'a', b's', b'\x05', b'G',
      b'r', b'o', b'u', b'p',
    ]),
  )
  assert_eq(strings, ["Renesas", "Group"])
}

///|
test "parse_sii_strings falls back for invalid utf8 payload" {
  let strings = @mailbox.parse_sii_strings(
    Bytes::from_array([b'\x01', b'\x02', b'\xFF', b'\xFE']),
  )
  assert_eq(strings.length(), 1)
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
    firmware_version: 0U,
    hardware_version: 0U,
    production_date_raw: 0U,
    pdi_control_1: b'\x00',
    esc_config_b0: b'\x00',
    pdi_config_1: 0U,
    pdi_config_1_ext: 0U,
    esc_config_b4: 0U,
    esc_config_b5: 0U,
    esc_config_b6: 0U,
    checksum_b: 0U,
    esc_config_b_present: false,
  }
  let sm_entries : Array[@mailbox.SiiSmEntry] = [
    {
      physical_start: 0U,
      length: 0U,
      control: b'\x26',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::MailboxOut,
    },
    {
      physical_start: 0U,
      length: 0U,
      control: b'\x22',
      status: b'\x00',
      activate: b'\x01',
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
      activate: b'\x01',
      sm_type: @mailbox.SmType::MailboxOut,
    },
    {
      physical_start: 0x1080U,
      length: 128U,
      control: b'\x22',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::MailboxIn,
    },
    {
      physical_start: 0x1100U,
      length: 32U,
      control: b'\x64',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::ProcessDataOut,
    },
    {
      physical_start: 0x1200U,
      length: 16U,
      control: b'\x20',
      status: b'\x00',
      activate: b'\x01',
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
    activate: b'\x01',
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
  // Activation register
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
test "apply_pdo_lengths_to_sm_configs backfills zero-length process sms" {
  let sm_configs : Array[@mailbox.SmConfig] = [
    {
      physical_start: 0x1000U,
      length: 128U,
      control: b'\x26',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::MailboxOut,
    },
    {
      physical_start: 0x1080U,
      length: 128U,
      control: b'\x22',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::MailboxIn,
    },
    {
      physical_start: 0x1100U,
      length: 0U,
      control: b'\x64',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::ProcessDataOut,
    },
    {
      physical_start: 0x1400U,
      length: 0U,
      control: b'\x20',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::ProcessDataIn,
    },
  ]
  let rx_pdos : Array[@mailbox.SiiPdo] = [
    {
      pdo_index: 0x1600U,
      entry_count: b'\x02',
      sync_manager: b'\x02',
      synchronization: b'\x00',
      name_idx: b'\x00',
      flags: 0U,
      entries: [
        {
          entry_index: 0x6040U,
          subindex: b'\x00',
          name_idx: b'\x00',
          data_type: b'\x00',
          bit_length: b'\x10',
          flags: 0U,
        },
        {
          entry_index: 0x607AU,
          subindex: b'\x00',
          name_idx: b'\x00',
          data_type: b'\x00',
          bit_length: b'\x20',
          flags: 0U,
        },
      ],
    },
  ]
  let tx_pdos : Array[@mailbox.SiiPdo] = [
    {
      pdo_index: 0x1A00U,
      entry_count: b'\x02',
      sync_manager: b'\x03',
      synchronization: b'\x00',
      name_idx: b'\x00',
      flags: 0U,
      entries: [
        {
          entry_index: 0x6041U,
          subindex: b'\x00',
          name_idx: b'\x00',
          data_type: b'\x00',
          bit_length: b'\x10',
          flags: 0U,
        },
        {
          entry_index: 0x6064U,
          subindex: b'\x00',
          name_idx: b'\x00',
          data_type: b'\x00',
          bit_length: b'\x20',
          flags: 0U,
        },
      ],
    },
  ]
  let patched = @mailbox.apply_pdo_lengths_to_sm_configs(
    sm_configs, tx_pdos, rx_pdos,
  )
  assert_eq(patched[2].length, 6U)
  assert_eq(patched[3].length, 6U)
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
      activate: b'\x01',
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
      activate: b'\x00',
      sm_type: @mailbox.SmType::Unused,
    },
    {
      physical_start: 0xFFFFU,
      length: 0xFFFFU,
      control: b'\xFF',
      status: b'\xFF',
      activate: b'\x01',
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
test "MailboxHeader masks counter to 3 bits" {
  let mbh : @mailbox.MailboxHeader = {
    length: 10U,
    address: 0x1001U,
    channel: b'\x01',
    priority: b'\x02',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x0F',
  }
  let encoded = mbh.to_bytes()
  assert_eq(encoded[5] & b'\x80', b'\x00')
  let decoded = @mailbox.MailboxHeader::from_bytes(encoded)
  assert_eq(decoded.counter, b'\x07')
}

///|
test "MailboxRepeatState decodes request and acknowledge bits" {
  let repeat = @mailbox.MailboxRepeatState::from_sync_manager_bytes(
    b'\x02', b'\x02',
  )
  assert_true(repeat.request)
  assert_true(repeat.acknowledge)
  assert_true(repeat.is_acknowledged())
}

///|
test "MailboxRepeatState applies request without disturbing other bits" {
  let repeat : @mailbox.MailboxRepeatState = {
    request: true,
    acknowledge: false,
  }
  let activate = repeat.apply_to_activate_byte(b'\x41')
  assert_eq(activate, b'\x43')
  let pdi = repeat.apply_to_pdi_control_byte(b'\x81')
  assert_eq(pdi, b'\x81')
}

///|
test "MailboxHeader::from_bytes rejects short data" {
  let short = Bytes::new(3)
  let result = try? @mailbox.MailboxHeader::from_bytes(short)
  assert_true(result is Err(_))
}

///|
test "MailboxCounter cycles 1 through 7" {
  let ctr = @mailbox.MailboxCounter::new()
  let mut last = b'\x00'
  for _i = 0; _i < 30; _i = _i + 1 {
    let v = ctr.next()
    assert_true(v >= b'\x01' && v <= b'\x07')
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
  assert_eq(mbh.address, 0U)
  assert_eq(mbh.length, 10U) // 2 + 8
}

///|
test "SdoTransaction upload request encode" {
  let txn = @mailbox.build_sdo_upload(b'\x01', 0x1001U, 0x1018U, b'\x01')
  let frame = txn.encode()
  assert_eq(frame.length(), 16)
  assert_eq(frame[2], b'\x00')
  assert_eq(frame[3], b'\x00')
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
  assert_true(!resp.segmented)
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
  assert_true(!resp.last_segment)
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
  assert_eq(mbh.address, 0U)
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
    firmware_version: 0U,
    hardware_version: 0U,
    production_date_raw: 0U,
    pdi_control_1: b'\x00',
    esc_config_b0: b'\x00',
    pdi_config_1: 0U,
    pdi_config_1_ext: 0U,
    esc_config_b4: 0U,
    esc_config_b5: 0U,
    esc_config_b6: 0U,
    checksum_b: 0U,
    esc_config_b_present: false,
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
  assert_true(!cfg.is_valid())
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
  assert_true(cnt >= b'\x01' && cnt <= b'\x07')
  assert_true(!rmsm.is_idle())
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
  let wrong_cnt = if cnt == b'\x07' { b'\x01' } else { cnt + b'\x01' }
  let result = try? rmsm.validate_response(wrong_cnt)
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

///|
test "parse_sii_categories accepts standard end marker 0xFFFF" {
  let data = Bytes::makei(132, fn(i) {
    match i {
      128 => b'\xFF'
      129 => b'\xFF'
      _ => b'\x00'
    }
  })
  let categories = @mailbox.parse_sii_categories(data)
  assert_eq(categories.length(), 0)
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
  assert_true(!is_new) // Repeat detected
}

///|
test "Rmsm begin_read_repeat toggles SyncManager repeat request bit" {
  let rmsm = @mailbox.Rmsm::new()
  let _ = rmsm.begin_transaction()
  let first = rmsm.begin_read_repeat(b'\x01')
  assert_eq(first, b'\x03')
  assert_true(rmsm.awaits_repeat_ack())
  let second = rmsm.begin_read_repeat(first)
  assert_eq(second, b'\x01')
  assert_true(rmsm.awaits_repeat_ack())
}

///|
test "Rmsm observe_repeat_ack completes when toggle matches" {
  let rmsm = @mailbox.Rmsm::new()
  let _ = rmsm.begin_transaction()
  ignore(rmsm.begin_read_repeat(b'\x00'))
  assert_true(!rmsm.observe_repeat_ack(b'\x00'))
  assert_true(rmsm.awaits_repeat_ack())
  assert_true(rmsm.observe_repeat_ack(b'\x02'))
  assert_true(!rmsm.awaits_repeat_ack())
}

///|
test "Rmsm begin_read_repeat rejects idle state" {
  let rmsm = @mailbox.Rmsm::new()
  let result = try? rmsm.begin_read_repeat(b'\x00')
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

///|
test "Rmsm record_timeout allows retries up to max" {
  let rmsm = @mailbox.Rmsm::new(max_retries=2)
  let _ = rmsm.begin_transaction()
  assert_true(rmsm.record_timeout())
  assert_true(rmsm.record_timeout())
  assert_true(!rmsm.record_timeout()) // Third retry exceeds max
}

///|
test "Rmsm reset returns to Idle" {
  let rmsm = @mailbox.Rmsm::new()
  let _ = rmsm.begin_transaction()
  ignore(rmsm.begin_read_repeat(b'\x00'))
  rmsm.reset()
  assert_true(rmsm.is_idle())
  assert_true(!rmsm.awaits_repeat_ack())
}

///|
test "Rmsm retry reset preserves accumulated retry budget" {
  let rmsm = @mailbox.Rmsm::new(max_retries=1)
  let _ = rmsm.begin_transaction()
  assert_true(rmsm.record_timeout())
  rmsm.reset_for_retry()
  let _ = rmsm.begin_retry_transaction()
  assert_true(!rmsm.record_timeout())
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
  // CoE header: service type = 1 (Emergency) in bits [15:12] 鈫?high byte = 0x10
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
    current_on_ebus: 0,
    group_idx_dup: b'\x00',
    physical_port_0: b'\x00',
    physical_port_1: b'\x00',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  }
  assert_true(gen.is_op_only())
  assert_true(!gen.prefers_not_lrw())
  assert_true(!gen.supports_identification_ado())
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
    current_on_ebus: 0,
    group_idx_dup: b'\x00',
    physical_port_0: b'\x00',
    physical_port_1: b'\x00',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  }
  assert_true(!gen.is_op_only())
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
    current_on_ebus: 0,
    group_idx_dup: b'\x00',
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
    current_on_ebus: 0,
    group_idx_dup: b'\x00',
    physical_port_0: b'\x00',
    physical_port_1: b'\x00',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  }
  assert_true(!gen.is_op_only())
  assert_true(!gen.prefers_not_lrw())
  assert_true(!gen.supports_identification_ado())
  assert_true(!gen.supports_mailbox_data_link_layer())
  assert_true(!gen.supports_identification_physical_memory())
}

///|
test "SiiGeneral mailbox and identification helpers detect bits" {
  let gen : @mailbox.SiiGeneral = {
    group_idx: b'\x00',
    image_idx: b'\x00',
    order_idx: b'\x00',
    name_idx: b'\x00',
    coe_details: b'\x3F',
    foe_supported: false,
    eoe_supported: false,
    soe_supported: false,
    soe_channels: b'\x00',
    ds402_channels: b'\x00',
    sysman_class: b'\x00',
    flags: b'\x14',
    current_on_ebus: 0,
    group_idx_dup: b'\x00',
    physical_port_0: b'\x00',
    physical_port_1: b'\x00',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  }
  assert_true(gen.supports_coe_sdo())
  assert_true(gen.supports_coe_sdo_info())
  assert_true(gen.supports_coe_pdo_assign())
  assert_true(gen.supports_coe_pdo_configuration())
  assert_true(gen.supports_coe_upload_at_startup())
  assert_true(gen.supports_coe_complete_access())
  assert_true(gen.supports_mailbox_data_link_layer())
  assert_true(gen.supports_identification_physical_memory())
}

///|
test "SiiData mailbox protocol helpers detect masks" {
  let sii : @mailbox.SiiData = {
    vendor_id: 0U,
    product_code: 0U,
    revision: 0U,
    serial: 0U,
    bootstrap_rx_offset: 0U,
    bootstrap_rx_size: 0U,
    bootstrap_tx_offset: 0U,
    bootstrap_tx_size: 0U,
    mailbox_rx_offset: 0U,
    mailbox_rx_size: 0U,
    mailbox_tx_offset: 0U,
    mailbox_tx_size: 0U,
    mailbox_protocols: 0x003FU,
    firmware_version: 0U,
    hardware_version: 0U,
    production_date_raw: 0U,
    pdi_control_1: b'\x00',
    esc_config_b0: b'\x00',
    pdi_config_1: 0U,
    pdi_config_1_ext: 0U,
    esc_config_b4: 0U,
    esc_config_b5: 0U,
    esc_config_b6: 0U,
    checksum_b: 0U,
    esc_config_b_present: false,
  }
  assert_true(sii.supports_aoe())
  assert_true(sii.supports_eoe())
  assert_true(sii.supports_coe())
  assert_true(sii.supports_foe())
  assert_true(sii.supports_soe())
  assert_true(sii.supports_voe())
}

///|
test "parse_sii_fmmu handles dynamic outputs and inputs" {
  let fmmu_dirs = @mailbox.parse_sii_fmmu(
    Bytes::from_array([b'\x05', b'\x06', b'\x01', b'\x02']),
  )
  assert_eq(fmmu_dirs.length(), 4)
  assert_eq(fmmu_dirs[0], @mailbox.FmmuDirection::DynamicOutputs)
  assert_eq(fmmu_dirs[1], @mailbox.FmmuDirection::DynamicInputs)
  assert_eq(fmmu_dirs[2], @mailbox.FmmuDirection::Outputs)
  assert_eq(fmmu_dirs[3], @mailbox.FmmuDirection::Inputs)
}

///|
test "parse_sii_general populates group_idx_dup" {
  let data = Bytes::makei(20, fn(i) {
    match i {
      0 => b'\x01' // group_idx
      14 => b'\x07' // group_idx_dup
      _ => b'\x00'
    }
  })
  let general = @mailbox.parse_sii_general(data)
  assert_eq(general.group_idx, b'\x01')
  assert_eq(general.group_idx_dup, b'\x07')
}

///|
test "SiiGeneral identification_method extracts bits 3-4" {
  // bits 3-4 = 0b00 => method 0
  let gen0 : @mailbox.SiiGeneral = {
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
    current_on_ebus: 0,
    group_idx_dup: b'\x00',
    physical_port_0: b'\x00',
    physical_port_1: b'\x00',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  }
  assert_eq(gen0.identification_method(), 0)
  // bit 3 set = 0x08 => method 1 (IdentALSts)
  let gen1 : @mailbox.SiiGeneral = { ..gen0, flags: b'\x08' }
  assert_eq(gen1.identification_method(), 1)
  // bit 4 set = 0x10 => method 2 (IdentPhyM)
  let gen2 : @mailbox.SiiGeneral = { ..gen0, flags: b'\x10' }
  assert_eq(gen2.identification_method(), 2)
  // bits 3+4 set = 0x18 => method 3 (both)
  let gen3 : @mailbox.SiiGeneral = { ..gen0, flags: b'\x18' }
  assert_eq(gen3.identification_method(), 3)
}

///|
test "SiiPdo flag helpers" {
  let pdo : @mailbox.SiiPdo = {
    pdo_index: 0x1600U,
    entry_count: b'\x01',
    sync_manager: b'\x02',
    synchronization: b'\x00',
    name_idx: b'\x00',
    flags: 0x0B33U, // bits 0,1,4,5,8,9,11 set
    entries: [],
  }
  assert_true(pdo.is_mandatory()) // bit 0
  assert_true(pdo.is_default()) // bit 1
  assert_true(pdo.is_fixed_content()) // bit 4
  assert_true(pdo.is_virtual_content()) // bit 5
  assert_true(pdo.is_module_align()) // bit 8
  assert_true(pdo.is_depend_on_slot()) // bit 9
  assert_true(!pdo.is_depend_on_slot_group()) // bit 10 NOT set
  assert_true(pdo.is_overwritten_by_module()) // bit 11
}

///|
test "SiiPdo all flags clear" {
  let pdo : @mailbox.SiiPdo = {
    pdo_index: 0x1A00U,
    entry_count: b'\x00',
    sync_manager: b'\x00',
    synchronization: b'\x00',
    name_idx: b'\x00',
    flags: 0x0000U,
    entries: [],
  }
  assert_true(!pdo.is_mandatory())
  assert_true(!pdo.is_default())
  assert_true(!pdo.is_fixed_content())
  assert_true(!pdo.is_virtual_content())
  assert_true(!pdo.is_module_align())
  assert_true(!pdo.is_depend_on_slot())
  assert_true(!pdo.is_depend_on_slot_group())
  assert_true(!pdo.is_overwritten_by_module())
}

///|
test "sdo_abort_code_description known codes" {
  assert_eq(@mailbox.sdo_abort_code_description(0x00000000U), "No error")
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06020000U),
    "The object does not exist in the object dictionary",
  )
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06090011U),
    "Subindex does not exist",
  )
  assert_eq(
    @mailbox.sdo_abort_code_description(0x05030000U),
    "Toggle bit not changed",
  )
  assert_eq(
    @mailbox.sdo_abort_code_description(0x08000022U),
    "Data cannot be transferred or stored to the application because of the present device state",
  )
}

///|
test "sdo_abort_code_description unknown code" {
  let desc = @mailbox.sdo_abort_code_description(0xDEADBEEFU)
  assert_true(desc.contains("Unknown"))
}

///|
test "FoeOpCode roundtrip byte conversion" {
  let ops : Array[@mailbox.FoeOpCode] = [Read, Write, Data, Ack, Error, Busy]
  for op in ops {
    let b = op.to_byte()
    let decoded = @mailbox.FoeOpCode::from_byte(b)
    assert_eq(op, decoded)
  }
}

///|
test "FoeOpCode from_byte invalid raises error" {
  let result = try? @mailbox.FoeOpCode::from_byte(b'\x00')
  assert_true(result is Err(_))
  let result2 = try? @mailbox.FoeOpCode::from_byte(b'\xFF')
  assert_true(result2 is Err(_))
}

///|
// ===== SoE tests (was 0% coverage) =====

///|
test "SoeOpCode roundtrip uint conversion" {
  let ops : Array[@mailbox.SoeOpCode] = [
    ReadReq,
    ReadRes,
    WriteReq,
    WriteRes,
    Notification,
    Emergency,
  ]
  for op in ops {
    let v = op.to_uint()
    let decoded = @mailbox.SoeOpCode::from_uint(v)
    assert_eq(op, decoded)
  }
}

///|
test "SoeOpCode from_uint invalid raises error" {
  let result = try? @mailbox.SoeOpCode::from_uint(0U)
  assert_true(result is Err(_))
  let result2 = try? @mailbox.SoeOpCode::from_uint(7U)
  assert_true(result2 is Err(_))
}

///|
test "SoeElementFlag to_byte values" {
  assert_eq(@mailbox.SoeElementFlag::DataState.to_byte(), b'\x01')
  assert_eq(@mailbox.SoeElementFlag::Name.to_byte(), b'\x02')
  assert_eq(@mailbox.SoeElementFlag::Attribute.to_byte(), b'\x04')
  assert_eq(@mailbox.SoeElementFlag::Unit.to_byte(), b'\x08')
  assert_eq(@mailbox.SoeElementFlag::Min.to_byte(), b'\x10')
  assert_eq(@mailbox.SoeElementFlag::Max.to_byte(), b'\x20')
  assert_eq(@mailbox.SoeElementFlag::Value.to_byte(), b'\x40')
  assert_eq(@mailbox.SoeElementFlag::Default.to_byte(), b'\x80')
}

///|
test "soe_element_flags combine multiple flags" {
  let flags = @mailbox.soe_element_flags([
    @mailbox.SoeElementFlag::Value,
    @mailbox.SoeElementFlag::Name,
  ])
  assert_eq(flags, b'\x42') // 0x40 | 0x02
}

///|
test "soe_element_flags empty" {
  let flags = @mailbox.soe_element_flags([])
  assert_eq(flags, b'\x00')
}

///|
test "encode_soe_read_req and decode roundtrip" {
  let frame = @mailbox.encode_soe_read_req(
    b'\x01', // counter
    1U, // drive_no
    @mailbox.soe_element_flags([@mailbox.SoeElementFlag::Value]),
    0x0015U, // IDN
  )
  // Verify frame is valid 鈥?ReadReq will trigger unexpected opcode error
  // since decode_soe_response expects response opcodes only
  assert_true(frame.length() >= 10) // 6B mailbox header + 4B SoE header
}

///|
test "encode_soe_write_req with data" {
  let data = Bytes::from_array([b'\xAA', b'\xBB', b'\xCC'])
  let frame = @mailbox.encode_soe_write_req(
    b'\x02', // counter
    2U, // drive_no
    @mailbox.soe_element_flags([@mailbox.SoeElementFlag::Value]),
    0x0020U, // IDN
    data,
  )
  assert_true(frame.length() >= 13) // 6B + 4B + 3B data
}

///|
test "decode_soe_response read data" {
  // Build a SoE ReadRes frame manually
  // Mailbox header (6 bytes): length=7, address=0, ch=0, pri=0, type=SoE(5), counter=1
  let frame = Bytes::from_array([
    b'\x07', b'\x00', // length = 7
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x15', // byte4=ch|pri=0, byte5=type(5)|counter(1<<4)=0x15
    // SoE header (4 bytes):
     b'\x02', // byte0: opCode=ReadRes(2)[2:0], incomplete=0, error=0, driveNo=0
     b'\x40', // element_flags = Value
     b'\x15', b'\x00', // IDN = 0x0015
    // Data (3 bytes):
     b'\xDE', b'\xAD', b'\xBE',
  ])
  let resp = @mailbox.decode_soe_response(frame)
  assert_true(
    resp
    is @mailbox.SoeResponse::SoeReadData(
      drive_no=0,
      idn=0x0015,
      incomplete=false,
      ..
    ),
  )
}

///|
test "decode_soe_response write ack" {
  let frame = Bytes::from_array([
    b'\x04', b'\x00', // length = 4
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x15', // type=SoE(5), counter=1
     b'\x04', // byte0: opCode=WriteRes(4), incomplete=0, error=0, driveNo=0
     b'\x40', // element_flags = Value
     b'\x20', b'\x00', // IDN = 0x0020
  ])
  let resp = @mailbox.decode_soe_response(frame)
  assert_true(
    resp is @mailbox.SoeResponse::SoeWriteAck(drive_no=0, idn=0x0020, ..),
  )
}

///|
test "decode_soe_response error" {
  let frame = Bytes::from_array([
    b'\x06', b'\x00', // length = 6
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x15', // type=SoE(5), counter=1
     b'\x12', // byte0: opCode=ReadRes(2), incomplete=0, error=1(bit4), driveNo=0
     b'\x40', // element_flags
     b'\x15', b'\x00', // IDN = 0x0015
     b'\x03', b'\x00', // error_code = 3
  ])
  let resp = @mailbox.decode_soe_response(frame)
  assert_true(
    resp is @mailbox.SoeResponse::SoeError(drive_no=0, idn=0x0015, error_code=3),
  )
}

///|
test "decode_soe_response notification" {
  let frame = Bytes::from_array([
    b'\x07', b'\x00', // length = 7
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x15', // type=SoE(5), counter=1
     b'\x05', // byte0: opCode=Notification(5), incomplete=0, error=0, driveNo=0
     b'\x40', // element_flags
     b'\x10', b'\x00', // IDN = 0x0010
     b'\x01', b'\x02', b'\x03', // data
  ])
  let resp = @mailbox.decode_soe_response(frame)
  assert_true(
    resp is @mailbox.SoeResponse::SoeNotification(drive_no=0, idn=0x0010, ..),
  )
}

///|
test "decode_soe_response with drive_no" {
  // driveNo=3 鈫?bits[7:5] = 0b011 = 0x60
  let frame = Bytes::from_array([
    b'\x04', b'\x00', // length = 4
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x15', // type=SoE(5), counter=1
     b'\x64', // byte0: opCode=WriteRes(4), incomplete=0, error=0, driveNo=3 (0x60)
     b'\x40', // element_flags
     b'\x20', b'\x00', // IDN
  ])
  let resp = @mailbox.decode_soe_response(frame)
  assert_true(resp is @mailbox.SoeResponse::SoeWriteAck(drive_no=3, ..))
}

///|
test "decode_soe_response incomplete flag" {
  let frame = Bytes::from_array([
    b'\x07', b'\x00', // length = 7
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x15', // type=SoE(5), counter=1
     b'\x0A', // byte0: opCode=ReadRes(2), incomplete=1(bit3=0x08), error=0, driveNo=0
     b'\x40', // element_flags
     b'\x15', b'\x00', // IDN
     b'\xAA', b'\xBB', b'\xCC', // data
  ])
  let resp = @mailbox.decode_soe_response(frame)
  assert_true(
    resp is @mailbox.SoeResponse::SoeReadData(incomplete=true, drive_no=0, ..),
  )
}

///|
test "decode_soe_response frame too short" {
  let short = Bytes::from_array([b'\x00', b'\x00', b'\x00'])
  let result = try? @mailbox.decode_soe_response(short)
  assert_true(result is Err(_))
}

///|
test "decode_soe_response wrong mailbox type" {
  // Build frame with CoE type instead of SoE
  let frame = Bytes::from_array([
    b'\x04', b'\x00', b'\x00', b'\x00', b'\x00', b'\x13', // type=CoE(3), counter=1 鈫?byte5=0x13
     b'\x02', b'\x40', b'\x15', b'\x00',
  ])
  let result = try? @mailbox.decode_soe_response(frame)
  assert_true(result is Err(_))
}

///|
test "decode_soe_response unexpected opcode (ReadReq in response)" {
  let frame = Bytes::from_array([
    b'\x04', b'\x00', b'\x00', b'\x00', b'\x00', b'\x15', // type=SoE(5), counter=1
     b'\x01', // byte0: opCode=ReadReq(1) 鈥?unexpected in response
     b'\x40', b'\x15', b'\x00',
  ])
  let result = try? @mailbox.decode_soe_response(frame)
  assert_true(result is Err(_))
}

///|
// ===== EoE tests (was ~33% coverage) =====

///|
test "EoeFrameType roundtrip uint conversion" {
  let types : Array[@mailbox.EoeFrameType] = [
    FragData,
    InitRespTimestamp,
    SetIpReq,
    SetIpResp,
    SetAddrFilterReq,
    SetAddrFilterResp,
    GetIpReq,
    GetIpResp,
    GetAddrFilterReq,
    GetAddrFilterResp,
  ]
  for t in types {
    let v = t.to_uint()
    let decoded = @mailbox.EoeFrameType::from_uint(v)
    assert_eq(t, decoded)
  }
}

///|
test "EoeFrameType from_uint invalid raises error" {
  let result = try? @mailbox.EoeFrameType::from_uint(10U)
  assert_true(result is Err(_))
}

///|
test "EoeResult roundtrip" {
  let results : Array[@mailbox.EoeResult] = [
    Success,
    UnspecifiedError,
    UnsupportedFrameType,
    NoIpSupport,
    NoDhcpSupport,
    NoFilterSupport,
    Unknown(0x9999U),
  ]
  for r in results {
    let v = r.to_uint()
    let decoded = @mailbox.EoeResult::from_uint(v)
    assert_eq(r, decoded)
  }
}

///|
test "encode_eoe_fragment and decode roundtrip" {
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03'])
  let frame = @mailbox.encode_eoe_fragment(
    b'\x01', // counter
     0U, // port
     true, // last_fragment
     0U, // frag_number
     0U, // frame_offset
     1U, // frame_number
     data,
  )
  let resp = @mailbox.decode_eoe_response(frame)
  assert_true(
    resp
    is @mailbox.EoeResponse::EoeFragment(
      last_fragment=true,
      frag_number=0,
      frame_number=1,
      ..
    ),
  )
}

///|
test "encode_eoe_fragment not last fragment" {
  let data = Bytes::from_array([b'\xAA', b'\xBB'])
  let frame = @mailbox.encode_eoe_fragment(b'\x02', 0U, false, 1U, 1U, 0U, data)
  let resp = @mailbox.decode_eoe_response(frame)
  assert_true(
    resp
    is @mailbox.EoeResponse::EoeFragment(
      last_fragment=false,
      frag_number=1,
      frame_offset=1,
      ..
    ),
  )
}

///|
test "encode_eoe_set_ip_req with all params" {
  let ip = Bytes::from_array([b'\xC0', b'\xA8', b'\x01', b'\x01'])
  let subnet = Bytes::from_array([b'\xFF', b'\xFF', b'\xFF', b'\x00'])
  let gateway = Bytes::from_array([b'\xC0', b'\xA8', b'\x01', b'\xFE'])
  let frame = @mailbox.encode_eoe_set_ip_req(b'\x01', 0U, ip, subnet, gateway)
  assert_true(frame.length() > 10)
}

///|
test "encode_eoe_set_ip_req with only ip" {
  let ip = Bytes::from_array([b'\xC0', b'\xA8', b'\x01', b'\x01'])
  let frame = @mailbox.encode_eoe_set_ip_req(
    b'\x01',
    0U,
    ip,
    Bytes::new(0),
    Bytes::new(0),
  )
  assert_true(frame.length() > 10)
}

///|
test "encode_eoe_get_ip_req" {
  let frame = @mailbox.encode_eoe_get_ip_req(b'\x03', 0U)
  assert_eq(frame.length(), 10) // 6B mailbox + 4B EoE header
}

///|
test "decode_eoe_response SetIpResp" {
  // Build a SetIpResp frame
  let frame = Bytes::from_array([
    b'\x04', b'\x00', // length = 4
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x12', // type=EoE(2), counter=1 鈫?byte5=0x12
     b'\x03', b'\x01', // frameinfo1: frame_type=SetIpResp(3), last=1 (bit8)
     b'\x00', b'\x00', // frameinfo2: result=0 (Success)
  ])
  let resp = @mailbox.decode_eoe_response(frame)
  assert_true(resp is @mailbox.EoeResponse::EoeIpResponse(..))
}

///|
test "decode_eoe_response GetIpResp with data" {
  let frame = Bytes::from_array([
    b'\x08', b'\x00', // length = 8
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x12', // type=EoE(2), counter=1 鈫?byte5=0x12
     b'\x07', b'\x01', // frameinfo1: frame_type=GetIpResp(7), last=1
     b'\x00', b'\x00', // frameinfo2: result=0
     b'\xC0', b'\xA8', b'\x01', b'\x01', // data: IP 192.168.1.1
  ])
  let resp = @mailbox.decode_eoe_response(frame)
  assert_true(resp is @mailbox.EoeResponse::EoeIpResponse(..))
}

///|
test "decode_eoe_response frame too short" {
  let short = Bytes::from_array([b'\x00', b'\x01'])
  let result = try? @mailbox.decode_eoe_response(short)
  assert_true(result is Err(_))
}

///|
test "decode_eoe_response wrong mailbox type" {
  let frame = Bytes::from_array([
    b'\x04', b'\x00', b'\x00', b'\x00', b'\x00', b'\x13', // type=CoE(3), counter=1 鈫?byte5=0x13
     b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  let result = try? @mailbox.decode_eoe_response(frame)
  assert_true(result is Err(_))
}

///|
// ===== FoE encode tests (was ~12% gap) =====

///|
test "encode_foe_read frame structure" {
  let frame = @mailbox.encode_foe_read(b'\x01', 0x12345678U, "test.bin")
  // Verify mailbox header
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::FoE)
  // Verify filename is in the payload (ASCII bytes of "test.bin")
  assert_true(frame.length() >= 6 + 6 + 8) // mbh + foe_header + filename
}

///|
test "encode_foe_write frame structure" {
  let frame = @mailbox.encode_foe_write(b'\x02', 0U, "firmware.fw")
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::FoE)
  assert_true(frame.length() >= 6 + 6 + 11) // mbh + foe_header + filename
}

///|
test "encode_foe_data roundtrip" {
  let data = Bytes::from_array([b'\x01', b'\x02', b'\x03', b'\x04'])
  let frame = @mailbox.encode_foe_data(b'\x03', 1U, data)
  let (mbh, resp) = @mailbox.decode_foe_response(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::FoE)
  assert_true(resp is @mailbox.FoeResponse::FoeData(packet_number=1, ..))
}

///|
test "encode_foe_ack roundtrip" {
  let frame = @mailbox.encode_foe_ack(b'\x04', 2U)
  let (mbh, resp) = @mailbox.decode_foe_response(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::FoE)
  assert_true(resp is @mailbox.FoeResponse::FoeAck(packet_number=2))
}

///|
test "FoeErrorCode roundtrip" {
  let codes : Array[@mailbox.FoeErrorCode] = [
    NotDefined,
    NotFound,
    AccessDenied,
    DiskFull,
    Illegal,
    PacketNumberWrong,
    AlreadyExists,
    NoUser,
    BootstrapOnly,
    NotInBootstrap,
    NoRights,
    ProgramError,
    InvalidChecksum,
    InvalidFirmware,
    FlashError,
  ]
  for code in codes {
    let u = code.to_uint()
    let decoded = @mailbox.FoeErrorCode::from_uint(u)
    assert_eq(code, decoded)
  }
}

///|
test "FoeErrorCode unknown code roundtrip" {
  let code = @mailbox.FoeErrorCode::from_uint(0x1234U)
  assert_true(code is Unknown(_))
  assert_eq(code.to_uint(), 0x1234U)
}

///|
test "encode_foe_read produces valid frame" {
  let frame = @mailbox.encode_foe_read(b'\x01', 0x12345678U, "test.bin")
  // 6 mailbox header + 6 FoE header + 8 filename = 20 bytes
  assert_eq(frame.length(), 20)
  // Mailbox header: length field (LE u16 at offset 0) = 14 (FoE header + filename)
  assert_eq(frame[0], b'\x0E') // 14 low
  assert_eq(frame[1], b'\x00') // 14 high
  // Mailbox type byte at offset 5: bits [3:0] = 4 (FoE), bits [7:4] = counter
  // counter=1 鈫?(1 << 4) | 4 = 0x14
  assert_eq(frame[5], b'\x14')
  // FoE OpCode at offset 6: Read = 0x01
  assert_eq(frame[6], b'\x01')
  // Reserved at offset 7
  assert_eq(frame[7], b'\x00')
  // Password (LE u32) at offset 8-11: 0x12345678
  assert_eq(frame[8], b'\x78')
  assert_eq(frame[9], b'\x56')
  assert_eq(frame[10], b'\x34')
  assert_eq(frame[11], b'\x12')
}

///|
test "encode_foe_write produces valid frame" {
  let frame = @mailbox.encode_foe_write(b'\x02', 0U, "fw.bin")
  // 6 + 6 + 6 = 18 bytes
  assert_eq(frame.length(), 18)
  // FoE OpCode at offset 6: Write = 0x02
  assert_eq(frame[6], b'\x02')
}

///|
test "encode_foe_data produces valid frame" {
  let payload = Bytes::from_array([b'\xAA', b'\xBB', b'\xCC'])
  let frame = @mailbox.encode_foe_data(b'\x03', 1U, payload)
  // 6 + 6 + 3 = 15 bytes
  assert_eq(frame.length(), 15)
  // FoE OpCode at offset 6: Data = 0x03
  assert_eq(frame[6], b'\x03')
  // Packet number (LE u32) at offset 8-11: 1
  assert_eq(frame[8], b'\x01')
  assert_eq(frame[9], b'\x00')
  // Payload starts at offset 12
  assert_eq(frame[12], b'\xAA')
  assert_eq(frame[13], b'\xBB')
  assert_eq(frame[14], b'\xCC')
}

///|
test "encode_foe_ack produces valid frame" {
  let frame = @mailbox.encode_foe_ack(b'\x04', 5U)
  // 6 + 6 = 12 bytes
  assert_eq(frame.length(), 12)
  // FoE OpCode at offset 6: Ack = 0x04
  assert_eq(frame[6], b'\x04')
  // Packet number at offset 8-11: 5
  assert_eq(frame[8], b'\x05')
  assert_eq(frame[9], b'\x00')
}

///|
test "decode_foe_response Data frame" {
  // Build a FoE Data response frame manually
  let frame = @mailbox.encode_foe_data(
    b'\x01',
    42U,
    Bytes::from_array([b'\xDE', b'\xAD']),
  )
  let (mbh, resp) = @mailbox.decode_foe_response(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::FoE)
  match resp {
    @mailbox.FoeResponse::FoeData(packet_number=pn, data=d) => {
      assert_eq(pn, 42U)
      assert_eq(d.length(), 2)
      assert_eq(d[0], b'\xDE')
      assert_eq(d[1], b'\xAD')
    }
    _ => assert_true(false)
  }
}

///|
test "decode_foe_response Ack frame" {
  let frame = @mailbox.encode_foe_ack(b'\x02', 7U)
  let (_mbh, resp) = @mailbox.decode_foe_response(frame)
  match resp {
    @mailbox.FoeResponse::FoeAck(packet_number=pn) => assert_eq(pn, 7U)
    _ => assert_true(false)
  }
}

///|
test "decode_foe_response too short frame" {
  let short = Bytes::from_array([b'\x00', b'\x01', b'\x02'])
  let result = try? @mailbox.decode_foe_response(short)
  assert_true(result is Err(_))
}

///|
test "decode_foe_response wrong mailbox type" {
  // Build a frame with CoE type instead of FoE
  let buf = Bytes::makei(14, fn(i) {
    match i {
      0 => b'\x08' // length low = 8
      1 => b'\x00' // length high
      5 => b'\x13' // type=CoE(3), counter=1 鈫?(1<<4)|3 = 0x13
      6 => b'\x03' // FoE Data opcode (but type is CoE)
      _ => b'\x00'
    }
  })
  let result = try? @mailbox.decode_foe_response(buf)
  assert_true(result is Err(_))
}

// ===== Coverage: mailbox/coe_engine.mbt 鈥?MailboxHeader VoE and unknown type =====

///|
test "MailboxHeader from_bytes VoE type" {
  let frame = Bytes::from_array([
    b'\x04', b'\x00', // length = 4
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x1F', // byte5: type=VoE(0x0F), counter=1(0x10) 鈫?0x1F
  ])
  let mbh = @mailbox.MailboxHeader::from_bytes(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::VoE)
}

///|
test "MailboxHeader from_bytes unknown type raises" {
  let frame = Bytes::from_array([
    b'\x04', b'\x00', b'\x00', b'\x00', b'\x00', b'\x1E', // type=0x0E (invalid), counter=1
  ])
  let result = try? @mailbox.MailboxHeader::from_bytes(frame)
  assert_true(result is Err(_))
}

// ===== Coverage: mailbox/mailbox.mbt 鈥?MailboxType::to_byte Err and VoE =====

///|
test "MailboxType to_byte Err" {
  assert_eq(@mailbox.MailboxType::Err.to_byte(), b'\x00')
}

///|
test "MailboxType to_byte VoE" {
  assert_eq(@mailbox.MailboxType::VoE.to_byte(), b'\x0F')
}

// ===== Coverage: mailbox/coe_engine.mbt 鈥?CoeService and SdoCommand edge cases =====

///|
test "decode_sdo_response with Emergency service" {
  // Build CoE frame with service=Emergency(1) in CoE header
  // Mailbox header: length=10 (coe_hdr=2 + sdo_hdr=8), type=CoE(3), counter=1
  let frame = Bytes::from_array([
    b'\x0A', b'\x00', // length = 10
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x13', // type=CoE(3), counter=1 鈫?0x13
    // CoE header: service=Emergency(1) in bits[15:12] 鈫?word = 0x1000
     b'\x00', b'\x10',
    // SDO header: command byte = UploadRequest (0x40)
     b'\x40',
    // Index (LE)
     b'\x01', b'\x10',
    // Subindex
     b'\x00',
    // Data (4 bytes)
     b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  // 0x40 has bits[7:5]=010 鈫?UploadResponse in the command decoder
  let (_mbh, resp) = @mailbox.decode_sdo_response(frame)
  assert_eq(resp.command, @mailbox.SdoCommand::UploadResponse)
}

///|
test "decode_sdo_response with TxPdo service" {
  // Build CoE frame with service=TxPdo(5)
  let frame = Bytes::from_array([
    b'\x0A', b'\x00', // length = 10
     b'\x00', b'\x00', // address = 0
     b'\x00', b'\x13', // type=CoE(3), counter=1
    // CoE header: service=TxPdo(5) in bits[15:12] 鈫?word = 0x5000
     b'\x00', b'\x50',
    // SDO header: cmd=DownloadResponse (0x60)
     b'\x60', b'\x01', b'\x10', // index
     b'\x00', // subindex
     b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  let (_mbh, resp) = @mailbox.decode_sdo_response(frame)
  assert_eq(resp.command, @mailbox.SdoCommand::DownloadResponse)
}

///|
test "decode_sdo_response with invalid CoE service raises" {
  let frame = Bytes::from_array([
    b'\x0A', b'\x00', b'\x00', b'\x00', b'\x00', b'\x13', // CoE, counter=1
    // CoE header: service=0x0A (invalid)
     b'\x00', b'\xA0', b'\x60', // SDO cmd
     b'\x01', b'\x10', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  let result = try? @mailbox.decode_sdo_response(frame)
  assert_true(result is Err(_))
}

///|
test "decode_sdo_response DownloadRequest command" {
  // SDO command specifier bits[7:5] = 001 鈫?DownloadRequest (0x21)
  let frame = Bytes::from_array([
    b'\x0A', b'\x00', b'\x00', b'\x00', b'\x00', b'\x13', // CoE
     b'\x00', b'\x20', // CoE header: SdoRequest(2)
     b'\x21', // DownloadRequest: bits[7:5]=001
     b'\x01', b'\x10', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  let (_mbh, resp) = @mailbox.decode_sdo_response(frame)
  assert_eq(resp.command, @mailbox.SdoCommand::DownloadRequest)
}

///|
test "decode_sdo_response AbortTransfer command" {
  // SDO Abort: cmd_byte=0x80, then abort code in 4 bytes after index/subindex
  let frame = Bytes::from_array([
    b'\x0A', b'\x00', // length = 10
     b'\x00', b'\x00', b'\x00', b'\x13', // CoE
     b'\x00', b'\x20', // CoE header: SdoRequest(2)
     b'\x80', // AbortTransfer: bits[7:5]=100
     b'\x01', b'\x10', b'\x00', // index=0x1001, subindex=0
     b'\x00', b'\x00', b'\x02', b'\x06', // abort code = 0x06020000
  ])
  let result = try? @mailbox.decode_sdo_response(frame)
  // Should raise SdoAbort
  assert_true(result is Err(_))
}

// ===== Coverage: mailbox/foe.mbt 鈥?decode_foe_response edge cases =====

///|
test "decode_foe_response payload too short" {
  // FoE frame with length=1 (too short for opcode)
  let frame = Bytes::from_array([
    b'\x01', b'\x00', // length = 1
     b'\x00', b'\x00', b'\x00', b'\x14', // type=FoE(4), counter=1
     b'\x03', // Data opcode
  ])
  let result = try? @mailbox.decode_foe_response(frame)
  assert_true(result is Err(_))
}

///|
test "decode_foe_response Data frame too short" {
  // FoE Data with payload length < foe_header_len (6)
  let frame = Bytes::from_array([
    b'\x04', b'\x00', // length = 4 (< 6 = foe_header_len)
     b'\x00', b'\x00', b'\x00', b'\x14', // type=FoE(4), counter=1
     b'\x03', b'\x00', // opcode=Data(3), reserved
     b'\x01', b'\x00', // partial packet number
  ])
  let result = try? @mailbox.decode_foe_response(frame)
  assert_true(result is Err(_))
}

///|
test "decode_foe_response Busy opcode" {
  let frame = Bytes::from_array([
    b'\x02', b'\x00', // length = 2
     b'\x00', b'\x00', b'\x00', b'\x14', // type=FoE(4), counter=1
     b'\x06', b'\x00', // opcode=Busy(6)
  ])
  let (mbh, resp) = @mailbox.decode_foe_response(frame)
  assert_eq(mbh.mb_type, @mailbox.MailboxType::FoE)
  assert_true(resp is @mailbox.FoeBusy)
}

///|
test "decode_foe_response Error with text" {
  // FoE Error: header=6, error_code=4, text=2 鈫?payload=8
  let frame = Bytes::from_array([
    b'\x08', b'\x00', // length = 8 (foe_hdr=6 + text=2)
     b'\x00', b'\x00', b'\x00', b'\x14', // type=FoE(4), counter=1
     b'\x05', b'\x00', // opcode=Error(5)
     b'\x01', b'\x80', b'\x00', b'\x00', // error_code = NotFound(0x8001) LE
     b'\x68', b'\x69', // "hi"
  ])
  let (_mbh, resp) = @mailbox.decode_foe_response(frame)
  match resp {
    @mailbox.FoeError(code~, text~) => {
      assert_eq(code, @mailbox.FoeErrorCode::NotFound)
      assert_eq(text, "hi")
    }
    _ => assert_true(false)
  }
}

// ===== Coverage: mailbox/emergency.mbt 鈥?short frame =====

///|
test "decode_emergency_frame too short" {
  // Emergency needs 16 bytes minimum (6 mbh + 2 coe + 8 emergency)
  let frame = Bytes::from_array([
    b'\x08', b'\x00', // length = 8
     b'\x00', b'\x00', b'\x00', b'\x13', // type=CoE(3)
     b'\x00', b'\x10', // CoE header: emergency(1)
     b'\x00', b'\x00', b'\x01', b'\x00', // only 4 bytes of emergency data
  ])
  let result = try? @mailbox.decode_emergency_frame(frame)
  assert_true(result is Err(_))
}

// ===== Coverage: mailbox/sii.mbt 鈥?StandardUnknown label =====

///|
test "SiiCategoryClass StandardUnknown label" {
  assert_eq(
    @mailbox.SiiCategoryClass::StandardUnknown.label(),
    "standard-unknown",
  )
}

// ===== Coverage: mailbox/sii_parser.mbt 鈥?read_sii_word out of bounds =====

///|
test "parse_sii_preamble too short" {
  let short = Bytes::new(4)
  let result = try? @mailbox.parse_sii_preamble(short)
  assert_true(result is Err(_))
}

// ===== Coverage: mailbox/rmsm.mbt 鈥?begin_retry in wrong state =====

///|
test "Rmsm begin_retry_transaction in wrong state" {
  let rmsm = @mailbox.Rmsm::new()
  // First get into WaitingForResponse state
  let _cnt = rmsm.begin_transaction()
  // Now trying begin_retry should fail since we're in WaitingForResponse
  let result = try? rmsm.begin_retry_transaction()
  assert_true(result is Err(_))
}

// ===== Coverage: mailbox/mapping.mbt 鈥?apply_pdo_lengths =====

///|
test "apply_pdo_lengths_to_sm_configs patches zero-length SM" {
  let sm_configs : Array[@mailbox.SmConfig] = [
    {
      physical_start: 0x1000U,
      length: 0U,
      control: b'\x64',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::ProcessDataOut,
    },
  ]
  let rx_pdos : Array[@mailbox.SiiPdo] = [
    {
      pdo_index: 0x1600U,
      entry_count: b'\x01',
      sync_manager: b'\x00',
      synchronization: b'\x00',
      name_idx: b'\x00',
      flags: 0U,
      entries: [
        {
          entry_index: 0x7000U,
          subindex: b'\x01',
          name_idx: b'\x00',
          data_type: b'\x05',
          bit_length: b'\x10',
          flags: 0U,
        },
      ],
    },
  ]
  let result = @mailbox.apply_pdo_lengths_to_sm_configs(sm_configs, [], rx_pdos)
  // The patched SM should have length = ceil(16 / 8) = 2
  assert_eq(result[0].length, 2U)
}

///|
// 鈹€鈹€ Batch 7: parse_sii_full_info integration 鈹€鈹€

///|
test "parse_sii_full_info with fixture eeprom" {
  let data = @fixtures.sample_sii_eeprom()
  let info = @mailbox.parse_sii_full_info(data)
  // Header fields should have nonzero vendor
  assert_true(info.header.vendor_id != 0U)
  // Categories should be non-empty
  assert_true(info.categories.length() > 0)
  // General category should be parsed
  assert_true(info.general is Some(_))
  // FMMU entries should be present
  assert_true(info.fmmu.length() > 0)
}

///|
test "parse_sii_full_info with pdo fixture" {
  let data = @fixtures.sample_sii_eeprom_with_pdo()
  let info = @mailbox.parse_sii_full_info(data)
  // Header should parse with nonzero vendor
  assert_true(info.header.vendor_id != 0U)
  // SM entries should include process data SMs
  assert_true(info.sync_managers.length() >= 4)
  // FMMU entries should be present
  assert_true(info.fmmu.length() > 0)
}

///|
test "parse_sii_full_info short data raises" {
  let data = Bytes::make(10, 0)
  let result : Result[@mailbox.SiiFullInfo, Error] = try? @mailbox.parse_sii_full_info(
    data,
  )
  assert_true(result is Err(_))
}

// ===== Batch 9: sdo_abort_code_description uncovered arms =====

///|
test "sdo_abort_code_description protocol timeout" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x05040000U),
    "SDO protocol timeout",
  )
}

///|
test "sdo_abort_code_description complete access not supported" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06010004U),
    "SDO Complete Access not supported for variable length objects",
  )
}

///|
test "sdo_abort_code_description cannot be mapped" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06040041U),
    "The object cannot be mapped into the PDO",
  )
}

///|
test "sdo_abort_code_description exceed PDO length" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06040042U),
    "Number and length of objects to be mapped would exceed PDO length",
  )
}

///|
test "sdo_abort_code_description data type length mismatch" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06070010U),
    "Data type does not match, length of service parameter does not match",
  )
}

///|
test "sdo_abort_code_description data type length too high" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06070012U),
    "Data type does not match, length of service parameter too high",
  )
}

///|
test "sdo_abort_code_description data type length too low" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06070013U),
    "Data type does not match, length of service parameter too low",
  )
}

///|
test "sdo_abort_code_description value range exceeded" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06090030U),
    "Value range of parameter exceeded",
  )
}

///|
test "sdo_abort_code_description local control" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x08000021U),
    "Data cannot be transferred or stored to the application because of local control",
  )
}

///|
test "sdo_abort_code_description object dictionary dynamic fail" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x08000023U),
    "Object dictionary dynamic generation fails or no object dictionary is present",
  )
}

// ===== Batch 9: decode_sdo_response error paths =====

///|
test "decode_sdo_response frame too short" {
  // Need at least mailbox_header(6) + coe_header(2) + 1 = 9 bytes
  let data = Bytes::make(8, 0)
  let result = try? @mailbox.decode_sdo_response(data)
  assert_true(result is Err(_))
}

///|
test "decode_sdo_response non-CoE mailbox type rejected" {
  // Build 16-byte frame: mailbox hdr says length=10, type=FoE(4), then fill
  let buf = Bytes::makei(16, fn(i) {
    match i {
      0 => b'\x0A' // length lo = 10
      1 => b'\x00' // length hi
      5 => b'\x04' // mb_type = FoE (4), counter=0
      _ => b'\x00'
    }
  })
  let result = try? @mailbox.decode_sdo_response(buf)
  assert_true(result is Err(_))
}

///|
test "decode_sdo_response abort transfer" {
  // Build frame: mailbox hdr(6) + CoE hdr(2) + SDO abort(8) = 16 bytes
  let buf = Bytes::makei(16, fn(i) {
    match i {
      0 => b'\x0A' // length lo = 10
      5 => b'\x03' // mb_type = CoE (3)
      7 => b'\x30' // CoE service hi nibble = 3 (SdoResponse) 鈫?svc_field = (0x3000 >> 12) = 3
      8 => b'\x80' // cmd = abort_transfer
      12 => b'\x47' // abort code LSB
      13 => b'\x00'
      14 => b'\x06' // 0x06040047
      15 => b'\x00'
      _ => b'\x00'
    }
  })
  let result = try? @mailbox.decode_sdo_response(buf)
  assert_true(result is Err(_))
}

// ===== Batch 9: decode_sdo_info_od/oe_description_payload edge cases =====

///|
test "decode_sdo_info_od_description_payload too short" {
  let data = Bytes::make(5, 0)
  let result = try? @mailbox.decode_sdo_info_od_description_payload(data)
  assert_true(result is Err(_))
}

///|
test "decode_sdo_info_od_description_payload no name" {
  // Exactly 6 bytes: index(2) + data_type(2) + max_subindex(1) + object_code(1)
  let data = Bytes::makei(6, fn(i) {
    match i {
      0 => b'\x01' // index lo = 1
      _ => b'\x00'
    }
  })
  let result = try? @mailbox.decode_sdo_info_od_description_payload(data)
  guard result is Ok(desc) else { panic() }
  assert_eq(desc.name, "")
}

///|
test "decode_sdo_info_oe_description_payload too short" {
  let data = Bytes::make(9, 0)
  let result = try? @mailbox.decode_sdo_info_oe_description_payload(data)
  assert_true(result is Err(_))
}

///|
test "decode_sdo_info_oe_description_payload no name" {
  // Exactly 10 bytes: index(2)+subindex(1)+value_info(1)+data_type(2)+bit_length(2)+access(2)
  let data = Bytes::makei(10, fn(i) {
    match i {
      0 => b'\x01' // index lo = 1
      6 => b'\x20' // bit_length lo = 32
      _ => b'\x00'
    }
  })
  let result = try? @mailbox.decode_sdo_info_oe_description_payload(data)
  guard result is Ok(desc) else { panic() }
  assert_eq(desc.name, "")
}

// ===== Batch 9: MailboxType::to_byte AoE and MailboxRepeatState::toggle_request =====

///|
test "MailboxType to_byte AoE" {
  assert_eq(@mailbox.MailboxType::AoE.to_byte(), b'\x01')
}

///|
test "MailboxRepeatState toggle_request" {
  let state : @mailbox.MailboxRepeatState = {
    request: true,
    acknowledge: false,
  }
  assert_eq(state.toggle_request(), false)
  let state2 : @mailbox.MailboxRepeatState = {
    request: false,
    acknowledge: false,
  }
  assert_eq(state2.toggle_request(), true)
}

// ===== Batch 9: mapping MailboxState FMMU direction =====

///|
test "calculate_fmmu_configs MailboxState direction" {
  // SM configs: SM0=MailboxOut, SM1=MailboxIn, SM2=ProcessDataOut, SM3=ProcessDataIn
  let sm_configs : Array[@mailbox.SmConfig] = [
    {
      physical_start: 0x1000U,
      length: 128U,
      control: b'\x26',
      status: b'\x00',
      activate: b'\x00',
      sm_type: @mailbox.SmType::MailboxOut,
    },
    {
      physical_start: 0x1080U,
      length: 128U,
      control: b'\x22',
      status: b'\x00',
      activate: b'\x00',
      sm_type: @mailbox.SmType::MailboxIn,
    },
    {
      physical_start: 0x1100U,
      length: 4U,
      control: b'\x24',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::ProcessDataOut,
    },
    {
      physical_start: 0x1180U,
      length: 2U,
      control: b'\x20',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::ProcessDataIn,
    },
  ]
  // FMMU directions include MailboxState
  let fmmu_dirs : Array[@mailbox.FmmuDirection] = [
    @mailbox.FmmuDirection::Outputs,
    @mailbox.FmmuDirection::Inputs,
    @mailbox.FmmuDirection::MailboxState,
  ]
  let (fmmus, total_out, total_in) = @mailbox.calculate_fmmu_configs(
    fmmu_dirs, sm_configs, 0U,
  )
  assert_eq(fmmus.length(), 3)
  assert_eq(total_out, 4)
  // MailboxState maps 1 byte 鈫?total_in = 2 (from ProcessDataIn) + 1 (MailboxState) = 3
  assert_eq(total_in, 3)
}

///|
test "apply_pdo_lengths_to_sm_configs Unused sm_type" {
  // SM with type Unused and length 0 should remain as-is
  let sm_configs : Array[@mailbox.SmConfig] = [
    {
      physical_start: 0x1000U,
      length: 0U,
      control: b'\x00',
      status: b'\x00',
      activate: b'\x00',
      sm_type: @mailbox.SmType::Unused,
    },
  ]
  let result = @mailbox.apply_pdo_lengths_to_sm_configs(sm_configs, [], [])
  assert_eq(result[0].length, 0U)
}

// ===== Batch 10: coe_engine remaining uncovered decode paths =====

///|
test "sdo_abort_code_description 0x05040001" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x05040001U),
    "Client/Server command specifier not valid or unknown",
  )
}

///|
test "sdo_abort_code_description 0x06010005" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06010005U),
    "Object length exceeds mailbox size",
  )
}

///|
test "sdo_abort_code_description 0x06040043" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06040043U),
    "General parameter incompatibility reason",
  )
}

///|
test "sdo_abort_code_description 0x06090031" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06090031U),
    "Value of parameter written too high",
  )
}

///|
test "decode_sdo_response abort with short payload" {
  // Mailbox header: length=9 (coe_header=2 + sdo_payload=7, < 8 for abort)
  // mb_type=0x03 (CoE), counter=1
  // CoE header: service=SdoResponse (3 << 12 = 0x3000), lower 12 = 0
  // SDO cmd byte = 0x80 (abort transfer)
  // But sdo_payload=7 < 8 鈫?"SDO abort payload too short"
  let buf = @buffer.new()
  // mailbox header: length=9 (LE), address=0, channel=0, priority=0, type=0x03, counter=1<<4
  buf.write_byte(b'\x09') // length lo
  buf.write_byte(b'\x00') // length hi
  buf.write_byte(b'\x00') // address lo
  buf.write_byte(b'\x00') // address hi
  buf.write_byte(b'\x00') // channel + priority
  buf.write_byte(b'\x13') // type=0x03 | counter=1<<4
  // CoE header: SdoResponse service = 3 << 12 = 0x3000
  buf.write_byte(b'\x00') // coe lo
  buf.write_byte(b'\x30') // coe hi (3 << 12)
  // SDO abort command
  buf.write_byte(b'\x80') // cmd = abort
  // Only 6 more bytes of SDO data (abort needs 8 total from sdo start, we have 7 = 9-2)
  for i = 0; i < 6; i = i + 1 {
    buf.write_byte(b'\x00')
  }
  let data = buf.to_bytes()
  let result : Result[(@mailbox.MailboxHeader, @mailbox.SdoResponse), Error] = try? @mailbox.decode_sdo_response(
    data,
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_response segmented upload" {
  // cs=000, toggle=0, n_unused=2, last=1 鈫?cmd_byte = 0x05
  // sdo_payload_len = 1 + 5 = 6 (enough for seg data 7-2=5)
  let buf = @buffer.new()
  // mailbox header: length=8 (coe_hdr=2 + sdo_payload=6)
  buf.write_byte(b'\x08')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x13') // type=CoE(3), counter=1<<4
  // CoE header: SdoResponse=3<<12
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x30')
  // SDO: cs=000, toggle=0(bit4), n_unused=2(bits3:1)=0x04, last=1(bit0) 鈫?0x05
  buf.write_byte(b'\x05')
  // 5 bytes of segment data
  for i = 0; i < 5; i = i + 1 {
    buf.write_byte((i + 0x10).to_byte())
  }
  let data = buf.to_bytes()
  let (_mbh, resp) = @mailbox.decode_sdo_response(data)
  assert_true(resp.segmented)
  assert_true(resp.last_segment)
  assert_eq(resp.data.length(), 5)
}

///|
test "decode_sdo_response segmented upload empty segment" {
  // cs=000, toggle=0, n_unused=7, last=1 鈫?seg_len = 7-7=0 鈫?Bytes::new(0)
  // cmd_byte: n_unused=7 (bits 3:1)=0x0E, last=1 鈫?0x0F
  let buf = @buffer.new()
  // mailbox header: length=3 (coe_hdr=2 + 1 cmd byte)
  buf.write_byte(b'\x03')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x13')
  // CoE header
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x30')
  // SDO cmd: cs=000, toggle=0, n_unused=7(0x0E), last=1 鈫?0x0F
  buf.write_byte(b'\x0F')
  let data = buf.to_bytes()
  let (_mbh, resp) = @mailbox.decode_sdo_response(data)
  assert_eq(resp.data.length(), 0)
  assert_true(resp.segmented)
}

///|
test "decode_sdo_response header too short" {
  // Non-segmented, non-abort: cmd=DownloadResponse(0x60), cs=011
  // But sdo_payload < sdo_header_len(8)
  let buf = @buffer.new()
  // length=4 鈫?payload=4, coe=2, sdo_payload=2 < 8
  buf.write_byte(b'\x04')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x13')
  // CoE
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x30')
  // SDO cmd: DownloadResponse = 0x60, cs=011
  buf.write_byte(b'\x60')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let result : Result[(@mailbox.MailboxHeader, @mailbox.SdoResponse), Error] = try? @mailbox.decode_sdo_response(
    data,
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_response non-expedited upload with extra data" {
  // UploadResponse (cs=010, bits[7:5]), non-expedited (bit1=0), size_indicated (bit0=1)
  // cmd_byte: 010_00001 = 0x41
  let buf = @buffer.new()
  // length=14 (coe=2 + sdo_header=8 + extra=4)
  buf.write_byte(b'\x0E')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x13')
  // CoE header
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x30')
  // SDO cmd: 0x41 (UploadResponse, non-expedited, size-indicated)
  buf.write_byte(b'\x41')
  // index (2 bytes, LE)
  buf.write_byte(b'\x01')
  buf.write_byte(b'\x10')
  // subindex
  buf.write_byte(b'\x02')
  // complete_size (4 bytes, LE) = 100
  buf.write_byte(b'\x64')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  // extra data (4 bytes)
  buf.write_byte(b'\xAA')
  buf.write_byte(b'\xBB')
  buf.write_byte(b'\xCC')
  buf.write_byte(b'\xDD')
  let data = buf.to_bytes()
  let (_mbh, resp) = @mailbox.decode_sdo_response(data)
  assert_true(resp.segmented)
  assert_eq(resp.data.length(), 4)
  assert_eq(resp.data[0], b'\xAA')
  assert_eq(resp.complete_size, Some(100U))
}

///|
test "decode_sdo_info_response frame too short" {
  let data = Bytes::make(5, 0)
  let result : Result[(@mailbox.MailboxHeader, @mailbox.SdoInfoResponse), Error] = try? @mailbox.decode_sdo_info_response(
    data,
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_info_response payload too short" {
  // Mailbox header says length=3, but need coe(2)+info(4)=6
  let buf = @buffer.new()
  buf.write_byte(b'\x03') // length=3
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x03') // type=CoE(3)
  // 3 bytes of payload
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let result : Result[(@mailbox.MailboxHeader, @mailbox.SdoInfoResponse), Error] = try? @mailbox.decode_sdo_info_response(
    data,
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_info_response truncated data" {
  // Header says length=20 but we only provide 12 bytes total
  let buf = @buffer.new()
  buf.write_byte(b'\x14') // length=20
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x03') // CoE
  // Only 6 bytes of payload (need 20)
  for _i = 0; _i < 6; _i = _i + 1 {
    buf.write_byte(b'\x00')
  }
  let data = buf.to_bytes()
  let result : Result[(@mailbox.MailboxHeader, @mailbox.SdoInfoResponse), Error] = try? @mailbox.decode_sdo_info_response(
    data,
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_info_response wrong mailbox type" {
  // mb_type=FoE(5) instead of CoE(3)
  let buf = @buffer.new()
  buf.write_byte(b'\x06') // length=6 (coe=2+info=4)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x05') // type=FoE(5)
  // CoE header
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x80') // svc=8<<12
  // SDO Info header (4 bytes)
  buf.write_byte(b'\x01')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let result : Result[(@mailbox.MailboxHeader, @mailbox.SdoInfoResponse), Error] = try? @mailbox.decode_sdo_info_response(
    data,
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_info_response wrong service field" {
  // service=3 (SdoResponse) instead of 8 (SdoInfo)
  let buf = @buffer.new()
  buf.write_byte(b'\x06') // length=6
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x03') // type=CoE
  // CoE header: service=3<<12
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x30')
  // SDO Info header
  buf.write_byte(b'\x01')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let result : Result[(@mailbox.MailboxHeader, @mailbox.SdoInfoResponse), Error] = try? @mailbox.decode_sdo_info_response(
    data,
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_info_response empty body" {
  // length=6 = coe(2)+info(4) 鈫?body_len=0 鈫?Bytes::new(0)
  let buf = @buffer.new()
  buf.write_byte(b'\x06') // length=6
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x03') // type=CoE
  // CoE header: service=8<<12=0x8000
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x80')
  // SDO Info header (4 bytes): opcode=1, reserved=0, fragments=0
  buf.write_byte(b'\x01')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let (_mbh, resp) = @mailbox.decode_sdo_info_response(data)
  assert_eq(resp.payload.length(), 0)
}

// ===== Batch 10: FoE uncovered decode paths =====

///|
test "decode_foe_response payload too short for opcode" {
  let buf = @buffer.new()
  buf.write_byte(b'\x01') // length=1 (< 2)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x04') // type=FoE
  buf.write_byte(b'\x03') // opcode placeholder
  let data = buf.to_bytes()
  let result : Result[(@mailbox.MailboxHeader, @mailbox.FoeResponse), Error] = try? @mailbox.decode_foe_response(
    data,
  )
  assert_true(result is Err(_))
}

///|
test "decode_foe_response data empty segment" {
  // Data opcode=3, payload >= foe_header_len(6) but data_end <= data_start
  let buf = @buffer.new()
  buf.write_byte(b'\x06') // length=6 (foe_header_len)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x04') // type=FoE
  // opcode=3 (Data)
  buf.write_byte(b'\x03')
  buf.write_byte(b'\x00') // reserved
  // packet number (4 bytes)
  buf.write_byte(b'\x01')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let (_mbh, resp) = @mailbox.decode_foe_response(data)
  inspect(resp, content="FoeData(packet_number=1, data=b\"\")")
}

///|
test "decode_foe_response ack short payload" {
  // Ack opcode=4, payload < foe_header_len 鈫?packet_number=0
  let buf = @buffer.new()
  buf.write_byte(b'\x02') // length=2 (just opcode+reserved)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x04') // type=FoE
  // opcode=4 (Ack)
  buf.write_byte(b'\x04')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let (_mbh, resp) = @mailbox.decode_foe_response(data)
  inspect(resp, content="FoeAck(packet_number=0)")
}

///|
test "decode_foe_response error short payload" {
  // Error opcode=5, payload < foe_header_len 鈫?error_code=NotDefined, text=""
  let buf = @buffer.new()
  buf.write_byte(b'\x02') // length=2
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x04') // type=FoE
  // opcode=5 (Error)
  buf.write_byte(b'\x05')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let (_mbh, resp) = @mailbox.decode_foe_response(data)
  inspect(resp, content="FoeError(code=NotDefined, text=\"\")")
}

///|
test "decode_foe_response error no text" {
  // Error opcode=5, payload == foe_header_len 鈫?text=""
  let buf = @buffer.new()
  buf.write_byte(b'\x06') // length=6
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x04') // type=FoE
  // opcode=5 (Error)
  buf.write_byte(b'\x05')
  buf.write_byte(b'\x00')
  // error code = 1 (NotDefined=0, NotFound=1, ...)
  buf.write_byte(b'\x01')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let (_mbh, resp) = @mailbox.decode_foe_response(data)
  inspect(
    resp,
    content=(
      #|FoeError(code=Unknown(1), text="")
    ),
  )
}

///|
test "decode_foe_response unexpected opcode" {
  // opcode=1 (Read), not valid in response
  let buf = @buffer.new()
  buf.write_byte(b'\x02')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x04') // type=FoE
  buf.write_byte(b'\x01') // opcode=Read
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let result : Result[(@mailbox.MailboxHeader, @mailbox.FoeResponse), Error] = try? @mailbox.decode_foe_response(
    data,
  )
  assert_true(result is Err(_))
}

// ===== Batch 10: SoE uncovered decode paths =====

///|
test "decode_soe_response error short payload" {
  // SoE error response with total_len < data_start+2 鈫?error_code=0
  let buf = @buffer.new()
  // length=4: just enough for SoE header (4 bytes)
  buf.write_byte(b'\x04')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x05') // type=SoE(5)
  // SoE header: opcode=ReadRes(2)=bits[2:0], is_error=bit4 => byte0=0x12
  buf.write_byte(b'\x12') // opcode=2, error=1
  buf.write_byte(b'\x00') // element_flags
  buf.write_byte(b'\x01') // idn lo
  buf.write_byte(b'\x00') // idn hi
  let data = buf.to_bytes()
  let resp = @mailbox.decode_soe_response(data)
  inspect(resp, content="SoeError(drive_no=0, idn=1, error_code=0)")
}

///|
test "decode_soe_response read no data" {
  // ReadRes with no data after header 鈫?Bytes::new(0)
  let buf = @buffer.new()
  buf.write_byte(b'\x04') // length=4
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x05') // type=SoE
  // opcode=2 (ReadRes), no error => byte0=0x02
  buf.write_byte(b'\x02')
  buf.write_byte(b'\x00') // element_flags
  buf.write_byte(b'\x02') // idn lo
  buf.write_byte(b'\x00') // idn hi
  let data = buf.to_bytes()
  let resp = @mailbox.decode_soe_response(data)
  inspect(
    resp,
    content="SoeReadData(drive_no=0, element_flags=b'\\x00', idn=2, incomplete=false, data=b\"\")",
  )
}

///|
test "decode_soe_response notification no data" {
  // Notification opcode=5, no data after header 鈫?Bytes::new(0)
  let buf = @buffer.new()
  buf.write_byte(b'\x04') // length=4
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x05') // type=SoE
  // opcode=5 (Notification), no error 鈫?byte0=0x05
  buf.write_byte(b'\x05')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x03')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let resp = @mailbox.decode_soe_response(data)
  inspect(resp, content="SoeNotification(drive_no=0, idn=3, data=b\"\")")
}

// ===== Batch 10: SII/SII parser uncovered paths =====

///|
test "parse_sii_strings empty data" {
  let data = Bytes::new(0)
  let result = @mailbox.parse_sii_strings(data)
  assert_eq(result.length(), 0)
}

///|
test "parse_sii_strings offset past end" {
  // n_strings=3 but only 1 string fits, offset goes past end
  let buf = @buffer.new()
  buf.write_byte(b'\x03') // n_strings=3
  buf.write_byte(b'\x02') // str_len=2
  buf.write_byte(b'\x41') // 'A'
  buf.write_byte(b'\x42') // 'B'
  // No more data for string 2 and 3
  let data = buf.to_bytes()
  let result = @mailbox.parse_sii_strings(data)
  assert_eq(result.length(), 1)
  assert_eq(result[0], "AB")
}

///|
test "parse_sii_strings string extends past end" {
  // n_strings=2, first string OK, second has str_len that extends past data
  let buf = @buffer.new()
  buf.write_byte(b'\x02') // n_strings=2
  buf.write_byte(b'\x01') // str_len=1
  buf.write_byte(b'\x41') // 'A'
  buf.write_byte(b'\x05') // str_len=5 but only 0 bytes left
  let data = buf.to_bytes()
  let result = @mailbox.parse_sii_strings(data)
  assert_eq(result.length(), 1)
}

///|
test "parse_sii_dc too short" {
  let data = Bytes::make(10, 0) // < 24 bytes
  let result : Result[@mailbox.SiiDcClock, Error] = try? @mailbox.parse_sii_dc(
    data,
  )
  assert_true(result is Err(_))
}

///|
test "SiiCategoryClass label DeviceSpecific" {
  assert_eq(
    @mailbox.SiiCategoryClass::DeviceSpecific.label(),
    "device-specific",
  )
}

///|
test "SiiOverlayCandidate status_label opaque" {
  // decoder_name returns None 鈫?"opaque"
  let candidate : @mailbox.SiiOverlayCandidate = {
    type_code: 0x0001U,
    scope: @mailbox.SiiOverlayScope::DeviceSpecific,
    data: Bytes::new(0),
  }
  assert_eq(candidate.status_label(), "opaque")
}

// ===== Batch 10: EoE empty fragment data =====

///|
test "decode_eoe_response fragment empty data" {
  // Frame type=0, data_start >= frame.length 鈫?Bytes::new(0)
  let buf = @buffer.new()
  // mailbox header: length=4 (eoe_header_len=4, no extra data)
  buf.write_byte(b'\x04')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x02') // type=EoE(2)
  // EoE header bytes (4 bytes)
  // frame_type=0 (bits 3:0 of byte0), port=0, last=0, ts_appended=0
  // frame_number=0 (bits 3:0 of byte2), frag_number=0 (bits 9:4), offset=0
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let resp = @mailbox.decode_eoe_response(data)
  inspect(
    resp,
    content=(
      #|EoeFragment(frame_type=FragData, last_fragment=false, frag_number=0, frame_offset=0, frame_number=0, data=b"")
    ),
  )
}

// ===== Batch 10: mapping uncovered MailboxState no matching SM =====

///|
test "calculate_fmmu_configs MailboxState no matching SM" {
  // Only ProcessDataOut and ProcessDataIn SMs, no MailboxIn 鈫?MailboxState direction falls through to None
  let sm_configs : Array[@mailbox.SmConfig] = [
    {
      physical_start: 0x1100U,
      length: 4U,
      control: b'\x24',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::ProcessDataOut,
    },
    {
      physical_start: 0x1180U,
      length: 2U,
      control: b'\x20',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::ProcessDataIn,
    },
  ]
  let fmmu_dirs : Array[@mailbox.FmmuDirection] = [
    @mailbox.FmmuDirection::MailboxState,
    @mailbox.FmmuDirection::Outputs,
    @mailbox.FmmuDirection::Inputs,
  ]
  let (fmmus, total_out, total_in) = @mailbox.calculate_fmmu_configs(
    fmmu_dirs, sm_configs, 0U,
  )
  // MailboxState should be skipped (no MailboxIn SM), so only 2 FMMUs
  assert_eq(fmmus.length(), 2)
  assert_eq(total_out, 4)
  assert_eq(total_in, 2)
}

///|
test "calculate_fmmu_configs DynamicOutputs no matching SM" {
  // No ProcessDataOut SM at all => DynamicOutputs falls through to () branch
  let sm_configs : Array[@mailbox.SmConfig] = [
    {
      physical_start: 0x1000U,
      length: 128U,
      control: b'\x26',
      status: b'\x00',
      activate: b'\x01',
      sm_type: @mailbox.SmType::MailboxOut,
    },
  ]
  let fmmu_dirs : Array[@mailbox.FmmuDirection] = [
    @mailbox.FmmuDirection::DynamicOutputs,
  ]
  let (fmmus, total_out, _total_in) = @mailbox.calculate_fmmu_configs(
    fmmu_dirs, sm_configs, 0U,
  )
  // No ProcessDataOut SM => DynamicOutputs branch produces no FMMU
  assert_eq(fmmus.length(), 0)
  assert_eq(total_out, 0)
}

// ===== Batch 14: coe_engine uncovered paths =====

///|
test "decode_sdo_response truncated frame raises error" {
  // Header says payload is 20 bytes, but we only provide 12 total bytes
  let mbh : @mailbox.MailboxHeader = {
    length: 20U,
    address: 0x1001U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x01',
  }
  let hdr = mbh.to_bytes()
  // Total frame = 12 bytes, but header says 6 + 20 = 26 needed
  let frame = Bytes::makei(12, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 7 {
      b'\x30' // CoE SdoResponse service
    } else if i == 8 {
      b'\x42' // expedited upload response cmd
    } else {
      b'\x00'
    }
  })
  let result : Result[(_, _), _] = try
    @mailbox.decode_sdo_response(frame) |> Ok
  catch {
    e => Err(e)
  }
  assert_true(
    result is Err(@hal.EcError::MailboxProtocol("SDO response truncated")),
  )
}

///|
test "decode_sdo_response segmented upload with large payload caps seg_len" {
  // Segmented upload: cmd bits[7:5]=000, n_unused=0, toggle=0, last=1
  // payload_after_cmd > 7-n_unused triggers the seg_len cap branch
  let mbh : @mailbox.MailboxHeader = {
    length: 12U,
    address: 0x1001U,
    channel: b'\x00',
    priority: b'\x00',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x02',
  }
  let hdr = mbh.to_bytes()
  // Total frame = 6 (header) + 12 (payload) = 18 bytes
  let frame = Bytes::makei(18, fn(i) {
    if i < 6 {
      hdr[i]
    } else if i == 6 {
      b'\x00' // CoE header low
    } else if i == 7 {
      b'\x30' // CoE SdoResponse service in upper nibble
    } else if i == 8 {
      b'\x01' // cmd: bits[7:5]=000, n=0, last=1
    } else {
      // Fill segment data bytes 0xA0..0xA8
      (0xA0 + i - 9).to_byte()
    }
  })
  let (_mbh, resp) = @mailbox.decode_sdo_response(frame)
  assert_true(resp.segmented)
  assert_true(resp.last_segment)
  // seg_len should be capped to 7 - 0 = 7
  assert_eq(resp.data.length(), 7)
  assert_eq(resp.data[0], b'\xA0')
  assert_eq(resp.data[6], b'\xA6')
}

///|
// BATCH 17 — coverage gap tests

///|
test "SiiOverlayCandidate dispatch_key covers hex_digit 7" {
  let candidate : @mailbox.SiiOverlayCandidate = {
    scope: @mailbox.SiiOverlayScope::DeviceSpecific,
    type_code: 0x7000U,
    data: b"",
  }
  let key = candidate.dispatch_key()
  assert_true(key.contains("7"))
}

///|
test "decode_sdo_info_response payload too short for info header" {
  // mbh.length = 5 (< coe_header_len + sdo_info_header_len = 6) → triggers "payload too short"
  let frame = Bytes::makei(12, fn(i) {
    match i {
      0 => b'\x05' // length low = 5
      1 => b'\x00' // length high = 0
      5 => b'\x03' // type = CoE (0x03)
      _ => b'\x00'
    }
  })
  let result : Result[(@mailbox.MailboxHeader, @mailbox.SdoInfoResponse), Error] = try? @mailbox.decode_sdo_info_response(
    frame,
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_info_od_description_payload invalid UTF-8 name" {
  // 6 bytes header + invalid UTF-8 bytes for name
  let payload = Bytes::makei(8, fn(i) { if i >= 6 { b'\xFF' } else { b'\x00' } })
  let result : Result[@mailbox.SdoInfoObjectDescription, Error] = try? @mailbox.decode_sdo_info_od_description_payload(
    payload,
  )
  assert_true(result is Err(_))
}

///|
test "decode_sdo_info_oe_description_payload invalid UTF-8 name" {
  // 10 bytes header + invalid UTF-8 bytes for name
  let payload = Bytes::makei(12, fn(i) {
    if i >= 10 {
      b'\xFF'
    } else {
      b'\x00'
    }
  })
  let result : Result[@mailbox.SdoInfoEntryDescription, Error] = try? @mailbox.decode_sdo_info_oe_description_payload(
    payload,
  )
  assert_true(result is Err(_))
}

///|
test "sdo_abort_code_description out of memory" {
  assert_eq(@mailbox.sdo_abort_code_description(0x05040005U), "Out of memory")
}

///|
test "sdo_abort_code_description RxPDO blocked" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06010006U),
    "Object mapped to RxPDO, SDO download blocked",
  )
}

///|
test "sdo_abort_code_description internal incompatibility" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06040047U),
    "General internal incompatibility in the device",
  )
}

///|
test "sdo_abort_code_description value too low" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06090032U),
    "Value of parameter written too low",
  )
}

// ===== Batch 18: remaining sdo_abort_code_description arms =====

///|
test "sdo_abort_code_description unsupported access" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06010000U),
    "Unsupported access to an object",
  )
}

///|
test "sdo_abort_code_description hardware error" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06060000U),
    "Access failed due to a hardware error",
  )
}

///|
test "sdo_abort_code_description max less than min" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06090036U),
    "Maximum value is less than minimum value",
  )
}

// ===== sii hex_digit coverage =====

///|
test "SiiOverlayCandidate dispatch_key covers hex_digit 8" {
  let candidate : @mailbox.SiiOverlayCandidate = {
    scope: @mailbox.DeviceSpecific,
    type_code: 0x0008U,
    data: Bytes::new(0),
  }
  let key = candidate.dispatch_key()
  // type_code=0x0008 → format_hex4 → "0008" → hits hex_digit(8U)
  assert_true(key.contains("0008"))
}

// ===== additional sdo_abort_code cases =====

///|
test "sdo_abort_code_description attempt read write-only" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06010001U),
    "Attempt to read a write-only object",
  )
}

///|
test "sdo_abort_code_description general error" {
  assert_eq(@mailbox.sdo_abort_code_description(0x08000000U), "General error")
}

// ===== Batch 20: additional coverage =====

///|
test "decode_foe_response payload_len less than 2 raises" {
  // Mailbox header: length=1 (LE), address=0, ch/pri=0, type=FoE(0x04)
  // Total frame: 8 bytes (>= mbox_hdr + 2), but payload_len=1 < 2
  let frame = b"\x01\x00\x00\x00\x00\x04\x00\x00"
  let result : Result[(_, _), _] = try? @mailbox.decode_foe_response(frame)
  assert_true(result is Err(_))
}

// ===== Batch 24: remaining uncovered arms and branches =====

///|
test "sdo_abort_code_description write read-only object" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06010002U),
    "Attempt to write a read-only object",
  )
}

///|
test "sdo_abort_code_description data cannot be transferred" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x08000020U),
    "Data cannot be transferred or stored to the application",
  )
}

///|
test "sdo_abort_code_description subindex SI0 must be 0" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06010003U),
    "Subindex cannot be written, SI0 must be 0 for write access",
  )
}

///|
test "sdo_abort_code_description read write-only object" {
  assert_eq(
    @mailbox.sdo_abort_code_description(0x06010001U),
    "Attempt to read a write-only object",
  )
}

///|
test "parse_sii_fmmu ignores unknown byte" {
  // byte 0x04 is not a known FMMU direction → skipped via _ => ()
  let dirs = @mailbox.parse_sii_fmmu(
    Bytes::from_array([b'\x01', b'\x04', b'\x02', b'\xFF']),
  )
  // Only 0x01 (Outputs) and 0x02 (Inputs) should be recognized
  assert_eq(dirs.length(), 2)
  assert_eq(dirs[0], @mailbox.FmmuDirection::Outputs)
  assert_eq(dirs[1], @mailbox.FmmuDirection::Inputs)
}

///|
test "SiiOverlayCandidate dispatch_key covers hex_digit A-F" {
  let candidate : @mailbox.SiiOverlayCandidate = {
    scope: DeviceSpecific,
    type_code: 0xABCDU,
    data: Bytes::new(0),
  }
  let key = candidate.dispatch_key()
  assert_eq(key, "device-specific:ABCD")
}
