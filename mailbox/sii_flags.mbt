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
