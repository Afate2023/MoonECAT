// Batch 12: white-box tests for runtime/diagnosis.mbt private functions

///|
test "run_fault_issues StartupTransitionFailed all Some" {
  let issues = run_fault_issues(
    StartupTransitionFailed(
      station=0x1001U,
      target=@protocol.Op,
      current=Some(@protocol.SafeOp),
      error_indication=Some(true),
      status_code=Some(0x001AU),
      raw_status_code=Some(0x001AU),
      control_wkc=Some(1U),
    ),
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].level, Block)
  assert_eq(issues[0].source, StateTransition)
  assert_true(issues[0].detail.contains("Startup transition failed"))
  assert_true(issues[0].detail.contains("4097")) // 0x1001 in decimal
  assert_true(issues[0].detail.contains("set"))
}

///|
test "run_fault_issues StartupTransitionFailed all None" {
  let issues = run_fault_issues(
    StartupTransitionFailed(
      station=0x1001U,
      target=@protocol.Op,
      current=None,
      error_indication=None,
      status_code=None,
      raw_status_code=None,
      control_wkc=None,
    ),
  )
  assert_eq(issues.length(), 1)
  assert_true(issues[0].detail.contains("unknown"))
}

///|
test "run_fault_issues StartupTransitionFailed error_indication false" {
  let issues = run_fault_issues(
    StartupTransitionFailed(
      station=0x1001U,
      target=@protocol.Op,
      current=Some(@protocol.Init),
      error_indication=Some(false),
      status_code=Some(0U),
      raw_status_code=Some(0U),
      control_wkc=Some(0U),
    ),
  )
  assert_eq(issues.length(), 1)
  assert_true(issues[0].detail.contains("clear"))
}

///|
test "run_fault_issues TimeoutRecoveryRequired" {
  let issues = run_fault_issues(
    TimeoutRecoveryRequired(observed_timeouts=10L, consecutive_timeouts=3),
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].level, Block)
  assert_eq(issues[0].source, RuntimeTelemetry)
  assert_true(issues[0].detail.contains("Timeout recovery"))
  assert_true(issues[0].detail.contains("10"))
  assert_true(issues[0].detail.contains("3"))
}

///|
test "run_fault_issues RuntimeRecoveryRequired" {
  let issues = run_fault_issues(
    RuntimeRecoveryRequired(expected_wkc=5U, observed_wkc_errors=20L),
  )
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].level, Block)
  assert_true(issues[0].detail.contains("Runtime recovery"))
  assert_true(issues[0].detail.contains("5"))
  assert_true(issues[0].detail.contains("20"))
}

///|
test "run_fault_issues DcDrift" {
  let issues = run_fault_issues(DcDrift(delta_ns=12345L))
  assert_eq(issues.length(), 1)
  assert_eq(issues[0].level, Block)
  assert_true(issues[0].detail.contains("DC drift"))
  assert_true(issues[0].detail.contains("12345"))
}

///|
test "runtime_metrics_issues all clean" {
  let telemetry : Telemetry = {
    cycles: 100L,
    tx_frames: 200L,
    rx_frames: 200L,
    timeouts: 0L,
    retries: 0L,
    wkc_errors: 0L,
    irq_events: 0L,
    dc_delay_updates: 0L,
    emergency_events: 0L,
  }
  let issues = runtime_metrics_issues(telemetry, 100, 100)
  assert_eq(issues.length(), 0)
}

///|
test "runtime_metrics_issues all triggered" {
  let telemetry : Telemetry = {
    cycles: 100L,
    tx_frames: 200L,
    rx_frames: 200L,
    timeouts: 5L,
    retries: 2L,
    wkc_errors: 3L,
    irq_events: 0L,
    dc_delay_updates: 0L,
    emergency_events: 0L,
  }
  let issues = runtime_metrics_issues(telemetry, 100, 90)
  // timeouts>0 (Degrade), wkc_errors>0 (Degrade), retries>0 (Info), cycles_ok<requested (Degrade)
  assert_eq(issues.length(), 4)
  assert_eq(issues[0].level, Degrade) // timeouts
  assert_eq(issues[1].level, Degrade) // wkc_errors
  assert_eq(issues[2].level, Info) // retries
  assert_eq(issues[3].level, Degrade) // cycle completion
  assert_true(issues[3].detail.contains("90/100"))
}

///|
test "validation_difference_issue Missing" {
  let issue = validation_difference_issue(
    ConfigurationDifference::Missing(position=0),
  )
  assert_eq(issue.source, Topology)
  assert_eq(issue.category, Topology)
  assert_eq(issue.level, Block)
}

///|
test "validation_difference_issue Extra" {
  let issue = validation_difference_issue(
    ConfigurationDifference::Extra(position=0),
  )
  assert_eq(issue.source, Topology)
  assert_eq(issue.category, Topology)
  assert_eq(issue.level, Degrade)
}

///|
test "validation_difference_issue IdentityMismatch" {
  let issue = validation_difference_issue(
    ConfigurationDifference::IdentityMismatch(
      position=0,
      expected=None,
      actual=None,
    ),
  )
  assert_eq(issue.source, Configuration)
  assert_eq(issue.category, Identity)
  assert_eq(issue.level, Block)
}

///|
test "validation_difference_issue ProcessDataSummaryMismatch" {
  let pds : ConfigurationProcessDataSummary = {
    sync_manager_count: 0,
    fmmu_count: 0,
    rx_pdo_count: 0,
    tx_pdo_count: 0,
    mailbox_protocols: None,
    dc_op_mode_count: 0,
    dc_assign_activate_count: 0,
  }
  let issue = validation_difference_issue(
    ConfigurationDifference::ProcessDataSummaryMismatch(
      position=0,
      expected=pds,
      actual=pds,
    ),
  )
  assert_eq(issue.source, Configuration)
  assert_eq(issue.category, DiagnosticCategory::Configuration)
}

///|
test "diagnostic_level_from_validate_grade Pass" {
  assert_eq(diagnostic_level_from_validate_grade(Pass), Info)
}

///|
test "diagnostic_level_from_validate_grade Warn" {
  assert_eq(diagnostic_level_from_validate_grade(ValidateGrade::Warn), Degrade)
}

///|
test "diagnostic_level_from_validate_grade Block" {
  assert_eq(
    diagnostic_level_from_validate_grade(ValidateGrade::Block),
    DiagnosticLevel::Block,
  )
}

///|
test "highest_diagnostic_level empty issues uses fallback" {
  let issues : Array[DiagnosticIssue] = []
  assert_eq(highest_diagnostic_level(issues, Info), Info)
  assert_eq(highest_diagnostic_level(issues, Block), Block)
}

///|
test "highest_diagnostic_level picks highest" {
  let issues : Array[DiagnosticIssue] = [
    { source: Registers, category: AlStatus, level: Info, detail: "info" },
    { source: Registers, category: AlStatus, level: Degrade, detail: "degrade" },
  ]
  assert_eq(highest_diagnostic_level(issues, Info), Degrade)
}

///|
test "highest_diagnostic_level Block wins" {
  let issues : Array[DiagnosticIssue] = [
    { source: Registers, category: AlStatus, level: Info, detail: "info" },
    { source: Registers, category: AlStatus, level: Block, detail: "block" },
  ]
  assert_eq(highest_diagnostic_level(issues, Info), Block)
}

///|
test "diagnostic_level_rank ordering" {
  assert_eq(diagnostic_level_rank(Info), 0)
  assert_eq(diagnostic_level_rank(Degrade), 1)
  assert_eq(diagnostic_level_rank(Block), 2)
}

///|
test "empty_state_surface_summary all None" {
  let s = empty_state_surface_summary()
  assert_true(s.target_state is None)
  assert_true(s.current_state is None)
  assert_true(s.final_state is None)
  assert_true(s.al_state is None)
  assert_true(s.al_error_flag is None)
  assert_true(s.al_status_code is None)
  assert_true(s.wkc is None)
}

///|
test "configuration_surface_summary populates fields" {
  let scan : ScanReport = {
    slave_count: 2,
    slaves: [
      {
        position: 0,
        station_address: 0x1001U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
      {
        position: 1,
        station_address: 0x1002U,
        alias_address: None,
        vendor_id: 1U,
        product_code: 2U,
        revision: 3U,
        serial: 4U,
        identification: 5U,
      },
    ],
  }
  let cs = configuration_surface_summary(
    scan,
    Some(EniImport),
    Some(OnlineScan),
    Some(ValidateGrade::Warn),
    3,
  )
  assert_eq(cs.slave_count, 2)
  assert_eq(cs.station_addresses, [0x1001U, 0x1002U])
  assert_eq(cs.expected_source, Some(EniImport))
  assert_eq(cs.actual_source, Some(OnlineScan))
  assert_eq(cs.validation_grade, Some(ValidateGrade::Warn))
  assert_eq(cs.difference_count, 3)
}

///|
test "runtime_metrics_summary maps telemetry" {
  let telemetry : Telemetry = {
    cycles: 100L,
    tx_frames: 200L,
    rx_frames: 201L,
    timeouts: 5L,
    retries: 2L,
    wkc_errors: 3L,
    irq_events: 1L,
    dc_delay_updates: 4L,
    emergency_events: 6L,
  }
  let rm = runtime_metrics_summary(telemetry)
  assert_eq(rm.cycles, 100L)
  assert_eq(rm.tx_frames, 200L)
  assert_eq(rm.rx_frames, 201L)
  assert_eq(rm.timeouts, 5L)
  assert_eq(rm.retries, 2L)
  assert_eq(rm.wkc_errors, 3L)
  assert_eq(rm.irq_events, 1L)
  assert_eq(rm.dc_delay_updates, 4L)
  assert_eq(rm.emergency_events, 6L)
}

///|
test "diagnosis_timeout_step Ok returns value" {
  let result : Result[Int, Error] = Ok(42)
  let value = diagnosis_timeout_step(result, "test")
  assert_eq(value, 42)
}

///|
test "diagnosis_timeout_step RecvTimeout wraps" {
  let result : Result[Int, Error] = Err(@hal.EcError::RecvTimeout)
  let outcome : Result[Int, _] = try
    diagnosis_timeout_step(result, "test.step") |> Ok
  catch {
    e => Err(e)
  }
  guard outcome is Err(e) else { fail("expected error") }
  assert_true(e.to_string().contains("timeout at test.step"))
  assert_true(e.to_string().contains("RecvTimeout"))
}

///|
test "diagnosis_timeout_step MailboxTimeout wraps" {
  let result : Result[Int, Error] = Err(@hal.EcError::MailboxTimeout)
  let outcome : Result[Int, _] = try
    diagnosis_timeout_step(result, "test.step") |> Ok
  catch {
    e => Err(e)
  }
  guard outcome is Err(e) else { fail("expected error") }
  assert_true(e.to_string().contains("MailboxTimeout"))
}

///|
test "diagnosis_timeout_step Internal timeout chains" {
  let result : Result[Int, Error] = Err(
    @hal.EcError::Internal("timeout at inner.step"),
  )
  let outcome : Result[Int, _] = try
    diagnosis_timeout_step(result, "outer.step") |> Ok
  catch {
    e => Err(e)
  }
  guard outcome is Err(e) else { fail("expected error") }
  assert_true(e.to_string().contains("outer.step -> "))
  assert_true(e.to_string().contains("timeout at inner.step"))
}

///|
test "diagnosis_timeout_step other error wraps" {
  let result : Result[Int, Error] = Err(@hal.EcError::LinkDown)
  let outcome : Result[Int, _] = try
    diagnosis_timeout_step(result, "test.step") |> Ok
  catch {
    e => Err(e)
  }
  guard outcome is Err(e) else { fail("expected error") }
  assert_true(e.to_string().contains("LinkDown"))
}

///|
test "diagnosis_bytes_preview empty" {
  assert_eq(diagnosis_bytes_preview(b""), "<empty>")
}

///|
test "diagnosis_bytes_preview single byte" {
  assert_eq(diagnosis_bytes_preview(b"\xAB"), "0xAB")
}

///|
test "diagnosis_bytes_preview multiple bytes" {
  assert_eq(diagnosis_bytes_preview(b"\x00\xFF\x42"), "0x00 0xFF 0x42")
}

///|
test "diagnosis_hex_byte values" {
  assert_eq(diagnosis_hex_byte(b'\x00'), "0x00")
  assert_eq(diagnosis_hex_byte(b'\xFF'), "0xFF")
  assert_eq(diagnosis_hex_byte(b'\xAB'), "0xAB")
  assert_eq(diagnosis_hex_byte(b'\x1C'), "0x1C")
}

///|
test "diagnosis_hex_digit all values" {
  assert_eq(diagnosis_hex_digit(0), "0")
  assert_eq(diagnosis_hex_digit(1), "1")
  assert_eq(diagnosis_hex_digit(2), "2")
  assert_eq(diagnosis_hex_digit(3), "3")
  assert_eq(diagnosis_hex_digit(4), "4")
  assert_eq(diagnosis_hex_digit(5), "5")
  assert_eq(diagnosis_hex_digit(6), "6")
  assert_eq(diagnosis_hex_digit(7), "7")
  assert_eq(diagnosis_hex_digit(8), "8")
  assert_eq(diagnosis_hex_digit(9), "9")
  assert_eq(diagnosis_hex_digit(10), "A")
  assert_eq(diagnosis_hex_digit(11), "B")
  assert_eq(diagnosis_hex_digit(12), "C")
  assert_eq(diagnosis_hex_digit(13), "D")
  assert_eq(diagnosis_hex_digit(14), "E")
  assert_eq(diagnosis_hex_digit(15), "F")
}
