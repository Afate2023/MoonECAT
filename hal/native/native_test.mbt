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
  let version = native_stub_version()
  assert_true(version == 0 || version == 1)
  let _ = windows_npcap_runtime_available()
  let _ = linux_raw_socket_runtime_available()
}

///|
test "native scaffold exposes interface listing entry" {
  let _ : Result[String, Error] = try? windows_npcap_list_interfaces_text()
  let _ : Result[String, Error] = try? windows_npcap_list_interfaces_json()
  let _ : Result[String, Error] = try? linux_raw_socket_list_interfaces_text()
  let _ : Result[String, Error] = try? linux_raw_socket_list_interfaces_json()
  let _ : Result[String, Error] = try? native_list_interfaces_json(Auto)
}

///|
test "native scaffold keeps unavailable linux backend explicit" {
  if linux_raw_socket_runtime_available() {
    assert_true(native_backend_available(LinuxRawSocket))
    return
  }
  let result : Result[NativeNic, Error] = try? NativeNic::open_with_config(
    default_linux_config("eth0"),
  )
  guard result is Err(@hal.EcError::NotSupported(message)) else {
    fail("expected unavailable linux backend to raise NotSupported")
  }
  assert_true(
    message.contains("Linux Raw Socket backend") ||
    message.contains("native backend is not available"),
  )
}
