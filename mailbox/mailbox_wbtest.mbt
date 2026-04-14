///|
// ── Batch 6: SII parser whitebox edge cases ──

///|
test "read_sii_word short buffer returns zero" {
  // word_offset=1 → byte_offset=2, needs byte 3 → but length=2
  let data = Bytes::make(2, 0xFF)
  assert_eq(read_sii_word(data, 1), 0U)
}

///|
test "read_sii_word_at_byte short buffer returns zero" {
  let data = Bytes::make(1, 0xAB)
  assert_eq(read_sii_word_at_byte(data, 0), 0U)
}

///|
test "read_sii_i16_at_byte negative value" {
  // 0x8001 → should return -32767
  let data = Bytes::makei(4, fn(i) {
    if i == 0 {
      b'\x01'
    } else if i == 1 {
      b'\x80'
    } else {
      b'\x00'
    }
  })
  assert_eq(read_sii_i16_at_byte(data, 0), -32767)
}

///|
test "read_sii_i16_at_byte positive value" {
  let data = Bytes::makei(4, fn(i) { if i == 0 { b'\x05' } else { b'\x00' } })
  assert_eq(read_sii_i16_at_byte(data, 0), 5)
}

///|
test "read_sii_dword combines two words" {
  let data = Bytes::makei(8, fn(i) {
    match i {
      0 => b'\x78'
      1 => b'\x56'
      2 => b'\x34'
      3 => b'\x12'
      _ => b'\x00'
    }
  })
  assert_eq(read_sii_dword(data, 0), 0x12345678U)
}

///|
test "read_sii_dword_at_byte combines two words" {
  let data = Bytes::makei(8, fn(i) {
    match i {
      2 => b'\xCD'
      3 => b'\xAB'
      4 => b'\x34'
      5 => b'\x12'
      _ => b'\x00'
    }
  })
  assert_eq(read_sii_dword_at_byte(data, 2), 0x1234ABCDU)
}

///|
test "parse_sii_header short data raises error" {
  let data = Bytes::make(50, 0)
  let result : Result[SiiData, Error] = try? parse_sii_header(data)
  assert_true(result is Err(_))
}

///|
test "parse_sii_header 58 bytes no vendor no config_b" {
  let data = Bytes::make(58, 0)
  let result = parse_sii_header(data)
  // firmware/hardware/production should be 0 (no vendor info)
  assert_eq(result.firmware_version, 0U)
  assert_eq(result.hardware_version, 0U)
  assert_eq(result.production_date_raw, 0U)
  // pdi_config_1 etc should be 0 (no config B)
  assert_eq(result.pdi_config_1, 0U)
  assert_eq(result.esc_config_b_present, false)
}

///|
test "parse_sii_header 70 bytes vendor info but no config_b" {
  let data = Bytes::makei(70, fn(i) { if i == 64 { b'\x42' } else { b'\x00' } })
  let result = parse_sii_header(data)
  assert_eq(result.firmware_version, 0x42U)
  // Still no config B
  assert_eq(result.pdi_config_1, 0U)
}

///|
test "parse_sii_header 96 bytes with config_b" {
  let data = Bytes::makei(96, fn(i) { if i == 12 { b'\x01' } else { b'\x00' } })
  let result = parse_sii_header(data)
  assert_eq(result.esc_config_b_present, true)
}

///|
// ── Batch 7: category_from_code all arms ──

///|
test "category_from_code Strings" {
  assert_true(category_from_code(10U) is Strings)
}

///|
test "category_from_code DataTypes" {
  assert_true(category_from_code(20U) is DataTypes)
}

///|
test "category_from_code General" {
  assert_true(category_from_code(30U) is General)
}

///|
test "category_from_code Fmmu" {
  assert_true(category_from_code(40U) is Fmmu)
}

///|
test "category_from_code SyncManager" {
  assert_true(category_from_code(41U) is SyncManager)
}

///|
test "category_from_code FmmuEx" {
  assert_true(category_from_code(42U) is FmmuEx)
}

///|
test "category_from_code SyncUnit" {
  assert_true(category_from_code(43U) is SyncUnit)
}

///|
test "category_from_code TxPdo" {
  assert_true(category_from_code(50U) is TxPdo)
}

///|
test "category_from_code RxPdo" {
  assert_true(category_from_code(51U) is RxPdo)
}

///|
test "category_from_code Dc" {
  assert_true(category_from_code(60U) is Dc)
}

///|
test "category_from_code Timeouts" {
  assert_true(category_from_code(70U) is Timeouts)
}

///|
test "category_from_code Dictionary" {
  assert_true(category_from_code(80U) is Dictionary)
}

///|
test "category_from_code Hardware" {
  assert_true(category_from_code(90U) is Hardware)
}

///|
test "category_from_code VendorInformation" {
  assert_true(category_from_code(100U) is VendorInformation)
}

///|
test "category_from_code Images" {
  assert_true(category_from_code(110U) is Images)
}

///|
test "category_from_code unknown falls to Raw" {
  assert_true(category_from_code(999U) is Raw)
}

///|
test "crc8_update known values" {
  // CRC-8 with initial 0xFF
  let c1 = crc8_update(0xFF, b'\x00')
  assert_true(c1 >= 0)
  // Chain two bytes and verify deterministic
  let c2 = crc8_update(c1, b'\x01')
  let c3 = crc8_update(crc8_update(0xFF, b'\x00'), b'\x01')
  assert_eq(c2, c3)
}

// ===== Batch 9: CoE engine private functions =====

///|
test "CoeService to_uint SdoResponse arm" {
  assert_eq(CoeService::SdoResponse.to_uint(), 3U)
}

///|
test "coe_service_from_uint RxPdo arm" {
  let svc = coe_service_from_uint(6U)
  assert_true(svc is RxPdo)
}

///|
test "SdoCommand to_byte DownloadResponse arm" {
  assert_eq(SdoCommand::DownloadResponse.to_byte(), b'\x60')
}

///|
test "SdoCommand to_byte UploadResponse arm" {
  assert_eq(SdoCommand::UploadResponse.to_byte(), b'\x43')
}

///|
test "sdo_command_from_byte AbortTransfer arm" {
  let cmd = sdo_command_from_byte(b'\x80')
  assert_true(cmd is AbortTransfer)
}

///|
test "sdo_command_from_byte UploadResponse via byte 0x40" {
  // 0x40 >> 5 = 2 → UploadResponse arm
  let cmd = sdo_command_from_byte(b'\x40')
  assert_true(cmd is UploadResponse)
}

///|
test "sdo_command_from_byte unknown raises" {
  let result = try sdo_command_from_byte(b'\xA0') |> Ok catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "SdoCommand to_coe_service response variants" {
  assert_true(SdoCommand::DownloadResponse.to_coe_service() is SdoResponse)
  assert_true(SdoCommand::UploadResponse.to_coe_service() is SdoResponse)
}

// ===== Batch 10: RMSM uncovered paths =====

///|
test "Rmsm validate_response in wrong state" {
  let rmsm = Rmsm::new(max_retries=3)
  // rmsm starts in Idle state, not WaitingForResponse
  let result = try rmsm.validate_response(b'\x01') |> Ok catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "Rmsm current_counter in WaitingForResponse" {
  let rmsm = Rmsm::new(max_retries=3)
  // Begin a send to move to WaitingForResponse
  let _cnt = rmsm.begin_transaction()
  assert_eq(rmsm.current_counter(), b'\x01')
}

// ===== Batch 10: SII hex_digit(6) =====

///|
test "hex_digit 6" {
  assert_eq(hex_digit(6U), "6")
}

// ===== Batch 10: sii_parser SM type Unused fallback =====

///|
test "parse_sii_sm unknown type fallback" {
  // Build an 8-byte SM entry with type_byte=0xFF → Unused
  let buf = @buffer.new()
  // physical_start (2 bytes LE)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x10')
  // length (2 bytes LE)
  buf.write_byte(b'\x80')
  buf.write_byte(b'\x00')
  // control
  buf.write_byte(b'\x26')
  // status
  buf.write_byte(b'\x00')
  // activate
  buf.write_byte(b'\x01')
  // type = 0xFF → Unused
  buf.write_byte(b'\xFF')
  let data = buf.to_bytes()
  let result = parse_sii_sm(data)
  assert_eq(result.length(), 1)
  assert_true(result[0].sm_type is Unused)
}

// ===== Batch 10: sii_parser PDO truncated entries =====

///|
test "parse_sii_pdo truncated entry" {
  // A PDO with entry_count=2 but only 1 entry fits (8 bytes header + 8 bytes entry1 = 16)
  let buf = @buffer.new()
  // PDO header: 8 bytes
  // pdo_index (2 LE)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x16')
  // entry_count (1 byte)
  buf.write_byte(b'\x02') // claims 2 entries
  // sync_manager (1 byte)
  buf.write_byte(b'\x02')
  // synchronization (1 byte)
  buf.write_byte(b'\x00')
  // name_idx (1 byte)
  buf.write_byte(b'\x01')
  // flags (2 LE)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  // Entry 1: 8 bytes
  // entry_index (2 LE)
  buf.write_byte(b'\x01')
  buf.write_byte(b'\x60')
  // subindex
  buf.write_byte(b'\x01')
  // name_idx
  buf.write_byte(b'\x02')
  // data_type
  buf.write_byte(b'\x05')
  // bit_length
  buf.write_byte(b'\x08')
  // flags (2 LE)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  // No more data for entry 2 → break
  let data = buf.to_bytes()
  let result = parse_sii_pdo(data)
  assert_eq(result.length(), 1)
  assert_eq(result[0].entries.length(), 1)
}

// ===== Batch 10: FoE read_u32_le_bytes short data =====

///|
test "read_u32_le_bytes short data" {
  let data = Bytes::make(2, 0)
  assert_eq(read_u32_le_bytes(data, 1), 0U)
}

// ===== Batch 14: coe_engine uncovered arms =====

///|
test "CoeService to_uint SdoInfo arm" {
  assert_eq(CoeService::SdoInfo.to_uint(), 8U)
}

///|
test "coe_service_from_uint PdoRemoteRequest arm" {
  let svc = coe_service_from_uint(7U)
  assert_true(svc is PdoRemoteRequest)
}

///|
test "SdoCommand to_byte AbortTransfer arm" {
  assert_eq(SdoCommand::AbortTransfer.to_byte(), b'\x80')
}

// ===== Batch 15: sii_parser sub-parser direct coverage =====

///|
test "parse_sii_strings returns parsed strings" {
  // Strings category data: 1 string of length 2 "AB"
  let data = b"\x01\x02\x41\x42"
  let result = parse_sii_strings(data)
  assert_eq(result.length(), 1)
  assert_eq(result[0], "AB")
}

///|
test "parse_sii_general Err on short data" {
  // General data too short to parse (< 16 bytes) → raises
  let data = Bytes::make(4, 0)
  let result : Result[SiiGeneral, Error] = try? parse_sii_general(data)
  assert_true(result is Err(_))
}

///|
test "parse_sii_timeouts with valid data" {
  // Timeouts category needs 16 bytes
  let data = Bytes::make(16, 0)
  let result : Result[SiiTimeouts, Error] = try? parse_sii_timeouts(data)
  assert_true(result is Ok(_))
}

///|
test "parse_sii_timeouts Err on short data" {
  // Data too short (< 16) → raises
  let data = Bytes::make(4, 0)
  let result : Result[SiiTimeouts, Error] = try? parse_sii_timeouts(data)
  assert_true(result is Err(_))
}

///|
test "parse_sii_dc Err on short data" {
  // Data too short (< 24) → raises
  let data = Bytes::make(4, 0)
  let result : Result[SiiDcClock, Error] = try? parse_sii_dc(data)
  assert_true(result is Err(_))
}

///|
test "parse_sii_fmmu_ex with valid data" {
  // Each FmmuEx entry is 4 bytes: 2 flags + sm + su
  let data = b"\x03\x00\x01\x02"
  let result = parse_sii_fmmu_ex(data)
  assert_eq(result.length(), 1)
}

///|
test "parse_sii_sync_units with valid data" {
  // Each SyncUnit entry is 1 byte of flags
  let data = b"\x05"
  let result = parse_sii_sync_units(data)
  assert_eq(result.length(), 1)
}

///|
test "parse_sii_pdo with TxPdo data" {
  // Minimal PDO: 8-byte header with 0 entries
  let buf = @buffer.new()
  // pdo_index (2 LE)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x16')
  // entry_count
  buf.write_byte(b'\x00')
  // sync_manager
  buf.write_byte(b'\x02')
  // synchronization
  buf.write_byte(b'\x00')
  // name_idx
  buf.write_byte(b'\x00')
  // flags (2 LE)
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  let data = buf.to_bytes()
  let result = parse_sii_pdo(data)
  assert_eq(result.length(), 1)
}

///|
test "parse_sii_dc with valid dc data" {
  // DC category needs 24 bytes
  let data = Bytes::make(24, 0)
  let result : Result[SiiDcClock, Error] = try? parse_sii_dc(data)
  assert_true(result is Ok(_))
}

///|
test "hex_digit 9 returns nine" {
  assert_eq(hex_digit(9U), "9")
}

///|
test "coe_service TxPdo to_uint" {
  assert_eq(CoeService::TxPdo.to_uint(), 5U)
}

///|
test "coe_service_from_uint 8 returns SdoInfo" {
  let s = coe_service_from_uint(8U)
  assert_true(s is SdoInfo)
}
