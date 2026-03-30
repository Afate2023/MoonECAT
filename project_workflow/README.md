# MoonECAT Project Workflow

> **基于事件溯源的极速可验证工业互联架构**
> 先把 Native 主站做成可信执行器，再把验证能力做成原生能力，最后把它接成 MCU + Linux 协同 HIL 的通信内核。

本目录是 MoonECAT 项目的**任务拆解、进度追踪与维护主入口**。

---

## 项目进度总览

| 成熟度 | 名称 | 进度 | 说明 |
|:---:|---|:---:|---|
| **L1** | Foundation（基础骨架） | **9/9 ✅** | 包结构、HAL、帧/PDU、Mock、测试骨架 |
| **L2** | Protocol Core（协议闭环） | **22/22 ✅** | ESM、PDO、SII/ESI、CoE/SDO、DC、RMSM |
| **L3** | Product Surface（产品交付） | **15/15 ✅** | Native CLI、ENI/配置、OD、诊断、SII 深读、拓扑 |
| **L4** | Verification & Hardening | **7/13 ⚠️** | 实机 smoke、NDJSON、长跑、回放 ✅；Linux 实机/ASan/事件溯源回放/HIL ❌ |

**ETG.1500 Class B**：17/17 = 100%　｜　**测试**：413+ passing　｜　**三条主线**：A 原生运行时 · B 验证运行时 · C HIL 就绪边界

---

## 三条主线速览

| 主线 | 优先级 | 目标 | 当前状态 |
|---|:---:|---|---|
| **A — Native Runtime Baseline** | P0 | Windows/Linux HAL 统一 · 实机闭环 · 证据矩阵 | ⚠️ Windows Npcap 已跑通，Linux 待实机 |
| **B — Verification Runtime** | P1 | 事件溯源回放 · fault injection · monitor/verdict · 虚拟从站 | ❌ 规划中，模型基础已有 |
| **C — HIL-Ready Boundary** | P2 | runtime hook · 多任务 · co-sim adapter · MCU+Linux 时基 | ❌ 规划中 |

详见 [08_integrated_roadmap_and_backlog.md](08_integrated_roadmap_and_backlog.md) §3。

---

## 文件索引

| 文件 | 主题 | 关联主线 | 关联 L 级 |
|---|---|:---:|:---:|
| [01_baseline_and_roadmap.md](01_baseline_and_roadmap.md) | Class B 基线验收 + Class A 增量路线 | — | L1-L2 |
| [02_productization_tracks.md](02_productization_tracks.md) | 产品化拆解（OD/ENI/诊断/Hot Connect/Native/Extism） | A · B | L3 |
| [03_milestones_m1_m4.md](03_milestones_m1_m4.md) | 里程碑 M1-M4（已归档 ✅） | — | L1-L2 |
| [04_milestones_m5_m8.md](04_milestones_m5_m8.md) | 里程碑 M5-M8（M5-M7 ✅，M8 进行中） | A | L2-L3 |
| [05_reference_matrix.md](05_reference_matrix.md) | 参考实现核对矩阵 | — | L2-L3 |
| [06_parallel_workflows_dependencies_risks.md](06_parallel_workflows_dependencies_risks.md) | 并行工作流 · 依赖顺序 · 风险清单 | A · B · C | L3-L4 |
| [07_backlog_and_commit_process.md](07_backlog_and_commit_process.md) | 主线 Backlog 与提交流程 | A · B | L3-L4 |
| [08_integrated_roadmap_and_backlog.md](08_integrated_roadmap_and_backlog.md) | **统一路线图** — L1-L4 审计 · P0-P2 三条主线 · 事件溯源 · 多后端策略 | A · B · C | L1-L4 |

---

## 维护原则

- **08 文件为权威源** — L1-L4 成熟度定义、P0-P2 优先级、三条主线任务以 08 文件为准，其余文件负责细节落地与历史证据。
- **与实现强绑定的内容**优先更新参考矩阵（05）、backlog（07）、验收与风险（06），然后回填 08 审计表。
- **引用仓内文档**统一使用 `../` 相对路径。后续细分优先按"产品主线"拆，不按日期或提交批次拆。
- 原 `docs/ROADMAP.md` 与 `docs/BACKLOG.md` 已整合至 08，原文件仅保留索引指向。
