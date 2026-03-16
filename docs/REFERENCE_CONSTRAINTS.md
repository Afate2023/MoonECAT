# Reference Constraints To Tests

This document turns reference callflow analysis into executable constraints and acceptance checks.
It is intended to be updated incrementally as new behavior or regressions are identified.

## Scope

- Reference callflow docs under `src/*-callflow-analysis.md`
- MoonECAT implementation constraints in `protocol/`, `mailbox/`, `runtime/`
- Validation evidence in existing tests

## Mapping Matrix

| Reference topic | Constraint in MoonECAT | Acceptance tests |
|---|---|---|
| ESM transition sequencing and rollback | Transitions follow legal state graph and reject invalid path; failed steps do best-effort rollback | `protocol/protocol_test.mbt`: `transition_through with empty path raises error`; `runtime/runtime_test.mbt`: ESM transition/shutdown path tests |
| State transition timeout policy | Timeout resolution must be deterministic by target state, with override support and default fallback | `protocol/protocol_test.mbt`: `ESM default timeout values by target state`; `ESM timeout policy uses override then default` |
| PDO cyclic exchange in runtime loop | Runtime cycle must account tx/rx/wkc and report stable telemetry under load | `runtime/runtime_test.mbt`: `Free-run: run_cycles executes multiple cycles`; `Pressure: free-run core loop remains stable at high cycle count`; `Pressure: telemetry remains monotonic across different loads` |
| Timeout and link-failure handling | Recv timeout path increments timeout telemetry and continues; link down propagates as error | `runtime/runtime_test.mbt`: `Recovery: run_cycles records RecvTimeout and continues`; `Runtime run_cycle propagates LinkDown on broken NIC` |
| Mailbox and PDO decoupling | Mailbox path failures must not corrupt or block PDO cycle progression | `runtime/runtime_test.mbt`: `Decoupling: mailbox diagnosis failure does not block PDO run loop` |
| Mailbox retry boundary | Retry allowance must stop at configured max retry count | `mailbox/mailbox_test.mbt`: `Rmsm record_timeout allows retries up to max` |
| Scan-time CSA reassignment isolation | Scan must separate current-CSA observation, reassignment planning, and writeback so duplicate/zero addresses can be reallocated without hardcoding policy into the main scan loop | `protocol/protocol_test.mbt`: `discovery - read_station_address_ap via mock`; `runtime/runtime_test.mbt`: `scan preserves unique pre-existing station addresses`; `scan reassigns duplicate or zero station addresses into scan pool` |
| Validation mismatch handling | Discovery/validation mismatch must stop run workflow before cyclic operation | `runtime/runtime_test.mbt`: `run with mock loopback: validation fails when slaves expected but not found` |
| Minimal end-to-end replay path | Scan/validate/run/stop path must succeed on mock backend baseline | `runtime/runtime_test.mbt`: `replay integration minimal flow: scan->validate->run->stop` |

## Update Rule

When adding behavior that was motivated by reference callflow analysis:

1. Add or update one constraint row here.
2. Link at least one executable test proving the constraint.
3. If no test exists yet, add a TODO row and close it in the next commit.
