///|
/// Fail-closed rejection from the embedded ESI profile pipeline.
pub(all) suberror DeviceProfileError {
  InvalidAssetId(String)
  AssetTooLarge(String, Int)
  InvalidDigest(String)
  SourceDigestMismatch(String, String, String)
  InvalidUtf8(String)
  InvalidEsi(String, String)
  EmptyCandidate(String)
  DuplicateAsset(String)
  DuplicateProfile(String)
  MissingProfile(String)
  DuplicateSelection(String)
  ProfileDigestMismatch(String, String, String)
  InvalidBinding(String)
} derive(Eq, Debug)

///|
let max_esi_asset_bytes : Int = 4 * 1024 * 1024

///|
fn validate_asset_id(asset_id : String) -> Unit raise DeviceProfileError {
  let bytes = @utf8.encode(asset_id)
  if bytes.length() == 0 || bytes.length() > 128 {
    raise InvalidAssetId(asset_id)
  }
  for byte in bytes {
    let code = byte.to_int()
    let valid = (code >= b'a'.to_int() && code <= b'z'.to_int()) ||
      (code >= b'A'.to_int() && code <= b'Z'.to_int()) ||
      (code >= b'0'.to_int() && code <= b'9'.to_int()) ||
      code == b'.'.to_int() ||
      code == b'_'.to_int() ||
      code == b'-'.to_int() ||
      code == b'/'.to_int()
    if !valid {
      raise InvalidAssetId(asset_id)
    }
  }
}

///|
fn validate_binding_id(
  kind : String,
  value : String,
) -> Unit raise DeviceProfileError {
  let bytes = @utf8.encode(value)
  if bytes.length() == 0 || bytes.length() > 128 {
    raise InvalidBinding(kind + " must contain 1..128 bytes")
  }
  for byte in bytes {
    let code = byte.to_int()
    let valid = (code >= b'a'.to_int() && code <= b'z'.to_int()) ||
      (code >= b'A'.to_int() && code <= b'Z'.to_int()) ||
      (code >= b'0'.to_int() && code <= b'9'.to_int()) ||
      code == b'.'.to_int() ||
      code == b'_'.to_int() ||
      code == b'-'.to_int() ||
      code == b'/'.to_int()
    if !valid {
      raise InvalidBinding(kind + " contains an unsupported byte")
    }
  }
}

///|
fn validate_sha256(value : String) -> Unit raise DeviceProfileError {
  let bytes = @utf8.encode(value)
  if bytes.length() != 64 {
    raise InvalidDigest(value)
  }
  for byte in bytes {
    let code = byte.to_int()
    let valid = (code >= b'0'.to_int() && code <= b'9'.to_int()) ||
      (code >= b'a'.to_int() && code <= b'f'.to_int())
    if !valid {
      raise InvalidDigest(value)
    }
  }
}

///|
fn sha256_hex(value : Bytes) -> String {
  let builder = StringBuilder::new()
  for byte in @crypto.sha256(value) {
    builder.write_string(byte.to_hex())
  }
  builder.to_string()
}

///|
fn digest_record(domain : String, fields : Array[String]) -> String {
  let builder = StringBuilder::new()
  write_digest_field(builder, domain)
  for field in fields {
    write_digest_field(builder, field)
  }
  sha256_hex(@utf8.encode(builder.to_string()))
}

///|
fn write_digest_field(builder : StringBuilder, field : String) -> Unit {
  let bytes = @utf8.encode(field)
  builder.write_string(bytes.length().to_string())
  builder.write_string(":")
  builder.write_string(field)
}

///|
fn compare_profile_text(left : String, right : String) -> Int {
  if left < right {
    1
  } else if left > right {
    -1
  } else {
    0
  }
}

///|
fn option_uint_text(value : UInt?) -> String {
  match value {
    Some(actual) => "some:" + actual.to_string()
    None => "none"
  }
}
