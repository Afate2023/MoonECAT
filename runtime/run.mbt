///|
/// CLI run command: full EtherCAT lifecycle — scan, validate, transition
/// slaves to Operational, run PDO cycles, and return a diagnostic summary.

///|
/// RunPhase describes which phase the run command is in.
pub(all) enum RunPhase {
  Scanning
  Validating
  Configuring
  Operational
  Stopping
  Done
} derive(Eq, Show)

///|
/// RunReport summarizes the outcome of a full run cycle.
pub(all) struct RunReport {
  scan : ScanReport
  validation : ValidateReport
  cycles_requested : Int
  cycles_ok : Int
  telemetry : Telemetry
  final_phase : RunPhase
} derive(Show)

///|
/// Execute a full EtherCAT run workflow:
/// 1. Scan the bus to discover slaves.
/// 2. Validate discovered slaves against expected configuration.
/// 3. Transition all slaves to Operational via ESM broadcast.
/// 4. Run the requested number of PDO cycles.
/// 5. Transition slaves back to Init.
/// 6. Return a summary report.
pub fn[N : @hal.Nic] run(
  nic : N,
  config : @hal.MasterConfig,
  expected : Array[@hal.SlaveConfig],
  pdo_ctx : @protocol.PdoContext,
  expected_wkc : UInt,
  cycles : Int,
  timeout : @hal.Duration,
) -> RunReport raise @hal.EcError {
  // Phase 1: Scan
  let scan_report = scan(nic, timeout)

  // Phase 2: Validate
  let validate_report = validate(scan_report, expected)
  if not(validate_report.all_ok) {
    return {
      scan: scan_report,
      validation: validate_report,
      cycles_requested: cycles,
      cycles_ok: 0,
      telemetry: Telemetry::new(),
      final_phase: Validating,
    }
  }

  // Phase 3: Configure — transition slaves to Operational
  ignore(@protocol.broadcast_state(nic, @protocol.EsmState::Op, timeout))

  // Phase 4: Run PDO cycles
  let rt = Runtime::new(config)
  rt.configure_pdo(pdo_ctx, expected_wkc)
  let stations = expected.map(fn(s) { s.configured_address })
  let dc_ok = rt.init_dc(nic, stations, timeout) catch { _ => false }
  rt.set_state(Running(if dc_ok { DcSync } else { FreeRun }))
  let ok_count = rt.run_cycles(nic, cycles, timeout)

  // Phase 5: Shutdown — transition slaves back to Init
  ignore(
    @protocol.broadcast_state(nic, @protocol.EsmState::Init, timeout) catch {
      _ => 0U // Best-effort shutdown; report already captured
    },
  )
  rt.set_state(Idle)

  {
    scan: scan_report,
    validation: validate_report,
    cycles_requested: cycles,
    cycles_ok: ok_count,
    telemetry: rt.get_telemetry(),
    final_phase: Done,
  }
}

///|
/// Format a RunReport as a human-readable summary.
pub fn RunReport::format(self : RunReport) -> String {
  let buf = @buffer.new(size_hint=512)
  buf.write_string("MoonECAT Run Report\n")
  buf.write_string("===================\n")
  buf.write_string("Slaves found: " + self.scan.slave_count.to_string() + "\n")
  buf.write_string(
    "Validation: " +
    (if self.validation.all_ok { "PASS" } else { "FAIL" }) +
    "\n",
  )
  buf.write_string(
    "Cycles: " +
    self.cycles_ok.to_string() +
    "/" +
    self.cycles_requested.to_string() +
    " OK\n",
  )
  buf.write_string("Phase: " + self.final_phase.to_string() + "\n")
  let tel = self.telemetry
  buf.write_string(
    "Telemetry: tx=" +
    tel.tx_frames.to_string() +
    " rx=" +
    tel.rx_frames.to_string() +
    " timeouts=" +
    tel.timeouts.to_string() +
    " irq_events=" +
    tel.irq_events.to_string() +
    " wkc_errors=" +
    tel.wkc_errors.to_string() +
    "\n",
  )
  buf.to_string()
}
