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
  let preamble : @mailbox.SiiPreamble = {
    pdi_control: 0x0E80U,
    pdi_config: 0xEE44U,
    sync_impulse_length_raw: 0x0010U,
    pdi_config2: 0U,
    configured_station_alias: 0U,
    checksum: 0x00CBU,
    checksum_ok: true,
  }
  let standard : @mailbox.SiiStandardMetadata = {
    eeprom_size_raw: 15U,
    version: 1U,
  }
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
    soe_channels: b'\x01',
    ds402_channels: b'\x00',
    sysman_class: b'\x00',
    flags: b'\x0A',
    current_on_ebus: 14U,
    physical_port_0: b'\x01',
    physical_port_1: b'\x01',
    physical_port_2: b'\x00',
    physical_port_3: b'\x00',
    physical_memory_address: 0U,
  })
  let json = read_sii_json(
    0U,
    128,
    preamble,
    standard,
    header,
    general,
    ["SlaveName"],
    [@mailbox.FmmuDirection::Outputs],
    [
      {
        physical_start: 0x1000U,
        length: 256U,
        control: b'\x26',
        status: b'\x00',
        enable: true,
        sm_type: @mailbox.SmType::MailboxOut,
      },
    ],
    [
      {
        cycle_time_0: 0U,
        shift_time_0: 0U,
        shift_time_1: 0U,
        sync1_cycle_factor: 0,
        assign_activate: 0x0300U,
        sync0_cycle_factor: 0,
        name_idx: b'\x01',
        description_idx: b'\x01',
      },
    ],
    [
      {
        pdo_index: 0x1A00U,
        entry_count: b'\x01',
        sync_manager: b'\x03',
        synchronization: b'\x00',
        name_idx: b'\x01',
        flags: 0U,
        entries: [
          {
            entry_index: 0x6000U,
            subindex: b'\x01',
            name_idx: b'\x01',
            data_type: b'\x05',
            bit_length: b'\x10',
            flags: 0U,
          },
        ],
      },
    ],
    [],
    [{ category: @mailbox.General, data: Bytes::new(32) }],
  )
  let text = json.stringify(indent=2)
  assert_true(text.contains("\"vendor_id\": 1"))
  assert_true(text.contains("\"preamble\""))
  assert_true(text.contains("\"dc_clocks\""))
  assert_true(text.contains("\"tx_pdo\""))
  assert_true(text.contains("\"strings\""))
  assert_true(text.contains("\"categories\""))
}
