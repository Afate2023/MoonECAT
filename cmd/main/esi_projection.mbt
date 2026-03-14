///|
priv enum EsiPdoKind {
  Rx
  Tx
}

///|
priv struct EsiMailboxProjection {
  data_link_layer : Bool
  coe_present : Bool
  coe_sdo_info : Bool
  coe_pdo_assign : Bool
  coe_pdo_config : Bool
  coe_complete_access : Bool
  eoe : Bool
  foe : Bool
  soe : Bool
  voe : Bool
}

///|
priv struct EsiPdoEntryProjection {
  base_index : UInt
  depend_on_slot_index : Bool
  subindex : Byte
  bit_length : Byte
  name : String
  data_type_name : String
}

///|
priv struct EsiPdoProjection {
  kind : EsiPdoKind
  base_index : UInt
  depend_on_slot_pdo : Bool
  sync_manager : Byte
  name : String
  entries : Array[EsiPdoEntryProjection]
}

///|
priv struct EsiDcProjection {
  name : String
  description : String
  assign_activate : UInt
  cycle_time_sync0 : UInt
  sync0_factor : Int
  sync1_factor : Int
}

///|
priv struct EsiSelectedModule {
  module_ident : UInt
  slot_index : Int
}

///|
priv struct EsiDeviceProjection {
  vendor_id : UInt
  product_code : UInt
  revision : UInt
  serial : UInt
  physics : String
  device_name : String
  type_name : String
  slot_index_increment : UInt
  slot_pdo_increment : UInt
  mailbox : EsiMailboxProjection
  fmmu : Array[@mailbox.FmmuDirection]
  sync_managers : Array[@mailbox.SiiSmEntry]
  dc_modes : Array[EsiDcProjection]
  eeprom_byte_size : UInt
  config_data : Bytes
  bootstrap : Bytes
  default_modules : Array[EsiSelectedModule]
  rx_pdos : Array[EsiPdoProjection]
  tx_pdos : Array[EsiPdoProjection]
}

///|
priv struct EsiModuleProjection {
  module_ident : UInt
  module_name : String
  rx_pdos : Array[EsiPdoProjection]
  tx_pdos : Array[EsiPdoProjection]
}

///|
priv struct OfflineSiiReport {
  position : UInt
  word_count : Int
  eeprom : Bytes
  preamble : @mailbox.SiiPreamble
  standard : @mailbox.SiiStandardMetadata
  header : @mailbox.SiiData
  general : @mailbox.SiiGeneral?
  strings : Array[String]
  fmmu : Array[@mailbox.FmmuDirection]
  sync_managers : Array[@mailbox.SiiSmEntry]
  dc_clocks : Array[@mailbox.SiiDcClock]
  tx_pdo : Array[@mailbox.SiiPdo]
  rx_pdo : Array[@mailbox.SiiPdo]
  categories : Array[@mailbox.SiiCategoryEntry]
}

///|
fn run_esi_sii_command(
  args : Array[String],
  as_json : Bool,
) -> Unit raise @hal.EcError {
  let xml_path = require_cli_file_flag(args, "--xml", "ESI XML")
  let device_index = require_int_flag(args, "--device-index", 0)
  if device_index < 0 {
    raise @hal.EcError::ConfigMismatch(
      "device index for --device-index must be >= 0",
    )
  }
  let xml_content = read_cli_text_file(xml_path, "ESI XML")
  let report = project_esi_xml_to_sii_report(xml_content, device_index)
  if as_json {
    println(offline_sii_json(report).stringify(indent=2))
  } else {
    println(offline_sii_text(report))
  }
}

///|
fn require_cli_file_flag(
  args : Array[String],
  flag : String,
  label : String,
) -> String raise @hal.EcError {
  match flag_value(args, flag) {
    Some(value) => value
    None =>
      raise @hal.EcError::ConfigMismatch(
        "missing required flag " + flag + " for " + label,
      )
  }
}

///|
fn read_cli_text_file(
  path : String,
  label : String,
) -> String raise @hal.EcError {
  let content_result : Result[String, Error] = try? @fs.read_file_to_string(
    path,
  )
  match content_result {
    Ok(content) => content
    Err(err) =>
      raise @hal.EcError::ConfigMismatch(
        "failed to read " + label + " file " + path + ": " + err.to_string(),
      )
  }
}

///|
fn project_esi_xml_to_sii_report(
  xml_content : String,
  device_index : Int,
) -> OfflineSiiReport raise @hal.EcError {
  let (devices, modules) = parse_esi_document_projection(xml_content)
  if device_index >= devices.length() {
    raise @hal.EcError::EsiParseFailed(
      "device index out of range: " +
      device_index.to_string() +
      " (devices=" +
      devices.length().to_string() +
      ")",
    )
  }
  build_offline_sii_report(devices[device_index], modules, device_index)
}

///|
fn offline_sii_json(report : OfflineSiiReport) -> Json {
  read_sii_json(
    report.position,
    report.word_count,
    report.preamble,
    report.standard,
    report.header,
    report.general,
    report.strings,
    report.fmmu,
    report.sync_managers,
    report.dc_clocks,
    report.tx_pdo,
    report.rx_pdo,
    report.categories,
  )
}

///|
fn offline_sii_text(report : OfflineSiiReport) -> String {
  read_sii_text(
    report.position,
    report.word_count,
    report.eeprom,
    report.preamble,
    report.standard,
    report.header,
    report.general,
    report.strings,
    report.categories,
  )
}

///|
fn parse_esi_document_projection(
  xml_content : String,
) -> (Array[EsiDeviceProjection], Array[EsiModuleProjection]) raise @hal.EcError {
  let reader = @xml.Reader::from_string(xml_content)
  let devices : Array[EsiDeviceProjection] = []
  let modules : Array[EsiModuleProjection] = []

  let mut vendor_id = 0U
  let mut in_vendor = false
  let mut in_device = false
  let mut in_module = false
  let mut in_dc_op_mode = false
  let mut current_slot_index = 0
  let mut slot_module_default = false
  let mut current_text_target : String? = None

  let mut current_device = empty_esi_device_projection()
  let mut current_module = empty_esi_module_projection()
  let mut current_sm : @mailbox.SiiSmEntry? = None
  let mut current_pdo : EsiPdoProjection? = None
  let mut current_entry : EsiPdoEntryProjection? = None
  let mut current_dc = empty_esi_dc_projection()

  while true {
    let event = reader.read_event() catch {
      err =>
        raise @hal.EcError::EsiParseFailed(
          "ESI XML parse failed: " + err.to_string(),
        )
    }
    match event {
      @xml.Start(elem) => {
        if elem.name == "Vendor" {
          in_vendor = true
          current_text_target = None
          continue
        }
        if in_vendor && elem.name == "Id" {
          current_text_target = Some("vendor-id")
          continue
        }
        if elem.name == "Device" {
          in_device = true
          current_slot_index = 0
          current_device = empty_esi_device_projection()
          current_device = {
            ..current_device,
            vendor_id,
            physics: optional_xml_attr(elem, "Physics"),
          }
          current_text_target = None
          continue
        }
        if elem.name == "Module" {
          in_module = true
          current_module = empty_esi_module_projection()
          current_text_target = None
          continue
        }

        if in_device && not(in_module) {
          match elem.name {
            "Type" =>
              current_device = {
                ..current_device,
                product_code: option_uint_or(
                  optional_numeric_xml_attr(elem, "ProductCode"),
                  current_device.product_code,
                ),
                revision: option_uint_or(
                  optional_numeric_xml_attr(elem, "RevisionNo"),
                  current_device.revision,
                ),
              }
            "Name" =>
              current_text_target = if in_dc_op_mode {
                Some("dc-name")
              } else {
                Some("device-name")
              }
            "Fmmu" => current_text_target = Some("device-fmmu")
            "Sm" => {
              current_sm = Some({
                physical_start: option_uint_or(
                  optional_numeric_xml_attr(elem, "StartAddress"),
                  0U,
                ),
                length: option_uint_or(
                  optional_numeric_xml_attr(elem, "DefaultSize"),
                  option_uint_or(optional_numeric_xml_attr(elem, "MinSize"), 0U),
                ),
                control: option_uint_or(
                  optional_numeric_xml_attr(elem, "ControlByte"),
                  0U,
                ).to_byte(),
                status: b'\x00',
                enable: optional_numeric_xml_attr(elem, "Enable") == Some(1U),
                sm_type: Unused,
              })
              current_text_target = Some("sm-kind")
            }
            "Mailbox" =>
              current_device = {
                ..current_device,
                mailbox: {
                  ..current_device.mailbox,
                  data_link_layer: optional_numeric_xml_attr(
                    elem, "DataLinkLayer",
                  ) ==
                  Some(1U),
                },
              }
            "CoE" =>
              current_device = {
                ..current_device,
                mailbox: {
                  ..current_device.mailbox,
                  coe_present: true,
                  coe_sdo_info: optional_numeric_xml_attr(elem, "SdoInfo") ==
                  Some(1U),
                  coe_pdo_assign: optional_numeric_xml_attr(elem, "PdoAssign") ==
                  Some(1U),
                  coe_pdo_config: optional_numeric_xml_attr(elem, "PdoConfig") ==
                  Some(1U),
                  coe_complete_access: optional_numeric_xml_attr(
                    elem, "CompleteAccess",
                  ) ==
                  Some(1U),
                },
              }
            "EoE" =>
              current_device = {
                ..current_device,
                mailbox: { ..current_device.mailbox, eoe: true },
              }
            "FoE" =>
              current_device = {
                ..current_device,
                mailbox: { ..current_device.mailbox, foe: true },
              }
            "SoE" =>
              current_device = {
                ..current_device,
                mailbox: { ..current_device.mailbox, soe: true },
              }
            "VoE" =>
              current_device = {
                ..current_device,
                mailbox: { ..current_device.mailbox, voe: true },
              }
            "AoE" => ()
            "Dc" => ()
            "OpMode" => {
              in_dc_op_mode = true
              current_dc = empty_esi_dc_projection()
            }
            "Desc" => current_text_target = Some("dc-desc")
            "AssignActivate" => current_text_target = Some("dc-assign-activate")
            "CycleTimeSync0" => {
              current_dc = {
                ..current_dc,
                sync0_factor: option_int_or(
                  optional_numeric_xml_attr(elem, "Factor").map(fn(value) {
                    value.reinterpret_as_int()
                  }),
                  current_dc.sync0_factor,
                ),
              }
              current_text_target = Some("dc-cycle-time-sync0")
            }
            "CycleTimeSync1" => {
              current_dc = {
                ..current_dc,
                sync1_factor: option_int_or(
                  optional_numeric_xml_attr(elem, "Factor").map(fn(value) {
                    value.reinterpret_as_int()
                  }),
                  current_dc.sync1_factor,
                ),
              }
              current_text_target = Some("dc-cycle-time-sync1")
            }
            "Slots" =>
              current_device = {
                ..current_device,
                slot_index_increment: option_uint_or(
                  optional_numeric_xml_attr(elem, "SlotIndexIncrement"),
                  current_device.slot_index_increment,
                ),
                slot_pdo_increment: option_uint_or(
                  optional_numeric_xml_attr(elem, "SlotPdoIncrement"),
                  current_device.slot_pdo_increment,
                ),
              }
            "Slot" => slot_module_default = false
            "ModuleIdent" => {
              slot_module_default = optional_numeric_xml_attr(elem, "Default") ==
                Some(1U)
              current_text_target = Some("slot-module-ident")
            }
            "Eeprom" => ()
            "ByteSize" => current_text_target = Some("eeprom-byte-size")
            "ConfigData" => current_text_target = Some("eeprom-config-data")
            "BootStrap" => current_text_target = Some("eeprom-bootstrap")
            _ => ()
          }
        }

        if in_module {
          match elem.name {
            "Type" =>
              current_module = {
                ..current_module,
                module_ident: option_uint_or(
                  optional_numeric_xml_attr(elem, "ModuleIdent"),
                  current_module.module_ident,
                ),
              }
            "Name" =>
              if current_entry is Some(_) {
                current_text_target = Some("entry-name")
              } else if current_pdo is Some(_) {
                current_text_target = Some("pdo-name")
              } else {
                current_text_target = Some("module-name")
              }
            "RxPdo" =>
              current_pdo = Some({
                ..empty_esi_pdo_projection(Rx),
                sync_manager: option_uint_or(
                  optional_numeric_xml_attr(elem, "Sm"),
                  0U,
                ).to_byte(),
              })
            "TxPdo" =>
              current_pdo = Some({
                ..empty_esi_pdo_projection(Tx),
                sync_manager: option_uint_or(
                  optional_numeric_xml_attr(elem, "Sm"),
                  0U,
                ).to_byte(),
              })
            "Index" =>
              if current_entry is Some(_) {
                current_text_target = Some("entry-index")
                match current_entry {
                  Some(entry) =>
                    current_entry = Some({
                      ..entry,
                      depend_on_slot_index: optional_bool_xml_attr(
                        elem, "DependOnSlot",
                      ),
                    })
                  None => ()
                }
              } else {
                current_text_target = Some("pdo-index")
                match current_pdo {
                  Some(pdo) =>
                    current_pdo = Some({
                      ..pdo,
                      depend_on_slot_pdo: optional_bool_xml_attr(
                        elem, "DependOnSlot",
                      ),
                    })
                  None => ()
                }
              }
            "Entry" => current_entry = Some(empty_esi_pdo_entry_projection())
            "SubIndex" => current_text_target = Some("entry-subindex")
            "BitLen" => current_text_target = Some("entry-bitlen")
            "DataType" => current_text_target = Some("entry-datatype")
            _ => ()
          }
        }
      }
      @xml.Empty(elem) =>
        if in_device && not(in_module) {
          match elem.name {
            "CoE" =>
              current_device = {
                ..current_device,
                mailbox: {
                  ..current_device.mailbox,
                  coe_present: true,
                  coe_sdo_info: optional_numeric_xml_attr(elem, "SdoInfo") ==
                  Some(1U),
                  coe_pdo_assign: optional_numeric_xml_attr(elem, "PdoAssign") ==
                  Some(1U),
                  coe_pdo_config: optional_numeric_xml_attr(elem, "PdoConfig") ==
                  Some(1U),
                  coe_complete_access: optional_numeric_xml_attr(
                    elem, "CompleteAccess",
                  ) ==
                  Some(1U),
                },
              }
            "EoE" =>
              current_device = {
                ..current_device,
                mailbox: { ..current_device.mailbox, eoe: true },
              }
            "FoE" =>
              current_device = {
                ..current_device,
                mailbox: { ..current_device.mailbox, foe: true },
              }
            "SoE" =>
              current_device = {
                ..current_device,
                mailbox: { ..current_device.mailbox, soe: true },
              }
            "VoE" =>
              current_device = {
                ..current_device,
                mailbox: { ..current_device.mailbox, voe: true },
              }
            "AoE" =>
              current_device = {
                ..current_device,
                mailbox: current_device.mailbox,
              }
            _ => ()
          }
        }
      @xml.Text(content) => {
        let text = compact_esi_xml_text(content)
        if text == "" {
          continue
        }
        match current_text_target {
          Some("vendor-id") => vendor_id = parse_esi_numeric(text, "Vendor/Id")
          Some("device-name") =>
            if current_device.device_name == "" {
              current_device = { ..current_device, device_name: text }
            }
          Some("device-fmmu") =>
            match parse_esi_fmmu_direction(text) {
              Some(direction) => current_device.fmmu.push(direction)
              None => ()
            }
          Some("sm-kind") =>
            match current_sm {
              Some(sm) =>
                current_sm = Some({ ..sm, sm_type: parse_esi_sm_type(text) })
              None => ()
            }
          Some("dc-name") => current_dc = { ..current_dc, name: text }
          Some("dc-desc") => current_dc = { ..current_dc, description: text }
          Some("dc-assign-activate") =>
            current_dc = {
              ..current_dc,
              assign_activate: parse_esi_numeric(
                text, "Device/Dc/OpMode/AssignActivate",
              ),
            }
          Some("dc-cycle-time-sync0") =>
            current_dc = {
              ..current_dc,
              cycle_time_sync0: parse_esi_numeric(
                text, "Device/Dc/OpMode/CycleTimeSync0",
              ),
            }
          Some("dc-cycle-time-sync1") =>
            current_dc = { ..current_dc, description: current_dc.description }
          Some("slot-module-ident") =>
            if slot_module_default {
              current_device.default_modules.push({
                module_ident: parse_esi_numeric(
                  text, "Device/Slots/Slot/ModuleIdent",
                ),
                slot_index: current_slot_index,
              })
            }
          Some("eeprom-byte-size") =>
            current_device = {
              ..current_device,
              eeprom_byte_size: parse_esi_numeric(
                text, "Device/Eeprom/ByteSize",
              ),
            }
          Some("eeprom-config-data") =>
            current_device = {
              ..current_device,
              config_data: parse_hex_bytes(text, "Device/Eeprom/ConfigData"),
            }
          Some("eeprom-bootstrap") =>
            current_device = {
              ..current_device,
              bootstrap: parse_hex_bytes(text, "Device/Eeprom/BootStrap"),
            }
          Some("module-name") =>
            if current_module.module_name == "" {
              current_module = { ..current_module, module_name: text }
            }
          Some("pdo-name") =>
            match current_pdo {
              Some(pdo) => current_pdo = Some({ ..pdo, name: text })
              None => ()
            }
          Some("pdo-index") =>
            match current_pdo {
              Some(pdo) =>
                current_pdo = Some({
                  ..pdo,
                  base_index: parse_esi_numeric(text, "PDO/Index"),
                })
              None => ()
            }
          Some("entry-name") =>
            match current_entry {
              Some(entry) => current_entry = Some({ ..entry, name: text })
              None => ()
            }
          Some("entry-index") =>
            match current_entry {
              Some(entry) =>
                current_entry = Some({
                  ..entry,
                  base_index: parse_esi_numeric(text, "PDO/Entry/Index"),
                })
              None => ()
            }
          Some("entry-subindex") =>
            match current_entry {
              Some(entry) =>
                current_entry = Some({
                  ..entry,
                  subindex: parse_esi_numeric(text, "PDO/Entry/SubIndex").to_byte(),
                })
              None => ()
            }
          Some("entry-bitlen") =>
            match current_entry {
              Some(entry) =>
                current_entry = Some({
                  ..entry,
                  bit_length: parse_esi_numeric(text, "PDO/Entry/BitLen").to_byte(),
                })
              None => ()
            }
          Some("entry-datatype") =>
            match current_entry {
              Some(entry) =>
                current_entry = Some({ ..entry, data_type_name: text })
              None => ()
            }
          _ => ()
        }
      }
      @xml.CData(content) => {
        let text = compact_esi_xml_text(content)
        if text != "" && current_text_target == Some("eeprom-config-data") {
          current_device = {
            ..current_device,
            config_data: parse_hex_bytes(text, "Device/Eeprom/ConfigData"),
          }
        }
      }
      @xml.End(name) =>
        match name {
          "Vendor" => in_vendor = false
          "Sm" =>
            match current_sm {
              Some(sm) => {
                current_device.sync_managers.push(sm)
                current_sm = None
              }
              None => ()
            }
          "Entry" =>
            match current_entry {
              Some(entry) => {
                match current_pdo {
                  Some(pdo) => {
                    pdo.entries.push(entry)
                    current_pdo = Some(pdo)
                  }
                  None => ()
                }
                current_entry = None
              }
              None => ()
            }
          "RxPdo" | "TxPdo" =>
            match current_pdo {
              Some(pdo) => {
                if in_module {
                  match pdo.kind {
                    Rx => current_module.rx_pdos.push(pdo)
                    Tx => current_module.tx_pdos.push(pdo)
                  }
                } else {
                  match pdo.kind {
                    Rx => current_device.rx_pdos.push(pdo)
                    Tx => current_device.tx_pdos.push(pdo)
                  }
                }
                current_pdo = None
              }
              None => ()
            }
          "OpMode" =>
            if in_dc_op_mode {
              current_device.dc_modes.push(current_dc)
              current_dc = empty_esi_dc_projection()
              in_dc_op_mode = false
            }
          "Slot" => {
            current_slot_index = current_slot_index + 1
            slot_module_default = false
          }
          "Mailbox" => ()
          "Dc" => ()
          "Eeprom" => ()
          "Device" => {
            devices.push(current_device)
            current_device = empty_esi_device_projection()
            current_sm = None
            current_pdo = None
            current_entry = None
            current_dc = empty_esi_dc_projection()
            current_text_target = None
            in_device = false
            in_dc_op_mode = false
          }
          "Module" => {
            modules.push(current_module)
            current_module = empty_esi_module_projection()
            current_pdo = None
            current_entry = None
            current_text_target = None
            in_module = false
          }
          "Id"
          | "Name"
          | "Fmmu"
          | "ModuleIdent"
          | "ByteSize"
          | "ConfigData"
          | "BootStrap"
          | "AssignActivate"
          | "CycleTimeSync0"
          | "CycleTimeSync1"
          | "Index"
          | "SubIndex"
          | "BitLen"
          | "DataType" => current_text_target = None
          _ => ()
        }
      @xml.Eof => break
      _ => ()
    }
  }

  (devices, modules)
}

///|
fn empty_esi_mailbox_projection() -> EsiMailboxProjection {
  {
    data_link_layer: false,
    coe_present: false,
    coe_sdo_info: false,
    coe_pdo_assign: false,
    coe_pdo_config: false,
    coe_complete_access: false,
    eoe: false,
    foe: false,
    soe: false,
    voe: false,
  }
}

///|
fn empty_esi_pdo_entry_projection() -> EsiPdoEntryProjection {
  {
    base_index: 0U,
    depend_on_slot_index: false,
    subindex: b'\x00',
    bit_length: b'\x00',
    name: "",
    data_type_name: "",
  }
}

///|
fn empty_esi_pdo_projection(kind : EsiPdoKind) -> EsiPdoProjection {
  {
    kind,
    base_index: 0U,
    depend_on_slot_pdo: false,
    sync_manager: b'\x00',
    name: "",
    entries: [],
  }
}

///|
fn empty_esi_dc_projection() -> EsiDcProjection {
  {
    name: "",
    description: "",
    assign_activate: 0U,
    cycle_time_sync0: 0U,
    sync0_factor: 0,
    sync1_factor: 0,
  }
}

///|
fn empty_esi_device_projection() -> EsiDeviceProjection {
  {
    vendor_id: 0U,
    product_code: 0U,
    revision: 0U,
    serial: 0U,
    physics: "",
    device_name: "",
    type_name: "",
    slot_index_increment: 0U,
    slot_pdo_increment: 0U,
    mailbox: empty_esi_mailbox_projection(),
    fmmu: [],
    sync_managers: [],
    dc_modes: [],
    eeprom_byte_size: 0U,
    config_data: b"",
    bootstrap: b"",
    default_modules: [],
    rx_pdos: [],
    tx_pdos: [],
  }
}

///|
fn empty_esi_module_projection() -> EsiModuleProjection {
  { module_ident: 0U, module_name: "", rx_pdos: [], tx_pdos: [] }
}

///|
fn option_uint_or(value : UInt?, default : UInt) -> UInt {
  match value {
    Some(actual) => actual
    None => default
  }
}

///|
fn option_int_or(value : Int?, default : Int) -> Int {
  match value {
    Some(actual) => actual
    None => default
  }
}

///|
fn optional_xml_attr(elem : @xml.XmlElement, attr_name : String) -> String {
  match elem.get(attr_name) {
    Some(value) => value
    None => ""
  }
}

///|
fn optional_numeric_xml_attr(
  elem : @xml.XmlElement,
  attr_name : String,
) -> UInt? raise @hal.EcError {
  match elem.get(attr_name) {
    Some(value) => Some(parse_esi_numeric(value, elem.name + "/@" + attr_name))
    None => None
  }
}

///|
fn compact_esi_xml_text(content : String) -> String {
  let bytes = @utf8.encode(content)
  let filtered : Array[Byte] = []
  for ch in bytes {
    if ch == b'\x00' || ch == b' ' || ch == b'\t' || ch == b'\r' || ch == b'\n' {
      continue
    }
    filtered.push(ch)
  }
  @utf8.decode(Bytes::from_array(filtered)) catch {
    _ => ""
  }
}

///|
fn parse_esi_numeric(
  text : String,
  field_name : String,
) -> UInt raise @hal.EcError {
  let bytes = @utf8.encode(text)
  let filtered : Array[Byte] = []
  for ch in bytes {
    if ch == b'\x00' || ch == b' ' || ch == b'\t' || ch == b'\r' || ch == b'\n' {
      continue
    }
    filtered.push(ch)
  }
  if filtered.length() == 0 {
    raise @hal.EcError::EsiParseFailed(
      "missing numeric ESI field at " + field_name,
    )
  }
  let mut index = 0
  let mut base = 10U
  if filtered.length() >= 2 &&
    filtered[0] == b'#' &&
    (filtered[1] == b'x' || filtered[1] == b'X') {
    base = 16U
    index = 2
  } else if filtered.length() >= 2 &&
    filtered[0] == b'0' &&
    (filtered[1] == b'x' || filtered[1] == b'X') {
    base = 16U
    index = 2
  }
  if index >= filtered.length() {
    raise @hal.EcError::EsiParseFailed(
      "invalid numeric ESI field at " + field_name + ": " + text,
    )
  }
  let mut value = 0U
  for i = index; i < filtered.length(); i = i + 1 {
    let digit = esi_digit_value(filtered[i]) catch {
      _ =>
        raise @hal.EcError::EsiParseFailed(
          "invalid numeric ESI field at " + field_name + ": " + text,
        )
    }
    if digit >= base {
      raise @hal.EcError::EsiParseFailed(
        "invalid numeric ESI field at " + field_name + ": " + text,
      )
    }
    value = value * base + digit
  }
  value
}

///|
fn esi_digit_value(ch : Byte) -> UInt raise @hal.EcError {
  if ch >= b'0' && ch <= b'9' {
    return ch.to_uint() - b'0'.to_uint()
  }
  if ch >= b'a' && ch <= b'f' {
    return 10U + (ch.to_uint() - b'a'.to_uint())
  }
  if ch >= b'A' && ch <= b'F' {
    return 10U + (ch.to_uint() - b'A'.to_uint())
  }
  raise @hal.EcError::EsiParseFailed(
    "invalid hexadecimal digit in ESI numeric field",
  )
}

///|
fn parse_hex_bytes(
  text : String,
  field_name : String,
) -> Bytes raise @hal.EcError {
  let compact = compact_esi_xml_text(text)
  if compact == "" {
    return b""
  }
  let bytes = @utf8.encode(compact)
  if bytes.length() % 2 != 0 {
    raise @hal.EcError::EsiParseFailed(
      "invalid hex byte string at " + field_name + ": odd length",
    )
  }
  let values : Array[Byte] = []
  for i = 0; i < bytes.length(); i = i + 2 {
    let high = esi_digit_value(bytes[i]) catch {
      _ =>
        raise @hal.EcError::EsiParseFailed(
          "invalid hex ESI field at " + field_name + ": " + text,
        )
    }
    let low = esi_digit_value(bytes[i + 1]) catch {
      _ =>
        raise @hal.EcError::EsiParseFailed(
          "invalid hex ESI field at " + field_name + ": " + text,
        )
    }
    values.push(((high << 4) | low).reinterpret_as_int().to_byte())
  }
  Bytes::from_array(values)
}

///|
fn parse_esi_fmmu_direction(text : String) -> @mailbox.FmmuDirection? {
  match text {
    "Outputs" => Some(Outputs)
    "Inputs" => Some(Inputs)
    "MBoxState" => Some(MailboxState)
    _ => None
  }
}

///|
fn parse_esi_sm_type(text : String) -> @mailbox.SmType {
  match text {
    "MBoxOut" => MailboxOut
    "MBoxIn" => MailboxIn
    "Outputs" => ProcessDataOut
    "Inputs" => ProcessDataIn
    _ => Unused
  }
}

///|
fn build_offline_sii_report(
  device : EsiDeviceProjection,
  modules : Array[EsiModuleProjection],
  device_index : Int,
) -> OfflineSiiReport raise @hal.EcError {
  let (selected_tx_pdos, selected_rx_pdos) = resolve_selected_module_pdos(
    device, modules,
  )
  let tx_pdo_projection = if selected_tx_pdos.is_empty() {
    device.tx_pdos
  } else {
    selected_tx_pdos
  }
  let rx_pdo_projection = if selected_rx_pdos.is_empty() {
    device.rx_pdos
  } else {
    selected_rx_pdos
  }
  let strings = collect_projected_sii_strings(
    device, tx_pdo_projection, rx_pdo_projection,
  )
  let general = build_general_projection(device, strings)
  let tx_pdo = tx_pdo_projection.map(pdo => materialize_sii_pdo(pdo, strings))
  let rx_pdo = rx_pdo_projection.map(pdo => materialize_sii_pdo(pdo, strings))
  let dc_clocks = device.dc_modes.map(dc => materialize_sii_dc(dc, strings))
  let categories = build_sii_categories(
    device, strings, general, tx_pdo, rx_pdo, dc_clocks,
  )
  let byte_size = max_uint(
    device.eeprom_byte_size,
    minimum_eeprom_size(categories),
  )
  let normalized_byte_size = max_uint(byte_size, 128U)
  {
    position: device_index.reinterpret_as_uint(),
    word_count: (normalized_byte_size / 2U).reinterpret_as_int(),
    eeprom: Bytes::makei(normalized_byte_size.reinterpret_as_int(), fn(_) {
      b'\x00'
    }),
    preamble: build_sii_preamble(device),
    standard: {
      eeprom_size_raw: encode_eeprom_size_raw(normalized_byte_size),
      version: 1U,
    },
    header: build_sii_header(device),
    general: Some(general),
    strings,
    fmmu: device.fmmu,
    sync_managers: device.sync_managers,
    dc_clocks,
    tx_pdo,
    rx_pdo,
    categories,
  }
}

///|
fn resolve_selected_module_pdos(
  device : EsiDeviceProjection,
  modules : Array[EsiModuleProjection],
) -> (Array[EsiPdoProjection], Array[EsiPdoProjection]) {
  let tx_pdos : Array[EsiPdoProjection] = []
  let rx_pdos : Array[EsiPdoProjection] = []
  for selection in device.default_modules {
    match find_module_projection(modules, selection.module_ident) {
      Some(module_projection) => {
        for pdo in module_projection.tx_pdos {
          tx_pdos.push(apply_slot_selection(device, pdo, selection.slot_index))
        }
        for pdo in module_projection.rx_pdos {
          rx_pdos.push(apply_slot_selection(device, pdo, selection.slot_index))
        }
      }
      None => ()
    }
  }
  (tx_pdos, rx_pdos)
}

///|
fn find_module_projection(
  modules : Array[EsiModuleProjection],
  module_ident : UInt,
) -> EsiModuleProjection? {
  for module_projection in modules {
    if module_projection.module_ident == module_ident {
      return Some(module_projection)
    }
  }
  None
}

///|
fn apply_slot_selection(
  device : EsiDeviceProjection,
  pdo : EsiPdoProjection,
  slot_index : Int,
) -> EsiPdoProjection {
  let updated_entries = pdo.entries.map(fn(entry) {
    {
      ..entry,
      base_index: if entry.depend_on_slot_index {
        entry.base_index +
        device.slot_index_increment * slot_index.reinterpret_as_uint()
      } else {
        entry.base_index
      },
      depend_on_slot_index: false,
    }
  })
  {
    ..pdo,
    base_index: if pdo.depend_on_slot_pdo {
      pdo.base_index +
      device.slot_pdo_increment * slot_index.reinterpret_as_uint()
    } else {
      pdo.base_index
    },
    depend_on_slot_pdo: false,
    entries: updated_entries,
  }
}

///|
fn collect_projected_sii_strings(
  device : EsiDeviceProjection,
  tx_pdos : Array[EsiPdoProjection],
  rx_pdos : Array[EsiPdoProjection],
) -> Array[String] raise @hal.EcError {
  let strings : Array[String] = []
  ignore(intern_sii_string(strings, preferred_device_group_name(device)))
  ignore(intern_sii_string(strings, preferred_device_name(device)))
  for dc in device.dc_modes {
    ignore(intern_sii_string(strings, dc.name))
    ignore(intern_sii_string(strings, dc.description))
  }
  for pdo in tx_pdos {
    ignore(intern_sii_string(strings, pdo.name))
    for entry in pdo.entries {
      ignore(intern_sii_string(strings, entry.name))
    }
  }
  for pdo in rx_pdos {
    ignore(intern_sii_string(strings, pdo.name))
    for entry in pdo.entries {
      ignore(intern_sii_string(strings, entry.name))
    }
  }
  strings
}

///|
fn preferred_device_group_name(device : EsiDeviceProjection) -> String {
  if device.type_name != "" {
    device.type_name
  } else {
    device.device_name
  }
}

///|
fn preferred_device_name(device : EsiDeviceProjection) -> String {
  if device.device_name != "" {
    device.device_name
  } else {
    device.type_name
  }
}

///|
fn intern_sii_string(
  strings : Array[String],
  text : String,
) -> Byte raise @hal.EcError {
  if text == "" {
    return b'\x00'
  }
  for i = 0; i < strings.length(); i = i + 1 {
    if strings[i] == text {
      return (i + 1).to_byte()
    }
  }
  if strings.length() >= 255 {
    raise @hal.EcError::EsiParseFailed("too many synthesized SII strings")
  }
  strings.push(text)
  strings.length().to_byte()
}

///|
fn build_general_projection(
  device : EsiDeviceProjection,
  strings : Array[String],
) -> @mailbox.SiiGeneral raise @hal.EcError {
  let ports = decode_physical_ports(device.physics)
  {
    group_idx: intern_sii_string(strings, preferred_device_group_name(device)),
    image_idx: b'\x00',
    order_idx: b'\x00',
    name_idx: intern_sii_string(strings, preferred_device_name(device)),
    coe_details: build_coe_details_byte(device.mailbox),
    foe_supported: device.mailbox.foe,
    eoe_supported: device.mailbox.eoe,
    soe_supported: device.mailbox.soe,
    soe_channels: if device.mailbox.soe {
      b'\x01'
    } else {
      b'\x00'
    },
    ds402_channels: b'\x00',
    sysman_class: b'\x00',
    flags: build_general_flags(device),
    current_on_ebus: 0U,
    physical_port_0: ports[0],
    physical_port_1: ports[1],
    physical_port_2: ports[2],
    physical_port_3: ports[3],
    physical_memory_address: 0U,
  }
}

///|
fn build_coe_details_byte(mailbox : EsiMailboxProjection) -> Byte {
  (if mailbox.coe_present { b'\x01' } else { b'\x00' }) |
  (if mailbox.coe_sdo_info { b'\x02' } else { b'\x00' }) |
  (if mailbox.coe_pdo_assign { b'\x04' } else { b'\x00' }) |
  (if mailbox.coe_pdo_config { b'\x08' } else { b'\x00' }) |
  (if mailbox.coe_complete_access { b'\x20' } else { b'\x00' })
}

///|
fn build_general_flags(device : EsiDeviceProjection) -> Byte {
  let mut has_active_dc = false
  for dc in device.dc_modes {
    if dc.assign_activate != 0U {
      has_active_dc = true
      break
    }
  }
  (if has_active_dc { b'\x01' } else { b'\x00' }) |
  (if device.mailbox.data_link_layer { b'\x04' } else { b'\x00' })
}

///|
fn decode_physical_ports(physics : String) -> Array[Byte] {
  let ports : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  let bytes = @utf8.encode(physics)
  for i = 0; i < bytes.length() && i < 4; i = i + 1 {
    ports[i] = match bytes[i] {
      b'Y' | b'H' | b'K' => b'\x01'
      b'E' => b'\x03'
      _ => b'\x00'
    }
  }
  ports
}

///|
fn materialize_sii_pdo(
  pdo : EsiPdoProjection,
  strings : Array[String],
) -> @mailbox.SiiPdo raise @hal.EcError {
  {
    pdo_index: pdo.base_index,
    entry_count: pdo.entries.length().to_byte(),
    sync_manager: pdo.sync_manager,
    synchronization: b'\x00',
    name_idx: intern_sii_string(strings, pdo.name),
    flags: 0U,
    entries: pdo.entries.map(entry => {
      entry_index: entry.base_index,
      subindex: entry.subindex,
      name_idx: intern_sii_string(strings, entry.name),
      data_type: map_esi_data_type(entry.data_type_name, entry.bit_length),
      bit_length: entry.bit_length,
      flags: 0U,
    }),
  }
}

///|
fn map_esi_data_type(type_name : String, bit_length : Byte) -> Byte {
  match type_name {
    "BOOL" => b'\x01'
    "SINT" => b'\x02'
    "INT" => b'\x03'
    "DINT" => b'\x04'
    "USINT" | "BYTE" => b'\x05'
    "UINT" | "WORD" => b'\x06'
    "UDINT" | "DWORD" => b'\x07'
    _ =>
      match bit_length {
        b'\x08' => b'\x05'
        b'\x10' => b'\x06'
        b'\x20' => b'\x07'
        _ => b'\x00'
      }
  }
}

///|
fn materialize_sii_dc(
  dc : EsiDcProjection,
  strings : Array[String],
) -> @mailbox.SiiDcClock raise @hal.EcError {
  {
    cycle_time_0: dc.cycle_time_sync0,
    shift_time_0: 0U,
    shift_time_1: 0U,
    sync1_cycle_factor: dc.sync1_factor,
    assign_activate: dc.assign_activate,
    sync0_cycle_factor: dc.sync0_factor,
    name_idx: intern_sii_string(strings, dc.name),
    description_idx: intern_sii_string(strings, dc.description),
  }
}

///|
fn build_sii_preamble(device : EsiDeviceProjection) -> @mailbox.SiiPreamble {
  {
    pdi_control: read_u16_from_bytes(device.config_data, 0),
    pdi_config: read_u16_from_bytes(device.config_data, 2),
    sync_impulse_length_raw: read_u16_from_bytes(device.config_data, 4),
    pdi_config2: read_u16_from_bytes(device.config_data, 6),
    configured_station_alias: 0U,
    checksum: 0U,
    checksum_ok: false,
  }
}

///|
fn build_sii_header(device : EsiDeviceProjection) -> @mailbox.SiiData {
  {
    vendor_id: device.vendor_id,
    product_code: device.product_code,
    revision: device.revision,
    serial: device.serial,
    bootstrap_rx_offset: read_u16_from_bytes(device.bootstrap, 0),
    bootstrap_rx_size: read_u16_from_bytes(device.bootstrap, 2),
    bootstrap_tx_offset: read_u16_from_bytes(device.bootstrap, 4),
    bootstrap_tx_size: read_u16_from_bytes(device.bootstrap, 6),
    mailbox_rx_offset: if device.sync_managers.length() > 0 {
      device.sync_managers[0].physical_start
    } else {
      0U
    },
    mailbox_rx_size: if device.sync_managers.length() > 0 {
      device.sync_managers[0].length
    } else {
      0U
    },
    mailbox_tx_offset: if device.sync_managers.length() > 1 {
      device.sync_managers[1].physical_start
    } else {
      0U
    },
    mailbox_tx_size: if device.sync_managers.length() > 1 {
      device.sync_managers[1].length
    } else {
      0U
    },
    mailbox_protocols: build_mailbox_protocol_mask(device.mailbox),
  }
}

///|
fn build_mailbox_protocol_mask(mailbox : EsiMailboxProjection) -> UInt {
  (if mailbox.eoe { mailbox_eoe_mask } else { 0U }) |
  (if mailbox.coe_present { mailbox_coe_mask } else { 0U }) |
  (if mailbox.foe { mailbox_foe_mask } else { 0U }) |
  (if mailbox.soe { mailbox_soe_mask } else { 0U }) |
  (if mailbox.voe { mailbox_voe_mask } else { 0U })
}

///|
fn read_u16_from_bytes(data : Bytes, byte_offset : Int) -> UInt {
  if byte_offset + 1 >= data.length() {
    0U
  } else {
    data[byte_offset].to_uint() | (data[byte_offset + 1].to_uint() << 8)
  }
}

///|
fn build_sii_categories(
  device : EsiDeviceProjection,
  strings : Array[String],
  general : @mailbox.SiiGeneral,
  tx_pdo : Array[@mailbox.SiiPdo],
  rx_pdo : Array[@mailbox.SiiPdo],
  dc_clocks : Array[@mailbox.SiiDcClock],
) -> Array[@mailbox.SiiCategoryEntry] {
  let categories : Array[@mailbox.SiiCategoryEntry] = []
  if not(strings.is_empty()) {
    categories.push({ category: Strings, data: encode_sii_strings(strings) })
  }
  categories.push({ category: General, data: encode_sii_general(general) })
  if not(device.fmmu.is_empty()) {
    categories.push({ category: Fmmu, data: encode_sii_fmmu(device.fmmu) })
  }
  if not(device.sync_managers.is_empty()) {
    categories.push({
      category: SyncManager,
      data: encode_sii_sync_managers(device.sync_managers),
    })
  }
  if not(tx_pdo.is_empty()) {
    categories.push({ category: TxPdo, data: encode_sii_pdos(tx_pdo) })
  }
  if not(rx_pdo.is_empty()) {
    categories.push({ category: RxPdo, data: encode_sii_pdos(rx_pdo) })
  }
  for dc in dc_clocks {
    categories.push({ category: Dc, data: encode_sii_dc(dc) })
  }
  categories
}

///|
fn encode_sii_strings(strings : Array[String]) -> Bytes {
  let values : Array[Byte] = [strings.length().to_byte()]
  for text in strings {
    let bytes = @utf8.encode(text)
    values.push(bytes.length().to_byte())
    for byte in bytes {
      values.push(byte)
    }
  }
  pad_even_bytes(Bytes::from_array(values))
}

///|
fn encode_sii_general(general : @mailbox.SiiGeneral) -> Bytes {
  let values : Array[Byte] = []
  values.push(general.group_idx)
  values.push(general.image_idx)
  values.push(general.order_idx)
  values.push(general.name_idx)
  values.push(b'\x00')
  values.push(general.coe_details)
  values.push(if general.foe_supported { b'\x01' } else { b'\x00' })
  values.push(if general.eoe_supported { b'\x01' } else { b'\x00' })
  values.push(general.soe_channels)
  values.push(general.ds402_channels)
  values.push(general.sysman_class)
  values.push(general.flags)
  push_u16(values, general.current_on_ebus)
  values.push(b'\x00')
  values.push(b'\x00')
  values.push(
    ((general.physical_port_1.to_uint() << 4) |
    general.physical_port_0.to_uint())
    .reinterpret_as_int()
    .to_byte(),
  )
  values.push(
    ((general.physical_port_3.to_uint() << 4) |
    general.physical_port_2.to_uint())
    .reinterpret_as_int()
    .to_byte(),
  )
  push_u16(values, general.physical_memory_address)
  pad_even_bytes(Bytes::from_array(values))
}

///|
fn encode_sii_fmmu(fmmu : Array[@mailbox.FmmuDirection]) -> Bytes {
  let values : Array[Byte] = []
  for direction in fmmu {
    values.push(
      match direction {
        Outputs => b'\x01'
        Inputs => b'\x02'
        MailboxState => b'\x03'
      },
    )
  }
  pad_even_bytes(Bytes::from_array(values))
}

///|
fn encode_sii_sync_managers(sms : Array[@mailbox.SiiSmEntry]) -> Bytes {
  let values : Array[Byte] = []
  for sm in sms {
    push_u16(values, sm.physical_start)
    push_u16(values, sm.length)
    values.push(sm.control)
    values.push(sm.status)
    values.push(if sm.enable { b'\x01' } else { b'\x00' })
    values.push(
      match sm.sm_type {
        MailboxOut => b'\x01'
        MailboxIn => b'\x02'
        ProcessDataOut => b'\x03'
        ProcessDataIn => b'\x04'
        Unused => b'\x00'
      },
    )
  }
  Bytes::from_array(values)
}

///|
fn encode_sii_pdos(pdos : Array[@mailbox.SiiPdo]) -> Bytes {
  let values : Array[Byte] = []
  for pdo in pdos {
    push_u16(values, pdo.pdo_index)
    values.push(pdo.entry_count)
    values.push(pdo.sync_manager)
    values.push(pdo.synchronization)
    values.push(pdo.name_idx)
    push_u16(values, pdo.flags)
    for entry in pdo.entries {
      push_u16(values, entry.entry_index)
      values.push(entry.subindex)
      values.push(entry.name_idx)
      values.push(entry.data_type)
      values.push(entry.bit_length)
      push_u16(values, entry.flags)
    }
  }
  Bytes::from_array(values)
}

///|
fn encode_sii_dc(dc : @mailbox.SiiDcClock) -> Bytes {
  let values : Array[Byte] = []
  push_u32(values, dc.cycle_time_0)
  push_u32(values, dc.shift_time_0)
  push_u32(values, dc.shift_time_1)
  push_i16(values, dc.sync1_cycle_factor)
  push_u16(values, dc.assign_activate)
  push_i16(values, dc.sync0_cycle_factor)
  values.push(dc.name_idx)
  values.push(dc.description_idx)
  values.push(b'\x00')
  values.push(b'\x00')
  values.push(b'\x00')
  values.push(b'\x00')
  Bytes::from_array(values)
}

///|
fn push_u16(values : Array[Byte], value : UInt) -> Unit {
  values.push((value & 0xFFU).reinterpret_as_int().to_byte())
  values.push(((value >> 8) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
fn push_u32(values : Array[Byte], value : UInt) -> Unit {
  values.push((value & 0xFFU).reinterpret_as_int().to_byte())
  values.push(((value >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  values.push(((value >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  values.push(((value >> 24) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
fn push_i16(values : Array[Byte], value : Int) -> Unit {
  let encoded = if value < 0 {
    (value + 0x10000).reinterpret_as_uint()
  } else {
    value.reinterpret_as_uint()
  }
  push_u16(values, encoded)
}

///|
fn pad_even_bytes(data : Bytes) -> Bytes {
  if data.length() % 2 == 0 {
    data
  } else {
    let values : Array[Byte] = []
    for byte in data {
      values.push(byte)
    }
    values.push(b'\x00')
    Bytes::from_array(values)
  }
}

///|
fn minimum_eeprom_size(categories : Array[@mailbox.SiiCategoryEntry]) -> UInt {
  let mut total = 128U + 4U
  for entry in categories {
    total = total + 4U + entry.data.length().reinterpret_as_uint()
  }
  total
}

///|
fn encode_eeprom_size_raw(byte_size : UInt) -> UInt {
  if byte_size <= 0x80U {
    0U
  } else {
    (byte_size - 0x80U) >> 7
  }
}

///|
fn max_uint(left : UInt, right : UInt) -> UInt {
  if left >= right {
    left
  } else {
    right
  }
}

///|
fn optional_bool_xml_attr(elem : @xml.XmlElement, attr_name : String) -> Bool {
  match elem.get(attr_name) {
    Some("1") | Some("true") | Some("TRUE") => true
    _ => false
  }
}
