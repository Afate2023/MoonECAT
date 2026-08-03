///|
pub let inspect_bus_identity_operation_id : String = "inspect-bus-identity"

///|
pub let inspect_bus_identity_result_schema_id : String = "moonecat.inspect-bus-identity.result.v1"

///|
pub(all) suberror IdentityProviderError {
  InvalidContext(String)
  InvalidPolicy(String)
  InvalidTopology(String)
  DeadlineExpired
  TransactionLimitExceeded(Int)
  RetryableTransportFailure(String)
  TransportFailure(String)
  ResponseRejected(String)
  SiiReadRejected(Int, String)
} derive(Eq, Debug)

///|
fn provider_copy_bytes(value : Bytes) -> Bytes {
  Bytes::makei(value.length(), fn(index) { value[index] })
}

///|
fn provider_sha256_hex(value : Bytes) -> String {
  let builder = StringBuilder::new()
  for byte in @crypto.sha256(value) {
    builder.write_string(byte.to_hex())
  }
  builder.to_string()
}

///|
fn provider_write_field(builder : StringBuilder, value : String) -> Unit {
  let bytes = @utf8.encode(value)
  builder.write_string(bytes.length().to_string())
  builder.write_string(":")
  builder.write_string(value)
}

///|
fn provider_digest_record(domain : String, fields : Array[String]) -> String {
  provider_sha256_hex(provider_canonical_record(domain, fields))
}

///|
fn provider_canonical_record(domain : String, fields : Array[String]) -> Bytes {
  let builder = StringBuilder::new()
  provider_write_field(builder, domain)
  for field in fields {
    provider_write_field(builder, field)
  }
  @utf8.encode(builder.to_string())
}

///|
fn provider_valid_digest(value : String) -> Bool {
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
fn provider_uint_le(data : Bytes, offset : Int) -> UInt {
  data[offset].to_uint() |
  (data[offset + 1].to_uint() << 8) |
  (data[offset + 2].to_uint() << 16) |
  (data[offset + 3].to_uint() << 24)
}

///|
fn provider_bytes_equal(left : Bytes, right : Bytes) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index in 0..<left.length() {
    if left[index] != right[index] {
      return false
    }
  }
  true
}

///|
fn provider_mac_text(value : Bytes) -> String {
  let builder = StringBuilder::new()
  for index, byte in value {
    if index > 0 {
      builder.write_string(":")
    }
    builder.write_string(byte.to_hex())
  }
  builder.to_string()
}

///|
fn provider_mac_fixed(value : Bytes) -> FixedArray[Byte] {
  FixedArray::makei(6, fn(index) { value[index] })
}

///|
pub struct EthernetFrameContext {
  priv resolved_binding_digest : String
  priv current_mac : Bytes
  priv clock_domain : @clock.DomainId
  priv digest : String
}

///|
pub fn EthernetFrameContext::new(
  resolved_binding_digest~ : String,
  current_mac~ : Bytes,
  clock_domain~ : @clock.DomainId,
) -> EthernetFrameContext raise IdentityProviderError {
  let mut all_zero = true
  for byte in current_mac {
    if byte != b'\x00' {
      all_zero = false
    }
  }
  if !provider_valid_digest(resolved_binding_digest) {
    raise InvalidContext("resolved binding digest must be lowercase SHA-256")
  }
  if current_mac.length() != 6 ||
    all_zero ||
    (current_mac[0].to_uint() & 1U) != 0U {
    raise InvalidContext("current MAC must be a nonzero unicast address")
  }
  if clock_domain.name().is_empty() {
    raise InvalidContext("clock domain must be named")
  }
  let owned_mac = provider_copy_bytes(current_mac)
  let digest = provider_digest_record("moonecat.ethernet-frame-context.v1", [
    resolved_binding_digest,
    provider_mac_text(owned_mac),
    clock_domain.name(),
  ])
  { resolved_binding_digest, current_mac: owned_mac, clock_domain, digest }
}

///|
pub fn EthernetFrameContext::resolved_binding_digest(
  self : EthernetFrameContext,
) -> String {
  self.resolved_binding_digest
}

///|
pub fn EthernetFrameContext::current_mac(self : EthernetFrameContext) -> Bytes {
  provider_copy_bytes(self.current_mac)
}

///|
pub fn EthernetFrameContext::clock_domain(
  self : EthernetFrameContext,
) -> @clock.DomainId {
  self.clock_domain
}

///|
pub fn EthernetFrameContext::digest(self : EthernetFrameContext) -> String {
  self.digest
}

///|
pub struct InspectBusIdentityPolicy {
  priv max_slaves : Int
  priv max_wire_transactions : Int
  priv max_transport_retries : Int
  priv max_sii_status_polls : Int
  priv max_sii_nack_retries : Int
  priv max_ignored_observations : Int
  priv retry_backoff_ns : Int64
  priv digest : String
}

///|
pub fn InspectBusIdentityPolicy::new(
  max_slaves~ : Int,
  max_wire_transactions~ : Int,
  max_transport_retries~ : Int,
  max_sii_status_polls~ : Int,
  max_sii_nack_retries~ : Int,
  max_ignored_observations~ : Int,
  retry_backoff_ns~ : Int64,
) -> InspectBusIdentityPolicy raise IdentityProviderError {
  if max_slaves <= 0 || max_slaves > 64 {
    raise InvalidPolicy("max_slaves must be 1..64")
  }
  if max_wire_transactions <= 0 || max_wire_transactions > 8192 {
    raise InvalidPolicy("max_wire_transactions must be 1..8192")
  }
  if max_transport_retries < 0 || max_transport_retries > 3 {
    raise InvalidPolicy("max_transport_retries must be 0..3")
  }
  if max_sii_status_polls <= 0 || max_sii_status_polls > 64 {
    raise InvalidPolicy("max_sii_status_polls must be 1..64")
  }
  if max_sii_nack_retries < 0 || max_sii_nack_retries > 3 {
    raise InvalidPolicy("max_sii_nack_retries must be 0..3")
  }
  if max_ignored_observations < 0 || max_ignored_observations > 64 {
    raise InvalidPolicy("max_ignored_observations must be 0..64")
  }
  if retry_backoff_ns < 0L || retry_backoff_ns > 1_000_000_000L {
    raise InvalidPolicy("retry_backoff_ns must be 0..1000000000")
  }
  let digest = provider_digest_record(
    "moonecat.inspect-bus-identity.policy.v1",
    [
      max_slaves.to_string(),
      max_wire_transactions.to_string(),
      max_transport_retries.to_string(),
      max_sii_status_polls.to_string(),
      max_sii_nack_retries.to_string(),
      max_ignored_observations.to_string(),
      retry_backoff_ns.to_string(),
    ],
  )
  {
    max_slaves,
    max_wire_transactions,
    max_transport_retries,
    max_sii_status_polls,
    max_sii_nack_retries,
    max_ignored_observations,
    retry_backoff_ns,
    digest,
  }
}

///|
pub fn InspectBusIdentityPolicy::verification_default() -> InspectBusIdentityPolicy {
  try! InspectBusIdentityPolicy::new(
    max_slaves=64,
    max_wire_transactions=2048,
    max_transport_retries=1,
    max_sii_status_polls=32,
    max_sii_nack_retries=2,
    max_ignored_observations=32,
    retry_backoff_ns=100_000L,
  )
}

///|
pub fn InspectBusIdentityPolicy::max_slaves(
  self : InspectBusIdentityPolicy,
) -> Int {
  self.max_slaves
}

///|
pub fn InspectBusIdentityPolicy::max_wire_transactions(
  self : InspectBusIdentityPolicy,
) -> Int {
  self.max_wire_transactions
}

///|
pub fn InspectBusIdentityPolicy::max_transport_retries(
  self : InspectBusIdentityPolicy,
) -> Int {
  self.max_transport_retries
}

///|
pub fn InspectBusIdentityPolicy::max_sii_status_polls(
  self : InspectBusIdentityPolicy,
) -> Int {
  self.max_sii_status_polls
}

///|
pub fn InspectBusIdentityPolicy::max_sii_nack_retries(
  self : InspectBusIdentityPolicy,
) -> Int {
  self.max_sii_nack_retries
}

///|
pub fn InspectBusIdentityPolicy::max_ignored_observations(
  self : InspectBusIdentityPolicy,
) -> Int {
  self.max_ignored_observations
}

///|
pub fn InspectBusIdentityPolicy::retry_backoff_ns(
  self : InspectBusIdentityPolicy,
) -> Int64 {
  self.retry_backoff_ns
}

///|
pub fn InspectBusIdentityPolicy::digest(
  self : InspectBusIdentityPolicy,
) -> String {
  self.digest
}

///|
pub struct ExpectedBusTopology {
  priv bindings : Array[@device_profile.ProviderDeviceInstanceBinding]
  priv digest : String
}

///|
pub fn ExpectedBusTopology::new(
  bindings : Array[@device_profile.ProviderDeviceInstanceBinding],
) -> ExpectedBusTopology raise IdentityProviderError {
  if bindings.is_empty() || bindings.length() > 64 {
    raise InvalidTopology("expected topology must contain 1..64 bindings")
  }
  let owned = bindings.copy()
  let fields : Array[String] = []
  for index, binding in owned {
    if binding.physical_position() != index {
      raise InvalidTopology(
        "bindings must be ordered with physical_position equal to array index",
      )
    }
    for prior in 0..<index {
      if owned[prior].device_node_id() == binding.device_node_id() ||
        owned[prior].protocol_role_binding_id() ==
        binding.protocol_role_binding_id() ||
        owned[prior].config().configured_station_address() ==
        binding.config().configured_station_address() {
        raise InvalidTopology(
          "duplicate device node, protocol role or configured station address",
        )
      }
    }
    fields.push(binding.digest())
  }
  let digest = provider_digest_record(
    "moonecat.expected-bus-topology.v1", fields,
  )
  { bindings: owned, digest }
}

///|
pub fn ExpectedBusTopology::bindings(
  self : ExpectedBusTopology,
) -> Array[@device_profile.ProviderDeviceInstanceBinding] {
  self.bindings.copy()
}

///|
pub fn ExpectedBusTopology::count(self : ExpectedBusTopology) -> Int {
  self.bindings.length()
}

///|
pub fn ExpectedBusTopology::digest(self : ExpectedBusTopology) -> String {
  self.digest
}

///|
pub(all) enum ProviderExecutionSource {
  SimulationFixture
  ReplayFixture
  FaultFixture
  NativeContractFixture
  RuntimeUnverified
} derive(Eq, Debug)

///|
pub fn ProviderExecutionSource::label(self : ProviderExecutionSource) -> String {
  match self {
    SimulationFixture => "simulation-fixture"
    ReplayFixture => "replay-fixture"
    FaultFixture => "fault-fixture"
    NativeContractFixture => "native-contract-fixture"
    RuntimeUnverified => "runtime-unverified"
  }
}

///|
pub fn ProviderExecutionSource::live_verified(
  _self : ProviderExecutionSource,
) -> Bool {
  false
}

///|
pub(all) enum ProviderEffectKind {
  ProbeBusPopulation
  ObserveSiiControllerStatus
  ReadIdentityMetadata
  MutateVolatileSiiController
} derive(Eq, Debug)

///|
pub fn ProviderEffectKind::label(self : ProviderEffectKind) -> String {
  match self {
    ProbeBusPopulation => "probe-bus-population"
    ObserveSiiControllerStatus => "observe-sii-controller-status"
    ReadIdentityMetadata => "read-identity-metadata"
    MutateVolatileSiiController => "mutate-volatile-sii-controller"
  }
}

///|
pub struct ProviderEffectWitness {
  priv kind : ProviderEffectKind
  priv physical_position : Int?
  priv transaction_ordinal : Int
  priv frame_digest : String
}

///|
fn ProviderEffectWitness::make(
  kind : ProviderEffectKind,
  position : Int?,
  ordinal : Int,
  frame_digest : String,
) -> ProviderEffectWitness {
  {
    kind,
    physical_position: position,
    transaction_ordinal: ordinal,
    frame_digest,
  }
}

///|
pub fn ProviderEffectWitness::kind(
  self : ProviderEffectWitness,
) -> ProviderEffectKind {
  self.kind
}

///|
pub fn ProviderEffectWitness::physical_position(
  self : ProviderEffectWitness,
) -> Int? {
  self.physical_position
}

///|
pub fn ProviderEffectWitness::transaction_ordinal(
  self : ProviderEffectWitness,
) -> Int {
  self.transaction_ordinal
}

///|
pub fn ProviderEffectWitness::frame_digest(
  self : ProviderEffectWitness,
) -> String {
  self.frame_digest
}

///|
pub fn ProviderEffectWitness::truth_point(
  _self : ProviderEffectWitness,
) -> String {
  "tx-accepted-by-backend"
}

///|
pub struct OwnTxEchoRelation {
  priv transaction_ordinal : Int
  priv backend_sequence : Int64
  priv frame_digest : String
}

///|
fn OwnTxEchoRelation::make(
  transaction_ordinal : Int,
  backend_sequence : Int64,
  frame_digest : String,
) -> OwnTxEchoRelation {
  { transaction_ordinal, backend_sequence, frame_digest }
}

///|
pub fn OwnTxEchoRelation::transaction_ordinal(self : OwnTxEchoRelation) -> Int {
  self.transaction_ordinal
}

///|
pub fn OwnTxEchoRelation::backend_sequence(self : OwnTxEchoRelation) -> Int64 {
  self.backend_sequence
}

///|
pub fn OwnTxEchoRelation::frame_digest(self : OwnTxEchoRelation) -> String {
  self.frame_digest
}

///|
pub fn OwnTxEchoRelation::relation(_self : OwnTxEchoRelation) -> String {
  "ignored-local-tx-echo"
}

///|
pub(all) enum IdentityTraceKind {
  PolicyBound
  TransactionSubmitted
  ObservationIgnored
  ResponseAccepted
  SiiStatusPolled
  RetryScheduled
} derive(Eq, Debug)

///|
pub fn IdentityTraceKind::label(self : IdentityTraceKind) -> String {
  match self {
    PolicyBound => "policy-bound"
    TransactionSubmitted => "transaction-submitted"
    ObservationIgnored => "observation-ignored"
    ResponseAccepted => "response-accepted"
    SiiStatusPolled => "sii-status-polled"
    RetryScheduled => "retry-scheduled"
  }
}

///|
pub struct IdentityTraceEvent {
  priv kind : IdentityTraceKind
  priv transaction_ordinal : Int?
  priv timestamp : @clock.DomainInstant
  priv detail : String
}

///|
fn IdentityTraceEvent::make(
  kind : IdentityTraceKind,
  ordinal : Int?,
  timestamp : @clock.DomainInstant,
  detail : String,
) -> IdentityTraceEvent {
  { kind, transaction_ordinal: ordinal, timestamp, detail }
}

///|
pub fn IdentityTraceEvent::kind(self : IdentityTraceEvent) -> IdentityTraceKind {
  self.kind
}

///|
pub fn IdentityTraceEvent::transaction_ordinal(
  self : IdentityTraceEvent,
) -> Int? {
  self.transaction_ordinal
}

///|
pub fn IdentityTraceEvent::timestamp(
  self : IdentityTraceEvent,
) -> @clock.DomainInstant {
  self.timestamp
}

///|
pub fn IdentityTraceEvent::detail(self : IdentityTraceEvent) -> String {
  self.detail
}

///|
pub(all) enum ProfileMatchVerdict {
  ExactProfileMatch
  ModelOrRevisionMismatch
  UnitSerialMismatch
  NoSelectedProfile
} derive(Eq, Debug)

///|
pub fn ProfileMatchVerdict::label(self : ProfileMatchVerdict) -> String {
  match self {
    ExactProfileMatch => "exact-profile-match"
    ModelOrRevisionMismatch => "model-or-revision-mismatch"
    UnitSerialMismatch => "unit-serial-mismatch"
    NoSelectedProfile => "no-selected-profile"
  }
}

///|
pub struct ObservedDeviceIdentity {
  priv physical_position : Int
  priv vendor_id : UInt
  priv product_code : UInt
  priv revision : UInt
  priv serial : UInt
  priv raw_identity_digest : String
  priv selected_profile_digest : String?
  priv match_verdict : ProfileMatchVerdict
}

///|
fn ObservedDeviceIdentity::make(
  physical_position : Int,
  raw : Bytes,
  selected_profile_digest : String?,
  match_verdict : ProfileMatchVerdict,
) -> ObservedDeviceIdentity {
  {
    physical_position,
    vendor_id: provider_uint_le(raw, 0),
    product_code: provider_uint_le(raw, 4),
    revision: provider_uint_le(raw, 8),
    serial: provider_uint_le(raw, 12),
    raw_identity_digest: provider_sha256_hex(raw),
    selected_profile_digest,
    match_verdict,
  }
}

///|
pub fn ObservedDeviceIdentity::physical_position(
  self : ObservedDeviceIdentity,
) -> Int {
  self.physical_position
}

///|
pub fn ObservedDeviceIdentity::vendor_id(self : ObservedDeviceIdentity) -> UInt {
  self.vendor_id
}

///|
pub fn ObservedDeviceIdentity::product_code(
  self : ObservedDeviceIdentity,
) -> UInt {
  self.product_code
}

///|
pub fn ObservedDeviceIdentity::revision(self : ObservedDeviceIdentity) -> UInt {
  self.revision
}

///|
pub fn ObservedDeviceIdentity::serial(self : ObservedDeviceIdentity) -> UInt {
  self.serial
}

///|
pub fn ObservedDeviceIdentity::raw_identity_digest(
  self : ObservedDeviceIdentity,
) -> String {
  self.raw_identity_digest
}

///|
pub fn ObservedDeviceIdentity::selected_profile_digest(
  self : ObservedDeviceIdentity,
) -> String? {
  self.selected_profile_digest
}

///|
pub fn ObservedDeviceIdentity::match_verdict(
  self : ObservedDeviceIdentity,
) -> ProfileMatchVerdict {
  self.match_verdict
}

///|
pub(all) enum TopologyIssue {
  ExtraDevice(Int)
  MissingDevice(Int)
  ReorderedDevice(observed_position~ : Int, expected_position~ : Int)
  ModelOrRevisionMismatchAt(Int)
  UnitSerialMismatchAt(Int)
} derive(Eq, Debug)

///|
pub fn TopologyIssue::label(self : TopologyIssue) -> String {
  match self {
    ExtraDevice(position) => "extra-device:" + position.to_string()
    MissingDevice(position) => "missing-device:" + position.to_string()
    ReorderedDevice(observed_position~, expected_position~) =>
      "reordered-device:" +
      observed_position.to_string() +
      ":expected:" +
      expected_position.to_string()
    ModelOrRevisionMismatchAt(position) =>
      "model-or-revision-mismatch:" + position.to_string()
    UnitSerialMismatchAt(position) =>
      "unit-serial-mismatch:" + position.to_string()
  }
}

///|
pub(all) enum IdentityStrength {
  UnitIdentity
  ModelAndTopology
  NoIdentityAssurance
} derive(Eq, Debug)

///|
pub fn IdentityStrength::label(self : IdentityStrength) -> String {
  match self {
    UnitIdentity => "unit-identity"
    ModelAndTopology => "model-and-topology"
    NoIdentityAssurance => "no-identity-assurance"
  }
}

///|
pub struct InspectBusIdentityResult {
  priv expected_topology_digest : String
  priv expected_count : Int
  priv frame_context_digest : String
  priv policy_digest : String
  priv source : ProviderExecutionSource
  priv deadline : @clock.DomainInstant
  priv observed : Array[ObservedDeviceIdentity]
  priv issues : Array[TopologyIssue]
  priv identity_strength : IdentityStrength
  priv effects : Array[ProviderEffectWitness]
  priv echoes : Array[OwnTxEchoRelation]
  priv trace : Array[IdentityTraceEvent]
  priv transaction_count : Int
  priv canonical_bytes : Bytes
  priv digest : String
}

///|
fn InspectBusIdentityResult::make(
  expected_topology_digest : String,
  expected_count : Int,
  frame_context_digest : String,
  policy_digest : String,
  source : ProviderExecutionSource,
  deadline : @clock.DomainInstant,
  observed : Array[ObservedDeviceIdentity],
  issues : Array[TopologyIssue],
  identity_strength : IdentityStrength,
  effects : Array[ProviderEffectWitness],
  echoes : Array[OwnTxEchoRelation],
  trace : Array[IdentityTraceEvent],
  transaction_count : Int,
) -> InspectBusIdentityResult {
  let fields : Array[String] = [
    expected_topology_digest,
    expected_count.to_string(),
    frame_context_digest,
    policy_digest,
    source.label(),
    deadline.domain().name(),
    deadline.ns().to_string(),
    identity_strength.label(),
    transaction_count.to_string(),
  ]
  fields.push("observed")
  fields.push(observed.length().to_string())
  for item in observed {
    fields.push(item.physical_position().to_string())
    fields.push(item.vendor_id().to_string())
    fields.push(item.product_code().to_string())
    fields.push(item.revision().to_string())
    fields.push(item.serial().to_string())
    fields.push(item.raw_identity_digest())
    fields.push(
      match item.selected_profile_digest() {
        Some(value) => "some:" + value
        None => "none"
      },
    )
    fields.push(item.match_verdict().label())
  }
  fields.push("issues")
  fields.push(issues.length().to_string())
  for issue in issues {
    fields.push(issue.label())
  }
  fields.push("effects")
  fields.push(effects.length().to_string())
  for effect in effects {
    fields.push(effect.kind().label())
    fields.push(
      match effect.physical_position() {
        Some(value) => "some:" + value.to_string()
        None => "none"
      },
    )
    fields.push(effect.transaction_ordinal().to_string())
    fields.push(effect.frame_digest())
    fields.push(effect.truth_point())
  }
  fields.push("echoes")
  fields.push(echoes.length().to_string())
  for echo in echoes {
    fields.push(echo.relation())
    fields.push(echo.transaction_ordinal().to_string())
    fields.push(echo.backend_sequence().to_string())
    fields.push(echo.frame_digest())
  }
  fields.push("trace")
  fields.push(trace.length().to_string())
  for event in trace {
    fields.push(event.kind().label())
    fields.push(
      match event.transaction_ordinal() {
        Some(value) => "some:" + value.to_string()
        None => "none"
      },
    )
    fields.push(event.timestamp().domain().name())
    fields.push(event.timestamp().ns().to_string())
    fields.push(event.detail())
  }
  let canonical_bytes = provider_canonical_record(
    inspect_bus_identity_result_schema_id, fields,
  )
  let digest = provider_sha256_hex(canonical_bytes)
  {
    expected_topology_digest,
    expected_count,
    frame_context_digest,
    policy_digest,
    source,
    deadline,
    observed: observed.copy(),
    issues: issues.copy(),
    identity_strength,
    effects: effects.copy(),
    echoes: echoes.copy(),
    trace: trace.copy(),
    transaction_count,
    canonical_bytes,
    digest,
  }
}

///|
pub fn InspectBusIdentityResult::schema_id(
  _self : InspectBusIdentityResult,
) -> String {
  inspect_bus_identity_result_schema_id
}

///|
pub fn InspectBusIdentityResult::passes(
  self : InspectBusIdentityResult,
) -> Bool {
  self.issues.is_empty()
}

///|
pub fn InspectBusIdentityResult::expected_topology_digest(
  self : InspectBusIdentityResult,
) -> String {
  self.expected_topology_digest
}

///|
pub fn InspectBusIdentityResult::expected_count(
  self : InspectBusIdentityResult,
) -> Int {
  self.expected_count
}

///|
pub fn InspectBusIdentityResult::frame_context_digest(
  self : InspectBusIdentityResult,
) -> String {
  self.frame_context_digest
}

///|
pub fn InspectBusIdentityResult::policy_digest(
  self : InspectBusIdentityResult,
) -> String {
  self.policy_digest
}

///|
pub fn InspectBusIdentityResult::source(
  self : InspectBusIdentityResult,
) -> ProviderExecutionSource {
  self.source
}

///|
pub fn InspectBusIdentityResult::deadline(
  self : InspectBusIdentityResult,
) -> @clock.DomainInstant {
  self.deadline
}

///|
pub fn InspectBusIdentityResult::observed(
  self : InspectBusIdentityResult,
) -> Array[ObservedDeviceIdentity] {
  self.observed.copy()
}

///|
pub fn InspectBusIdentityResult::issues(
  self : InspectBusIdentityResult,
) -> Array[TopologyIssue] {
  self.issues.copy()
}

///|
pub fn InspectBusIdentityResult::identity_strength(
  self : InspectBusIdentityResult,
) -> IdentityStrength {
  self.identity_strength
}

///|
pub fn InspectBusIdentityResult::effects(
  self : InspectBusIdentityResult,
) -> Array[ProviderEffectWitness] {
  self.effects.copy()
}

///|
pub fn InspectBusIdentityResult::echoes(
  self : InspectBusIdentityResult,
) -> Array[OwnTxEchoRelation] {
  self.echoes.copy()
}

///|
pub fn InspectBusIdentityResult::trace(
  self : InspectBusIdentityResult,
) -> Array[IdentityTraceEvent] {
  self.trace.copy()
}

///|
pub fn InspectBusIdentityResult::transaction_count(
  self : InspectBusIdentityResult,
) -> Int {
  self.transaction_count
}

///|
pub fn InspectBusIdentityResult::canonical_bytes(
  self : InspectBusIdentityResult,
) -> Bytes {
  provider_copy_bytes(self.canonical_bytes)
}

///|
pub fn InspectBusIdentityResult::digest(
  self : InspectBusIdentityResult,
) -> String {
  self.digest
}

///|
pub fn InspectBusIdentityResult::live_verified(
  _self : InspectBusIdentityResult,
) -> Bool {
  false
}

///|
pub fn isochronon_provider_package_id() -> String {
  "mokomoking2501/MoonECAT/isochronon_provider"
}
