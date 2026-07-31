///|
fn native_test_two_datagram_frame() -> Bytes {
  let frame = FixedArray::make(40, b'\x00')
  frame[12] = b'\x88'
  frame[13] = b'\xA4'
  // EtherCAT payload: two empty datagrams, 12 bytes each.
  frame[14] = b'\x18'
  frame[15] = b'\x10'
  frame[16] = b'\x04'
  frame[17] = b'\x42'
  frame[23] = b'\x80'
  frame[28] = b'\x05'
  frame[29] = b'\x24'
  Bytes::from_array(frame)
}

///|
test "native wire datagram indices increment and wrap" {
  let original = native_test_two_datagram_frame()
  let (wire, protocol_indices, wire_indices, next) = prepare_native_send(
    original, 0xFF,
  )
  @debug.assert_eq(protocol_indices, [b'\x42', b'\x24'])
  @debug.assert_eq(wire_indices, [b'\xFF', b'\x00'])
  @debug.assert_eq(wire[17], b'\xFF')
  @debug.assert_eq(wire[29], b'\x00')
  @debug.assert_eq(next, 1)
}

///|
test "native response indices restore to protocol values" {
  let original = native_test_two_datagram_frame()
  let (wire, protocol_indices, wire_indices, _) = prepare_native_send(
    original, 0x6E,
  )
  let restored = restore_native_response_indices(
    wire, protocol_indices, wire_indices,
  )
  @debug.assert_eq(restored, original)
  let unrelated = FixedArray::make(wire.length(), b'\x00')
  for i in 0..<wire.length() {
    unrelated[i] = wire[i]
  }
  unrelated[17] = b'\x7F'
  let unrelated_bytes = Bytes::from_array(unrelated)
  @debug.assert_eq(
    restore_native_response_indices(
      unrelated_bytes, protocol_indices, wire_indices,
    ),
    unrelated_bytes,
  )
}

///|
test "native linux raw socket error helpers classify link and privilege issues" {
  let link_down_open : Result[Unit, Error] = Result::Ok(
    raise_linux_raw_socket_open_error(native_error_link_down, "network down"),
  ) catch {
    err => Result::Err(err)
  }
  let missing_open : Result[Unit, Error] = Result::Ok(
    raise_linux_raw_socket_open_error(native_error_not_found, "no such device"),
  ) catch {
    err => Result::Err(err)
  }
  let privilege_open : Result[Unit, Error] = Result::Ok(
    raise_linux_raw_socket_open_error(
      native_error_permission, "operation not permitted",
    ),
  ) catch {
    err => Result::Err(err)
  }
  let send_link_down : Result[Unit, Error] = Result::Ok(
    raise_linux_raw_socket_send_error(native_error_link_down, "device missing"),
  ) catch {
    err => Result::Err(err)
  }
  let recv_privilege : Result[Unit, Error] = Result::Ok(
    raise_linux_raw_socket_recv_error(
      native_error_permission, "permission denied",
    ),
  ) catch {
    err => Result::Err(err)
  }
  assert_true(link_down_open is Err(@hal.EcError::LinkDown))
  assert_true(missing_open is Err(@hal.EcError::ConfigMismatch(_)))
  assert_true(privilege_open is Err(@hal.EcError::NotSupported(_)))
  assert_true(send_link_down is Err(@hal.EcError::LinkDown))
  assert_true(recv_privilege is Err(@hal.EcError::NotSupported(_)))
}
