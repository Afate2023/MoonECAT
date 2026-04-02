///|
test "Scenario: basic evaluation - all match" {
  let s = @mock.Scenario::new(
    "test_timeout_scenario",
    description="Test recv timeout at cycle 10",
  )
  s.add_rule(@mock.FaultRule::new(@mock.RecvTimeout, @mock.AtCycle(10)))
  s.expect(10L, @runtime.Warn("timeout"))
  let observed : Array[@mock.ObservedVerdict] = [
    { cycle: 10L, verdict: @runtime.Warn("consecutive timeouts 1") },
  ]
  let result = s.evaluate(observed, @runtime.Pass, 20L, "normal")
  inspect(result.passed, content="true")
  inspect(result.name, content="test_timeout_scenario")
}

///|
test "Scenario: graceful stop within N cycles" {
  let s = @mock.Scenario::new(
    "graceful_stop",
    pass_condition=@mock.GracefulStopWithin(5),
  )
  let observed : Array[@mock.ObservedVerdict] = [
    { cycle: 50L, verdict: @runtime.Fail("wkc mismatch") },
  ]
  // Total cycles = 54, fail at 50, so 4 cycles remaining (< 5)
  let result = s.evaluate(observed, @runtime.Fail("wkc mismatch"), 54L, "fault")
  inspect(result.passed, content="true")
  // Too many cycles remaining
  let result2 = s.evaluate(
    observed,
    @runtime.Fail("wkc mismatch"),
    60L,
    "fault",
  )
  inspect(result2.passed, content="false")
}

///|
test "Scenario: build injector from rules" {
  let s = @mock.Scenario::new("injector_test")
  s.add_rule(@mock.FaultRule::new(@mock.RecvTimeout, @mock.Once))
  s.add_rule(@mock.FaultRule::new(@mock.SendFailure("test"), @mock.Always))
  let inj = s.build_injector()
  // Should have 2 rules
  inspect(inj.rules.length(), content="2")
}

///|
test "NicEventLog NDJSON roundtrip" {
  let log = @mock.NicEventLog::new()
  log.append(@mock.Sent(Bytes::make(4, b'\xAA'), 4))
  log.append(@mock.Received(Bytes::make(3, b'\xBB')))
  log.append(@mock.RecvTimeout)
  log.append(@mock.SendFailed("test error"))
  let ndjson = log.to_ndjson()
  let restored = @mock.NicEventLog::from_ndjson(ndjson)
  inspect(restored.len(), content="4")
  // Verify event types
  inspect(restored.events[0] is @mock.Sent(_, _), content="true")
  inspect(restored.events[1] is @mock.Received(_), content="true")
  inspect(restored.events[2] is @mock.RecvTimeout, content="true")
  inspect(restored.events[3] is @mock.SendFailed(_), content="true")
}

///|
test "NicEventLog NDJSON with header" {
  let log = @mock.NicEventLog::new()
  log.append(@mock.RecvTimeout)
  let ndjson = log.to_ndjson_with_header(slave_count=2, fingerprint="abc123")
  // First line should be header, second should be the event
  let lines = ndjson.split("\n").collect()
  inspect(lines.length(), content="2")
  // Header should contain version
  inspect(lines[0].contains("\"header\":true"), content="true")
  // Roundtrip: from_ndjson should skip header
  let restored = @mock.NicEventLog::from_ndjson(ndjson)
  inspect(restored.len(), content="1")
}

///|
test "VirtualMailbox SDO upload" {
  let mbx = @mock.VirtualMailbox::new()
  mbx.add_od(0x1018U, b'\x01', Bytes::make(4, b'\x42'))
  let response = mbx.handle_sdo_upload(0x1018U, b'\x01')
  inspect(response is None, content="false")
}

///|
test "VirtualMailbox SDO download" {
  let mbx = @mock.VirtualMailbox::new()
  mbx.add_od(0x6000U, b'\x00', Bytes::make(2, b'\x00'), access=@mock.ReadWrite)
  let response = mbx.handle_sdo_download(
    0x6000U,
    b'\x00',
    Bytes::make(2, b'\xFF'),
  )
  inspect(response.length() > 0, content="true")
  // Verify data was updated
  let entry = mbx.find_od(0x6000U, b'\x00')
  inspect(entry is None, content="false")
}

///|
test "VirtualMailbox SDO abort on missing entry" {
  let mbx = @mock.VirtualMailbox::new()
  let response = mbx.handle_sdo_upload(0xFFFFU, b'\x00')
  // Should return an abort frame
  inspect(response is None, content="false")
}

///|
test "VirtualMailbox emergency emission" {
  let mbx = @mock.VirtualMailbox::new()
  mbx.add_emergency(0x1000U, b'\x01', at_cycle=5L)
  // Not yet due
  let emg0 = mbx.emit_emergencies(3L)
  inspect(emg0.length(), content="0")
  // Due at cycle 5
  let emg5 = mbx.emit_emergencies(5L)
  inspect(emg5.length(), content="1")
  // Already emitted
  let emg6 = mbx.emit_emergencies(6L)
  inspect(emg6.length(), content="0")
}

///|
test "ProtocolDeviation: truncate frame" {
  let frame = Bytes::make(100, b'\xAA')
  let result = @mock.apply_protocol_deviation(@mock.TruncateFrame(50), frame)
  inspect(result.length(), content="50")
}

///|
test "ProtocolDeviation: zero frame" {
  let frame = Bytes::make(20, b'\xFF')
  let result = @mock.apply_protocol_deviation(@mock.ZeroFrame, frame)
  inspect(result.length(), content="20")
  inspect(result[0], content="b'\\x00'")
}

///|
test "FuzzRng deterministic" {
  let rng1 = @mock.FuzzRng::new(42L)
  let rng2 = @mock.FuzzRng::new(42L)
  // Same seed should produce same sequence
  inspect(rng1.next() == rng2.next(), content="true")
  inspect(rng1.next() == rng2.next(), content="true")
}

///|
test "FuzzRng generate_event_log" {
  let rng = @mock.FuzzRng::new(12345L)
  let log = rng.generate_event_log(10)
  inspect(log.len(), content="10")
}

///|
test "fuzz_campaign runs without crash" {
  let oracle : @mock.FuzzOracle = { check: fn() { true } }
  let results = @mock.fuzz_campaign(1L, 5, 10, oracle)
  inspect(results.length(), content="5")
  for r in results {
    inspect(r.crashed, content="false")
  }
}
