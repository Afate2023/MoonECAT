///|
fn test_mailbox() -> @runtime.EsiJsonMailbox {
  {
    data_link_layer: false,
    aoe: false,
    coe_present: true,
    coe_sdo_info: true,
    coe_pdo_assign: true,
    coe_pdo_config: true,
    coe_complete_access: false,
    eoe: false,
    foe: false,
    soe: false,
    voe: false,
  }
}

///|
fn test_esi_entry(
  index : UInt,
  subindex : Byte,
  bits : Byte,
  name : String,
  data_type_name : String,
) -> @runtime.EsiJsonPdoEntry {
  {
    base_index: index,
    depend_on_slot_index: false,
    subindex,
    bit_length: bits,
    name,
    data_type_name,
  }
}

///|
fn test_esi_pdo(
  direction : String,
  sync_manager : Byte,
  entries : Array[@runtime.EsiJsonPdoEntry],
) -> @runtime.EsiJsonPdo {
  {
    direction,
    base_index: if direction == "rx" {
      0x1600U
    } else {
      0x1A00U
    },
    depend_on_slot_pdo: false,
    sync_manager,
    name: direction + "pdo",
    entries,
  }
}

///|
fn test_esi_device() -> @runtime.EsiJsonDevice {
  {
    vendor_id: 0x1111U,
    product_code: 0x2222U,
    revision: 0x0001U,
    serial: Some(0x0002U),
    physics: "YY",
    device_name: "MC1C servo",
    type_name: "DS402 virtual drive",
    profile_no: Some(402U),
    slot_index_increment: 0U,
    slot_pdo_increment: 0U,
    mailbox: test_mailbox(),
    fmmu: ["Outputs", "Inputs"],
    sync_managers: [
      {
        physical_start: 0x1000U,
        length: 128U,
        control: b'\x26',
        status: b'\x00',
        enable: true,
        sm_type: "MailboxOut",
      },
    ],
    dc_modes: [],
    eeprom_byte_size: 512U,
    config_data: b"",
    bootstrap: b"",
    default_modules: [],
    init_commands: [],
    rx_pdos: [
      test_esi_pdo("rx", b'\x02', [
        test_esi_entry(0x6040U, b'\x00', b'\x10', "controlword", "UINT16"),
        test_esi_entry(0x607AU, b'\x00', b'\x20', "target_position", "INT32"),
      ]),
    ],
    tx_pdos: [
      test_esi_pdo("tx", b'\x03', [
        test_esi_entry(0x6041U, b'\x00', b'\x10', "statusword", "UINT16"),
        test_esi_entry(0x6064U, b'\x00', b'\x20', "actual_position", "INT32"),
      ]),
    ],
  }
}

///|
fn test_mapping() -> @mailbox.SlaveMapping {
  { sm_configs: [], fmmu_configs: [], output_bytes: 6, input_bytes: 6 }
}

///|
fn test_sii_data() -> @mailbox.SiiData {
  {
    vendor_id: 0x1111U,
    product_code: 0x2222U,
    revision: 0x0001U,
    serial: 0x0002U,
    bootstrap_rx_offset: 0U,
    bootstrap_rx_size: 0U,
    bootstrap_tx_offset: 0U,
    bootstrap_tx_size: 0U,
    mailbox_rx_offset: 0x1000U,
    mailbox_rx_size: 128U,
    mailbox_tx_offset: 0x1080U,
    mailbox_tx_size: 128U,
    mailbox_protocols: 0x0004U,
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
}

///|
fn test_sii_sm(sm_type : @mailbox.SmType) -> @mailbox.SiiSmEntry {
  {
    physical_start: 0x1100U,
    length: 6U,
    control: b'\x24',
    status: b'\x00',
    activate: b'\x01',
    sm_type,
  }
}

///|
fn test_sii_full_info() -> @mailbox.SiiFullInfo {
  let eeprom = b"\x00\x00\x00\x00"
  {
    eeprom: eeprom[:],
    preamble: {
      pdi_control: 0U,
      pdi_config: 0U,
      sync_impulse_length_raw: 0U,
      pdi_config2: 0U,
      configured_station_alias: 0U,
      checksum: 0U,
      checksum_ok: true,
    },
    standard: { eeprom_size_raw: 3U, version: 1U },
    header: test_sii_data(),
    categories: [],
    strings: [],
    general: None,
    timeouts: None,
    fmmu: [@mailbox.Outputs, @mailbox.Inputs],
    fmmu_ex: [],
    sync_managers: [
      test_sii_sm(@mailbox.ProcessDataOut),
      test_sii_sm(@mailbox.ProcessDataIn),
    ],
    sync_units: [],
    tx_pdo: [
      test_sii_pdo(0x1A00U, b'\x03', [test_sii_entry(0x6041U, b'\x00', b'\x10')]),
    ],
    rx_pdo: [
      test_sii_pdo(0x1600U, b'\x02', [test_sii_entry(0x6040U, b'\x00', b'\x10')]),
    ],
    dc_clocks: [],
  }
}

///|
fn test_startup_preparation() -> @runtime.SlaveStartupPreparation {
  {
    mapping: test_mapping(),
    dc_cycle_period_ns: None,
    startup_outputs: None,
    startup_mailbox_commands: [
      {
        transition: @runtime.SafeOpToOp,
        index: 0x6060U,
        subindex: b'\x00',
        data: b"\x08",
      },
    ],
    mailbox_config: {
      out_address: 0x1000U,
      out_size: 128U,
      out_sm_index: 0,
      in_address: 0x1080U,
      in_size: 128U,
      in_sm_index: 1,
    },
    sii: test_sii_full_info(),
    sii_categories: [],
    prefer_live_pdo_state: false,
  }
}

///|
fn test_virtual_template() -> @mock.VirtualSlaveTemplate {
  {
    identity: {
      vendor_id: 0x1111U,
      product_code: 0x2222U,
      revision: 0x0001U,
      serial: 0x0002U,
    },
    sii_eeprom: b"\x00\x00\x00\x00",
    startup_preparation: test_startup_preparation(),
  }
}

///|
fn test_sii_entry(
  index : UInt,
  subindex : Byte,
  bits : Byte,
) -> @mailbox.SiiPdoEntry {
  {
    entry_index: index,
    subindex,
    name_idx: b'\x01',
    data_type: b'\x05',
    bit_length: bits,
    flags: 0U,
  }
}

///|
fn test_sii_pdo(
  pdo_index : UInt,
  sync_manager : Byte,
  entries : Array[@mailbox.SiiPdoEntry],
) -> @mailbox.SiiPdo {
  {
    pdo_index,
    entry_count: entries.length().to_byte(),
    sync_manager,
    synchronization: b'\x00',
    name_idx: b'\x01',
    flags: 0U,
    entries,
  }
}

///|
test "ESI node and object evidence preserves DS402 identity and offsets" {
  let device = test_esi_device()
  let node = node_model_evidence_from_esi_device(device, test_mapping())
  @debug.assert_eq(node.identity.vendor_id, 0x1111U)
  @debug.assert_eq(node.profile_no, Some(402U))
  assert_true(node.ds402_profile_hint)
  @debug.assert_eq(node.output_bytes, 6)
  @debug.assert_eq(node.input_bytes, 6)
  @debug.assert_eq(node.rx_pdo_count, 1)
  @debug.assert_eq(node.tx_pdo_count, 1)
  let template_node = node_model_evidence_from_virtual_slave_template(
    test_virtual_template(),
    device_name=device.device_name,
    type_name=device.type_name,
    profile_no=device.profile_no,
  )
  assert_true(template_node.virtual_slave_template_available)
  @debug.assert_eq(template_node.sync_manager_count, 2)
  @debug.assert_eq(template_node.fmmu_count, 2)

  let bindings = object_bindings_from_esi_device(device)
  @debug.assert_eq(bindings.length(), 4)
  @debug.assert_eq(bindings[0].object_index, 0x6040U)
  @debug.assert_eq(bindings[0].channel, EsiRxPdo)
  @debug.assert_eq(bindings[0].byte_offset, 0)
  @debug.assert_eq(bindings[1].object_index, 0x607AU)
  @debug.assert_eq(bindings[1].byte_offset, 2)
  @debug.assert_eq(bindings[2].object_index, 0x6041U)
  @debug.assert_eq(bindings[2].channel, EsiTxPdo)
  @debug.assert_eq(bindings[2].profile_hint, Some("ds402.statusword"))
}

///|
test "SII PDO evidence computes channel-local process image offsets" {
  let rx = [
    test_sii_pdo(0x1600U, b'\x02', [
      test_sii_entry(0x6040U, b'\x00', b'\x10'),
      test_sii_entry(0x607AU, b'\x00', b'\x20'),
    ]),
  ]
  let tx = [
    test_sii_pdo(0x1A00U, b'\x03', [
      test_sii_entry(0x6041U, b'\x00', b'\x10'),
      test_sii_entry(0x6064U, b'\x00', b'\x20'),
    ]),
  ]
  let bindings = object_bindings_from_sii_pdos(rx, tx)
  @debug.assert_eq(bindings.length(), 4)
  @debug.assert_eq(bindings[0].channel, SiiRxPdo)
  @debug.assert_eq(bindings[1].byte_offset, 2)
  @debug.assert_eq(bindings[2].channel, SiiTxPdo)
  @debug.assert_eq(bindings[3].profile_hint, Some("ds402.actual_position"))
}

///|
test "startup SDO and VirtualMailbox OD evidence keep object identity" {
  let commands : Array[@runtime.StartupMailboxCommand] = [
    {
      transition: @runtime.SafeOpToOp,
      index: 0x6060U,
      subindex: b'\x00',
      data: b"\x08",
    },
  ]
  let startup = startup_object_commands_from_runtime(commands)
  @debug.assert_eq(startup.length(), 1)
  @debug.assert_eq(startup[0].channel, StartupSdo)
  @debug.assert_eq(startup[0].transition_label, "safeop_to_op")
  @debug.assert_eq(startup[0].profile_hint, Some("ds402.mode"))

  let mailbox = @mock.VirtualMailbox::new()
  mailbox.add_od(0x6040U, b'\x00', b"\x06\x00", access=@mock.ReadWrite)
  mailbox.add_od(0x6041U, b'\x00', b"\x21\x00", access=@mock.ReadOnly)
  let od = virtual_od_evidence(mailbox)
  @debug.assert_eq(od.length(), 2)
  @debug.assert_eq(od[0].access_label, "read_write")
  @debug.assert_eq(od[1].profile_hint, Some("ds402.statusword"))
}

///|
test "node object report converts to MC1A evidence sections" {
  let device = test_esi_device()
  let node = node_model_evidence_from_virtual_slave_template(
    test_virtual_template(),
    device_name=device.device_name,
    type_name=device.type_name,
    profile_no=device.profile_no,
  )
  let commands : Array[@runtime.StartupMailboxCommand] = [
    {
      transition: @runtime.SafeOpToOp,
      index: 0x6060U,
      subindex: b'\x00',
      data: b"\x08",
    },
  ]
  let mailbox = @mock.VirtualMailbox::new()
  mailbox.add_od(0x6040U, b'\x00', b"\x06\x00", access=@mock.ReadWrite)
  let report = NodeObjectEvidenceReport::make(
    node_model=node,
    object_bindings=object_bindings_from_esi_device(device),
    startup_commands=startup_object_commands_from_runtime(commands),
    virtual_od=virtual_od_evidence(mailbox),
  )
  assert_true(report.covers_required_node_object_evidence())
  let node_section = report.to_node_model_section()
  let object_section = report.to_object_binding_section()
  @debug.assert_eq(node_section.stage, @medium_evidence.NodeModel)
  @debug.assert_eq(node_section.boundary, @medium_evidence.MockSimulation)
  @debug.assert_eq(object_section.stage, @medium_evidence.ObjectBinding)
  @debug.assert_eq(object_section.boundary, @medium_evidence.StaticSchema)
}
