///|
/// TopologyFingerprint captures the essential topology identity as
/// a compact, comparable value. Two fingerprints are equal iff the
/// slave count and ordered identity sequence match exactly.
pub(all) struct TopologyFingerprint {
  slave_count : Int
  identity_hash : Int64
} derive(Eq, Debug)

///|
/// TopologyFingerprintMatch describes how two fingerprints differ.
pub(all) enum TopologyFingerprintMatch {
  Identical
  SlaveCountChanged(expected~ : Int, actual~ : Int)
  IdentityChanged
} derive(Eq, Debug)

///|
fn hash_identity(
  acc : Int64,
  vendor_id : UInt,
  product_code : UInt,
  revision : UInt,
  serial : UInt,
) -> Int64 {
  let mut h = acc
  h = h * 31L + vendor_id.to_int64()
  h = h * 31L + product_code.to_int64()
  h = h * 31L + revision.to_int64()
  h = h * 31L + serial.to_int64()
  h
}

///|
/// Compute a topology fingerprint from a ScanReport.
pub fn topology_fingerprint(scan : ScanReport) -> TopologyFingerprint {
  let mut h : Int64 = 0x811c9dc5L // FNV offset basis
  let sorted = scan.slaves.copy()
  sorted.sort_by(fn(a, b) { a.position.compare(b.position) })
  for slave in sorted {
    h = hash_identity(
      h,
      slave.vendor_id,
      slave.product_code,
      slave.revision,
      slave.serial,
    )
  }
  { slave_count: scan.slave_count, identity_hash: h }
}

///|
/// Compute a topology fingerprint from a ConfigurationModel.
pub fn topology_fingerprint_from_config(
  config : ConfigurationModel,
) -> TopologyFingerprint {
  let mut h : Int64 = 0x811c9dc5L
  let sorted = config.slaves.copy()
  sorted.sort_by(fn(a, b) { a.position.compare(b.position) })
  for slave in sorted {
    match slave.identity {
      Some(id) =>
        h = hash_identity(
          h,
          id.vendor_id,
          id.product_code,
          id.revision,
          id.serial,
        )
      None => h = h * 31L
    }
  }
  { slave_count: config.total_slaves, identity_hash: h }
}

///|
/// Compare two topology fingerprints.
pub fn fingerprint_match(
  expected : TopologyFingerprint,
  actual : TopologyFingerprint,
) -> TopologyFingerprintMatch {
  if expected == actual {
    Identical
  } else if expected.slave_count != actual.slave_count {
    SlaveCountChanged(expected=expected.slave_count, actual=actual.slave_count)
  } else {
    IdentityChanged
  }
}
