///|
test "EcCommand roundtrip byte conversion" {
  let cmds : Array[@protocol.EcCommand] = [
    APRD,
    APWR,
    APRW,
    FPRD,
    FPWR,
    FPRW,
    BRD,
    BWR,
    BRW,
    LRD,
    LWR,
    LRW,
    ARMW,
    FRMW,
  ]
  for cmd in cmds {
    let b = cmd.to_byte()
    let decoded = @protocol.EcCommand::from_byte(b)
    assert_eq(cmd, decoded)
  }
}

///|
test "EcCommand from_byte invalid raises error" {
  let result = try? @protocol.EcCommand::from_byte(b'\xFF')
  inspect(result, content="Err(InvalidPdu(\"unknown command byte: 255\"))")
}

///|
test "EsmState roundtrip byte conversion" {
  let states : Array[@protocol.EsmState] = [Init, PreOp, SafeOp, Op, Boot]
  for state in states {
    let b = state.to_byte()
    let decoded = @protocol.EsmState::from_byte(b)
    assert_eq(state, decoded)
  }
}

///|
test "EsmState valid transitions" {
  assert_true(
    @protocol.EsmState::Init.can_transition(@protocol.EsmState::PreOp),
  )
  assert_true(
    @protocol.EsmState::PreOp.can_transition(@protocol.EsmState::SafeOp),
  )
  assert_true(@protocol.EsmState::SafeOp.can_transition(@protocol.EsmState::Op))
  assert_true(@protocol.EsmState::Op.can_transition(@protocol.EsmState::SafeOp))
  // Invalid transition
  assert_true(
    not(@protocol.EsmState::Init.can_transition(@protocol.EsmState::Op)),
  )
}
