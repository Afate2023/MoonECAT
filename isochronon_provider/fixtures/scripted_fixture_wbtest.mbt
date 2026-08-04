///|
test "fixture decodes EtherCAT auto-increment ADP as topology position" {
  for position = 0; position < 3; position = position + 1 {
    let address = (@protocol.reg_type << 16) |
      @protocol.auto_increment_address(position.reinterpret_as_uint())
    assert_eq(fixture_auto_increment_position(address), position)
  }
}
