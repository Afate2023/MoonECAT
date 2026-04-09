///|
/// EoE Embedded Relay (Phase 3) — lightweight synchronous frame relay.
///
/// Design isolation from Phase 2 (async/network):
///   - Phase 2 (eoe_endpoint.mbt): queue-based async, decoupled timing,
///     host application polls at its own pace, needs buffering.
///   - Phase 3 (eoe_relay.mbt): synchronous callback, zero-copy intent,
///     frame processing happens inline during the PDO cycle, no queuing.
///
/// The embedded relay is suitable for bare-metal / RTOS targets where:
///   - No OS network stack (no TAP/TUN, no sockets)
///   - Frames are processed by application logic directly
///   - Deterministic timing: relay happens within the PDO cycle budget
///   - Memory is constrained: no dynamic queue growth

///|
/// Direction of an EoE relay frame.
pub(all) enum EoeRelayDirection {
  /// Frame going from host application to an EoE slave.
  HostToSlave
  /// Frame received from an EoE slave, delivered to host application.
  SlaveToHost
} derive(Eq, Debug)

///|
/// Metadata for a relayed EoE frame.
pub(all) struct EoeRelayFrame {
  /// Direction of the frame.
  direction : EoeRelayDirection
  /// EoE station address (source for SlaveToHost, destination for HostToSlave).
  station : UInt
  /// Raw Ethernet frame bytes.
  data : Bytes
} derive(Eq, Debug)

///|
/// Statistics for the embedded relay.
pub(all) struct EoeRelayStats {
  /// Total frames relayed host→slave.
  mut tx_relayed : Int64
  /// Total frames relayed slave→host.
  mut rx_relayed : Int64
  /// Frames dropped due to handler rejection.
  mut dropped : Int64
} derive(Eq, Debug)

///|
pub fn EoeRelayStats::new() -> EoeRelayStats {
  { tx_relayed: 0L, rx_relayed: 0L, dropped: 0L }
}

///|
/// EoE Embedded Relay engine.
///
/// Processes frames synchronously during the PDO cycle:
///   1. Collects all reassembled RX frames from EoeSwitch
///   2. Invokes `rx_handler` for each (application processes inline)
///   3. Invokes `tx_provider` to get frames to send (application provides inline)
///   4. Sends collected TX frames via EoeSwitch
///
/// The handler/provider are plain functions, not trait objects, keeping
/// the relay free of dynamic dispatch overhead on embedded targets.
pub(all) struct EoeRelay {
  /// Relay statistics.
  stats : EoeRelayStats
  /// Whether the relay is active.
  mut active : Bool
} derive(Debug)

///|
pub fn EoeRelay::new() -> EoeRelay {
  { stats: EoeRelayStats::new(), active: true }
}

///|
/// Activate or deactivate the relay.
pub fn EoeRelay::set_active(self : EoeRelay, active : Bool) -> Unit {
  self.active = active
}

///|
/// Execute one relay cycle synchronously.
///
/// `rx_handler`: Called for each reassembled Ethernet frame received from
///   an EoE slave. Returns true if the frame was accepted, false to drop.
///
/// `tx_provider`: Called repeatedly to collect frames to send. Returns
///   None when no more frames are available this cycle.
///
/// Returns (rx_count, tx_count) processed this cycle.
pub fn[N : @hal.Nic] EoeRelay::relay_cycle(
  self : EoeRelay,
  sw : EoeSwitch,
  nic : N,
  timeout : @hal.Duration,
  rx_handler : (EoeRelayFrame) -> Bool,
  tx_provider : () -> EoeRelayFrame?,
) -> (Int, Int) {
  if !self.active {
    return (0, 0)
  }
  // RX: deliver reassembled frames to application
  let received = sw.drain_rx()
  let mut rx_count = 0
  for f in received {
    let relay_frame = EoeRelayFrame::{
      direction: SlaveToHost,
      station: f.station,
      data: f.data,
    }
    if rx_handler(relay_frame) {
      self.stats.rx_relayed = self.stats.rx_relayed + 1L
      rx_count = rx_count + 1
    } else {
      self.stats.dropped = self.stats.dropped + 1L
    }
  }
  // TX: collect frames from application and send
  let mut tx_count = 0
  while true {
    match tx_provider() {
      None => break
      Some(frame) =>
        try {
          ignore(sw.send_frame(nic, frame.station, frame.data, timeout))
          self.stats.tx_relayed = self.stats.tx_relayed + 1L
          tx_count = tx_count + 1
        } catch {
          _ => self.stats.dropped = self.stats.dropped + 1L
        }
    }
  }
  (rx_count, tx_count)
}

///|
/// Get relay statistics as JSON.
pub fn EoeRelayStats::to_json(self : EoeRelayStats) -> Json {
  {
    "tx_relayed": Json::number(self.tx_relayed.to_double()),
    "rx_relayed": Json::number(self.rx_relayed.to_double()),
    "dropped": Json::number(self.dropped.to_double()),
  }
  |> Json::object
}

///|
/// Get full relay status as JSON.
pub fn EoeRelay::to_json(self : EoeRelay) -> Json {
  { "active": Json::boolean(self.active), "stats": self.stats.to_json() }
  |> Json::object
}

///|
/// Format relay status as human-readable text.
pub fn EoeRelay::format_text(self : EoeRelay) -> String {
  let buf = @buffer.new(size_hint=128)
  buf.write_string("EoE Embedded Relay\n")
  buf.write_string("  Active: ")
  buf.write_string(self.active.to_string())
  buf.write_string("\n  TX relayed: ")
  buf.write_string(self.stats.tx_relayed.to_string())
  buf.write_string("\n  RX relayed: ")
  buf.write_string(self.stats.rx_relayed.to_string())
  buf.write_string("\n  Dropped: ")
  buf.write_string(self.stats.dropped.to_string())
  buf.write_string("\n")
  buf.to_string()
}
