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
    raise @hal.EcError::Internal(
      "Linux Raw Socket open failed: " + native_last_error_message(),
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
    raise @hal.EcError::SendFailed(native_last_error_message())
  }
  sent
}

///|
pub fn linux_raw_socket_recv(handle_id : Int) -> Bytes raise @hal.EcError {
  let data = ffi_linux_raw_socket_recv(handle_id)
  match native_last_error_code() {
    1 => data
    0 => raise @hal.EcError::RecvTimeout
    _ => raise @hal.EcError::RecvFailed(native_last_error_message())
  }
}

///|
pub fn linux_raw_socket_close(handle_id : Int) -> Unit {
  ffi_linux_raw_socket_close(handle_id)
}
