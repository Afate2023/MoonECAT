///|
/// Verdict represents the outcome severity of a runtime monitor check.
/// Mirrors ETG diagnostic severity model.
pub(all) enum Verdict {
  /// All checks passed, no issues.
  Pass
  /// Non-critical observation requiring attention.
  Warn(String)
  /// Critical issue requiring recovery or stop.
  Fail(String)
  /// Fatal condition preventing continued operation.
  Block(String)
} derive(Eq, Debug)

///|
/// MonitorResult binds a named monitor to its verdict.
pub(all) struct MonitorResult {
  name : String
  verdict : Verdict
} derive(Eq, Debug)

///|
pub fn Verdict::severity(self : Verdict) -> Int {
  match self {
    Pass => 0
    Warn(_) => 1
    Fail(_) => 2
    Block(_) => 3
  }
}

///|
pub fn Verdict::is_passing(self : Verdict) -> Bool {
  self is (Pass | Warn(_))
}

///|
/// Compute the worst verdict from a set of monitor results.
pub fn worst_verdict(results : Array[MonitorResult]) -> Verdict {
  let mut worst : Verdict = Pass
  for r in results {
    if r.verdict.severity() > worst.severity() {
      worst = r.verdict
    }
  }
  worst
}
