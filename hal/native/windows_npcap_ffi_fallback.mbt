///|
pub let windows_npcap_backend_label : String = "npcap"

///|
pub fn windows_npcap_runtime_available() -> Bool {
  false
}

///|
pub fn windows_npcap_list_interfaces_text() -> String raise @hal.EcError {
  raise @hal.EcError::NotSupported(native_last_error_message())
}

///|
pub fn windows_npcap_open(config : NativeNicConfig) -> Int raise @hal.EcError {
  ignore(config)
  raise @hal.EcError::NotSupported(native_last_error_message())
}

///|
pub fn windows_npcap_send(
  handle_id : Int,
  data : Bytes,
) -> Int raise @hal.EcError {
  ignore(handle_id)
  ignore(data)
  raise @hal.EcError::NotSupported(native_last_error_message())
}

///|
pub fn windows_npcap_recv(handle_id : Int) -> Bytes raise @hal.EcError {
  ignore(handle_id)
  raise @hal.EcError::NotSupported(native_last_error_message())
}

///|
pub fn windows_npcap_close(handle_id : Int) -> Unit {
  ignore(handle_id)
}
