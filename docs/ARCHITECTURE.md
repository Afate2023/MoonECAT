# MoonECAT Architecture

## Overview

MoonECAT is a modular EtherCAT master library written in
[MoonBit](https://docs.moonbitlang.com), targeting **ETG.1500 Class B**
compliance. It implements the EtherCAT communication stack from raw Ethernet
frames up to cyclic PDO exchange and SDO/CoE transactions.

## Layered Architecture

```
┌──────────────────────────────────────────┐
│              CLI / Library               │  cmd/main, MoonECAT.mbt
├──────────────────────────────────────────┤
│               Runtime                    │  runtime/
│  scan · validate · run · scheduler       │
├──────────────────────────────────────────┤
│          Mailbox & Config                │  mailbox/
│  SII/ESI · FMMU/SM · CoE/SDO            │
├──────────────────────────────────────────┤
│           Protocol Core                  │  protocol/
│  Frame · PDU · Address · ESM · PDO       │
├──────────────────────────────────────────┤
│           Platform HAL                   │  hal/, hal/mock/
│  Nic · Clock · FileAccess · Error        │
└──────────────────────────────────────────┘
```

Each layer depends only on the layers below it. Cross-layer imports are
declared in each package's `moon.pkg` file.

## Package Reference

### `hal/` — Platform Abstraction

- **Traits**: `Nic` (open/send/recv/close), `Clock` (now/sleep),
  `FileAccess` (read_file/write_file).
- **Types**: `Timestamp(Int64)`, `Duration(Int64)`, `NicHandle`.
- **Config**: `MasterConfig` (cycle_us, timeout_us, max_retries),
  `SlaveIdentity` (vendor_id, product_code, revision, serial),
  `SlaveConfig` (position, expected_identity, configured_address).
- **Errors**: `EcError` suberror with variants for link, PDU, ESM,
  mailbox, SDO, SII, config, and internal errors.

### `hal/mock/` — Test Double

- `MockNic`: buffer-based loopback that echoes frames with WKC = 0.
- `MockClock`: deterministic clock starting from epoch 0.

### `protocol/` — EtherCAT Protocol Core

- **Frame codec**: `EtherCatFrame`, `encode`/`decode` for Ethernet-level
  framing with EtherType `0x88A4`.
- **PDU**: `Pdu` struct with command, address, data, working counter.
  Pipeline support for multi-PDU datagrams.
- **Addressing**: `auto_increment_address`, `fixed_position_address`,
  `logical_address` constructors.
- **Transactions**: `transact()` — send frame, receive response, extract PDU.
  Register read/write helpers: `read_register`, `read_register_fp`,
  `write_register`, `write_register_fp`.
- **Discovery**: `count_slaves`, `assign_configured_address`.
- **ESM engine**: `request_state`, `transition_through`,
  `build_transition_path`, `build_shutdown_path`, `broadcast_state`,
  `read_al_status`, `read_al_status_code`.
- **PDO**: `ProcessImage`, `PdoMapping`, `PdoContext::build`,
  `pdo_exchange` (LRW), `pdo_read` (LRD), `pdo_write` (LWR),
  `set_slave_outputs`, `get_slave_inputs`.

### `mailbox/` — Mailbox & Configuration

- **SII**: `sii_read` for SII EEPROM access, `SiiParser` for parsing
  SII category data (general, FMMU, SyncManager, PDO).
- **FMMU/SM**: `FmmuConfig`, `SmConfig`, `SlaveMapping`,
  `SlaveMapping::from_esi` for automatic FMMU/SM configuration.
- **CoE/SDO engine**: `MailboxHeader` encode/decode, `SdoTransaction`
  encode, `decode_sdo_response`, `MailboxCounter` (1–15 cycling),
  `build_sdo_download`, `build_sdo_upload`.

### `runtime/` — Runtime Orchestrator

- **Scheduler**: `RunMode` (FreeRun/DcSync), `RuntimeState`, `Telemetry`.
- **Runtime**: `Runtime::new`, `configure_pdo`, `run_cycle`, `run_cycles`,
  `needs_recovery`, telemetry accessors.
- **Scan command**: `scan()` — discover slaves, assign addresses, read
  identity from hardware registers.
- **Validate command**: `validate()` — compare discovered slaves against
  expected configuration.
- **Run command**: `run()` — full lifecycle: scan → validate → ESM
  transition → PDO cycling → shutdown.

### `cmd/main/` — CLI Entry Point

- `moonecat` binary with `scan`, `validate`, `run` commands.

## Data Flow

### Startup (scan → run)

```
                    ┌─────────┐
  scan()  ─────────►│ MockNic │──► BRD count_slaves
                    │ or real │──► APWR assign_address
                    │   NIC   │──► FPRD read identity
                    └────┬────┘
                         │
  validate() ◄───────────┘ ScanReport
       │
       ▼ ValidateReport (all_ok?)
       │
  broadcast_state(Op) ──────────► All slaves → Operational
       │
  run_cycles() ◄────────────────► LRW pdo_exchange (cyclic)
       │
  broadcast_state(Init) ────────► Shutdown
       │
       ▼ RunReport
```

### PDO Cycle (hot path)

```
  Runtime::run_cycle()
    └─► pdo_exchange(nic, ctx, timeout)
          ├─ encode LRW frame
          ├─ nic.send()
          ├─ nic.recv()
          ├─ decode response
          └─ return WKC
    └─► update telemetry (cycles, wkc_errors)
    └─► check consecutive errors → trigger recovery
```

## Testing Strategy

All tests run via `moon test` with zero external dependencies.

| Category | Approach | Package |
|----------|----------|---------|
| Frame codec | Encode → decode roundtrip | protocol/ |
| PDU pipeline | Multi-PDU build + parse | protocol/ |
| Discovery | Mock loopback + BRD/APWR | protocol/ |
| ESM | Transition path validation | protocol/ |
| SII/ESI | Sample EEPROM binary parse | mailbox/ |
| FMMU/SM | Mapping from ESI data | mailbox/ |
| CoE/SDO | Encode/decode/abort detection | mailbox/ |
| Runtime | State machine, telemetry, recovery | runtime/ |
| Scan/Validate | Constructed ScanReport checks | runtime/ |
| Run | End-to-end with mock NIC | runtime/ |

Test fixtures live in `fixtures/fixtures.mbt` and provide
`minimal_nop_frame()`, `sample_ek1100_identity()`,
`sample_sii_eeprom()`, and `sample_sii_eeprom_with_pdo()`.

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `EcError::RecvTimeout` | NIC recv timed out | Check cable / increase `timeout_us` |
| `EcError::UnexpectedWkc` | Slave not responding | Verify slave count and ESM state |
| `EcError::EsmTransitionFailed` | State change rejected | Read AL status code for detail |
| `EcError::SdoAbort` | SDO request refused | Check abort code per ETG.1000.6 |
| `ConfigMismatch` | Validate found wrong slave | Re-scan or update SlaveConfig |

## Extending MoonECAT

### Adding a new NIC backend

1. Implement the `Nic` trait in a new package (e.g., `hal/linux/`).
2. Provide `open_`, `send`, `recv`, `close` methods.
3. Import your package in `runtime/moon.pkg`.

### Adding a new CoE service

1. Extend `CoeService` enum in `mailbox/coe.mbt`.
2. Add encode/decode logic in `mailbox/coe_engine.mbt`.
3. Add tests in `mailbox/mailbox_test.mbt`.

### Extism / WASM Host Integration

The library compiles to WASM-GC. To integrate with Extism:
- Export `scan`, `validate`, `run` as host-callable functions.
- Pass NIC operations via host function imports.
- This boundary is designed but not yet implemented.

## Build & Run

```bash
moon check          # Type-check all packages
moon test           # Run all tests
moon test --update  # Update snapshot tests
moon fmt            # Format all MoonBit source
moon info           # Regenerate .mbti interface files
moon run cmd/main   # Run the CLI
```
