///|
pub let linux_raw_socket_backend_label : String = "raw-socket"

///|
extern "c" fn ffi_linux_raw_socket_available() -> Int = "moonecat_linux_raw_socket_available"

///|
#borrow(name)
extern "c" fn ffi_linux_raw_socket_open(
  name : Bytes,
  snaplen : Int,
  promisc : Bool,
  timeout_ms : Int,
) -> Int = "moonecat_linux_raw_socket_open"

///|
#borrow(data)
extern "c" fn ffi_linux_raw_socket_send(
  handle_id : Int,
  data : Bytes,
  length : Int,
) -> Int = "moonecat_linux_raw_socket_send"

///|
extern "c" fn ffi_linux_raw_socket_recv(handle_id : Int) -> Bytes = "moonecat_linux_raw_socket_recv"

///|
extern "c" fn ffi_linux_raw_socket_close(handle_id : Int) -> Unit = "moonecat_linux_raw_socket_close"

///|
extern "c" fn ffi_linux_raw_socket_list_interfaces_text() -> Bytes = "moonecat_linux_raw_socket_list_interfaces_text"

///|
extern "c" fn ffi_linux_raw_socket_list_interfaces_json() -> Bytes = "moonecat_linux_raw_socket_list_interfaces_json"

///|
pub fn linux_raw_socket_runtime_available() -> Bool {
  ffi_linux_raw_socket_available() != 0
}

///|
pub fn linux_raw_socket_list_interfaces_text() -> String raise @hal.EcError {
  if not(linux_raw_socket_runtime_available()) {
    raise @hal.EcError::NotSupported(
      "Linux Raw Socket backend is not available",
    )
  }
  @utf8.decode_lossy(ffi_linux_raw_socket_list_interfaces_text())
}

///|
pub fn linux_raw_socket_list_interfaces_json() -> String raise @hal.EcError {
  if not(linux_raw_socket_runtime_available()) {
    raise @hal.EcError::NotSupported(
      "Linux Raw Socket backend is not available",
    )
  }
  @utf8.decode_lossy(ffi_linux_raw_socket_list_interfaces_json())
}

///|
pub fn linux_raw_socket_open(
  config : NativeNicConfig,
) -> Int raise @hal.EcError {
  if not(linux_raw_socket_runtime_available()) {
    raise @hal.EcError::NotSupported(
      "Linux Raw Socket backend is not available",
    )
  }
  let handle_id = ffi_linux_raw_socket_open(
    @utf8.encode(config.interface_name),
    config.snaplen,
    config.promisc,
    config.timeout_ms,
  )
  if handle_id <= 0 {
    raise_linux_raw_socket_open_error(
      native_last_error_code(),
      native_last_error_message(),
    )
  }
  handle_id
}

///|
pub fn linux_raw_socket_send(
  handle_id : Int,
  data : Bytes,
) -> Int raise @hal.EcError {
  let sent = ffi_linux_raw_socket_send(handle_id, data, data.length())
  if sent < 0 {
    raise_linux_raw_socket_send_error(
      native_last_error_code(),
      native_last_error_message(),
    )
  }
  sent
}

///|
pub fn linux_raw_socket_recv(handle_id : Int) -> Bytes raise @hal.EcError {
  let data = ffi_linux_raw_socket_recv(handle_id)
  match native_last_error_code() {
    code if code == native_error_success => data
    code if code == native_error_timeout => raise @hal.EcError::RecvTimeout
    code => {
      raise_linux_raw_socket_recv_error(code, native_last_error_message())
      Bytes::new(0)
    }
  }
}

///|
fn raise_linux_raw_socket_open_error(
  code : Int,
  message : String,
) -> Unit raise @hal.EcError {
  match code {
    c if c == native_error_link_down => raise @hal.EcError::LinkDown
    c if c == native_error_permission =>
      raise @hal.EcError::NotSupported(
        "Linux Raw Socket requires raw-socket privileges: " + message,
      )
    c if c == native_error_not_found =>
      raise @hal.EcError::ConfigMismatch(
        "Linux Raw Socket interface is not available: " + message,
      )
    _ =>
      raise @hal.EcError::Internal("Linux Raw Socket open failed: " + message)
  }
}

///|
fn raise_linux_raw_socket_send_error(
  code : Int,
  message : String,
) -> Unit raise @hal.EcError {
  match code {
    c if c == native_error_link_down => raise @hal.EcError::LinkDown
    c if c == native_error_permission =>
      raise @hal.EcError::NotSupported(
        "Linux Raw Socket send requires raw-socket privileges: " + message,
      )
    _ => raise @hal.EcError::SendFailed(message)
  }
}

///|
fn raise_linux_raw_socket_recv_error(
  code : Int,
  message : String,
) -> Unit raise @hal.EcError {
  match code {
    c if c == native_error_link_down => raise @hal.EcError::LinkDown
    c if c == native_error_permission =>
      raise @hal.EcError::NotSupported(
        "Linux Raw Socket recv requires raw-socket privileges: " + message,
      )
    _ => raise @hal.EcError::RecvFailed(message)
  }
}

///|
pub fn linux_raw_socket_close(handle_id : Int) -> Unit {
  ffi_linux_raw_socket_close(handle_id)
}
