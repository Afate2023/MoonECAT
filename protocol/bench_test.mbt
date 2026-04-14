///|
/// Benchmark: zero-copy LRW frame encode vs standard EcFrame encode.
test "bench: frame encode — zero-copy vs standard" (b : @bench.T) {
  // Setup: typical LRW with 64-byte process data
  let buf = FixedArray::make(1518, b'\x00')
  let dst_mac : FixedArray[Byte] = [
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  ]
  let src_mac : FixedArray[Byte] = [
    b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
  ]
  let data = FixedArray::make(64, b'\xAA')
  b.bench(name="encode_lrw_zero_copy_64B", fn() {
    b.keep(
      @protocol.encode_lrw_frame_into(
        buf, dst_mac, src_mac, b'\x01', 0x1000U, data, 0, 64,
      ),
    )
  })
  // Standard path
  let pdu : @protocol.Pdu = {
    header: {
      command: LRW,
      index: b'\x01',
      address: 0x1000U,
      len_flags: 64U,
      irq: 0U,
    },
    data: Bytes::make(64, b'\xAA'),
    wkc: 0U,
  }
  let frame : @protocol.EcFrame = { dst_mac, src_mac, pdus: [pdu] }
  b.bench(name="encode_ecframe_standard_64B", fn() { b.keep(frame.encode()) })
}

///|
/// Benchmark: zero-copy decode vs standard EcFrame decode.
test "bench: frame decode — zero-copy vs standard" (b : @bench.T) {
  // Build a realistic LRW response frame for decode
  let buf = FixedArray::make(1518, b'\x00')
  let dst_mac : FixedArray[Byte] = [
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  ]
  let src_mac : FixedArray[Byte] = [
    b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
  ]
  let data = FixedArray::make(64, b'\xBB')
  let frame_len = @protocol.encode_lrw_frame_into(
    buf, dst_mac, src_mac, b'\x01', 0x1000U, data, 0, 64,
  )
  // Set WKC=1 in the response
  buf[frame_len - 2] = b'\x01'
  buf[frame_len - 1] = b'\x00'
  // Zero-copy decode
  let target = FixedArray::make(64, b'\x00')
  b.bench(name="decode_pdu_zero_copy_64B", fn() {
    b.keep(
      @protocol.decode_pdu_response_from(buf, frame_len, target, 0, 64) catch {
        _ => panic()
      },
    )
  })
  // Standard decode (needs Bytes input)
  let frame_bytes = Bytes::makei(frame_len, fn(i) { buf[i] })
  b.bench(name="decode_ecframe_standard_64B", fn() {
    b.keep(@protocol.EcFrame::decode(frame_bytes) catch { _ => panic() })
  })
}

///|
/// Benchmark: zero-copy encode with varying data sizes (8B, 64B, 256B, 1024B).
test "bench: zero-copy encode scaling" (b : @bench.T) {
  let buf = FixedArray::make(1518, b'\x00')
  let dst_mac : FixedArray[Byte] = [
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  ]
  let src_mac : FixedArray[Byte] = [
    b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
  ]
  let sizes = [8, 64, 256, 1024]
  for sz in sizes {
    let data = FixedArray::make(sz, b'\xCC')
    let name = "encode_lrw_zc_" + sz.to_string() + "B"
    b.bench(name~, fn() {
      b.keep(
        @protocol.encode_lrw_frame_into(
          buf, dst_mac, src_mac, b'\x01', 0x1000U, data, 0, sz,
        ),
      )
    })
  }
}

///|
/// Benchmark: encode_pdu_frame_into (general command) vs encode_lrw_frame_into (specialized).
test "bench: general vs specialized encode" (b : @bench.T) {
  let buf = FixedArray::make(1518, b'\x00')
  let dst_mac : FixedArray[Byte] = [
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  ]
  let src_mac : FixedArray[Byte] = [
    b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
  ]
  let data = FixedArray::make(64, b'\xDD')
  b.bench(name="encode_lrw_specialized_64B", fn() {
    b.keep(
      @protocol.encode_lrw_frame_into(
        buf, dst_mac, src_mac, b'\x01', 0x1000U, data, 0, 64,
      ),
    )
  })
  b.bench(name="encode_pdu_general_64B", fn() {
    b.keep(
      @protocol.encode_pdu_frame_into(
        buf,
        dst_mac,
        src_mac,
        LRW,
        b'\x01',
        0x1000U,
        data,
        0,
        64,
      ),
    )
  })
}

///|
/// Benchmark: decode_pdu_wkc_only (minimal parse) vs full decode.
test "bench: WKC-only decode vs full decode" (b : @bench.T) {
  let buf = FixedArray::make(1518, b'\x00')
  let dst_mac : FixedArray[Byte] = [
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  ]
  let src_mac : FixedArray[Byte] = [
    b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
  ]
  let data = FixedArray::make(64, b'\xEE')
  let frame_len = @protocol.encode_lrw_frame_into(
    buf, dst_mac, src_mac, b'\x01', 0x1000U, data, 0, 64,
  )
  buf[frame_len - 2] = b'\x01'
  b.bench(name="decode_wkc_only_64B", fn() {
    b.keep(@protocol.decode_pdu_wkc_only(buf, frame_len) catch { _ => panic() })
  })
  let target = FixedArray::make(64, b'\x00')
  b.bench(name="decode_full_response_64B", fn() {
    b.keep(
      @protocol.decode_pdu_response_from(buf, frame_len, target, 0, 64) catch {
        _ => panic()
      },
    )
  })
}

///|
/// Benchmark: full encode→decode roundtrip (zero-copy path).
test "bench: zero-copy roundtrip" (b : @bench.T) {
  let buf = FixedArray::make(1518, b'\x00')
  let dst_mac : FixedArray[Byte] = [
    b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF', b'\xFF',
  ]
  let src_mac : FixedArray[Byte] = [
    b'\x02', b'\x00', b'\x00', b'\x00', b'\x00', b'\x01',
  ]
  let data = FixedArray::make(64, b'\x42')
  let target = FixedArray::make(64, b'\x00')
  b.bench(name="roundtrip_zc_64B", fn() {
    let len = @protocol.encode_lrw_frame_into(
      buf, dst_mac, src_mac, b'\x01', 0x1000U, data, 0, 64,
    )
    b.keep(
      @protocol.decode_pdu_response_from(buf, len, target, 0, 64) catch {
        _ => panic()
      },
    )
  })
}
