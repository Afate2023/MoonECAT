///|
test "decode_dl_error_counters parses crafted register data" {
  // RX Error Counters: 0x0300–0x0307 (8 bytes: frame+physical per port)
  // Port 0: frame=10, physical=5
  // Port 1: frame=20, physical=15
  // Port 2: frame=0, physical=0
  // Port 3: frame=255, physical=128
  let rx_data = Bytes::from_array([10, 5, 20, 15, 0, 0, 255, 128])
  // Forwarded RX Error + EPU + PDI: 0x0308–0x030D (6 bytes)
  // Fwd Port 0=3, Port 1=7, Port 2=0, Port 3=1, EPU=42, PDI=99
  let fwd_data = Bytes::from_array([3, 7, 0, 1, 42, 99])
  // Lost Link Counters: 0x0310–0x0313 (4 bytes)
  // Port 0=11, Port 1=22, Port 2=0, Port 3=33
  let lost_data = Bytes::from_array([11, 22, 0, 33])
  let counters = decode_dl_error_counters(rx_data, fwd_data, lost_data)
  // Port 0
  assert_eq(counters.ports[0].frame_errors, 10U)
  assert_eq(counters.ports[0].physical_errors, 5U)
  assert_eq(counters.ports[0].forwarded_rx_errors, 3U)
  assert_eq(counters.ports[0].lost_link_count, 11U)
  // Port 1
  assert_eq(counters.ports[1].frame_errors, 20U)
  assert_eq(counters.ports[1].physical_errors, 15U)
  assert_eq(counters.ports[1].forwarded_rx_errors, 7U)
  assert_eq(counters.ports[1].lost_link_count, 22U)
  // Port 2
  assert_eq(counters.ports[2].frame_errors, 0U)
  assert_eq(counters.ports[2].physical_errors, 0U)
  assert_eq(counters.ports[2].forwarded_rx_errors, 0U)
  assert_eq(counters.ports[2].lost_link_count, 0U)
  // Port 3
  assert_eq(counters.ports[3].frame_errors, 255U)
  assert_eq(counters.ports[3].physical_errors, 128U)
  assert_eq(counters.ports[3].forwarded_rx_errors, 1U)
  assert_eq(counters.ports[3].lost_link_count, 33U)
  // Global counters
  assert_eq(counters.ecat_pu_errors, 42U)
  assert_eq(counters.pdi_errors, 99U)
}

///|
test "decode_dl_error_counters handles short data gracefully" {
  // Short/empty data should produce zero counters
  let counters = decode_dl_error_counters(
    Bytes::new(0),
    Bytes::new(0),
    Bytes::new(0),
  )
  for i = 0; i < 4; i = i + 1 {
    assert_eq(counters.ports[i].frame_errors, 0U)
    assert_eq(counters.ports[i].physical_errors, 0U)
    assert_eq(counters.ports[i].forwarded_rx_errors, 0U)
    assert_eq(counters.ports[i].lost_link_count, 0U)
  }
  assert_eq(counters.ecat_pu_errors, 0U)
  assert_eq(counters.pdi_errors, 0U)
}

///|
test "decode_dl_error_counters saturated counters at 0xFF" {
  // All counters at maximum (0xFF = 255, saturation point per ETG.1000.4)
  let rx_data = Bytes::from_array([255, 255, 255, 255, 255, 255, 255, 255])
  let fwd_data = Bytes::from_array([255, 255, 255, 255, 255, 255])
  let lost_data = Bytes::from_array([255, 255, 255, 255])
  let counters = decode_dl_error_counters(rx_data, fwd_data, lost_data)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(counters.ports[i].frame_errors, 255U)
    assert_eq(counters.ports[i].physical_errors, 255U)
    assert_eq(counters.ports[i].forwarded_rx_errors, 255U)
    assert_eq(counters.ports[i].lost_link_count, 255U)
  }
  assert_eq(counters.ecat_pu_errors, 255U)
  assert_eq(counters.pdi_errors, 255U)
}
