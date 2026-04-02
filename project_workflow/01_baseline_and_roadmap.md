# MoonECAT 基线与路线图

本文件由原 AI 任务清单拆分整理而来，对应原总述、Class B 功能对照、Class A 增量路线图与当前交付验收基线。

> **整合说明**：ROADMAP 三条主线（A/B/C）与 BACKLOG（P0-P2）已整合进 [08_integrated_roadmap_and_backlog.md](08_integrated_roadmap_and_backlog.md)，并引入 L1-L4 成熟度分级。本文件继续作为 Class B 基线验收与 Class A 增量路线的主要载体，与 08 文件互补使用。

> **成熟度定位**：Class B 功能对照表对应 **L1 Foundation + L2 Protocol Core** 全量完成；Class A 路线图延伸到 **L3 Product Surface** 与 **L4 Verification & Hardening**。

## 原始说明

本清单基于 [MoonECAT项目申报书.md](../MoonECAT项目申报书.md) 与 [ETG.1500 Master Classes](../ETG1500_V1i0i2_D_R_MasterClasses/ETG1500_V1i0i2_D_R_MasterClasses.md) 整理，用于把项目目标转成可执行任务和可追踪提交。其中 [MoonECAT项目申报书.md](../MoonECAT项目申报书.md) 现主要作为交付基线文档使用，不再按立项申报材料维护。产品面仍保持 `Library API + CLI(scan/validate/run)` 双入口，但总体路线已调整为“**Class B 强制项已完成，继续向 ETG.1500 Class A 工程能力演进**”。`EoE/FoE/SoE/AoE/VoE` 不再作为永久排除项，而是保留为后续 feature pack 级扩展，不阻塞当前主线。

## 0. ETG.1500 Class B 功能对照表

> 来源：ETG.1500 Table 1 — M=Mandatory, C=Conditional, ✅=已实现, ⚠️=部分, ❌=未实现, ➖=排除

| Feature ID | 功能 | Class B 要求 | 状态 | 对应模块 | 备注 |
|:---:|---|---|:---:|---|---|
| **基础功能 (5.3)** | | | | | |
| 101 | Service Commands (全部 DLPDU 命令) | shall if ENI | ✅ | [protocol/codec.mbt](../protocol/codec.mbt) | 15 种 EcCommand 全部映射 |
| 102 | IRQ Field in datagram | should | ✅ | [protocol/pdu.mbt](../protocol/pdu.mbt), [runtime/runtime.mbt](../runtime/runtime.mbt), [runtime/scheduler.mbt](../runtime/scheduler.mbt) | IRQ 已编解码透传并在主循环计数 (`irq_events`) |
| 103 | Slaves with Device Emulation | shall | ✅ | [protocol/esm_extensions.mbt](../protocol/esm_extensions.mbt) | read_device_emulation + request_state_aware + OpOnly |
| 104 | EtherCAT State Machine (ESM) | shall | ✅ | [protocol/esm.mbt](../protocol/esm.mbt), [protocol/esm_engine.mbt](../protocol/esm_engine.mbt) | Init/PreOp/SafeOp/Op/Boot + 回退路径 |
| 105 | Error Handling (WKC 等) | shall | ✅ | [runtime/scheduler.mbt](../runtime/scheduler.mbt) | WKC 校验 + 连续错误计数 + 诊断指标 |
| 106 | VLAN | may | ➖ | — | 不实现 |
| 107 | EtherCAT Frame Types (0x88A4) | shall | ✅ | [protocol/frame.mbt](../protocol/frame.mbt) | Ethernet II + EtherType 0x88A4 |
| 108 | UDP Frame Types | may | ➖ | — | 不实现 |
| **过程数据交换 (5.4)** | | | | | |
| 201 | Cyclic PDO | shall | ✅ | [protocol/pdo.mbt](../protocol/pdo.mbt), [runtime/runtime.mbt](../runtime/runtime.mbt) | pdo_exchange LRW 已完整实现 |
| 202 | Multiple Tasks | may | ➖ | — | Free Run 单任务优先 |
| 203 | Frame repetition | may | ➖ | — | 不实现 |
| **网络配置 (5.5)** | | | | | |
| 301 | Online scanning / ENI import (至少一种) | shall (至少一种) | ✅ | [runtime/scan.mbt](../runtime/scan.mbt) | Online scanning 已实现 |
| 302 | Compare Network configuration (boot-up) | shall | ✅ | [runtime/validate.mbt](../runtime/validate.mbt) | Vendor/Product/Revision/Serial 4-tuple 校验 |
| 303 | Explicit Device Identification | should | ✅ | [runtime/scan.mbt](../runtime/scan.mbt), [runtime/validate.mbt](../runtime/validate.mbt), [hal/config.mbt](../hal/config.mbt) | IdentificationAdo 读取 + 显式标识校验已接入 |
| 304 | Station Alias Addressing | may | ✅ | [protocol/discovery.mbt](../protocol/discovery.mbt) | `read_station_alias` + `enable_alias_addressing` (0x0012 + Bit24) |
| 305 | Access to EEPROM (Read shall, Write may) | Read shall | ✅ | [protocol/eeprom.mbt](../protocol/eeprom.mbt) | eeprom_read_word/eeprom_read via ESC 0x0502-0x0508 |
| **邮箱支持 (5.6)** | | | | | |
| 401 | Support Mailbox (基础传输) | shall | ✅ | [protocol/mailbox_transport.mbt](../protocol/mailbox_transport.mbt) | mailbox_send/recv/poll/exchange 已闭环 |
| 402 | Mailbox Resilient Layer (RMSM) | shall | ✅ | [mailbox/rmsm.mbt](../mailbox/rmsm.mbt) | Rmsm 状态机 + 计数器关联 + 重复检测 + 重试 |
| 403 | Multiple Mailbox channels | may | ➖ | — | 不实现 |
| 404 | Mailbox polling | shall | ✅ | [protocol/mailbox_transport.mbt](../protocol/mailbox_transport.mbt) | mailbox_poll SM status bit 检查 |
| **CoE (5.7)** | | | | | |
| 501 | SDO Up/Download (normal + expedited) | shall | ✅ | [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt) | sdo_download/upload + retry 事务已闭环 |
| 502 | Segmented Transfer | should | ✅ | [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt), [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt) | 分段上传/下载与续传循环均已闭环 |
| 503 | Complete Access | should (shall if ENI) | ✅ | [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt), [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt) | CA 编码、上传/下载事务与分段续传均已完成 |
| 504 | SDO Info service | should | ✅ | [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt), [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt), [cmd/main/main.mbt](../cmd/main/main.mbt) | SDO Info 事务与 Native `od` 浏览入口均已落地 |
| 505 | Emergency Message | shall | ✅ | [mailbox/emergency.mbt](../mailbox/emergency.mbt) | decode_emergency/decode_emergency_frame |
| 506 | PDO in CoE | may | ➖ | — | |
| **EoE (5.8)** | | | | | |
| 601–603 | EoE Protocol / Virtual Switch / OS Endpoint | shall if EoE | ➖ | — | 项目范围排除 |
| **FoE (5.9)** | | | | | |
| 701–703 | FoE Protocol / FW Up/Download / Boot State | shall if FoE | ➖ | — | 项目范围排除 |
| **SoE (5.10)** | | | | | |
| 801 | SoE Services | should if SoE | ➖ | — | 项目范围排除 |
| **AoE (5.11)** | | | | | |
| 901 | AoE Protocol | should | ➖ | — | 项目范围排除 |
| **VoE (5.12)** | | | | | |
| 1001 | VoE Protocol | may | ➖ | — | 项目范围排除 |
| **DC 同步 (5.13)** | | | | | |
| 1101 | DC support | shall if DC | ✅ | [protocol/dc.mbt](../protocol/dc.mbt), [runtime/runtime.mbt](../runtime/runtime.mbt) | 已实现 DC 初始化 + SYNC0 + FRMW 漂移补偿 |
| 1102 | Continuous Propagation Delay compensation | should | ✅ | [protocol/dc.mbt](../protocol/dc.mbt), [runtime/runtime.mbt](../runtime/runtime.mbt) | 运行态周期重估+平滑写回+计数 telemetry 已完成 |
| 1103 | Sync window monitoring | should | ✅ | [protocol/dc.mbt](../protocol/dc.mbt) | dc_read_sync_window |
| **Slave-to-Slave (5.14)** | | | | | |
| — | Slave-to-Slave via Master | — | ➖ | — | 暂不实现 |
| **Master 信息 (5.15)** | | | | | |
| 1301 | Master Object Dictionary | may | ➖ | — | Class B 可选 |

**Class B 强制(shall)功能覆盖率：17/17 = 100%**

## 0.1 Class A 增量路线图

> 来源：ETG.1500 对 Class A 的能力分层、EtherCAT_Compendium 对 Configuration Tool / ENI / 拓扑比较 / Hot Connect / 诊断分层的说明，以及 [src/SOEM-callflow-analysis.md](../src/SOEM-callflow-analysis.md)、[src/gatorcat-callflow-analysis.md](../src/gatorcat-callflow-analysis.md)、[src/ethercrab-callflow-analysis.md](../src/ethercrab-callflow-analysis.md)、[src/CherryECAT-callflow-analysis.md](../src/CherryECAT-callflow-analysis.md) 中的工程实现对照。

| Class A 方向 | 标准/参考依据 | 当前状态 | L 级 | 主线 | 下一步落点 |
|---|---|---|:---:|:---:|---|
| 配置工具 + ENI 双源配置 | ETG.1500 5.5；Gatorcat/SOEM ENI 入口 | ⚠️ XML→JSON 中转已通，Pass/Warn/Block 已输出；配置工具消费待补 | L3 | A | 补配置工具统一视图与更完整 offline 配置模型 |
| CoE 分段传输完整闭环 | ETG.1500 5.7；CherryECAT/EtherCrab/SOEM | ✅ 库层事务已完成 | L2 | — | 补 CLI / 配置工具入口与真实从站回归 |
| Complete Access 完整支持 | ETG.1500 5.7；SOEM/EtherCrab/Gatorcat | ✅ 库层事务已完成 | L2 | — | 补用户面入口与 ENI 配置联动验证 |
| SDO Info / 对象字典浏览 | ETG.1500 5.7；Compendium OD/诊断 | ⚠️ Native CLI `od` 已落地，配置工具复用待收口 | L3 | A | 补稳定错误分类与配置工具复用模型 |
| Master Object Dictionary | ETG.1500 5.15.1 | ❌ 未实现 | L3 | B | 设计主站 OD、配置摘要与诊断汇聚模型 |
| 拓扑变化 / Hot Connect | Compendium topology/Hot Connect；GatorCAT/ethercrab/SOEM | ⚠️ 显式标识+别名+4-tuple 已有，拓扑指纹待冻结 | L3-L4 | B | 补拓扑指纹与实机双分支证据 |
| Multiple Tasks / Process Image | ETG.1500 5.4.2；EtherCrab/Gatorcat | ➖ 单任务 Free Run 优先 | L4 | C | DC 基线稳定后再设计 |
| EoE/FoE/SoE 等 feature pack | ETG.1500 5.8~5.10 | ➖ 不阻塞主线 | — | — | Class A 基线完成后按 feature pack 评估 |

## 0.2 当前交付验收基线

> 成熟度快照：**L1** 9/9 ✅ · **L2** 22/22 ✅ · **L3** 15/15 ✅ · **L4** 7/13 ≈54%  
> 测试：413+ tests passing · Class B 17/17 = 100%

- `moon test` 413+ 用例通过，覆盖 Wasm-GC / Native 双后端，可作为仓库级最小回归闸门。
- Windows Npcap 路径下 `moon run cmd/main state -- --backend native-windows-npcap --if <interface>` 已成功执行，可作为 Native `state` 入口 smoke 证据。
- Native CLI 当前具备 `list-if`、`read-sii`、`state`、`diagnosis`、`od` 等交付表面；其中 `state` 最近实机执行成功，`od` 已具备稳定文本/JSON 浏览输出。
- SII Deep Read 全量解析已落地（Native CLI `read-sii --deep`），含 Category overlay 解码。
