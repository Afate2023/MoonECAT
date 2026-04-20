# MoonECAT Backlog

> **整合通知**：本文档的 P0/P1/P2 条目已整合进 [project_workflow/08_integrated_roadmap_and_backlog.md](../project_workflow/08_integrated_roadmap_and_backlog.md)，与 ROADMAP 三条主线合并，并引入 L1-L4 成熟度分级。本文件保留为历史参考，后续更新以整合文件为准。

> **完成度快照（2026-04-14）**：基于代码实际状态标注。标记说明：
> - ✅ 已完成 — 功能已实现并可用
> - 🔶 大部分完成 — 核心已实现，剩余收尾/文档化工作
> - ⬜ 尚未开始或仅有骨架

本文档整理 MoonECAT 当前后续 backlog。  
原则上按三组推进：

- **P0 / Native Runtime Baseline**
- **P1 / Verification Runtime**
- **P2 / HIL-Ready Runtime Boundary**

每项包含：
- 背景
- 目标
- 建议涉及目录
- 验收标准

---

# P0 / Native Runtime Baseline

---

## P0-1 统一 Windows Npcap 与 Linux Raw Socket 的 Native HAL 语义 🔶

### 背景
MoonECAT 当前已经具备 Windows Npcap 与 Linux Raw Socket 两条 Native 路径。  
下一阶段重点不是“两个后端都能跑”，而是“两个后端服从同一约定 HAL/runtime 合同”。

### 目标
- 对齐 `open/send/recv/close/list-if` 行为语义
- 对齐 `EcError` 映射与错误分类
- 对齐 `list-if/scan/state/run` 的 JSON/text 表面
- 对齐 timeout / link-down / permission / not-found 等行为
- 对齐自发包过滤策略

### 建议涉及目录
- `hal/native/`
- `cmd/main/`
- `docs/`

### 验收标准
- 等价错误在 Windows/Linux 上映射到同一 `EcError`
- `list-if --json` 拥有稳定共享 schema
- `scan/validate/state/run` 输出不再依赖未文档化的平台差异
- 存在一份 Native HAL 合同文档并与实现一致

---

## P0-2 完成 Linux Raw Socket 实机闭环 smoke 基线 ✅

### 背景
2026-04-20 已在 Linux Raw Socket + `eno1` + `VT_EX_CA20_20250225.esi.json` 单从站链路上补齐最小实机闭环证据。后续重点从“能不能跑”切到“长跑、ASan 与脚本化固化”。

### 目标
- 完成 `list-if -> scan -> validate -> run`
- 完成 `state` 的广播与定点迁移路径
- 细化 Linux `open/send/recv` 错误分类
- 稳定空总线行为
- 与 Windows Native 路径保持一致运行语义

### 建议涉及目录
- `hal/native/`
- `cmd/main/`
- `scripts/`
- `docs/`

### 验收标准
- Linux 上 `list-if/scan/validate/state/run` 均有最小实机证据
- 空总线情况下结果稳定
- `RecvTimeout/LinkDown/NotSupported/NotFound/RecvFailed(...)` 分类稳定
- Linux Native 路径不再停留在“可编译骨架”状态

---

## P0-3 冻结 Native trace / progress NDJSON schema 🔶

### 背景
MoonECAT 已具备 `run --json`、`--progress-ndjson` 等运行输出。  
下一步应把这些输出提升为稳定 runtime trace surface。

### 目标
- 定义 `progress-ndjson` 稳定 schema
- 定义 NDJSON 与最终 JSON summary 的关系
- 给 schema 增加版本/兼容性说明
- 提供跨平台样例

### 建议字段
- cycle index
- elapsed timestamp
- backend
- interface
- run mode
- current ESM state
- slave count
- WKC / timeout / retry
- diagnosis snapshot
- stop reason / first fault reason

### 建议涉及目录
- `runtime/`
- `cmd/main/`
- `docs/`
- `scripts/`

### 验收标准
- `run --progress-ndjson` 输出 schema 稳定且文档化
- 最终 JSON summary 与 NDJSON 中间事件关系明确
- 提供 Windows/Linux 样例
- 后续可扩展但不会破坏已有消费者

---

## P0-4 将 `run --until-fault` 收口为正式回归入口 ✅

### 背景
`run --until-fault` 已具备很强的验证价值，但仍更像运行参数而非正式回归表面。

### 目标
- 正式定义 stop reason
- 正式定义 fault summary
- 接入 Native 回归脚本
- 输出稳定 artifact

### 建议涉及目录
- `runtime/`
- `cmd/main/`
- `scripts/`
- `docs/`

### 验收标准
- `run --until-fault` 的停止条件明确且文档化
- 最终 JSON summary 含 stop reason、first fault、consecutive timeouts、last healthy cycle
- 平台脚本可以稳定输出 artifacts
- 文档把 `until-fault` 定义为正式工作流而非调试技巧

---

## P0-5 补齐 Native FFI 生命周期与失败路径测试 🔶

### 背景
MoonECAT 已采用保守的 Native FFI ownership 方案。  
下一步应把这套设计转为更强的测试基线。

### 目标
- 覆盖 open/send/recv/close 生命周期
- 覆盖 invalid handle / open fail / recv fail / send fail / double close
- 覆盖 fallback 与 backend gating 路径
- 确保文档与实现一致

### 建议涉及目录
- `hal/native/`
- `MoonECAT_test.mbt`
- `MoonECAT_wbtest.mbt`
- `docs/`

### 验收标准
- Native backend 失败路径具备覆盖
- fallback 行为稳定
- 文档与测试一致
- 不泄露裸宿主句柄

---

## P0-6 建立 Native CLI 实机证据矩阵 🔶

### 背景
MoonECAT 的 Native CLI 表面已具雏形。  
需要把“跑过”变成“可复核交付”。

### 目标
- 为 `list-if/scan/read-sii/state/diagnosis/od/run` 建证据矩阵
- 记录平台、网卡、从站、命令、结果
- 区分 smoke / regression / manual

### 建议涉及目录
- `docs/`
- `project_workflow/`
- `scripts/`
- `fixtures/`

### 验收标准
- 每个 Native CLI 表面至少有最小证据或明确缺口
- 证据矩阵区分 Windows/Linux
- 证据格式可复用
- 可作为发布检查输入

---

# P1 / Verification Runtime

---

## P1-1 设计并实现一等 fault injection 模型 ✅

### 背景
MoonECAT 要走向验证执行器，就必须把 fault injection 从脚本技巧提升为 runtime 原生能力。

### 目标
- 定义 fault 类型与注入点
- 支持定时/条件触发
- 不污染 protocol core 的纯逻辑边界
- 让 fault 进入统一 runtime 输出

### 首批 fault 建议
- recv timeout burst
- send failure
- WKC mismatch
- missing slave
- AL status mismatch
- state transition timeout
- mailbox timeout

### 建议涉及目录
- `runtime/`
- `protocol/`
- `hal/`
- `docs/`

### 验收标准
- 至少 3 类 fault 可控注入
- fault 输出可观测
- protocol core 不因 fault model 变得平台耦合
- fault model 有文档

---

## P1-2 引入 deterministic replay 最小闭环 ✅

### 背景
可复现是 MoonECAT 未来的重要差异化能力。

### 目标
- 保存可 replay 的最小运行工件
- 从记录输入/事件重放失败场景
- 复现相同 stop reason 或等价失败类别
- 为后续最小反例收缩做准备

### 建议涉及目录
- `runtime/`
- `cmd/main/`
- `fixtures/`
- `docs/`

### 验收标准
- 至少 1 个失败场景可保存并 replay
- replay 结果能复现同类 stop reason
- replay 输入边界有说明
- 提供示例 replay fixture

---

## P1-3 引入 monitor / verdict 框架 ✅

### 背景
MoonECAT 输出应从“日志与 telemetry”升级为“验证结论”。

### 目标
- 定义 `Pass/Warn/Fail/Block`
- 引入可组合 monitor
- 在 `run/validate/diagnosis` 中复用
- 区分“事实层”与“解释层”

### 首批 monitor 建议
- consecutive timeout threshold exceeded
- WKC below threshold
- startup state not reached
- shutdown rollback failure
- unexpected slave count change
- repeated mailbox failure

### 建议涉及目录
- `runtime/`
- `cmd/main/`
- `docs/`

### 验收标准
- `run` 输出显式 verdict
- monitor 结果可汇入统一 summary
- monitor 可组合
- monitor 生命周期文档化

---

## P1-4 从 loopback/mock 演进到协议级虚拟从站 ✅

### 背景
仅依赖 loopback 难以支撑高密度验证。

### 目标
- 增加最小 ESM 虚拟从站
- 增加最小 PDO 行为
- 增加 mailbox/SDO 响应脚本
- 提高 CI 中协议验证密度

### 建议涉及目录
- `hal/mock/`
- `protocol/`
- `mailbox/`
- `fixtures/`

### 验收标准
- 至少 1 个虚拟从站能完成 `scan -> state -> run`
- 能模拟 mailbox/SDO 成功与失败
- fixture 可进入 CI
- 虚拟从站行为文档化

---

## P1-5 冻结 topology fingerprint / Hot Connect 最小模型 ✅

### 背景
当前拓扑比较、显式标识、可选段等能力仍需统一模型。

### 目标
- 定义 topology fingerprint
- 定义 required / optional slave or group
- 定义启动告警/阻断规则
- 定义在线变化检测边界

### 建议涉及目录
- `runtime/`
- `mailbox/`
- `docs/`
- `project_workflow/`

### 验收标准
- `validate` 可输出 topology fingerprint
- 至少覆盖 missing slave / order mismatch / alias mismatch
- Hot Connect 最小模型文档冻结
- diff 输出有稳定 schema

---

## P1-6 扩展 `DiagnosticSurface` 为统一事实层 ✅

### 背景
`DiagnosticSurface` 应成为 CLI、配置工具、回放、HIL 的统一状态来源。

### 目标
- 汇聚 AL / WKC / timeout / topology / config summary / telemetry
- 区分稳定字段与派生字段
- 让 `validate/state/diagnosis/run` 共用同一事实层

### 建议涉及目录
- `runtime/`
- `cmd/main/`
- `docs/`

### 验收标准
- 主要命令共享同一事实层结构
- 字段语义稳定
- 有回归测试
- 消费方可区分 raw fact 与 interpreted verdict

---

# P2 / HIL-Ready Runtime Boundary

---

## P2-1 抽象 runtime hook：process image / cycle / event / fault ✅

### 背景
MoonECAT 若要进入 HIL，需要先有稳定扩展点，而不是靠 fork runtime 实现。

### 目标
- 增加 process image hook
- 增加 cycle hook
- 增加 event/fault hook
- 保持现有 CLI 默认路径不变

### 建议涉及目录
- `runtime/`
- `protocol/`
- `docs/`

### 验收标准
- runtime 可挂外部 hook 且不破坏 CLI 主线
- hook 合同有文档
- 至少 1 个 mock/fixture 证明 hook 生效
- 未使用 hook 时行为不变

---

## P2-2 冻结 multiple tasks / process-image partitioning 接口模型 ✅

### 背景
当前不急着完整实现多任务，但必须避免后续重画 runtime 边界。

### 目标
- 定义 task group
- 定义 process image slice
- 定义 phase order 与 sync relation
- 保持单任务基线为默认

### 建议涉及目录
- `runtime/`
- `docs/`
- `project_workflow/`

### 验收标准
- 有数据模型/接口文档
- 当前单任务实现不被破坏
- 后续多任务扩展有稳定落点
- 至少 1 个白盒测试证明模型表达力

---

## P2-3 定义外部 plant/controller co-sim adapter contract ✅

### 背景
MoonECAT 未来要接更大的电力电子/HIL 系统，但不应直接膨胀为完整仿真器。

### 目标
- 定义 `step/reset/snapshot/restore`
- 定义 process image 交换边界
- 定义 timing / timestamp 约束
- 保持与特定仿真器解耦

### 建议涉及目录
- `runtime/`
- `plugin/`
- `docs/`

### 验收标准
- 最小 co-sim adapter contract 文档化
- 不绑定特��� GUI 或仿真器
- 至少 1 个 mock adapter 示例
- 预留 fault / verdict 汇聚接口

---

## P2-4 实现最小 communication-closed-loop HIL PoC 🔶

### 背景
在完整电力电子 HIL 之前，先做最小通信闭环 HIL 更稳妥。

### 目标
- MoonECAT Native 运行时进入最小闭环
- 把 state / PDO / SDO / fault 路径放进同一执行循环
- 复用 trace / verdict / diagnosis 机制

### 建议涉及目录
- `runtime/`
- `cmd/main/`
- `docs/`
- `scripts/`

### 验收标准
- PoC 至少演示 `scan/state/run` + 一类异常路径
- 输出进入统一 trace/verdict
- 不要求完整硬实时
- 文档明确这是 communication-closed-loop PoC，而非完整控制闭环 HIL

---

## P2-5 定义未来 MCU + Linux 协同 HIL 的时基合同 ✅

### 背景
MoonECAT 最终若进入 MCU + Linux HIL，最先需要冻结的是时间责任边界，而不是立刻堆功能。

### 目标
- 定义 wall-clock / cycle-clock / external clock
- 定义 deterministic / jitter-tolerant 路径
- 定义 Linux runtime 的时间职责边界
- 为后续 MCU 集成保留架构稳定性

### 建议涉及目录
- `runtime/`
- `hal/`
- `docs/`

### 验收标准
- 时钟/时基模型显式文档化
- 明确哪些路径要求 deterministic，哪些允许 jitter
- Runtime 时间责任清晰
- 后续 MCU 集成不需要重写 runtime 核心

---

# 推荐里程碑

## Milestone A — Native Runtime Baseline
- P0-1
- P0-2
- P0-3
- P0-4
- P0-5
- P0-6

## Milestone B — Verification Runtime
- P1-1
- P1-2
- P1-3
- P1-4
- P1-5
- P1-6

## Milestone C — HIL-Ready Runtime Boundary
- P2-1
- P2-2
- P2-3
- P2-4
- P2-5

---

# 推荐标签

- `native`
- `windows`
- `linux`
- `ffi`
- `runtime`
- `verification`
- `diagnostics`
- `replay`
- `fault-injection`
- `topology`

---

# 完成度总览（2025-07 快照）

| 编号 | 条目 | 状态 | 关键实现证据 |
|------|------|------|-------------|
| P0-1 | 统一 Native HAL 语义 | 🔶 | `Nic`/`ZeroCopyNic` 共享 trait; `EcError` 17 变体; 部分边界行为待文档对齐 |
| P0-2 | Linux Raw Socket 实机闭环 | ✅ | 已补 Linux 单从站实机证据：`list-if / scan / validate / diagnosis / state / read-sii / od / run / run --until-fault` |
| P0-3 | NDJSON schema 冻结 | 🔶 | `--progress-ndjson` 已实现; schema 规范文档待写 |
| P0-4 | `run --until-fault` 正式化 | ✅ | CLI 已集成; stop reason / first fault / fault count 结构化输出 |
| P0-5 | Native FFI 生命周期测试 | 🔶 | 保守所有权模型; NATIVE_FFI_SAFETY.md; 失败路径测试待扩展 |
| P0-6 | Native CLI 证据矩阵 | ✅ | BACKEND_RELEASE_MATRIX.md 已回填 Windows + Linux 实机记录 |
| **P0 小计** | 6 项 | **3 ✅ / 3 🔶** | |
| P1-1 | fault injection 模型 | ✅ | `FaultInjection` + `FaultNic`: drop/delay/corrupt/WKC mismatch |
| P1-2 | deterministic replay | ✅ | `RecordingNic` + `ReplayNic` 帧录制回放 |
| P1-3 | monitor / verdict | ✅ | `Monitor` trait + `Verdict` + `MonitorRegistry` + 内建 monitors |
| P1-4 | 虚拟从站 | ✅ | `VirtualSlave`/`VirtualBus`/`VirtualMailbox`/`VirtualSlaveTemplate` |
| P1-5 | topology fingerprint | ✅ | `TopologyFingerprint` + `TopologyHealthAnalyzer` |
| P1-6 | DiagnosticSurface 统一事实层 | ✅ | `DiagnosticSurface` 汇聚 AL/WKC/timeout/topology/config |
| **P1 小计** | 6 项 | **6 ✅** | |
| P2-1 | runtime hook | ✅ | `HilCycleHook` + `HilSession` + hook 体系 |
| P2-2 | task / process-image partitioning | ✅ | `TaskSchedule` + `MultiRateAnalysis` + `ProcessImageSlice` |
| P2-3 | co-sim adapter contract | ✅ | `CoSimAdapter` trait + `LoopbackCoSimAdapter` 参考实现 |
| P2-4 | HIL PoC 闭环 | 🔶 | 框架就绪; `ExternalProcessBridge`; 完整 PoC 演示待收口 |
| P2-5 | MCU + Linux 时基合同 | ✅ | `Timebase`/`TimebaseSync`/`VirtualTimebase` + `McuHal` 骨架 |
| **P2 小计** | 5 项 | **4 ✅ / 1 🔶** | |
| **总计** | **17 项** | **11 ✅ / 6 🔶 / 0 ⬜** | P1 全部完成; P0/P2 剩余收尾 |
- `hil`
- `roadmap`
- `design`

---

# 一句话总结

MoonECAT 当前 backlog 的核心不是“补更多主站功能”，而是：

> **把 Native 主站做成可信执行器，把验证能力做成原生能力，并提前冻结 HIL 所需的运行时边界。**