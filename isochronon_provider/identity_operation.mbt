///|
let ethernet_minimum_without_fcs : Int = 60

///|
let sii_identity_start_word : UInt = 8U

///|
let sii_identity_octets : Int = 16

///|
let sii_ctrl_busy : UInt = 0x8000U

///|
let sii_ctrl_nack : UInt = 0x2000U

///|
let sii_ctrl_r64 : UInt = 0x0040U

///|
let sii_ctrl_error_mask : UInt = 0x7800U

///|
let sii_ctrl_read_cmd : UInt = 0x0100U

///|
priv struct IdentityOperationState {
  policy : InspectBusIdentityPolicy
  context : EthernetFrameContext
  port : IdentityLinkPort
  deadline : @clock.DomainInstant
  mut next_index : Int
  mut transaction_count : Int
  mut sii_cleanup_reserved : Bool
  mut sii_ownership_may_be_changed : Bool
  effects : Array[ProviderEffectWitness]
  echoes : Array[OwnTxEchoRelation]
  trace : Array[IdentityTraceEvent]
}

///|
fn IdentityOperationState::new(
  policy : InspectBusIdentityPolicy,
  context : EthernetFrameContext,
  port : IdentityLinkPort,
  deadline : @clock.DomainInstant,
) -> IdentityOperationState raise IdentityProviderError {
  let now = port.now()
  if now.domain() != context.clock_domain() ||
    deadline.domain() != context.clock_domain() {
    raise InvalidContext("port, context and deadline clock domains must match")
  }
  if now.ns() >= deadline.ns() {
    raise DeadlineExpired
  }
  let trace = [
    IdentityTraceEvent::make(
      PolicyBound,
      None,
      now,
      "policy=" +
      policy.digest() +
      ";max_transactions=" +
      policy.max_wire_transactions().to_string() +
      ";transport_retries=" +
      policy.max_transport_retries().to_string() +
      ";status_polls=" +
      policy.max_sii_status_polls().to_string() +
      ";nack_retries=" +
      policy.max_sii_nack_retries().to_string() +
      ";ignored=" +
      policy.max_ignored_observations().to_string() +
      ";backoff_ns=" +
      policy.retry_backoff_ns().to_string(),
    ),
  ]
  {
    policy,
    context,
    port,
    deadline,
    next_index: 0,
    transaction_count: 0,
    sii_cleanup_reserved: false,
    sii_ownership_may_be_changed: false,
    effects: [],
    echoes: [],
    trace,
  }
}

///|
fn IdentityOperationState::now(
  self : IdentityOperationState,
) -> @clock.DomainInstant raise IdentityProviderError {
  let now = self.port.now()
  if now.domain() != self.deadline.domain() {
    raise InvalidContext("port clock domain changed during operation")
  }
  now
}

///|
fn IdentityOperationState::require_budget(
  self : IdentityOperationState,
  allow_reserved_cleanup : Bool,
) -> Unit raise IdentityProviderError {
  if self.now().ns() >= self.deadline.ns() {
    raise DeadlineExpired
  }
  let cleanup_reserve = if self.sii_cleanup_reserved && !allow_reserved_cleanup {
    self.policy.max_transport_retries() + 1
  } else {
    0
  }
  if self.transaction_count + cleanup_reserve >=
    self.policy.max_wire_transactions() {
    raise TransactionLimitExceeded(self.policy.max_wire_transactions())
  }
}

///|
fn IdentityOperationState::backoff(
  self : IdentityOperationState,
  ordinal : Int?,
  reason : String,
) -> Unit raise IdentityProviderError {
  self.trace.push(
    IdentityTraceEvent::make(
      RetryScheduled,
      ordinal,
      self.now(),
      reason + ";backoff_ns=" + self.policy.retry_backoff_ns().to_string(),
    ),
  )
  if self.policy.retry_backoff_ns() == 0L {
    return
  }
  let wake = self
    .now()
    .add(@core.Duration::from_ns(self.policy.retry_backoff_ns()))
  if wake.ns() >= self.deadline.ns() {
    raise DeadlineExpired
  }
  self.port.sleep_until(wake)
  if self.now().ns() >= self.deadline.ns() {
    raise DeadlineExpired
  }
}

///|
fn padded_request_frame(
  context : EthernetFrameContext,
  command : @protocol.EcCommand,
  index : Byte,
  address : UInt,
  data : Bytes,
) -> Bytes {
  let frame : @protocol.EcFrame = {
    dst_mac: FixedArray::makei(6, fn(i) { @protocol.broadcast_mac[i] }),
    src_mac: provider_mac_fixed(context.current_mac()),
    pdus: [
      {
        header: {
          command,
          index,
          address,
          len_flags: data.length().reinterpret_as_uint() & 0x7FFU,
          irq: 0U,
        },
        data: provider_copy_bytes(data),
        wkc: 0U,
      },
    ],
  }
  let encoded = frame.encode()
  if encoded.length() >= ethernet_minimum_without_fcs {
    encoded
  } else {
    Bytes::makei(ethernet_minimum_without_fcs, fn(i) {
      if i < encoded.length() {
        encoded[i]
      } else {
        b'\x00'
      }
    })
  }
}

///|
fn fixed_mac_equals_bytes(left : FixedArray[Byte], right : Bytes) -> Bool {
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
fn valid_response_frame_context(
  frame : @protocol.EcFrame,
  context : EthernetFrameContext,
) -> Bool {
  fixed_mac_equals_bytes(
    frame.dst_mac,
    Bytes::from_array(@protocol.broadcast_mac),
  ) &&
  fixed_mac_equals_bytes(frame.src_mac, context.current_mac())
}

///|
fn response_matches_request(
  response : @protocol.Pdu,
  command : @protocol.EcCommand,
  index : Byte,
  address : UInt,
  expected_data_length : Int,
) -> Bool {
  if response.header.command != command ||
    response.header.index != index ||
    response.data.length() != expected_data_length {
    return false
  }
  match command {
    @protocol.APRD | @protocol.APWR =>
      @protocol.address_offset(response.header.address) ==
      @protocol.address_offset(address)
    _ => response.header.address == address
  }
}

///|
fn IdentityOperationState::exchange_once(
  self : IdentityOperationState,
  command : @protocol.EcCommand,
  address : UInt,
  data : Bytes,
  effect : ProviderEffectKind,
  position : Int?,
  index : Byte,
  allow_reserved_cleanup : Bool,
) -> @protocol.Pdu raise IdentityProviderError {
  self.require_budget(allow_reserved_cleanup)
  let request = padded_request_frame(
    self.context,
    command,
    index,
    address,
    data,
  )
  let request_digest = provider_sha256_hex(request)
  self.transaction_count = self.transaction_count + 1
  let ordinal = self.transaction_count
  self.port.submit(request)
  self.effects.push(
    ProviderEffectWitness::make(effect, position, ordinal, request_digest),
  )
  self.trace.push(
    IdentityTraceEvent::make(
      TransactionSubmitted,
      Some(ordinal),
      self.now(),
      "command=" +
      command.to_byte().to_hex() +
      ";address=" +
      address.to_string() +
      ";deadline_ns=" +
      self.deadline.ns().to_string(),
    ),
  )
  let mut ignored = 0
  for ;; {
    if self.now().ns() >= self.deadline.ns() {
      raise DeadlineExpired
    }
    let observation = match self.port.poll(self.deadline) {
      None => raise DeadlineExpired
      Some(value) => value
    }
    if observation.timestamp().domain() != self.context.clock_domain() ||
      observation.timestamp().ns() > self.deadline.ns() {
      raise ResponseRejected(
        "RX observation uses a different clock domain or exceeds deadline",
      )
    }
    let payload = observation.payload()
    if provider_bytes_equal(payload, request) {
      self.echoes.push(
        OwnTxEchoRelation::make(
          ordinal,
          observation.backend_sequence(),
          request_digest,
        ),
      )
      self.trace.push(
        IdentityTraceEvent::make(
          ObservationIgnored,
          Some(ordinal),
          observation.timestamp(),
          "ignored-local-tx-echo",
        ),
      )
      ignored = ignored + 1
      if ignored > self.policy.max_ignored_observations() {
        raise ResponseRejected("too many ignored observations")
      }
      continue
    }
    if payload.length() < 14 || payload[12] != b'\x88' || payload[13] != b'\xA4' {
      self.trace.push(
        IdentityTraceEvent::make(
          ObservationIgnored,
          Some(ordinal),
          observation.timestamp(),
          "ignored-unrelated-ethernet-frame",
        ),
      )
      ignored = ignored + 1
      if ignored > self.policy.max_ignored_observations() {
        raise ResponseRejected("too many ignored observations")
      }
      continue
    }
    let decoded = @protocol.EcFrame::decode(payload) catch {
      error =>
        raise ResponseRejected(
          "invalid EtherCAT response: " + @debug.to_string(error),
        )
    }
    if !valid_response_frame_context(decoded, self.context) ||
      decoded.pdus.length() != 1 {
      raise ResponseRejected("response frame context or PDU count is invalid")
    }
    let response = decoded.pdus[0]
    if !response_matches_request(
        response,
        command,
        index,
        address,
        data.length(),
      ) {
      raise ResponseRejected("response PDU does not match outstanding request")
    }
    self.trace.push(
      IdentityTraceEvent::make(
        ResponseAccepted,
        Some(ordinal),
        observation.timestamp(),
        "backend_sequence=" + observation.backend_sequence().to_string(),
      ),
    )
    return response
  }
}

///|
fn IdentityOperationState::exchange(
  self : IdentityOperationState,
  command : @protocol.EcCommand,
  address : UInt,
  data : Bytes,
  effect : ProviderEffectKind,
  position : Int?,
  require_single_wkc : Bool,
  allow_reserved_cleanup? : Bool = false,
) -> @protocol.Pdu raise IdentityProviderError {
  let index = (self.next_index % 256).to_byte()
  self.next_index = self.next_index + 1
  for attempt = 0
      attempt <= self.policy.max_transport_retries()
      attempt = attempt + 1 {
    let outcome : Result[@protocol.Pdu, IdentityProviderError] = Result::Ok(
      self.exchange_once(
        command, address, data, effect, position, index, allow_reserved_cleanup,
      ),
    ) catch {
      error => Result::Err(error)
    }
    match outcome {
      Ok(response) => {
        if require_single_wkc && response.wkc != 1U {
          raise ResponseRejected(
            "identity register transaction requires WKC=1, got " +
            response.wkc.to_string(),
          )
        }
        return response
      }
      Err(RetryableTransportFailure(message)) if attempt <
        self.policy.max_transport_retries() =>
        self.backoff(None, "transport-retry:" + message)
      Err(error) => raise error
    }
  }
  raise TransportFailure("transport retry loop exhausted")
}

///|
fn auto_increment_register_address(position : Int, register : UInt) -> UInt {
  @protocol.auto_increment_address(position.reinterpret_as_uint()) |
  ((register & 0xFFFFU) << 16)
}

///|
fn IdentityOperationState::write_sii(
  self : IdentityOperationState,
  position : Int,
  register : UInt,
  data : Bytes,
) -> Unit raise IdentityProviderError {
  ignore(
    self.exchange(
      @protocol.APWR,
      auto_increment_register_address(position, register),
      data,
      MutateVolatileSiiController,
      Some(position),
      true,
    ),
  )
}

///|
fn IdentityOperationState::restore_sii_pdi(
  self : IdentityOperationState,
  position : Int,
) -> Unit raise IdentityProviderError {
  ignore(
    self.exchange(
      @protocol.APWR,
      auto_increment_register_address(position, @protocol.reg_sii_config),
      Bytes::from_array([b'\x01']),
      MutateVolatileSiiController,
      Some(position),
      true,
      allow_reserved_cleanup=true,
    ),
  )
}

///|
fn IdentityOperationState::read_sii(
  self : IdentityOperationState,
  position : Int,
  register : UInt,
  length : Int,
) -> @protocol.Pdu raise IdentityProviderError {
  let effect = if register == @protocol.reg_sii_control {
    ObserveSiiControllerStatus
  } else {
    ReadIdentityMetadata
  }
  self.exchange(
    @protocol.APRD,
    auto_increment_register_address(position, register),
    Bytes::new(length),
    effect,
    Some(position),
    true,
  )
}

///|
fn IdentityOperationState::wait_sii_ready(
  self : IdentityOperationState,
  position : Int,
  phase : String,
) -> UInt raise IdentityProviderError {
  for poll = 0; poll < self.policy.max_sii_status_polls(); poll = poll + 1 {
    let response = self.read_sii(position, @protocol.reg_sii_control, 2)
    let status = response.data[0].to_uint() | (response.data[1].to_uint() << 8)
    self.trace.push(
      IdentityTraceEvent::make(
        SiiStatusPolled,
        Some(self.transaction_count),
        self.now(),
        "position=" +
        position.to_string() +
        ";phase=" +
        phase +
        ";poll=" +
        poll.to_string() +
        ";status=" +
        status.to_string(),
      ),
    )
    if (status & sii_ctrl_busy) == 0U {
      return status
    }
  }
  raise SiiReadRejected(position, "SII busy poll limit exceeded at " + phase)
}

///|
fn IdentityOperationState::clear_sii_errors(
  self : IdentityOperationState,
  position : Int,
) -> Unit raise IdentityProviderError {
  self.write_sii(
    position,
    @protocol.reg_sii_control,
    Bytes::from_array([b'\x00', b'\x00']),
  )
}

///|
fn IdentityOperationState::read_sii_chunk(
  self : IdentityOperationState,
  position : Int,
  word_address : UInt,
) -> Bytes raise IdentityProviderError {
  let initial = self.wait_sii_ready(position, "before-command")
  if (initial & sii_ctrl_error_mask) != 0U {
    self.clear_sii_errors(position)
    ignore(self.wait_sii_ready(position, "after-error-clear"))
  }
  for nack_attempt = 0
      nack_attempt <= self.policy.max_sii_nack_retries()
      nack_attempt = nack_attempt + 1 {
    self.write_sii(
      position,
      @protocol.reg_sii_control,
      Bytes::from_array([
        (sii_ctrl_read_cmd & 0xFFU).to_byte(),
        ((sii_ctrl_read_cmd >> 8) & 0xFFU).to_byte(),
        (word_address & 0xFFU).to_byte(),
        ((word_address >> 8) & 0xFFU).to_byte(),
        b'\x00',
        b'\x00',
      ]),
    )
    let status = self.wait_sii_ready(position, "after-read-command")
    if (status & sii_ctrl_nack) != 0U {
      if nack_attempt >= self.policy.max_sii_nack_retries() {
        raise SiiReadRejected(
          position,
          "SII NACK retry limit exceeded at word " + word_address.to_string(),
        )
      }
      self.clear_sii_errors(position)
      self.backoff(
        Some(self.transaction_count),
        "sii-nack-retry:position=" +
        position.to_string() +
        ";word=" +
        word_address.to_string(),
      )
      continue
    }
    if (status & sii_ctrl_error_mask) != 0U {
      raise SiiReadRejected(
        position,
        "SII status error at word " + word_address.to_string(),
      )
    }
    let read_length = if (status & sii_ctrl_r64) != 0U { 8 } else { 4 }
    return self.read_sii(position, @protocol.reg_sii_data, read_length).data
  }
  raise SiiReadRejected(position, "SII read loop exhausted")
}

///|
fn IdentityOperationState::read_identity_metadata(
  self : IdentityOperationState,
  position : Int,
) -> Bytes raise IdentityProviderError {
  self.sii_cleanup_reserved = true
  let read_result : Result[Bytes, IdentityProviderError] = Result::Ok(
    {
      self.require_budget(false)
      self.sii_ownership_may_be_changed = true
      self.write_sii(
        position,
        @protocol.reg_sii_config,
        Bytes::from_array([b'\x02']),
      )
      self.write_sii(
        position,
        @protocol.reg_sii_config,
        Bytes::from_array([b'\x00']),
      )
      let output = Buffer(size_hint=sii_identity_octets)
      let mut word = sii_identity_start_word
      while output.length() < sii_identity_octets {
        let chunk = self.read_sii_chunk(position, word)
        let remaining = sii_identity_octets - output.length()
        let take = if chunk.length() < remaining {
          chunk.length()
        } else {
          remaining
        }
        for index in 0..<take {
          output.write_byte(chunk[index])
        }
        word = word + (if chunk.length() >= 8 { 4U } else { 2U })
        if word > 16U && output.length() < sii_identity_octets {
          raise SiiReadRejected(
            position, "identity metadata exceeded words 8..15",
          )
        }
      }
      output.to_bytes()
    },
  ) catch {
    error => Result::Err(error)
  }
  let restore_result : Result[Unit, IdentityProviderError] = if self.sii_ownership_may_be_changed {
    Result::Ok(self.restore_sii_pdi(position)) catch {
      error => Result::Err(error)
    }
  } else {
    Result::Ok(())
  }
  self.sii_cleanup_reserved = false
  self.sii_ownership_may_be_changed = false
  match (read_result, restore_result) {
    (Ok(raw), Ok(_)) => raw
    (Err(read_error), Err(restore_error)) =>
      raise SiiReadRejected(
        position,
        "identity read failed and PDI restore also failed: read=" +
        @debug.to_string(read_error) +
        ";restore=" +
        @debug.to_string(restore_error),
      )
    (Err(error), _) => raise error
    (_, Err(error)) => raise error
  }
}

///|
fn raw_matches_pin(raw : Bytes, pin : @device_profile.DeviceProfilePin) -> Bool {
  provider_uint_le(raw, 0) == pin.vendor_id() &&
  provider_uint_le(raw, 4) == pin.product_code() &&
  provider_uint_le(raw, 8) == pin.revision() &&
  (match pin.serial() {
    None => true
    Some(serial) => provider_uint_le(raw, 12) == serial
  })
}

///|
fn classify_observed(
  raw : Bytes,
  position : Int,
  expected : ExpectedBusTopology,
  issues : Array[TopologyIssue],
) -> ObservedDeviceIdentity {
  let bindings = expected.bindings()
  if position >= bindings.length() {
    issues.push(ExtraDevice(position))
    return ObservedDeviceIdentity::make(position, raw, None, NoSelectedProfile)
  }
  let pin = bindings[position].profile_pin()
  let model_matches = provider_uint_le(raw, 0) == pin.vendor_id() &&
    provider_uint_le(raw, 4) == pin.product_code() &&
    provider_uint_le(raw, 8) == pin.revision()
  let verdict = if model_matches {
    match pin.serial() {
      Some(serial) if provider_uint_le(raw, 12) != serial => {
        issues.push(UnitSerialMismatchAt(position))
        UnitSerialMismatch
      }
      _ => ExactProfileMatch
    }
  } else {
    let mut reordered_from : Int? = None
    for expected_position, binding in bindings {
      if expected_position != position &&
        raw_matches_pin(raw, binding.profile_pin()) {
        reordered_from = Some(expected_position)
      }
    }
    match reordered_from {
      Some(expected_position) => {
        issues.push(
          ReorderedDevice(observed_position=position, expected_position~),
        )
        ModelOrRevisionMismatch
      }
      None => {
        issues.push(ModelOrRevisionMismatchAt(position))
        ModelOrRevisionMismatch
      }
    }
  }
  ObservedDeviceIdentity::make(
    position,
    raw,
    Some(pin.profile_digest()),
    verdict,
  )
}

///|
fn result_identity_strength(
  expected : ExpectedBusTopology,
  issues : Array[TopologyIssue],
) -> IdentityStrength {
  if !issues.is_empty() {
    return NoIdentityAssurance
  }
  for binding in expected.bindings() {
    if binding.profile_pin().serial() is None {
      return ModelAndTopology
    }
  }
  UnitIdentity
}

///|
/// Execute one bounded commissioning action. The port must already refer to an
/// opened runtime session; lifecycle orchestration remains outside this owner.
pub fn inspect_bus_identity(
  expected~ : ExpectedBusTopology,
  context~ : EthernetFrameContext,
  policy~ : InspectBusIdentityPolicy,
  deadline~ : @clock.DomainInstant,
  port~ : IdentityLinkPort,
) -> InspectBusIdentityResult raise IdentityProviderError {
  if expected.count() > policy.max_slaves() {
    raise InvalidTopology("expected topology exceeds policy max_slaves")
  }
  let state = IdentityOperationState::new(policy, context, port, deadline)
  let count_response = state.exchange(
    @protocol.BRD,
    @protocol.broadcast_address(@protocol.reg_type),
    Bytes::new(1),
    ProbeBusPopulation,
    None,
    false,
  )
  let actual_count = count_response.wkc.reinterpret_as_int()
  if actual_count > policy.max_slaves() {
    raise InvalidTopology("observed topology exceeds policy max_slaves")
  }
  let observed : Array[ObservedDeviceIdentity] = []
  let issues : Array[TopologyIssue] = []
  for position in 0..<actual_count {
    let raw = state.read_identity_metadata(position)
    if raw.length() != sii_identity_octets {
      raise SiiReadRejected(position, "identity metadata must contain 16 bytes")
    }
    observed.push(classify_observed(raw, position, expected, issues))
  }
  for position = actual_count
      position < expected.count()
      position = position + 1 {
    issues.push(MissingDevice(position))
  }
  let strength = result_identity_strength(expected, issues)
  InspectBusIdentityResult::make(
    expected.digest(),
    expected.count(),
    context.digest(),
    policy.digest(),
    port.source(),
    deadline,
    observed,
    issues,
    strength,
    state.effects,
    state.echoes,
    state.trace,
    state.transaction_count,
  )
}
