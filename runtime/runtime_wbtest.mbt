///|
test "scan station address strategy seam keeps twincat path replaceable" {
  let observed : Array[ObservedSlaveAddress] = [
    { position: 0U, current_station_address: 0U },
    { position: 1U, current_station_address: 0x2001U },
    { position: 2U, current_station_address: 0x2001U },
  ]
  let preserved = plan_scan_station_addresses_with_strategy(
    observed,
    PreserveExistingUniqueNonZero,
  )
  let twincat = plan_scan_station_addresses_with_strategy(
    observed,
    TwinCATCompatible,
  )
  assert_eq(preserved, [0x1001U, 0x1002U, 0x1003U])
  assert_eq(twincat, preserved)
}

///|
fn build_esm_response_frame(
  request : @protocol.EcFrame,
  data : Bytes,
  wkc : UInt,
) -> Bytes {
  let request_pdu = request.pdus[0]
  (
    {
      dst_mac: request.src_mac,
      src_mac: request.dst_mac,
      pdus: [
        {
          header: {
            command: request_pdu.header.command,
            index: request_pdu.header.index,
            address: request_pdu.header.address,
            len_flags: data.length().reinterpret_as_uint(),
            irq: request_pdu.header.irq,
          },
          data,
          wkc,
        },
      ],
    } : @protocol.EcFrame).encode()
}

///|
pub struct StrictRunTransitionNic {
  mut next_response : Bytes
  mut is_open : Bool
  mut current_state : Byte
  mut error_indication : Bool
  mut status_code : UInt
  control_writes : Array[Byte]
}

///|
fn StrictRunTransitionNic::new(
  current_state : @protocol.EsmState,
  error_indication : Bool,
  status_code : UInt,
) -> StrictRunTransitionNic {
  {
    next_response: Bytes::new(0),
    is_open: true,
    current_state: current_state.to_byte(),
    error_indication,
    status_code,
    control_writes: [],
  }
}

///|
fn strict_status_bytes(nic : StrictRunTransitionNic) -> Bytes {
  let status = if nic.error_indication {
    nic.current_state | b'\x10'
  } else {
    nic.current_state
  }
  Bytes::from_array([status, b'\x00'])
}

///|
fn strict_status_code_bytes(status_code : UInt) -> Bytes {
  Bytes::from_array([
    (status_code & 0xFFU).reinterpret_as_int().to_byte(),
    ((status_code >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
  ])
}

///|
pub impl @hal.Nic for StrictRunTransitionNic with open_(name) {
  ignore(name)
  StrictRunTransitionNic::new(@protocol.EsmState::Init, false, 0U)
}

///|
pub impl @hal.Nic for StrictRunTransitionNic with send(self, data) {
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  let request = @protocol.EcFrame::decode(data)
  let pdu = request.pdus[0]
  let offset = @protocol.address_offset(pdu.header.address)
  self.next_response = match pdu.header.command {
    @protocol.FPRD => {
      let response_data = if offset == @protocol.reg_al_status {
        strict_status_bytes(self)
      } else if offset == @protocol.reg_al_status_code {
        strict_status_code_bytes(self.status_code)
      } else {
        Bytes::new(pdu.data.length())
      }
      build_esm_response_frame(request, response_data, 1U)
    }
    @protocol.FPWR => {
      if offset == @protocol.reg_al_control && pdu.data.length() >= 1 {
        let control = pdu.data[0]
        self.control_writes.push(control)
        let requested_state = control & b'\x0F'
        let acknowledge = (control & b'\x10') != b'\x00'
        if acknowledge {
          self.error_indication = false
          self.status_code = 0U
        }
        if requested_state != self.current_state {
          let current = @protocol.EsmState::from_byte(self.current_state)
          let target = @protocol.EsmState::from_byte(requested_state)
          if current.can_transition(target) {
            self.current_state = requested_state
            self.error_indication = false
            self.status_code = 0U
          } else {
            self.error_indication = true
            self.status_code = 0x0011U
          }
        }
      }
      build_esm_response_frame(request, strict_status_bytes(self), 1U)
    }
    _ => build_esm_response_frame(request, Bytes::new(pdu.data.length()), 1U)
  }
  data.length()
}

///|
pub impl @hal.Nic for StrictRunTransitionNic with recv(self, timeout~) {
  ignore(timeout)
  if not(self.is_open) {
    raise @hal.EcError::LinkDown
  }
  self.next_response
}

///|
pub impl @hal.Nic for StrictRunTransitionNic with close(self) {
  self.is_open = false
}

///|
test "runtime startup transition clears error then follows strict route" {
  let nic = StrictRunTransitionNic::new(
    @protocol.EsmState::SafeOp,
    true,
    0x0016U,
  )
  let timeout = @hal.Duration(1000L)
  let ok = attempt_transition_slave_to_target(
    nic,
    0x1001U,
    @protocol.EsmState::Init,
    timeout,
  )
  assert_true(ok)
  assert_eq(nic.control_writes.length(), 3)
  assert_eq(
    nic.control_writes[0],
    @protocol.EsmState::SafeOp.to_byte() | b'\x10',
  )
  assert_eq(
    nic.control_writes[1] & b'\x0F',
    @protocol.EsmState::PreOp.to_byte(),
  )
  assert_eq(nic.control_writes[2] & b'\x0F', @protocol.EsmState::Init.to_byte())
}
