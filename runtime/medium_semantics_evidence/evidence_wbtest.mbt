///|
test "logical commands classify LRD LWR LRW and WKC contribution" {
  let lrd = classify_medium_command(@protocol.read_command(@protocol.Logical))
  let lwr = classify_medium_command(@protocol.write_command(@protocol.Logical))
  let lrw = classify_medium_command(
    @protocol.readwrite_command(@protocol.Logical),
  )
  @debug.assert_eq(lrd.command_label, "LRD")
  @debug.assert_eq(lrd.frame_kind, LogicalRead)
  @debug.assert_eq(lrd.wkc_contribution.expected_single_match_increment(), 1U)
  assert_true(lrd.reads_process_data)
  assert_true(!lrd.writes_process_data)
  @debug.assert_eq(lwr.command_label, "LWR")
  @debug.assert_eq(lwr.frame_kind, LogicalWrite)
  @debug.assert_eq(lwr.wkc_contribution.expected_single_match_increment(), 1U)
  assert_true(!lwr.reads_process_data)
  assert_true(lwr.writes_process_data)
  @debug.assert_eq(lrw.command_label, "LRW")
  @debug.assert_eq(lrw.frame_kind, LogicalReadWrite)
  @debug.assert_eq(lrw.wkc_contribution.expected_single_match_increment(), 3U)
  assert_true(lrw.reads_process_data)
  assert_true(lrw.writes_process_data)
}

///|
test "ESM DC fault HAL and lookahead evidence remain offline" {
  let report = medium_semantics_report()
  assert_true(report.covers_required_medium_semantics())
  @debug.assert_eq(
    report.segment_traversal.traversal_model,
    "VirtualBus per-PDU slave-chain traversal",
  )
  assert_true(report.segment_traversal.visits_slaves_in_wire_order)
  assert_true(report.segment_traversal.swaps_response_mac)
  assert_true(report.segment_traversal.accumulates_pdu_wkc)
  @debug.assert_eq(report.esm_valid.from, @protocol.Init)
  @debug.assert_eq(report.esm_valid.target, @protocol.PreOp)
  assert_true(report.esm_valid.valid)
  assert_true(!report.esm_invalid.valid)
  @debug.assert_eq(report.dc.latch_register, @protocol.reg_dc_time0)
  @debug.assert_eq(report.dc.system_time_register, @protocol.reg_dc_system_time)
  @debug.assert_eq(report.dc.sync_window_register, @protocol.reg_dc_system_diff)
  assert_true(!report.dc.live_claimed)
  @debug.assert_eq(
    report.lookahead.max_pdus_per_frame,
    @protocol.max_pdus_per_frame,
  )
  @debug.assert_eq(report.lookahead.outstanding_frames, 1)
  assert_true(report.lookahead.supports_frame_internal_batching)
  assert_true(!report.lookahead.supports_cross_cycle_pipeline)
}

///|
test "mock fault and NIC event classifiers cover all boundary classes" {
  let timeout = classify_mock_fault(@mock.RecvTimeout)
  @debug.assert_eq(timeout.fault_class, ReceiveTimeout)
  assert_true(timeout.affects_recv)
  assert_true(!timeout.affects_send)
  let send = classify_mock_fault(@mock.SendFailure("boom"))
  @debug.assert_eq(send.fault_class, TransmitFailure)
  assert_true(send.affects_send)
  assert_true(!send.affects_recv)
  let drop = classify_mock_fault(@mock.FrameDrop)
  @debug.assert_eq(drop.fault_class, FrameLoss)
  assert_true(drop.affects_recv)
  let corrupt = classify_mock_fault(@mock.FrameCorrupt(offset=1, value=b'\xAA'))
  @debug.assert_eq(corrupt.fault_class, FrameMutation)
  assert_true(corrupt.can_change_wkc)
  let wkc = classify_mock_fault(@mock.WkcCorrupt(delta=-1))
  @debug.assert_eq(wkc.fault_class, WorkingCounterMutation)
  assert_true(wkc.can_change_wkc)

  @debug.assert_eq(
    classify_mock_nic_event(@mock.Sent(b"\x00", 1)).event_class,
    TxFrame,
  )
  @debug.assert_eq(
    classify_mock_nic_event(@mock.Received(b"\x00")).event_class,
    RxFrame,
  )
  @debug.assert_eq(
    classify_mock_nic_event(@mock.RecvTimeout).event_class,
    RxTimeout,
  )
  @debug.assert_eq(
    classify_mock_nic_event(@mock.RecvFailed("rx")).event_class,
    RxFailure,
  )
  @debug.assert_eq(
    classify_mock_nic_event(@mock.LinkDown).event_class,
    LinkState,
  )
  @debug.assert_eq(
    classify_mock_nic_event(@mock.SendFailed("tx")).event_class,
    TxFailure,
  )
}

///|
test "semantics report converts to MC1A medium evidence section" {
  let section = medium_semantics_report().to_medium_evidence_section()
  @debug.assert_eq(section.stage, @medium_evidence.MediumTransport)
  @debug.assert_eq(section.boundary, @medium_evidence.MockSimulation)
  @debug.assert_eq(section.artifact_ref, Some("medium-semantics-evidence-v1"))
}
