# MoonECAT Roadmap

> **整合通知**：本文档的三条主线（A: Native Runtime Baseline / B: Verification Runtime / C: HIL-Ready Runtime Boundary）已整合进 [project_workflow/08_integrated_roadmap_and_backlog.md](../project_workflow/08_integrated_roadmap_and_backlog.md)，并引入 L1-L4 成熟度分级和 P0-P2 优先级映射。本文件保留为历史参考，后续更新以整合文件为准。

本文档定义 MoonECAT 在当前阶段之后的主线演进方向。  
目标不是把 MoonECAT 继续扩展为“功能更全的 EtherCAT 主站”，而是把它收敛为：

- **可实机闭环的 Native 主站运行时**
- **可编排、可回放、可验证的验证执行器**
- **为 MCU + Linux 协同 HIL 预留稳定边界的通信内核**

MoonECAT 当前已经具备清晰的分层边界（HAL / Protocol / Mailbox / Runtime / CLI）和 Native 后端方向，因此后续路线不再以“平均补功能”为主，而以“Native 收口、验证能力原生化、HIL 边界前置设计”为主线推进。

---

## 1. 路线总览

MoonECAT 后续路线分为三条主线：

### A. Native Runtime Baseline
目标：把 Windows Npcap 与 Linux Raw Socket 收敛成同一 Native HAL 合同，并形成稳定实机闭环与运行证据。

### B. Verification Runtime
目标：把 MoonECAT 从“能运行的主站”升级为“可验证、可回放、可注入故障的执行器”。

### C. HIL-Ready Runtime Boundary
目标：为未来 MCU + Linux 协同 HIL、外部 plant/controller 联调、多任务/多时基扩展预留稳定运行时边界。

---

## 2. 当前阶段判断

MoonECAT 当前更适合被定义为：

> **Class B 主站核心已全面实现，验证运行时已建成，正在从功能完成走向实机闭环全覆盖与文档规范化。**

具体而言：
- 协议核心（帧编解码、ESM、DC、PDO、SDO、FoE、EEPROM、SII 全类别解析）功能完整
- 验证基础设施（虚拟总线/从站、故障注入、录制回放、场景执行器、monitor/verdict）**已全面实现**，超出原始路线预期
- Native 后端（Windows Npcap）已有实机闭环证据；Linux Raw Socket FFI 已实现，实机验证待补
- HIL/Co-Sim 框架（hook、adapter、timebase、task schedule）已就绪，PoC 演示待收口
- CLI 功能完整（8 个子命令），Extism 插件边界已设计

后续重点不再是"把验证能力做出来"（已完成），而应是：

1. **补齐 Linux 实机证据** — 完成双平台对等验证
2. **规范化输出 schema 与合同文档** — 把实现转化为稳定交付
3. **收口 HIL PoC** — 验证端到端闭环

---

## 3. 主线 A：Native Runtime Baseline

### 3.1 目标
- 对齐 Windows Npcap 与 Linux Raw Socket 的 HAL 语义
- 形成 Linux Raw Socket 实机���环基线
- 冻结 Native trace / progress NDJSON 输出
- 把 `run --until-fault` 收口为正式回归入口
- 把 Native 交付从“人工跑过”升级为“可复核证据矩阵”

### 3.2 收口条件
当满足以下条件时，可认为 Native Runtime Baseline 达成：

- Windows 与 Linux Native 后端共享同一稳定 HAL 语义
- Linux 实机 `list-if -> scan -> validate -> run` 闭环可复现
- `state` 命令在 Linux Native 路径具备广播与定点迁移闭环
- `run --progress-ndjson` 与最终 JSON summary 拥有稳定 schema
- `run --until-fault` 成为正式回归工作流
- Native CLI 各主命令拥有最小实机证据矩阵

### 3.3 为什么优先级最高
因为后面的 replay、fault injection、HIL adapter、AI 分析都依赖一个稳定的 Native runtime contract。  
如果 Native 语义和产物还不稳定，后续验证层会被平台差异不断反噬。

---

## 4. 主线 B：Verification Runtime

### 4.1 目标
- 引入一等故障注入模型
- 增加 deterministic replay 最小闭环
- 引入 monitor / verdict 框架
- 从简单 loopback/mock 走向“虚拟从站”
- 冻结 topology fingerprint / Hot Connect 最小模型
- 把 `DiagnosticSurface` 扩成统一事实层

### 4.2 收口条件
当满足以下条件时，可认为 Verification Runtime 达成第一阶段目标：

- 至少 3 类 fault 可控注入
- 至少 1 类失败场景可保存并 replay
- `run` 可输出显式 verdict
- 至少 1 个虚拟从站场景可完成 `scan -> state -> run`
- `validate` 可输出稳定 topology fingerprint
- `validate/state/diagnosis/run` 共享统一事实层

### 4.3 价值
这是 MoonECAT 区别于 TwinCAT / CODESYS / 常规主站库的关键方向。  
MoonECAT 后续竞争力不应主要来自“功能项更多”，而应来自：

- 可验证
- 可回放
- 可解释
- 可脚本化
- 可作为联调执行器嵌入更大系统

---

## 5. 主线 C：HIL-Ready Runtime Boundary

### 5.1 目标
- 定义 runtime hook：process image / cycle / event / fault
- 冻结 multiple tasks / process-image partitioning 接口模型
- 定义外部 plant/controller co-sim adapter contract
- 做最小 communication-closed-loop HIL PoC
- 定义未来 MCU + Linux 协同 HIL 所需的 clock contract

### 5.2 收口条件
当满足以下条件时，可认为 HIL-Ready Boundary 达成第一阶段目标：

- Runtime 可以挂接外部 hook 而不污染协议核心
- 单任务基线之上已有多任务/切片接口模型
- 有最小 co-sim adapter contract
- 有一个最小 communication-closed-loop HIL PoC
- 有时基/时钟责任文档，为后续 MCU 联调预留边界

### 5.3 边界原则
MoonECAT 不应直接膨胀成完整仿真器。  
MoonECAT 在未来 HIL 系统中的定位应是：

> **通信执行器 + 运行时协调器的一部分**

而不是吞掉 plant 求解、控制器实现或 GUI 工作台的全部职责。

---

## 6. 优先级排序与完成度

> 以下完成度标注基于 2025-07 代码实际状态。
>
> - ✅ 已完成 / 已达预期
> - 🔶 大部分完成，剩余收尾
> - ⬜ 尚未开始或仅有骨架

### P0：必须优先完成 — Native Runtime Baseline
| 条目 | 状态 | 说明 |
|------|------|------|
| Native HAL 语义统一 | 🔶 | Windows Npcap + Linux Raw Socket 双后端共享 `Nic`/`ZeroCopyNic` trait; `EcError` 17 变体覆盖; 零拷贝后端已实现; 尚需对齐部分边界行为文档 |
| Linux Raw Socket 实机闭环 | 🔶 | FFI 桩 + fallback 体系完成; AF_PACKET send/recv/list 路径已实现; 实机证据待补(Windows 已有 BACKEND_RELEASE_MATRIX 实机记录) |
| Native trace / NDJSON schema 冻结 | 🔶 | `run --progress-ndjson` 已实现; schema 尚未作为正式规范文档化 |
| `run --until-fault` 正式化 | ✅ | `run --until-fault` 已实现并集成于 CLI; 输出 stop reason / first fault / fault count |
| Native FFI 生命周期与失败路径测试 | 🔶 | Native FFI 安全模型有文档(NATIVE_FFI_SAFETY.md); handle 生命周期由保守所有权管理; 需更多失败路径测试 |
| Native CLI 证据矩阵 | 🔶 | BACKEND_RELEASE_MATRIX.md 记录了 Windows Npcap 实机证据(2026-03-11, 2026-03-14); Linux 实机证据待补 |

### P1：形成验证平台差异化 — Verification Runtime
| 条目 | 状态 | 说明 |
|------|------|------|
| fault injection API | ✅ | `FaultInjection` 模型已实现于 hal/mock/: drop/delay/corrupt/WKC mismatch; 条件/定时触发; `FaultNic` 包装器 |
| deterministic replay | ✅ | `RecordingNic` + `ReplayNic` 已实现; 支持帧录制与确定性回放 |
| monitor / verdict | ✅ | `Monitor` trait + `Verdict`(Pass/Warn/Fail/Block) + `MonitorRegistry` + 内建 monitors 已实现 |
| 虚拟从站 | ✅ | `VirtualSlave` + `VirtualSlaveTemplate` + `VirtualBus` + `VirtualMailbox` 已实现; 支持多从站场景 |
| topology fingerprint / Hot Connect | ✅ | `TopologyFingerprint` + `TopologyHealthAnalyzer` 已实现; 支持 hash/match/diff |
| 扩展 `DiagnosticSurface` | ✅ | `DiagnosticSurface` 统一事实层已实现: 汇聚 AL/WKC/timeout/topology/config/telemetry; 支持 issue 分级与结构化诊断 |

### P2：为 HIL 做边界冻结 — HIL-Ready Runtime Boundary
| 条目 | 状态 | 说明 |
|------|------|------|
| runtime hook 模型 | ✅ | `HilCycleHook` + `HilSession` 已实现; 支持 process image / cycle / event hook |
| multiple tasks / process-image partitioning 接口 | ✅ | `TaskSchedule` + `MultiRateAnalysis` + `ProcessImageSlice` 已实现 |
| co-sim adapter contract | ✅ | `CoSimAdapter` trait (step/reset/snapshot/restore) 已实现; `LoopbackCoSimAdapter` 作为参考实现 |
| communication-closed-loop HIL PoC | 🔶 | HIL 框架就绪(`HilSession` + `ExternalProcessBridge`); 完整 PoC 闭环演示待完成 |
| MCU + Linux clock contract | ✅ | `Timebase` + `TimebaseSync` + `VirtualTimebase` 已实现; MCU HAL 有 `McuHal` trait 骨架 |

---

## 7. 不做什么

为避免路线发散，当前阶段不以以下方向为优先目标：

- 与 TwinCAT / CODESYS 做功能项逐条对齐
- 过早扩展大量 feature pack（EoE/FoE/SoE/AoE/VoE）
- 过早把 MoonECAT 做成完整 GUI 平台
- 过早实现完整硬实时电力电子 HIL
- 让平台/后端差异持续泄漏到上层 runtime 语义

---

## 8. 一句话路线结论

MoonECAT 的后期路线应概括为：

> **先把 Native 主站做成可信执行器，再把验证能力做成原生能力，最后把它接成 MCU + Linux 协同 HIL 的通信内核。**

---

## 9. 当前进度总结（2025-07 快照）

| 主线 | 总体完成度 | 关键里程碑 |
|------|-----------|-----------|
| A. Native Runtime Baseline | **~75%** | Windows Npcap 实机闭环已达成; Linux Raw Socket FFI 已实现; CLI 8 个子命令可用; 剩余：Linux 实机验证、schema 规范文档化 |
| B. Verification Runtime | **~95%** | fault injection / replay / monitor-verdict / virtual slave / topology fingerprint / DiagnosticSurface 全部已实现 |
| C. HIL-Ready Runtime Boundary | **~85%** | HIL hook / co-sim adapter / task schedule / timebase 全部已实现; 剩余：完整 PoC 闭环演示 |

**整体评估**：MoonECAT 已从"协议骨架"演进为功能完整的可验证 Native EtherCAT 主站运行时。P1 验证能力已全面实现并超出原始路线预期。P0 和 P2 剩余工作主要集中在实机验证闭环与文档规范化。