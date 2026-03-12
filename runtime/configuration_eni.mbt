///|
/// ENI-specific XML projection kept separate from the runtime-facing
/// ConfigurationModel. The parser extracts only the fields needed for
/// comparison and leaves process-data details for later phases.

///|
priv struct EniSlaveProjection {
  position : Int
  configured_address : UInt?
  vendor_id : UInt?
  product_code : UInt?
  revision : UInt?
  serial : UInt?
  identification : UInt?
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
fn parse_eni_slave_projection(
  xml_content : String,
) -> Array[EniSlaveProjection] raise @hal.EcError {
  let reader = @xml.Reader::from_string(xml_content)
  let slaves : Array[EniSlaveProjection] = []

  let mut in_slave = false
  let mut in_info = false
  let mut current_field : String? = None
  let mut current_position = 0
  let mut current_values : EniCurrentValues = {
    configured_address: None,
    vendor_id: None,
    product_code: None,
    revision: None,
    serial: None,
  }
  let mut current_identification : UInt? = None

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
          current_field = None
          current_values = {
            configured_address: None,
            vendor_id: None,
            product_code: None,
            revision: None,
            serial: None,
          }
          current_identification = None
          continue
        }

        if not(in_slave) {
          continue
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
        if in_slave && in_info && elem.name == "Identification" {
          current_identification = parse_optional_numeric_attribute(
            elem, "Value", "Slave/Info/Identification@Value",
          )
        }
      @xml.Text(content) =>
        current_values = update_eni_field(
          content, current_field, current_values,
        )
      @xml.CData(content) =>
        current_values = update_eni_field(
          content, current_field, current_values,
        )
      @xml.End(name) => {
        if in_info && current_field == Some(name) {
          current_field = None
        }
        if name == "Info" {
          in_info = false
          current_field = None
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
          })
          current_position = current_position + 1
          in_slave = false
          in_info = false
          current_field = None
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
fn project_eni_slaves(slaves : Array[EniSlaveProjection]) -> ConfigurationModel {
  {
    source: EniImport,
    total_slaves: slaves.length(),
    slaves: slaves.map(fn(slave) {
      {
        position: slave.position,
        configured_address: slave.configured_address,
        identity: build_eni_identity(slave),
        identification: slave.identification,
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
