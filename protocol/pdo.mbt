///|
/// PDO (Process Data Object) runtime loop.
/// Manages the cyclic exchange of process data between master and slaves
/// using logical addressing (LRW/LRD/LWR).

///|
/// Process data image: a contiguous byte buffer backing all slave I/O.
pub(all) struct ProcessImage {
  /// Output data (master → slaves).
  mut outputs : Bytes
  /// Input data (slaves → master).
  mut inputs : Bytes
  /// Total output size in bytes.
  output_size : Int
  /// Total input size in bytes.
  input_size : Int
} derive(Debug)

///|
pub fn ProcessImage::new(output_size : Int, input_size : Int) -> ProcessImage {
  {
    outputs: Bytes::new(output_size),
    inputs: Bytes::new(input_size),
    output_size,
    input_size,
  }
}

///|
/// Per-slave PDO mapping entry, describing where in the process image
/// this slave's data lives.
pub(all) struct PdoMapping {
  /// Slave configured address.
  station : UInt
  /// Logical start address for this slave's output data.
  output_logical : UInt
  /// Byte offset into ProcessImage.outputs.
  output_offset : Int
  /// Number of output bytes.
  output_length : Int
  /// Logical start address for this slave's input data.
  input_logical : UInt
  /// Byte offset into ProcessImage.inputs.
  input_offset : Int
  /// Number of input bytes.
  input_length : Int
} derive(Eq, Debug)

///|
/// PDO exchange context: holds the process image and all mappings.
pub(all) struct PdoContext {
  image : ProcessImage
  mappings : Array[PdoMapping]
  /// Logical base address for the entire process data domain.
  logical_base : UInt
  /// Total logical range in bytes (output + input).
  logical_size : Int
  /// When true, use separate LRD + LWR instead of LRW.
  /// Set when any slave in the group sets the SII PreferNotLRW flag.
  mut block_lrw : Bool
} derive(Debug)

///|
/// Result of one PDO exchange, including WKC and datagram IRQ.
pub(all) struct PdoExchangeResult {
  wkc : UInt
  irq : UInt
} derive(Eq, Debug)

///|
/// Build a PdoContext from a list of slave mappings.
/// Each SlaveMapping provides output/input byte counts from FMMU calculation.
pub fn PdoContext::build(
  slave_mappings : Array[(@mailbox.SlaveMapping, UInt)],
  logical_base : UInt,
) -> PdoContext {
  let mappings : Array[PdoMapping] = []
  let mut out_offset = 0
  let mut in_offset = 0
  let mut current_logical = logical_base
  for i = 0; i < slave_mappings.length(); i = i + 1 {
    let (sm, station) = slave_mappings[i]
    let out_len = sm.output_bytes
    let in_len = sm.input_bytes
    let out_logical = current_logical
    current_logical = current_logical + out_len.reinterpret_as_uint()
    let in_logical = current_logical
    current_logical = current_logical + in_len.reinterpret_as_uint()
    mappings.push({
      station,
      output_logical: out_logical,
      output_offset: out_offset,
      output_length: out_len,
      input_logical: in_logical,
      input_offset: in_offset,
      input_length: in_len,
    })
    out_offset = out_offset + out_len
    in_offset = in_offset + in_len
  }
  let total_logical = (current_logical - logical_base).reinterpret_as_int()
  {
    image: ProcessImage::new(out_offset, in_offset),
    mappings,
    logical_base,
    logical_size: total_logical,
    block_lrw: false,
  }
}

///|
/// Execute one PDO cycle: send outputs via LRW, receive inputs.
/// Returns the working counter from the response.
pub fn[N : @hal.Nic] pdo_exchange(
  nic : N,
  ctx : PdoContext,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  pdo_exchange_result(nic, ctx, timeout).wkc
}

///|
/// Execute one PDO cycle and return both WKC and IRQ from the response datagram.
pub fn[N : @hal.Nic] pdo_exchange_result(
  nic : N,
  ctx : PdoContext,
  timeout : @hal.Duration,
) -> PdoExchangeResult raise @hal.EcError {
  if ctx.logical_size <= 0 {
    return { wkc: 0U, irq: 0U }
  }
  if ctx.block_lrw {
    return pdo_exchange_split_result(nic, ctx, timeout)
  }
  // Build the outgoing data: combine outputs + zero-filled input area
  let total = ctx.image.output_size + ctx.image.input_size
  let out_data = Bytes::makei(total, fn(i) {
    if i < ctx.image.output_size {
      ctx.image.outputs[i]
    } else {
      b'\x00'
    }
  })
  let pdu = transact_pdu(
    nic,
    EcCommand::LRW,
    logical_address(ctx.logical_base),
    out_data,
    timeout,
  )
  // Extract input data from the response
  if pdu.data.length() >= total {
    ctx.image.inputs = Bytes::makei(ctx.image.input_size, fn(i) {
      pdu.data[ctx.image.output_size + i]
    })
  }
  { wkc: pdu.wkc, irq: pdu.header.irq }
}

///|
/// Execute one PDO cycle using separate LRD + LWR instead of LRW.
/// Used when any slave in the group sets the PreferNotLRW SII flag.
/// WKC from LWR is doubled to normalise against LRW semantics (per SOEM convention).
fn[N : @hal.Nic] pdo_exchange_split_result(
  nic : N,
  ctx : PdoContext,
  timeout : @hal.Duration,
) -> PdoExchangeResult raise @hal.EcError {
  let mut total_wkc = 0U
  let mut irq = 0U
  // LRD: read inputs
  if ctx.image.input_size > 0 {
    let pdu = transact_pdu(
      nic,
      EcCommand::LRD,
      logical_address(
        ctx.logical_base + ctx.image.output_size.reinterpret_as_uint(),
      ),
      Bytes::new(ctx.image.input_size),
      timeout,
    )
    if pdu.data.length() >= ctx.image.input_size {
      ctx.image.inputs = Bytes::makei(ctx.image.input_size, fn(i) {
        pdu.data[i]
      })
    }
    total_wkc = total_wkc + pdu.wkc
    irq = pdu.header.irq
  }
  // LWR: write outputs
  if ctx.image.output_size > 0 {
    let pdu = transact_pdu(
      nic,
      EcCommand::LWR,
      logical_address(ctx.logical_base),
      ctx.image.outputs,
      timeout,
    )
    // Double LWR WKC to normalise against LRW: LRW increments WKC for
    // both read and write, while LWR increments only for write.
    total_wkc = total_wkc + pdu.wkc * 2U
    if irq == 0U {
      irq = pdu.header.irq
    }
  }
  { wkc: total_wkc, irq }
}

///|
/// Execute a read-only PDO cycle (LRD): fetch inputs without writing outputs.
pub fn[N : @hal.Nic] pdo_read(
  nic : N,
  ctx : PdoContext,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  if ctx.image.input_size <= 0 {
    return 0U
  }
  let pdu = transact_pdu(
    nic,
    EcCommand::LRD,
    logical_address(
      ctx.logical_base + ctx.image.output_size.reinterpret_as_uint(),
    ),
    Bytes::new(ctx.image.input_size),
    timeout,
  )
  if pdu.data.length() >= ctx.image.input_size {
    ctx.image.inputs = Bytes::makei(ctx.image.input_size, fn(i) { pdu.data[i] })
  }
  pdu.wkc
}

///|
/// Execute a write-only PDO cycle (LWR): send outputs without reading.
pub fn[N : @hal.Nic] pdo_write(
  nic : N,
  ctx : PdoContext,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  if ctx.image.output_size <= 0 {
    return 0U
  }
  let pdu = transact_pdu(
    nic,
    EcCommand::LWR,
    logical_address(ctx.logical_base),
    ctx.image.outputs,
    timeout,
  )
  pdu.wkc
}

///|
/// Set output data for a specific slave in the process image.
pub fn PdoContext::set_slave_outputs(
  self : PdoContext,
  station : UInt,
  data : Bytes,
) -> Unit raise @hal.EcError {
  for i = 0; i < self.mappings.length(); i = i + 1 {
    let m = self.mappings[i]
    if m.station == station {
      if data.length() != m.output_length {
        raise @hal.EcError::ConfigMismatch(
          "output data length mismatch: expected " +
          m.output_length.to_string() +
          " got " +
          data.length().to_string(),
        )
      }
      // Copy data into the process image outputs
      let buf = @buffer.new(size_hint=self.image.output_size)
      for j = 0; j < self.image.output_size; j = j + 1 {
        if j >= m.output_offset && j < m.output_offset + m.output_length {
          buf.write_byte(data[j - m.output_offset])
        } else {
          buf.write_byte(self.image.outputs[j])
        }
      }
      self.image.outputs = buf.to_bytes()
      return
    }
  }
  raise @hal.EcError::ConfigMismatch(
    "slave station " + station.to_string() + " not found in mappings",
  )
}

///|
/// Get input data for a specific slave from the process image.
pub fn PdoContext::get_slave_inputs(
  self : PdoContext,
  station : UInt,
) -> Bytes raise @hal.EcError {
  for i = 0; i < self.mappings.length(); i = i + 1 {
    let m = self.mappings[i]
    if m.station == station {
      return Bytes::makei(m.input_length, fn(j) {
        self.image.inputs[m.input_offset + j]
      })
    }
  }
  raise @hal.EcError::ConfigMismatch(
    "slave station " + station.to_string() + " not found in mappings",
  )
}
