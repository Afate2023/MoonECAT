///|
/// CLI validate command: check that discovered slaves match an expected
/// configuration, verifying identity and ESM readiness.

///|
/// ValidationResult describes the outcome of one slave check.
pub(all) enum ValidationResult {
  /// Slave matches expected configuration.
  Ok
  /// Slave station address mismatch.
  StationAddressMismatch(position~ : Int, expected~ : UInt, actual~ : UInt)
  /// Slave identity mismatch.
  IdentityMismatch(expected~ : @hal.SlaveIdentity, actual~ : @hal.SlaveIdentity)
  /// Slave explicit identification mismatch.
  IdentificationMismatch(position~ : Int, expected~ : UInt, actual~ : UInt)
  /// Slave not found at expected position.
  Missing(position~ : Int)
  /// Extra slave found that was not expected.
  Extra(position~ : Int)
} derive(Show)

///|
pub(all) enum ValidateGrade {
  Pass
  Warn
  Block
} derive(Eq, Show)

///|
/// ValidateReport holds the full validation result.
pub(all) struct ValidateReport {
  expected_source : ConfigurationSource
  actual_source : ConfigurationSource
  total_expected : Int
  total_found : Int
  results : Array[ValidationResult]
  all_ok : Bool
  grade : ValidateGrade
} derive(Show)

///|
/// Validate that a scan report matches an expected slave configuration.
/// Each expected slave is checked by position.
fn zero_identity() -> @hal.SlaveIdentity {
  { vendor_id: 0U, product_code: 0U, revision: 0U, serial: 0U }
}

///|
pub fn validate_configuration(
  actual : ConfigurationModel,
  expected : ConfigurationModel,
) -> ValidateReport {
  let comparison = compare_configurations(expected, actual)
  let results : Array[ValidationResult] = []
  for exp in expected.slaves {
    let position = exp.position
    let diffs = differences_for_position(comparison.differences, position)
    if diffs.length() == 0 {
      results.push(Ok)
    } else {
      let missing_or_address = first_missing_or_address_diff(diffs)
      match missing_or_address {
        Some(diff) => results.push(configuration_difference_to_validation(diff))
        None => {
          let identity_diff = first_identity_diff(diffs)
          match identity_diff {
            Some(diff) =>
              results.push(configuration_difference_to_validation(diff))
            None => results.push(Ok)
          }
          for diff in diffs {
            match diff {
              IdentificationMismatch(..) =>
                results.push(configuration_difference_to_validation(diff))
              _ => ()
            }
          }
        }
      }
    }
  }
  for diff in comparison.differences {
    match diff {
      Extra(_) => results.push(configuration_difference_to_validation(diff))
      _ => ()
    }
  }
  {
    expected_source: comparison.expected_source,
    actual_source: comparison.actual_source,
    total_expected: comparison.total_expected,
    total_found: comparison.total_found,
    results,
    all_ok: comparison.all_ok,
    grade: validation_grade_from_differences(comparison.differences),
  }
}

///|
fn validation_grade_from_differences(
  differences : Array[ConfigurationDifference],
) -> ValidateGrade {
  if differences.length() == 0 {
    return Pass
  }
  for diff in differences {
    match diff {
      Extra(..) => ()
      _ => return Block
    }
  }
  Warn
}

///|
fn differences_for_position(
  differences : Array[ConfigurationDifference],
  wanted_position : Int,
) -> Array[ConfigurationDifference] {
  let matches : Array[ConfigurationDifference] = []
  for diff in differences {
    match diff {
      Missing(position~) if position == wanted_position => matches.push(diff)
      StationAddressMismatch(position~, ..) if position == wanted_position =>
        matches.push(diff)
      IdentityMismatch(position~, ..) if position == wanted_position =>
        matches.push(diff)
      IdentificationMismatch(position~, ..) if position == wanted_position =>
        matches.push(diff)
      _ => ()
    }
  }
  matches
}

///|
fn first_missing_or_address_diff(
  differences : Array[ConfigurationDifference],
) -> ConfigurationDifference? {
  for diff in differences {
    match diff {
      Missing(..) | StationAddressMismatch(..) => return Some(diff)
      _ => ()
    }
  }
  None
}

///|
fn first_identity_diff(
  differences : Array[ConfigurationDifference],
) -> ConfigurationDifference? {
  for diff in differences {
    match diff {
      IdentityMismatch(..) => return Some(diff)
      _ => ()
    }
  }
  None
}

///|
fn configuration_difference_to_validation(
  difference : ConfigurationDifference,
) -> ValidationResult {
  match difference {
    Missing(position~) => Missing(position~)
    Extra(position~) => Extra(position~)
    StationAddressMismatch(position~, expected~, actual~) =>
      StationAddressMismatch(
        position~,
        expected=option_uint_or_zero(expected),
        actual=option_uint_or_zero(actual),
      )
    IdentityMismatch(position~, expected~, actual~) => {
      let _ = position
      ValidationResult::IdentityMismatch(
        expected=option_identity_or_zero(expected),
        actual=option_identity_or_zero(actual),
      )
    }
    IdentificationMismatch(position~, expected~, actual~) =>
      IdentificationMismatch(
        position~,
        expected=option_uint_or_zero(expected),
        actual=option_uint_or_zero(actual),
      )
  }
}

///|
fn option_uint_or_zero(value : UInt?) -> UInt {
  match value {
    Some(number) => number
    None => 0U
  }
}

///|
fn option_identity_or_zero(value : @hal.SlaveIdentity?) -> @hal.SlaveIdentity {
  match value {
    Some(identity) => identity
    None => zero_identity()
  }
}

///|
/// Validate that scan results match expected slaves by `position`.
pub fn validate(
  scan_report : ScanReport,
  expected : Array[@hal.SlaveConfig],
) -> ValidateReport {
  validate_configuration(
    configuration_from_scan(scan_report),
    configuration_from_expected(expected),
  )
}

///|
fn validate_grade_label(grade : ValidateGrade) -> String {
  match grade {
    Pass => "PASS"
    Warn => "WARN"
    Block => "BLOCK"
  }
}

///|
/// Format a ValidateReport as a human-readable string.
pub fn ValidateReport::format(self : ValidateReport) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("EtherCAT Validation Report\n")
  buf.write_string("==========================\n")
  buf.write_string(
    "Expected Source: " + self.expected_source.to_string() + "\n",
  )
  buf.write_string("Actual Source:   " + self.actual_source.to_string() + "\n")
  buf.write_string("Expected: " + self.total_expected.to_string() + " slaves\n")
  buf.write_string("Found:    " + self.total_found.to_string() + " slaves\n")
  buf.write_string("Status:   " + validate_grade_label(self.grade) + "\n\n")
  for i = 0; i < self.results.length(); i = i + 1 {
    match self.results[i] {
      Ok => buf.write_string("  [OK] Slave #" + i.to_string() + "\n")
      StationAddressMismatch(position~, expected~, actual~) =>
        buf.write_string(
          "  [ADDR-MISMATCH] Slave #" +
          position.to_string() +
          ": expected 0x" +
          expected.reinterpret_as_int().to_string() +
          " actual 0x" +
          actual.reinterpret_as_int().to_string() +
          "\n",
        )
      IdentityMismatch(..) =>
        buf.write_string(
          "  [MISMATCH] Slave #" + i.to_string() + ": identity mismatch\n",
        )
      IdentificationMismatch(position~, expected~, actual~) =>
        buf.write_string(
          "  [ID-MISMATCH] Slave #" +
          position.to_string() +
          ": expected 0x" +
          expected.reinterpret_as_int().to_string() +
          " actual 0x" +
          actual.reinterpret_as_int().to_string() +
          "\n",
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
