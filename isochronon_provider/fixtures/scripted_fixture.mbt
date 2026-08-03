///|
pub struct FixtureDeviceIdentity {
  priv vendor_id : UInt
  priv product_code : UInt
  priv revision : UInt
  priv serial : UInt
}

///|
pub fn FixtureDeviceIdentity::new(
  vendor_id~ : UInt,
  product_code~ : UInt,
  revision~ : UInt,
  serial~ : UInt,
) -> FixtureDeviceIdentity {
  { vendor_id, product_code, revision, serial }
}

///|
pub fn FixtureDeviceIdentity::vendor_id(self : FixtureDeviceIdentity) -> UInt {
  self.vendor_id
}

///|
pub fn FixtureDeviceIdentity::product_code(
  self : FixtureDeviceIdentity,
) -> UInt {
  self.product_code
}

///|
pub fn FixtureDeviceIdentity::revision(self : FixtureDeviceIdentity) -> UInt {
  self.revision
}

///|
pub fn FixtureDeviceIdentity::serial(self : FixtureDeviceIdentity) -> UInt {
  self.serial
}

///|
fn write_fixture_u32(output : Buffer, value : UInt) -> Unit {
  output.write_byte((value & 0xFFU).to_byte())
  output.write_byte(((value >> 8) & 0xFFU).to_byte())
  output.write_byte(((value >> 16) & 0xFFU).to_byte())
  output.write_byte(((value >> 24) & 0xFFU).to_byte())
}

///|
fn FixtureDeviceIdentity::raw(self : FixtureDeviceIdentity) -> Bytes {
  let output = Buffer(size_hint=16)
  write_fixture_u32(output, self.vendor_id)
  write_fixture_u32(output, self.product_code)
  write_fixture_u32(output, self.revision)
  write_fixture_u32(output, self.serial)
  output.to_bytes()
}

///|
priv struct PendingFixtureObservation {
  payload : Bytes
  completes_transaction : Bool
}

///|
priv struct ScriptedIdentityState {
  source : @isochronon_provider.ProviderExecutionSource
  domain : @clock.DomainId
  devices : Array[FixtureDeviceIdentity]
  current_mac : Bytes
  emit_echo : Bool
  mut fail_next_poll : Bool
  mut now_ns : Int64
  mut sequence : Int64
  mut outstanding : Int
  mut max_outstanding : Int
  submitted_frames : Array[Bytes]
  poll_deadlines : Array[@clock.DomainInstant]
  accessed_registers : Array[UInt]
  accessed_sii_words : Array[UInt]
  current_sii_words : Array[UInt]
  pending : Array[PendingFixtureObservation]
}

///|
fn fixture_copy_bytes(value : Bytes) -> Bytes {
  Bytes::makei(value.length(), fn(index) { value[index] })
}

///|
fn fixture_padded_frame(frame : @protocol.EcFrame) -> Bytes {
  let encoded = frame.encode()
  if encoded.length() >= 60 {
    encoded
  } else {
    Bytes::makei(60, fn(index) {
      if index < encoded.length() { encoded[index] } else { b'\x00' }
    })
  }
}

///|
fn fixture_response_data(
  state : ScriptedIdentityState,
  request : @protocol.Pdu,
) -> (Bytes, UInt) raise @isochronon_provider.IdentityProviderError {
  let register = @protocol.address_offset(request.header.address)
  match request.header.command {
    @protocol.BRD => {
      if register != @protocol.reg_type || request.data.length() != 1 {
        raise @isochronon_provider.TransportFailure(
          "fixture received an unsupported broadcast request",
        )
      }
      (Bytes::new(1), state.devices.length().reinterpret_as_uint())
    }
    @protocol.APWR => {
      let position = @protocol.address_station(
        request.header.address,
      ).reinterpret_as_int()
      if position < 0 || position >= state.devices.length() {
        raise @isochronon_provider.TransportFailure(
          "fixture APWR position is outside observed topology",
        )
      }
      state.accessed_registers.push(register)
      if register == @protocol.reg_sii_control && request.data.length() == 6 {
        let word = request.data[2].to_uint() |
          (request.data[3].to_uint() << 8)
        state.current_sii_words[position] = word
        state.accessed_sii_words.push(word)
      } else if register != @protocol.reg_sii_config &&
        register != @protocol.reg_sii_control {
        raise @isochronon_provider.TransportFailure(
          "fixture APWR accessed a non-SII register",
        )
      }
      (fixture_copy_bytes(request.data), 1U)
    }
    @protocol.APRD => {
      let position = @protocol.address_station(
        request.header.address,
      ).reinterpret_as_int()
      if position < 0 || position >= state.devices.length() {
        raise @isochronon_provider.TransportFailure(
          "fixture APRD position is outside observed topology",
        )
      }
      state.accessed_registers.push(register)
      if register == @protocol.reg_sii_control && request.data.length() == 2 {
        (Bytes::new(2), 1U)
      } else if register == @protocol.reg_sii_data &&
        (request.data.length() == 4 || request.data.length() == 8) {
        let raw = state.devices[position].raw()
        let byte_offset = (state.current_sii_words[position] - 8U).reinterpret_as_int() * 2
        if byte_offset < 0 || byte_offset + request.data.length() > raw.length() {
          raise @isochronon_provider.TransportFailure(
            "fixture SII data request escaped identity words 8..15",
          )
        }
        (
          Bytes::makei(request.data.length(), fn(index) {
            raw[byte_offset + index]
          }),
          1U,
        )
      } else {
        raise @isochronon_provider.TransportFailure(
          "fixture APRD accessed a non-identity SII register",
        )
      }
    }
    _ =>
      raise @isochronon_provider.TransportFailure(
        "fixture received an unsupported EtherCAT command",
      )
  }
}

///|
fn fixture_build_response(
  state : ScriptedIdentityState,
  request_bytes : Bytes,
) -> Bytes raise @isochronon_provider.IdentityProviderError {
  let frame = @protocol.EcFrame::decode(request_bytes) catch {
    error =>
      raise @isochronon_provider.TransportFailure(@debug.to_string(error))
  }
  if frame.pdus.length() != 1 {
    raise @isochronon_provider.TransportFailure(
      "fixture requires one PDU per request",
    )
  }
  let request = frame.pdus[0]
  let (data, wkc) = fixture_response_data(state, request)
  fixture_padded_frame({
    dst_mac: FixedArray::makei(6, fn(index) { frame.dst_mac[index] }),
    src_mac: FixedArray::makei(6, fn(index) { frame.src_mac[index] }),
    pdus: [
      {
        header: {
          command: request.header.command,
          index: request.header.index,
          address: request.header.address,
          len_flags: data.length().reinterpret_as_uint(),
          irq: 0U,
        },
        data,
        wkc,
      },
    ],
  })
}

///|
fn ScriptedIdentityState::submit(
  self : ScriptedIdentityState,
  payload : Bytes,
) -> Unit raise @isochronon_provider.IdentityProviderError {
  if self.outstanding != 0 {
    raise @isochronon_provider.TransportFailure(
      "fixture detected more than one outstanding transaction",
    )
  }
  self.outstanding = 1
  if self.outstanding > self.max_outstanding {
    self.max_outstanding = self.outstanding
  }
  let owned = fixture_copy_bytes(payload)
  self.submitted_frames.push(owned)
  let response = fixture_build_response(self, owned)
  if self.emit_echo {
    self.pending.push({ payload: owned, completes_transaction: false })
  }
  self.pending.push({ payload: response, completes_transaction: true })
  self.now_ns = self.now_ns + 1L
}

///|
fn ScriptedIdentityState::poll(
  self : ScriptedIdentityState,
  deadline : @clock.DomainInstant,
) -> @runtime.RxObservation? raise @isochronon_provider.IdentityProviderError {
  self.poll_deadlines.push(deadline)
  if self.fail_next_poll {
    self.fail_next_poll = false
    self.outstanding = 0
    self.pending.clear()
    raise @isochronon_provider.RetryableTransportFailure(
      "fixture injected one poll failure",
    )
  }
  if self.pending.is_empty() {
    self.outstanding = 0
    return None
  }
  let item = self.pending.remove(0)
  if item.completes_transaction {
    self.outstanding = 0
  }
  self.sequence = self.sequence + 1L
  self.now_ns = self.now_ns + 1L
  let payload = fixture_copy_bytes(item.payload)
  Some(
    @runtime.RxObservation::new(
      payload~,
      captured_length=payload.length(),
      original_length=payload.length(),
      logical_length=payload.length(),
      timestamp=@clock.DomainInstant::new(
        domain=self.domain, ns=self.now_ns,
      ),
      direction=@runtime.UnknownDirection,
      backend_sequence=self.sequence,
      provenance=@runtime.CopiedBuffer,
    ) catch {
      error =>
        raise @isochronon_provider.TransportFailure(@debug.to_string(error))
    },
  )
}

///|
pub struct IdentityFixtureHarness {
  priv state : ScriptedIdentityState
  priv port : @isochronon_provider.IdentityLinkPort
}

///|
pub fn IdentityFixtureHarness::new(
  source~ : @isochronon_provider.ProviderExecutionSource,
  domain~ : @clock.DomainId,
  current_mac~ : Bytes,
  devices~ : Array[FixtureDeviceIdentity],
  emit_echo? : Bool = true,
  inject_one_poll_failure? : Bool = false,
) -> IdentityFixtureHarness raise @isochronon_provider.IdentityProviderError {
  if devices.is_empty() || devices.length() > 64 || current_mac.length() != 6 {
    raise @isochronon_provider.InvalidContext(
      "fixture requires 1..64 devices and a six-byte current MAC",
    )
  }
  let state : ScriptedIdentityState = {
    source,
    domain,
    devices: devices.copy(),
    current_mac: fixture_copy_bytes(current_mac),
    emit_echo,
    fail_next_poll: inject_one_poll_failure,
    now_ns: 1_000L,
    sequence: 0L,
    outstanding: 0,
    max_outstanding: 0,
    submitted_frames: [],
    poll_deadlines: [],
    accessed_registers: [],
    accessed_sii_words: [],
    current_sii_words: Array::make(devices.length(), 0U),
    pending: [],
  }
  let port = @isochronon_provider.IdentityLinkPort::new(
    source~,
    now_fn=fn() { @clock.DomainInstant::new(domain~, ns=state.now_ns) },
    submit_fn=(payload) => state.submit(payload),
    poll_fn=(deadline) => state.poll(deadline),
    sleep_until_fn=(deadline) => {
      if deadline.domain() != state.domain || deadline.ns() < state.now_ns {
        raise @isochronon_provider.InvalidContext(
          "fixture sleep deadline is invalid",
        )
      }
      state.now_ns = deadline.ns()
    },
  )
  { state, port }
}

///|
pub fn IdentityFixtureHarness::port(
  self : IdentityFixtureHarness,
) -> @isochronon_provider.IdentityLinkPort {
  self.port
}

///|
pub fn IdentityFixtureHarness::now(
  self : IdentityFixtureHarness,
) -> @clock.DomainInstant {
  @clock.DomainInstant::new(domain=self.state.domain, ns=self.state.now_ns)
}

///|
pub fn IdentityFixtureHarness::submitted_frames(
  self : IdentityFixtureHarness,
) -> Array[Bytes] {
  self.state.submitted_frames.map(fixture_copy_bytes)
}

///|
pub fn IdentityFixtureHarness::poll_deadlines(
  self : IdentityFixtureHarness,
) -> Array[@clock.DomainInstant] {
  self.state.poll_deadlines.copy()
}

///|
pub fn IdentityFixtureHarness::max_outstanding_transactions(
  self : IdentityFixtureHarness,
) -> Int {
  self.state.max_outstanding
}

///|
pub fn IdentityFixtureHarness::source(
  self : IdentityFixtureHarness,
) -> @isochronon_provider.ProviderExecutionSource {
  self.state.source
}

///|
pub fn IdentityFixtureHarness::current_mac(
  self : IdentityFixtureHarness,
) -> Bytes {
  fixture_copy_bytes(self.state.current_mac)
}

///|
pub fn IdentityFixtureHarness::accessed_registers(
  self : IdentityFixtureHarness,
) -> Array[UInt] {
  self.state.accessed_registers.copy()
}

///|
pub fn IdentityFixtureHarness::accessed_sii_words(
  self : IdentityFixtureHarness,
) -> Array[UInt] {
  self.state.accessed_sii_words.copy()
}

///|
pub fn identity_fixture_package_id() -> String {
  "mokomoking2501/MoonECAT/isochronon_provider/fixtures"
}
