///|
test "EcError variants display correctly" {
  inspect(@hal.EcError::LinkDown, content="LinkDown")
  inspect(@hal.EcError::SendFailed("test"), content="SendFailed(\"test\")")
  inspect(@hal.EcError::RecvTimeout, content="RecvTimeout")
}

///|
test "Duration and Timestamp construct correctly" {
  let ts = @hal.Timestamp(1000L)
  let dur = @hal.Duration(500L)
  inspect(ts, content="Timestamp(1000)")
  inspect(dur, content="Duration(500)")
}
