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

> **Class B 主站骨架已成，正在从协议正确性工程迈向可实机闭环的验证运行时。**

这意味着后续工作优先级应从“继续横向补功能”切换为：

1. 先把 Native 主线收成稳定基线
2. 再把验证能力做成原生能力
3. 最后把 HIL 所需边界提前冻结

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

## 6. 优先级排序

### P0：必须优先完成
- Native HAL 语义统一
- Linux Raw Socket 实机闭环
- Native trace / NDJSON schema 冻结
- `run --until-fault` 正式化
- Native FFI 生命周期与失败路径测试
- Native CLI 证据矩阵

### P1：形成验证平台差异化
- fault injection API
- deterministic replay
- monitor / verdict
- 虚拟从站
- topology fingerprint / Hot Connect
- 扩展 `DiagnosticSurface`

### P2：为 HIL 做边界冻结
- runtime hook 模型
- multiple tasks / process-image partitioning 接口
- co-sim adapter contract
- communication-closed-loop HIL PoC
- MCU + Linux clock contract

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