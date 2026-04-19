///|
/// Shared HIL-facing cycle result and DC state types.

///|
pub(all) struct CycleResult {
  wkc : UInt
  expected_wkc : UInt
  ok : Bool
} derive(Eq, Debug)

///|
pub(all) enum DcState {
  Disabled
  Measuring
  Locked
  Drifting(Int64)
} derive(Debug)
