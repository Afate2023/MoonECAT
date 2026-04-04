///|
test "decode_dl_error_counters parses crafted register data" {
  // RX Error Counters: 0x0300–0x0307 (8 bytes: frame+physical per port)
  // Port 0: frame=10, physical=5
  // Port 1: frame=20, physical=15
  // Port 2: frame=0, physical=0
  // Port 3: frame=255, physical=128
  let rx_data = Bytes::from_array([10, 5, 20, 15, 0, 0, 255, 128])
  // Forwarded RX Error + EPU + PDI: 0x0308–0x030D (6 bytes)
  // Fwd Port 0=3, Port 1=7, Port 2=0, Port 3=1, EPU=42, PDI=99
  let fwd_data = Bytes::from_array([3, 7, 0, 1, 42, 99])
  // Lost Link Counters: 0x0310–0x0313 (4 bytes)
  // Port 0=11, Port 1=22, Port 2=0, Port 3=33
  let lost_data = Bytes::from_array([11, 22, 0, 33])
  let counters = decode_dl_error_counters(rx_data, fwd_data, lost_data)
  // Port 0
  assert_eq(counters.ports[0].frame_errors, 10U)
  assert_eq(counters.ports[0].physical_errors, 5U)
  assert_eq(counters.ports[0].forwarded_rx_errors, 3U)
  assert_eq(counters.ports[0].lost_link_count, 11U)
  // Port 1
  assert_eq(counters.ports[1].frame_errors, 20U)
  assert_eq(counters.ports[1].physical_errors, 15U)
  assert_eq(counters.ports[1].forwarded_rx_errors, 7U)
  assert_eq(counters.ports[1].lost_link_count, 22U)
  // Port 2
  assert_eq(counters.ports[2].frame_errors, 0U)
  assert_eq(counters.ports[2].physical_errors, 0U)
  assert_eq(counters.ports[2].forwarded_rx_errors, 0U)
  assert_eq(counters.ports[2].lost_link_count, 0U)
  // Port 3
  assert_eq(counters.ports[3].frame_errors, 255U)
  assert_eq(counters.ports[3].physical_errors, 128U)
  assert_eq(counters.ports[3].forwarded_rx_errors, 1U)
  assert_eq(counters.ports[3].lost_link_count, 33U)
  // Global counters
  assert_eq(counters.ecat_pu_errors, 42U)
  assert_eq(counters.pdi_errors, 99U)
}

///|
test "decode_dl_error_counters handles short data gracefully" {
  // Short/empty data should produce zero counters
  let counters = decode_dl_error_counters(
    Bytes::new(0),
    Bytes::new(0),
    Bytes::new(0),
  )
  for i = 0; i < 4; i = i + 1 {
    assert_eq(counters.ports[i].frame_errors, 0U)
    assert_eq(counters.ports[i].physical_errors, 0U)
    assert_eq(counters.ports[i].forwarded_rx_errors, 0U)
    assert_eq(counters.ports[i].lost_link_count, 0U)
  }
  assert_eq(counters.ecat_pu_errors, 0U)
  assert_eq(counters.pdi_errors, 0U)
}

///|
test "decode_dl_error_counters saturated counters at 0xFF" {
  // All counters at maximum (0xFF = 255, saturation point per ETG.1000.4)
  let rx_data = Bytes::from_array([255, 255, 255, 255, 255, 255, 255, 255])
  let fwd_data = Bytes::from_array([255, 255, 255, 255, 255, 255])
  let lost_data = Bytes::from_array([255, 255, 255, 255])
  let counters = decode_dl_error_counters(rx_data, fwd_data, lost_data)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(counters.ports[i].frame_errors, 255U)
    assert_eq(counters.ports[i].physical_errors, 255U)
    assert_eq(counters.ports[i].forwarded_rx_errors, 255U)
    assert_eq(counters.ports[i].lost_link_count, 255U)
  }
  assert_eq(counters.ecat_pu_errors, 255U)
  assert_eq(counters.pdi_errors, 255U)
}

// ===== Coverage: protocol/dc.mbt — pure helper functions =====

///|
test "le_u32 decodes little-endian 4 bytes" {
  let data = Bytes::from_array([b'\x78', b'\x56', b'\x34', b'\x12'])
  assert_eq(le_u32(data), 0x12345678U)
}

///|
test "le_u32 with short data returns 0" {
  assert_eq(le_u32(Bytes::new(2)), 0U)
}

///|
test "write_u32 encodes little-endian 4 bytes" {
  let data = write_u32(0xDEADBEEFU)
  assert_eq(data[0], b'\xEF')
  assert_eq(data[1], b'\xBE')
  assert_eq(data[2], b'\xAD')
  assert_eq(data[3], b'\xDE')
}

///|
test "le_u64 decodes little-endian 8 bytes" {
  let data = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08',
  ])
  assert_eq(le_u64(data), 0x0807060504030201UL)
}

///|
test "le_u64 with short data returns 0" {
  assert_eq(le_u64(Bytes::new(4)), 0UL)
}

///|
test "write_u64 encodes little-endian 8 bytes" {
  let data = write_u64(0x0102030405060708UL)
  assert_eq(data[0], b'\x08')
  assert_eq(data[7], b'\x01')
}

///|
test "write_i64_from_i32 positive value" {
  let data = write_i64_from_i32(256)
  // Low 4 bytes = 256 LE
  assert_eq(data[0], b'\x00')
  assert_eq(data[1], b'\x01')
  assert_eq(data[2], b'\x00')
  assert_eq(data[3], b'\x00')
  // High 4 bytes = 0 (positive)
  assert_eq(data[4], b'\x00')
  assert_eq(data[7], b'\x00')
}

///|
test "write_i64_from_i32 negative value" {
  let data = write_i64_from_i32(-1)
  // Low 4 bytes = 0xFFFFFFFF LE
  assert_eq(data[0], b'\xFF')
  assert_eq(data[3], b'\xFF')
  // High 4 bytes = 0xFFFFFFFF (sign extension)
  assert_eq(data[4], b'\xFF')
  assert_eq(data[7], b'\xFF')
}

///|
test "abs_diff_u32 a > b" {
  assert_eq(abs_diff_u32(10U, 3U), 7U)
}

///|
test "abs_diff_u32 b > a" {
  assert_eq(abs_diff_u32(3U, 10U), 7U)
}

///|
test "abs_diff_u32 equal" {
  assert_eq(abs_diff_u32(5U, 5U), 0U)
}

// ===== Coverage: protocol/transact.mbt — should_ignore_rx_decode_error =====

///|
test "should_ignore_rx_decode_error with frame too short" {
  assert_true(
    should_ignore_rx_decode_error(
      @hal.EcError::InvalidFrame("frame too short: 4"),
    ),
  )
}

///|
test "should_ignore_rx_decode_error with wrong ethertype" {
  assert_true(
    should_ignore_rx_decode_error(
      @hal.EcError::InvalidFrame("wrong ethertype: 0x800"),
    ),
  )
}

///|
test "should_ignore_rx_decode_error with wrong ecat type" {
  assert_true(
    should_ignore_rx_decode_error(
      @hal.EcError::InvalidFrame("wrong ecat type: 2"),
    ),
  )
}

///|
test "should_ignore_rx_decode_error with other InvalidFrame is false" {
  assert_eq(
    should_ignore_rx_decode_error(
      @hal.EcError::InvalidFrame("PDU header truncated"),
    ),
    false,
  )
}

///|
test "should_ignore_rx_decode_error with non-frame error is false" {
  assert_eq(should_ignore_rx_decode_error(@hal.EcError::RecvTimeout), false)
}

// ===== Coverage: protocol/esm_engine.mbt — decode_al_status_snapshot =====

///|
test "decode_al_status_snapshot no error" {
  let snap = decode_al_status_snapshot(b'\x02', None)
  assert_eq(snap.state, EsmState::PreOp)
  assert_eq(snap.error_indication, false)
  assert_eq(snap.status_code, None)
}

///|
test "decode_al_status_snapshot with error bit" {
  let snap = decode_al_status_snapshot(b'\x14', Some(0x0011U))
  assert_eq(snap.state, EsmState::SafeOp)
  assert_eq(snap.error_indication, true)
  assert_eq(snap.status_code, Some(0x0011U))
}

///|
test "decode_al_status_snapshot error bit but no code strips code" {
  let snap = decode_al_status_snapshot(b'\x11', None)
  assert_eq(snap.state, EsmState::Init)
  assert_eq(snap.error_indication, true)
  assert_eq(snap.status_code, None)
}

// ===== Coverage: protocol/esm_engine.mbt — should_rollback_al_error_to_init =====

///|
test "should_rollback_al_error_to_init true for 0x0016" {
  assert_true(should_rollback_al_error_to_init(Some(0x0016U)))
}

///|
test "should_rollback_al_error_to_init true for 0x001D" {
  assert_true(should_rollback_al_error_to_init(Some(0x001DU)))
}

///|
test "should_rollback_al_error_to_init true for 0x001E" {
  assert_true(should_rollback_al_error_to_init(Some(0x001EU)))
}

///|
test "should_rollback_al_error_to_init true for 0x0070" {
  assert_true(should_rollback_al_error_to_init(Some(0x0070U)))
}

///|
test "should_rollback_al_error_to_init false for other code" {
  assert_eq(should_rollback_al_error_to_init(Some(0x0001U)), false)
}

///|
test "should_rollback_al_error_to_init false for None" {
  assert_eq(should_rollback_al_error_to_init(None), false)
}

// ===== Coverage: protocol/foe_transaction.mbt — foe_raise_error =====

///|
test "foe_raise_error with text" {
  let result = try? foe_raise_error(@mailbox.FoeErrorCode::NotDefined, "detail")
  assert_true(result is Err(_))
}

///|
test "foe_raise_error without text" {
  let result = try? foe_raise_error(@mailbox.FoeErrorCode::NotFound, "")
  assert_true(result is Err(_))
}

// ===== Coverage: protocol/zero_copy_codec.mbt — private helpers =====

///|
test "write_u16_le_fixed and read_u16_le_fixed roundtrip" {
  let buf : FixedArray[Byte] = FixedArray::make(4, b'\x00')
  write_u16_le_fixed(buf, 1, 0x1234U)
  assert_eq(buf[1], b'\x34')
  assert_eq(buf[2], b'\x12')
  assert_eq(read_u16_le_fixed(buf, 1), 0x1234U)
}

///|
test "write_u32_le_fixed encodes LE 4 bytes" {
  let buf : FixedArray[Byte] = FixedArray::make(6, b'\x00')
  write_u32_le_fixed(buf, 1, 0xDEADBEEFU)
  assert_eq(buf[1], b'\xEF')
  assert_eq(buf[2], b'\xBE')
  assert_eq(buf[3], b'\xAD')
  assert_eq(buf[4], b'\xDE')
  // Surrounding bytes unchanged
  assert_eq(buf[0], b'\x00')
  assert_eq(buf[5], b'\x00')
}

// ===== Coverage: protocol/codec.mbt — private helpers =====

///|
test "read_u16_le and read_u32_le" {
  let data = Bytes::from_array([
    b'\x34', b'\x12', b'\xEF', b'\xBE', b'\xAD', b'\xDE',
  ])
  assert_eq(read_u16_le(data, 0), 0x1234U)
  assert_eq(read_u32_le(data, 2), 0xDEADBEEFU)
}

///|
test "write_u16_le and write_u32_le" {
  let buf = @buffer.new()
  write_u16_le(buf, 0xABCDU)
  write_u32_le(buf, 0x12345678U)
  let out = buf.to_bytes()
  assert_eq(out[0], b'\xCD')
  assert_eq(out[1], b'\xAB')
  assert_eq(out[2], b'\x78')
  assert_eq(out[3], b'\x56')
  assert_eq(out[4], b'\x34')
  assert_eq(out[5], b'\x12')
}

///|
// ── Batch 6: request_state_poll_budget coverage ──

///|
test "request_state_poll_budget small timeout returns max_polls" {
  // Very large transport timeout → suggested_polls very small → returns request_state_max_polls (32)
  // Init default = 5_000_000_000L, transport = 5_000_000_000L → suggested = 1 ≤ 32 → 32
  let budget = request_state_poll_budget(Init, @hal.Duration(5_000_000_000L))
  assert_eq(budget, 32)
}

///|
test "request_state_poll_budget large timeout returns extended" {
  // Very small transport timeout → suggested_polls huge → returns extended max (4096)
  // SafeOp default = 10_000_000_000L, transport = 1L → suggested = 10B ≥ 4096 → 4096
  let budget = request_state_poll_budget(SafeOp, @hal.Duration(1L))
  assert_eq(budget, 4096)
}

///|
test "request_state_poll_budget zero timeout uses 1L floor" {
  // Zero transport → floored to 1L → suggested_polls overflows Int32 → clamped to max_polls (32)
  let budget = request_state_poll_budget(PreOp, @hal.Duration(0L))
  assert_eq(budget, 32)
}

///|
test "request_state_poll_budget middle range returns suggested" {
  // PreOp default = 3_000_000_000L, transport = 1_000_000L → suggested = 3000
  // 32 < 3000 < 4096 → returns 3000
  let budget = request_state_poll_budget(PreOp, @hal.Duration(1_000_000L))
  assert_eq(budget, 3000)
}
// ===== mailbox_transport: short SM window edge cases =====

///|
test "mailbox_status_from_sm_window short window returns false" {
  // window.length() <= sm_status_offset(5) → returns false
  let window = Bytes::make(3, b'\xFF')
  assert_eq(mailbox_status_from_sm_window(window), false)
}

///|
test "validate_input_mailbox_sm_window short window returns early" {
  // window.length() < sm_register_window_size(8) → returns without error
  let window = Bytes::make(4, b'\xFF')
  validate_input_mailbox_sm_window(window)
  // No exception raised = pass
}

///|
test "read_sm_window_activate_byte short window raises" {
  // window.length() <= sm_activate_offset(6) → raises error
  let window = Bytes::make(5, b'\x00')
  let result = try? read_sm_window_activate_byte(window)
  assert_true(result is Err(_))
}

///|
test "read_sm_window_pdi_control_byte short window raises" {
  // window.length() <= sm_pdi_control_offset(7) → raises error
  let window = Bytes::make(6, b'\x00')
  let result = try? read_sm_window_pdi_control_byte(window)
  assert_true(result is Err(_))
}

// ===== Batch 21: mailbox_transport — validate_input_mailbox_sm_window deactivated =====

///|
test "validate_input_mailbox_sm_window deactivated SM raises" {
  // 8-byte SM window: start=0x1000 length=0x0080 status=0x00 control=0x01 (bit 8 set = deactivated)
  // Bytes: [start_lo, start_hi, len_lo, len_hi, ctrl_lo, status, activate(ctrl_hi=0x01), pdi]
  // start=0x1000 → [0x00, 0x10], length=0x0080 → [0x80, 0x00]
  // control word at bytes 6-7: we need bit 8 of the 16-bit control_word set
  // control = read_u16_le(window, 6) → window[6] | (window[7] << 8)
  // deactivate_mask = 0x0100 → window[7] bit 0
  let window = Bytes::from_array([
    b'\x00', b'\x10', // start = 0x1000
     b'\x80', b'\x00', // length = 0x0080
     b'\x00', // control_lo (byte 4)
     b'\x00', // status (byte 5)
     b'\x00', b'\x01', // activate/pdi: control_word = 0x0100 (deactivated)
  ])
  let result = try? validate_input_mailbox_sm_window(window)
  assert_true(result is Err(_))
}

///|
test "validate_input_mailbox_sm_window repeat_request with zero start+length raises" {
  // start=0, length=0, repeat_request bit set (bit 1 of control lo = 0x02)
  let window = Bytes::from_array([
    b'\x00', b'\x00', // start = 0
     b'\x00', b'\x00', // length = 0
     b'\x00', // control_lo
     b'\x00', // status
     b'\x02', b'\x00', // control_word = 0x0002 (repeat_request)
  ])
  let result = try? validate_input_mailbox_sm_window(window)
  assert_true(result is Err(_))
}

///|
test "validate_input_mailbox_sm_window normal SM passes" {
  let window = Bytes::from_array([
    b'\x00', b'\x10', // start = 0x1000
     b'\x80', b'\x00', // length = 0x0080
     b'\x00', // control_lo
     b'\x08', // status (mailbox full)
     b'\x01', b'\x00', // control_word = 0x0001 (activate, not deactivated)
  ])
  validate_input_mailbox_sm_window(window) // should not raise
}
