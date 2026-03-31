///|
/// ZeroCopyNic defines the zero-allocation network interface contract.
///
/// Unlike `Nic` which allocates Bytes on every recv, ZeroCopyNic operates
/// on pre-allocated FramePool slots. The hot path has zero GC allocations.
///
/// Platform backends:
/// - Windows Npcap: FramePool in MoonBit heap, pcap_sendpacket via #borrow
/// - Linux Raw Socket: FramePool in MoonBit heap, send/recv via #borrow
/// - Linux AF_XDP: FramePool backed by UMEM shared memory
/// - Embedded MCU: FramePool mapped to DMA descriptor ring in .DMA_SRAM
pub(open) trait ZeroCopyNic {
  /// Open a network interface by name, with an associated frame pool.
  open_(String, FramePool) -> Self raise EcError
  /// Acquire a TX frame slot from the pool (zero allocation).
  acquire_tx(Self) -> FrameRef raise EcError
  /// Get the writable buffer for a TX frame slot.
  tx_buffer(Self, FrameRef) -> FixedArray[Byte]
  /// Submit a filled frame for sending. The frame is consumed.
  submit(Self, FrameRef, length~ : Int) -> Unit raise EcError
  /// Receive a frame into a pre-allocated RX slot (zero allocation).
  recv(Self, timeout~ : Duration) -> FrameRef raise EcError
  /// Get the read buffer for a received frame.
  rx_buffer(Self, FrameRef) -> FixedArray[Byte]
  /// Get the data length of a received frame.
  rx_length(Self, FrameRef) -> Int
  /// Release a frame slot back to the pool.
  release(Self, FrameRef) -> Unit
  /// Close the network interface and release all resources.
  close(Self) -> Unit
}

///|
/// MutableProcessImage uses FixedArray[Byte] for in-place read/write,
/// eliminating per-cycle Bytes allocation in the PDO hot path.
pub(all) struct MutableProcessImage {
  outputs : FixedArray[Byte]
  inputs : FixedArray[Byte]
  output_size : Int
  input_size : Int
} derive(Show)

///|
/// Create a new MutableProcessImage with pre-allocated buffers.
pub fn MutableProcessImage::new(
  output_size : Int,
  input_size : Int
) -> MutableProcessImage {
  {
    outputs: FixedArray::make(output_size, b'\x00'),
    inputs: FixedArray::make(input_size, b'\x00'),
    output_size,
    input_size,
  }
}

///|
/// Zero out inputs buffer (called before receiving new PDO data).
pub fn MutableProcessImage::clear_inputs(self : MutableProcessImage) -> Unit {
  for i = 0; i < self.input_size; i = i + 1 {
    self.inputs[i] = b'\x00'
  }
}
