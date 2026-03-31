///|
/// Zero-copy FFI for Npcap: receive directly into pre-allocated buffer.
/// Returns number of bytes received, 0 for timeout, negative for error.
#borrow(buf)
extern "c" fn ffi_npcap_recv_into(
  handle_id : Int,
  buf : FixedArray[Byte],
  max_len : Int
) -> Int = "moonecat_npcap_recv_into"

///|
/// Zero-copy FFI for Npcap: send from FixedArray buffer.
#borrow(buf)
extern "c" fn ffi_npcap_send_fixed(
  handle_id : Int,
  buf : FixedArray[Byte],
  length : Int
) -> Int = "moonecat_npcap_send_fixed"

///|
/// Zero-copy FFI for Linux raw socket: receive directly into pre-allocated buffer.
#borrow(buf)
extern "c" fn ffi_linux_recv_into(
  handle_id : Int,
  buf : FixedArray[Byte],
  max_len : Int
) -> Int = "moonecat_linux_recv_into"

///|
/// Zero-copy FFI for Linux raw socket: send from FixedArray buffer.
#borrow(buf)
extern "c" fn ffi_linux_send_fixed(
  handle_id : Int,
  buf : FixedArray[Byte],
  length : Int
) -> Int = "moonecat_linux_send_fixed"

///|
/// Zero-copy Npcap send wrapper raising EcError on failure.
pub fn npcap_send_zero_copy(
  handle_id : Int,
  buf : FixedArray[Byte],
  length : Int
) -> Int raise @hal.EcError {
  let result = ffi_npcap_send_fixed(handle_id, buf, length)
  if result < 0 {
    raise @hal.EcError::SendFailed("Npcap zero-copy send failed")
  }
  result
}

///|
/// Zero-copy Npcap recv wrapper raising EcError on timeout/error.
pub fn npcap_recv_zero_copy(
  handle_id : Int,
  buf : FixedArray[Byte],
  max_len : Int
) -> Int raise @hal.EcError {
  let result = ffi_npcap_recv_into(handle_id, buf, max_len)
  if result < 0 {
    raise @hal.EcError::RecvFailed("Npcap zero-copy recv error")
  }
  if result == 0 {
    raise @hal.EcError::RecvTimeout
  }
  result
}

///|
/// Zero-copy Linux raw socket send wrapper.
pub fn linux_send_zero_copy(
  handle_id : Int,
  buf : FixedArray[Byte],
  length : Int
) -> Int raise @hal.EcError {
  let result = ffi_linux_send_fixed(handle_id, buf, length)
  if result < 0 {
    raise @hal.EcError::SendFailed("Linux zero-copy send failed")
  }
  result
}

///|
/// Zero-copy Linux raw socket recv wrapper.
pub fn linux_recv_zero_copy(
  handle_id : Int,
  buf : FixedArray[Byte],
  max_len : Int
) -> Int raise @hal.EcError {
  let result = ffi_linux_recv_into(handle_id, buf, max_len)
  if result < 0 {
    raise @hal.EcError::RecvFailed("Linux zero-copy recv error")
  }
  if result == 0 {
    raise @hal.EcError::RecvTimeout
  }
  result
}
