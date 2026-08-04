# `last_fun` 协议栈合并审计

审计日期：2026-08-04

## Scope

本任务把 `origin/last_fun` 的最新端点 `7e7fba9` 合入
`isochronon-medium-sixpack`，并保持已经裁决的职责边界：Lockwire 负责网卡、
session、字节传输、capture 和时间；MoonECAT 负责 EtherCAT datagram、Mailbox、
CoE/SDO、PDO、WKC、ESM、DC 等协议语义。

本任务不是 cyclic PDO 实机验证，不产生新的 device/timing/zero-copy/认证 claim。

## Existing Implementation Survey

| 上游提交 | 合入内容 | 处理结论 |
| --- | --- | --- |
| `5ff80e8` | receive-only 补收、cyclic SDO/trace helper、历史 NativeNic 调整和临时 capture | 保留通用协议/helper；不恢复 `hal/native`；排除 3 个 pcapng 与 1 个 NDJSON 临时采集物 |
| `267ceab` | `DatagramIndexSource`、`DatagramSession`、递增/legacy index、runtime/CLI 泛型传播 | 完整合入；同一协议会话只包装一次，失败事务消耗 index，旧 trace 显式使用 fixed-zero legacy session |
| `7e7fba9` | bounded `MailboxFrame`、ERR、Channel U6、CoE service、独立 TX/RX Cnt、local `MailboxSession`、AP ADP 二补数 | 完整合入；同步修复 `isochronon_provider` 多从站 fixture 的 ADP→拓扑位置解码 |

## Abstraction And Interface Proposal

- `DatagramSession[N]` 是 EtherCAT DLPDU session，不属于 Lockwire；Lockwire NIC/
  `LinkSession` 仍只搬运 bytes。
- `MailboxFrame` 只消费 header `Length` 声明的 payload，SyncManager padding 不进入
  应用协议 decoder；通用 ERR 必须先于 CoE/FoE/EoE/SoE 分派。
- built-in `cmd/main --backend native*` 继续 fail closed。cyclic SDO 与 frame trace
  helper 当前只是协议实现，不是 live CLI；后续应迁入 stack-owned provider operation，
  由 Isochronon composition 注入已打开的 Lockwire session、permit、deadline 和 evidence
  sink。
- zero-copy PDO 通道尚未接入 `DatagramSession` index allocator；不得以本次合并声称
  live hot-path zero-copy。

## Merge Resolution

- `moon.mod` 保留 `mokomoking2501/lockwire@0.1.0` 声明并升级
  `moonbitlang/async` 至 `0.19.4`。
- 未恢复 `hal/native`、NativeNic、C stub 或 MoonECAT-owned NIC lifecycle。
- 当前文档从已删除的 `fieldbus_core/moonecat_master_harness` 改为
  `isochronon_provider + Isochronon composition + Lockwire session`。
- README 删除不可执行的 native cyclic SDO 示例，并明确 helper 不是 live claim。
- AP ADP `0x0000/0xFFFF/0xFFFE` 分别解码为位置 `0/1/2`，新增 fixture 白盒测试。
- 上游根目录 capture 合计约 65.8 MiB，未被源码、测试或文档引用，且不符合有界
  evidence/CAS 边界，因此不进入合并结果；原始内容仍可从
  `origin/last_fun:5ff80e8` 恢复。

## Audit Result: PASS

### Findings

- Critical/High/Medium：0。
- Low：`cmd/main/nic_frame_trace.mbt` 与 `sdo_cycle_commands.mbt` 有 6 个 unused
  warning。它们被保留为待迁移的 stack helper，当前无 dispatch/live claim，不阻断
  协议合并。
- Release blocker：`MOON_WORK=off moon check --target all` 无法使用 registry
  `lockwire@0.1.0`，因为该发布版缺少 `capture/pcapng`；workspace local Lockwire 可编译。
  该项属于后续 package publication，不把本次 workspace 合并误判为独立发布闭环。

### Validation Reviewed

- `moon fmt MoonECAT`：PASS。
- `moon info MoonECAT\\protocol MoonECAT\\mailbox MoonECAT\\runtime MoonECAT\\isochronon_provider MoonECAT\\isochronon_provider\\fixtures MoonECAT\\cmd\\main MoonECAT`：PASS，公开 `.mbti` 已审查。
- `moon check --target all`：PASS，0 errors。
- `moon test --target wasm`：`3092/3092`。
- `moon test --target wasm-gc`：`3092/3092`。
- `moon test --target js`：`3093/3093`。
- 普通 PowerShell `moon test --target native`：`3255/3255`，未加载
  `vcvars64.bat`。
- `git diff --check`、`git diff --cached --check`：PASS。

### Evidence Boundary

本轮没有打开 NIC、连接设备、发送新 live frame、运行 PDO/DC 稳态、执行长期运行或
多从站实机测试，也没有生成新的 pcap/tshark assessment/claim。此前 AR7V 的单从站
identity 证据不自动提升为本轮协议能力证明。
