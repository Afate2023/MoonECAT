# MoonECAT 交付基线说明（原项目申报书）

- **交付对象**：MoonECAT —— 基于 MoonBit 的全场景、模块化、下一代 EtherCAT 主站库
- **文档用途**：该文档已从立项申报材料转为后续交付基线说明，用于统一范围、阶段目标、验收边界与实施路线。

## 1. 项目目标与应用场景

### 1.1 行业背景与痛点分析

EtherCAT 是工业自动化中应用最广泛的实时以太网协议之一，主站协议栈的实现直接影响控制系统的实时性、稳定性与研发效率。当前开源生态在“工程化工具链”之间仍存在明显断层。

#### 配置工具链的割裂

传统 EtherCAT 工程仍普遍依赖外部商业软件或脚本工具完成 ESI/ENI 解析、对象字典检查和诊断，协议栈与工具链长期割裂，难以形成统一的自动化工程流。

#### 主站能力与工程目标错位

依据 ETG.1500 Master Classes，工程落地并不应停留在“能跑通基础扫描和 PDO 通信”的 Class B 基线，而应尽量向 Class A 靠拢，把在线扫描、离线 ENI、对象字典浏览、诊断与拓扑一致性校验统一到一套主站能力中。EtherCAT_Compendium 也明确体现了“配置工具 + ESI/ENI + 启动一致性校验 + 在线诊断”是一条完整工程链路，而不是彼此独立的附属功能。

### 1.2 项目核心目标

本项目利用 MoonBit 的快速编译、内存安全和多后端能力，持续交付全场景、高可靠、模块化的 EtherCAT 主站库 **MoonECAT**，并以统一核心实现支撑 CLI、库和后续配置工具形态。

具体目标包括：

- **内存安全与轻量实时**：借鉴 EtherCrab 的静态 PDU 存储与 CherryECAT 的轻量化实现思路,通过 MoonBit 的静态类型，在保证内存安全的同时控制运行态抖动，目标满足严苛实时要求。
- **统一抽象与跨平台部署**：参考 SOEM 的 OSAL 设计和 Gatorcat 的库/CLI 双模式思路，使同一协议栈可运行于 Linux、裸机/RTOS，并可通过 moonbit-pdk 打包为 Extism 插件，以共享内存缓冲区方式与宿主协同收发数据。
- **以 Class B 为基线、以 Class A 为目标**：当前实现以 ETG.1500 Class B 强制项完整覆盖为第一交付基线，在此基础上继续补齐 Class A 更强调的 ENI/配置工具工作流、完整 CoE 浏览能力、主站对象字典、拓扑变化与 Hot Connect 支持，形成可持续演进的工程路线。

### 1.3 核心应用场景

#### 场景一：多平台的 CLI、库与配置工作台
MoonECAT 将提供 CLI 和库两种接口，并预留配置工具/网页工作台方向，覆盖本地调试、离线配置和测试从站三类场景。CLI 采用“发现 -> 校验 -> 诊断/执行”命令模型，支持网络扫描、ESI/SII 校验、在线状态迁移、诊断与主站运行；库接口面向嵌入式和上层系统集成，提供稳定 API；配置工作台则承接 ESI/ENI 导入、对象字典浏览与拓扑一致性检查。

#### 场景二：在线诊断与 ENI 配置工具

MoonECAT 可基于 moonbit-pdk 将协议栈逻辑打包为 Extism 插件，通过宿主函数接入网卡、计时和文件能力，并以共享内存缓冲区方式完成 send/recv 数据交换，在桌面端或者服务端对接 rabbita 实现网页 EtherCAT 扫描、诊断、对象字典浏览与 ENI 配置工具。该方向直接对应 EtherCAT_Compendium 中“MainDevice + Configuration Tool + ESI/ENI”的工程形态。

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

CLI 关键能力：统一参数模型、`free run/dc` 双模式运行。当前已具备 `scan/validate/run/read-sii/state/diagnosis/od` 入口，其中 `validate --eni <path>` 已可把离线 ENI 文件接入统一比对路径，并输出 `Pass/Warn/Block` 结论与来源信息；后续补完整差异项与更细粒度配置摘要。

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
| Class B 基线能力 | 以库层能力、测试覆盖与 CLI 闭环为准，不以单一文档声明为准 | `moon test` 通过；Class B 强制项在 [MoonECAT-AI任务清单.md](MoonECAT-AI任务清单.md) 中保持 17/17 |
| Native CLI 基础入口 | 以 Windows Npcap / Linux Raw Socket 对同一 HAL 契约的可执行性为准 | 至少验证 `list-if`、`scan`、`state`、`diagnosis` 中的代表路径；当前 Windows Npcap `state` 已跑通 |
| 配置工具 / ENI 主线 | 以 online scan 与 ENI import 进入同一配置对象模型为准 | 当前已接入 `validate --eni <path>`、统一比较路径与 `Pass/Warn/Block` 分级，并补上最小 ENI XML + `SM/RxPDO/TxPDO` 摘要；后续继续补完整差异项和统一视图 |
| 对象字典浏览产品面 | 以现有 SDO Info / Complete Access / Segmented Transfer 能力是否被 CLI 或配置工具直接消费为准 | CLI 已能浏览 OD list、OD 描述、OE 描述，并提供失败路径分类；后续补配置工具复用 |
| 统一诊断表面 | 以 AL / WKC / DC / 拓扑 / 配置摘要是否汇聚到同一结果对象为准 | CLI、库和配置工具不再各自维护一套状态解释逻辑 |

### 2.5 阶段交付物与验收证据矩阵

| 阶段 | 交付物 | 当前状态 | 主要证据 |
|---|---|---|---|
| Phase 0 | Class B 基线能力、库层主链路、基础测试闭环 | 已完成 | [MoonECAT-AI任务清单.md](MoonECAT-AI任务清单.md) 中 Class B 17/17；`moon test` 通过 |
| Phase 1 | Native CLI 基础表面：`list-if`、`scan`、`read-sii`、`state`、`diagnosis` | 已形成最小交付 | Windows Npcap 路径 `state` smoke 成功；Native CLI 相关条目已在任务清单与发布矩阵落账 |
| Phase 2 | 配置工具 / ENI 主线：统一配置对象、差异报告、配置工作流 | 已进入统一产品面收口阶段 | 已新增 runtime 统一配置模型与统一比较路径，CLI 已支持 `validate --eni <path>`，并补上 `Pass/Warn/Block` 分级与最小 ENI `SM/RxPDO/TxPDO` 摘要；后续证据聚焦完整差异列表、FMMU/mailbox/DC 摘要与统一拓扑视图 |
| Phase 3 | 对象字典浏览产品化：CLI / 配置工具可直接消费的浏览表面 | 已形成最小 CLI 交付，继续收口 | Native `od` 命令已可输出 `OD List` / `OD Description` / `OE Description` 的文本与 JSON 结果，并能区分 `transport-failure` / `protocol-failure` / `unsupported`；后续证据聚焦配置工具复用 |
| Phase 4 | 主站对象字典与统一诊断表面 | 未开始 | 后续以结果对象、CLI 统一输出、配置工具复用为主要证据 |
| Phase 5 | Hot Connect / 拓扑变化感知 / Extism 产品化 | 规划中 | 后续以拓扑差异告警、宿主能力对齐和最小集成回放为主要证据 |

### 2.6 主线收口条件

为避免文档长期停留在“持续补下一步”的状态，当前主线按以下条件判定收口：

- **配置模型收口**：online scan、ENI import、启动比对、差异报告统一进入同一配置对象模型。
- **浏览表面收口**：对象字典浏览具备稳定 CLI 文本输出与 JSON 输出，并能直接被配置工具复用。
- **诊断模型收口**：AL / WKC / DC / 拓扑 / 配置摘要进入同一诊断结果对象，产品面不再重复维护状态解释逻辑。
- **产品面收口**：CLI、库、Extism 宿主三者共享同一配置模型、诊断模型与错误分类。
- **证据收口**：阶段矩阵中的 Phase 2、Phase 3、Phase 4 均具备可复核的命令、测试或文档证据，而不再仅依赖路线描述。

## 3. 技术路线说明

### 3.1 整体系统架构

结合 MoonBit 当前“模块化包管理、静态类型、快速构建测试”和 moonbit-pdk 对 Extism 插件开发的支持，本项目采用“核心纯逻辑 + 平台薄适配 + CLI/测试外壳”的六层架构，并把配置工具/ENI 视作 Product Surface 的自然延伸，而不是额外并行的一套实现。

#### Layer 1：Platform HAL（平台适配层）

- **定位**：封装平台相关能力，不承载协议语义。
- **能力边界**：网卡收发、计时、任务调度、文件与抓包输出。
- **后端实现**：Linux Raw Socket、Windows Npcap、Embedded MAC、Extism 插件适配层；其中插件侧通过共享内存缓冲区与宿主交换收发数据。
- **接口约束**：通过 `trait` 定义最小接口，统一错误码，便于替换和测试注入。

#### Layer 2：Protocol Core（协议核心层）

- **定位**：以纯 MoonBit 实现核心协议逻辑，最大化可测性与可移植性。
- **核心组件**：帧编解码、PDU 管线、ESM 状态机、寻址与拓扑管理、错误模型。
- **实现原则**：ADT + 模式匹配保证分支穷尽；运行态预分配缓冲区并控制热路径分配。

#### Layer 3：Mailbox & Config（事务与配置层）

- **定位**：承载非周期事务和配置逻辑，避免污染 PDO 热路径。
- **核心组件**：CoE/SoE、SDO、SII/ESI 解析、FMMU/SM 计算。
- **执行模型**：采用“请求队列 + 超时 + 重试 + 关联 ID”的状态推进机制。

#### Layer 4：Runtime Orchestrator（运行编排层）

- **定位**：统一调度周期通信、事务推进、超时治理和背压控制。
- **核心能力**：`PduLoop` 周期收发、Mailbox 分片推进、抖动与重试统计。
- **设计原则**：不绑定特定线程模型，对 Native、Extism、Embedded 采用一致的状态推进接口。

#### Layer 5：Product Surface（产品接口层）

- **库接口**：面向嵌入式和上层系统集成，提供稳定 API。
- **CLI 接口**：面向调试、测试和回归，提供 `scan/validate/run` 命令族。
- **配置工具接口**：面向 ESI/ENI 导入、对象字典浏览、拓扑一致性校验与诊断分析，可由 CLI 或 Extism 宿主承载。
- **设计原则**：CLI、库与配置工具共享同一核心实现，避免双实现分叉。

通过上述架构，MoonECAT 实现“同一核心、双重入口、多平台落地、测试闭环”，与 EtherCAT 从站预符合性验证流程直接对齐。

### 3.2 Class A 演进路线

围绕 ETG.1500 与 EtherCAT_Compendium，本项目后续演进重点如下：

- **配置工具与 ENI 工作流**：在在线扫描之外，补齐 ENI 导入、离线配置生成、启动时网络对比和差异报告，使 MoonECAT 能承载完整工程流，而不只是一套通信库。当前已先冻结统一配置模型与统一比较路径，并补上最小 ENI XML 投影，避免后续继续扩展 ENI 字段时再形成第二套校验语义；下一步聚焦 SM/FMMU/PDO 摘要、统一差异分级与配置工具消费模型。
- **对象字典浏览产品化**：库层能力已上浮出最小 Native CLI `od` 浏览表面，可直接浏览 `OD List` / `OD Description` / `OE Description`，失败路径也已形成稳定分类；下一步聚焦配置工具复用与实机 smoke 证据。
- **主站对象字典与诊断汇聚**：构建统一的主站对象字典和诊断表面，承载 AL Status、WKC、Diagnosis History、DC 状态、配置摘要等信息，减少 CLI/宿主各自维护状态解释逻辑。
- **拓扑变化与 Hot Connect**：参考 EtherCAT_Compendium 对显式设备标识、拓扑比较、热插拔分组的说明，逐步支持更强的启动自检与在线变化感知。
- **多任务与后端发布形态**：在 Free Run / DC 基线稳定后，再向 ETG.1500 中的 Multiple Tasks、Native Library、Extism Plugin、嵌入式裁剪版本扩展，保持一套协议语义，多种产品形态。

### 3.3 当前主线 Backlog 对齐

当前主线不再以泛化“下一步建议”推进，而以三条收口主线并行推进：

- **配置工具 / ENI 主线**：统一配置对象、差异报告与配置工作流。
- **对象字典浏览产品化**：把库层 CoE 浏览能力上浮为 CLI / 配置工具可直接消费的稳定表面。
- **主站对象字典与统一诊断表面**：形成跨产品面共享的结果对象和错误分级。

上述三条主线收口后，剩余工作将主要转入 Hot Connect、Native 实机闭环、Extism 产品化等后续扩展交付。

## 4. 风险分析与应对方案

### 4.1 核心风险：GC 带来的实时性抖动

**应对**：moonbit的静态类型已经解决大部分问题，剩余的通过预分配缓冲区、运行态对象池和周期内不分配的设计原则来控制抖动，确保满足 EtherCAT 的实时性要求。

### 4.2 工程风险：跨平台网卡接口碎片化

**应对**：定义最小 HAL 接口，分级实现 Linux Raw Socket、Windows Npcap、Mock/插件宿主适配，降低平台差异影响。

### 4.3 协议风险：状态机逻辑死锁

**应对**：采用 moonbit 的静态ADT与模式匹配描述状态流转，结合单元测试和异常工况回放验证错误回退路径。

### 4.4 工程风险：配置漂移与拓扑变更难以定位

**应对**：把启动时网络比较、显式设备标识、AL Status/AL Status Code、Diagnosis History、WKC 异常统计纳入统一诊断表面，并在后续阶段补齐 ENI 对比与 Hot Connect 分组约束，降低“能通信但配置已偏移”的隐性风险。

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
- **文档基线**：后续交付说明、任务拆解、参考实现核对与发布物矩阵分别由本文件、[MoonECAT-AI任务清单.md](MoonECAT-AI任务清单.md)、[docs/REFERENCE_CONSTRAINTS.md](docs/REFERENCE_CONSTRAINTS.md)、[docs/BACKEND_RELEASE_MATRIX.md](docs/BACKEND_RELEASE_MATRIX.md) 承担。





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