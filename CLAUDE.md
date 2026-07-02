# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

MoonECAT is a modular **EtherCAT master library written in [MoonBit](https://docs.moonbitlang.com)**, targeting ETG.1500 Class B. The build tool is `moon`; module name is `mokomoking2501/MoonECAT` (`moon.mod.json`).

## Commands

```bash
moon check                      # Type-check all packages (this is also the pre-commit hook)
moon test                       # Run all tests
moon test runtime               # Run one package's tests (path relative to module root)
moon test -p mokomoking2501/MoonECAT/runtime -f runtime_test.mbt   # Single file
moon test --update              # Refresh snapshot tests after intended output changes
moon fmt                        # Format all source
moon info                       # Regenerate .mbti interface files
moon build --target native      # Build the native binary
moon run cmd/main --target native <subcommand> -- <args>  # Run the CLI
```

Finishing-touches for any change: run `moon info && moon fmt`, then inspect the `.mbti` diffs. **An empty `.mbti` diff means your change is invisible to external package users** — a safe refactor. `moon test` supports snapshot testing; regenerate with `moon test --update` only when output changes are intended.

### CLI gotchas (read before running `cmd/main`)

- **MoonBit flags belong to `moon`, MoonECAT flags go after `--`.** Without the `--` separator, flags like `--backend` and `--if` are swallowed by `moon run` itself. Example: `moon run cmd/main scan -- --backend native --if eth0 --json`.
- **The CLI still builds only on the native target** (`cmd/main` declares `supported_targets = "+native"`), but live NIC access has moved out of this package. Native backend flags now produce provider-harness pending output/errors; use the Isochronon `fieldbus_core/moonecat_master_harness` delivery path for Lockwire-backed live sessions.
- `--backend native` resolves to Windows Npcap when available, else Linux Raw Socket; use `native-windows-npcap` / `native-linux-raw` to force one. `--backend mock` needs no hardware and is what tests use.

See [README.mbt.md](README.mbt.md) for the full CLI surface (scan/validate/run/run-zc/diagnosis/od/state/replay/scenario/analysis subcommands) and parameter table.

## Architecture

Strict bottom-up layering — **each layer imports only the layers below it**, and every cross-package dependency is declared explicitly in that package's `moon.pkg`:

```
cmd/main, plugin/extism      CLI + Wasm plugin adapter
        │
runtime/                     scan · validate · run · diagnosis · monitor/verdict ·
  + analysis/ hil/ simulation/   topology · config model · startup prep · HIL/co-sim
        │
mailbox/                     SII/ESI parse · FMMU/SM · CoE/SDO · FoE · EoE · SoE · RMSM
        │
protocol/                    Frame · PDU · addressing · ESM · DC · PDO · zero-copy codec
        │
hal/  + mock/ native/ mcu/   Nic / ZeroCopyNic / Clock / FileAccess traits · FramePool
```

The repository root is itself the library package `mokomoking2501/MoonECAT` (`MoonECAT.mbt`, imported as `@lib`). [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) is the authoritative deep reference: per-package API inventory, data-flow diagrams (startup, PDO hot path, diagnosis, HIL), the testing matrix, and a per-package maturity assessment (L1–L4).

### HAL backends

`hal/` defines the traits; `hal/mock/` is the test/verification backend (VirtualBus, fault injection, record→replay, fuzzing, scenarios) used by nearly all tests; `hal/mcu/` is a bare-metal skeleton. The old `hal/native/` package has been removed from MoonECAT; new live NIC work belongs in provider-owned Lockwire session harnesses, not in MoonECAT protocol packages. When the hot path matters, there is a parallel zero-copy lane: `ZeroCopyNic` + `FramePool` + `MutableProcessImage`, and `pdo_exchange_zero_copy` in `protocol/`.

### Native FFI target gating

Do not add native C stubs in MoonECAT. Lockwire owns the NIC/session C ABI surface; MoonECAT stays a protocol/runtime stack that exposes HAL traits and generic runners for provider harnesses.

## MoonBit conventions (project-specific)

- Code is organized in **blocks separated by `///|`**; block order is irrelevant, so refactors can proceed block-by-block.
- Each package has `<name>_test.mbt` (blackbox) and `<name>_wbtest.mbt` (whitebox) test files, plus a generated `pkg.generated.mbti` interface — **regenerate `.mbti` with `moon info`, never hand-edit it**.
- Keep deprecated blocks in a `deprecated.mbt` file per directory.
- Prefer `assert_eq` / `assert_true(x is Pattern(...))` for stable, well-defined results; reserve snapshot tests for recording current behavior.
- For navigation use `moon ide` helpers (`peek-def`, `outline`, `find-references`); the `moonbit-agent-guide` skill (a git submodule at `.github/skills/`) documents them.

## Reference-driven discipline

When you add behavior motivated by a reference implementation's call flow, update [docs/REFERENCE_CONSTRAINTS.md](docs/REFERENCE_CONSTRAINTS.md): add/adjust one constraint row and link at least one executable test that proves it (add a TODO row if the test doesn't exist yet).

## What is NOT project source

These directories are reference material or build artifacts — **do not edit them, and exclude them when searching for project code**:

- `Reference_Project/` — third-party EtherCAT stacks vendored for study (SOEM, ethercrab, gatorcat, IgH ethercat, EtherCAT.NET, CherryECAT) and the MoonBit `async` library.
- `References/` — ETG specification documents (markdown/PDF).
- `src/` — call-flow analysis write-ups (`*-callflow-analysis.md`) and a spec PDF, **not** MoonBit source.
- `.mooncakes/` — vendored MoonBit dependencies; `_build/` — build output.

`scripts/` holds PowerShell helpers for real-device regression and NDJSON trace analysis. `project_workflow/` tracks the roadmap/backlog (file `08_*.md` is the authoritative source for maturity levels and priorities).
