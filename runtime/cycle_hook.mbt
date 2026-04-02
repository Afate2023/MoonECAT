///|
/// CycleHook — zero-cost trait for intercepting the runtime cyclic loop.
///
/// Design rationale:
///   - MoonBit open traits monomorphize at compile time → zero vtable overhead
///   - Each hook method has a default no-op semantic; implementors override only
///     what they need
///   - The hook sits between ProcessImage and the Nic layer, enabling:
///       • Pre-cycle output injection (plant model / controller writes)
///       • Post-cycle input observation (data logging / verdict / co-sim)
///       • Cycle-level fault injection (WKC manipulation, frame drop)
///       • Cycle-level breakpoint / single-step support for HIL debugging
///
/// Performance contract:
///   - `on_pre_cycle` and `on_post_cycle` execute inline in the hot path
///   - Implementations MUST be bounded O(1) or O(slave_count)
///   - No heap allocation in the default (NullCycleHook) path

///|
/// CycleSnapshot captures the minimal state exposed to hooks at each cycle boundary.
pub(all) struct CycleSnapshot {
  /// Monotonically increasing cycle counter (from Telemetry.cycles).
  cycle : Int64
  /// The CycleResult from the most recent PDO exchange (post-cycle only).
  result : CycleResult?
  /// Current DC synchronization state.
  dc_state : DcState
  /// Whether the runtime will trigger recovery after this cycle.
  recovery_pending : Bool
} derive(Show)

///|
/// CycleDirective tells the runtime what action to take after a hook returns.
pub(all) enum CycleDirective {
  /// Continue normal execution.
  Continue
  /// Skip this cycle's PDO exchange (pre-cycle only: outputs are not sent).
  SkipCycle
  /// Request immediate graceful stop after this cycle.
  StopGraceful
} derive(Eq, Show)

///|
/// CycleHook — the runtime calls these methods at each cycle boundary.
///
/// Trait methods use `Self` (not `&Self`) following MoonBit trait convention.
/// The runtime passes `CycleSnapshot` by value (16-24 bytes, stack-allocated).
pub(open) trait CycleHook {
  /// Called before PDO exchange. Receives mutable access to ProcessImage
  /// outputs via the PdoContext. Return a directive controlling cycle execution.
  on_pre_cycle(Self, CycleSnapshot, @protocol.PdoContext) -> CycleDirective

  /// Called after PDO exchange with the cycle result. Receives the updated
  /// ProcessImage inputs via PdoContext. Return a directive for the next step.
  on_post_cycle(Self, CycleSnapshot, @protocol.PdoContext) -> CycleDirective

  /// Called when the runtime encounters a fault condition (timeout, WKC error,
  /// DC drift). The hook may log, record, or override recovery behavior.
  on_fault(Self, CycleSnapshot, @hal.EcError) -> CycleDirective
}

///|
/// NullCycleHook — default no-op hook. Compiles to nothing in monomorphized code.
pub struct NullCycleHook {
  _unused : Unit
}

///|
pub fn NullCycleHook::new() -> NullCycleHook {
  { _unused: () }
}

///|
pub impl CycleHook for NullCycleHook with on_pre_cycle(self, _snap, _ctx) {
  ignore(self)
  Continue
}

///|
pub impl CycleHook for NullCycleHook with on_post_cycle(self, _snap, _ctx) {
  ignore(self)
  Continue
}

///|
pub impl CycleHook for NullCycleHook with on_fault(self, _snap, _err) {
  ignore(self)
  Continue
}
