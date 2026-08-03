///|
test "external consumer uses only the MoonECAT root facade" {
  let binding = try! build_external_binding()
  @debug.assert_eq(binding.profile_pin().vendor_id(), 0x5566U)
  @debug.assert_eq(binding.profile_pin().product_code(), 32U)
  @debug.assert_eq(binding.profile_pin().revision(), 1U)
  @debug.assert_eq(binding.profile_pin().serial(), None)
  @debug.assert_eq(binding.physical_position(), 0)
  @debug.assert_eq(binding.digest().length(), 64)
}
