///|
/// Maximum number of PDUs that can fit in a single Ethernet frame.
/// Conservative estimate based on max frame size and minimum PDU overhead.
pub let max_pdus_per_frame : Int = 15

///|
/// FrameBuilder accumulates PDUs and builds frames efficiently.
/// Uses a running index counter for PDU correlation.
pub(all) struct FrameBuilder {
  mut next_index : Int
  pending : Array[Pdu]
  mut pending_size : Int
} derive(Show)

///|
/// Create a new FrameBuilder.
pub fn FrameBuilder::new() -> FrameBuilder {
  { next_index: 0, pending: [], pending_size: 0 }
}

///|
/// Reset the builder for a new cycle, keeping the index counter.
pub fn FrameBuilder::reset(self : FrameBuilder) -> Unit {
  self.pending.clear()
  self.pending_size = 0
}

///|
/// Calculate whether adding a PDU with the given data length would exceed frame limits.
fn FrameBuilder::would_exceed(self : FrameBuilder, data_len : Int) -> Bool {
  let new_size = ethernet_header_len +
    ecat_header_len +
    self.pending_size +
    pdu_header_len +
    data_len +
    wkc_len
  new_size > @hal.max_frame_size || self.pending.length() >= max_pdus_per_frame
}

///|
/// Add a PDU to the pending list. Returns the assigned index for correlation.
/// Raises ConfigError if frame capacity would be exceeded.
pub fn FrameBuilder::add(
  self : FrameBuilder,
  command : EcCommand,
  address : UInt,
  data : Bytes,
) -> Byte raise @hal.EcError {
  if self.would_exceed(data.length()) {
    raise @hal.EcError::Internal("frame capacity exceeded")
  }
  let index = (self.next_index % 256).to_byte()
  self.next_index = self.next_index + 1
  let len_flags = data.length().reinterpret_as_uint() & 0x7FFU
  self.pending.push({
    header: { command, index, address, len_flags, irq: 0U },
    data,
    wkc: 0U,
  })
  self.pending_size = self.pending_size +
    pdu_header_len +
    data.length() +
    wkc_len
  index
}

///|
/// Build and return the assembled EcFrame from pending PDUs.
/// Resets the builder afterward.
pub fn FrameBuilder::build(self : FrameBuilder) -> EcFrame {
  let frame : EcFrame = {
    dst_mac: broadcast_mac,
    src_mac: default_master_mac,
    pdus: self.pending.copy(),
  }
  self.reset()
  frame
}

///|
/// Return the number of pending PDUs.
pub fn FrameBuilder::length(self : FrameBuilder) -> Int {
  self.pending.length()
}

///|
/// Check if the builder has no pending PDUs.
pub fn FrameBuilder::is_empty(self : FrameBuilder) -> Bool {
  self.pending.is_empty()
}

///|
/// Find a PDU in a decoded response frame by its index byte.
pub fn find_pdu_by_index(frame : EcFrame, index : Byte) -> Pdu? {
  for pdu in frame.pdus {
    if pdu.header.index == index {
      return Some(pdu)
    }
  }
  None
}
