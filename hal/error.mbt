///|
/// EcError represents all error conditions in the MoonECAT stack.
/// Errors are grouped by layer to keep diagnostics clear.
pub(all) suberror EcError {
  // HAL errors
  LinkDown
  SendFailed(String)
  RecvTimeout
  RecvFailed(String)
  // Protocol errors
  InvalidFrame(String)
  InvalidPdu(String)
  UnexpectedWkc(expected~ : Int, actual~ : Int)
  // ESM errors
  EsmTransitionFailed(from~ : String, to~ : String)
  EsmStateError(String)
  // Mailbox errors
  MailboxTimeout
  MailboxProtocol(String)
  SdoAbort(UInt)
  // Config errors
  SiiReadFailed(String)
  EsiParseFailed(String)
  ConfigMismatch(String)
  // General errors
  NotSupported(String)
  Internal(String)
} derive(Debug)
