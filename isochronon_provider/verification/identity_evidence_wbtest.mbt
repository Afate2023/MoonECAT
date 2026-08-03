///|
test "tshark projection preserves an empty final protocol data column" {
  let lines = try! tshark_projection_lines(
    b"1\t0\t60\t60\t1.0\tff:ff:ff:ff:ff:ff\tc8:ff:bf:03:53:af\t0x88a4\t0x07\t0x0000\t0x0000\t1\t\r\n",
  )
  @debug.assert_eq(lines.length(), 1)
  let fields = lines[0].split("\t").to_array()
  @debug.assert_eq(fields.length(), identity_tshark_fields().length())
  @debug.assert_eq(fields[12], "")
}

///|
test "tshark projection must exactly match the decoded EtherCAT frame" {
  let frame : @protocol.EcFrame = {
    dst_mac: FixedArray::make(6, b'\xff'),
    src_mac: [b'\xc8', b'\xff', b'\xbf', b'\x03', b'\x53', b'\xaf'],
    pdus: [
      {
        header: {
          command: @protocol.APWR,
          index: b'\x2a',
          address: 0x05000000U,
          len_flags: 1U,
          irq: 0U,
        },
        data: b"\x02",
        wkc: 0U,
      },
    ],
  }
  let fields = "1\t0\t60\t60\t1.0\tff:ff:ff:ff:ff:ff\tc8:ff:bf:03:53:af\t0x88a4\t0x02\t0x0000\t0x0500\t1\t02"
    .split("\t")
    .to_array()
  @debug.assert_eq(
    tshark_projection_matches_frame(fields, frame.encode()),
    true,
  )
  let register_decoded = fields.copy()
  register_decoded[12] = ""[:]
  @debug.assert_eq(
    tshark_projection_matches_frame(register_decoded, frame.encode()),
    true,
  )
  let wrong_data = fields.copy()
  wrong_data[12] = "03"[:]
  @debug.assert_eq(
    tshark_projection_matches_frame(wrong_data, frame.encode()),
    false,
  )
  let tampered = fields.copy()
  tampered[10] = "0x0501"[:]
  @debug.assert_eq(
    tshark_projection_matches_frame(tampered, frame.encode()),
    false,
  )
}
