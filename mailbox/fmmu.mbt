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
} derive(Eq, Show)

///|
pub(all) enum FmmuDirection {
  Outputs
  Inputs
  MailboxState
} derive(Eq, Show)

///|
/// SyncManager (SM) configuration entry.
pub(all) struct SmConfig {
  physical_start : UInt
  length : UInt
  control : Byte
  status : Byte
  enable : Bool
  sm_type : SmType
} derive(Eq, Show)

///|
pub(all) enum SmType {
  MailboxOut
  MailboxIn
  ProcessDataOut
  ProcessDataIn
  Unused
} derive(Eq, Show)
