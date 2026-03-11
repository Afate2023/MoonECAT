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
```

`list-if --json` returns a structured object with `backend` and `interfaces`.
Each interface entry includes a stable `name` plus backend-specific metadata such
as `description`, `loopback`, or `index`.

`--backend native` resolves to Windows Npcap when available, otherwise Linux Raw
Socket when available. Use the explicit backend names when you need predictable
cross-machine scripts.

`read-sii` currently performs a minimal online SII read for one slave position
via the native backend and reports the parsed header, General category, string
table, and discovered category list. Use `--position` to select the slave index
and `--words` to control the EEPROM word window to read.

MoonBit CLI flags belong to `moon run`, so MoonECAT parameters must be placed
after `--`, otherwise flags like `--backend` and `--if` will be consumed by
`moon` itself.

## Documentation

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full architecture
guide, data flow diagrams, testing strategy, common issues, and extension
points. See [docs/BACKEND_RELEASE_MATRIX.md](docs/BACKEND_RELEASE_MATRIX.md)
for the current Native CLI / Native Library / Extism Plugin release boundaries,
environment requirements, and smoke commands.