///|
extern "c" fn ffi_native_stub_version() -> Int = "moonecat_native_stub_version"

///|
pub fn native_stub_version() -> Int {
  ffi_native_stub_version()
}

///|
extern "c" fn ffi_native_last_error_code() -> Int = "moonecat_native_last_error_code"

///|
extern "c" fn ffi_native_last_error_message() -> Bytes = "moonecat_native_last_error_message"

///|
let native_error_success : Int = 1

///|
let native_error_timeout : Int = 0

///|
let native_error_link_down : Int = -2

///|
let native_error_permission : Int = -3

///|
let native_error_not_found : Int = -4

///|
fn native_last_error_code() -> Int {
  ffi_native_last_error_code()
}

///|
fn native_last_error_message() -> String {
  @utf8.decode_lossy(ffi_native_last_error_message())
}
