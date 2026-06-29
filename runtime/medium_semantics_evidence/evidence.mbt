///|
/// MediumFrameKind classifies EtherCAT PDU commands by the medium semantics
/// that matter for mock/offline evidence.

///|
pub(all) enum MediumFrameKind {
  NoopFrame
  PhysicalRead
  PhysicalWrite
  PhysicalReadWrite
  BroadcastRead
  BroadcastWrite
  BroadcastReadWrite
  LogicalRead
  LogicalWrite
  LogicalReadWrite
  MultipleWrite
} derive(Eq, Debug)

///|
pub fn medium_frame_kind_label(kind : MediumFrameKind) -> String {
  match kind {
    NoopFrame => "noop"
    PhysicalRead => "physical.read"
    PhysicalWrite => "physical.write"
    PhysicalReadWrite => "physical.read_write"
    BroadcastRead => "broadcast.read"
    BroadcastWrite => "broadcast.write"
    BroadcastReadWrite => "broadcast.read_write"
    LogicalRead => "logical.read"
    LogicalWrite => "logical.write"
    LogicalReadWrite => "logical.read_write"
    MultipleWrite => "multiple_write"
  }
}

///|
pub(all) enum WkcContribution {
  NoWkc
  ReadOnly
  WriteOnly
  ReadWrite
} derive(Eq, Debug)

///|
pub fn WkcContribution::expected_single_match_increment(
  self : WkcContribution,
) -> UInt {
  match self {
    NoWkc => 0U
    ReadOnly | WriteOnly => 1U
    ReadWrite => 3U
  }
}

///|
pub(all) struct MediumCommandEvidence {
  command_label : String
  command_byte : Byte
  frame_kind : MediumFrameKind
  uses_logical_fmmu : Bool
  reads_process_data : Bool
  writes_process_data : Bool
  wkc_contribution : WkcContribution
  source : String
} derive(Eq, Debug)

///|
pub(all) struct SegmentTraversalEvidence {
  traversal_model : String
  visits_slaves_in_wire_order : Bool
  swaps_response_mac : Bool
  accumulates_pdu_wkc : Bool
  source : String
} derive(Eq, Debug)

///|
pub fn segment_traversal_evidence() -> SegmentTraversalEvidence {
  {
    traversal_model: "VirtualBus per-PDU slave-chain traversal",
    visits_slaves_in_wire_order: true,
    swaps_response_mac: true,
    accumulates_pdu_wkc: true,
    source: "hal/mock/VirtualBus::process_frame + process_pdu",
  }
}

///|
pub fn command_label(command : @protocol.EcCommand) -> String {
  match command {
    NOP => "NOP"
    APRD => "APRD"
    APWR => "APWR"
    APRW => "APRW"
    FPRD => "FPRD"
    FPWR => "FPWR"
    FPRW => "FPRW"
    BRD => "BRD"
    BWR => "BWR"
    BRW => "BRW"
    LRD => "LRD"
    LWR => "LWR"
    LRW => "LRW"
    ARMW => "ARMW"
    FRMW => "FRMW"
  }
}

///|
pub fn classify_medium_command(
  command : @protocol.EcCommand,
) -> MediumCommandEvidence {
  let (
    frame_kind,
    uses_logical_fmmu,
    reads_process_data,
    writes_process_data,
    wkc_contribution,
  ) = match command {
    NOP => (NoopFrame, false, false, false, NoWkc)
    APRD | FPRD => (PhysicalRead, false, false, false, ReadOnly)
    APWR | FPWR => (PhysicalWrite, false, false, false, WriteOnly)
    APRW | FPRW => (PhysicalReadWrite, false, false, false, ReadWrite)
    BRD => (BroadcastRead, false, false, false, ReadOnly)
    BWR => (BroadcastWrite, false, false, false, WriteOnly)
    BRW => (BroadcastReadWrite, false, false, false, ReadWrite)
    LRD => (LogicalRead, true, true, false, ReadOnly)
    LWR => (LogicalWrite, true, false, true, WriteOnly)
    LRW => (LogicalReadWrite, true, true, true, ReadWrite)
    ARMW | FRMW => (MultipleWrite, false, false, false, NoWkc)
  }
  {
    command_label: command_label(command),
    command_byte: command.to_byte(),
    frame_kind,
    uses_logical_fmmu,
    reads_process_data,
    writes_process_data,
    wkc_contribution,
    source: "protocol/address.mbt + hal/mock/VirtualBus::process_pdu",
  }
}

///|
pub(all) struct EsmTransitionEvidence {
  from : @protocol.EsmState
  target : @protocol.EsmState
  valid : Bool
  source : String
} derive(Eq, Debug)

///|
pub fn esm_transition_evidence(
  from : @protocol.EsmState,
  target : @protocol.EsmState,
) -> EsmTransitionEvidence {
  {
    from,
    target,
    valid: from.can_transition(target),
    source: "protocol/EsmState::can_transition + hal/mock/VirtualSlave::write_reg",
  }
}

///|
pub(all) struct DcSemanticsEvidence {
  latch_register : UInt
  system_time_register : UInt
  sync_window_register : UInt
  check_source : String
  live_claimed : Bool
} derive(Eq, Debug)

///|
pub fn dc_semantics_evidence() -> DcSemanticsEvidence {
  {
    latch_register: @protocol.reg_dc_time0,
    system_time_register: @protocol.reg_dc_system_time,
    sync_window_register: @protocol.reg_dc_system_diff,
    check_source: "protocol/dc.mbt: dc_latch_times, dc_configure_linear, dc_check_sync_window",
    live_claimed: false,
  }
}

///|
pub(all) enum MediumFaultClass {
  ReceiveTimeout
  TransmitFailure
  FrameLoss
  FrameMutation
  WorkingCounterMutation
} derive(Eq, Debug)

///|
pub fn medium_fault_class_label(class : MediumFaultClass) -> String {
  match class {
    ReceiveTimeout => "receive.timeout"
    TransmitFailure => "transmit.failure"
    FrameLoss => "frame.loss"
    FrameMutation => "frame.mutation"
    WorkingCounterMutation => "working_counter.mutation"
  }
}

///|
pub(all) struct MediumFaultEvidence {
  fault_class : MediumFaultClass
  affects_send : Bool
  affects_recv : Bool
  can_change_wkc : Bool
  source : String
} derive(Eq, Debug)

///|
pub fn classify_mock_fault(fault : @mock.FaultType) -> MediumFaultEvidence {
  match fault {
    RecvTimeout =>
      {
        fault_class: ReceiveTimeout,
        affects_send: false,
        affects_recv: true,
        can_change_wkc: false,
        source: "hal/mock/FaultInjector::check_recv",
      }
    SendFailure(_) =>
      {
        fault_class: TransmitFailure,
        affects_send: true,
        affects_recv: false,
        can_change_wkc: false,
        source: "hal/mock/FaultInjector::check_send",
      }
    FrameDrop =>
      {
        fault_class: FrameLoss,
        affects_send: false,
        affects_recv: true,
        can_change_wkc: false,
        source: "hal/mock/apply_frame_fault",
      }
    FrameCorrupt(..) =>
      {
        fault_class: FrameMutation,
        affects_send: false,
        affects_recv: true,
        can_change_wkc: true,
        source: "hal/mock/apply_frame_fault",
      }
    WkcCorrupt(..) =>
      {
        fault_class: WorkingCounterMutation,
        affects_send: false,
        affects_recv: true,
        can_change_wkc: true,
        source: "hal/mock/apply_frame_fault",
      }
  }
}

///|
pub(all) enum MediumHalEventClass {
  TxFrame
  RxFrame
  RxTimeout
  RxFailure
  LinkState
  TxFailure
} derive(Eq, Debug)

///|
pub fn medium_hal_event_class_label(class : MediumHalEventClass) -> String {
  match class {
    TxFrame => "tx.frame"
    RxFrame => "rx.frame"
    RxTimeout => "rx.timeout"
    RxFailure => "rx.failure"
    LinkState => "link.state"
    TxFailure => "tx.failure"
  }
}

///|
pub(all) struct MediumHalEventEvidence {
  event_class : MediumHalEventClass
  replayable : Bool
  native_live_claimed : Bool
  source : String
} derive(Eq, Debug)

///|
pub fn classify_mock_nic_event(
  event : @mock.NicEvent,
) -> MediumHalEventEvidence {
  let event_class = match event {
    Sent(_, _) => TxFrame
    Received(_) => RxFrame
    RecvTimeout => RxTimeout
    RecvFailed(_) => RxFailure
    LinkDown => LinkState
    SendFailed(_) => TxFailure
  }
  {
    event_class,
    replayable: true,
    native_live_claimed: false,
    source: "hal/mock/NicEventLog",
  }
}

///|
pub(all) struct LookaheadBoundaryEvidence {
  max_pdus_per_frame : Int
  outstanding_frames : Int
  supports_frame_internal_batching : Bool
  supports_cross_cycle_pipeline : Bool
  source : String
} derive(Eq, Debug)

///|
pub fn lookahead_boundary_evidence() -> LookaheadBoundaryEvidence {
  {
    max_pdus_per_frame: @protocol.max_pdus_per_frame,
    outstanding_frames: 1,
    supports_frame_internal_batching: true,
    supports_cross_cycle_pipeline: false,
    source: "protocol/FrameBuilder + protocol/transact synchronous request/response",
  }
}

///|
pub(all) struct MediumSemanticsReport {
  report_version : String
  segment_traversal : SegmentTraversalEvidence
  command_evidence : Array[MediumCommandEvidence]
  esm_valid : EsmTransitionEvidence
  esm_invalid : EsmTransitionEvidence
  dc : DcSemanticsEvidence
  fault_evidence : Array[MediumFaultEvidence]
  hal_event_evidence : Array[MediumHalEventEvidence]
  lookahead : LookaheadBoundaryEvidence
  live_claimed : Bool
} derive(Eq, Debug)

///|
pub fn medium_semantics_report() -> MediumSemanticsReport {
  {
    report_version: "medium-semantics-evidence-v1",
    segment_traversal: segment_traversal_evidence(),
    command_evidence: [
      classify_medium_command(@protocol.read_command(@protocol.Logical)),
      classify_medium_command(@protocol.write_command(@protocol.Logical)),
      classify_medium_command(@protocol.readwrite_command(@protocol.Logical)),
    ],
    esm_valid: esm_transition_evidence(@protocol.Init, @protocol.PreOp),
    esm_invalid: esm_transition_evidence(@protocol.Init, @protocol.Op),
    dc: dc_semantics_evidence(),
    fault_evidence: [
      classify_mock_fault(@mock.RecvTimeout),
      classify_mock_fault(@mock.SendFailure("send failed")),
      classify_mock_fault(@mock.FrameDrop),
      classify_mock_fault(@mock.FrameCorrupt(offset=0, value=b'\xFF')),
      classify_mock_fault(@mock.WkcCorrupt(delta=-1)),
    ],
    hal_event_evidence: [
      classify_mock_nic_event(@mock.Sent(b"\x00", 1)),
      classify_mock_nic_event(@mock.Received(b"\x00")),
      classify_mock_nic_event(@mock.RecvTimeout),
      classify_mock_nic_event(@mock.RecvFailed("rx failed")),
      classify_mock_nic_event(@mock.LinkDown),
      classify_mock_nic_event(@mock.SendFailed("tx failed")),
    ],
    lookahead: lookahead_boundary_evidence(),
    live_claimed: false,
  }
}

///|
pub fn MediumSemanticsReport::has_logical_command(
  self : MediumSemanticsReport,
  kind : MediumFrameKind,
) -> Bool {
  self.command_evidence
  .iter()
  .any(fn(item) { item.uses_logical_fmmu && item.frame_kind == kind })
}

///|
pub fn MediumSemanticsReport::covers_required_medium_semantics(
  self : MediumSemanticsReport,
) -> Bool {
  self.has_logical_command(LogicalRead) &&
  self.has_logical_command(LogicalWrite) &&
  self.has_logical_command(LogicalReadWrite) &&
  self.segment_traversal.visits_slaves_in_wire_order &&
  self.segment_traversal.swaps_response_mac &&
  self.segment_traversal.accumulates_pdu_wkc &&
  self.esm_valid.valid &&
  !self.esm_invalid.valid &&
  !self.dc.live_claimed &&
  self.fault_evidence.length() == 5 &&
  self.hal_event_evidence.length() == 6 &&
  !self.lookahead.supports_cross_cycle_pipeline &&
  !self.live_claimed
}

///|
pub fn MediumSemanticsReport::to_medium_evidence_section(
  self : MediumSemanticsReport,
) -> @medium_evidence.MediumEvidenceSection {
  @medium_evidence.MediumEvidenceSection::make(
    stage=@medium_evidence.MediumTransport,
    title="EtherCAT medium semantics evidence",
    source="runtime/medium_semantics_evidence + protocol + hal/mock",
    summary="classifies VirtualBus segment traversal, LRD/LWR/LRW, WKC contribution, ESM transition validity, DC evidence points, mock fault/HAL events, and lookahead boundaries; live_claimed=\{self.live_claimed}",
    boundary=@medium_evidence.MockSimulation,
    artifact_ref="medium-semantics-evidence-v1",
  )
}
