///|
/// ESI XML -> ESI JSON conversion. XML parsing stays in the standalone bridge,
/// while downstream consumers operate on the normalized JSON document.

///|
fn convert_esi_xml_to_json_string(
  xml_content : String,
) -> String raise @hal.EcError {
  @runtime.esi_json_to_string(esi_json_document_from_xml(xml_content))
}

///|
fn esi_json_document_from_xml(
  xml_content : String,
) -> @runtime.EsiJsonDocument raise @hal.EcError {
  let (devices, modules) = parse_esi_document_projection(xml_content)
  { devices, modules }
}

///|
fn parse_esi_document_projection(
  xml_content : String,
) -> (Array[@runtime.EsiJsonDevice], Array[@runtime.EsiJsonModule]) raise @hal.EcError {
  let reader = @xml.Reader::from_string(xml_content)
  let devices : Array[@runtime.EsiJsonDevice] = []
  let modules : Array[@runtime.EsiJsonModule] = []

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
  let mut current_sm : @runtime.EsiJsonSmEntry? = None
  let mut current_pdo : @runtime.EsiJsonPdo? = None
  let mut current_entry : @runtime.EsiJsonPdoEntry? = None
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
            "Type" => {
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
                serial: option_uint_or(
                  optional_numeric_xml_attr(elem, "SerialNo"),
                  current_device.serial,
                ),
              }
              current_text_target = Some("device-type-name")
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
                sm_type: "unused",
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
            "AoE" =>
              current_device = {
                ..current_device,
                mailbox: { ..current_device.mailbox, aoe: true },
              }
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
            "ByteSize" => current_text_target = Some("eeprom-byte-size")
            "ConfigData" => current_text_target = Some("eeprom-config-data")
            "BootStrap" => current_text_target = Some("eeprom-bootstrap")
            _ => ()
          }
        }

        if in_module {
          match elem.name {
            "Type" => {
              current_module = {
                ..current_module,
                module_ident: option_uint_or(
                  optional_numeric_xml_attr(elem, "ModuleIdent"),
                  current_module.module_ident,
                ),
              }
              current_text_target = Some("module-type-name")
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
                ..empty_esi_pdo_projection("rx"),
                sync_manager: option_uint_or(
                  optional_numeric_xml_attr(elem, "Sm"),
                  0U,
                ).to_byte(),
              })
            "TxPdo" =>
              current_pdo = Some({
                ..empty_esi_pdo_projection("tx"),
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
          Some("device-type-name") =>
            if current_device.type_name == "" {
              current_device = { ..current_device, type_name: text }
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
          Some("module-type-name") =>
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
                  if pdo.direction == "rx" {
                    current_module.rx_pdos.push(pdo)
                  } else {
                    current_module.tx_pdos.push(pdo)
                  }
                } else if pdo.direction == "rx" {
                  current_device.rx_pdos.push(pdo)
                } else {
                  current_device.tx_pdos.push(pdo)
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
          | "Type"
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
fn empty_esi_mailbox_projection() -> @runtime.EsiJsonMailbox {
  {
    data_link_layer: false,
    aoe: false,
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
fn empty_esi_pdo_entry_projection() -> @runtime.EsiJsonPdoEntry {
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
fn empty_esi_pdo_projection(direction : String) -> @runtime.EsiJsonPdo {
  {
    direction,
    base_index: 0U,
    depend_on_slot_pdo: false,
    sync_manager: b'\x00',
    name: "",
    entries: [],
  }
}

///|
fn empty_esi_dc_projection() -> @runtime.EsiJsonDcMode {
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
fn empty_esi_device_projection() -> @runtime.EsiJsonDevice {
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
fn empty_esi_module_projection() -> @runtime.EsiJsonModule {
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
fn parse_esi_fmmu_direction(text : String) -> String? {
  match text {
    "Outputs" => Some("outputs")
    "Inputs" => Some("inputs")
    "MBoxState" => Some("mailbox-state")
    _ => None
  }
}

///|
fn parse_esi_sm_type(text : String) -> String {
  match text {
    "MBoxOut" => "mailbox-out"
    "MBoxIn" => "mailbox-in"
    "Outputs" => "process-data-out"
    "Inputs" => "process-data-in"
    _ => "unused"
  }
}

///|
fn optional_bool_xml_attr(elem : @xml.XmlElement, attr_name : String) -> Bool {
  match elem.get(attr_name) {
    Some("1") | Some("true") | Some("TRUE") => true
    _ => false
  }
}
