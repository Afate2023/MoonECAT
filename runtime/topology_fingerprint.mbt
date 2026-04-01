///|
/// TopologyFingerprint captures the essential topology identity as
/// a compact, comparable value. Two fingerprints are equal iff the
/// slave count and ordered identity sequence match exactly.
pub(all) struct TopologyFingerprint {
  slave_count : Int
  identity_hash : Int64
} derive(Eq, Show)

///|
/// TopologyFingerprintMatch describes how two fingerprints differ.
pub(all) enum TopologyFingerprintMatch {
  Identical
  SlaveCountChanged(expected~ : Int, actual~ : Int)
  IdentityChanged
} derive(Eq, Show)

///|
/// FNV-1a 64-bit prime.
let fnv64_prime : Int64 = 0x00000100000001b3L

///|
/// FNV-1a 64-bit offset basis (0xcbf29ce484222325 as signed Int64).
let fnv64_offset_basis : Int64 = -3750763034362895579L

///|
/// Mix one byte into an FNV-1a 64-bit hash state.
fn fnv1a_byte(h : Int64, b : Int64) -> Int64 {
  (h ^ b) * fnv64_prime
}

///|
/// Mix a UInt (4 bytes, little-endian) into an FNV-1a 64-bit hash state.
fn fnv1a_uint(h : Int64, v : UInt) -> Int64 {
  let mut h = h
  h = fnv1a_byte(h, (v & 0xFFU).to_int64())
  h = fnv1a_byte(h, ((v >> 8) & 0xFFU).to_int64())
  h = fnv1a_byte(h, ((v >> 16) & 0xFFU).to_int64())
  h = fnv1a_byte(h, ((v >> 24) & 0xFFU).to_int64())
  h
}

///|
fn hash_identity(
  acc : Int64,
  vendor_id : UInt,
  product_code : UInt,
  revision : UInt,
  serial : UInt,
) -> Int64 {
  let mut h = acc
  h = fnv1a_uint(h, vendor_id)
  h = fnv1a_uint(h, product_code)
  h = fnv1a_uint(h, revision)
  h = fnv1a_uint(h, serial)
  h
}

///|
/// Compute a topology fingerprint from a ScanReport.
pub fn topology_fingerprint(scan : ScanReport) -> TopologyFingerprint {
  let mut h : Int64 = fnv64_offset_basis
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
  let mut h : Int64 = fnv64_offset_basis
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
      None => h = hash_identity(h, 0U, 0U, 0U, 0U)
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
