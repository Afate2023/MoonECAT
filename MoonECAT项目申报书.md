# MoonECAT 项目申报书

- **项目名称**：MoonECAT —— 基于 MoonBit 的全场景、模块化、下一代 EtherCAT 主站库

## 1. 项目目标与应用场景

### 1.1 行业背景与痛点分析

EtherCAT 是工业自动化中应用最广泛的实时以太网协议之一，主站协议栈的实现直接影响控制系统的实时性、稳定性与研发效率。当前开源生态在“工程化工具链”之间仍存在明显断层。

#### 配置工具链的割裂

传统 EtherCAT 工程仍普遍依赖外部商业软件或脚本工具完成 ESI/ENI 解析、对象字典检查和诊断，协议栈与工具链长期割裂，难以形成统一的自动化工程流。

### 1.2 项目核心目标

本项目以“AI 原生软件工厂”为理念，利用 MoonBit 的快速编译、内存安全和多后端能力，构建全场景、高可靠、模块化的下一代 EtherCAT 主站库 **MoonECAT**。

具体目标包括：

- **内存安全与轻量实时**：借鉴 EtherCrab 的静态 PDU 存储与 CherryECAT 的轻量化实现思路,通过 MoonBit 的静态类型，在保证内存安全的同时控制运行态抖动，目标满足严苛实时要求。
- **统一抽象与跨平台部署**：参考 SOEM 的 OSAL 设计和 Gatorcat 的库/CLI 双模式思路，使同一协议栈可运行于 Linux、裸机/RTOS，并可通过 moonbit-pdk 打包为 Extism 插件，以共享内存缓冲区方式与宿主协同收发数据。

### 1.3 核心应用场景

#### 场景一：多平台的cli和库
MoonECAT 将提供 CLI 和库两种接口，覆盖本地调试和测试从站两类场景。CLI 采用“发现 -> 配置 -> 执行”三阶段命令模型，支持网络扫描、ESI/SII 校验和主站运行等功能；库接口面向嵌入式和上层系统集成，提供稳定 API。

#### 场景二：在线诊断工具(应用方向)

MoonECAT 可基于 moonbit-pdk 将协议栈逻辑打包为 Extism 插件，通过宿主函数接入网卡、计时和文件能力，并以共享内存缓冲区方式完成 send/recv 数据交换，在桌面端或者服务端对接rabbita实现网页 EtherCAT 扫描、诊断与配置工具。

## 2. 交付物说明

### 2.1 拟支持的核心功能与功能边界（Scope）

本项目依据 **ETG.1500 Master Classes** 标准，聚焦 **Class B（Basic）** 核心能力，并兼顾现代嵌入式工程需求。

| 功能模块 | 核心功能点（In Scope） | 说明 / 技术对标 |
|---|---|---|
| 基础架构 | OSAL（操作系统抽象层） | 参考 SOEM，提供 Linux/Windows/RTOS/Extism 插件宿主统一适配接口。 |
| 数据链路层 | 多后端网卡适配 | 支持 Raw Socket（xdp）、Npcap（Windows）、Mock Loopbackd、Extism 插件适配层。 |
| 数据链路层 | Ethernet II 帧封装 | 构建与校验符合 IEEE 802.3 标准的 EtherCAT 帧。 |
| 协议核心 | EtherCAT 状态机（ESM） | 复刻 IgH 逻辑：Init $\\to$ PreOp $\\to$ SafeOp $\\to$ Op，含错误回退。 |
| 协议核心 | 寻址模式 | 支持位置寻址（Auto Increment）与设置站别名寻址（Configured Station Alias）。 |
| 协议核心 | 服务数据对象（CoE） | 支持 SDO Upload/Download，支持 SDO Info Service。 |
| 协议核心 | 过程数据对象（PDO） | 支持周期性数据交换，支持逻辑寻址（LWR/LRD/LRW）。 |
| 配置与发现 | 自动网络扫描 | 读取从站 SII（EEPROM），自动识别 Vendor ID / Product Code。 |
| 配置与发现 | FMMU/SM 自动配置 | 根据从站描述自动计算并下发 SyncManager 与 FMMU 映射。 |
| 配置与发现 | 分布式时钟（DC）PLL 锁定算法 | 支持 DC PLL 锁定与同步，确保周期性数据交换的时间一致性。 |
| 运行时编排 | 周期通信调度 | 实现周期性 PDO 交换的调度机制，支持 Free Run 与 DC 同步两种模式。 |
| 运行时编排 | 事务推进机制 | 实现 SDO 读写的请求队列、超时重试与状态推进机制。 |
**Out of Scope**：

- EoE、FoE

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

CLI 关键能力：统一参数模型、`free run/dc` 双模式运行。

### 2.2 文档规划
- **开发文档**：涵盖架构设计、接口定义、实现细节与测试指南。
- **用户文档**：涵盖安装指南、CLI 使用手册、测试套件说明与常见问题解答。

## 3. 技术路线说明

### 3.1 整体系统架构

结合 MoonBit 当前“模块化包管理、静态类型、快速构建测试”和 moonbit-pdk 对 Extism 插件开发的支持，本项目采用“核心纯逻辑 + 平台薄适配 + CLI/测试外壳”的六层架构。

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
- **设计原则**：CLI 与库共享同一核心实现，避免双实现分叉。

通过上述架构，MoonECAT 实现“同一核心、双重入口、多平台落地、测试闭环”，与 EtherCAT 从站预符合性验证流程直接对齐。

## 4. 风险分析与应对方案

### 4.1 核心风险：GC 带来的实时性抖动

**应对**：moonbit的静态类型已经解决大部分问题，剩余的通过预分配缓冲区、运行态对象池和周期内不分配的设计原则来控制抖动，确保满足 EtherCAT 的实时性要求。

### 4.2 工程风险：跨平台网卡接口碎片化

**应对**：定义最小 HAL 接口，分级实现 Linux Raw Socket、Windows Npcap、Mock/插件宿主适配，降低平台差异影响。

### 4.3 协议风险：状态机逻辑死锁

**应对**：采用 moonbit 的静态ADT与模式匹配描述状态流转，结合单元测试和异常工况回放验证错误回退路径。

## 5. 相关研究与实践基础

### 5.1 开源项目基础

- **IgH EtherCAT Master**：提供标准 FSM 行为参考。
- **SOEM**：证明了 OSAL 与库化设计的可行性。
- **EtherCrab**：验证了现代安全语言和异步 API 的可行路线。
- **Gatorcat**：提供库/CLI 双模式的工程启发。
- **CherryECAT**：为 MCU 场景下的轻量化实现提供参考。
- **EtherCAT.NET**：提供了 C# 语言通过共享内存与宿主交互的实践经验。

### 5.2 个人实践积累

申报人拥有从应用层到链路层的完整实践经验：

- **全栈主站开发**：具备跨平台 EtherCAT 上位机和对象字典调试界面开发经验。
- **链路层验证**：具备 Raw Socket 发包、SII 读取与 FMMU 配置实践。
- **配置算法研究**：具备 ESI XML 与 EEPROM 数据双向转换能力。

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