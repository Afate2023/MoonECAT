///|
/// One reusable, declared EtherCAT model/revision projected from an ESI asset.
/// It is not an observed physical slave identity.
pub struct DeviceProfile {
  priv source_asset_id : String
  priv source_sha256 : String
  priv vendor_id : UInt
  priv product_code : UInt
  priv revision : UInt
  priv serial : UInt?
  priv physics : String
  priv device_name : String
  priv type_name : String
  priv profile_no : UInt?
  priv canonical_json : String
  priv digest : String
}

///|
pub fn DeviceProfile::source_asset_id(self : DeviceProfile) -> String {
  self.source_asset_id
}

///|
pub fn DeviceProfile::source_sha256(self : DeviceProfile) -> String {
  self.source_sha256
}

///|
pub fn DeviceProfile::vendor_id(self : DeviceProfile) -> UInt {
  self.vendor_id
}

///|
pub fn DeviceProfile::product_code(self : DeviceProfile) -> UInt {
  self.product_code
}

///|
pub fn DeviceProfile::revision(self : DeviceProfile) -> UInt {
  self.revision
}

///|
pub fn DeviceProfile::serial(self : DeviceProfile) -> UInt? {
  self.serial
}

///|
pub fn DeviceProfile::physics(self : DeviceProfile) -> String {
  self.physics
}

///|
pub fn DeviceProfile::device_name(self : DeviceProfile) -> String {
  self.device_name
}

///|
pub fn DeviceProfile::type_name(self : DeviceProfile) -> String {
  self.type_name
}

///|
pub fn DeviceProfile::profile_no(self : DeviceProfile) -> UInt? {
  self.profile_no
}

///|
pub fn DeviceProfile::canonical_json(self : DeviceProfile) -> String {
  self.canonical_json
}

///|
pub fn DeviceProfile::digest(self : DeviceProfile) -> String {
  self.digest
}

///|
/// Decode a fresh document on every access so mutable arrays cannot mutate the
/// activated profile stored in a catalog.
pub fn DeviceProfile::typed_document(
  self : DeviceProfile,
) -> @runtime.EsiJsonDocument raise DeviceProfileError {
  @runtime.parse_esi_json_document(self.canonical_json) catch {
    error => raise InvalidEsi(self.source_asset_id, "\{Repr(error)}")
  }
}

///|
fn DeviceProfile::identity_key(self : DeviceProfile) -> String {
  digest_record("moonecat.device-profile.identity.v1", [
    self.vendor_id.to_string(),
    self.product_code.to_string(),
    self.revision.to_string(),
  ])
}

///|
fn DeviceProfile::selection_key(self : DeviceProfile) -> String {
  digest_record("moonecat.device-profile.selection.v1", [
    self.source_asset_id,
    self.vendor_id.to_string(),
    self.product_code.to_string(),
    self.revision.to_string(),
  ])
}

///|
fn device_profile_from_document(
  asset_id : String,
  source_sha256 : String,
  device : @runtime.EsiJsonDevice,
  modules : Array[@runtime.EsiJsonModule],
) -> DeviceProfile {
  let canonical_json = @runtime.esi_json_to_string(
    { devices: [device], modules: modules.copy() },
    indent=0,
  )
  let digest = digest_record("moonecat.device-profile.v1", [
    asset_id,
    source_sha256,
    device.vendor_id.to_string(),
    device.product_code.to_string(),
    device.revision.to_string(),
    option_uint_text(device.serial),
    canonical_json,
  ])
  {
    source_asset_id: asset_id,
    source_sha256,
    vendor_id: device.vendor_id,
    product_code: device.product_code,
    revision: device.revision,
    serial: device.serial,
    physics: device.physics,
    device_name: device.device_name,
    type_name: device.type_name,
    profile_no: device.profile_no,
    canonical_json,
    digest,
  }
}

///|
/// Immutable result of validating and projecting one bounded embedded asset.
pub struct DeviceProfileCandidate {
  priv asset_id : String
  priv source_sha256 : String
  priv profiles : Array[DeviceProfile]
  priv digest : String
}

///|
pub fn DeviceProfileCandidate::from_esi_xml(
  asset_id~ : String,
  declared_source_sha256~ : String,
  source_bytes : Bytes,
) -> DeviceProfileCandidate raise DeviceProfileError {
  validate_asset_id(asset_id)
  validate_sha256(declared_source_sha256)
  if source_bytes.length() == 0 || source_bytes.length() > max_esi_asset_bytes {
    raise AssetTooLarge(asset_id, source_bytes.length())
  }
  let actual_source_sha256 = sha256_hex(source_bytes)
  if actual_source_sha256 != declared_source_sha256 {
    raise SourceDigestMismatch(
      asset_id, declared_source_sha256, actual_source_sha256,
    )
  }
  let xml = @utf8.decode(source_bytes) catch {
    _ => raise InvalidUtf8(asset_id)
  }
  let document = esi_json_document_from_xml(xml) catch {
    error => raise InvalidEsi(asset_id, "\{Repr(error)}")
  }
  if document.devices.length() == 0 {
    raise EmptyCandidate(asset_id)
  }
  let profiles : Array[DeviceProfile] = []
  for device in document.devices {
    let profile = device_profile_from_document(
      asset_id,
      actual_source_sha256,
      device,
      document.modules,
    )
    for existing in profiles {
      if existing.identity_key() == profile.identity_key() {
        raise DuplicateProfile(profile_identity_label(profile))
      }
    }
    profiles.push(profile)
  }
  let digest_fields = profiles.map(profile => profile.digest())
  digest_fields.sort_by(compare_profile_text)
  let digest = digest_record(
    "moonecat.device-profile.candidate.v1",
    [asset_id, actual_source_sha256, ..digest_fields],
  )
  { asset_id, source_sha256: actual_source_sha256, profiles, digest }
}

///|
pub fn DeviceProfileCandidate::asset_id(
  self : DeviceProfileCandidate,
) -> String {
  self.asset_id
}

///|
pub fn DeviceProfileCandidate::source_sha256(
  self : DeviceProfileCandidate,
) -> String {
  self.source_sha256
}

///|
pub fn DeviceProfileCandidate::profiles(
  self : DeviceProfileCandidate,
) -> Array[DeviceProfile] {
  self.profiles.copy()
}

///|
pub fn DeviceProfileCandidate::digest(self : DeviceProfileCandidate) -> String {
  self.digest
}

///|
fn profile_identity_label(profile : DeviceProfile) -> String {
  profile.vendor_id().to_string() +
  ":" +
  profile.product_code().to_string() +
  ":" +
  profile.revision().to_string()
}
