# MoonECAT Tasks

## Isochronon integration

| Status | ID | Scope | Evidence |
|---|---|---|---|
| Done | AR7M1-MOONECAT-DEVICE-PROFILE-MODEL | Reusable typed ESI projection, closed-world multi-model catalog, optional serial and exact provider device instance binding. | Audit PASS; all-target workspace/package/external-consumer validation; `device_profile/`; `compat/device_profile_consumer/`; `docs/research/ar7m1-device-profile-model.md` |
| Done | AR7M2-MOONECAT-STACK-OWNED-PROVIDER-IDENTITY | Add bounded `isochronon_provider` bus-identity inspection and typed result/effect/assurance boundary without live claims. | Done 2026-08-03：audit PASS；one absolute deadline/single outstanding、current-MAC frame、SII words 8..15、ordered topology/identity strength、typed effect/echo/canonical result、digest-verified assurance decoder、provider capture filter、four no-live fixtures、public `.mbti`/external consumer；all-target/full-workspace validation passed. |

## Protocol primitives

| ID | Task | Status | Evidence |
| --- | --- | --- | --- |
| ECAT-P0-001 | Close the P0 protocol primitive gaps: bounded Mailbox/ERR decoding, Channel U6, CoE service values, independent TX/RX Cnt, local MailboxSession semantics, and two's-complement AP ADP | Done | `docs/research/ethercat-protocol-primitives-audit.md`; merge audit PASS; workspace tests wasm `3092/3092`, wasm-gc `3092/3092`, JS `3093/3093`, native `3255/3255` |
| ECAT-P0-002 | Merge latest `origin/last_fun` protocol work through `7e7fba9` into the Isochronon branch without restoring MoonECAT-owned native transport | Done | `docs/research/last-fun-isochronon-merge-audit.md`; fresh-eyes audit PASS; all-target tests; AP multi-slave fixture fix; temporary capture excluded |

## Deferred integration

| ID | Task | Status | Boundary |
| --- | --- | --- | --- |
| ECAT-P1-001 | Move cyclic SDO/frame-trace helpers from unreachable built-in native CLI code into a stack-owned provider operation | Deferred | Requires Isochronon composition to inject an already-open Lockwire session, run permit, absolute deadline and bounded evidence sink; no MoonECAT native backend |
| PKG-001 | Publish a Lockwire revision containing `capture/pcapng` and re-run isolated `MOON_WORK=off` consumer validation | Blocked | Current registry `mokomoking2501/lockwire@0.1.0` does not expose that package; workspace-local validation passes |
