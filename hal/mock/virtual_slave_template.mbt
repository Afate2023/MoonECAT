///|
/// VirtualSlaveTemplate describes a generated VirtualSlave configuration
/// derived from ESI/SII offline projection. It captures the synthesized
/// SII EEPROM, identity, and startup preparation so that a VirtualSlave
/// (or an array for VirtualBus) can be instantiated without hardware.
pub(all) struct VirtualSlaveTemplate {
  identity : @hal.SlaveIdentity
  sii_eeprom : Bytes
  startup_preparation : @runtime.SlaveStartupPreparation
}

///|
/// Generate a VirtualSlaveTemplate from an ESI offline SII report.
pub fn VirtualSlaveTemplate::from_esi_report(
  report : @runtime.EsiOfflineSiiReport,
  logical_base : UInt,
) -> VirtualSlaveTemplate {
  let identity : @hal.SlaveIdentity = {
    vendor_id: report.header.vendor_id,
    product_code: report.header.product_code,
    revision: report.header.revision,
    serial: report.header.serial,
  }
  let startup_preparation = @runtime.startup_preparation_from_esi_offline_report(
    report, logical_base,
  )
  { identity, sii_eeprom: report.eeprom, startup_preparation }
}

///|
/// Generate VirtualSlaveTemplates from an ESI JSON document.
/// One template per device entry in the document.
pub fn virtual_slave_templates_from_esi_document(
  document : @runtime.EsiJsonDocument,
) -> Array[VirtualSlaveTemplate] raise @hal.EcError {
  let templates : Array[VirtualSlaveTemplate] = []
  for i = 0; i < document.devices.length(); i = i + 1 {
    let report = @runtime.offline_sii_report_from_esi_document(document, i)
    templates.push(VirtualSlaveTemplate::from_esi_report(report, 0U))
  }
  templates
}

///|
/// Parse ESI JSON text and generate VirtualSlaveTemplates.
pub fn virtual_slave_templates_from_esi_json(
  json_content : String,
) -> Array[VirtualSlaveTemplate] raise @hal.EcError {
  let document = @runtime.parse_esi_json_document(json_content)
  virtual_slave_templates_from_esi_document(document)
}

///|
/// Create a VirtualSlave from this template at the given bus position.
pub fn VirtualSlaveTemplate::to_virtual_slave(
  self : VirtualSlaveTemplate,
  position : Int,
) -> VirtualSlave {
  VirtualSlave::new(position, self.identity, self.sii_eeprom)
}

///|
/// Build a VirtualBus from an ESI JSON document, one slave per device entry.
pub fn VirtualBus::from_esi_json(
  json_content : String,
) -> (VirtualBus, Array[VirtualSlaveTemplate]) raise @hal.EcError {
  let templates = virtual_slave_templates_from_esi_json(json_content)
  let slaves : Array[VirtualSlave] = []
  for i = 0; i < templates.length(); i = i + 1 {
    slaves.push(templates[i].to_virtual_slave(i))
  }
  (VirtualBus::new(slaves), templates)
}

///|
/// Build a VirtualBus from pre-built templates.
pub fn VirtualBus::from_templates(
  templates : Array[VirtualSlaveTemplate],
) -> VirtualBus {
  let slaves : Array[VirtualSlave] = []
  for i = 0; i < templates.length(); i = i + 1 {
    slaves.push(templates[i].to_virtual_slave(i))
  }
  VirtualBus::new(slaves)
}
