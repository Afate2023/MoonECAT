# MoonECAT

A modular EtherCAT master library written in MoonBit, targeting ETG.1500 Class B.

## Package Structure

| Package | Layer | Description |
|---------|-------|-------------|
| `hal/` | Platform HAL | Network send/recv, timing, scheduling traits |
| `hal/mock/` | Platform HAL | Mock loopback backend for testing |
| `protocol/` | Protocol Core | Frame/PDU codec, ESM state machine, addressing |
| `mailbox/` | Mailbox & Config | CoE/SDO, SII/ESI parsing, FMMU/SM config |
| `runtime/` | Runtime | Scheduler, PDO loop, telemetry |
| `cmd/main/` | CLI | `moonecat` command-line interface |

## Quick Start

```bash
moon run cmd/main      # Run CLI
moon test              # Run all tests
moon test hal/mock     # Run mock HAL tests
```

## CLI Usage

```bash
# Show CLI help text
moon run cmd/main

# Enumerate available interfaces using the native backend selected for this OS
moon run cmd/main list-if -- --backend native

# Enumerate interfaces as structured JSON objects
moon run cmd/main list-if -- --backend native --json

# Force Windows Npcap enumeration
moon run cmd/main list-if -- --backend native-windows-npcap --json

# Force Linux Raw Socket enumeration
moon run cmd/main list-if -- --backend native-linux-raw --json

# Run a scan with the auto-selected native backend
moon run cmd/main scan -- --backend native --if <interface>

# Read a slave SII window and print parsed header/general/categories
moon run cmd/main read-sii -- --backend native --if <interface> --position 0 --words 128

# Read the same SII window as JSON
moon run cmd/main read-sii -- --backend native --if <interface> --position 0 --words 128 --json

# Request a bus-wide EtherCAT state transition
moon run cmd/main state -- --backend native --if <interface> --state safeop

# Request a confirmed per-slave state transition
moon run cmd/main state -- --backend native --if <interface> --state op --station 4097 --path

# Run cyclic exchange but stop at SafeOp first and skip shutdown rollback
moon run cmd/main run -- --backend native --if <interface> --startup-state safeop --shutdown-state none

# Run a real-device until-fault loop with NDJSON progress output
moon run cmd/main run -- --backend native --if <interface> --json --progress-ndjson --until-fault --output-period-ms 1000
```

`list-if --json` returns a structured object with `backend` and `interfaces`.
Each interface entry includes a stable `name` plus backend-specific metadata such
as `description`, `loopback`, or `index`.

`--backend native` resolves to Windows Npcap when available, otherwise Linux Raw
Socket when available. Use the explicit backend names when you need predictable
cross-machine scripts.

`read-sii` currently reads one slave EEPROM window through the native backend
and reports parsed preamble, standard metadata, header, strings, General,
FMMU, SyncManager, DC, PDO, and raw category inventory. Use `--position` to
select the slave index and `--words` to control the EEPROM word window to
read.

`state` exposes EtherCAT AL state changes over the native backend. Use it
without `--station` for a bus-wide broadcast transition, or add `--station`
for per-slave confirmed transitions. Add `--path` to let the CLI build a safe
stepwise path via `Init` when the requested target is not directly reachable.

`run` now accepts `--startup-state` and `--shutdown-state` so Native and Mock
smoke runs can stop at `Init|PreOp|SafeOp|Op|Boot` on entry, and optionally
leave the bus in place by using `--shutdown-state none`. For long-running JSON
consumers, combine `--json --progress-ndjson --until-fault --output-period-ms <n>`
to receive NDJSON progress snapshots without corrupting the final JSON summary.

MoonBit CLI flags belong to `moon run`, so MoonECAT parameters must be placed
after `--`, otherwise flags like `--backend` and `--if` will be consumed by
`moon` itself.

## Documentation

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full architecture
guide, data flow diagrams, testing strategy, common issues, and extension
points. See [docs/BACKEND_RELEASE_MATRIX.md](docs/BACKEND_RELEASE_MATRIX.md)
for the current Native CLI / Native Library / Extism Plugin release boundaries,
environment requirements, and smoke commands. See
[docs/NATIVE_FFI_SAFETY.md](docs/NATIVE_FFI_SAFETY.md) for current Native FFI
ownership notes, handle lifetime rules, and sanitizer validation guidance. See
[docs/NATIVE_REAL_STATE_TRANSITION_DESIGN.md](docs/NATIVE_REAL_STATE_TRANSITION_DESIGN.md)
for the current raw socket completion plan and Npcap real-NIC ESM transition design.

Current Native smoke evidence is split into two layers: Windows Npcap already
has a verified empty-bus `list-if -> scan -> validate -> run` chain plus a real
`state` execution baseline, while the next backlog item is a longer single-link
chain covering `scan -> validate -> state -> diagnosis -> run` on the same NIC
session and recording both empty-bus and single-slave baselines.