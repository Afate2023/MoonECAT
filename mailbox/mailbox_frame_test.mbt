///|
test "mailbox header preserves six-bit channel" {
  let header : @mailbox.MailboxHeader = {
    length: 0U,
    address: 0x1001U,
    channel: b'\x2A',
    priority: b'\x03',
    mb_type: @mailbox.MailboxType::CoE,
    counter: b'\x05',
  }
  let encoded = header.to_bytes()
  @debug.assert_eq(encoded[4], b'\xEA')
  let decoded = @mailbox.MailboxHeader::from_bytes(encoded)
  @debug.assert_eq(decoded.channel, b'\x2A')
  @debug.assert_eq(decoded.priority, b'\x03')
}

///|
test "mailbox header rejects reserved counter bit" {
  let encoded = b"\x00\x00\x00\x00\x00\x80"
  let result = Result::Ok(@mailbox.MailboxHeader::from_bytes(encoded)) catch {
    error => Result::Err(error)
  }
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

///|
test "mailbox frame discards SyncManager padding" {
  let raw = b"\x04\x00\x00\x00\x00\x40\x01\x00\x02\x00\xC0\x00\x00\x4E"
  let frame = @mailbox.MailboxFrame::from_bytes(raw)
  @debug.assert_eq(frame.header.length, 4U)
  @debug.assert_eq(frame.header.counter, b'\x04')
  @debug.assert_eq(frame.payload, b"\x01\x00\x02\x00")
  @debug.assert_eq(frame.to_bytes().length(), 10)
}

///|
test "mailbox frame decodes unsupported protocol ERR" {
  // 04 00 00 00 00 40 is Length=4, Type=ERR, Cnt=4.
  // 01 00 02 00 is Mailbox Command / Unsupported Protocol.
  let raw = b"\x04\x00\x00\x00\x00\x40\x01\x00\x02\x00\xC0\x00\x00\x4E"
  let frame = @mailbox.MailboxFrame::from_bytes(raw)
  let mailbox_error = frame.decode_error()
  assert_true(
    mailbox_error.error_type is @mailbox.MailboxErrorType::MailboxCommand,
  )
  assert_true(
    mailbox_error.detail is @mailbox.MailboxErrorDetail::UnsupportedProtocol,
  )
  @debug.assert_eq(mailbox_error.detail.label(), "unsupported protocol")
}

///|
test "mailbox frame rejects declared payload truncation" {
  let raw = b"\x05\x00\x00\x00\x00\x13\x01\x02\x03\x04"
  let result = Result::Ok(@mailbox.MailboxFrame::from_bytes(raw)) catch {
    error => Result::Err(error)
  }
  assert_true(result is Err(@hal.EcError::MailboxProtocol(_)))
}

///|
test "mailbox frame encoding derives Length from payload" {
  let frame : @mailbox.MailboxFrame = {
    header: {
      length: 99U,
      address: 0U,
      channel: b'\x00',
      priority: b'\x00',
      mb_type: @mailbox.MailboxType::FoE,
      counter: b'\x01',
    },
    payload: b"\x03\x00",
  }
  let encoded = frame.to_bytes()
  @debug.assert_eq(encoded.length(), 8)
  @debug.assert_eq(encoded[0], b'\x02')
  @debug.assert_eq(encoded[1], b'\x00')
}

///|
test "SDO decoder reports generic mailbox ERR before CoE parsing" {
  let raw = b"\x04\x00\x00\x00\x00\x40\x01\x00\x02\x00\xC0\x00\x00\x4E"
  let result = Result::Ok(@mailbox.decode_sdo_response(raw)) catch {
    error => Result::Err(error)
  }
  assert_true(
    result
    is Err(
      @hal.EcError::MailboxProtocol(
        "mailbox error: unsupported protocol (type=1, detail=2)"
      )
    ),
  )
}

///|
test "all mailbox application decoders route generic ERR first" {
  let raw = b"\x04\x00\x00\x00\x00\x40\x01\x00\x02\x00\xC0\x00\x00\x4E"
  let eoe = Result::Ok(@mailbox.decode_eoe_response(raw)) catch {
    error => Result::Err(error)
  }
  let foe = Result::Ok(@mailbox.decode_foe_response(raw)) catch {
    error => Result::Err(error)
  }
  let soe = Result::Ok(@mailbox.decode_soe_response(raw)) catch {
    error => Result::Err(error)
  }
  let emergency = Result::Ok(@mailbox.decode_emergency_frame(raw)) catch {
    error => Result::Err(error)
  }
  let sdo_info = Result::Ok(@mailbox.decode_sdo_info_response(raw)) catch {
    error => Result::Err(error)
  }
  assert_true(
    eoe
    is Err(
      @hal.EcError::MailboxProtocol(
        "mailbox error: unsupported protocol (type=1, detail=2)"
      )
    ),
  )
  assert_true(
    foe
    is Err(
      @hal.EcError::MailboxProtocol(
        "mailbox error: unsupported protocol (type=1, detail=2)"
      )
    ),
  )
  assert_true(
    soe
    is Err(
      @hal.EcError::MailboxProtocol(
        "mailbox error: unsupported protocol (type=1, detail=2)"
      )
    ),
  )
  assert_true(
    emergency
    is Err(
      @hal.EcError::MailboxProtocol(
        "mailbox error: unsupported protocol (type=1, detail=2)"
      )
    ),
  )
  assert_true(
    sdo_info
    is Err(
      @hal.EcError::MailboxProtocol(
        "mailbox error: unsupported protocol (type=1, detail=2)"
      )
    ),
  )
}

///|
test "EoE decoder excludes physical mailbox padding" {
  let raw = b"\x04\x00\x00\x00\x00\x12\x00\x01\x00\x00\xAA\xBB"
  let response = @mailbox.decode_eoe_response(raw)
  assert_true(response is @mailbox.EoeResponse::EoeFragment(data=b"", ..))
}

///|
test "SoE decoder excludes physical mailbox padding" {
  let raw = b"\x04\x00\x00\x00\x00\x15\x02\x40\x15\x00\xAA\xBB"
  let response = @mailbox.decode_soe_response(raw)
  assert_true(response is @mailbox.SoeResponse::SoeReadData(data=b"", ..))
}

///|
test "CoE service values match ETG wire encoding" {
  @debug.assert_eq(@mailbox.CoeService::Emergency.to_uint(), 1U)
  @debug.assert_eq(@mailbox.CoeService::SdoRequest.to_uint(), 2U)
  @debug.assert_eq(@mailbox.CoeService::SdoResponse.to_uint(), 3U)
  @debug.assert_eq(@mailbox.CoeService::TxPdo.to_uint(), 4U)
  @debug.assert_eq(@mailbox.CoeService::RxPdo.to_uint(), 5U)
  @debug.assert_eq(@mailbox.CoeService::TxPdoRemoteRequest.to_uint(), 6U)
  @debug.assert_eq(@mailbox.CoeService::RxPdoRemoteRequest.to_uint(), 7U)
  @debug.assert_eq(@mailbox.CoeService::SdoInfo.to_uint(), 8U)
  assert_true(@mailbox.CoeService::from_uint(4U) is @mailbox.CoeService::TxPdo)
  assert_true(
    @mailbox.CoeService::from_uint(6U)
    is @mailbox.CoeService::TxPdoRemoteRequest,
  )
  assert_true(
    @mailbox.CoeService::from_uint(7U)
    is @mailbox.CoeService::RxPdoRemoteRequest,
  )
}

///|
test "MailboxSession names the MainDevice-side tracker" {
  let session = @mailbox.MailboxSession::new()
  let tx_counter = session.begin_transaction()
  assert_true(tx_counter >= b'\x01' && tx_counter <= b'\x07')
}
