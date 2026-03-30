///|
/// ESI/SII General flags bit extraction helpers.
/// Per ETG.2000 Table 3 — SII General Category, Byte Offset 11.

///|
/// Check if CoE SDO upload/download services are supported.
pub fn SiiGeneral::supports_coe_sdo(self : SiiGeneral) -> Bool {
  (self.coe_details & b'\x01') != b'\x00'
}

///|
/// Check if CoE SDO Information services are supported.
pub fn SiiGeneral::supports_coe_sdo_info(self : SiiGeneral) -> Bool {
  (self.coe_details & b'\x02') != b'\x00'
}

///|
/// Check if CoE PDO assignment objects are writable/configurable.
pub fn SiiGeneral::supports_coe_pdo_assign(self : SiiGeneral) -> Bool {
  (self.coe_details & b'\x04') != b'\x00'
}

///|
/// Check if CoE PDO mapping objects are writable/configurable.
pub fn SiiGeneral::supports_coe_pdo_configuration(self : SiiGeneral) -> Bool {
  (self.coe_details & b'\x08') != b'\x00'
}

///|
/// Check if CoE upload at startup is supported.
pub fn SiiGeneral::supports_coe_upload_at_startup(self : SiiGeneral) -> Bool {
  (self.coe_details & b'\x10') != b'\x00'
}

///|
/// Check if CoE Complete Access is supported.
pub fn SiiGeneral::supports_coe_complete_access(self : SiiGeneral) -> Bool {
  (self.coe_details & b'\x20') != b'\x00'
}

///|
/// Check if the slave's OpOnly flag is set.
/// When true, output data is only valid in Operational state;
/// the master should disable output SM in non-Op states.
pub fn SiiGeneral::is_op_only(self : SiiGeneral) -> Bool {
  (self.flags & b'\x01') != b'\x00'
}

///|
/// Check if the slave prefers separate LRD/LWR instead of LRW.
/// When true, the master should use LRD + LWR instead of LRW for PDO exchange.
pub fn SiiGeneral::prefers_not_lrw(self : SiiGeneral) -> Bool {
  (self.flags & b'\x02') != b'\x00'
}

///|
/// Check if resilient mailbox handling via Data Link Layer is supported.
pub fn SiiGeneral::supports_mailbox_data_link_layer(self : SiiGeneral) -> Bool {
  (self.flags & b'\x04') != b'\x00'
}

///|
/// Check if the slave supports Explicit Device Identification (IdentificationAdo).
/// Used for Hot Connect verification.
pub fn SiiGeneral::supports_identification_ado(self : SiiGeneral) -> Bool {
  (self.flags & b'\x08') != b'\x00'
}

///|
/// Check if the slave supports Explicit Device Identification via Physical Memory.
pub fn SiiGeneral::supports_identification_physical_memory(
  self : SiiGeneral,
) -> Bool {
  (self.flags & b'\x10') != b'\x00'
}

///|
/// Supported mailbox protocol bit helpers from the SII header mailbox protocol mask.
pub fn SiiData::supports_aoe(self : SiiData) -> Bool {
  (self.mailbox_protocols & 0x0001U) != 0U
}

///|
pub fn SiiData::supports_eoe(self : SiiData) -> Bool {
  (self.mailbox_protocols & 0x0002U) != 0U
}

///|
pub fn SiiData::supports_coe(self : SiiData) -> Bool {
  (self.mailbox_protocols & 0x0004U) != 0U
}

///|
pub fn SiiData::supports_foe(self : SiiData) -> Bool {
  (self.mailbox_protocols & 0x0008U) != 0U
}

///|
pub fn SiiData::supports_soe(self : SiiData) -> Bool {
  (self.mailbox_protocols & 0x0010U) != 0U
}

///|
pub fn SiiData::supports_voe(self : SiiData) -> Bool {
  (self.mailbox_protocols & 0x0020U) != 0U
}

///|
/// PDO flags bit 0: PDO is mandatory.
pub fn SiiPdo::is_mandatory(self : SiiPdo) -> Bool {
  (self.flags & 0x0001U) != 0U
}

///|
/// PDO flags bit 1: PDO is mapped by default.
pub fn SiiPdo::is_default(self : SiiPdo) -> Bool {
  (self.flags & 0x0002U) != 0U
}

///|
/// PDO flags bit 4: PDO has fixed content (entries cannot be changed).
pub fn SiiPdo::is_fixed_content(self : SiiPdo) -> Bool {
  (self.flags & 0x0010U) != 0U
}

///|
/// PDO flags bit 5: PDO has virtual content.
pub fn SiiPdo::is_virtual_content(self : SiiPdo) -> Bool {
  (self.flags & 0x0020U) != 0U
}

///|
/// PDO flags bit 8: Module alignment for PDO.
pub fn SiiPdo::is_module_align(self : SiiPdo) -> Bool {
  (self.flags & 0x0100U) != 0U
}

///|
/// PDO flags bit 9: PDO index depends on slot.
pub fn SiiPdo::is_depend_on_slot(self : SiiPdo) -> Bool {
  (self.flags & 0x0200U) != 0U
}

///|
/// PDO flags bit 10: PDO index depends on slot group.
pub fn SiiPdo::is_depend_on_slot_group(self : SiiPdo) -> Bool {
  (self.flags & 0x0400U) != 0U
}

///|
/// PDO flags bit 11: PDO is overwritten by module.
pub fn SiiPdo::is_overwritten_by_module(self : SiiPdo) -> Bool {
  (self.flags & 0x0800U) != 0U
}

///|
/// Extract the identification method from the SII General flags (bits 3-4).
/// Returns 0 = none, 1 = IdentALSts, 2 = IdentPhyM, 3 = both.
pub fn SiiGeneral::identification_method(self : SiiGeneral) -> Int {
  (self.flags.to_int() >> 3) & 0x03
}
