///|
pub let windows_npcap_backend_label : String = "npcap"

///|
#borrow(name)
extern "c" fn ffi_windows_npcap_open(
  name : Bytes,
  snaplen : Int,
  promisc : Bool,
  timeout_ms : Int,
) -> Int = "moonecat_windows_npcap_open"

///|
#borrow(data)
extern "c" fn ffi_windows_npcap_send(
  handle_id : Int,
  data : Bytes,
  length : Int,
) -> Int = "moonecat_windows_npcap_send"

///|
extern "c" fn ffi_windows_npcap_recv(handle_id : Int) -> Bytes = "moonecat_windows_npcap_recv"

///|
extern "c" fn ffi_windows_npcap_close(handle_id : Int) -> Unit = "moonecat_windows_npcap_close"

///|
extern "c" fn ffi_windows_npcap_available() -> Int = "moonecat_windows_npcap_available"

///|
extern "c" fn ffi_windows_npcap_list_interfaces_text() -> Bytes = "moonecat_windows_npcap_list_interfaces_text"

///|
extern "c" fn ffi_windows_npcap_list_interfaces_json() -> Bytes = "moonecat_windows_npcap_list_interfaces_json"

///|
pub fn windows_npcap_runtime_available() -> Bool {
  ffi_windows_npcap_available() != 0
}

///|
pub fn windows_npcap_list_interfaces_text() -> String raise @hal.EcError {
  if not(windows_npcap_runtime_available()) {
    raise @hal.EcError::NotSupported("Npcap runtime is not available")
  }
  @utf8.decode_lossy(ffi_windows_npcap_list_interfaces_text())
}

///|
pub fn windows_npcap_list_interfaces_json() -> String raise @hal.EcError {
  if not(windows_npcap_runtime_available()) {
    raise @hal.EcError::NotSupported("Npcap runtime is not available")
  }
  @utf8.decode_lossy(ffi_windows_npcap_list_interfaces_json())
}

///|
pub fn windows_npcap_open(config : NativeNicConfig) -> Int raise @hal.EcError {
  if not(windows_npcap_runtime_available()) {
    raise @hal.EcError::NotSupported("Npcap runtime is not available")
  }
  let handle_id = ffi_windows_npcap_open(
    @utf8.encode(config.interface_name),
    config.snaplen,
    config.promisc,
    config.timeout_ms,
  )
  if handle_id <= 0 {
    raise @hal.EcError::Internal(
      "Npcap open failed: " + native_last_error_message(),
    )
  }
  handle_id
}

///|
pub fn windows_npcap_send(
  handle_id : Int,
  data : Bytes,
) -> Int raise @hal.EcError {
  let sent = ffi_windows_npcap_send(handle_id, data, data.length())
  if sent < 0 {
    raise @hal.EcError::SendFailed(native_last_error_message())
  }
  sent
}

///|
pub fn windows_npcap_recv(handle_id : Int) -> Bytes raise @hal.EcError {
  let data = ffi_windows_npcap_recv(handle_id)
  match native_last_error_code() {
    1 => data
    0 => raise @hal.EcError::RecvTimeout
    _ => raise @hal.EcError::RecvFailed(native_last_error_message())
  }
}

///|
pub fn windows_npcap_close(handle_id : Int) -> Unit {
  ffi_windows_npcap_close(handle_id)
}
