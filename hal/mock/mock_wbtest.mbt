// Whitebox tests for hal/mock package private functions

///|
test "apply_replay_event RecvFailed event" {
  let log = NicEventLog::new()
  log.append(NicEvent::RecvFailed("test error"))
  let replay = ReplayNic::from_log(log)
  // RecvFailed triggers recv on replay → may raise but ignored
  apply_replay_event(replay, NicEvent::RecvFailed("test error"))
}

///|
test "apply_replay_event LinkDown event" {
  let log = NicEventLog::new()
  log.append(NicEvent::LinkDown)
  let replay = ReplayNic::from_log(log)
  apply_replay_event(replay, NicEvent::LinkDown)
}

///|
test "escape_json_string backslash" {
  let result = escape_json_string("a\\b")
  assert_true(result.contains("\\\\"))
}

///|
test "escape_json_string carriage_return" {
  let result = escape_json_string("a\rb")
  assert_true(result.contains("\\r"))
}

///|
test "find_substr empty needle returns 0" {
  let haystack = "hello".to_array()
  let needle : Array[Char] = []
  assert_eq(find_substr(haystack, needle), 0)
}

///|
test "find_substr haystack shorter than needle returns -1" {
  let haystack = "hi".to_array()
  let needle = "hello".to_array()
  assert_eq(find_substr(haystack, needle), -1)
}

// ===== Batch 25: escape_json_string tab, check_graceful_stop non-Fail =====

///|
test "escape_json_string escapes tab character" {
  let result = escape_json_string("a\tb")
  assert_eq(result, "a\\tb")
}

///|
test "check_graceful_stop with only non-Fail verdicts returns true" {
  let observed : Array[ObservedVerdict] = [
    { cycle: 1L, verdict: @runtime.Pass },
    { cycle: 2L, verdict: @runtime.Warn("test") },
  ]
  assert_eq(check_graceful_stop(observed, 10, 100L), true)
}
