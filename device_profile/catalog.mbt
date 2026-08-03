///|
/// Exact identity and digest requested from a preview.
pub struct DeviceProfileSelection {
  priv source_asset_id : String
  priv vendor_id : UInt
  priv product_code : UInt
  priv revision : UInt
  priv expected_profile_digest : String
}

///|
pub fn DeviceProfileSelection::new(
  source_asset_id~ : String,
  vendor_id~ : UInt,
  product_code~ : UInt,
  revision~ : UInt,
  expected_profile_digest~ : String,
) -> DeviceProfileSelection raise DeviceProfileError {
  validate_asset_id(source_asset_id)
  validate_sha256(expected_profile_digest)
  {
    source_asset_id,
    vendor_id,
    product_code,
    revision,
    expected_profile_digest,
  }
}

///|
pub fn DeviceProfileSelection::source_asset_id(
  self : DeviceProfileSelection,
) -> String {
  self.source_asset_id
}

///|
pub fn DeviceProfileSelection::vendor_id(self : DeviceProfileSelection) -> UInt {
  self.vendor_id
}

///|
pub fn DeviceProfileSelection::product_code(
  self : DeviceProfileSelection,
) -> UInt {
  self.product_code
}

///|
pub fn DeviceProfileSelection::revision(self : DeviceProfileSelection) -> UInt {
  self.revision
}

///|
pub fn DeviceProfileSelection::expected_profile_digest(
  self : DeviceProfileSelection,
) -> String {
  self.expected_profile_digest
}

///|
fn DeviceProfileSelection::selection_key(
  self : DeviceProfileSelection,
) -> String {
  digest_record("moonecat.device-profile.selection.v1", [
    self.source_asset_id,
    self.vendor_id.to_string(),
    self.product_code.to_string(),
    self.revision.to_string(),
  ])
}

///|
pub struct DeviceProfilePreview {
  priv candidates : Array[DeviceProfileCandidate]
  priv profiles : Array[DeviceProfile]
  priv digest : String
}

///|
pub fn DeviceProfilePreview::new(
  candidates : Array[DeviceProfileCandidate],
) -> DeviceProfilePreview raise DeviceProfileError {
  if candidates.length() == 0 {
    raise EmptyCandidate("preview")
  }
  let owned_candidates = candidates.copy()
  let profiles : Array[DeviceProfile] = []
  for index, candidate in owned_candidates {
    for prior_index in 0..<index {
      if owned_candidates[prior_index].asset_id() == candidate.asset_id() {
        raise DuplicateAsset(candidate.asset_id())
      }
    }
    for profile in candidate.profiles() {
      for existing in profiles {
        if existing.identity_key() == profile.identity_key() {
          raise DuplicateProfile(profile_identity_label(profile))
        }
      }
      profiles.push(profile)
    }
  }
  let digest_fields = owned_candidates.map(candidate => candidate.digest())
  digest_fields.sort_by(compare_profile_text)
  let digest = digest_record(
    "moonecat.device-profile.preview.v1", digest_fields,
  )
  { candidates: owned_candidates, profiles, digest }
}

///|
pub fn DeviceProfilePreview::candidates(
  self : DeviceProfilePreview,
) -> Array[DeviceProfileCandidate] {
  self.candidates.copy()
}

///|
pub fn DeviceProfilePreview::profiles(
  self : DeviceProfilePreview,
) -> Array[DeviceProfile] {
  self.profiles.copy()
}

///|
pub fn DeviceProfilePreview::digest(self : DeviceProfilePreview) -> String {
  self.digest
}

///|
/// Runtime-capable wrapper produced only by catalog activation.
pub struct ActivatedDeviceProfile {
  priv profile : DeviceProfile
}

///|
pub fn ActivatedDeviceProfile::profile(
  self : ActivatedDeviceProfile,
) -> DeviceProfile {
  self.profile
}

///|
pub fn ActivatedDeviceProfile::typed_document(
  self : ActivatedDeviceProfile,
) -> @runtime.EsiJsonDocument raise DeviceProfileError {
  self.profile.typed_document()
}

///|
pub fn ActivatedDeviceProfile::digest(self : ActivatedDeviceProfile) -> String {
  self.profile.digest()
}

///|
pub struct DeviceProfileCatalog {
  priv profiles : Array[ActivatedDeviceProfile]
  priv digest : String
}

///|
pub fn DeviceProfileCatalog::activate(
  preview : DeviceProfilePreview,
  selections : Array[DeviceProfileSelection],
) -> DeviceProfileCatalog raise DeviceProfileError {
  if selections.length() == 0 {
    raise MissingProfile("activation selection is empty")
  }
  let activated : Array[ActivatedDeviceProfile] = []
  for index, selection in selections {
    for prior_index in 0..<index {
      if selections[prior_index].selection_key() == selection.selection_key() {
        raise DuplicateSelection(selection_label(selection))
      }
    }
    let mut selected : DeviceProfile? = None
    for profile in preview.profiles {
      if profile.selection_key() == selection.selection_key() {
        selected = Some(profile)
      }
    }
    guard selected is Some(profile) else {
      raise MissingProfile(selection_label(selection))
    }
    if profile.digest() != selection.expected_profile_digest() {
      raise ProfileDigestMismatch(
        selection_label(selection),
        selection.expected_profile_digest(),
        profile.digest(),
      )
    }
    activated.push({ profile, })
  }
  let digest_fields = activated.map(profile => profile.digest())
  digest_fields.sort_by(compare_profile_text)
  let digest = digest_record(
    "moonecat.device-profile.catalog.v1", digest_fields,
  )
  { profiles: activated, digest }
}

///|
pub fn DeviceProfileCatalog::profiles(
  self : DeviceProfileCatalog,
) -> Array[ActivatedDeviceProfile] {
  self.profiles.copy()
}

///|
pub fn DeviceProfileCatalog::digest(self : DeviceProfileCatalog) -> String {
  self.digest
}

///|
/// Resolve only a fully pinned selection. There is deliberately no name,
/// product-only, or highest-revision lookup.
pub fn DeviceProfileCatalog::resolve_exact(
  self : DeviceProfileCatalog,
  selection : DeviceProfileSelection,
) -> ActivatedDeviceProfile raise DeviceProfileError {
  for profile in self.profiles {
    if profile.profile.selection_key() == selection.selection_key() {
      if profile.digest() != selection.expected_profile_digest() {
        raise ProfileDigestMismatch(
          selection_label(selection),
          selection.expected_profile_digest(),
          profile.digest(),
        )
      }
      return profile
    }
  }
  raise MissingProfile(selection_label(selection))
}

///|
fn selection_label(selection : DeviceProfileSelection) -> String {
  selection.source_asset_id() +
  ":" +
  selection.vendor_id().to_string() +
  ":" +
  selection.product_code().to_string() +
  ":" +
  selection.revision().to_string()
}
