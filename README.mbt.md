# MoonECAT

A modular EtherCAT master library written in MoonBit, targeting ETG.1500 Class B.

## Installation

When this package is available from your MoonBit package registry or mirror,
run this in your MoonBit project root:

```bash
moon add mokomoking2501/MoonECAT@0.1.0
```

This project targets the native backend by default.

## Packages

MoonECAT provides the following MoonBit packages. To use a package from another
MoonBit project, add it to the `import` field of `moon.pkg`.

| Package | Purpose |
|---------|---------|
| `mokomoking2501/MoonECAT` | Root facade package and package metadata surface |
| `mokomoking2501/MoonECAT/hal` | Platform-neutral HAL contracts, errors, diagnostics, frame pools, zero-copy traits |
| `mokomoking2501/MoonECAT/hal/mock` | Mock loopback, VirtualBus, RecordingNic, ReplayNic, FaultNic, protocol deviation helpers |
| `mokomoking2501/MoonECAT/hal/native` | Windows Npcap and Linux Raw Socket native NIC backends |
| `mokomoking2501/MoonECAT/hal/mcu` | MCU-oriented HAL stubs and event bridge types |
| `mokomoking2501/MoonECAT/protocol` | EtherCAT frame/PDU codec, addressing, discovery, ESM, EEPROM, PDO, DC, mailbox transport |
| `mokomoking2501/MoonECAT/mailbox` | CoE/SDO, FoE, SoE, EoE frames, SII parsing, SM/FMMU mapping, Emergency, MainDevice mailbox session/repeat recovery |
| `mokomoking2501/MoonECAT/runtime` | Scan, validate, run, scheduler, telemetry, monitors, verdicts, diagnosis, ESI/ENI projection |
| `mokomoking2501/MoonECAT/runtime/analysis` | DC jitter, PDO auto-tune, topology health, cycle performance, communication quality analysis |
| `mokomoking2501/MoonECAT/runtime/hil` | HIL cycle hooks, loop export, and HIL task types |
| `mokomoking2501/MoonECAT/runtime/simulation` | Co-simulation adapter, external bridge, drift compensation, multi-rate scheduler, task partitioning |
| `mokomoking2501/MoonECAT/fixtures` | Shared test fixtures and sample frame data |

Runnable and integration packages:

| Package | Purpose |
|---------|---------|
| `cmd/main` | `moonecat` command-line interface |
| `cmd/eni_json` | ENI/ESI XML to JSON converter |
| `plugin/extism` | Extism Wasm plugin boundary and entrypoint skeleton |

## Source Files

Each directory containing a `moon.pkg` file is a MoonBit package. Source file
names are organizational only; imports refer to package paths, not individual
files.

```text
MoonECAT/
├── moon.mod                  # module metadata, version, dependencies, readme
├── moon.pkg                  # root package marker
├── MoonECAT.mbt              # root facade documentation and exports
├── MoonECAT_test.mbt         # root black-box tests
├── MoonECAT_wbtest.mbt       # root white-box tests
├── README.mbt.md             # package readme used by mooncakes-style pages
├── hal/                      # HAL contracts and backend packages
│   ├── hal.mbt
│   ├── error.mbt
│   ├── diagnostic.mbt
│   ├── config.mbt
│   ├── frame_pool.mbt
│   ├── zero_copy.mbt
│   ├── mock/                 # virtual and fault-injection backends
│   ├── native/               # native FFI backends
│   └── mcu/                  # MCU HAL/event bridge
├── protocol/                 # EtherCAT wire protocol and state-machine core
├── mailbox/                  # mailbox protocols, SII, SM/FMMU mapping
├── runtime/                  # master runtime, diagnosis, verification, analysis
│   ├── analysis/             # analysis engine subpackage
│   ├── hil/                  # HIL integration subpackage
│   └── simulation/           # co-simulation subpackage
├── cmd/
│   ├── main/                 # CLI package
│   └── eni_json/             # XML to JSON converter package
├── plugin/extism/            # Extism plugin package
├── fixtures/                 # shared fixture package
├── docs/                     # architecture, backend, safety, and design docs
├── project_workflow/         # roadmap, milestones, backlog, release workflow
├── src/                      # reference-stack callflow analysis notes
├── scripts/                  # local regression and maintenance scripts
├── References/               # local device/configuration references
└── Reference_Project/        # vendored reference implementations for study
```

## Quick Start

```bash
moon run cmd/main      # Show CLI help
moon test              # Run all tests
moon test hal/mock     # Run mock HAL tests only
moon build --target native  # Build native binary
```

## CLI Commands

MoonBit CLI flags belong to `moon run`, so MoonECAT parameters must be placed
after `--`, otherwise flags like `--backend` and `--if` will be consumed by
`moon` itself.

`--backend native` resolves to Windows Npcap when available, otherwise Linux Raw
Socket. Use `native-windows-npcap` or `native-linux-raw` for explicit control.

### Discovery

```bash
# Enumerate available network interfaces
moon run cmd/main list-if -- --backend native --json

# Force Windows Npcap / Linux Raw Socket enumeration
moon run cmd/main list-if -- --backend native-windows-npcap --json
moon run cmd/main list-if -- --backend native-linux-raw --json

# Scan slave topology
moon run cmd/main scan -- --backend native --if <interface>
moon run cmd/main scan -- --backend native --if <interface> --json
```

### Configuration

```bash
# Validate online vs offline configuration
moon run cmd/main validate -- --backend native --if <interface> --eni-json config.json --json

# ESI XML→SII JSON projection
moon run cmd/main esi-sii -- --esi-json sample.esi.json --device-index 0 --json
```

### Diagnostics

```bash
# Read slave SII/EEPROM
moon run cmd/main read-sii -- --backend native --if <interface> --position 0 --json

# Unified diagnostic surface
moon run cmd/main diagnosis -- --backend native --if <interface> --station 4097 --json

# Object dictionary browse (slave)
moon run cmd/main od -- --backend native --if <interface> --station 4097 --json
moon run cmd/main od -- --backend native --if <interface> --station 4097 --index 7187
moon run cmd/main od -- --backend native --if <interface> --station 4097 --index 6656 --subindex 1
moon run cmd/main sdo-read -- --backend native --if <interface> --station 4097 --index 6656 --subindex 1 --cycles 100 --cycle-period-ms 100 --json
moon run cmd/main sdo-read -- --backend native --if <interface> --station 4097 --index 6656 --subindex 1 --cycles 100 --cycle-period-ms 100 --record sdo-read-trace.ndjson
moon run cmd/main sdo-write -- --backend native --if <interface> --station 4097 --index 6656 --subindex 1 --data-hex 2A00 --cycles 100 --cycle-period-ms 100 --json

# Master object dictionary
moon run cmd/main master-od -- --backend native --if <interface> --json

# ESC register dump
moon run cmd/main esc-regs -- --backend native --if <interface> --station 4097 --json

# Expected vs actual register comparison
moon run cmd/main expected-regs -- --backend native --if <interface> --station 4097 --json
```

For `sdo-read --record <path>`, timeout diagnostics print a bounded TX/RX frame
window around each `RecvTimeout`. The NDJSON file retains the complete raw NIC
event stream for offline packet inspection.

### Operation

```bash
# ESM state transition (bus-wide broadcast)
moon run cmd/main state -- --backend native --if <interface> --state safeop

# Per-slave confirmed state transition with stepwise path
moon run cmd/main state -- --backend native --if <interface> --state op --station 4097 --path

# Cyclic PDO exchange
moon run cmd/main run -- --backend native --if <interface> --cycles 1000
moon run cmd/main run -- --backend native --if <interface> --startup-state safeop --shutdown-state none
moon run cmd/main run -- --backend native --if <interface> --until-fault --json --progress-ndjson --output-period-ms 1000

# Zero-copy PDO exchange (FramePool + MutableProcessImage)
moon run cmd/main run-zc -- --backend mock --cycles 1000 --json
moon run cmd/main run-zc -- --backend native --if <interface> --cycles 1000 --pool-capacity 32 --json

# Virtual slave bus from ESI JSON (offline simulation)
moon run cmd/main run-virtual -- --esi-json sample.esi.json --cycles 1000 --json

# Startup sequence tracing
moon run cmd/main startup-trace -- --backend native --if <interface> --station 4097 --esi-json sample.esi.json --device-index 0 --json

# Startup diff analysis
moon run cmd/main startup-diff -- --backend native --if <interface> --station 4097 --esi-json sample.esi.json --device-index 0 --json

# Mailbox resilient layer validation
moon run cmd/main mailbox-readback -- --backend native --if <interface> --station 4097 --esi-json sample.esi.json --device-index 0 --json
```

### Verification

```bash
# Replay from NDJSON trace file and output verdict
moon run cmd/main replay -- --trace session.ndjson --json

# Execute composite verification scenario
moon run cmd/main scenario -- --scenario basic-timeout --cycles 200 --json
```

### Analysis Engine

```bash
# DC jitter profiling
moon run cmd/main jitter-profile -- --trace session.ndjson --period-ns 1000000 --json

# PDO auto-tuning (online parameter identification)
moon run cmd/main auto-tune -- --strategy balanced --json

# Topology health analysis
moon run cmd/main topo-health -- --trace session.ndjson --json

# Cycle performance statistics
moon run cmd/main cycle-perf -- --trace session.ndjson --period-ns 1000000 --json

# Communication quality scoring
moon run cmd/main comm-quality -- --trace session.ndjson --json
```

### ENI/ESI XML Converter

```bash
# Convert ENI XML to JSON
moon run cmd/eni_json -- --input config.xml --output config.json

# Convert ESI XML to JSON
moon run cmd/eni_json -- --input References/sample.xml --kind esi --output sample.esi.json
```

## Common Parameters

| Parameter | Description | Applies to |
|-----------|-------------|------------|
| `--backend <name>` | `mock`, `native`, `native-windows-npcap`, `native-linux-raw` | All |
| `--if <interface>` | Network interface name | Native commands |
| `--json` | Structured JSON output | All |
| `--timeout-ms <n>` | Command timeout in milliseconds | All |
| `--station <addr>` | Target slave configured address | Per-slave commands |
| `--position <n>` | Target slave link position (0-based) | `read-sii` |
| `--cycles <n>` | Operation cycle count | `run`, `run-zc`, `scenario`, `sdo-read`, `sdo-write` |
| `--until-fault` | Run until fault detected | `run` |
| `--progress-ndjson` | Stream NDJSON progress events | `run` |
| `--startup-state <s>` | Startup target ESM state | `run`, `run-zc`, `replay` |
| `--shutdown-state <s>` | Shutdown target or `none` | `run`, `run-zc`, `replay` |
| `--cycle-period-us <n>` | Override cycle period (microseconds) | `run` |
| `--cycle-period-ms <n>` | SDO operation period (milliseconds) | `sdo-read`, `sdo-write` |
| `--data-hex <hex>` | SDO write payload as hexadecimal bytes | `sdo-write` |
| `--record <path>` | Save complete raw NIC events as NDJSON | `run`, `sdo-read` |
| `--output-period-ms <n>` | NDJSON progress output interval | `run` |
| `--pool-capacity <n>` | Zero-copy frame pool capacity | `run-zc` |
| `--trace <path>` | NDJSON trace file path | `replay`, `jitter-profile`, `topo-health`, `cycle-perf`, `comm-quality` |
| `--scenario <name>` | Scenario name | `scenario` |
| `--strategy <name>` | `balanced`, `conservative`, `aggressive` | `auto-tune` |
| `--period-ns <n>` | Analysis period (nanoseconds) | `jitter-profile`, `cycle-perf` |
| `--esi-json <path>` | ESI JSON file for enrichment | `state`, `run`, `startup-*`, `mailbox-readback` |
| `--path` | Use stepwise state transition path | `state` |

## Key Features

- **Multi-backend architecture**: Mock loopback, Windows Npcap, Linux Raw Socket
- **Full ESM lifecycle**: Init → PreOp → SafeOp → Op with per-slave confirmed transitions
- **CoE/SDO**: Upload/download, segmented transfer, complete access, SDO Info Service
- **SII/EEPROM**: Full ETG.2010 category deep-read framework
- **Zero-copy PDO**: FramePool + MutableProcessImage for hot-path allocation elimination
- **Event sourcing**: RecordingNic → ReplayNic deterministic replay
- **Fault injection**: 7 fault types × 5 schedules via FaultNic
- **Monitor/Verdict**: Pass/Warn/Fail/Block verdicts with composable monitor registry
- **Analysis engine**: DC jitter profiling, PDO auto-tuning, topology health, cycle perf, comm quality scoring
- **Distributed Clock**: SYNC0 configuration + FRMW drift compensation + propagation delay
- **ENI/ESI tooling**: XML→JSON converter with unified configuration model
- **VirtualBus**: Multi-slave protocol-level simulation with SDO/Emergency emulation
- **VirtualSlaveTemplate**: ESI JSON → synthesized EEPROM → VirtualSlave pipeline

## Documentation

| Document | Description |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture guide, data flow, testing strategy |
| [docs/BACKEND_RELEASE_MATRIX.md](docs/BACKEND_RELEASE_MATRIX.md) | Release boundaries + environment requirements |
| [docs/NATIVE_FFI_SAFETY.md](docs/NATIVE_FFI_SAFETY.md) | FFI handle lifetime + sanitizer guidance |
| [docs/NATIVE_REAL_STATE_TRANSITION_DESIGN.md](docs/NATIVE_REAL_STATE_TRANSITION_DESIGN.md) | Npcap ESM transition design |
| [docs/ZERO_COPY_HAL_DESIGN.md](docs/ZERO_COPY_HAL_DESIGN.md) | Zero-copy FramePool + ZeroCopyNic design |
| [docs/SII_FULL_READ_DESIGN.md](docs/SII_FULL_READ_DESIGN.md) | SII deep-read category framework |
| [docs/EXTISM_HOST_BOUNDARY.md](docs/EXTISM_HOST_BOUNDARY.md) | Extism plugin host boundary |
| [project_workflow/](project_workflow/) | Integrated roadmap + backlog (L1-L4, P0-P2) |
