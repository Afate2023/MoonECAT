# Extism Host Boundary

This document defines the host/plugin boundary for running MoonECAT as an Extism plugin.
Scope is boundary design and constraints only; concrete plugin wiring is intentionally deferred.

## Goals

- Reuse existing library entrypoints (`scan`, `validate`, `run`) without duplicating protocol logic.
- Keep `protocol/`, `mailbox/`, and `runtime/` independent from Extism-specific APIs.
- Restrict host interaction to HAL-equivalent capabilities: NIC, time, and optional file I/O.

## Non-goals

- No direct raw-socket implementation inside plugin code.
- No direct coupling from protocol code to Extism PDK APIs.
- No new state machine semantics; ESM/PDO/mailbox behavior must stay identical to native path.

## Layering Rule

- Plugin adapter layer: translates Extism calls to MoonECAT library calls.
- HAL adapter layer: implements `@hal.Nic`/`@hal.Clock`/`@hal.FileAccess` semantics through host functions.
- Core layers (`protocol`, `mailbox`, `runtime`): unchanged and unaware of Extism.

## Host Capability Contract

The host must provide these operations to the plugin adapter:

- `nic_open(name: String) -> handle`
- `nic_send(handle, frame: Bytes) -> sent_len`
- `nic_recv(handle, timeout_ns: Int64) -> Bytes`
- `nic_close(handle) -> Unit`
- `clock_now_ns() -> Int64`
- `clock_sleep_ns(duration_ns: Int64) -> Unit`
- `read_file(path: String) -> Bytes` (optional)
- `write_file(path: String, data: Bytes) -> Unit` (optional)

All timeout values use nanoseconds to match `@hal.Duration(Int64)`.

## Data Boundary

- Input/output payloads across host boundary should be bytes or JSON text only.
- Plugin entrypoints should accept/return serialized request/response envelopes.
- Large cyclic data should be exchanged through host-managed shared memory buffers where possible.

## Error Boundary

- Internal errors remain MoonECAT `EcError` categories.
- Plugin responses should map errors to stable string codes plus detail message.
- Timeout, WKC mismatch, and ESM transition failures must preserve their original category semantics.

## API Stability Constraint

- Public library APIs in `runtime/` stay primary and stable.
- Extism adapter can evolve independently as long as it calls stable library APIs.
- Any future adapter-only helpers should live outside `protocol/` and `mailbox/` packages.

## Validation Checklist For Future Adapter

- `scan` path: host NIC open/send/recv/close roundtrip works.
- `validate` path: identity and identification checks are unchanged from native execution.
- `run` path: timeout behavior and telemetry fields match native semantics.
- Error mapping: `RecvTimeout`, `UnexpectedWkc`, `EsmTransitionFailed` each map to distinct error codes.
