///|
pub let linux_raw_socket_backend_label : String = "raw-socket"

///|
pub fn linux_raw_socket_runtime_available() -> Bool {
  false
}

///|
pub fn linux_raw_socket_list_interfaces_text() -> String raise @hal.EcError {
  raise @hal.EcError::NotSupported(native_last_error_message())
}

///|
pub fn linux_raw_socket_list_interfaces_json() -> String raise @hal.EcError {
  raise @hal.EcError::NotSupported(native_last_error_message())
}

///|
pub fn linux_raw_socket_open(
  config : NativeNicConfig,
) -> Int raise @hal.EcError {
  ignore(config)
  raise @hal.EcError::NotSupported(native_last_error_message())
}

///|
pub fn linux_raw_socket_send(
  handle_id : Int,
  data : Bytes,
) -> Int raise @hal.EcError {
  ignore(handle_id)
  ignore(data)
  raise @hal.EcError::NotSupported(native_last_error_message())
}

///|
pub fn linux_raw_socket_recv(handle_id : Int) -> Bytes raise @hal.EcError {
  ignore(handle_id)
  raise @hal.EcError::NotSupported(native_last_error_message())
}

///|
pub fn linux_raw_socket_close(handle_id : Int) -> Unit {
  ignore(handle_id)
}
