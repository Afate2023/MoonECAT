///|
/// Severity level for diagnostic events.
pub(all) enum Severity {
  Debug
  Info
  Warn
  Error
} derive(Eq, Debug)

///|
/// DiagnosticEvent represents a structured event emitted during operation.
pub(all) struct DiagnosticEvent {
  timestamp : Timestamp
  severity : Severity
  source : String
  message : String
} derive(Debug)

///|
pub fn DiagnosticEvent::new(
  timestamp : Timestamp,
  severity : Severity,
  source : String,
  message : String,
) -> DiagnosticEvent {
  { timestamp, severity, source, message }
}

///|
/// DiagnosticSink receives diagnostic events from the stack.
pub(open) trait DiagnosticSink {
  /// Emit a diagnostic event.
  emit(Self, DiagnosticEvent) -> Unit
}
