///|
test "native linux raw socket error helpers classify link and privilege issues" {
  let link_down_open : Result[Unit, Error] = try? raise_linux_raw_socket_open_error(
    native_error_link_down, "network down",
  )
  let missing_open : Result[Unit, Error] = try? raise_linux_raw_socket_open_error(
    native_error_not_found, "no such device",
  )
  let privilege_open : Result[Unit, Error] = try? raise_linux_raw_socket_open_error(
    native_error_permission, "operation not permitted",
  )
  let send_link_down : Result[Unit, Error] = try? raise_linux_raw_socket_send_error(
    native_error_link_down, "device missing",
  )
  let recv_privilege : Result[Unit, Error] = try? raise_linux_raw_socket_recv_error(
    native_error_permission, "permission denied",
  )
  assert_true(link_down_open is Err(@hal.EcError::LinkDown))
  assert_true(missing_open is Err(@hal.EcError::ConfigMismatch(_)))
  assert_true(privilege_open is Err(@hal.EcError::NotSupported(_)))
  assert_true(send_link_down is Err(@hal.EcError::LinkDown))
  assert_true(recv_privilege is Err(@hal.EcError::NotSupported(_)))
}
