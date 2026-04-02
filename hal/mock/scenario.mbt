///|
/// Composite fault scenario orchestration (B-7).
///
/// A Scenario bundles multiple FaultRules with an expected Verdict sequence,
/// enabling declarative verification tests:
///   Scenario {
///     setup: [FaultRule(RecvTimeout, AfterN(50)), FaultRule(WkcCorrupt(1), AtCycle(100))]
///     expected: [Warn at cycle 51, Fail at cycle 100]
///     pass_condition: runtime stops gracefully
///   }

///|
/// ExpectedVerdict records a verdict expected at a specific cycle.
pub(all) struct ExpectedVerdict {
  cycle : Int64
  verdict : @runtime.Verdict
} derive(Eq, Show)

///|
/// ScenarioPassCondition defines when a scenario is considered passed.
pub(all) enum ScenarioPassCondition {
  /// All expected verdicts match and runtime completes normally.
  AllMatch
  /// Runtime stops gracefully within N cycles after the first Fail.
  GracefulStopWithin(Int)
  /// Custom: the final verdict must equal the given severity or lower.
  FinalVerdictAtMost(@runtime.Verdict)
} derive(Show)

///|
/// Scenario describes a complete verification case with fault injection
/// setup, expected verdict timeline, and pass criteria.
pub(all) struct Scenario {
  name : String
  description : String
  rules : Array[FaultRule]
  expected_verdicts : Array[ExpectedVerdict]
  pass_condition : ScenarioPassCondition
} derive(Show)

///|
pub fn Scenario::new(
  name : String,
  description? : String = "",
  pass_condition? : ScenarioPassCondition = AllMatch,
) -> Scenario {
  { name, description, rules: [], expected_verdicts: [], pass_condition }
}

///|
/// Add a fault rule to this scenario.
pub fn Scenario::add_rule(self : Scenario, rule : FaultRule) -> Unit {
  self.rules.push(rule)
}

///|
/// Add an expected verdict at a specific cycle.
pub fn Scenario::expect(
  self : Scenario,
  cycle : Int64,
  verdict : @runtime.Verdict,
) -> Unit {
  self.expected_verdicts.push({ cycle, verdict })
}

///|
/// ObservedVerdict records what actually happened at a cycle.
pub(all) struct ObservedVerdict {
  cycle : Int64
  verdict : @runtime.Verdict
} derive(Eq, Show)

///|
/// ScenarioResult holds the outcome of running a scenario.
pub(all) struct ScenarioResult {
  name : String
  passed : Bool
  expected : Array[ExpectedVerdict]
  observed : Array[ObservedVerdict]
  final_verdict : @runtime.Verdict
  total_cycles : Int64
  stop_reason : String
} derive(Show)

///|
/// Build a FaultInjector from a Scenario's rules.
pub fn Scenario::build_injector(self : Scenario) -> FaultInjector {
  let inj = FaultInjector::new()
  for rule in self.rules {
    inj.add_rule(FaultRule::new(rule.fault, rule.schedule))
  }
  inj
}

///|
/// Evaluate whether the scenario passed based on observed verdicts.
pub fn Scenario::evaluate(
  self : Scenario,
  observed : Array[ObservedVerdict],
  final_verdict : @runtime.Verdict,
  total_cycles : Int64,
  stop_reason : String,
) -> ScenarioResult {
  let passed = match self.pass_condition {
    AllMatch => check_all_match(self.expected_verdicts, observed)
    GracefulStopWithin(n) => check_graceful_stop(observed, n, total_cycles)
    FinalVerdictAtMost(max) => final_verdict.severity() <= max.severity()
  }
  {
    name: self.name,
    passed,
    expected: self.expected_verdicts,
    observed,
    final_verdict,
    total_cycles,
    stop_reason,
  }
}

///|
/// Check that all expected verdicts are present in the observed list.
fn check_all_match(
  expected : Array[ExpectedVerdict],
  observed : Array[ObservedVerdict],
) -> Bool {
  for e in expected {
    let mut found = false
    for o in observed {
      if o.cycle == e.cycle && o.verdict.severity() >= e.verdict.severity() {
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
/// Check that runtime stopped gracefully within N cycles of the first Fail.
fn check_graceful_stop(
  observed : Array[ObservedVerdict],
  max_cycles : Int,
  total_cycles : Int64,
) -> Bool {
  for o in observed {
    match o.verdict {
      @runtime.Fail(_) => {
        let remaining = total_cycles - o.cycle
        return remaining <= max_cycles.to_int64()
      }
      _ => ()
    }
  }
  true
}
