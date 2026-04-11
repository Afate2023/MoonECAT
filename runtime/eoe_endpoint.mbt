///|
/// EoE Endpoint abstraction for async/network integration (Phase 2).
///
/// An EoeEndpoint represents the host-side network interface that bridges
/// Ethernet frames between the EoE Virtual Switch and an external network
/// stack (TAP/TUN device, raw socket, or user-space application).
///
/// Design isolation: This module handles only the host↔switch boundary.
/// The actual EtherCAT-side fragmentation/reassembly remains in eoe_switch.mbt.

///|
/// Trait for bidirectional Ethernet frame exchange at the host boundary.
///
/// Implementors:
///   - QueueEndpoint: in-process async queue (default, no OS dependency)
///   - Future: TapEndpoint (Linux TAP/TUN via C FFI)
///   - Future: WintunEndpoint (Windows Wintun via C FFI)
pub(open) trait EoeEndpoint {
  /// Read an Ethernet frame from the host network stack.
  /// Returns None if no frame is available (non-blocking).
  read_frame(Self) -> Bytes?
  /// Write an Ethernet frame to the host network stack.
  /// Returns true on success.
  write_frame(Self, Bytes) -> Bool
  /// Whether the endpoint is connected and operational.
  is_up(Self) -> Bool
}

///|
/// Queue-based EoE endpoint for in-process async bridging.
///
/// The host application pushes frames into `tx_pending` (host→slave direction)
/// and reads frames from `rx_pending` (slave→host direction).
/// The bridge cycle transfers frames between these queues and the EoeSwitch.
///
/// This endpoint requires no OS network stack — suitable for user-space
/// applications, unit tests, and embedded systems with application-level
/// networking.
pub(all) struct QueueEndpoint {
  /// Frames waiting to be sent to EoE slaves (host→slave).
  tx_pending : Array[EoeEndpointFrame]
  /// Frames received from EoE slaves, ready for host consumption (slave→host).
  rx_pending : Array[EoeEndpointFrame]
  /// Maximum queue depth per direction (0 = unlimited).
  max_depth : Int
  /// Whether this endpoint is active.
  mut up : Bool
} derive(Debug)

///|
/// A frame in the endpoint queue, tagged with the destination/source station.
pub(all) struct EoeEndpointFrame {
  /// Target or source EoE station address.
  station : UInt
  /// Raw Ethernet frame bytes.
  data : Bytes
} derive(Eq, Debug)

///|
pub fn QueueEndpoint::new(max_depth? : Int = 64) -> QueueEndpoint {
  { tx_pending: [], rx_pending: [], max_depth, up: true }
}

///|
/// Submit a frame for sending to an EoE slave (host→slave direction).
/// Returns false if the queue is full or endpoint is down.
pub fn QueueEndpoint::submit_tx(
  self : QueueEndpoint,
  station : UInt,
  data : Bytes,
) -> Bool {
  if !self.up {
    return false
  }
  if self.max_depth > 0 && self.tx_pending.length() >= self.max_depth {
    return false
  }
  self.tx_pending.push(EoeEndpointFrame::{ station, data })
  true
}

///|
/// Consume the next received frame from the slave→host queue.
/// Returns None if no frames are available.
pub fn QueueEndpoint::consume_rx(self : QueueEndpoint) -> EoeEndpointFrame? {
  if self.rx_pending.length() == 0 {
    return None
  }
  // Remove from front (FIFO)
  Some(self.rx_pending.remove(0))
}

///|
/// Number of frames waiting to be sent to slaves.
pub fn QueueEndpoint::tx_depth(self : QueueEndpoint) -> Int {
  self.tx_pending.length()
}

///|
/// Number of frames received from slaves, waiting for host consumption.
pub fn QueueEndpoint::rx_depth(self : QueueEndpoint) -> Int {
  self.rx_pending.length()
}

///|
/// Set endpoint up/down state.
pub fn QueueEndpoint::set_up(self : QueueEndpoint, up : Bool) -> Unit {
  self.up = up
}

///|
/// EoeEndpoint implementation for QueueEndpoint.
pub fn QueueEndpoint::read_frame(self : QueueEndpoint) -> Bytes? {
  if self.tx_pending.length() == 0 {
    return None
  }
  let frame = self.tx_pending.remove(0)
  Some(frame.data)
}

///|
pub fn QueueEndpoint::write_frame(self : QueueEndpoint, data : Bytes) -> Bool {
  if !self.up {
    return false
  }
  if self.max_depth > 0 && self.rx_pending.length() >= self.max_depth {
    return false
  }
  // Station is unknown when writing from switch; use 0 as placeholder.
  self.rx_pending.push(EoeEndpointFrame::{ station: 0U, data })
  true
}

///|
pub fn QueueEndpoint::is_up(self : QueueEndpoint) -> Bool {
  self.up
}

///|
/// Bridge one cycle between EoeSwitch and QueueEndpoint.
///
/// TX direction (host→slave): Drains tx_pending, fragments and sends
/// each frame to its target EoE station via the switch.
///
/// RX direction (slave→host): Drains the switch rx_queue and pushes
/// reassembled frames into rx_pending for host consumption.
///
/// Returns (tx_sent, rx_delivered) counts.
pub fn[N : @hal.Nic] bridge_eoe_cycle(
  sw : EoeSwitch,
  ep : QueueEndpoint,
  nic : N,
  timeout : @hal.Duration,
) -> (Int, Int) {
  let mut tx_sent = 0
  // TX: host → slave
  while ep.tx_pending.length() > 0 {
    let frame = ep.tx_pending.remove(0)
    let _ = sw.send_frame(nic, frame.station, frame.data, timeout) catch {
      _ => continue
    }
    tx_sent = tx_sent + 1
  }
  // RX: slave → host
  let received = sw.drain_rx()
  let mut rx_delivered = 0
  for f in received {
    if ep.up && (ep.max_depth == 0 || ep.rx_pending.length() < ep.max_depth) {
      ep.rx_pending.push(EoeEndpointFrame::{ station: f.station, data: f.data })
      rx_delivered = rx_delivered + 1
    }
  }
  (tx_sent, rx_delivered)
}

///|
/// Get endpoint status as JSON.
pub fn QueueEndpoint::to_json(self : QueueEndpoint) -> Json {
  {
    "up": Json::boolean(self.up),
    "tx_depth": Json::number(self.tx_pending.length().to_double()),
    "rx_depth": Json::number(self.rx_pending.length().to_double()),
    "max_depth": Json::number(self.max_depth.to_double()),
  }
  |> Json::object
}
