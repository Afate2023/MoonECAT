///|
/// ESI/SII General flags bit extraction helpers.
/// Per ETG.2000 Table 3 — SII General Category, Byte Offset 11.

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
/// Check if the slave supports Explicit Device Identification (IdentificationAdo).
/// Used for Hot Connect verification.
pub fn SiiGeneral::supports_identification_ado(self : SiiGeneral) -> Bool {
  (self.flags & b'\x08') != b'\x00'
}
