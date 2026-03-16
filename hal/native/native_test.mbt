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
test "native interface listing parses metadata and probe candidates" {
  let listing = parse_native_interface_listing(
    Json::object({
      "backend": Json::string("native-windows-npcap"),
      "interfaces": Json::array([
        Json::object({
          "name": Json::string("ethercat0"),
          "description": Json::string("Ethernet"),
          "loopback": Json::boolean(false),
          "up": Json::boolean(true),
          "connected": Json::boolean(true),
          "wireless": Json::boolean(false),
        }),
        Json::object({
          "name": Json::string("wifi0"),
          "description": Json::string("Wi-Fi"),
          "loopback": Json::boolean(false),
          "up": Json::boolean(true),
          "connected": Json::boolean(true),
          "wireless": Json::boolean(true),
        }),
        Json::object({
          "name": Json::string("loop"),
          "loopback": Json::boolean(true),
          "up": Json::boolean(true),
          "connected": Json::boolean(true),
          "wireless": Json::boolean(false),
        }),
      ]),
    }),
  )
  assert_eq(listing.backend, WindowsNpcap)
  assert_eq(listing.interfaces.length(), 3)
  let candidates = native_interface_probe_candidates(listing)
  assert_eq(candidates.length(), 1)
  assert_eq(candidates[0].name, "ethercat0")
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
