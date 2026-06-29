///|
/// NodeIdentityEvidence records the stable identity fields that tie ESI/SII
/// projections and virtual slaves to the same EtherCAT node.
pub(all) struct NodeIdentityEvidence {
  vendor_id : UInt
  product_code : UInt
  revision : UInt
  serial : UInt
} derive(Eq, Debug)

///|
pub(all) struct NodeModelEvidence {
  identity : NodeIdentityEvidence
  device_name : String
  type_name : String
  profile_no : UInt?
  ds402_profile_hint : Bool
  sii_word_count : Int
  sii_eeprom_bytes : Int
  sync_manager_count : Int
  fmmu_count : Int
  rx_pdo_count : Int
  tx_pdo_count : Int
  output_bytes : Int
  input_bytes : Int
  virtual_slave_template_available : Bool
  source : String
} derive(Eq, Debug)

///|
pub fn NodeModelEvidence::make(
  identity~ : NodeIdentityEvidence,
  device_name~ : String,
  type_name~ : String,
  profile_no~ : UInt?,
  ds402_profile_hint~ : Bool,
  sii_word_count~ : Int,
  sii_eeprom_bytes~ : Int,
  sync_manager_count~ : Int,
  fmmu_count~ : Int,
  rx_pdo_count~ : Int,
  tx_pdo_count~ : Int,
  output_bytes~ : Int,
  input_bytes~ : Int,
  virtual_slave_template_available~ : Bool,
  source~ : String,
) -> NodeModelEvidence {
  {
    identity,
    device_name,
    type_name,
    profile_no,
    ds402_profile_hint,
    sii_word_count,
    sii_eeprom_bytes,
    sync_manager_count,
    fmmu_count,
    rx_pdo_count,
    tx_pdo_count,
    output_bytes,
    input_bytes,
    virtual_slave_template_available,
    source,
  }
}

///|
pub fn node_model_evidence_from_esi_device(
  device : @runtime.EsiJsonDevice,
  mapping : @mailbox.SlaveMapping,
) -> NodeModelEvidence {
  NodeModelEvidence::make(
    identity={
      vendor_id: device.vendor_id,
      product_code: device.product_code,
      revision: device.revision,
      serial: device.serial,
    },
    device_name=device.device_name,
    type_name=device.type_name,
    profile_no=device.profile_no,
    ds402_profile_hint=device.profile_no == Some(402U),
    sii_word_count=0,
    sii_eeprom_bytes=device.eeprom_byte_size.reinterpret_as_int(),
    sync_manager_count=device.sync_managers.length(),
    fmmu_count=device.fmmu.length(),
    rx_pdo_count=device.rx_pdos.length(),
    tx_pdo_count=device.tx_pdos.length(),
    output_bytes=mapping.output_bytes,
    input_bytes=mapping.input_bytes,
    virtual_slave_template_available=false,
    source="runtime/EsiJsonDevice + mailbox/SlaveMapping",
  )
}

///|
pub fn node_model_evidence_from_virtual_slave_template(
  template : @mock.VirtualSlaveTemplate,
  device_name~ : String,
  type_name~ : String,
  profile_no~ : UInt?,
) -> NodeModelEvidence {
  let preparation = template.startup_preparation
  let sii = preparation.sii
  let mapping = preparation.mapping
  NodeModelEvidence::make(
    identity={
      vendor_id: template.identity.vendor_id,
      product_code: template.identity.product_code,
      revision: template.identity.revision,
      serial: template.identity.serial,
    },
    device_name~,
    type_name~,
    profile_no~,
    ds402_profile_hint=profile_no == Some(402U),
    sii_word_count=template.sii_eeprom.length() / 2,
    sii_eeprom_bytes=template.sii_eeprom.length(),
    sync_manager_count=sii.sync_managers.length(),
    fmmu_count=sii.fmmu.length(),
    rx_pdo_count=sii.rx_pdo.length(),
    tx_pdo_count=sii.tx_pdo.length(),
    output_bytes=mapping.output_bytes,
    input_bytes=mapping.input_bytes,
    virtual_slave_template_available=true,
    source="hal/mock/VirtualSlaveTemplate + runtime/SlaveStartupPreparation",
  )
}

///|
pub(all) enum ObjectEvidenceChannel {
  EsiRxPdo
  EsiTxPdo
  SiiRxPdo
  SiiTxPdo
  StartupSdo
  VirtualOd
} derive(Eq, Debug)

///|
pub fn object_evidence_channel_label(channel : ObjectEvidenceChannel) -> String {
  match channel {
    EsiRxPdo => "esi.rxpdo"
    EsiTxPdo => "esi.txpdo"
    SiiRxPdo => "sii.rxpdo"
    SiiTxPdo => "sii.txpdo"
    StartupSdo => "startup.sdo"
    VirtualOd => "virtual.od"
  }
}

///|
pub(all) struct ObjectBindingEvidence {
  object_index : UInt
  subindex : Byte
  bit_length : Int
  byte_offset : Int
  bit_offset : Int
  channel : ObjectEvidenceChannel
  source_path : String
  object_name : String
  data_type_name : String
  profile_hint : String?
} derive(Eq, Debug)

///|
pub fn ds402_object_hint(index : UInt) -> String? {
  match index {
    0x603FU => Some("ds402.error_code")
    0x6040U => Some("ds402.controlword")
    0x6041U => Some("ds402.statusword")
    0x6060U => Some("ds402.mode")
    0x6061U => Some("ds402.mode_display")
    0x6064U => Some("ds402.actual_position")
    0x607AU => Some("ds402.target_position")
    _ => None
  }
}

///|
pub fn object_bindings_from_esi_device(
  device : @runtime.EsiJsonDevice,
) -> Array[ObjectBindingEvidence] {
  let result : Array[ObjectBindingEvidence] = []
  push_esi_pdo_bindings(result, device.rx_pdos, EsiRxPdo, "esi.rx_pdos")
  push_esi_pdo_bindings(result, device.tx_pdos, EsiTxPdo, "esi.tx_pdos")
  result
}

///|
fn push_esi_pdo_bindings(
  result : Array[ObjectBindingEvidence],
  pdos : Array[@runtime.EsiJsonPdo],
  channel : ObjectEvidenceChannel,
  source_prefix : String,
) -> Unit {
  let mut total_bits = 0
  for pdo_index, pdo in pdos {
    for entry_index, entry in pdo.entries {
      result.push({
        object_index: entry.base_index,
        subindex: entry.subindex,
        bit_length: entry.bit_length.to_int(),
        byte_offset: total_bits / 8,
        bit_offset: total_bits % 8,
        channel,
        source_path: source_prefix +
        "[" +
        pdo_index.to_string() +
        "].entries[" +
        entry_index.to_string() +
        "]",
        object_name: entry.name,
        data_type_name: entry.data_type_name,
        profile_hint: ds402_object_hint(entry.base_index),
      })
      total_bits = total_bits + entry.bit_length.to_int()
    }
  }
}

///|
pub fn object_bindings_from_sii_pdos(
  rx_pdos : Array[@mailbox.SiiPdo],
  tx_pdos : Array[@mailbox.SiiPdo],
) -> Array[ObjectBindingEvidence] {
  let result : Array[ObjectBindingEvidence] = []
  push_sii_pdo_bindings(result, rx_pdos, SiiRxPdo, "sii.rx_pdo")
  push_sii_pdo_bindings(result, tx_pdos, SiiTxPdo, "sii.tx_pdo")
  result
}

///|
fn push_sii_pdo_bindings(
  result : Array[ObjectBindingEvidence],
  pdos : Array[@mailbox.SiiPdo],
  channel : ObjectEvidenceChannel,
  source_prefix : String,
) -> Unit {
  let mut total_bits = 0
  for pdo_index, pdo in pdos {
    for entry_index, entry in pdo.entries {
      result.push({
        object_index: entry.entry_index,
        subindex: entry.subindex,
        bit_length: entry.bit_length.to_int(),
        byte_offset: total_bits / 8,
        bit_offset: total_bits % 8,
        channel,
        source_path: source_prefix +
        "[" +
        pdo_index.to_string() +
        "].entries[" +
        entry_index.to_string() +
        "]",
        object_name: "sii.name_idx." + entry.name_idx.to_int().to_string(),
        data_type_name: "sii.data_type." + entry.data_type.to_int().to_string(),
        profile_hint: ds402_object_hint(entry.entry_index),
      })
      total_bits = total_bits + entry.bit_length.to_int()
    }
  }
}

///|
pub(all) struct StartupObjectCommandEvidence {
  transition : @runtime.StartupCommandTransition
  transition_label : String
  object_index : UInt
  subindex : Byte
  data_length : Int
  channel : ObjectEvidenceChannel
  profile_hint : String?
  source : String
} derive(Eq, Debug)

///|
pub fn startup_transition_label(
  transition : @runtime.StartupCommandTransition,
) -> String {
  match transition {
    InitToPreOp => "init_to_preop"
    InitToBoot => "init_to_boot"
    PreOpToInit => "preop_to_init"
    PreOpToSafeOp => "preop_to_safeop"
    SafeOpToInit => "safeop_to_init"
    SafeOpToPreOp => "safeop_to_preop"
    SafeOpToOp => "safeop_to_op"
    OpToInit => "op_to_init"
    OpToPreOp => "op_to_preop"
    OpToSafeOp => "op_to_safeop"
    BootToInit => "boot_to_init"
  }
}

///|
pub fn startup_object_commands_from_runtime(
  commands : Array[@runtime.StartupMailboxCommand],
) -> Array[StartupObjectCommandEvidence] {
  let result : Array[StartupObjectCommandEvidence] = []
  for command in commands {
    result.push({
      transition: command.transition,
      transition_label: startup_transition_label(command.transition),
      object_index: command.index,
      subindex: command.subindex,
      data_length: command.data.length(),
      channel: StartupSdo,
      profile_hint: ds402_object_hint(command.index),
      source: "runtime/StartupMailboxCommand",
    })
  }
  result
}

///|
pub(all) struct VirtualObjectDictionaryEvidence {
  object_index : UInt
  subindex : Byte
  data_length : Int
  access_label : String
  channel : ObjectEvidenceChannel
  profile_hint : String?
  source : String
} derive(Eq, Debug)

///|
pub fn od_access_label(access : @mock.OdAccess) -> String {
  match access {
    @mock.ReadOnly => "read_only"
    @mock.ReadWrite => "read_write"
    @mock.WriteOnly => "write_only"
  }
}

///|
pub fn virtual_od_evidence(
  mailbox : @mock.VirtualMailbox,
) -> Array[VirtualObjectDictionaryEvidence] {
  let result : Array[VirtualObjectDictionaryEvidence] = []
  for entry in mailbox.od {
    result.push({
      object_index: entry.index,
      subindex: entry.subindex,
      data_length: entry.data.length(),
      access_label: od_access_label(entry.access),
      channel: VirtualOd,
      profile_hint: ds402_object_hint(entry.index),
      source: "hal/mock/VirtualMailbox.od",
    })
  }
  result
}

///|
pub(all) struct NodeObjectEvidenceReport {
  report_version : String
  node_model : NodeModelEvidence
  object_bindings : Array[ObjectBindingEvidence]
  startup_commands : Array[StartupObjectCommandEvidence]
  virtual_od : Array[VirtualObjectDictionaryEvidence]
  live_claimed : Bool
} derive(Eq, Debug)

///|
pub fn NodeObjectEvidenceReport::make(
  node_model~ : NodeModelEvidence,
  object_bindings~ : Array[ObjectBindingEvidence],
  startup_commands~ : Array[StartupObjectCommandEvidence],
  virtual_od~ : Array[VirtualObjectDictionaryEvidence],
) -> NodeObjectEvidenceReport {
  {
    report_version: "node-object-evidence-v1",
    node_model,
    object_bindings,
    startup_commands,
    virtual_od,
    live_claimed: false,
  }
}

///|
pub fn NodeObjectEvidenceReport::has_profile_hint(
  self : NodeObjectEvidenceReport,
  hint : String,
) -> Bool {
  self.object_bindings.iter().any(fn(item) { item.profile_hint == Some(hint) }) ||
  self.startup_commands.iter().any(fn(item) { item.profile_hint == Some(hint) }) ||
  self.virtual_od.iter().any(fn(item) { item.profile_hint == Some(hint) })
}

///|
pub fn NodeObjectEvidenceReport::covers_required_node_object_evidence(
  self : NodeObjectEvidenceReport,
) -> Bool {
  self.node_model.ds402_profile_hint &&
  self.node_model.virtual_slave_template_available &&
  self.object_bindings.length() > 0 &&
  self.has_profile_hint("ds402.controlword") &&
  self.has_profile_hint("ds402.statusword") &&
  self.startup_commands.length() > 0 &&
  self.virtual_od.length() > 0 &&
  !self.live_claimed
}

///|
pub fn NodeObjectEvidenceReport::to_node_model_section(
  self : NodeObjectEvidenceReport,
) -> @medium_evidence.MediumEvidenceSection {
  @medium_evidence.MediumEvidenceSection::make(
    stage=@medium_evidence.NodeModel,
    title="EtherCAT node model evidence",
    source="runtime/node_object_evidence + ESI/SII + hal/mock",
    summary="records device identity, profile hint, SII/ESI counts, SM/FMMU/PDO sizes, and virtual slave template availability; live_claimed=\{self.live_claimed}",
    boundary=@medium_evidence.MockSimulation,
    artifact_ref="node-object-evidence-v1",
  )
}

///|
pub fn NodeObjectEvidenceReport::to_object_binding_section(
  self : NodeObjectEvidenceReport,
) -> @medium_evidence.MediumEvidenceSection {
  @medium_evidence.MediumEvidenceSection::make(
    stage=@medium_evidence.ObjectBinding,
    title="EtherCAT object binding evidence",
    source="runtime/node_object_evidence + ESI/SII PDO + VirtualMailbox",
    summary="records object index/subindex/channel/source path/process-image offset/startup SDO/virtual OD facts without ObjectMonitor verdict; live_claimed=\{self.live_claimed}",
    boundary=@medium_evidence.StaticSchema,
    artifact_ref="node-object-evidence-v1",
  )
}
