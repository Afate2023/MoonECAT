///|
test "Telemetry initializes to zero" {
  let t = @runtime.Telemetry::new()
  assert_eq(t.cycles, 0L)
  assert_eq(t.tx_frames, 0L)
  assert_eq(t.rx_frames, 0L)
  assert_eq(t.timeouts, 0L)
  assert_eq(t.retries, 0L)
  assert_eq(t.wkc_errors, 0L)
}

///|
test "RunMode display" {
  inspect(@runtime.RunMode::FreeRun, content="FreeRun")
  inspect(@runtime.RunMode::DcSync, content="DcSync")
}

///|
test "RuntimeState display" {
  inspect(@runtime.RuntimeState::Idle, content="Idle")
  inspect(
    @runtime.RuntimeState::Running(@runtime.RunMode::FreeRun),
    content="Running(FreeRun)",
  )
}
