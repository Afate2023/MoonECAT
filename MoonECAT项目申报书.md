# MoonECAT 交付基线说明（原项目申报书）

- **交付对象**：MoonECAT —— 基于事件溯源的极速可验证工业互联架构
- **副标题**：基于 MoonBit 的全场景、模块化、下一代 EtherCAT 主站库
- **文档用途**：该文档已从立项申报材料转为后续交付基线说明，用于统一范围、阶段目标、验收边界与实施路线。路线图与 Backlog 的详细拆解见 [project_workflow/08_integrated_roadmap_and_backlog.md](project_workflow/08_integrated_roadmap_and_backlog.md)。

## 1. 项目目标与应用场景

### 1.1 行业背景与痛点分析

EtherCAT 是工业自动化中应用最广泛的实时以太网协议之一，主站协议栈的实现直接影响控制系统的实时性、稳定性与研发效率。当前开源生态在“工程化工具链”之间仍存在明显断层。

#### 配置工具链的割裂

传统 EtherCAT 工程仍普遍依赖外部商业软件或脚本工具完成 ESI/ENI 解析、对象字典检查和诊断，协议栈与工具链长期割裂，难以形成统一的自动化工程流。

#### 主站能力与工程目标错位

依据 ETG.1500 Master Classes，工程落地并不应停留在“能跑通基础扫描和 PDO 通信”的 Class B 基线，而应尽量向 Class A 靠拢，把在线扫描、离线 ENI、对象字典浏览、诊断与拓扑一致性校验统一到一套主站能力中。EtherCAT_Compendium 也明确体现了“配置工具 + ESI/ENI + 启动一致性校验 + 在线诊断”是一条完整工程链路，而不是彼此独立的附属功能。

### 1.2 项目核心目标

本项目利用 MoonBit 的快速编译、内存安全和多后端能力，持续交付全场景、高可靠、模块化的 EtherCAT 主站库 **MoonECAT**，并以统一核心实现支撑 CLI、库和后续配置工具形态。

MoonECAT 的核心架构范式——**事件溯源 (Event Sourcing) 与纯函数状态机**——从根本上区别于传统协议栈的"面条式"设计：

- **状态不可变性**：协议栈被抽象为纯函数 $\text{State'} = f(\text{State}, \text{Event})$。当前系统状态完全由"初始状态"加上"历史事件流 (Event Stream)"积分计算而来。
- **时间即数据 (Time as Data)**：物理时间不再是系统中的"环境变量"，而是被固化为 Event 结构体中的 `timestamp_ns` 字段。状态机推进的唯一依据是事件中的时间戳。
- **100% 确定性回放**：只要记录下硬件层抛出的极小体积的 Event 流，就可以在任何平台（PC、浏览器）上逐纳秒地完美重演裸机上的运行轨迹，实现"时空穿越式"的 Bug 追踪。

具体目标包括：

- **内存安全与轻量实时**：借鉴 EtherCrab 的静态 PDU 存储与 CherryECAT 的轻量化实现思路，通过 MoonBit 的静态类型，在保证内存安全的同时控制运行态抖动，目标满足严苛实时要求。
- **统一抽象与跨平台部署**：参考 SOEM 的 OSAL 设计和 Gatorcat 的库/CLI 双模式思路，使同一协议栈可运行于 Linux、裸机/RTOS，并可通过 moonbit-pdk 打包为 Extism 插件，以共享内存缓冲区方式与宿主协同收发数据。
- **以 Class B 为基线、以 Class A 为目标**：当前实现以 ETG.1500 Class B 强制项完整覆盖为第一交付基线，在此基础上继续补齐 Class A 更强调的 ENI/配置工具工作流、完整 CoE 浏览能力、主站对象字典、拓扑变化与 Hot Connect 支持，形成可持续演进的工程路线。
- **从协议栈到验证平台**：通过事件溯源、故障注入、确定性回放与 monitor/verdict 框架，使 MoonECAT 不仅是 EtherCAT 主站，更是可验证、可回放、可解释的工业通信测试执行器。

### 1.3 核心应用场景

#### 场景一：多平台的 CLI、库与配置工作台
MoonECAT 将提供 CLI 和库两种接口，并预留配置工具/网页工作台方向，覆盖本地调试、离线配置和测试从站三类场景。CLI 采用“发现 -> 校验 -> 诊断/执行”命令模型，支持网络扫描、ESI/SII 校验、在线状态迁移、诊断与主站运行；库接口面向嵌入式和上层系统集成，提供稳定 API；配置工作台则承接 ESI/ENI 导入、对象字典浏览与拓扑一致性检查。

#### 场景二：在线诊断与 ENI 配置工具

MoonECAT 可基于 moonbit-pdk 将协议栈逻辑打包为 Extism 插件，通过宿主函数接入网卡、计时和文件能力，并以共享内存缓冲区方式完成 send/recv 数据交换，在桌面端或者服务端对接 rabbita 实现网页 EtherCAT 扫描、诊断、对象字典浏览与 ENI 配置工具。该方向直接对应 EtherCAT_Compendium 中“MainDevice + Configuration Tool + ESI/ENI”的工程形态。
#### 场景三：HIL 验证执行器与确定性回放

基于事件溯源架构，MoonECAT 天然具备"在硬件在环 (HIL) 测试台上捕获事件流，在 PC/浏览器上离线回放"的能力。
- **录制**：嵌入式裸机端以极低开销将硬件事件（帧收发、中断时间戳、WKC）写入 NDJSON 文件或环形缓冲区。
- **回放**：PC 端加载事件流，驱动同一纯函数状态机逐事件推进，可断点、快退、条件搜索。
- **判定**：内置 monitor/verdict 框架，对 DC 同步窗口、WKC 丢包率、状态迁移合规性进行自动化判定，输出 Pass/Warn/Fail 报告。

这使 MoonECAT 不仅是 EtherCAT 主站，更是面向 IEC 62443 / DO-178C 等安全关键领域的**可验证测试执行器**。

#### 场景四：内置分析与自整定引擎

MoonECAT 将在运行时编排层嵌入轻量分析引擎，把传统需要外部示波器或专用诊断软件完成的工作内化为主站能力：
- **DC Jitter Profiling**：逐周期记录 `System Time − Reference Clock` 差值，输出 P95/P99 直方图与趋势告警，无需外部抓包即可评估同步质量。
- **PDO Auto-Tuning**：基于实测 WKC 延迟与 jitter 分布，自动建议或调整 PDO 周期、SM watermark 和重试阈值，降低手动调参成本。
## 2. 交付物说明

### 2.1 拟支持的核心功能与功能边界（Scope）

本项目依据 **ETG.1500 Master Classes** 标准推进，采用“**Class B 全量基线已完成，Class A 为后续目标能力**”的分阶段策略。第一阶段确保基础主站能力与 Native/CLI 交付闭环，第二阶段围绕配置工具、ENI、对象字典产品面深化与主站对象字典等 Class A 能力持续收口。

| 功能模块 | 核心功能点（In Scope） | 说明 / 技术对标 |
|---|---|---|
| 基础架构 | OSAL（操作系统抽象层） | 参考 SOEM，提供 Linux/Windows/RTOS/Extism 插件宿主统一适配接口。 |
| 数据链路层 | 多后端网卡适配 | 支持 Raw Socket（xdp）、Npcap（Windows）、Mock Loopbackd、Extism 插件适配层。 |
| 数据链路层 | Ethernet II 帧封装 | 构建与校验符合 IEEE 802.3 标准的 EtherCAT 帧。 |
| 协议核心 | EtherCAT 状态机（ESM） | 复刻 IgH 逻辑：Init $\\to$ PreOp $\\to$ SafeOp $\\to$ Op，含错误回退。 |
| 协议核心 | 寻址模式 | 支持位置寻址（Auto Increment）与设置站别名寻址（Configured Station Alias）。 |
| 协议核心 | 服务数据对象（CoE） | 已支持 SDO Upload/Download、Segmented Transfer、Complete Access、SDO Info 全流程，并新增 Native `od` 浏览入口。 |
| 协议核心 | 过程数据对象（PDO） | 支持周期性数据交换，支持逻辑寻址（LWR/LRD/LRW）。 |
| 配置与发现 | 自动网络扫描 + ENI 导入 | 支持在线扫描、离线 ENI 导入与两者之间的一致性校验，形成配置工具工作流。 |
| 配置与发现 | FMMU/SM 自动配置 | 根据从站描述自动计算并下发 SyncManager 与 FMMU 映射。 |
| 配置与发现 | 拓扑与身份一致性校验 | 启动阶段校验 Vendor / Product / Revision / Serial、拓扑顺序、显式设备标识与 Hot Connect 约束。 |
| 配置与发现 | 分布式时钟（DC）PLL 锁定算法 | 支持 DC PLL 锁定与同步，确保周期性数据交换的时间一致性。 |
| 运行时编排 | 周期通信调度 | 实现周期性 PDO 交换的调度机制，支持 Free Run 与 DC 同步两种模式。 |
| 运行时编排 | 事务推进机制 | 实现 SDO 读写的请求队列、超时重试与状态推进机制。 |
| 工程工具 | 主站对象字典与诊断表面 | 统一承载主站参数、诊断摘要、错误码与配置视图，支撑 CLI、库和后续配置工具共享同一语义。 |
**Out of Scope**：

- 第一阶段不承诺完整 EoE/FoE/SoE/AoE/VoE 协议栈交付
- 不在 `protocol/`、`mailbox/`、`runtime/` 中引入平台专属分叉
- 不把配置工具能力做成独立第二套协议实现，仍要求复用同一主站核心

### 2.2 预期使用方式

本项目参考 Gatorcat 提供 `moonecat` 命令行工具（CLI）与从站测试套件双入口，覆盖本地调试和测试从站两类场景。

#### 2.2.1 CLI 使用方式

CLI 采用“发现 -> 配置 -> 执行”三阶段命令模型：

```bash
# 1) 发现网络与从站信息
moonecat scan --if eth0 --out artifacts/topology.json

# 2) 校验 ESI/SII/对象字典一致性
moonecat validate --esi ./device.xml --sii ./eeprom.bin

# 3) 运行主站
moonecat run --if eth0 --config ./master_config.json

```

CLI 关键能力：统一参数模型、`free run/dc` 双模式运行。当前已具备 `scan/validate/run/read-sii/state/diagnosis/od` 入口，其中离线 ENI 工作流已改为“`moon run cmd/eni_json -- --input <eni.xml> --output <eni.json>` 先做 XML→JSON 中转，再由 `validate --eni-json <path>` 接入统一比对路径”，并输出 `Pass/Warn/Block` 结论、来源信息与完整差异项；ENI 侧也已补到最小 `SM/FMMU/PDO + mailbox/DC` 摘要。

### 2.2 文档规划
- **开发文档**：涵盖架构设计、接口定义、实现细节与测试指南。
- **用户文档**：涵盖安装指南、CLI 使用手册、测试套件说明与常见问题解答。

### 2.3 阶段交付基线

- **已完成基线**：ETG.1500 Class B 强制项、`scan/validate/run` 主链路、Native CLI 基本入口、SII 在线读取、状态迁移与诊断入口。
- **当前主线交付**：配置工具 / ENI 工作流、对象字典浏览产品化、主站对象字典与统一诊断表面。
- **后续扩展交付**：Hot Connect / 拓扑变化感知、Extism 产品化、多任务与 feature pack 级协议扩展。

### 2.4 交付验收口径

| 交付项 | 当前口径 | 最小验收方式 |
|---|---|---|
| Class B 基线能力 | 以库层能力、测试覆盖与 CLI 闭环为准，不以单一文档声明为准 | `moon test` 通过；Class B 强制项在 [project_workflow/01_baseline_and_roadmap.md](project_workflow/01_baseline_and_roadmap.md) 中保持 17/17 |
| Native CLI 基础入口 | 以 Windows Npcap / Linux Raw Socket 对同一 HAL 契约的可执行性为准 | 至少验证 `list-if`、`scan`、`state`、`diagnosis` 中的代表路径；当前 Windows Npcap `state` 已跑通 |
| 配置工具 / ENI 主线 | 以 online scan 与 ENI import 进入同一配置对象模型为准 | 当前已接入 `cmd/eni_json` 的 XML→JSON 中转工具与 `validate --eni-json <path>` 统一比较路径，并补上完整差异项 JSON 和最小 ENI `SM/FMMU/PDO + mailbox/DC` 摘要；后续继续补统一视图与 offline 配置工具模型 |
| 对象字典浏览产品面 | 以现有 SDO Info / Complete Access / Segmented Transfer 能力是否被 CLI 或配置工具直接消费为准 | CLI 已能浏览 OD list、OD 描述、OE 描述，并提供失败路径分类；后续补配置工具复用 |
| 统一诊断表面 | 以 AL / WKC / DC / 拓扑 / 配置摘要是否汇聚到同一结果对象为准 | CLI、库和配置工具不再各自维护一套状态解释逻辑 |

### 2.5 阶段交付物与验收证据矩阵（L1–L4 成熟度分级）

本项目以 **L1–L4 成熟度等级** 取代原线性 Phase 0–5 分阶段模型，更准确地反映各功能模块的工程成熟度与验收状态。完整条目清单与 Backlog P0-P2 映射详见 [project_workflow/08_integrated_roadmap_and_backlog.md](project_workflow/08_integrated_roadmap_and_backlog.md)。

| 成熟度 | 定义 | 含义 |
|---|---|---|
| **L1 — Foundation** | 基础骨架层 | 包结构、HAL 契约、Frame/PDU 编解码、Mock Loopback、基础测试脚手架 |
| **L2 — Protocol Core** | 协议核心层 | ESM 状态机、PDO 交换、SII/ESI、FMMU/SM、CoE/SDO 全事务、DC PLL、邮箱传输 |
| **L3 — Product Surface** | 产品交付层 | Native CLI 入口、ENI/配置工具、OD 浏览、统一诊断表面、SII 深度读取 |
| **L4 — Verification & Hardening** | 验证与加固层 | 真实设备 smoke、NDJSON 溯源、故障注入、确定性回放、HIL 就绪 |

#### L1 Foundation — 已完成 (9/9)

| 交付物 | 证据 | 对应里程碑 |
|---|---|---|
| 包结构与模块划分 (`hal/`, `protocol/`, `mailbox/`, `runtime/`) | `moon.mod.json` + `moon.pkg` 全绿 | M1 |
| HAL Trait (`NetworkInterface` / `Timer` / `TaskScheduler`) | `hal/hal.mbt` + Mock 实现 | M1 |
| 统一错误模型 (`EcError` ADT) | `hal/error.mbt` 分支穷尽 | M1 |
| Ethernet II 帧编解码 | `protocol/frame.mbt` + round-trip 测试 | M2 |
| PDU 编解码与管线 | `protocol/pdu.mbt` + `pipeline.mbt` | M2 |
| Transact 原语 (`BRD/BWR/APRD/FPRD…`) | `protocol/transact.mbt` | M2 |
| Mock Loopback 后端 | `hal/mock/` 全套 | M2 |
| 固件热加载基础支持 (`fixtures/`) | `fixtures/fixtures.mbt` | M2 |
| 基础测试脚手架 (>50 用例首批) | `moon test` 通过 | M2 |

#### L2 Protocol Core — 已完成 (22/22)

| 交付物 | 证据 | 对应里程碑 |
|---|---|---|
| 网络扫描与从站发现 | `protocol/discovery.mbt` | M3 |
| SII/ESI 在线解析 | `mailbox/sii.mbt` + `sii_parser.mbt` | M3 |
| FMMU/SM 自动配置 | `mailbox/fmmu.mbt` + `mapping.mbt` | M3 |
| 拓扑/身份一致性校验 | `protocol/discovery.mbt` validate 路径 | M3 |
| ESM 状态机 (Init→PreOp→SafeOp→Op + 回退) | `protocol/esm.mbt` + `esm_engine.mbt` | M4 |
| PDO 周期交换 (LWR/LRD/LRW) | `protocol/pdo.mbt` | M4 |
| Runtime 周期调度器 | `runtime/` scheduler | M4 |
| DC 基础框架 | `protocol/dc.mbt` | M4 |
| 设备仿真层 | `hal/mock/` device emulation | M4 |
| CoE SDO Upload/Download | `protocol/sdo_transaction.mbt` | M5 |
| CoE Segmented Transfer | mailbox segmented 路径 | M5 |
| CoE Complete Access | mailbox complete access 路径 | M5 |
| CoE SDO Info | SDO Info 服务 | M5 |
| Mailbox 传输层 | `protocol/mailbox_transport.mbt` | M5 |
| RMSM (Replication Master SM) | `mailbox/rmsm.mbt` | M5 |
| Emergency 协议 | `mailbox/emergency.mbt` | M5 |
| EEPROM 在线读写 | `protocol/eeprom.mbt` | M6 |
| Explicit Device ID | discovery 扩展 | M6 |
| Station Alias 设置 | address 扩展 | M6 |
| 诊断接口 (AL Status Code / Diagnosis History) | `protocol/` + `mailbox/` | M6 |
| DC 初始化与漂移补偿 | `protocol/dc.mbt` 扩展 | M7 |
| DC 同步窗口监控 | DC sync window monitor | M7 |

#### L3 Product Surface — 已完成 (15/15)

| 交付物 | 证据 | 对应里程碑 |
|---|---|---|
| Native CLI `scan` | `cmd/main/` scan 入口 | M8 |
| Native CLI `state` | `cmd/main/` state 入口 | M8 |
| Native CLI `read-sii` | `cmd/main/` read-sii 入口 | M8 |
| Native CLI `diagnosis` | `cmd/main/` diagnosis 入口 | M8 |
| Native CLI `od` (OD 浏览) | `cmd/main/` od 入口 | M8 |
| ENI XML→JSON 中转工具 | `cmd/eni_json/` | M8 |
| `validate --eni-json` 统一比较路径 | validate 入口 + Pass/Warn/Block 输出 | M8 |
| 统一配置对象模型 (online scan ∪ ENI import) | runtime 配置模型 | M8 |
| 统一诊断结果对象 (`DiagnosticSurface`) | runtime 诊断模型 | M8 |
| SII 深度读取 (全 Category 框架) | sii_parser 扩展 | M8 |
| Hot Connect 模型 (拓扑分组约束) | mailbox/ hot connect | M8 |
| 结构化 JSON 输出 (NDJSON progress) | CLI JSON 模式 | M8 |
| Windows Npcap Native 后端 | `hal/native/` npcap | M8 |
| Linux Raw Socket Native 后端 | `hal/native/` raw socket | M8 |
| Extism 插件骨架 | `plugin/extism/` | M8 |

#### L4 Verification & Hardening — 进行中 (7/13)

| 交付物 | 状态 | 证据或计划 |
|---|---|---|
| Windows Npcap 真实设备 smoke | ✅ 已完成 | Realtek USB GbE, station 4097, vendor 1894, product 2320 |
| NDJSON 溯源与可观测性 | ✅ 已完成 | CLI progress 输出 |
| SII 全 Category 深度框架 | ✅ 已完成 | sii_parser 全类别支持 |
| 跨平台语义一致性 (Mock=Native 行为对齐) | ✅ 已完成 | 白盒测试覆盖 |
| 长跑故障检测 (WKC 异常统计) | ✅ 已完成 | runtime 统计 |
| ENI 差异分级报告 (Pass/Warn/Block) | ✅ 已完成 | validate 路径 |
| OD 浏览失败路径分类 | ✅ 已完成 | transport/protocol/unsupported 三类 |
| Linux Raw Socket 真实设备 smoke | ⬚ 待验证 | 编译通过，待实机 |
| Extism 宿主能力对齐 | ⬚ 待完成 | 宿主 FFI 待补齐 |
| 故障注入框架 (Fault Injection) | ⬚ 待实现 | Mock 层注入 + verdict |
| 确定性回放引擎 (Replay Engine) | ⬚ 待实现 | NDJSON → state machine replay |
| Monitor/Verdict 框架 | ⬚ 待实现 | 自动化判定 Pass/Warn/Fail |
| DC Jitter Profiling 与 PDO Auto-Tuning | ⬚ 待实现 | 分析引擎 |

### 2.6 主线收口条件

为避免文档长期停留在“持续补下一步”的状态，当前主线按以下条件判定收口：

- **配置模型收口**：online scan、ENI import、启动比对、差异报告统一进入同一配置对象模型。
- **浏览表面收口**：对象字典浏览具备稳定 CLI 文本输出与 JSON 输出，并能直接被配置工具复用。
- **诊断模型收口**：AL / WKC / DC / 拓扑 / 配置摘要进入同一诊断结果对象，产品面不再重复维护状态解释逻辑。
- **产品面收口**：CLI、库、Extism 宿主三者共享同一配置模型、诊断模型与错误分类。
- **证据收口**：阶段矩阵中的 Phase 2、Phase 3、Phase 4 均具备可复核的命令、测试或文档证据，而不再仅依赖路线描述。

## 3. 技术路线说明

### 3.1 整体系统架构

结合 MoonBit 当前"模块化包管理、静态类型、快速构建测试"和 moonbit-pdk 对 Extism 插件开发的支持，本项目采用"核心纯逻辑 + 平台薄适配 + CLI/测试外壳"的七层架构，并把配置工具/ENI 视作 Product Surface 的自然延伸，而不是额外并行的一套实现。

#### 架构基石：事件溯源 (Event Sourcing)

贯穿全部层次的核心范式：

```
┌─────────────────────────────────────────────────────┐
│  Event Stream (NDJSON / Ring Buffer)                │
│  { kind: "frame_rx", timestamp_ns: 1234, ... }     │
│  { kind: "esm_transition", from: PreOp, to: Op }   │
│  { kind: "wkc_mismatch", expected: 3, actual: 2 }  │
└──────────────────────┬──────────────────────────────┘
                       │ replay / fold
                       ▼
          State' = f(State, Event)
```

- **HAL 职责**：将每一次硬件交互（帧收发、计时器滴答、中断）包装为不可变 Event 结构体，固化 `timestamp_ns`。
- **协议/邮箱层职责**：以纯函数消费 Event 流，输出新状态 + 副作用列表 (side-effects)。
- **运行时职责**：执行副作用、收集新 Event、驱动下一轮 fold。
- **产品面职责**：订阅 Event 流实现 NDJSON 日志、诊断分析、进度报告。

#### Layer 0：Hardware Platform（硬件承载层）

- **定位**：描述 MoonECAT 可运行的硬件形态演进路线。
- **当前形态**：PC (x86/ARM Linux + Windows Npcap)。
- **近期目标**：单核 MCU (Renesas RZ/N2L、HPM6E00、STM32H7)。设计约束——无 MMU、无 heap、≤256 KB SRAM、DMA 描述符零拷贝、ISR ≤ 100 ns。
- **远期展望**：异构 SoC (ARM Cortex-A + FPGA/PRU)。利用 FPGA 卸载帧过滤与时间戳插入，CPU 仅负责协议状态推进。

#### Layer 1：Platform HAL（平台适配层）

- **定位**：封装平台相关能力，不承载协议语义。向上提供不可变 Event 流接口。
- **能力边界**：网卡收发（零拷贝 DMA 描述符 / 用户态 mmap）、计时（纳秒级 `timestamp_ns`）、任务调度、文件与抓包输出。
- **后端实现**：Linux Raw Socket、Windows Npcap、Embedded MAC、Extism 插件适配层；其中插件侧通过共享内存缓冲区与宿主交换收发数据。
- **零拷贝设计**：HAL 不复制帧数据，而是提供 `BorrowedFrame` 引用，协议层在 borrowed window 内完成解码。对于嵌入式后端，直接映射 DMA ring buffer 描述符，ISR 仅翻转 owner bit。
- **接口约束**：通过 `trait` 定义最小接口，统一错误码，便于替换和测试注入。

#### Layer 2：Protocol Core（协议核心层）

- **定位**：以纯 MoonBit 实现核心协议逻辑，最大化可测性与可移植性。
- **核心组件**：帧编解码、PDU 管线、ESM 状态机、寻址与拓扑管理、错误模型。
- **实现原则**：ADT + 模式匹配保证分支穷尽；运行态预分配缓冲区并控制热路径分配；所有状态转换为纯函数 `(State, Event) -> (State, Effects)`。

#### Layer 3：Mailbox & Config（事务与配置层）

- **定位**：承载非周期事务和配置逻辑，避免污染 PDO 热路径。
- **核心组件**：CoE/SoE、SDO、SII/ESI 解析、FMMU/SM 计算。
- **执行模型**：采用“请求队列 + 超时 + 重试 + 关联 ID”的状态推进机制。

#### Layer 4：Runtime Orchestrator（运行编排层）

- **定位**：统一调度周期通信、事务推进、超时治理和背压控制。
- **核心能力**：`PduLoop` 周期收发、Mailbox 分片推进、抖动与重试统计。
- **内置分析引擎**：DC Jitter Profiling（逐周期 $\Delta t = T_{system} - T_{ref}$，输出 P95/P99 直方图）、PDO Auto-Tuning（基于 WKC 延迟与 jitter 分布自动建议周期与阈值）。
- **设计原则**：不绑定特定线程模型，对 Native、Extism、Embedded 采用一致的状态推进接口。

#### Layer 5：Product Surface（产品接口层）

- **库接口**：面向嵌入式和上层系统集成，提供稳定 API。
- **CLI 接口**：面向调试、测试和回归，提供 `scan/validate/run` 命令族。
- **配置工具接口**：面向 ESI/ENI 导入、对象字典浏览、拓扑一致性校验与诊断分析，可由 CLI 或 Extism 宿主承载。
- **设计原则**：CLI、库与配置工具共享同一核心实现，避免双实现分叉。

通过上述架构，MoonECAT 实现"**同一核心、事件溯源、多形态交付、确定性验证**"，与 EtherCAT 从站预符合性验证流程直接对齐。

#### Layer 6：Verification Runtime（验证运行时层）

- **定位**：将 MoonECAT 从通信主站提升为可验证测试执行器。
- **确定性回放**：录入 NDJSON/Ring Buffer Event 流，在 PC/浏览器中驱动同一纯函数状态机逐事件推进，支持断点、快退、条件搜索。
- **故障注入**：Mock HAL 层注入丢帧、WKC 偏差、计时抖动，验证协议栈在异常工况下的行为。
- **Monitor/Verdict 框架**：对 DC 同步窗口、WKC 丢包率、状态迁移合规性自动判定，输出 Pass/Warn/Fail 报告。

### 3.2 三条主线演进路线

围绕 ETG.1500 与 EtherCAT_Compendium，本项目后续以三条主线并行推进（详细拆解见 [08_integrated_roadmap_and_backlog.md](project_workflow/08_integrated_roadmap_and_backlog.md)）：

#### 主线 A：Native Runtime Baseline（P0 — 产品化闭环）

以 Native CLI + 真实设备 smoke 为核心验收证据：
- **配置工具与 ENI 工作流**：已冻结统一配置模型与统一比较路径，已补上最小 ENI XML 投影、统一差异分级与共享 JSON 结果对象；下一步聚焦更完整 offline 配置工具模型。
- **对象字典浏览产品化**：库层已上浮最小 Native CLI `od` 浏览表面，失败路径已形成 `transport-failure / protocol-failure / unsupported` 三分类；下一步聚焦配置工具复用与实机 smoke。
- **主站对象字典与诊断汇聚**：最小统一 `DiagnosticSurface` 已落仓，由 CLI / Extism 共享；下一步补真实从站 smoke 与更完整主站对象字典视图。
- **Linux Raw Socket 实机 smoke**：编译通过，待实机验证。

#### 主线 B：Verification Runtime（P1 — 可验证性保障）

以事件溯源范式为基础，构建确定性验证能力：
- **故障注入框架**：Mock HAL 层注入丢帧、WKC 偏差、计时抖动。
- **确定性回放引擎**：NDJSON Event 流 → 纯函数状态机逐事件推进。
- **Monitor/Verdict 框架**：自动化判定 DC 同步窗口、WKC 丢包率、状态迁移合规性。
- **内置分析引擎**：DC Jitter Profiling 与 PDO Auto-Tuning。

#### 主线 C：HIL-Ready Runtime Boundary（P2 — 硬件就绪）

围绕嵌入式裸机与 SoC 场景持续收口：
- **拓扑变化与 Hot Connect**：显式设备标识、拓扑比较、热插拔分组约束。
- **多任务与后端发布形态**：Multiple Tasks、Native Library、Extism Plugin、嵌入式裁剪版本。
- **HAL 零拷贝实现**：DMA 描述符直接映射、lock-free ring buffer、minimal ISR。
- **Extism 宿主能力对齐与产品化**。

### 3.3 当前主线 Backlog 对齐

当前主线不再以泛化"下一步建议"推进，而以上述三条主线（A/B/C）并行推进，并以 P0-P2 优先级映射到具体 Backlog 条目。完整 Backlog 条目、验收标准与状态追踪统一由 [project_workflow/08_integrated_roadmap_and_backlog.md](project_workflow/08_integrated_roadmap_and_backlog.md) 承载。

当前摘要：

- **P0 条目（主线 A）**：Native Runtime 闭环、ENI 统一配置工具、OD 浏览产品面、统一诊断——已大部分完成，剩余 Linux 实机 smoke 与配置工具复用。
- **P1 条目（主线 B）**：故障注入、确定性回放、Monitor/Verdict、DC Jitter Profiling——待实现。
- **P2 条目（主线 C）**：Hot Connect、Extism 产品化、嵌入式裁剪、lock-free ring buffer——待实现。

## 4. 风险分析与应对方案

### 4.1 核心风险：GC 带来的实时性抖动

**应对**：moonbit的静态类型已经解决大部分问题，剩余的通过预分配缓冲区、运行态对象池和周期内不分配的设计原则来控制抖动，确保满足 EtherCAT 的实时性要求。

### 4.2 工程风险：跨平台网卡接口碎片化

**应对**：定义最小 HAL 接口，分级实现 Linux Raw Socket、Windows Npcap、Mock/插件宿主适配，降低平台差异影响。

### 4.3 协议风险：状态机逻辑死锁

**应对**：采用 moonbit 的静态ADT与模式匹配描述状态流转，结合单元测试和异常工况回放验证错误回退路径。

### 4.4 工程风险：配置漂移与拓扑变更难以定位

**应对**：把启动时网络比较、显式设备标识、AL Status/AL Status Code、Diagnosis History、WKC 异常统计纳入统一诊断表面，并在后续阶段补齐 ENI 对比与 Hot Connect 分组约束，降低“能通信但配置已偏移”的隐性风险。
### 4.5 架构风险：事件溯源模型在嵌入式场景的适用性

**应对**：Event 结构体设计为定长（≤64 字节），Ring Buffer 采用 lock-free SPSC（单生产者单消费者）结构，ISR 仅负责写入 Event 并翻转 owner bit。对于 ≤256 KB SRAM 的 MCU，Event Buffer 容量在编译期由 `const` 配置，编译器可做死代码消除。PC 端回放使用相同代码路径，保证语义一致。

### 4.6 硬件风险：MCU/SoC 平台多样性与验证覆盖

**应对**：HAL 层以最小 trait 接口隔离平台差异，嵌入式后端以板级支持包 (BSP) 形式独立维护。第一批目标 MCU（RZ/N2L、HPM6E00）优先验证 DMA 零拷贝路径与中断延迟；SoC 场景（ARM+FPGA/PRU）以仿真器验证帧过滤卸载逻辑，降低对实际硬件的依赖。

### 4.7 验证风险：确定性回放的事件完整性

**应对**：Event 流以 NDJSON 格式落盘，每行自描述（含 `kind`、`timestamp_ns`、payload），丢失单行不影响后续解析。回放引擎在启动时校验事件流连续性（时间戳单调递增、序列号无跳变），对不完整流输出降级而非崩溃。
## 5. 实施基础与参考依据

### 5.1 开源项目基础

- **IgH EtherCAT Master**：提供标准 FSM 行为参考。
- **SOEM**：证明了 OSAL 与库化设计的可行性。
- **EtherCrab**：验证了现代安全语言和异步 API 的可行路线。
- **Gatorcat**：提供库/CLI 双模式的工程启发。
- **CherryECAT**：为 MCU 场景下的轻量化实现提供参考。
- **EtherCAT.NET**：提供了 C# 语言通过共享内存与宿主交互的实践经验。
- **EtherCAT_Compendium + ETG.1500**：提供配置工具、ENI、拓扑比较、诊断与主站能力分级的标准化路线，是项目从 Class B 基线继续迈向 Class A 的主要依据。

### 5.2 当前实现与验证基线

- **测试基线**：当前仓库 `moon test` 已通过，可作为回归与交付前最小闸门。
- **Native CLI 基线**：Windows Npcap 路径下 `moon run cmd/main state -- --backend native-windows-npcap --if <interface>` 已成功执行，可作为真实 NIC 状态迁移入口的最小 smoke 证据。
- **协议能力基线**：Class B 强制项、CoE segmented / complete access / SDO Info 库层事务、SII 在线读取、诊断 helper 与 Native `state/diagnosis` 入口均已落仓。
- **文档基线**：后续交付说明、任务拆解、参考实现核对与发布物矩阵分别由本文件、[project_workflow/README.md](project_workflow/README.md)、[docs/REFERENCE_CONSTRAINTS.md](docs/REFERENCE_CONSTRAINTS.md)、[docs/BACKEND_RELEASE_MATRIX.md](docs/BACKEND_RELEASE_MATRIX.md) 承担。





参考资料：
- [EtherCAT Conformance Test Tool（CTT）ET9400](https://www.ethercat.org/en/downloads/downloads_9C14719DA04D4912AE8611D7AA4546F2.htm)
- [ETG.1500 Master Classes.](src/ETG1500_V1i0i2_D_R_MasterClasses.pdf)
- [ETG.1000 EtherCAT System Architecture.](https://www.ethercat.org/en/downloads/downloads_A02E436C7A97479F9261FDFA8A6D71E5.htm)
- [IgH EtherCAT Master](https://gitlab.com/etherlab.org/ethercat) 
[Igh callflow analysis](src/IgH-callflow-analysis.md)
- [SOEM (Simple Open EtherCAT Master)](https://github.com/OpenEtherCATsociety/SOEM) 
[SOEM callflow analysis](src/SOEM-callflow-analysis.md)
- [EtherCrab](https://github.com/ethercrab-rs/ethercrab) 
[EtherCrab callflow analysis](src/EtherCrab-callflow-analysis.md)
- [Gatorcat](https://codeberg.org/jeffective/gatorcat)
 [Gatorcat callflow analysis](src/gatorcat-callflow-analysis.md)
- [CherryECAT](https://github.com/cherry-embedded/CherryECAT) 
[CherryECAT callflow analysis](src/CherryECAT-callflow-analysis.md)
- [EtherCAT.NET](https://github.com/XzuluX/EtherCAT.NET) 
[EtherCAT.NET callflow analysis](src/EtherCAT.net-callflow-analysis.md)