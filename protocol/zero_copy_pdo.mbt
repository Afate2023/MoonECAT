///|
/// Zero-copy PDO exchange functions using ZeroCopyNic and FramePool.
/// These eliminate all per-cycle heap allocation in the real-time hot path.

///|
/// MutablePdoContext combines a MutableProcessImage with PDO mappings
/// for zero-copy exchange. Analogous to PdoContext but uses FixedArray[Byte].
pub(all) struct MutablePdoContext {
  image : @hal.MutableProcessImage
  mappings : Array[PdoMapping]
  logical_base : UInt
  logical_size : Int
} derive(Debug)

///|
/// Build a MutablePdoContext from slave mappings, using pre-allocated buffers.
pub fn MutablePdoContext::build(
  slave_mappings : Array[(@mailbox.SlaveMapping, UInt)],
  logical_base : UInt,
) -> MutablePdoContext {
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
    image: @hal.MutableProcessImage::new(out_offset, in_offset),
    mappings,
    logical_base,
    logical_size: total_logical,
  }
}

///|
/// Set output data for a specific slave in the mutable process image.
pub fn MutablePdoContext::set_slave_outputs(
  self : MutablePdoContext,
  station : UInt,
  data : FixedArray[Byte],
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
      for j = 0; j < m.output_length; j = j + 1 {
        self.image.outputs[m.output_offset + j] = data[j]
      }
      return
    }
  }
  raise @hal.EcError::ConfigMismatch(
    "slave station " + station.to_string() + " not found in mappings",
  )
}

///|
/// Get input data for a specific slave from the mutable process image.
/// Returns a copy as FixedArray[Byte] (one allocation, but only on user request,
/// not on the hot path).
pub fn MutablePdoContext::get_slave_inputs(
  self : MutablePdoContext,
  station : UInt,
) -> FixedArray[Byte] raise @hal.EcError {
  for i = 0; i < self.mappings.length(); i = i + 1 {
    let m = self.mappings[i]
    if m.station == station {
      return FixedArray::makei(m.input_length, fn(j) {
        self.image.inputs[m.input_offset + j]
      })
    }
  }
  raise @hal.EcError::ConfigMismatch(
    "slave station " + station.to_string() + " not found in mappings",
  )
}

///|
/// Zero-copy PDO exchange using ZeroCopyNic.
/// The complete hot-path cycle with zero heap allocation:
///   1. Acquire TX slot from pool (no alloc)
///   2. Encode LRW frame directly into TX buffer (no alloc)
///   3. Submit frame to NIC (no alloc)
///   4. Receive response into RX slot (no alloc)
///   5. Decode response data in-place into MutableProcessImage (no alloc)
///   6. Release RX slot (no alloc)
pub fn[N : @hal.ZeroCopyNic] pdo_exchange_zero_copy(
  nic : N,
  ctx : MutablePdoContext,
  timeout : @hal.Duration,
) -> PdoExchangeResult raise @hal.EcError {
  if ctx.logical_size <= 0 {
    return { wkc: 0U, irq: 0U }
  }
  // 1. Acquire TX slot
  let tx_ref = nic.acquire_tx()
  let tx_buf = nic.tx_buffer(tx_ref)
  // 2. Encode LRW frame: outputs in data area, zeros for input area
  let frame_len = encode_lrw_pdo_frame_into(
    tx_buf,
    broadcast_mac,
    default_master_mac,
    b'\x01', // index
    logical_address(ctx.logical_base),
    ctx.image.outputs,
    ctx.image.output_size,
    ctx.image.input_size,
  )
  // 3. Submit
  nic.submit(tx_ref, length=frame_len)
  // 4. Receive response
  let rx_ref = nic.recv(timeout~)
  let rx_buf = nic.rx_buffer(rx_ref)
  let rx_len = nic.rx_length(rx_ref)
  // 5. Decode response: skip output echo, copy inputs directly into image
  let result = try? decode_pdu_response_slice(
    rx_buf,
    rx_len,
    ctx.image.output_size, // skip output echo bytes
    ctx.image.inputs,
    0,
    ctx.image.input_size,
  )
  // 6. Release RX slot
  nic.release(rx_ref)
  match result {
    Ok((wkc, irq)) => { wkc, irq }
    Err(e) => raise e
  }
}

///|
/// Encode an LRW PDO frame with split output data and zero-filled input area.
/// This is specialized for the PDO exchange pattern where:
///   - First `output_size` bytes come from the outputs array
///   - Next `input_size` bytes are zeros (to be filled by slaves)
/// Returns the total frame length.
fn encode_lrw_pdo_frame_into(
  buf : FixedArray[Byte],
  dst_mac : FixedArray[Byte],
  src_mac : FixedArray[Byte],
  index : Byte,
  logical_addr : UInt,
  outputs : FixedArray[Byte],
  output_size : Int,
  input_size : Int,
) -> Int {
  let data_len = output_size + input_size
  let mut pos = 0
  // Ethernet II header
  for i in 0..<6 {
    buf[pos + i] = dst_mac[i]
  }
  pos = pos + 6
  for i in 0..<6 {
    buf[pos + i] = src_mac[i]
  }
  pos = pos + 6
  buf[pos] = b'\x88'
  buf[pos + 1] = b'\xA4'
  pos = pos + 2
  // EtherCAT header
  let pdu_payload_len = pdu_header_len + data_len + wkc_len
  let ecat_hdr = (pdu_payload_len.reinterpret_as_uint() & 0x7FFU) |
    (ecat_frame_type.reinterpret_as_uint() << 12)
  write_u16_le_fixed(buf, pos, ecat_hdr)
  pos = pos + 2
  // PDU header
  buf[pos] = EcCommand::LRW.to_byte()
  buf[pos + 1] = index
  write_u32_le_fixed(buf, pos + 2, logical_addr)
  let len_flags = data_len.reinterpret_as_uint() & 0x7FFU
  write_u16_le_fixed(buf, pos + 6, len_flags)
  write_u16_le_fixed(buf, pos + 8, 0U) // IRQ
  pos = pos + pdu_header_len
  // Data: outputs then zeros for inputs
  for i = 0; i < output_size; i = i + 1 {
    buf[pos + i] = outputs[i]
  }
  pos = pos + output_size
  for i = 0; i < input_size; i = i + 1 {
    buf[pos + i] = b'\x00'
  }
  pos = pos + input_size
  // WKC = 0
  write_u16_le_fixed(buf, pos, 0U)
  pos = pos + wkc_len
  pos
}

///|
/// Zero-copy read-only PDO cycle (LRD).
pub fn[N : @hal.ZeroCopyNic] pdo_read_zero_copy(
  nic : N,
  ctx : MutablePdoContext,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  if ctx.image.input_size <= 0 {
    return 0U
  }
  let tx_ref = nic.acquire_tx()
  let tx_buf = nic.tx_buffer(tx_ref)
  // For LRD, data payload is all zeros. Use encode_zero_data_frame_into
  // to avoid allocating a zero buffer.
  let frame_len = encode_zero_data_frame_into(
    tx_buf,
    broadcast_mac,
    default_master_mac,
    EcCommand::LRD,
    b'\x01',
    logical_address(
      ctx.logical_base + ctx.image.output_size.reinterpret_as_uint(),
    ),
    ctx.image.input_size,
  )
  nic.submit(tx_ref, length=frame_len)
  let rx_ref = nic.recv(timeout~)
  let rx_buf = nic.rx_buffer(rx_ref)
  let rx_len = nic.rx_length(rx_ref)
  let result = try? decode_pdu_response_from(
    rx_buf,
    rx_len,
    ctx.image.inputs,
    0,
    ctx.image.input_size,
  )
  nic.release(rx_ref)
  match result {
    Ok((wkc, _irq)) => wkc
    Err(e) => raise e
  }
}

///|
/// Zero-copy write-only PDO cycle (LWR).
pub fn[N : @hal.ZeroCopyNic] pdo_write_zero_copy(
  nic : N,
  ctx : MutablePdoContext,
  timeout : @hal.Duration,
) -> UInt raise @hal.EcError {
  if ctx.image.output_size <= 0 {
    return 0U
  }
  let tx_ref = nic.acquire_tx()
  let tx_buf = nic.tx_buffer(tx_ref)
  let frame_len = encode_pdu_frame_into(
    tx_buf,
    broadcast_mac,
    default_master_mac,
    EcCommand::LWR,
    b'\x01',
    logical_address(ctx.logical_base),
    ctx.image.outputs,
    0,
    ctx.image.output_size,
  )
  nic.submit(tx_ref, length=frame_len)
  let rx_ref = nic.recv(timeout~)
  let rx_buf = nic.rx_buffer(rx_ref)
  let rx_len = nic.rx_length(rx_ref)
  // For LWR we only need WKC, discard response data in-place
  let result = try? decode_pdu_wkc_only(rx_buf, rx_len)
  nic.release(rx_ref)
  match result {
    Ok(wkc) => wkc
    Err(e) => raise e
  }
}
