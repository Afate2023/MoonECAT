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
