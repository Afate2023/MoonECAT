///|
test "MonitorRegistry defaults" {
  let reg = @runtime.MonitorRegistry::with_defaults()
  inspect(reg.len(), content="6")
}

///|
test "MonitorRegistry custom monitor" {
  let reg = @runtime.MonitorRegistry::new()
  reg.register("custom_test", {
    run: fn(_rt) {
      ({ name: "custom_test", verdict: @runtime.Pass } : @runtime.MonitorResult)
    },
  })
  inspect(reg.len(), content="1")
}

///|
test "MonitorRegistry unregister" {
  let reg = @runtime.MonitorRegistry::with_defaults()
  inspect(reg.len(), content="6")
  reg.unregister("dc_drift")
  inspect(reg.len(), content="5")
}

///|
test "VerificationReport to_markdown" {
  let report = @runtime.VerificationReport::new("Test Report")
  report.add_event(0L, "start", "cycle 0", @runtime.Pass)
  report.add_event(10L, "fault", "recv timeout", @runtime.Warn("timeout"))
  report.add_fault("RecvTimeout at cycle 10")
  report.add_meta("platform", "test")
  let md = report.to_markdown()
  inspect(md.contains("# Test Report"), content="true")
  inspect(md.contains("Verdict Timeline"), content="true")
  inspect(md.contains("Fault Injections"), content="true")
}

///|
test "VerificationReport to_json" {
  let report = @runtime.VerificationReport::new("JSON Test")
  report.add_event(5L, "warn", "issue", @runtime.Warn("test"))
  let json = report.to_json()
  inspect(json.contains("\"title\":\"JSON Test\""), content="true")
  inspect(json.contains("\"timeline\":["), content="true")
}
