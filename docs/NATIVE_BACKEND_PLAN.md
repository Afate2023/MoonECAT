# Native Backend Plan

> **迁移状态（2026-07-02）**：旧 MoonECAT `hal/native/` package 已删除。
> Windows Npcap、Linux raw socket、native zero-copy 和 C stub ownership
> 已迁出 MoonECAT，进入 Isochronon Lockwire native layer 与 provider harness
> seam。本文件保留设计意图和新交付边界，不再描述 MoonECAT 内部包布局。

## 目标

- MoonECAT 保持纯 EtherCAT protocol/runtime stack。
- MoonECAT 不依赖 `mokomoking2501/lockwire`，也不直接拥有 NIC/session C ABI。
- Lockwire 不认识 EtherCAT 协议语义。
- 组合发生在 `fieldbus_core/moonecat_master_harness` 或后续 companion
  provider package：该层把 Lockwire native session wrapper 适配成 MoonECAT
  `@hal.Nic` / `@hal.ZeroCopyNic` / `@hal.Clock`。

## 旧实现去向

| 旧职责 | 旧位置 | 新 owner |
| --- | --- | --- |
| Windows Npcap interface listing/open/send/recv/close | `hal/native/` | Lockwire native session / provider harness |
| Linux raw socket listing/open/send/recv/close | `hal/native/` | Lockwire native session / provider harness |
| native zero-copy NIC wrapper | `hal/native/` | Lockwire FramePool/session wrapper + provider harness |
| C stubs and native target gating | `hal/native/moon.pkg` | Lockwire native packages |
| MoonECAT scan/read-sii/run native CLI entry | `cmd/main` direct native backend | provider harness entry; MoonECAT CLI returns pending handoff |

## MoonECAT 保留面

- `hal/` trait 和 zero-copy data model。
- `hal/mock/` verification backend。
- `protocol/` EtherCAT frame/PDU/ESM/DC/PDO/mailbox transport。
- `mailbox/` SII/ESI/CoE/SDO/FoE/EoE/SoE/RMSM。
- `runtime/` scan/validate/run/diagnosis/replay/monitor/report。
- `cmd/main` mock/replay/virtual CLI and generic runner functions.

## Provider harness 验收

后续 harness 侧 live backend 必须证明：

- driver/session id 来自 Lockwire native catalog。
- 默认不打开 NIC；live open 需要显式 allow gate。
- `list-if` / `scan` / `read-sii` / `run` / `run-zc` 的 live entry 不在
  MoonECAT `cmd/main` 内直接执行。
- MoonECAT `protocol` / `runtime` / `mailbox` 不 import Lockwire。
- live evidence、pcap/tshark、设备互操作和认证结果独立记录，不能用 mock
  或 replay 替代。
