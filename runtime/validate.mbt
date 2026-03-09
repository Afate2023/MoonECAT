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
fn find_slave_at_position(
  slaves : Array[SlaveReport],
  position : Int,
) -> SlaveReport? {
  for slave in slaves {
    if slave.position == position {
      return Some(slave)
    }
  }
  None
}

///|
fn has_expected_position(
  expected : Array[@hal.SlaveConfig],
  position : Int,
) -> Bool {
  for exp in expected {
    if exp.position.reinterpret_as_int() == position {
      return true
    }
  }
  false
}

///|
/// Validate that scan results match expected slaves by `position`.
pub fn validate(
  scan_report : ScanReport,
  expected : Array[@hal.SlaveConfig],
) -> ValidateReport {
  let results : Array[ValidationResult] = []
  let mut all_ok = true
  // Check each expected slave by configured position.
  for exp in expected {
    let pos = exp.position.reinterpret_as_int()
    match find_slave_at_position(scan_report.slaves, pos) {
      Some(found) => {
        let actual_identity : @hal.SlaveIdentity = {
          vendor_id: found.vendor_id,
          product_code: found.product_code,
          revision: found.revision,
          serial: found.serial,
        }
        match exp.expected_identity {
          Some(expected_id) =>
            if actual_identity.vendor_id == expected_id.vendor_id &&
              actual_identity.product_code == expected_id.product_code &&
              actual_identity.revision == expected_id.revision &&
              actual_identity.serial == expected_id.serial {
              results.push(Ok)
            } else {
              results.push(
                IdentityMismatch(expected=expected_id, actual=actual_identity),
              )
              all_ok = false
            }
          None => results.push(Ok) // No identity constraint — accept any
        }
      }
      None => {
        results.push(Missing(position=pos))
        all_ok = false
      }
    }
  }

  // Check for extra slaves whose positions are not configured.
  for found in scan_report.slaves {
    if not(has_expected_position(expected, found.position)) {
      results.push(Extra(position=found.position))
      all_ok = false
    }
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
