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

## Documentation

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full architecture
guide, data flow diagrams, testing strategy, common issues, and extension
points.