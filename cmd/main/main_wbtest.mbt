///|
test "cli parse_backend supports explicit native backends" {
  assert_eq(
    parse_backend(["moonecat", "list-if", "--backend", "native-windows-npcap"]),
    NativeWindowsNpcap,
  )
  assert_eq(
    parse_backend(["moonecat", "list-if", "--backend", "native-linux-raw"]),
    NativeLinuxRaw,
  )
}

///|
test "cli parse_backend defaults to mock and native" {
  assert_eq(parse_backend(["moonecat", "scan"]), Mock)
  assert_eq(
    parse_backend(["moonecat", "scan", "--backend", "native"]),
    NativeAuto,
  )
}

///|
test "cli require_interface_name validates flag presence" {
  assert_eq(
    require_interface_name(["moonecat", "scan", "--if", "eth0"]),
    "eth0",
  )
  let result : Result[String, Error] = try? require_interface_name([
    "moonecat", "scan",
  ])
  assert_true(result is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli numeric flag parsers accept valid integers" {
  assert_eq(parse_uint_flag("--position", "12"), 12U)
  assert_eq(parse_int_flag("--words", "128"), 128)
}

///|
test "cli numeric flag parsers reject invalid integers" {
  let bad_uint : Result[UInt, Error] = try? parse_uint_flag("--position", "1a")
  let bad_int : Result[Int, Error] = try? parse_int_flag("--words", "")
  assert_true(bad_uint is Err(@hal.EcError::ConfigMismatch(_)))
  assert_true(bad_int is Err(@hal.EcError::ConfigMismatch(_)))
}

///|
test "cli native backend mapping stays stable" {
  assert_eq(cli_backend_to_native_backend(NativeAuto), @native.Auto)
  assert_eq(
    cli_backend_to_native_backend(NativeWindowsNpcap),
    @native.WindowsNpcap,
  )
  assert_eq(
    cli_backend_to_native_backend(NativeLinuxRaw),
    @native.LinuxRawSocket,
  )
}

///|
test "cli run helper reopens nic for run path" {
  let result : Result[Unit, Error] = try? run_mock_command_with_fresh_nic(
    true,
    @hal.Duration(1000L),
  )
  assert_true(result is Ok(_))
}

///|
test "cli read_sii_json includes header and categories" {
  let header : @mailbox.SiiData = {
    vendor_id: 1U,
    product_code: 2U,
    revision: 3U,
    serial: 4U,
    bootstrap_rx_offset: 5U,
    bootstrap_rx_size: 6U,
    bootstrap_tx_offset: 7U,
    bootstrap_tx_size: 8U,
    mailbox_rx_offset: 9U,
    mailbox_rx_size: 10U,
    mailbox_tx_offset: 11U,
    mailbox_tx_size: 12U,
    mailbox_protocols: 13U,
  }
  let general : @mailbox.SiiGeneral? = Some({
    group_idx: b'\x01',
    image_idx: b'\x02',
    order_idx: b'\x03',
    name_idx: b'\x04',
    coe_details: b'\x05',
    foe_supported: true,
    eoe_supported: false,
    soe_supported: true,
    flags: b'\x0A',
    current_on_ebus: 14U,
  })
  let json = read_sii_json(0U, 128, header, general, ["SlaveName"], [
    { category: @mailbox.General, data: Bytes::new(16) },
  ])
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"vendor_id\": 1"))
  assert_true(text.contains("\"strings\""))
  assert_true(text.contains("\"categories\""))
}
