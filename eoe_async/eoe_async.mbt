///|
/// EoE Async Bridge — fully asynchronous interface for the EoE Virtual Switch.
///
/// Uses `moonbitlang/async` Queue for TX/RX channels and periodic polling.
/// This bridges the synchronous EoeSwitch engine with the async runtime,
/// allowing concurrent frame send/receive and background polling.
///
/// Relationship to other modules:
///   - runtime/eoe_switch.mbt: core synchronous engine (fragmentation, reassembly)
///   - runtime/eoe_endpoint.mbt: sync queue + one-shot bridge_eoe_cycle()
///   - eoe_async/ (this package): async Queue channels + background poll task

///|
/// Async bridge wrapping the EoE Virtual Switch with async Queue channels.
///
/// TX flow: application → tx_queue → poll task → EoeSwitch → mailbox → slave
/// RX flow: slave → mailbox → EoeSwitch → poll task → rx_queue → application
pub(all) struct EoeAsyncBridge {
  /// The underlying synchronous switch engine.
  sw : @runtime.EoeSwitch
  /// Async queue for host→slave frames (application puts, poll task drains).
  tx_queue : @aqueue.Queue[@runtime.EoeEndpointFrame]
  /// Async queue for slave→host frames (poll task puts, application gets).
  rx_queue : @aqueue.Queue[@runtime.EoeEndpointFrame]
  /// Whether the bridge is active.
  mut active : Bool
  /// Polling interval in milliseconds.
  poll_interval_ms : Int
}

///|
/// Create a new async bridge.
///
/// `tx_depth` / `rx_depth`: maximum queue depth for each direction.
/// `poll_interval_ms`: how often the background task polls the switch (ms).
pub fn EoeAsyncBridge::new(
  tx_depth? : Int = 64,
  rx_depth? : Int = 64,
  poll_interval_ms? : Int = 10,
) -> EoeAsyncBridge {
  {
    sw: @runtime.EoeSwitch::new(),
    tx_queue: @aqueue.Queue::new(kind=Blocking(tx_depth)),
    rx_queue: @aqueue.Queue::new(kind=Blocking(rx_depth)),
    active: true,
    poll_interval_ms,
  }
}

///|
/// Register an EoE-capable station.
pub fn EoeAsyncBridge::add_station(
  self : EoeAsyncBridge,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
) -> Unit {
  self.sw.add_station(station, mb_config)
}

///|
/// Submit a frame for sending to an EoE slave (async, may block if queue full).
pub async fn EoeAsyncBridge::send(
  self : EoeAsyncBridge,
  station : UInt,
  data : Bytes,
) -> Unit {
  self.tx_queue.put(@runtime.EoeEndpointFrame::{ station, data })
}

///|
/// Submit a frame for sending (non-blocking). Returns false if queue is full.
pub fn EoeAsyncBridge::try_send(
  self : EoeAsyncBridge,
  station : UInt,
  data : Bytes,
) -> Bool {
  self.tx_queue.try_put(@runtime.EoeEndpointFrame::{ station, data }) catch {
    _ => false
  }
}

///|
/// Receive an Ethernet frame from an EoE slave (async, blocks until available).
pub async fn EoeAsyncBridge::recv(
  self : EoeAsyncBridge,
) -> @runtime.EoeEndpointFrame {
  self.rx_queue.get()
}

///|
/// Try to receive a frame (non-blocking). Returns None if queue is empty.
pub fn EoeAsyncBridge::try_recv(
  self : EoeAsyncBridge,
) -> @runtime.EoeEndpointFrame? {
  self.rx_queue.try_get() catch {
    _ => None
  }
}

///|
/// Run the background polling loop. Call this from a TaskGroup via spawn_loop.
///
/// Each cycle:
///   1. Drain tx_queue → send_frame() via EoeSwitch
///   2. poll() to receive mailbox responses
///   3. drain_rx() → push into rx_queue
///
/// This function runs until the bridge is deactivated or cancelled.
pub async fn[N : @hal.Nic] EoeAsyncBridge::poll_loop(
  self : EoeAsyncBridge,
  nic : N,
  timeout : @hal.Duration,
) -> Unit {
  while self.active {
    // TX: drain pending sends
    while true {
      let frame = self.tx_queue.try_get() catch { _ => None }
      match frame {
        None => break
        Some(frame) =>
          ignore(
            self.sw.send_frame(nic, frame.station, frame.data, timeout) catch {
              _ => 0
            },
          )
      }
    }
    // RX: poll mailbox and deliver
    ignore(self.sw.poll(nic, timeout))
    let received = self.sw.drain_rx()
    for f in received {
      let ep_frame = @runtime.EoeEndpointFrame::{
        station: f.station,
        data: f.data,
      }
      try {
        if !self.rx_queue.try_put(ep_frame) {
          // queue full — drop frame
          ()
        }
      } catch {
        _ => ()
      }
    }
    @async.sleep(self.poll_interval_ms)
  }
}

///|
/// Stop the bridge. The poll_loop will exit on next iteration.
pub fn EoeAsyncBridge::stop(self : EoeAsyncBridge) -> Unit {
  self.active = false
}

///|
/// Check if the bridge is active.
pub fn EoeAsyncBridge::is_active(self : EoeAsyncBridge) -> Bool {
  self.active
}

///|
/// Get the underlying switch for direct access (status, IP config, etc.).
pub fn EoeAsyncBridge::switch(self : EoeAsyncBridge) -> @runtime.EoeSwitch {
  self.sw
}

///|
/// Get bridge status as JSON.
pub fn EoeAsyncBridge::to_json(self : EoeAsyncBridge) -> Json {
  {
    "active": Json::boolean(self.active),
    "poll_interval_ms": Json::number(self.poll_interval_ms.to_double()),
    "switch": self.sw.to_json(),
  }
  |> Json::object
}
