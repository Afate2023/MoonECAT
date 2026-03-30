///|
/// ENI XML to ENI JSON interchange conversion tool.
fn main {
  let _ = cli_main() catch {
    err => {
      println("moonecat eni-json error: " + err.to_string())
      ()
    }
  }
}

///|
fn cli_main() -> Unit raise @hal.EcError {
  let args = @env.args()
  let input_path = require_flag(args, "--input")
  let output_path = flag_value(args, "--output")
  let input_kind = optional_kind_flag(args)
  let xml_content = read_text_file(input_path, "ENI XML")
  let json_text = convert_xml_to_json_string(xml_content, input_kind)
  match output_path {
    Some(path) => write_text_file(path, json_text, "ENI JSON")
    None => println(json_text)
  }
}

///|
fn convert_xml_to_json_string(
  xml_content : String,
  input_kind : String,
) -> String raise @hal.EcError {
  match input_kind {
    "eni" => convert_eni_xml_to_json_string(xml_content)
    "esi" => convert_esi_xml_to_json_string(xml_content)
    _ =>
      raise @hal.EcError::ConfigMismatch(
        "unsupported --kind value: " + input_kind + " (expected eni or esi)",
      )
  }
}

///|
fn convert_eni_xml_to_json_string(
  xml_content : String,
) -> String raise @hal.EcError {
  @runtime.configuration_to_eni_json_string(
    configuration_from_eni_xml(xml_content),
  )
}

///|
fn optional_kind_flag(args : Array[String]) -> String {
  match flag_value(args, "--kind") {
    Some(value) => value
    None => "eni"
  }
}

///|
fn read_text_file(path : String, label : String) -> String raise @hal.EcError {
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
fn write_text_file(
  path : String,
  content : String,
  label : String,
) -> Unit raise @hal.EcError {
  let write_result : Result[Unit, Error] = try? @fs.write_string_to_file(
    path, content,
  )
  match write_result {
    Ok(_) => ()
    Err(err) =>
      raise @hal.EcError::ConfigMismatch(
        "failed to write " + label + " file " + path + ": " + err.to_string(),
      )
  }
}

///|
fn require_flag(
  args : Array[String],
  flag : String,
) -> String raise @hal.EcError {
  match flag_value(args, flag) {
    Some(value) => value
    None =>
      raise @hal.EcError::ConfigMismatch(
        "missing required flag: " +
        flag +
        "\nusage: moon run cmd/eni_json -- --input <eni-or-esi.xml> [--kind <eni|esi>] [--output <bridge.json>]",
      )
  }
}

///|
fn flag_value(args : Array[String], flag : String) -> String? {
  for i = 0; i + 1 < args.length(); i = i + 1 {
    if args[i] == flag {
      return Some(args[i + 1])
    }
  }
  None
}

///|
priv struct EniSlaveProjection {
  position : Int
  configured_address : UInt?
  vendor_id : UInt?
  product_code : UInt?
  revision : UInt?
  serial : UInt?
  identification : UInt?
  sync_manager_count : Int
  fmmu_count : Int
  rx_pdo_count : Int
  tx_pdo_count : Int
  mailbox_protocols : @runtime.ConfigurationMailboxProtocols?
  dc_op_mode_count : Int
  dc_assign_activate_count : Int
}

///|
priv struct EniCurrentValues {
  configured_address : UInt?
  vendor_id : UInt?
  product_code : UInt?
  revision : UInt?
  serial : UInt?
}

///|
priv struct EniMailboxProtocols {
  aoe : Bool
  coe : Bool
  eoe : Bool
  foe : Bool
  soe : Bool
  voe : Bool
}

///|
fn configuration_from_eni_xml(
  xml_content : String,
) -> @runtime.ConfigurationModel raise @hal.EcError {
  project_eni_slaves(parse_eni_slave_projection(xml_content))
}

///|
fn parse_eni_slave_projection(
  xml_content : String,
) -> Array[EniSlaveProjection] raise @hal.EcError {
  let reader = @xml.Reader::from_string(xml_content)
  let slaves : Array[EniSlaveProjection] = []

  let mut in_slave = false
  let mut in_info = false
  let mut in_mailbox = false
  let mut in_dc = false
  let mut current_field : String? = None
  let mut current_mailbox_field : String? = None
  let mut current_dc_field : String? = None
  let mut current_position = 0
  let mut current_values : EniCurrentValues = {
    configured_address: None,
    vendor_id: None,
    product_code: None,
    revision: None,
    serial: None,
  }
  let mut current_identification : UInt? = None
  let mut current_sync_manager_count = 0
  let mut current_fmmu_count = 0
  let mut current_rx_pdo_count = 0
  let mut current_tx_pdo_count = 0
  let mut current_mailbox_protocols : EniMailboxProtocols? = None
  let mut current_dc_op_mode_count = 0
  let mut current_dc_assign_activate_count = 0

  while true {
    let event = reader.read_event() catch {
      err =>
        raise @hal.EcError::EsiParseFailed(
          "ENI XML parse failed: " + err.to_string(),
        )
    }
    match event {
      @xml.Start(elem) => {
        if elem.name == "Slave" {
          in_slave = true
          in_info = false
          in_mailbox = false
          in_dc = false
          current_field = None
          current_mailbox_field = None
          current_dc_field = None
          current_values = {
            configured_address: None,
            vendor_id: None,
            product_code: None,
            revision: None,
            serial: None,
          }
          current_identification = None
          current_sync_manager_count = 0
          current_fmmu_count = 0
          current_rx_pdo_count = 0
          current_tx_pdo_count = 0
          current_mailbox_protocols = None
          current_dc_op_mode_count = 0
          current_dc_assign_activate_count = 0
          continue
        }

        if !in_slave {
          continue
        }

        if is_eni_sync_manager_tag(elem.name) {
          current_sync_manager_count = current_sync_manager_count + 1
        }
        if elem.name == "Fmmu" {
          current_fmmu_count = current_fmmu_count + 1
        }
        if elem.name == "RxPdo" {
          current_rx_pdo_count = current_rx_pdo_count + 1
        }
        if elem.name == "TxPdo" {
          current_tx_pdo_count = current_tx_pdo_count + 1
        }

        if elem.name == "Mailbox" {
          in_mailbox = true
          current_mailbox_field = None
          continue
        }

        if elem.name == "Dc" {
          in_dc = true
          current_dc_field = None
          continue
        }

        if in_mailbox {
          if is_eni_mailbox_protocol_tag(elem.name) {
            current_mailbox_protocols = Some(
              enable_mailbox_protocol(current_mailbox_protocols, elem.name),
            )
            current_mailbox_field = None
          } else if elem.name == "Protocol" {
            current_mailbox_field = Some(elem.name)
          } else {
            current_mailbox_field = None
          }
        }

        if in_dc {
          if elem.name == "OpMode" {
            current_dc_op_mode_count = current_dc_op_mode_count + 1
            current_dc_field = None
          } else if elem.name == "AssignActivate" {
            current_dc_field = Some(elem.name)
          } else {
            current_dc_field = None
          }
        }

        if elem.name == "Info" {
          in_info = true
          current_field = None
          continue
        }

        if in_info {
          if elem.name == "Identification" {
            current_identification = parse_optional_numeric_attribute(
              elem, "Value", "Slave/Info/Identification@Value",
            )
            current_field = None
          } else if is_eni_info_field(elem.name) {
            current_field = Some(elem.name)
          } else {
            current_field = None
          }
        }
      }
      @xml.Empty(elem) =>
        if in_slave {
          if is_eni_sync_manager_tag(elem.name) {
            current_sync_manager_count = current_sync_manager_count + 1
          }
          if elem.name == "Fmmu" {
            current_fmmu_count = current_fmmu_count + 1
          }
          if elem.name == "RxPdo" {
            current_rx_pdo_count = current_rx_pdo_count + 1
          }
          if elem.name == "TxPdo" {
            current_tx_pdo_count = current_tx_pdo_count + 1
          }
          if in_mailbox && is_eni_mailbox_protocol_tag(elem.name) {
            current_mailbox_protocols = Some(
              enable_mailbox_protocol(current_mailbox_protocols, elem.name),
            )
          }
          if in_dc && elem.name == "OpMode" {
            current_dc_op_mode_count = current_dc_op_mode_count + 1
          }
          if in_info && elem.name == "Identification" {
            current_identification = parse_optional_numeric_attribute(
              elem, "Value", "Slave/Info/Identification@Value",
            )
          }
        }
      @xml.Text(content) => {
        current_values = update_eni_field(
          content, current_field, current_values,
        )
        current_mailbox_protocols = update_mailbox_protocol_text(
          content, current_mailbox_field, current_mailbox_protocols,
        )
        current_dc_assign_activate_count = update_dc_assign_activate_count(
          content, current_dc_field, current_dc_assign_activate_count,
        )
      }
      @xml.CData(content) => {
        current_values = update_eni_field(
          content, current_field, current_values,
        )
        current_mailbox_protocols = update_mailbox_protocol_text(
          content, current_mailbox_field, current_mailbox_protocols,
        )
        current_dc_assign_activate_count = update_dc_assign_activate_count(
          content, current_dc_field, current_dc_assign_activate_count,
        )
      }
      @xml.End(name) => {
        if in_info && current_field == Some(name) {
          current_field = None
        }
        if in_mailbox && current_mailbox_field == Some(name) {
          current_mailbox_field = None
        }
        if in_dc && current_dc_field == Some(name) {
          current_dc_field = None
        }
        if name == "Info" {
          in_info = false
          current_field = None
          continue
        }
        if name == "Mailbox" {
          in_mailbox = false
          current_mailbox_field = None
          continue
        }
        if name == "Dc" {
          in_dc = false
          current_dc_field = None
          continue
        }
        if name == "Slave" && in_slave {
          slaves.push({
            position: current_position,
            configured_address: current_values.configured_address,
            vendor_id: current_values.vendor_id,
            product_code: current_values.product_code,
            revision: current_values.revision,
            serial: current_values.serial,
            identification: current_identification,
            sync_manager_count: current_sync_manager_count,
            fmmu_count: current_fmmu_count,
            rx_pdo_count: current_rx_pdo_count,
            tx_pdo_count: current_tx_pdo_count,
            mailbox_protocols: current_mailbox_protocols.map(fn(protocols) {
              {
                aoe: protocols.aoe,
                coe: protocols.coe,
                eoe: protocols.eoe,
                foe: protocols.foe,
                soe: protocols.soe,
                voe: protocols.voe,
              }
            }),
            dc_op_mode_count: current_dc_op_mode_count,
            dc_assign_activate_count: current_dc_assign_activate_count,
          })
          current_position = current_position + 1
          in_slave = false
          in_info = false
          in_mailbox = false
          in_dc = false
          current_field = None
          current_mailbox_field = None
          current_dc_field = None
        }
      }
      @xml.Eof => break
      _ => ()
    }
  }

  slaves
}

///|
fn is_eni_info_field(name : String) -> Bool {
  name == "PhysAddr" ||
  name == "VendorId" ||
  name == "ProductCode" ||
  name == "RevisionNo" ||
  name == "SerialNo"
}

///|
fn is_eni_sync_manager_tag(name : String) -> Bool {
  name == "Sm" ||
  name == "Sm0" ||
  name == "Sm1" ||
  name == "Sm2" ||
  name == "Sm3"
}

///|
fn is_eni_mailbox_protocol_tag(name : String) -> Bool {
  name == "AoE" ||
  name == "CoE" ||
  name == "EoE" ||
  name == "FoE" ||
  name == "SoE" ||
  name == "VoE"
}

///|
fn empty_mailbox_protocols() -> EniMailboxProtocols {
  { aoe: false, coe: false, eoe: false, foe: false, soe: false, voe: false }
}

///|
fn enable_mailbox_protocol(
  protocols : EniMailboxProtocols?,
  protocol_name : String,
) -> EniMailboxProtocols {
  let current = match protocols {
    Some(value) => value
    None => empty_mailbox_protocols()
  }
  match protocol_name {
    "AoE" => { ..current, aoe: true }
    "CoE" => { ..current, coe: true }
    "EoE" => { ..current, eoe: true }
    "FoE" => { ..current, foe: true }
    "SoE" => { ..current, soe: true }
    "VoE" => { ..current, voe: true }
    _ => current
  }
}

///|
fn compact_xml_text(content : String) -> String {
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
fn update_mailbox_protocol_text(
  content : String,
  current_mailbox_field : String?,
  current_protocols : EniMailboxProtocols?,
) -> EniMailboxProtocols? {
  if current_mailbox_field != Some("Protocol") {
    return current_protocols
  }
  let protocol_name = compact_xml_text(content)
  if protocol_name == "" {
    return current_protocols
  }
  Some(enable_mailbox_protocol(current_protocols, protocol_name))
}

///|
fn update_dc_assign_activate_count(
  content : String,
  current_dc_field : String?,
  current_count : Int,
) -> Int raise @hal.EcError {
  if current_dc_field != Some("AssignActivate") || is_blank_xml_text(content) {
    return current_count
  }
  if parse_eni_numeric(content, "Slave/Dc/OpMode/AssignActivate") == 0U {
    return current_count
  }
  current_count + 1
}

///|
fn update_eni_field(
  content : String,
  current_field : String?,
  current_values : EniCurrentValues,
) -> EniCurrentValues raise @hal.EcError {
  let field = match current_field {
    Some(field) => field
    None => return current_values
  }
  if is_blank_xml_text(content) {
    return current_values
  }
  let value = parse_eni_numeric(content, "Slave/Info/" + field)
  match field {
    "PhysAddr" => { ..current_values, configured_address: Some(value) }
    "VendorId" => { ..current_values, vendor_id: Some(value) }
    "ProductCode" => { ..current_values, product_code: Some(value) }
    "RevisionNo" => { ..current_values, revision: Some(value) }
    "SerialNo" => { ..current_values, serial: Some(value) }
    _ => current_values
  }
}

///|
fn is_blank_xml_text(content : String) -> Bool {
  let bytes = @utf8.encode(content)
  for ch in bytes {
    if ch == b'\x00' {
      continue
    }
    if ch != b' ' && ch != b'\t' && ch != b'\r' && ch != b'\n' {
      return false
    }
  }
  true
}

///|
fn parse_optional_numeric_attribute(
  elem : @xml.XmlElement,
  attr_name : String,
  field_name : String,
) -> UInt? raise @hal.EcError {
  match elem.get(attr_name) {
    Some(value) => Some(parse_eni_numeric(value, field_name))
    None => None
  }
}

///|
fn parse_eni_numeric(
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
      "missing numeric ENI field at " + field_name,
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
      "invalid numeric ENI field at " + field_name + ": " + text,
    )
  }

  let mut value = 0U
  for i = index; i < filtered.length(); i = i + 1 {
    let digit = eni_digit_value(filtered[i])
    if digit >= base {
      raise @hal.EcError::EsiParseFailed(
        "invalid numeric ENI field at " + field_name + ": " + text,
      )
    }
    value = value * base + digit
  }
  value
}

///|
fn eni_digit_value(ch : Byte) -> UInt raise @hal.EcError {
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
    "invalid hexadecimal digit in ENI numeric field",
  )
}

///|
fn project_eni_slaves(
  slaves : Array[EniSlaveProjection],
) -> @runtime.ConfigurationModel {
  {
    source: @runtime.EniImport,
    total_slaves: slaves.length(),
    slaves: slaves.map(fn(slave) {
      {
        position: slave.position,
        configured_address: slave.configured_address,
        alias_address: None,
        identity: build_eni_identity(slave),
        identification: slave.identification,
        process_data_summary: Some({
          sync_manager_count: slave.sync_manager_count,
          fmmu_count: slave.fmmu_count,
          rx_pdo_count: slave.rx_pdo_count,
          tx_pdo_count: slave.tx_pdo_count,
          mailbox_protocols: slave.mailbox_protocols,
          dc_op_mode_count: slave.dc_op_mode_count,
          dc_assign_activate_count: slave.dc_assign_activate_count,
        }),
        presence: @hal.Mandatory,
      }
    }),
  }
}

///|
fn build_eni_identity(slave : EniSlaveProjection) -> @hal.SlaveIdentity? {
  match slave.vendor_id {
    Some(vendor_id) =>
      match slave.product_code {
        Some(product_code) =>
          match slave.revision {
            Some(revision) =>
              match slave.serial {
                Some(serial) =>
                  Some({ vendor_id, product_code, revision, serial })
                None => None
              }
            None => None
          }
        None => None
      }
    None => None
  }
}
