///|
test "fixtures expose minimal EtherCAT nop frame and identities" {
  let frame = minimal_nop_frame()
  assert_eq(frame.length(), 28)
  assert_true(frame[0] == b'\xFF' && frame[5] == b'\xFF')
  let ek1100 = sample_ek1100_identity()
  assert_eq(ek1100.vendor_id, 0x2U)
  assert_eq(ek1100.product_code, 0x44C2C52U)
}
