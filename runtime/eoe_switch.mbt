///|
/// EoE (Ethernet over EtherCAT) Virtual Switch engine.
///
/// Implements L2 frame fragmentation, reassembly, and routing between
/// the host (master) and EoE-capable slaves. Designed for integration
/// with the Runtime PDO cycle via poll_eoe(), following the same pattern
/// as poll_emergencies().
///
/// Phase 1 scope: async/network — fragment/reassemble frames, IP config.
/// Phase 2 scope: embedded relay — lightweight, no OS network stack.

///|
/// Maximum number of concurrent reassembly buffers per station.
let eoe_max_reassembly_buffers : Int = 4

///|
/// EoE fragment size alignment (32-byte boundary per SOEM convention).
let eoe_fragment_align : Int = 32

///|
/// Mailbox header (6 bytes) + EoE header (4 bytes) overhead.
let eoe_overhead : Int = 10

///|
/// Reassembly buffer for one in-progress EoE frame from a single slave.
struct EoeReassemblyBuffer {
  /// Frame number being reassembled (4-bit, 0–15).
  frame_number : UInt
  /// Collected fragment data in order; index = fragment_number.
  fragments : Array[Bytes?]
  /// Total bytes accumulated so far.
  mut total_bytes : Int
  /// Whether the last fragment has been received.
  mut last_seen : Bool
  /// Number of fragments expected (set when last fragment arrives).
  mut expected_count : UInt
} derive(Debug)

///|
fn EoeReassemblyBuffer::new(frame_number : UInt) -> EoeReassemblyBuffer {
  {
    frame_number,
    fragments: Array::make(64, None),
    total_bytes: 0,
    last_seen: false,
    expected_count: 0U,
  }
}

///|
/// Insert a fragment into the reassembly buffer.
/// Returns true if the frame is now complete.
fn EoeReassemblyBuffer::insert(
  self : EoeReassemblyBuffer,
  frag_number : UInt,
  last_fragment : Bool,
  data : Bytes,
) -> Bool {
  let idx = frag_number.reinterpret_as_int()
  if idx < self.fragments.length() && self.fragments[idx] is None {
    self.fragments[idx] = Some(data)
    self.total_bytes = self.total_bytes + data.length()
  }
  if last_fragment {
    self.last_seen = true
    self.expected_count = frag_number + 1U
  }
  self.is_complete()
}

///|
/// Check if all fragments have been received.
fn EoeReassemblyBuffer::is_complete(self : EoeReassemblyBuffer) -> Bool {
  if !self.last_seen {
    return false
  }
  let count = self.expected_count.reinterpret_as_int()
  for i = 0; i < count; i = i + 1 {
    if self.fragments[i] is None {
      return false
    }
  }
  true
}

///|
/// Assemble the complete Ethernet frame from collected fragments.
fn EoeReassemblyBuffer::assemble(self : EoeReassemblyBuffer) -> Bytes {
  let buf = @buffer.new(size_hint=self.total_bytes)
  let count = self.expected_count.reinterpret_as_int()
  for i = 0; i < count; i = i + 1 {
    guard self.fragments[i] is Some(frag) else { continue }
    for j = 0; j < frag.length(); j = j + 1 {
      buf.write_byte(frag[j])
    }
  }
  buf.to_bytes()
}

///|
/// Per-station EoE context: tracks reassembly state and send counter.
pub(all) struct EoeStationContext {
  /// Station address (configured address).
  station : UInt
  /// Mailbox configuration for this slave.
  mb_config : @mailbox.MailboxConfig
  /// Active reassembly buffers keyed by frame_number.
  reassembly : Array[EoeReassemblyBuffer?]
  /// Monotonic frame number counter for outgoing frames (0–15 wrap).
  mut tx_frame_number : UInt
  /// Mailbox counter for EoE frames (1–7 wrap, 0 reserved).
  mut mb_counter : Byte
} derive(Debug)

///|
fn EoeStationContext::new(
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
) -> EoeStationContext {
  {
    station,
    mb_config,
    reassembly: Array::make(eoe_max_reassembly_buffers, None),
    tx_frame_number: 0U,
    mb_counter: b'\x01',
  }
}

///|
/// Advance the mailbox counter (1–7 wrap).
fn EoeStationContext::next_counter(self : EoeStationContext) -> Byte {
  let c = self.mb_counter
  let next = c.to_int() + 1
  self.mb_counter = if next > 7 { b'\x01' } else { next.to_byte() }
  c
}

///|
/// Advance the TX frame number (0–15 wrap).
fn EoeStationContext::next_frame_number(self : EoeStationContext) -> UInt {
  let n = self.tx_frame_number
  self.tx_frame_number = (n + 1U) & 0xFU
  n
}

///|
/// Find or allocate a reassembly buffer for the given frame_number.
/// Evicts the oldest buffer if all slots are full.
fn EoeStationContext::get_reassembly(
  self : EoeStationContext,
  frame_number : UInt,
) -> EoeReassemblyBuffer {
  // Look for existing buffer with matching frame_number.
  for i = 0; i < self.reassembly.length(); i = i + 1 {
    guard self.reassembly[i] is Some(buf) else { continue }
    if buf.frame_number == frame_number {
      return buf
    }
  }
  // Look for an empty slot.
  for i = 0; i < self.reassembly.length(); i = i + 1 {
    if self.reassembly[i] is None {
      let buf = EoeReassemblyBuffer::new(frame_number)
      self.reassembly[i] = Some(buf)
      return buf
    }
  }
  // Evict slot 0 (oldest).
  let buf = EoeReassemblyBuffer::new(frame_number)
  self.reassembly[0] = Some(buf)
  buf
}

///|
/// Remove the reassembly buffer for the given frame_number.
fn EoeStationContext::clear_reassembly(
  self : EoeStationContext,
  frame_number : UInt,
) -> Unit {
  for i = 0; i < self.reassembly.length(); i = i + 1 {
    guard self.reassembly[i] is Some(buf) else { continue }
    if buf.frame_number == frame_number {
      self.reassembly[i] = None
      return
    }
  }
}

///|
/// Received EoE frame delivered to the host.
pub(all) struct EoeReceivedFrame {
  /// Source station address.
  station : UInt
  /// Reassembled Ethernet frame bytes.
  data : Bytes
} derive(Eq, Debug)

///|
/// EoE Virtual Switch state.
pub(all) struct EoeSwitch {
  /// Per-station EoE contexts.
  mut stations : Array[EoeStationContext]
  /// Completed frames ready for delivery to the host.
  rx_queue : Array[EoeReceivedFrame]
  /// Telemetry: total fragments sent.
  mut tx_fragments : Int64
  /// Telemetry: total fragments received.
  mut rx_fragments : Int64
  /// Telemetry: total frames reassembled.
  mut rx_frames_complete : Int64
  /// Telemetry: reassembly errors (unexpected fragment, etc.).
  mut rx_errors : Int64
} derive(Debug)

///|
pub fn EoeSwitch::new() -> EoeSwitch {
  {
    stations: [],
    rx_queue: [],
    tx_fragments: 0L,
    rx_fragments: 0L,
    rx_frames_complete: 0L,
    rx_errors: 0L,
  }
}

///|
/// Register an EoE-capable station.
pub fn EoeSwitch::add_station(
  self : EoeSwitch,
  station : UInt,
  mb_config : @mailbox.MailboxConfig,
) -> Unit {
  // Avoid duplicate registration.
  for ctx in self.stations {
    if ctx.station == station {
      return
    }
  }
  self.stations.push(EoeStationContext::new(station, mb_config))
}

///|
/// Calculate the maximum fragment data size for a given mailbox config.
/// Follows SOEM convention: (mailbox_out_size - overhead) rounded down
/// to 32-byte boundary.
pub fn eoe_max_fragment_size(mb_config : @mailbox.MailboxConfig) -> Int {
  let raw = mb_config.out_size.reinterpret_as_int() - eoe_overhead
  if raw <= 0 {
    return 0
  }
  raw / eoe_fragment_align * eoe_fragment_align
}

///|
/// Fragment and send an Ethernet frame to a specific EoE station.
/// Returns the number of fragments sent.
pub fn[N : @hal.Nic] EoeSwitch::send_frame(
  self : EoeSwitch,
  nic : N,
  station : UInt,
  eth_frame : Bytes,
  timeout : @hal.Duration,
) -> Int raise @hal.EcError {
  let ctx = self.find_station(station)
  guard ctx is Some(ctx) else {
    raise @hal.EcError::MailboxProtocol(
      "EoE station not registered: " + station.reinterpret_as_int().to_string(),
    )
  }
  let max_frag = eoe_max_fragment_size(ctx.mb_config)
  if max_frag <= 0 {
    raise @hal.EcError::MailboxProtocol("EoE mailbox too small for fragments")
  }
  let frame_number = ctx.next_frame_number()
  let total = eth_frame.length()
  let mut offset = 0
  let mut frag_num = 0U
  while offset < total {
    let remaining = total - offset
    let chunk_size = if remaining > max_frag { max_frag } else { remaining }
    let last = offset + chunk_size >= total
    let data = Bytes::makei(chunk_size, fn(i) { eth_frame[offset + i] })
    let frame_offset = (offset / eoe_fragment_align).reinterpret_as_uint()
    let counter = ctx.next_counter()
    let mbx_frame = @mailbox.encode_eoe_fragment(
      counter, 0U, last, frag_num, frame_offset, frame_number, data,
    )
    @protocol.mailbox_send(nic, ctx.station, ctx.mb_config, mbx_frame, timeout)
    self.tx_fragments = self.tx_fragments + 1L
    offset = offset + chunk_size
    frag_num = frag_num + 1U
  }
  frag_num.reinterpret_as_int()
}

///|
/// Process a received raw mailbox frame as an EoE response.
/// If a complete Ethernet frame is reassembled, it is placed in the rx_queue.
/// Returns true if a complete frame was produced.
pub fn EoeSwitch::process_received(
  self : EoeSwitch,
  station : UInt,
  frame : Bytes,
) -> Bool {
  let response = @mailbox.decode_eoe_response(frame) catch {
    _ => {
      self.rx_errors = self.rx_errors + 1L
      return false
    }
  }
  match response {
    @mailbox.EoeFragment(
      frame_type=@mailbox.FragData,
      last_fragment~,
      frag_number~,
      frame_number~,
      data~,
      ..
    ) => {
      self.rx_fragments = self.rx_fragments + 1L
      let ctx = self.find_station(station)
      guard ctx is Some(ctx) else {
        self.rx_errors = self.rx_errors + 1L
        return false
      }
      let buf = ctx.get_reassembly(frame_number)
      let complete = buf.insert(frag_number, last_fragment, data)
      if complete {
        let assembled = buf.assemble()
        ctx.clear_reassembly(frame_number)
        self.rx_frames_complete = self.rx_frames_complete + 1L
        self.rx_queue.push(EoeReceivedFrame::{ station, data: assembled })
        true
      } else {
        false
      }
    }
    _ => false
  }
}

///|
/// Drain all completed frames from the receive queue.
pub fn EoeSwitch::drain_rx(self : EoeSwitch) -> Array[EoeReceivedFrame] {
  let result : Array[EoeReceivedFrame] = []
  while self.rx_queue.length() > 0 {
    // pop from front
    guard self.rx_queue.pop() is Some(f) else { break }
    result.push(f)
  }
  result
}

///|
/// Poll all registered EoE stations for incoming mailbox data.
/// Returns the number of complete Ethernet frames reassembled this cycle.
pub fn[N : @hal.Nic] EoeSwitch::poll(
  self : EoeSwitch,
  nic : N,
  timeout : @hal.Duration,
) -> Int {
  let mut complete = 0
  for ctx in self.stations {
    let has_data = @protocol.mailbox_poll(
      nic,
      ctx.station,
      ctx.mb_config,
      timeout,
    ) catch {
      _ => false
    }
    if has_data {
      let frame = @protocol.mailbox_recv(
        nic,
        ctx.station,
        ctx.mb_config,
        timeout,
        max_polls=1,
      ) catch {
        _ => continue
      }
      if self.process_received(ctx.station, frame) {
        complete = complete + 1
      }
    }
  }
  complete
}

///|
/// Send a Set IP parameters request to an EoE station.
pub fn[N : @hal.Nic] EoeSwitch::set_ip(
  self : EoeSwitch,
  nic : N,
  station : UInt,
  ip : Bytes,
  subnet : Bytes,
  gateway : Bytes,
  timeout : @hal.Duration,
) -> @mailbox.EoeResponse raise @hal.EcError {
  let ctx = self.find_station(station)
  guard ctx is Some(ctx) else {
    raise @hal.EcError::MailboxProtocol(
      "EoE station not registered: " + station.reinterpret_as_int().to_string(),
    )
  }
  let counter = ctx.next_counter()
  let req = @mailbox.encode_eoe_set_ip_req(counter, 0U, ip, subnet, gateway)
  let resp = @protocol.mailbox_exchange(
    nic,
    ctx.station,
    ctx.mb_config,
    @mailbox.Rmsm::new(),
    req,
    timeout,
  )
  @mailbox.decode_eoe_response(resp)
}

///|
/// Send a Get IP parameters request to an EoE station.
pub fn[N : @hal.Nic] EoeSwitch::get_ip(
  self : EoeSwitch,
  nic : N,
  station : UInt,
  timeout : @hal.Duration,
) -> @mailbox.EoeResponse raise @hal.EcError {
  let ctx = self.find_station(station)
  guard ctx is Some(ctx) else {
    raise @hal.EcError::MailboxProtocol(
      "EoE station not registered: " + station.reinterpret_as_int().to_string(),
    )
  }
  let counter = ctx.next_counter()
  let req = @mailbox.encode_eoe_get_ip_req(counter, 0U)
  let resp = @protocol.mailbox_exchange(
    nic,
    ctx.station,
    ctx.mb_config,
    @mailbox.Rmsm::new(),
    req,
    timeout,
  )
  @mailbox.decode_eoe_response(resp)
}

///|
/// Get EoE switch telemetry as JSON.
pub fn EoeSwitch::to_json(self : EoeSwitch) -> Json {
  {
    "station_count": Json::number(self.stations.length().to_double()),
    "tx_fragments": Json::number(self.tx_fragments.to_double()),
    "rx_fragments": Json::number(self.rx_fragments.to_double()),
    "rx_frames_complete": Json::number(self.rx_frames_complete.to_double()),
    "rx_errors": Json::number(self.rx_errors.to_double()),
    "rx_queue_depth": Json::number(self.rx_queue.length().to_double()),
  }
  |> Json::object
}

///|
/// Format EoE switch status as human-readable text.
pub fn EoeSwitch::format_text(self : EoeSwitch) -> String {
  let buf = @buffer.new(size_hint=256)
  buf.write_string("EoE Virtual Switch\n")
  buf.write_string("  Stations: ")
  buf.write_string(self.stations.length().to_string())
  buf.write_string("\n  TX fragments: ")
  buf.write_string(self.tx_fragments.to_string())
  buf.write_string("\n  RX fragments: ")
  buf.write_string(self.rx_fragments.to_string())
  buf.write_string("\n  RX complete frames: ")
  buf.write_string(self.rx_frames_complete.to_string())
  buf.write_string("\n  RX errors: ")
  buf.write_string(self.rx_errors.to_string())
  buf.write_string("\n  RX queue depth: ")
  buf.write_string(self.rx_queue.length().to_string())
  buf.write_string("\n")
  for ctx in self.stations {
    buf.write_string("  Station 0x")
    buf.write_string(uint_to_hex(ctx.station))
    buf.write_string(": tx_frame#=")
    buf.write_string(ctx.tx_frame_number.reinterpret_as_int().to_string())
    buf.write_string(" mb_counter=")
    buf.write_string(ctx.mb_counter.to_int().to_string())
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
fn EoeSwitch::find_station(
  self : EoeSwitch,
  station : UInt,
) -> EoeStationContext? {
  for ctx in self.stations {
    if ctx.station == station {
      return Some(ctx)
    }
  }
  None
}

///|
/// Format a UInt as a hex string (no 0x prefix).
fn uint_to_hex(v : UInt) -> String {
  if v == 0U {
    return "0"
  }
  let digits = "0123456789abcdef".to_array()
  let buf = @buffer.new(size_hint=8)
  let mut val = v
  let chars : Array[Char] = []
  while val > 0U {
    let nibble = (val & 0xFU).reinterpret_as_int()
    chars.push(digits[nibble])
    val = val >> 4
  }
  // Reverse
  let len = chars.length()
  for i = len - 1; i >= 0; i = i - 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}
