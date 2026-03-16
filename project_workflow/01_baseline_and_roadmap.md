# MoonECAT 基线与路线图

本文件由原 AI 任务清单拆分整理而来，对应原总述、Class B 功能对照、Class A 增量路线图与当前交付验收基线。

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

| Class A 方向 | 标准/参考依据 | 当前状态 | 下一步落点 |
|---|---|---|---|
| 配置工具 + ENI 双源配置 | ETG.1500 5.5，EtherCAT_Compendium 对 ESI/ENI/Configuration Tool 的工程流说明；Gatorcat/SOEM 均有 ENI 或配置文件入口 | ⚠️ 已改成 `cmd/eni_json` 的 XML→JSON 中转：ENI XML 走统一配置 JSON，ESI XML 走共享 ESI JSON 中间模型；`validate --eni-json <path>` 与 `esi-sii -- --esi-json <path>` 分别消费各自 JSON 桥，并补上通过/警告/阻塞三级结论、完整差异项 JSON，以及最小 `SM/FMMU/PDO + mailbox/DC` 摘要；配置工具消费模型仍待补齐 | 继续补配置工具统一视图、启动时网络差异细分与更完整 offline 配置模型 |
| CoE 分段传输完整闭环 | ETG.1500 5.7；CherryECAT、EtherCrab、SOEM 均有完整 mailbox/SDO 流程 | ✅ 库层事务已完成 | 补 CLI / 配置工具入口与真实从站回归，避免能力停留在事务层 |
| Complete Access 完整支持 | ETG.1500 5.7；SOEM/EtherCrab/Gatorcat 均在映射与批量访问中依赖 CA | ✅ 库层事务已完成 | 补用户面入口、批量对象浏览输出与 ENI 配置联动验证 |
| SDO Info / 对象字典浏览 | ETG.1500 5.7；Compendium 强调对象字典与诊断工具链协同 | ⚠️ 已新增 Native CLI `od` 只读浏览入口，配置工具复用与错误分类仍待收口 | 补稳定错误分类、配置工具复用模型与实机 smoke 证据 |
| Master Object Dictionary | ETG.1500 5.15.1，Class A 更强调统一主站信息表面 | ❌ 未实现 | 设计主站对象字典、配置摘要与诊断状态汇聚模型 |
| 拓扑变化、显式标识与 Hot Connect | EtherCAT_Compendium 对拓扑比较、Explicit Device Identification、Hot Connect group 的说明；GatorCAT / ethercrab / SOEM 对从站顺序、别名、链路位置和可选从站处理的共同做法 | ⚠️ 已有显式标识读取、别名读取与 4-tuple 校验，但尚未冻结“拓扑指纹 / 可选组 / 启动告警”统一模型 | 继续补拓扑指纹、Hot Connect group/optional segment、启动期缺失从站分级和实机/回放证据 |
| Multiple Tasks / Process Image 分区 | ETG.1500 5.4.2；EtherCrab/Gatorcat 展示了更细粒度 process image 与任务切分 | ➖ 目前以单任务 Free Run 优先 | 在 Free Run/DC 基线稳定后，再设计多任务调度与 process image 切片 |
| EoE/FoE/SoE 等 feature pack | ETG.1500 5.8~5.10；CherryECAT/SOEM 提供协议面参考 | ➖ 当前不阻塞主线 | 在 Class A 主站基线完成后，按 feature pack 独立评估与落地 |

## 0.2 当前交付验收基线（2026-03-12）

- `moon test` 已通过，可作为仓库级最小回归闸门。
- Windows Npcap 路径下 `moon run cmd/main state -- --backend native-windows-npcap --if <interface>` 已成功执行，可作为 Native `state` 入口 smoke 证据。
- Native CLI 当前至少已具备 `list-if`、`read-sii`、`state`、`diagnosis`、`od` 等交付表面；其中 `state` 的最近一次实机执行已成功，`od` 已具备稳定文本/JSON 浏览输出。
