# MoonECAT

A modular EtherCAT master library written in MoonBit, targeting ETG.1500 Class B.

## Package Structure

| Package | Layer | Description |
|---------|-------|-------------|
| `hal/` | Platform HAL | Network send/recv, timing, scheduling traits; FramePool/ZeroCopyNic |
| `hal/mock/` | Platform HAL | Mock loopback, VirtualBus, RecordingNic, ReplayNic, FaultNic |
| `hal/native/` | Platform HAL | Windows Npcap + Linux Raw Socket native backends |
| `hal/mcu/` | Platform HAL | MCU bare-metal HAL stubs (RZ/N2L, HPM6E00) |
| `protocol/` | Protocol Core | Frame/PDU codec, ESM, PDO, zero-copy codec, addressing |
| `mailbox/` | Mailbox & Config | CoE/SDO, SII/ESI parsing, FMMU/SM, RMSM, Emergency |
| `runtime/` | Runtime | Scheduler, PDO loop, telemetry, monitors, verdicts, analysis engine |
| `cmd/main/` | CLI | `moonecat` command-line interface |
| `cmd/eni_json/` | Tool | ENI/ESI XML→JSON converter |
| `plugin/extism/` | Plugin | Extism Wasm plugin skeleton |
| `fixtures/` | Test Data | Shared test fixtures and sample frames |

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

# Master object dictionary
moon run cmd/main master-od -- --backend native --if <interface> --json

# ESC register dump
moon run cmd/main esc-regs -- --backend native --if <interface> --station 4097 --json

# Expected vs actual register comparison
moon run cmd/main expected-regs -- --backend native --if <interface> --station 4097 --json
```

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
| `--cycles <n>` | PDO cycle count | `run`, `run-zc`, `scenario` |
| `--until-fault` | Run until fault detected | `run` |
| `--progress-ndjson` | Stream NDJSON progress events | `run` |
| `--startup-state <s>` | Startup target ESM state | `run`, `run-zc`, `replay` |
| `--shutdown-state <s>` | Shutdown target or `none` | `run`, `run-zc`, `replay` |
| `--cycle-period-us <n>` | Override cycle period (microseconds) | `run` |
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