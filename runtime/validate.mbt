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
  /// Slave alias address mismatch.
  AliasAddressMismatch(position~ : Int, expected~ : UInt, actual~ : UInt)
  /// Slave identity mismatch.
  IdentityMismatch(expected~ : @hal.SlaveIdentity, actual~ : @hal.SlaveIdentity)
  /// Slave explicit identification mismatch.
  IdentificationMismatch(position~ : Int, expected~ : UInt, actual~ : UInt)
  /// Slave process-data/config summary mismatch.
  ProcessDataMismatch(position~ : Int)
  /// Slave not found at expected position.
  Missing(position~ : Int)
  /// Optional slave group member is absent.
  OptionalMissing(position~ : Int, group_id~ : UInt?)
  /// Extra slave found that was not expected.
  Extra(position~ : Int)
} derive(Debug)

///|
pub(all) enum ValidateGrade {
  Pass
  Warn
  Block
} derive(Eq, Debug)

///|
pub(all) enum ValidateDifferenceCategory {
  Topology
  Identity
  Configuration
  Informational
} derive(Eq, Debug)

///|
/// ValidateReport holds the full validation result.
pub(all) struct ValidateReport {
  expected_source : ConfigurationSource
  actual_source : ConfigurationSource
  total_expected : Int
  total_found : Int
  results : Array[ValidationResult]
  differences : Array[ConfigurationDifference]
  all_ok : Bool
  grade : ValidateGrade
} derive(Debug)

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
              IdentificationMismatch(..) | ProcessDataSummaryMismatch(..) =>
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
    differences: comparison.differences,
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
      Extra(..) | OptionalMissing(..) => ()
      _ => return Block
    }
  }
  Warn
}

///|
pub fn validation_difference_category(
  difference : ConfigurationDifference,
) -> ValidateDifferenceCategory {
  match difference {
    Missing(..)
    | OptionalMissing(..)
    | Extra(..)
    | StationAddressMismatch(..)
    | AliasAddressMismatch(..) => Topology
    IdentityMismatch(..) => Identity
    IdentificationMismatch(..) | ProcessDataSummaryMismatch(..) => Configuration
  }
}

///|
pub fn validation_difference_grade(
  difference : ConfigurationDifference,
) -> ValidateGrade {
  match difference {
    Extra(..) | OptionalMissing(..) => Warn
    _ => Block
  }
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
      OptionalMissing(position~, ..) if position == wanted_position =>
        matches.push(diff)
      StationAddressMismatch(position~, ..) if position == wanted_position =>
        matches.push(diff)
      AliasAddressMismatch(position~, ..) if position == wanted_position =>
        matches.push(diff)
      IdentityMismatch(position~, ..) if position == wanted_position =>
        matches.push(diff)
      IdentificationMismatch(position~, ..) if position == wanted_position =>
        matches.push(diff)
      ProcessDataSummaryMismatch(position~, ..) if position == wanted_position =>
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
      Missing(..)
      | OptionalMissing(..)
      | StationAddressMismatch(..)
      | AliasAddressMismatch(..) => return Some(diff)
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
    OptionalMissing(position~, group_id~) =>
      OptionalMissing(position~, group_id~)
    Extra(position~) => Extra(position~)
    StationAddressMismatch(position~, expected~, actual~) =>
      StationAddressMismatch(
        position~,
        expected=option_uint_or_zero(expected),
        actual=option_uint_or_zero(actual),
      )
    AliasAddressMismatch(position~, expected~, actual~) =>
      AliasAddressMismatch(
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
    ProcessDataSummaryMismatch(position~, ..) => ProcessDataMismatch(position~)
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
      AliasAddressMismatch(position~, expected~, actual~) =>
        buf.write_string(
          "  [ALIAS-MISMATCH] Slave #" +
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
      ProcessDataMismatch(position~) =>
        buf.write_string(
          "  [CONFIG-MISMATCH] Slave #" +
          position.to_string() +
          ": process-data summary mismatch\n",
        )
      Missing(position~) =>
        buf.write_string(
          "  [MISSING] Slave #" + position.to_string() + ": not found\n",
        )
      OptionalMissing(position~, group_id~) =>
        buf.write_string(
          "  [OPTIONAL-MISSING] Slave #" +
          position.to_string() +
          ": optional hot-connect member absent" +
          optional_group_suffix(group_id) +
          "\n",
        )
      Extra(position~) =>
        buf.write_string(
          "  [EXTRA] Slave #" + position.to_string() + ": unexpected\n",
        )
    }
  }
  buf.to_string()
}

///|
fn optional_group_suffix(group_id : UInt?) -> String {
  match group_id {
    Some(group) => " (group=" + group.to_string() + ")"
    None => ""
  }
}
