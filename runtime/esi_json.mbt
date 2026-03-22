///|
/// ESI JSON interchange model shared between XML import tools and SII-facing consumers.

///|
let esi_mailbox_aoe_mask : UInt = 0x0001U

///|
let esi_mailbox_coe_mask : UInt = 0x0004U

///|
let esi_mailbox_eoe_mask : UInt = 0x0002U

///|
let esi_mailbox_foe_mask : UInt = 0x0008U

///|
let esi_mailbox_soe_mask : UInt = 0x0010U

///|
let esi_mailbox_voe_mask : UInt = 0x0020U

///|
pub(all) struct EsiJsonMailbox {
  data_link_layer : Bool
  aoe : Bool
  coe_present : Bool
  coe_sdo_info : Bool
  coe_pdo_assign : Bool
  coe_pdo_config : Bool
  coe_complete_access : Bool
  eoe : Bool
  foe : Bool
  soe : Bool
  voe : Bool
} derive(Eq, Show, ToJson)

///|
pub(all) struct EsiJsonSmEntry {
  physical_start : UInt
  length : UInt
  control : Byte
  status : Byte
  enable : Bool
  sm_type : String
} derive(Eq, Show, ToJson)

///|
pub(all) struct EsiJsonPdoEntry {
  base_index : UInt
  depend_on_slot_index : Bool
  subindex : Byte
  bit_length : Byte
  name : String
  data_type_name : String
} derive(Eq, Show, ToJson)

///|
pub(all) struct EsiJsonPdo {
  direction : String
  base_index : UInt
  depend_on_slot_pdo : Bool
  sync_manager : Byte
  name : String
  entries : Array[EsiJsonPdoEntry]
} derive(Eq, Show, ToJson)

///|
pub(all) struct EsiJsonDcMode {
  name : String
  description : String
  assign_activate : UInt
  cycle_time_sync0 : UInt
  sync0_factor : Int
  sync1_factor : Int
} derive(Eq, Show, ToJson)

///|
pub(all) struct EsiJsonSelectedModule {
  module_ident : UInt
  slot_index : Int
} derive(Eq, Show, ToJson)

///|
pub(all) struct EsiJsonDevice {
  vendor_id : UInt
  product_code : UInt
  revision : UInt
  serial : UInt
  physics : String
  device_name : String
  type_name : String
  slot_index_increment : UInt
  slot_pdo_increment : UInt
  mailbox : EsiJsonMailbox
  fmmu : Array[String]
  sync_managers : Array[EsiJsonSmEntry]
  dc_modes : Array[EsiJsonDcMode]
  eeprom_byte_size : UInt
  config_data : Bytes
  bootstrap : Bytes
  default_modules : Array[EsiJsonSelectedModule]
  rx_pdos : Array[EsiJsonPdo]
  tx_pdos : Array[EsiJsonPdo]
} derive(Eq, Show, ToJson)

///|
pub(all) struct EsiJsonModule {
  module_ident : UInt
  module_name : String
  rx_pdos : Array[EsiJsonPdo]
  tx_pdos : Array[EsiJsonPdo]
} derive(Eq, Show, ToJson)

///|
pub(all) struct EsiJsonDocument {
  devices : Array[EsiJsonDevice]
  modules : Array[EsiJsonModule]
} derive(Eq, Show, ToJson)

///|
pub(all) struct EsiOfflineSiiReport {
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
pub fn parse_esi_json_document(
  json_content : String,
) -> EsiJsonDocument raise @hal.EcError {
  let parsed = @json.parse(json_content[:]) catch {
    err =>
      raise @hal.EcError::EsiParseFailed(
        "ESI JSON parse failed: " + err.to_string(),
      )
  }
  parse_esi_json_document_value(parsed)
}

///|
pub fn esi_json_to_string(
  document : EsiJsonDocument,
  indent? : Int = 2,
) -> String {
  document.to_json().stringify(indent~)
}

///|
pub fn offline_sii_report_from_esi_json(
  json_content : String,
  device_index : Int,
) -> EsiOfflineSiiReport raise @hal.EcError {
  offline_sii_report_from_esi_document(
    parse_esi_json_document(json_content),
    device_index,
  )
}

///|
pub fn offline_sii_report_from_esi_document(
  document : EsiJsonDocument,
  device_index : Int,
) -> EsiOfflineSiiReport raise @hal.EcError {
  if device_index < 0 || device_index >= document.devices.length() {
    raise @hal.EcError::EsiParseFailed(
      "device index out of range: " +
      device_index.to_string() +
      " (devices=" +
      document.devices.length().to_string() +
      ")",
    )
  }
  build_offline_sii_report(
    document.devices[device_index],
    document.modules,
    device_index,
  )
}

///|
fn parse_esi_json_document_value(
  json : Json,
) -> EsiJsonDocument raise @hal.EcError {
  guard json
    is { "devices": Array(devices_json), "modules": Array(modules_json), .. } else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: missing devices/modules arrays",
    )
  }
  {
    devices: devices_json.map(device_json => parse_esi_json_device(device_json)),
    modules: modules_json.map(module_json => parse_esi_json_module(module_json)),
  }
}

///|
fn parse_esi_json_device(json : Json) -> EsiJsonDevice raise @hal.EcError {
  guard json
    is {
      "vendor_id": vendor_id_json,
      "product_code": product_code_json,
      "revision": revision_json,
      "serial": serial_json,
      "physics": physics_json,
      "device_name": device_name_json,
      "type_name": type_name_json,
      "slot_index_increment": slot_index_increment_json,
      "slot_pdo_increment": slot_pdo_increment_json,
      "mailbox": mailbox_json,
      "fmmu": Array(fmmu_json),
      "sync_managers": Array(sync_managers_json),
      "dc_modes": Array(dc_modes_json),
      "eeprom_byte_size": eeprom_byte_size_json,
      "config_data": config_data_json,
      "bootstrap": bootstrap_json,
      "default_modules": Array(default_modules_json),
      "rx_pdos": Array(rx_pdos_json),
      "tx_pdos": Array(tx_pdos_json),
      ..
    } else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: invalid device entry",
    )
  }
  {
    vendor_id: decode_esi_json_uint(vendor_id_json),
    product_code: decode_esi_json_uint(product_code_json),
    revision: decode_esi_json_uint(revision_json),
    serial: decode_esi_json_uint(serial_json),
    physics: decode_esi_json_string(physics_json),
    device_name: decode_esi_json_string(device_name_json),
    type_name: decode_esi_json_string(type_name_json),
    slot_index_increment: decode_esi_json_uint(slot_index_increment_json),
    slot_pdo_increment: decode_esi_json_uint(slot_pdo_increment_json),
    mailbox: parse_esi_json_mailbox(mailbox_json),
    fmmu: fmmu_json.map(item => decode_esi_json_string(item)),
    sync_managers: sync_managers_json.map(item => parse_esi_json_sm_entry(item)),
    dc_modes: dc_modes_json.map(item => parse_esi_json_dc_mode(item)),
    eeprom_byte_size: decode_esi_json_uint(eeprom_byte_size_json),
    config_data: decode_esi_json_bytes(config_data_json),
    bootstrap: decode_esi_json_bytes(bootstrap_json),
    default_modules: default_modules_json.map(item => {
      parse_esi_json_selected_module(item)
    }),
    rx_pdos: rx_pdos_json.map(item => parse_esi_json_pdo(item)),
    tx_pdos: tx_pdos_json.map(item => parse_esi_json_pdo(item)),
  }
}

///|
fn parse_esi_json_module(json : Json) -> EsiJsonModule raise @hal.EcError {
  guard json
    is {
      "module_ident": module_ident_json,
      "module_name": module_name_json,
      "rx_pdos": Array(rx_pdos_json),
      "tx_pdos": Array(tx_pdos_json),
      ..
    } else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: invalid module entry",
    )
  }
  {
    module_ident: decode_esi_json_uint(module_ident_json),
    module_name: decode_esi_json_string(module_name_json),
    rx_pdos: rx_pdos_json.map(item => parse_esi_json_pdo(item)),
    tx_pdos: tx_pdos_json.map(item => parse_esi_json_pdo(item)),
  }
}

///|
fn parse_esi_json_mailbox(json : Json) -> EsiJsonMailbox raise @hal.EcError {
  guard json
    is {
      "data_link_layer": data_link_layer_json,
      "aoe": aoe_json,
      "coe_present": coe_present_json,
      "coe_sdo_info": coe_sdo_info_json,
      "coe_pdo_assign": coe_pdo_assign_json,
      "coe_pdo_config": coe_pdo_config_json,
      "coe_complete_access": coe_complete_access_json,
      "eoe": eoe_json,
      "foe": foe_json,
      "soe": soe_json,
      "voe": voe_json,
      ..
    } else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: invalid mailbox entry",
    )
  }
  {
    data_link_layer: decode_esi_json_bool(data_link_layer_json),
    aoe: decode_esi_json_bool(aoe_json),
    coe_present: decode_esi_json_bool(coe_present_json),
    coe_sdo_info: decode_esi_json_bool(coe_sdo_info_json),
    coe_pdo_assign: decode_esi_json_bool(coe_pdo_assign_json),
    coe_pdo_config: decode_esi_json_bool(coe_pdo_config_json),
    coe_complete_access: decode_esi_json_bool(coe_complete_access_json),
    eoe: decode_esi_json_bool(eoe_json),
    foe: decode_esi_json_bool(foe_json),
    soe: decode_esi_json_bool(soe_json),
    voe: decode_esi_json_bool(voe_json),
  }
}

///|
fn parse_esi_json_sm_entry(json : Json) -> EsiJsonSmEntry raise @hal.EcError {
  guard json
    is {
      "physical_start": physical_start_json,
      "length": length_json,
      "control": control_json,
      "status": status_json,
      "enable": enable_json,
      "sm_type": sm_type_json,
      ..
    } else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: invalid sync manager entry",
    )
  }
  {
    physical_start: decode_esi_json_uint(physical_start_json),
    length: decode_esi_json_uint(length_json),
    control: decode_esi_json_byte(control_json),
    status: decode_esi_json_byte(status_json),
    enable: decode_esi_json_bool(enable_json),
    sm_type: decode_esi_json_string(sm_type_json),
  }
}

///|
fn parse_esi_json_pdo(json : Json) -> EsiJsonPdo raise @hal.EcError {
  guard json
    is {
      "direction": direction_json,
      "base_index": base_index_json,
      "depend_on_slot_pdo": depend_on_slot_pdo_json,
      "sync_manager": sync_manager_json,
      "name": name_json,
      "entries": Array(entries_json),
      ..
    } else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: invalid PDO entry",
    )
  }
  {
    direction: decode_esi_json_string(direction_json),
    base_index: decode_esi_json_uint(base_index_json),
    depend_on_slot_pdo: decode_esi_json_bool(depend_on_slot_pdo_json),
    sync_manager: decode_esi_json_byte(sync_manager_json),
    name: decode_esi_json_string(name_json),
    entries: entries_json.map(item => parse_esi_json_pdo_entry(item)),
  }
}

///|
fn parse_esi_json_pdo_entry(json : Json) -> EsiJsonPdoEntry raise @hal.EcError {
  guard json
    is {
      "base_index": base_index_json,
      "depend_on_slot_index": depend_on_slot_index_json,
      "subindex": subindex_json,
      "bit_length": bit_length_json,
      "name": name_json,
      "data_type_name": data_type_name_json,
      ..
    } else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: invalid PDO entry item",
    )
  }
  {
    base_index: decode_esi_json_uint(base_index_json),
    depend_on_slot_index: decode_esi_json_bool(depend_on_slot_index_json),
    subindex: decode_esi_json_byte(subindex_json),
    bit_length: decode_esi_json_byte(bit_length_json),
    name: decode_esi_json_string(name_json),
    data_type_name: decode_esi_json_string(data_type_name_json),
  }
}

///|
fn parse_esi_json_dc_mode(json : Json) -> EsiJsonDcMode raise @hal.EcError {
  guard json
    is {
      "name": name_json,
      "description": description_json,
      "assign_activate": assign_activate_json,
      "cycle_time_sync0": cycle_time_sync0_json,
      "sync0_factor": sync0_factor_json,
      "sync1_factor": sync1_factor_json,
      ..
    } else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: invalid DC entry",
    )
  }
  {
    name: decode_esi_json_string(name_json),
    description: decode_esi_json_string(description_json),
    assign_activate: decode_esi_json_uint(assign_activate_json),
    cycle_time_sync0: decode_esi_json_uint(cycle_time_sync0_json),
    sync0_factor: decode_esi_json_int(sync0_factor_json),
    sync1_factor: decode_esi_json_int(sync1_factor_json),
  }
}

///|
fn parse_esi_json_selected_module(
  json : Json,
) -> EsiJsonSelectedModule raise @hal.EcError {
  guard json
    is { "module_ident": module_ident_json, "slot_index": slot_index_json, .. } else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: invalid selected module entry",
    )
  }
  {
    module_ident: decode_esi_json_uint(module_ident_json),
    slot_index: decode_esi_json_int(slot_index_json),
  }
}

///|
fn decode_esi_json_string(json : Json) -> String raise @hal.EcError {
  @json.from_json(json) catch {
    err =>
      raise @hal.EcError::EsiParseFailed(
        "ESI JSON decode failed: " + err.to_string(),
      )
  }
}

///|
fn decode_esi_json_uint(json : Json) -> UInt raise @hal.EcError {
  @json.from_json(json) catch {
    err =>
      raise @hal.EcError::EsiParseFailed(
        "ESI JSON decode failed: " + err.to_string(),
      )
  }
}

///|
fn decode_esi_json_int(json : Json) -> Int raise @hal.EcError {
  @json.from_json(json) catch {
    err =>
      raise @hal.EcError::EsiParseFailed(
        "ESI JSON decode failed: " + err.to_string(),
      )
  }
}

///|
fn decode_esi_json_bool(json : Json) -> Bool raise @hal.EcError {
  @json.from_json(json) catch {
    err =>
      raise @hal.EcError::EsiParseFailed(
        "ESI JSON decode failed: " + err.to_string(),
      )
  }
}

///|
fn decode_esi_json_byte(json : Json) -> Byte raise @hal.EcError {
  let value = decode_esi_json_int(json)
  if value < 0 || value > 255 {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: byte value out of range",
    )
  }
  value.to_byte()
}

///|
fn decode_esi_json_bytes(json : Json) -> Bytes raise @hal.EcError {
  let direct_result : Result[Bytes, Error] = try? ({
    let decoded : Bytes = @json.from_json(json)
    decoded
  })
  match direct_result {
    Ok(decoded) => return decoded
    Err(_) => ()
  }
  guard json is Array(byte_json) else {
    raise @hal.EcError::EsiParseFailed(
      "ESI JSON decode failed: expected byte array",
    )
  }
  let values : Array[Byte] = []
  for item in byte_json {
    values.push(decode_esi_json_byte(item))
  }
  Bytes::from_array(values)
}

///|
fn build_offline_sii_report(
  device : EsiJsonDevice,
  modules : Array[EsiJsonModule],
  device_index : Int,
) -> EsiOfflineSiiReport raise @hal.EcError {
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
  let fmmu = device.fmmu.map(direction => map_esi_json_fmmu_direction(direction))
  let sync_managers = device.sync_managers.map(sm => {
    materialize_sii_sm_entry(sm)
  })
  let tx_pdo = tx_pdo_projection.map(pdo => materialize_sii_pdo(pdo, strings))
  let rx_pdo = rx_pdo_projection.map(pdo => materialize_sii_pdo(pdo, strings))
  let dc_clocks = device.dc_modes.map(dc => materialize_sii_dc(dc, strings))
  let categories = build_sii_categories(
    fmmu, sync_managers, strings, general, tx_pdo, rx_pdo, dc_clocks,
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
    header: build_sii_header(device, sync_managers),
    general: Some(general),
    strings,
    fmmu,
    sync_managers,
    dc_clocks,
    tx_pdo,
    rx_pdo,
    categories,
  }
}

///|
fn resolve_selected_module_pdos(
  device : EsiJsonDevice,
  modules : Array[EsiJsonModule],
) -> (Array[EsiJsonPdo], Array[EsiJsonPdo]) {
  let tx_pdos : Array[EsiJsonPdo] = []
  let rx_pdos : Array[EsiJsonPdo] = []
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
  modules : Array[EsiJsonModule],
  module_ident : UInt,
) -> EsiJsonModule? {
  for module_projection in modules {
    if module_projection.module_ident == module_ident {
      return Some(module_projection)
    }
  }
  None
}

///|
fn apply_slot_selection(
  device : EsiJsonDevice,
  pdo : EsiJsonPdo,
  slot_index : Int,
) -> EsiJsonPdo {
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
  device : EsiJsonDevice,
  tx_pdos : Array[EsiJsonPdo],
  rx_pdos : Array[EsiJsonPdo],
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
fn preferred_device_group_name(device : EsiJsonDevice) -> String {
  if device.type_name != "" {
    device.type_name
  } else {
    device.device_name
  }
}

///|
fn preferred_device_name(device : EsiJsonDevice) -> String {
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
  device : EsiJsonDevice,
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
    current_on_ebus: 0,
    physical_port_0: ports[0],
    physical_port_1: ports[1],
    physical_port_2: ports[2],
    physical_port_3: ports[3],
    physical_memory_address: 0U,
  }
}

///|
fn build_coe_details_byte(mailbox : EsiJsonMailbox) -> Byte {
  (if mailbox.coe_present { b'\x01' } else { b'\x00' }) |
  (if mailbox.coe_sdo_info { b'\x02' } else { b'\x00' }) |
  (if mailbox.coe_pdo_assign { b'\x04' } else { b'\x00' }) |
  (if mailbox.coe_pdo_config { b'\x08' } else { b'\x00' }) |
  (if mailbox.coe_complete_access { b'\x20' } else { b'\x00' })
}

///|
fn build_general_flags(device : EsiJsonDevice) -> Byte {
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
fn materialize_sii_sm_entry(sm : EsiJsonSmEntry) -> @mailbox.SiiSmEntry {
  {
    physical_start: sm.physical_start,
    length: sm.length,
    control: sm.control,
    status: sm.status,
    activate: if sm.enable {
      b'\x01'
    } else {
      b'\x00'
    },
    sm_type: map_esi_json_sm_type(sm.sm_type),
  }
}

///|
fn materialize_sii_pdo(
  pdo : EsiJsonPdo,
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
  dc : EsiJsonDcMode,
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
fn map_esi_json_fmmu_direction(direction : String) -> @mailbox.FmmuDirection {
  match direction {
    "outputs" => Outputs
    "inputs" => Inputs
    _ => MailboxState
  }
}

///|
fn map_esi_json_sm_type(sm_type : String) -> @mailbox.SmType {
  match sm_type {
    "mailbox-out" => MailboxOut
    "mailbox-in" => MailboxIn
    "process-data-out" => ProcessDataOut
    "process-data-in" => ProcessDataIn
    _ => Unused
  }
}

///|
fn build_sii_preamble(device : EsiJsonDevice) -> @mailbox.SiiPreamble {
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
fn build_sii_header(
  device : EsiJsonDevice,
  sync_managers : Array[@mailbox.SiiSmEntry],
) -> @mailbox.SiiData {
  {
    vendor_id: device.vendor_id,
    product_code: device.product_code,
    revision: device.revision,
    serial: device.serial,
    bootstrap_rx_offset: read_u16_from_bytes(device.bootstrap, 0),
    bootstrap_rx_size: read_u16_from_bytes(device.bootstrap, 2),
    bootstrap_tx_offset: read_u16_from_bytes(device.bootstrap, 4),
    bootstrap_tx_size: read_u16_from_bytes(device.bootstrap, 6),
    mailbox_rx_offset: if sync_managers.length() > 0 {
      sync_managers[0].physical_start
    } else {
      0U
    },
    mailbox_rx_size: if sync_managers.length() > 0 {
      sync_managers[0].length
    } else {
      0U
    },
    mailbox_tx_offset: if sync_managers.length() > 1 {
      sync_managers[1].physical_start
    } else {
      0U
    },
    mailbox_tx_size: if sync_managers.length() > 1 {
      sync_managers[1].length
    } else {
      0U
    },
    mailbox_protocols: build_mailbox_protocol_mask(device.mailbox),
  }
}

///|
fn build_mailbox_protocol_mask(mailbox : EsiJsonMailbox) -> UInt {
  (if mailbox.aoe { esi_mailbox_aoe_mask } else { 0U }) |
  (if mailbox.eoe { esi_mailbox_eoe_mask } else { 0U }) |
  (if mailbox.coe_present { esi_mailbox_coe_mask } else { 0U }) |
  (if mailbox.foe { esi_mailbox_foe_mask } else { 0U }) |
  (if mailbox.soe { esi_mailbox_soe_mask } else { 0U }) |
  (if mailbox.voe { esi_mailbox_voe_mask } else { 0U })
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
  fmmu : Array[@mailbox.FmmuDirection],
  sync_managers : Array[@mailbox.SiiSmEntry],
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
  if not(fmmu.is_empty()) {
    categories.push({ category: Fmmu, data: encode_sii_fmmu(fmmu) })
  }
  if not(sync_managers.is_empty()) {
    categories.push({
      category: SyncManager,
      data: encode_sii_sync_managers(sync_managers),
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
  push_i16(values, general.current_on_ebus)
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
    values.push(sm.activate)
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
