///|
/// Fallback zero-copy FFI stubs for wasm-gc target.
/// All functions raise NotSupported since zero-copy requires native backend.

///|
pub fn npcap_send_zero_copy(
  _handle_id : Int,
  _buf : FixedArray[Byte],
  _length : Int,
) -> Int raise @hal.EcError {
  raise @hal.EcError::NotSupported("Zero-copy Npcap not available on wasm-gc")
}

///|
pub fn npcap_recv_zero_copy(
  _handle_id : Int,
  _buf : FixedArray[Byte],
  _max_len : Int,
) -> Int raise @hal.EcError {
  raise @hal.EcError::NotSupported("Zero-copy Npcap not available on wasm-gc")
}

///|
pub fn linux_send_zero_copy(
  _handle_id : Int,
  _buf : FixedArray[Byte],
  _length : Int,
) -> Int raise @hal.EcError {
  raise @hal.EcError::NotSupported(
    "Zero-copy Linux raw socket not available on wasm-gc",
  )
}

///|
pub fn linux_recv_zero_copy(
  _handle_id : Int,
  _buf : FixedArray[Byte],
  _max_len : Int,
) -> Int raise @hal.EcError {
  raise @hal.EcError::NotSupported(
    "Zero-copy Linux raw socket not available on wasm-gc",
  )
}
