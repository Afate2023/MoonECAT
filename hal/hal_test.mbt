///|
test "EcError variants display correctly" {
  inspect(@hal.EcError::LinkDown, content="LinkDown")
  inspect(@hal.EcError::SendFailed("test"), content="SendFailed(\"test\")")
  inspect(@hal.EcError::RecvTimeout, content="RecvTimeout")
}

///|
test "Duration and Timestamp construct correctly" {
  let ts = @hal.Timestamp(1000L)
  let dur = @hal.Duration(500L)
  inspect(ts, content="Timestamp(1000)")
  inspect(dur, content="Duration(500)")
}

///|
test "MasterConfig default values" {
  let cfg = @hal.MasterConfig::default()
  assert_eq(cfg.interface_name, "eth0")
  assert_eq(cfg.cycle_period_ns, 1_000_000L)
  assert_eq(cfg.max_retries, 3)
  assert_eq(cfg.dc_enabled, false)
}

///|
test "DiagnosticEvent construction" {
  let evt = @hal.DiagnosticEvent::new(
    @hal.Timestamp(100L),
    @hal.Severity::Info,
    "hal",
    "link up",
  )
  assert_eq(evt.severity, @hal.Severity::Info)
  assert_eq(evt.source, "hal")
  assert_eq(evt.message, "link up")
}

///|
test "SlaveIdentity equality" {
  let id1 : @hal.SlaveIdentity = {
    vendor_id: 0x2U,
    product_code: 0x1U,
    revision: 0x0U,
    serial: 0x0U,
  }
  let id2 : @hal.SlaveIdentity = {
    vendor_id: 0x2U,
    product_code: 0x1U,
    revision: 0x0U,
    serial: 0x0U,
  }
  assert_eq(id1, id2)
}
