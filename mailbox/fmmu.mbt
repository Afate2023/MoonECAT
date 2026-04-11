///|
/// FMMU (Fieldbus Memory Management Unit) configuration entry.
pub(all) struct FmmuConfig {
  logical_start : UInt
  length : UInt
  logical_start_bit : Byte
  logical_end_bit : Byte
  physical_start : UInt
  physical_start_bit : Byte
  direction : FmmuDirection
  activate : Bool
} derive(Eq, Debug)

///|
pub(all) enum FmmuDirection {
  Outputs
  Inputs
  MailboxState
  DynamicOutputs
  DynamicInputs
} derive(Eq, Debug)

///|
/// SyncManager (SM) configuration entry.
pub(all) struct SmConfig {
  physical_start : UInt
  length : UInt
  control : Byte
  status : Byte
  activate : Byte
  sm_type : SmType
} derive(Eq, Debug)

///|
pub(all) enum SmType {
  MailboxOut
  MailboxIn
  ProcessDataOut
  ProcessDataIn
  DynamicProcessDataOut
  DynamicProcessDataIn
  Unused
} derive(Eq, Debug)
