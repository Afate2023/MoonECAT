///|
pub let identity_assurance_scope : String = "moonecat.inspect-bus-identity"

///|
pub(all) suberror IdentityAssuranceDecodeError {
  InvalidIdentityResultArtifact(String)
} derive(Eq, Debug)

///|
fn decoder_sha256_hex(value : Bytes) -> String {
  let output = StringBuilder::new()
  for byte in @crypto.sha256(value) {
    output.write_string(byte.to_hex())
  }
  output.to_string()
}

///|
fn decode_length_framed_fields(
  bytes : Bytes,
) -> Array[String] raise IdentityAssuranceDecodeError {
  if bytes.is_empty() || bytes.length() > 1_048_576 {
    raise InvalidIdentityResultArtifact(
      "canonical result bytes must contain 1..1048576 octets",
    )
  }
  let fields : Array[String] = []
  let mut offset = 0
  while offset < bytes.length() {
    let mut length = 0
    let mut digit_count = 0
    while offset < bytes.length() && bytes[offset] != b':' {
      let value = bytes[offset].to_int() - b'0'.to_int()
      if value < 0 || value > 9 || digit_count >= 7 {
        raise InvalidIdentityResultArtifact("invalid field length prefix")
      }
      length = length * 10 + value
      digit_count = digit_count + 1
      offset = offset + 1
    }
    if digit_count == 0 || offset >= bytes.length() || bytes[offset] != b':' {
      raise InvalidIdentityResultArtifact("truncated field length prefix")
    }
    offset = offset + 1
    if length < 0 || offset + length > bytes.length() {
      raise InvalidIdentityResultArtifact(
        "field payload exceeds artifact bounds",
      )
    }
    let field_bytes = Bytes::makei(length, fn(index) { bytes[offset + index] })
    let field = @utf8.decode(field_bytes) catch {
      _ => raise InvalidIdentityResultArtifact("field payload is not UTF-8")
    }
    fields.push(field)
    offset = offset + length
  }
  fields
}

///|
fn decode_count(value : String) -> Int raise IdentityAssuranceDecodeError {
  let bytes = @utf8.encode(value)
  if bytes.is_empty() || bytes.length() > 6 {
    raise InvalidIdentityResultArtifact("section count is invalid")
  }
  let mut result = 0
  for byte in bytes {
    let digit = byte.to_int() - b'0'.to_int()
    if digit < 0 || digit > 9 {
      raise InvalidIdentityResultArtifact("section count is not decimal")
    }
    result = result * 10 + digit
  }
  result
}

///|
fn decoder_valid_decimal(value : String, max_digits : Int) -> Bool {
  let bytes = @utf8.encode(value)
  if bytes.is_empty() || bytes.length() > max_digits {
    return false
  }
  for byte in bytes {
    if byte < b'0' || byte > b'9' {
      return false
    }
  }
  true
}

///|
fn decoder_valid_optional_digest(value : String) -> Bool {
  if value == "none" {
    return true
  }
  let bytes = @utf8.encode(value)
  if bytes.length() != 69 ||
    bytes[0] != b's' ||
    bytes[1] != b'o' ||
    bytes[2] != b'm' ||
    bytes[3] != b'e' ||
    bytes[4] != b':' {
    return false
  }
  decoder_valid_digest(
    @utf8.decode(Bytes::makei(64, fn(index) { bytes[index + 5] })) catch {
      _ => return false
    },
  )
}

///|
fn decoder_valid_optional_decimal(value : String) -> Bool {
  if value == "none" {
    return true
  }
  let bytes = @utf8.encode(value)
  if bytes.length() <= 5 ||
    bytes[0] != b's' ||
    bytes[1] != b'o' ||
    bytes[2] != b'm' ||
    bytes[3] != b'e' ||
    bytes[4] != b':' {
    return false
  }
  decoder_valid_decimal(
    @utf8.decode(
      Bytes::makei(bytes.length() - 5, fn(index) { bytes[index + 5] }),
    ) catch {
      _ => return false
    },
    6,
  )
}

///|
fn decoder_valid_digest(value : String) -> Bool {
  let bytes = @utf8.encode(value)
  if bytes.length() != 64 {
    return false
  }
  for byte in bytes {
    let code = byte.to_int()
    if !((code >= b'0'.to_int() && code <= b'9'.to_int()) ||
      (code >= b'a'.to_int() && code <= b'f'.to_int())) {
      return false
    }
  }
  true
}

///|
fn consume_section(
  fields : Array[String],
  cursor : Int,
  label : String,
  width : Int,
  max_count : Int,
) -> (Int, Int) raise IdentityAssuranceDecodeError {
  if cursor + 1 >= fields.length() || fields[cursor] != label {
    raise InvalidIdentityResultArtifact(
      "missing or reordered " + label + " section",
    )
  }
  let count = decode_count(fields[cursor + 1])
  if count < 0 || count > max_count {
    raise InvalidIdentityResultArtifact(label + " section exceeds its bound")
  }
  let next = cursor + 2 + count * width
  if next < cursor || next > fields.length() {
    raise InvalidIdentityResultArtifact(label + " section is truncated")
  }
  (count, next)
}

///|
fn decode_source(
  value : String,
) -> @isochronon_provider.ProviderExecutionSource raise IdentityAssuranceDecodeError {
  match value {
    "simulation-fixture" => @isochronon_provider.SimulationFixture
    "replay-fixture" => @isochronon_provider.ReplayFixture
    "fault-fixture" => @isochronon_provider.FaultFixture
    "native-contract-fixture" => @isochronon_provider.NativeContractFixture
    "runtime-unverified" => @isochronon_provider.RuntimeUnverified
    _ =>
      raise InvalidIdentityResultArtifact("unknown provider execution source")
  }
}

///|
fn decode_strength(
  value : String,
) -> @isochronon_provider.IdentityStrength raise IdentityAssuranceDecodeError {
  match value {
    "unit-identity" => @isochronon_provider.UnitIdentity
    "model-and-topology" => @isochronon_provider.ModelAndTopology
    "no-identity-assurance" => @isochronon_provider.NoIdentityAssurance
    _ => raise InvalidIdentityResultArtifact("unknown identity strength")
  }
}

///|
pub(all) enum IdentityAssuranceDisposition {
  ProtocolFactsMatchAwaitingExternalEvidence
  ProtocolFactsRejected
} derive(Eq, Debug)

///|
pub fn IdentityAssuranceDisposition::label(
  self : IdentityAssuranceDisposition,
) -> String {
  match self {
    ProtocolFactsMatchAwaitingExternalEvidence =>
      "protocol-facts-match-awaiting-external-evidence"
    ProtocolFactsRejected => "protocol-facts-rejected"
  }
}

///|
/// Stack-owned normalization output for an independent verifier. It cannot
/// construct an AssuranceAssessment or claim by itself.
pub struct DecodedIdentityAssurance {
  priv scope : String
  priv result_schema_id : String
  priv result_digest : String
  priv expected_topology_digest : String
  priv expected_count : Int
  priv frame_context_digest : String
  priv policy_digest : String
  priv source : @isochronon_provider.ProviderExecutionSource
  priv identity_strength : @isochronon_provider.IdentityStrength
  priv disposition : IdentityAssuranceDisposition
  priv observed_count : Int
  priv issue_count : Int
  priv transaction_count : Int
}

///|
pub fn decode_identity_assurance(
  result : @isochronon_provider.InspectBusIdentityResult,
) -> DecodedIdentityAssurance {
  try! decode_identity_assurance_artifact(
    result.canonical_bytes(),
    expected_digest=result.digest(),
  )
}

///|
/// Independently decode the exact canonical result artifact. Every section is
/// bounded and must be consumed exactly; provider in-memory objects are not a
/// trust shortcut for a verifier process.
pub fn decode_identity_assurance_artifact(
  canonical_bytes : Bytes,
  expected_digest~ : String,
) -> DecodedIdentityAssurance raise IdentityAssuranceDecodeError {
  let actual_digest = decoder_sha256_hex(canonical_bytes)
  if !decoder_valid_digest(expected_digest) || actual_digest != expected_digest {
    raise InvalidIdentityResultArtifact("canonical result digest mismatch")
  }
  let fields = decode_length_framed_fields(canonical_bytes)
  if fields.length() < 12 ||
    fields[0] != @isochronon_provider.inspect_bus_identity_result_schema_id ||
    !decoder_valid_digest(fields[1]) ||
    !decoder_valid_digest(fields[3]) ||
    !decoder_valid_digest(fields[4]) {
    raise InvalidIdentityResultArtifact(
      "result header or pinned digest is invalid",
    )
  }
  let expected_count = decode_count(fields[2])
  if expected_count <= 0 || expected_count > 64 {
    raise InvalidIdentityResultArtifact("expected topology count is invalid")
  }
  let source = decode_source(fields[5])
  if fields[6].is_empty() ||
    !decoder_valid_decimal(fields[7], 19) ||
    !decoder_valid_decimal(fields[9], 6) {
    raise InvalidIdentityResultArtifact("clock domain is empty")
  }
  let identity_strength = decode_strength(fields[8])
  let transaction_count = decode_count(fields[9])
  let (observed_count, after_observed) = consume_section(
    fields, 10, "observed", 8, 64,
  )
  let (issue_count, after_issues) = consume_section(
    fields, after_observed, "issues", 1, 128,
  )
  let (effect_count, after_effects) = consume_section(
    fields, after_issues, "effects", 5, 8192,
  )
  let (echo_count, after_echoes) = consume_section(
    fields, after_effects, "echoes", 4, 8192,
  )
  let (trace_count, after_trace) = consume_section(
    fields, after_echoes, "trace", 5, 32768,
  )
  if after_trace != fields.length() || transaction_count <= 0 {
    raise InvalidIdentityResultArtifact(
      "artifact has trailing fields or invalid transaction count",
    )
  }
  for index in 0..<observed_count {
    let base = 12 + index * 8
    if fields[base] != index.to_string() ||
      !decoder_valid_decimal(fields[base + 1], 10) ||
      !decoder_valid_decimal(fields[base + 2], 10) ||
      !decoder_valid_decimal(fields[base + 3], 10) ||
      !decoder_valid_decimal(fields[base + 4], 10) ||
      !decoder_valid_digest(fields[base + 5]) ||
      !decoder_valid_optional_digest(fields[base + 6]) {
      raise InvalidIdentityResultArtifact("observed identity entry is invalid")
    }
    let match_label = fields[base + 7]
    if match_label != "exact-profile-match" &&
      match_label != "model-or-revision-mismatch" &&
      match_label != "unit-serial-mismatch" &&
      match_label != "no-selected-profile" {
      raise InvalidIdentityResultArtifact(
        "observed profile match label is invalid",
      )
    }
    if issue_count == 0 &&
      (match_label != "exact-profile-match" || fields[base + 6] == "none") {
      raise InvalidIdentityResultArtifact(
        "passing topology contains a non-exact observed profile",
      )
    }
  }
  if effect_count == 0 || trace_count == 0 {
    raise InvalidIdentityResultArtifact(
      "result must contain effect and trace witnesses",
    )
  }
  for index in 0..<effect_count {
    let base = after_issues + 2 + index * 5
    let kind = fields[base]
    if (
        kind != "probe-bus-population" &&
        kind != "observe-sii-controller-status" &&
        kind != "read-identity-metadata" &&
        kind != "mutate-volatile-sii-controller"
      ) ||
      !decoder_valid_optional_decimal(fields[base + 1]) ||
      !decoder_valid_decimal(fields[base + 2], 6) ||
      !decoder_valid_digest(fields[base + 3]) ||
      fields[base + 4] != "tx-accepted-by-backend" {
      raise InvalidIdentityResultArtifact("effect witness is invalid")
    }
  }
  for index in 0..<echo_count {
    let base = after_effects + 2 + index * 4
    if fields[base] != "ignored-local-tx-echo" ||
      !decoder_valid_decimal(fields[base + 1], 6) ||
      !decoder_valid_decimal(fields[base + 2], 19) ||
      !decoder_valid_digest(fields[base + 3]) {
      raise InvalidIdentityResultArtifact("local TX echo relation is invalid")
    }
  }
  for index in 0..<trace_count {
    let base = after_echoes + 2 + index * 5
    let kind = fields[base]
    if (
        kind != "policy-bound" &&
        kind != "transaction-submitted" &&
        kind != "observation-ignored" &&
        kind != "response-accepted" &&
        kind != "sii-status-polled" &&
        kind != "retry-scheduled"
      ) ||
      !decoder_valid_optional_decimal(fields[base + 1]) ||
      fields[base + 2].is_empty() ||
      !decoder_valid_decimal(fields[base + 3], 19) ||
      fields[base + 4].is_empty() {
      raise InvalidIdentityResultArtifact("identity trace event is invalid")
    }
  }
  if (
      issue_count == 0 &&
      identity_strength == @isochronon_provider.NoIdentityAssurance
    ) ||
    (
      issue_count > 0 &&
      identity_strength != @isochronon_provider.NoIdentityAssurance
    ) {
    raise InvalidIdentityResultArtifact(
      "topology issues and identity strength are inconsistent",
    )
  }
  if issue_count == 0 && observed_count != expected_count {
    raise InvalidIdentityResultArtifact(
      "passing topology does not consume the expected ordered count",
    )
  }
  let disposition = if issue_count == 0 {
    ProtocolFactsMatchAwaitingExternalEvidence
  } else {
    ProtocolFactsRejected
  }
  {
    scope: identity_assurance_scope,
    result_schema_id: fields[0],
    result_digest: actual_digest,
    expected_topology_digest: fields[1],
    expected_count,
    frame_context_digest: fields[3],
    policy_digest: fields[4],
    source,
    identity_strength,
    disposition,
    observed_count,
    issue_count,
    transaction_count,
  }
}

///|
pub fn DecodedIdentityAssurance::scope(
  self : DecodedIdentityAssurance,
) -> String {
  self.scope
}

///|
pub fn DecodedIdentityAssurance::result_schema_id(
  self : DecodedIdentityAssurance,
) -> String {
  self.result_schema_id
}

///|
pub fn DecodedIdentityAssurance::result_digest(
  self : DecodedIdentityAssurance,
) -> String {
  self.result_digest
}

///|
pub fn DecodedIdentityAssurance::expected_topology_digest(
  self : DecodedIdentityAssurance,
) -> String {
  self.expected_topology_digest
}

///|
pub fn DecodedIdentityAssurance::expected_count(
  self : DecodedIdentityAssurance,
) -> Int {
  self.expected_count
}

///|
pub fn DecodedIdentityAssurance::frame_context_digest(
  self : DecodedIdentityAssurance,
) -> String {
  self.frame_context_digest
}

///|
pub fn DecodedIdentityAssurance::policy_digest(
  self : DecodedIdentityAssurance,
) -> String {
  self.policy_digest
}

///|
pub fn DecodedIdentityAssurance::source(
  self : DecodedIdentityAssurance,
) -> @isochronon_provider.ProviderExecutionSource {
  self.source
}

///|
pub fn DecodedIdentityAssurance::identity_strength(
  self : DecodedIdentityAssurance,
) -> @isochronon_provider.IdentityStrength {
  self.identity_strength
}

///|
pub fn DecodedIdentityAssurance::disposition(
  self : DecodedIdentityAssurance,
) -> IdentityAssuranceDisposition {
  self.disposition
}

///|
pub fn DecodedIdentityAssurance::observed_count(
  self : DecodedIdentityAssurance,
) -> Int {
  self.observed_count
}

///|
pub fn DecodedIdentityAssurance::issue_count(
  self : DecodedIdentityAssurance,
) -> Int {
  self.issue_count
}

///|
pub fn DecodedIdentityAssurance::transaction_count(
  self : DecodedIdentityAssurance,
) -> Int {
  self.transaction_count
}

///|
pub fn DecodedIdentityAssurance::external_evidence_complete(
  _self : DecodedIdentityAssurance,
) -> Bool {
  false
}

///|
pub fn DecodedIdentityAssurance::claim_eligible(
  _self : DecodedIdentityAssurance,
) -> Bool {
  false
}

///|
pub fn identity_assurance_decoder_package_id() -> String {
  "mokomoking2501/MoonECAT/isochronon_provider/assurance"
}
