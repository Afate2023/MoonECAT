///|
test "native scaffold exposes config defaults" {
  let linux = default_linux_config("eth0")
  let windows = default_windows_npcap_config("\\\\Device\\\\NPF_{GUID}")
  assert_eq(linux.backend, LinuxRawSocket)
  assert_eq(windows.backend, WindowsNpcap)
  assert_eq(linux.snaplen, @hal.max_frame_size)
}

///|
test "native scaffold exposes stub runtime and availability" {
  assert_eq(native_stub_version(), 1)
  let _ = windows_npcap_runtime_available()
}

///|
test "native scaffold keeps linux placeholder explicit" {
  let result : Result[NativeNic, Error] = try? NativeNic::open_with_config(
    default_linux_config("eth0"),
  )
  guard result is Err(@hal.EcError::NotSupported(message)) else {
    fail("expected linux placeholder to raise NotSupported")
  }
  assert_true(message.contains("Linux Raw Socket"))
}
