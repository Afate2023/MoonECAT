///|
/// CLI validate command: check that discovered slaves match an expected
/// configuration, verifying identity and ESM readiness.

///|
/// ValidationResult describes the outcome of one slave check.
pub(all) enum ValidationResult {
  /// Slave matches expected configuration.
  Ok
  /// Slave identity mismatch.
  IdentityMismatch(expected~ : @hal.SlaveIdentity, actual~ : @hal.SlaveIdentity)
  /// Slave not found at expected position.
  Missing(position~ : Int)
  /// Extra slave found that was not expected.
  Extra(position~ : Int)
} derive(Show)

///|
/// ValidateReport holds the full validation result.
pub(all) struct ValidateReport {
  total_expected : Int
  total_found : Int
  results : Array[ValidationResult]
  all_ok : Bool
} derive(Show)

///|
/// Validate that a scan report matches an expected slave configuration.
/// Each expected slave is checked by position.
pub fn validate(
  scan_report : ScanReport,
  expected : Array[@hal.SlaveConfig],
) -> ValidateReport {
  let results : Array[ValidationResult] = []
  let mut all_ok = true
  // Check each expected slave
  for i = 0; i < expected.length(); i = i + 1 {
    if i < scan_report.slaves.length() {
      let found = scan_report.slaves[i]
      let exp = expected[i]
      let actual_identity : @hal.SlaveIdentity = {
        vendor_id: found.vendor_id,
        product_code: found.product_code,
        revision: found.revision,
        serial: found.serial,
      }
      match exp.expected_identity {
        Some(expected_id) =>
          if actual_identity.vendor_id == expected_id.vendor_id &&
            actual_identity.product_code == expected_id.product_code {
            results.push(Ok)
          } else {
            results.push(
              IdentityMismatch(expected=expected_id, actual=actual_identity),
            )
            all_ok = false
          }
        None => results.push(Ok) // No identity constraint — accept any
      }
    } else {
      results.push(Missing(position=i))
      all_ok = false
    }
  }
  // Check for extra slaves
  for i = expected.length(); i < scan_report.slaves.length(); i = i + 1 {
    results.push(Extra(position=i))
    all_ok = false
  }
  {
    total_expected: expected.length(),
    total_found: scan_report.slave_count,
    results,
    all_ok,
  }
}

///|
/// Format a ValidateReport as a human-readable string.
pub fn ValidateReport::format(self : ValidateReport) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("EtherCAT Validation Report\n")
  buf.write_string("==========================\n")
  buf.write_string("Expected: " + self.total_expected.to_string() + " slaves\n")
  buf.write_string("Found:    " + self.total_found.to_string() + " slaves\n")
  buf.write_string(
    "Status:   " + (if self.all_ok { "PASS" } else { "FAIL" }) + "\n\n",
  )
  for i = 0; i < self.results.length(); i = i + 1 {
    match self.results[i] {
      Ok => buf.write_string("  [OK] Slave #" + i.to_string() + "\n")
      IdentityMismatch(..) =>
        buf.write_string(
          "  [MISMATCH] Slave #" + i.to_string() + ": identity mismatch\n",
        )
      Missing(position~) =>
        buf.write_string(
          "  [MISSING] Slave #" + position.to_string() + ": not found\n",
        )
      Extra(position~) =>
        buf.write_string(
          "  [EXTRA] Slave #" + position.to_string() + ": unexpected\n",
        )
    }
  }
  buf.to_string()
}
