# MoonECAT 统一路线图与 Backlog（整合版）

> 本文件整合原 `docs/ROADMAP.md` 与 `docs/BACKLOG.md` 的全部内容，按 L1-L4 成熟度与 P0-P2 优先级统一管理。
> 原独立文件仅保留索引指向。

---

## 0. 定位声明

MoonECAT 的后续路线目标不是"补更多主站功能"，而是：

> **基于事件溯源的极速可验证工业互联架构——  
> 先把 Native 主站做成可信执行器，再把验证能力做成原生能力，最后把它接成 MCU + Linux 协同 HIL 的通信内核。**

---

## 1. 成熟度分层：L1 – L4

MoonECAT 把全部已交付与规划工作按四个成熟度等级归类：

| 等级 | 名称 | 定义 | 典型验收方式 |
|:---:|---|---|---|
| **L1** | **Foundation（基础骨架）** | 包结构、HAL trait、帧/PDU 编解码、Mock loopback、测试骨架 | `moon check` + 编解码 roundtrip 通过 |
| **L2** | **Protocol Core（协议闭环）** | ESM、PDO、SII/ESI、FMMU/SM、发现、CoE/SDO、DC、邮箱弹性层 | 库层事务闭环 + 回放测试 ≥95% 分支 |
| **L3** | **Product Surface（产品交付）** | Native CLI、ENI/配置工具统一模型、OD 浏览、统一诊断、SII 深读、拓扑分级 | CLI 稳定文本/JSON 输出 + 实机或回放证据 |
| **L4** | **Verification & Hardening（验证加固）** | 实机 smoke 闭环、NDJSON trace 冻结、长跑故障检测、事件溯源回放、fault injection、HIL 边界 | 真实从站可复现 + 跨平台证据矩阵 |

---

## 2. 已完成事项审计（截至 2026-03-31）

### L1 — Foundation ✅ 完成

| ID | 完成事项 | 里程碑 | 关键提交 |
|---|---|---|---|
| L1-01 | MoonBit 包结构与目录边界（hal/protocol/mailbox/runtime/cmd/fixtures） | M1 | `daf1957` |
| L1-02 | HAL 最小接口：Nic/Clock/FileAccess trait + EcError 16 变体 | M1 | `fb12340` |
| L1-03 | 核心配置对象：MasterConfig/NicConfig/SlaveIdentity/SlaveConfig | M1 | `fb12340` |
| L1-04 | Library API + CLI 入口占位 | M1 | `daf1957` |
| L1-05 | 测试骨架与样例夹具 (~163 tests) | M1 | `4921fdf` |
| L1-06 | Ethernet II + EtherCAT 帧编解码（EtherType 0x88A4） | M2 | `7d4a727` |
| L1-07 | PDU 编解码与管线原语（15 种 EcCommand） | M2 | `6ca34be` |
| L1-08 | Mock Loopback 后端（MockNic + MockClock） | M2 | `641fc49` |
| L1-09 | 统一 transact/transact_pdu/transact_pdu_retry 收发流程 | M2 | `5ab7859` |

### L2 — Protocol Core ✅ 完成

| ID | 完成事项 | 里程碑 | 关键提交 |
|---|---|---|---|
| L2-01 | 基础从站发现（BRD count_slaves, APWR assign_address） | M3 | `ea96328` |
| L2-02 | SII/ESI 解析（header/general/strings/fmmu/sm/pdo） | M3 | `a8be821` |
| L2-03 | FMMU/SM 自动配置计算 | M3 | `bfbe7d5` |
| L2-04 | Vendor/Product/Revision/Serial 4-tuple 校验 | M3 | `3a08bff` |
| L2-05 | ESM 状态机 Init/PreOp/SafeOp/Op/Boot + 回退路径 | M4 | `b4019b1` |
| L2-06 | PDO 周期交换 pdo_exchange (LRW + logical addressing) | M4 | `cfd6f14` |
| L2-07 | Runtime 调度器 + Telemetry（cycles/tx/rx/timeouts/retries/wkc_errors） | M4 | `ddc6158` |
| L2-08 | Device Emulation 感知 + OpOnly 标志 | M4 | `89f0cc4` |
| L2-09 | ESM 超时策略（EsmTimeoutPolicy + 默认值 + 可覆盖） | M4 | `51ab95c` |
| L2-10 | SDO Upload/Download 事务闭环 | M5 | `698052c` |
| L2-11 | Mailbox Resilient Layer (RMSM) | M5 | `89f0cc4` / `62c4742` |
| L2-12 | Mailbox polling + Emergency Message 接收 | M5 | `89f0cc4` |
| L2-13 | SDO 分段传输（上传 + 下载 + toggle） | M5 | `27b9c4b` / `9266591` |
| L2-14 | SDO Complete Access（上传/下载 + 分段续传） | M5 | `afb1a29` / `9266591` |
| L2-15 | SDO Info Service（OD List / OD Description / OE Description） | M5 | `0971f77` |
| L2-16 | EEPROM/SII 寄存器级读取（ESC 0x0502-0x0508） | M6 | `89f0cc4` |
| L2-17 | Explicit Device Identification + 显式标识校验 | M6 | `9ce7516` / `9284ede` |
| L2-18 | Station Alias Addressing (0x0012 + Bit24) | M6 | `fbb3745` |
| L2-19 | Error Register / Diagnosis Counter / Slave Diagnosis 接口 | M6 | `9541967` / `fa72af8` |
| L2-20 | DC 初始化 + SYNC0 配置 + FRMW 漂移补偿 | M7 | `ce48f37` |
| L2-21 | Continuous Propagation Delay compensation（运行态周期重估） | M7 | `0971f77` |
| L2-22 | Sync Window Monitoring (0x092C) | M7 | `ce48f37` |

### L3 — Product Surface ✅ 已形成最小产品面

| ID | 完成事项 | 里程碑 | 关键提交 |
|---|---|---|---|
| L3-01 | CLI scan/validate/run 命令接入 | M8 | `9541967` |
| L3-02 | CLI `list-if` / `read-sii` / `state` / `diagnosis` / `od` Native 入口 | M8 | `26166fc` / `f01a411` / `fcc384e` |
| L3-03 | Windows Npcap Native 后端（动态加载 + FFI） | M8 | `c873347` / `4eabaf7` |
| L3-04 | Linux Raw Socket Native 后端（errno 分类 + link-down 检测） | M8 | `2058971` |
| L3-05 | Native 自动候选网卡筛选与 BRD 探测 | M8 | `bff2f5e` |
| L3-06 | 统一配置对象模型（ConfigurationModel / ConfigurationSlave） | M8 | `d2ba48d` |
| L3-07 | ENI XML→JSON 中转 + validate --eni-json 统一比对 + Pass/Warn/Block | M8 | `fa82594` / `6f4241a` / `121cafa` |
| L3-08 | ESI XML→JSON 共享桥 + esi-sii 投影 | M8 | `1e23be5` / `3330009` |
| L3-09 | 对象字典浏览 CLI（OD List/OD Desc/OE Desc + 错误分类） | M8 | `fcc384e` / `f8f75bd` |
| L3-10 | 统一诊断表面 DiagnosticSurface / DiagnosticIssue | M8 | `d7e6c6a` |
| L3-11 | Hot Connect 拓扑分级（SlavePresence: Mandatory/Optional） | M8 | `0a602b2` |
| L3-12 | SII 完整类别深读框架（ETG.2010 全量 category 建模） | M8 | `43b36e8` / `ebbaf31` |
| L3-13 | SII category class 导出 + overlay 挂载点 + decoder 状态合同 | M8 | `ff93f64` / `ca0a906` / `b024aec` |
| L3-14 | Extism 插件骨架 + envelope + Mock 回放入口 | M8 | `2484759` / `9cc3456` |
| L3-15 | 多后端发布物矩阵文档 | M8 | `5583dcb` |

### L4 — Verification & Hardening ⚠️ 部分完成

| ID | 完成事项 | 状态 | 关键提交 / 证据 |
|---|---|---|---|
| L4-01 | Windows Npcap 真实从站 `list-if → scan → validate → read-sii → diagnosis → state → od → run` 完整链路 | ✅ | Realtek USB GbE / station 4097 / vendor 1894 / product 2320 / cycles_ok=10 |
| L4-02 | 空总线行为基线（0 slaves / PASS / Done） | ✅ | `1a38d47` |
| L4-03 | NDJSON 运行进度与故障汇总 | ✅ | `0bda199` / `23c85c1` |
| L4-04 | 长跑控制 + 连续超时故障检测 (--until-fault) | ✅ | `71f178e` |
| L4-05 | Native FFI 句柄安全策略文档（整数句柄 ID + C stub 内部句柄表） | ✅ | `docs/NATIVE_FFI_SAFETY.md` |
| L4-06 | 回放集成测试 scan→validate→run→stop | ✅ | `898616e` |
| L4-07 | 压力回归（1000 周期稳定性 + telemetry 单调性） | ✅ | `e4bff92` |
| L4-08 | Linux Raw Socket 实机闭环 | ❌ | 待验证 |
| L4-09 | AddressSanitizer / 等价内存安全检查 | ❌ | 未执行 |
| L4-10 | Extism 宿主 host capability 打通 | ❌ | 仅 Mock 回放 |
| L4-11 | 事件溯源 deterministic replay 最小闭环 | ✅ | `e4b03a2` / `fa33f01`：RecordingNic + ReplayNic + NicEventLog；多从站 FMMU PDO 确定性回放 + 多周期输入变化回放，hal/mock 53/53 |
| L4-12 | Fault injection 一等模型 | ✅ | `ba7356e` / `fa33f01`：FaultInjector + FaultNic（7 fault × 5 schedule）；多从站 FMMU RecvTimeout/WkcCorrupt/CountDown 恢复，hal/mock 53/53 |
| L4-13 | Monitor / Verdict 框架 | ✅ | `7af544f`：Verdict(Pass/Warn/Fail/Block) + 6 内置 monitor + run_monitors + DiagnosticSurface 集成；runtime 测试全量覆盖 |

**综合进度**：L1/L2 全部完成，L3 已形成最小产品面，L4 验证加固层约 77% 完成（10/13）。

---

## 3. 三条主线路线图

### 主线 A：Native Runtime Baseline（P0 优先级）

目标：把 Windows Npcap 与 Linux Raw Socket 收敛成同一 Native HAL 合同，形成稳定实机闭环与运行证据。

| 编号 | 任务 | 对应 BACKLOG | 状态 | 涉及目录 |
|---|---|---|---|---|
| A-1 | 统一 Windows/Linux Native HAL 语义（open/send/recv/close/error/filter） | P0-1 | ⚠️ 部分 | hal/native/, cmd/main/ |
| A-2 | Linux Raw Socket 实机闭环 `list-if → scan → validate → run` | P0-2 | ❌ | hal/native/, scripts/ |
| A-3 | 冻结 NDJSON progress schema（版本/字段/兼容性） | P0-3 | ⚠️ 已实现待冻结 | runtime/, cmd/main/ |
| A-4 | `run --until-fault` 正式化为回归入口（stop reason / fault summary） | P0-4 | ⚠️ 已实现待文档化 | runtime/, cmd/main/ |
| A-5 | Native FFI 生命周期与失败路径测试（ASan / double close / leak） | P0-5 | ❌ | hal/native/ |
| A-6 | Native CLI 实机证据矩阵（平台 × 网卡 × 从站 × 命令 × 结果） | P0-6 | ⚠️ Windows 部分 | docs/, scripts/ |

**收口条件**：
- Windows 与 Linux Native 后端共享同一稳定 HAL 语义
- Linux 实机 `list-if → scan → validate → run` 闭环可复现
- `run --progress-ndjson` 与最终 JSON summary 拥有冻结 schema
- `run --until-fault` 有正式文档定义 stop reason
- Native CLI 各主命令拥有可复核的证据矩阵

### 主线 B：Verification Runtime（P1 优先级）

目标：把 MoonECAT 从"能运行的主站"升级为"可验证、可回放、可注入故障的事件溯源执行器"。

**核心架构升级——事件溯源 (Event Sourcing)**：

> 协议栈被抽象为纯函数状态机 `State' = f(State, Event)`。当前系统状态完全由"初始状态 + 历史事件流"积分计算而来。物理时间被固化为 Event 中的 `timestamp_ns` 字段。只要记录硬件层抛出的 Event 流，就可以在任何平台上逐纳秒完美重演运行轨迹。

#### B 阶段一（✅ 已完成）：最小验证闭环

| 编号 | 任务 | 对应 BACKLOG | 状态 | 涉及目录 |
|---|---|---|---|---|
| B-1 | 设计并实现一等 fault injection 模型（≥3 类可控注入） | P1-1 | ✅ `ba7356e` | runtime/, protocol/, hal/ |
| B-2 | 引入 deterministic replay 最小闭环（事件溯源回放） | P1-2 | ✅ `e4b03a2` | runtime/, fixtures/ |
| B-3 | 引入 monitor / verdict 框架（Pass/Warn/Fail/Block） | P1-3 | ✅ `7af544f` | runtime/, cmd/main/ |
| B-4 | 从 loopback/mock 演进到协议级虚拟从站 | P1-4 | ✅ `5535c69` / `e1fee13` | hal/mock/, protocol/, mailbox/ |
| B-5 | 冻结 topology fingerprint / Hot Connect 最小模型 | P1-5 | ✅ `164014a` | runtime/, mailbox/ |
| B-6 | 扩展 DiagnosticSurface 为统一事实层 | P1-6 | ✅ `07e7333` | runtime/, cmd/main/ |

**B-1 首批 fault 类型**：recv timeout burst、send failure、WKC mismatch、missing slave、AL status mismatch、state transition timeout、mailbox timeout

**B-2 事件溯源核心设计**：
- 状态不可变性：系统状态 = 初始状态 + 折叠(事件流)
- 时间即数据：物理时间固化为 `Event.timestamp_ns`
- 100% 确定性回放：记录 Event 流即可在 PC/浏览器完美重演裸机运行

**B-3 首批 monitor**：consecutive timeout threshold、WKC below threshold、startup state not reached、shutdown rollback failure、unexpected slave count change、repeated mailbox failure

**B 阶段一收口条件**（✅ 全部满足）：
- ✅ 7 类 fault 可控注入（FaultInjector + FaultNic）
- ✅ 事件溯源回放闭环（RecordingNic → ReplayNic）
- ✅ `run` 输出显式 verdict（Pass/Warn/Fail/Block）
- ✅ VirtualSlave 可完成 `scan → state → run`（VirtualBus 多从站仿真）；2026-04-01 再按 SOES 风格补齐 FMMU logical addressing / process-data 路由，覆盖单从站与多从站 LRD/LWR/LRW、Init→Op 生命周期和 PDO 回归（commit: `e1fee13`，验证：`moon test --target wasm-gc hal/mock` = `48/48`、`moon test --target wasm-gc hal hal/mock protocol mailbox fixtures` = `310/310`、`moon test --target wasm-gc .` = `2/2`）
- ✅ topology fingerprint 冻结（TopologyFingerprint + SlavePresence）

#### B 阶段二（规划中）：深度验证与场景扩展

> 阶段一证明了"能录、能放、能判"；阶段二目标是形成**可组合的验证场景库**，使 MoonECAT 成为协议一致性测试的执行引擎。

| 编号 | 任务 | 优先级 | 状态 | 涉及目录 |
|---|---|---|---|---|
| B-7 | 复合 fault 场景编排（Scenario = FaultRule[] + 预期 Verdict 序列） | P1 | ✅ | hal/mock/, runtime/ |
| B-8 | NicEventLog 持久化（NDJSON 导出 / 导入，支持跨会话回放） | P1 | ✅ | hal/mock/, cmd/main/ |
| B-9 | VirtualSlave 邮箱仿真（CoE SDO upload/download + Emergency 注入） | P1 | ✅ | hal/mock/, mailbox/ |
| B-10 | 协议偏差注入（畸形帧、PDU 长度越界、WKC 篡改位置可控） | P1 | ✅ | hal/mock/, protocol/ |
| B-11 | Monitor 可组合注册 + 用户自定义 monitor trait | P1 | ✅ | runtime/ |
| B-12 | CLI `replay` 命令（从 NDJSON trace 文件回放并输出 verdict） | P1 | ✅ | cmd/main/：replay, scenario, jitter-profile, auto-tune 4 条 CLI 命令，commit `6213ee6` |
| B-13 | Wasm-GC fuzzing 最小框架（随机 Event 生成 + crash oracle） | P2 | ✅ | hal/mock/, runtime/ |
| B-14 | 验证报告生成器（HTML/Markdown 格式，含 verdict 时间线 + fault 注入点标注） | P2 | ✅ | runtime/, cmd/main/ |

**B-7 复合场景编排设计**：
```
Scenario {
  name: "dc_drift_under_burst_timeout"
  setup: [FaultRule(RecvTimeout, AfterN(50)), FaultRule(WkcCorrupt(1), AtCycle(100))]
  expected_verdicts: [Warn at cycle 51, Fail at cycle 100]
  pass_condition: runtime stops gracefully within 10 cycles of Fail
}
```

**B-8 事件流持久化格式**：
- 每行一个 NicEvent JSON：`{"type":"sent","ts_ns":123456,"frame_hex":"88a4..."}`
- 文件头包含拓扑指纹 + 录制参数
- ReplayNic 可从文件直接构建，无需中间数据结构
- 兼容 `--progress-ndjson` 的输出管道

**B-9 虚拟邮箱需求**：
- VirtualSlave 当前仅支持 ESM + PDO echo，缺少 CoE/SDO 事务
- 新增：SDO upload/download 模拟（预置对象字典表）
- 新增：Emergency 消息主动注入（可配时序触发）
- 新增：邮箱计数器/重复请求 RMSM 回环测试

**B 阶段二收口条件**：
- 复合场景可声明式定义并自动验证
- NicEventLog 可 NDJSON ↔ 文件双向无损往返
- `moonecat replay trace.ndjson --json` 输出与原录制一致的 verdict
- VirtualSlave 可完成 SDO upload roundtrip
- 至少 1 个用户自定义 monitor 的集成测试

### 主线 C：HIL-Ready Runtime Boundary（P2 优先级）

目标：为未来 MCU + Linux 协同 HIL、异构 SoC、多任务/多时基扩展预留稳定运行时边界。

#### C 阶段一（✅ 已完成）：接口合同与 PoC

| 编号 | 任务 | 对应 BACKLOG | 状态 | 涉及目录 |
|---|---|---|---|---|
| C-1 | 抽象 runtime hook：process image / cycle / event / fault | P2-1 | ✅ `2b9c98f` | runtime/, protocol/ |
| C-2 | 冻结 multiple tasks / process-image partitioning 接口模型 | P2-2 | ✅ `2b9c98f` | runtime/ |
| C-3 | 定义外部 plant/controller co-sim adapter contract | P2-3 | ✅ `2b9c98f` | runtime/, plugin/ |
| C-4 | 实现最小 communication-closed-loop HIL PoC | P2-4 | ✅ `2b9c98f` | runtime/, cmd/main/ |
| C-5 | 定义 MCU + Linux 协同 HIL 的时基合同 | P2-5 | ✅ `2b9c98f` | runtime/, hal/ |
| C-6 | 零拷贝帧池 + ZeroCopyNic HAL 合同 | P2-6 | ✅ `b1e26e8` | hal/ |
| C-7 | 多平台零拷贝 FFI 后端桩设计 | P2-7 | ✅ `e9c7771` | hal/native/ |
| C-8 | ProcessImage 就地映射（消除热路径 Bytes 分配） | P2-8 | ✅ `675bc24` | protocol/ |

**C-1 至 C-5 统一设计原则**：

MoonECAT 在 HIL 系统中的定位是**通信执行器 + 运行时协调器**，而非完整仿真器。

**硬件承载平台演进路线**：
1. **单核/多核 MCU (RZ/N2L, HPM6E00)**：依靠 TCM/ILM 和绑核隔离实现亚百微秒通讯周期
2. **异构 SoC (ARM + FPGA/PRU)**：FPGA 充当绝对精确"事件生成器"，ARM 核心充当"纯粹事件消费者"，通过 AXI 总线交互
3. **物理隔离边界**：无锁事件队列（Lock-Free Ring Buffer）、绝对零拷贝（Zero-Copy DMA 描述符）、极简 ISR

**C 阶段一收口条件**（✅ 全部满足）：
- ✅ Runtime 可挂接外部 hook 而不污染协议核心（CycleHook trait）
- ✅ 有多任务/切片接口模型（TaskSchedule + ProcessImageSlice）
- ✅ 有最小 co-sim adapter contract（CoSimAdapter trait）
- ✅ 有 communication-closed-loop HIL PoC（HilCycleHook + HilSession）
- ✅ 时基/时钟责任文档明确（Timebase trait + TimebaseSync + VirtualTimebase）
- ✅ 零拷贝帧池 + ZeroCopyNic HAL 合同（C-6 `b1e26e8`）
- ✅ 多平台零拷贝 FFI 后端桩设计（C-7 `e9c7771`）
- ✅ ProcessImage 就地映射消除热路径分配（C-8 `675bc24`）

#### C 阶段二（规划中）：HIL 实战集成

> 阶段一完成了全部 trait 合同与 PoC；阶段二目标是把合同落地到至少一个真实 MCU 平台，并验证跨域协同。

| 编号 | 任务 | 优先级 | 状态 | 涉及目录 |
|---|---|---|---|---|
| C-9 | RZ/N2L 或 HPM6E00 裸机 HAL 适配（Nic + Clock + ZeroCopyNic） | P2 | ✅ | hal/native/, hal/mcu/ |
| C-10 | MCU→Linux 事件队列桥接（Lock-Free Ring + shared memory） | P2 | ✅ | hal/, runtime/ |
| C-11 | CoSimAdapter 外部进程桥（Unix socket / shared memory 变体） | P2 | ✅ | runtime/, plugin/ |
| C-12 | 多速率 TaskSchedule 实机验证（cycle_divisor 2/4/8 混合调度） | P2 | ✅ | runtime/ |
| C-13 | TimebaseSync 在线漂移补偿实测（MCU↔Linux 域） | P2 | ✅ | runtime/, hal/ |
| C-14 | HIL session 状态导出（SimTime + step_log → JSON trace） | P2 | ✅ | runtime/, cmd/main/ |

**C 阶段二收口条件**：
- 至少一个 MCU 平台完成 Nic::open_ → send → recv → close 全链路
- 多速率调度在裸机上可稳定运行 ≥10000 周期
- CoSimAdapter 可通过进程间通信驱动外部 Simulink/Modelica 模型
- TimebaseSync 漂移补偿在 MCU↔Linux 上达到 ≤1μs 同步精度


---

## 4. 内置分析与自整定引擎（远期能力）

将 MoonECAT 从协议栈提升为工业级诊断工具。

### 4.1 DC 抖动图 (DC Jitter Profiling)

- **原理**：旁路监听带有硬件时间戳的 Rx/Tx Event 流，实时计算主站发包抖动与从站同步时钟漂移量
- **价值**：告别外部抓包仪器（如 Beckhoff ET2000），几秒钟即可输出纳秒级抖动直方图，判断底层驱动和内存隔离是否合格
- **依赖**：主线 B 事件溯源模型就绪

### 4.2 PDO 同步时间参数在线识别 (Online PDO Auto-Tuning)

- **原理**：启动阶段自动发送探测帧，结合硬件时间戳计算菊花链拓扑延迟与传输延迟，自动推算并写入最优 Sync0/Sync1 偏移量
- **价值**：大幅降低多轴伺服系统 DC 参数调试门槛，由 MoonECAT 在 INIT→PREOP 阶段自动扫描并最优配置
- **依赖**：主线 A DC 基线稳定 + 主线 B 时间数据模型

---

## 5. MoonBit 多后端协同验证策略

利用 MoonBit 的多后端特性实现降维验证：

| 后端 | 用途 | 状态 |
|---|---|---|
| **Wasm-GC (仿真与 Fuzzing)** | 将主站逻辑与虚拟从站编译为 WebAssembly，在 PC 上注入海量畸变 Event 进行极限边缘测试 | ⚠️ 基础编译通过，fuzzing 框架待建 |
| **Native-C (裸机执行)** | 验证通过的代码零修改编译为 C，链接到裸机 HAL 驱动真实硅片 | ⚠️ Windows Npcap 已跑通，嵌入式链接待做 |
| **Extism Plugin (边缘部署)** | 打包为 Extism 插件，通过宿主函数接入网卡/计时，在桌面/服务端对接网页工作台 | ⚠️ 骨架+Mock回放已有，宿主打通待做 |

---

## 6. CLI 统一设计规范

### 6.1 命令分层

MoonECAT CLI 按操作语义分为五个层级：

| 层级 | 命令 | 说明 | 后端要求 | 输出 |
|---|---|---|---|---|
| **发现层** | `list-if` | 列举可用网卡 | All | 文本/JSON |
| | `scan` | 扫描从站拓扑 | All | 文本/JSON |
| **配置层** | `validate` | 比对在线/离线配置 | All | Pass/Warn/Block + JSON |
| | `esi-sii` | ESI XML→SII JSON 投影 | Mock/Native | JSON |
| **诊断层** | `read-sii` | SII EEPROM 深读 | Native | 文本/JSON |
| | `diagnosis` | 统一诊断表面 | Native | DiagnosticIssue[] |
| | `od` | 对象字典浏览 | Native | OD tree JSON |
| | `esc-regs` | ESC 寄存器原始转储 | Native | hex/JSON |
| | `expected-regs` | 预期 vs 实际寄存器对比 | Native | diff JSON |
| **操控层** | `state` | ESM 状态转换 | Native | 文本/JSON |
| | `run` | 完整生命周期运行 | All | RunReport + NDJSON |
| | `startup-trace` | 启动序列追踪 | Native | trace JSON |
| | `startup-diff` | 启动序列差异分析 | Native | diff JSON |
| | `mailbox-readback` | 邮箱弹性层验证 | Native | 文本/JSON |
| **验证层** ⭐新增 | `replay` | 从 trace 文件回放并判定 | All | Verdict + JSON |
| | `scenario` | 执行复合验证场景 | Mock/Virtual | Verdict[] + report |
| **远程层** ⭐新增 | `serve` | 启动远程 HAL 服务器 | Native | 状态日志 |

### 6.2 统一参数规范

**后端选择**：
```
--backend <mock|native-auto|native-windows-npcap|native-linux-raw|remote>
--remote <host:port>          # 等价于 --backend remote + 地址
--if <interface>              # 物理网卡名（native/serve 模式）
```

**输出控制**：
```
--json                        # 结构化 JSON 输出（所有命令）
--progress-ndjson             # 流式 NDJSON 进度事件（run 命令）
--output <path>               # 输出到文件而非 stdout
--quiet                       # 仅输出最终 verdict/结果
```

**从站定位**：
```
--station <address>           # 目标从站配置地址
--position <N>                # 目标从站链路位置（0-based）
--all                         # 操作所有从站
```

**运行控制**：
```
--cycles <N>                  # PDO 周期数（run 命令）
--until-fault                 # 持续运行直到故障
--startup-state <state>       # 启动目标 ESM 状态
--shutdown-state <state>      # 关闭目标 ESM 状态
--timeout <ms>                # 命令超时（毫秒）
--cycle-period <ns>           # 手动覆盖周期时间
```

**验证参数** ⭐新增：
```
--trace <path>                # NicEventLog NDJSON 文件（replay 命令）
--scenario <path>             # 场景定义文件（scenario 命令）
--record <path>               # 录制 NicEvent 到文件（run 命令）
--inject <fault_spec>         # 即时注入规则（run 命令，格式：type:schedule）
```

**远程参数** ⭐新增：
```
--port <N>                    # 监听端口（serve 命令，默认 9100）
--bind <addr>                 # 绑定地址（serve 命令，默认 0.0.0.0）
--tls                         # 启用 TLS（可选）
--reconnect <strategy>        # 重连策略：immediate/backoff/none（remote 模式）
```

### 6.3 命令交互矩阵

```
                    mock  native  remote  virtual-bus
  list-if            ✓      ✓       ✓        ─
  scan               ✓      ✓       ✓        ✓
  validate           ✓      ✓       ✓        ✓
  run                ✓      ✓       ✓        ✓
  read-sii           ─      ✓       ✓        ─
  diagnosis          ─      ✓       ✓        ─
  od                 ─      ✓       ✓        ─
  state              ─      ✓       ✓        ✓
  esc-regs           ─      ✓       ✓        ─
  expected-regs      ─      ✓       ✓        ─
  startup-trace      ─      ✓       ✓        ─
  startup-diff       ─      ✓       ✓        ─
  mailbox-readback   ─      ✓       ✓        ─
  esi-sii            ✓      ✓       ─        ─
  replay             ✓      ─       ─        ✓
  scenario           ✓      ─       ─        ✓
  serve              ─      ✓       ─        ─
```

> `remote` 后端对命令的支持与 `native` 对等——远端服务器转发所有 Nic 操作到物理网卡。
> `virtual-bus` 后端（`--backend virtual`）使用 VirtualBus 仿真，适用于纯软件验证。

### 6.4 JSON 输出合同

所有 `--json` 输出遵循统一信封：

```json
{
  "version": "1.0",
  "command": "<command-name>",
  "backend": "<backend-name>",
  "timestamp": "<ISO-8601>",
  "verdict": "Pass|Warn|Fail|Block",
  "payload": { ... },
  "diagnostics": [ ... ]
}
```

**NDJSON 流事件信封**（`--progress-ndjson`）：
```json
{"event":"progress","ts_ns":123456,"cycles_completed":100,"cycles_ok":99,"telemetry":{...}}
{"event":"fault","ts_ns":234567,"type":"recv_timeout","detail":"..."}
{"event":"verdict","ts_ns":345678,"verdict":"Warn","monitors":[...]}
{"event":"summary","report":{...}}
```

### 6.5 退出码规范

| 退出码 | 含义 | 对应场景 |
|:---:|---|---|
| 0 | 成功 / Verdict=Pass | 正常完成 |
| 1 | 一般错误 | 参数错误、未知命令 |
| 2 | Verdict=Warn | validate/run 发现非致命问题 |
| 3 | Verdict=Fail | validate/run 发现关键故障 |
| 4 | Verdict=Block | 致命条件阻止继续 |
| 10 | 连接失败 | remote 后端网络不可达 |
| 11 | 超时 | 命令执行超时 |
| 12 | 后端不可用 | 请求的后端不支持该命令 |

---

## 7. 里程碑映射

| 里程碑 | 对应主线 | 包含任务 | 目标状态 |
|---|---|---|---|
| **MA — Native Runtime Baseline** | 主线 A | A-1 ~ A-6 | L4 验证加固 |
| **MB1 — Verification Runtime 基础** | 主线 B 阶段一 | B-1 ~ B-6 | ✅ L4 验证加固 |
| **MB2 — Verification Runtime 深度** | 主线 B 阶段二 | B-7 ~ B-14 | ✅ B-7~B-14 全部完成，含 B-12 CLI replay/scenario/jitter-profile/auto-tune |
| **MC1 — HIL-Ready Boundary 合同** | 主线 C 阶段一 | C-1 ~ C-8 | ✅ 全部完成 |
| **MC2 — HIL-Ready Boundary 实战** | 主线 C 阶段二 | C-9 ~ C-14 | ✅ 全部完成 |
| **MD — Remote Capability** | 主线 D | D-1 ~ D-10 | L3 远程闭环 |
| **ME — Analysis Engine** | 远期 | 4.1, 4.2 | ✅ 全部完成 |

---

## 8. 不做什么（反目标）

当前阶段明确不以以下方向为优先目标：

- 与 TwinCAT / CODESYS 做功能项逐条对齐
- 过早扩展大量 feature pack（EoE/FoE/SoE/AoE/VoE）
- 过早把 MoonECAT 做成完整 GUI 平台
- 过早实现完整硬实时电力电子 HIL
- 让平台/后端差异持续泄漏到上层 runtime 语义
- 在 `protocol/` / `mailbox/` / `runtime/` 中引入平台专属分叉
- 在远程层重新发明 EtherCAT 帧转发——远程能力严格位于 HAL 抽象之上

---

## 9. 推荐标签

`native` · `windows` · `linux` · `ffi` · `runtime` · `verification` · `diagnostics` · `replay` · `fault-injection` · `topology` · `hil` · `event-sourcing` · `zero-copy` · `jitter-profiling` · `auto-tuning` · `remote` · `cli` · `scenario` · `fuzzing`
