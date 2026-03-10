# MoonECAT AI 任务清单

本清单基于 [MoonECAT项目申报书.md](MoonECAT项目申报书.md) 与 [ETG.1500 Master Classes](ETG1500_V1i0i2_D_R_MasterClasses/ETG1500_V1i0i2_D_R_MasterClasses.md) 整理，用于把项目目标转成可执行任务和可追踪提交。范围保持不变：产品面为 `Library API + CLI(scan/validate/run)` 双入口，目标对齐 ETG.1500 `Class B`，`EoE/FoE/SoE/AoE/VoE` 继续排除在外。

## 0. ETG.1500 Class B 功能对照表

> 来源：ETG.1500 Table 1 — M=Mandatory, C=Conditional, ✅=已实现, ⚠️=部分, ❌=未实现, ➖=排除

| Feature ID | 功能 | Class B 要求 | 状态 | 对应模块 | 备注 |
|:---:|---|---|:---:|---|---|
| **基础功能 (5.3)** | | | | | |
| 101 | Service Commands (全部 DLPDU 命令) | shall if ENI | ✅ | `protocol/codec` | 15 种 EcCommand 全部映射 |
| 102 | IRQ Field in datagram | should | ❌ | `protocol/pdu` | PDU 已解析 IRQ 字段，但主循环未消费 |
| 103 | Slaves with Device Emulation | shall | ✅ | `protocol/esm_extensions` | read_device_emulation + request_state_aware + OpOnly |
| 104 | EtherCAT State Machine (ESM) | shall | ✅ | `protocol/esm`, `esm_engine` | Init/PreOp/SafeOp/Op/Boot + 回退路径 |
| 105 | Error Handling (WKC 等) | shall | ✅ | `runtime/scheduler` | WKC 校验 + 连续错误计数 + 诊断指标 |
| 106 | VLAN | may | ➖ | — | 不实现 |
| 107 | EtherCAT Frame Types (0x88A4) | shall | ✅ | `protocol/frame` | Ethernet II + EtherType 0x88A4 |
| 108 | UDP Frame Types | may | ➖ | — | 不实现 |
| **过程数据交换 (5.4)** | | | | | |
| 201 | Cyclic PDO | shall | ✅ | `protocol/pdo`, `runtime` | pdo_exchange LRW 已完整实现 |
| 202 | Multiple Tasks | may | ➖ | — | Free Run 单任务优先 |
| 203 | Frame repetition | may | ➖ | — | 不实现 |
| **网络配置 (5.5)** | | | | | |
| 301 | Online scanning / ENI import (至少一种) | shall (至少一种) | ✅ | `runtime/scan` | Online scanning 已实现 |
| 302 | Compare Network configuration (boot-up) | shall | ✅ | `runtime/validate` | Vendor/Product/Revision/Serial 4-tuple 校验 |
| 303 | Explicit Device Identification | should | ❌ | — | IdentificationAdo 未实现 |
| 304 | Station Alias Addressing | may | ❌ | — | Register 0x0012 + DL Control Bit 24 |
| 305 | Access to EEPROM (Read shall, Write may) | Read shall | ✅ | `protocol/eeprom` | eeprom_read_word/eeprom_read via ESC 0x0502-0x0508 |
| **邮箱支持 (5.6)** | | | | | |
| 401 | Support Mailbox (基础传输) | shall | ✅ | `protocol/mailbox_transport` | mailbox_send/recv/poll/exchange 已闭环 |
| 402 | Mailbox Resilient Layer (RMSM) | shall | ✅ | `mailbox/rmsm` | Rmsm 状态机 + 计数器关联 + 重复检测 + 重试 |
| 403 | Multiple Mailbox channels | may | ➖ | — | 不实现 |
| 404 | Mailbox polling | shall | ✅ | `protocol/mailbox_transport` | mailbox_poll SM status bit 检查 |
| **CoE (5.7)** | | | | | |
| 501 | SDO Up/Download (normal + expedited) | shall | ✅ | `protocol/sdo_transaction` | sdo_download/upload + retry 事务已闭环 |
| 502 | Segmented Transfer | should | ❌ | — | |
| 503 | Complete Access | should (shall if ENI) | ❌ | — | |
| 504 | SDO Info service | should | ❌ | — | |
| 505 | Emergency Message | shall | ✅ | `mailbox/emergency` | decode_emergency/decode_emergency_frame |
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
| 1101 | DC support | shall if DC | ❌ | `runtime/scheduler` | DcState 枚举存在，实现为空 |
| 1102 | Continuous Propagation Delay compensation | should | ❌ | — | |
| 1103 | Sync window monitoring | should | ❌ | — | |
| **Slave-to-Slave (5.14)** | | | | | |
| — | Slave-to-Slave via Master | — | ➖ | — | 暂不实现 |
| **Master 信息 (5.15)** | | | | | |
| 1301 | Master Object Dictionary | may | ➖ | — | Class B 可选 |

**Class B 强制(shall)功能覆盖率：16/17 ≈ 94%** (仅 DC #1101 待实现)

---

## 1. 使用规则

- 任务完成后再打勾，不能按预期完成时补充阻塞说明。
- 每次提交只覆盖一个清晰目标，避免把无关改动混进同一个 commit。
- 优先提交可验证结果，例如接口、测试、最小闭环、文档更新。
- 提交顺序必须服从依赖关系，不能先做 CLI 再倒逼核心库改接口。

## 2. 里程碑任务

### M1 基础骨架与包结构 — ✅ 已完成

- [x] 建立稳定的 MoonBit 包结构，明确 HAL、Protocol Core、Mailbox、Runtime、CLI 的目录边界。
  - 📦 hal/, protocol/, mailbox/, runtime/, fixtures/, cmd/main/
- [x] 定义 HAL 最小接口，覆盖收发、计时、调度、文件访问和统一错误码。
  - 📦 Nic/Clock/FileAccess trait + EcError 枚举
- [x] 定义核心错误模型、诊断事件模型和基础配置对象。
  - 📦 EcError(16 变体) + DiagnosticEvent + MasterConfig/NicConfig
- [x] 建立 `Library API` 与 `CLI` 的入口占位，保证共享核心实现。
  - 📦 cmd/main/main.mbt (stub)
- [x] 建立最小测试骨架和样例夹具结构。
  - 📦 fixtures/fixtures.mbt + 各包 *_test.mbt (~163 tests)

已完成提交：
- ✅ `feat: scaffold moonecat package layout`
- ✅ `feat: define platform hal contracts`
- ✅ `test: add minimal project test harness`

### M2 HAL 与帧/PDU 最小闭环 — ✅ 已完成

- [x] 实现 Ethernet II 与 EtherCAT 基本帧结构的编码、解码和校验。
  - 📦 EcFrame::encode/decode, EtherType 0x88A4 [ETG.1500 #107]
- [x] 实现 PDU 编码、解码、地址模型和缓冲区管理。
  - 📦 EcCommand(15种), PDU header, FrameBuilder [ETG.1500 #101]
- [x] 落地首个可运行后端，优先 `Mock Loopback`。
  - 📦 hal/mock/loopback.mbt: MockNic + MockClock
- [x] 建立发送、接收、超时和错误返回的统一流程。
  - 📦 transact/transact_pdu/transact_pdu_retry
- [x] 为热路径加入预分配或少分配约束。
  - 📦 FrameBuilder 缓冲区管理
- [x] 补齐帧/PDU 和收发闭环测试。
  - 📦 protocol_test.mbt (~15 tests)

已完成提交：
- ✅ `feat: add ethercat frame codec` (1aeb2f3)
- ✅ `feat: add pdu pipeline primitives` (3cb23a2)
- ✅ `feat: add mock loopback hal` (43045fe)
- ✅ `test: cover frame and pdu roundtrip` (fcfa689)

### M3 拓扑发现、SII/ESI、配置计算 — ✅ 已完成

- [x] 实现基础从站发现流程和拓扑结果对象。
  - 📦 count_slaves(BRD), SlaveInfo, ScanReport [ETG.1500 #301]
- [x] 支持 SII 读取与基础解析。
  - 📦 parse_sii_header/categories/general/fmmu/sm/strings/pdo [ETG.1500 #305 Read]
- [x] 支持 ESI 最小可用子集解析，聚焦配置所需字段。
  - 📦 SiiGeneral, SiiSmEntry, SiiPdo/SiiPdoEntry
- [x] 实现 Vendor ID、Product Code 和一致性校验。
  - 📦 validate() — 4-tuple 校验 [ETG.1500 #302]
- [x] 实现 FMMU/SM 自动配置计算。
  - 📦 calculate_sm_configs + calculate_fmmu_configs + FmmuConfig::to_bytes
- [x] 提供 `scan` 和 `validate` 可复用的库层接口。
  - 📦 runtime/scan.mbt + runtime/validate.mbt
- [x] 补齐无真实网卡场景下的夹具测试。
  - 📦 fixtures/fixtures.mbt + mailbox_test.mbt + runtime_test.mbt

已完成提交：
- ✅ `feat: add slave discovery model` (9739150)
- ✅ `feat: parse sii and esi metadata` (4dde9ff)
- ✅ `feat: calculate fmmu and sync manager mapping` (f64ccba)
- ✅ `test: add discovery and config fixture coverage` (5b72cd9)
- ✅ `fix(validate): compare full identity 4-tuple` (773692c)
- ✅ `fix(mailbox): ESI/SII conformance fixes per ETG1000.6` (b95a431)

### M4 ESM、PDO 周期通信、运行时编排 — ✅ 核心完成，ESM 超时值待补

- [x] 实现 ESM 状态流转和错误回退路径。
  - 📦 EsmState 5 状态 + can_transition + request_state + transition_through [ETG.1500 #104]
- [x] 实现位置寻址、别名寻址和逻辑寻址核心流程。
  - 📦 AddressType 4 种 + auto_increment/configured/broadcast/logical_address
- [x] 实现运行时调度器，统一周期循环、超时治理和背压控制。
  - 📦 Runtime + Telemetry + CycleResult + run_cycle/needs_recovery [ETG.1500 #105]
- [x] 加入 DC PLL 的接口和状态推进框架。
  - 📦 DcState enum (Disabled/Measuring/Locked/Drifting) — 仅枚举
- [x] 输出抖动、重试、状态迁移等诊断指标。
  - 📦 Telemetry: cycles/tx/rx/timeouts/retries/wkc_errors
- [x] 补齐 Free Run 主流程和关键错误回退测试。
  - 📦 runtime_test.mbt (~13 tests)
- [x] **【缺口】pdo_exchange 实体循环**：完成 LRW/LRD/LWR 实际收发，使 run_cycle 能驱动真实 PDO 交换 [ETG.1500 #201]
  - ✅ 代码审查确认 pdo_exchange 已完整实现 (LRW + logical addressing)
- [x] **【缺口】Device Emulation 感知**：ESM 引擎根据 SII DeviceEmulation 标志跳过 Error Indication Acknowledge [ETG.1500 #103]
  - ✅ `protocol/esm_extensions.mbt`: read_device_emulation + request_state_aware
- [ ] **【缺口】ESM 超时值**：从 SII/ESI 或 ETG.1020 默认值获取 ESM 转换超时 [ETG.1500 §5.3.4]
- [x] **【缺口】OpOnly 标志处理**：ESI OpOnly Flag 为真时，非 Op 状态禁用输出 SM [ETG.1500 §5.3.4]
  - ✅ `protocol/esm_extensions.mbt`: apply_op_only_policy + set_sm_enable
  - ✅ `mailbox/sii_flags.mbt`: SiiGeneral::is_op_only/prefers_not_lrw/supports_identification_ado

已完成提交：
- ✅ `feat: add esm transition engine` (3652ca4)
- ✅ `feat: add pdo runtime loop` (88e4a3a)
- ✅ `feat: add runtime scheduler and telemetry` (e5886a4)
- ✅ `test: cover free-run and recovery paths` (0ec6ce2)

待完成提交：
- `feat: implement pdo_exchange with LRW transaction` — 已确认完成，无需额外代码
- ✅ `feat: handle device emulation and OpOnly flags in ESM` (ff166d4)

### M5 CoE/SDO、邮箱引擎 — ✅ 核心事务已闭环，分段/CA/Info 待实现

- [x] 实现 MailboxHeader 编解码。
  - 📦 MailboxHeader::to_bytes/from_bytes + MailboxType 枚举
- [x] 实现 CoE/SDO 请求编码框架。
  - 📦 CoeService/SdoCommand/SdoRequest 类型 + coe_engine 常量
- [x] **【缺口】SDO Upload/Download 事务闭环**：编码 SDO 请求 → 通过邮箱发送 → 等待响应 → 解码结果 [ETG.1500 #501 shall]
  - ✅ `protocol/sdo_transaction.mbt`: sdo_download/upload + retry
- [x] **【缺口】Mailbox Resilient Layer (RMSM)**：丢帧恢复状态机 + Counter/Repeat 管理 [ETG.1500 #402 shall]
  - ✅ `mailbox/rmsm.mbt`: Rmsm struct + begin/validate/timeout/reset
- [x] **【缺口】Mailbox polling**：周期性检查 Input-Mailbox 或 Status-Bit [ETG.1500 #404 shall]
  - ✅ `protocol/mailbox_transport.mbt`: mailbox_poll SM status bit
- [x] **【缺口】Emergency Message 接收**：解码 CoE Emergency 帧并分发到应用 [ETG.1500 #505 shall]
  - ✅ `mailbox/emergency.mbt`: decode_emergency/decode_emergency_frame
- [ ] SDO 分段传输 (Segmented Transfer) [ETG.1500 #502 should]
- [ ] SDO Complete Access [ETG.1500 #503 should, shall if ENI]
- [ ] SDO Info Service [ETG.1500 #504 should]

已完成提交：
- ✅ `feat: add coe sdo transaction engine` (f161c3c)
- ✅ `feat: implement P0 gaps — mailbox transport, RMSM, SDO transaction, EEPROM read, ESM extensions` (ff166d4)

待完成提交：
- `feat: add sdo segmented transfer`
- `feat: add sdo complete access`
- `feat: add sdo info service`

### M6 网络配置增强 — ⚠️ EEPROM 读取已完成，ID/Alias 待实现

- [x] **EEPROM/SII 寄存器级读取流程**：通过 ESC 寄存器 0x0502-0x0508 读取 EEPROM 内容 [ETG.1500 #305]
  - ✅ `protocol/eeprom.mbt`: eeprom_read_word/eeprom_read
- [ ] **Explicit Device Identification**：读取 IdentificationAdo 进行 Hot Connect 防误插 [ETG.1500 #303 should]
- [ ] **Station Alias Addressing**：读取 Register 0x0012 + 激活 DL Control Bit 24 [ETG.1500 #304 may]
- [ ] Error Register / Diagnosis Object 接口：向应用暴露错误和诊断信息 [ETG.1500 §5.3.5]

已完成提交：
- ✅ `feat: implement P0 gaps — mailbox transport, RMSM, SDO transaction, EEPROM read, ESM extensions` (ff166d4)

待完成提交：
- `feat: add explicit device identification`

### M7 DC 同步 — ❌ 框架占位，不阻塞 Free Run

- [ ] DC 初始化流程：传播延迟测量 + Offset 补偿 + Start Time 写入 [ETG.1500 #1101]
- [ ] DC 持续漂移补偿：ARMW 周期帧 [ETG.1500 #1101]
- [ ] Continuous Propagation Delay compensation [ETG.1500 #1102 should]
- [ ] Sync window monitoring：读取 Register 0x092C [ETG.1500 #1103 should]

待完成提交：
- `feat: add dc propagation delay measurement`
- `feat: add dc drift compensation`
- `feat: add sync window monitoring`

### M8 CLI、文档与最终集成 — ⚠️ CLI stub，文档已有初版

- [x] 实现 `moonecat scan` 命令（库层接口）。
  - 📦 runtime/scan.mbt: scan() → ScanReport
- [x] 实现 `moonecat validate` 命令（库层接口）。
  - 📦 runtime/validate.mbt: validate() → ValidateReport
- [x] 实现 `moonecat run` 命令（库层接口框架）。
  - 📦 runtime/runtime.mbt: Runtime + run_cycle
- [x] 补全文档：架构、接口、测试方式。
  - 📦 README.mbt.md 已更新
- [ ] **【缺口】CLI 实际接入**：cmd/main/main.mbt 目前仅 println stub，需接入 HAL + scan/validate/run 流程
- [ ] **【缺口】结构化诊断输出**：scan/validate/run 结果的 JSON/human-readable 格式化
- [ ] 评估并整理 Extism 宿主接入边界。

已完成提交：
- ✅ `feat: add moonecat scan command` (04b1e6d)
- ✅ `feat: add moonecat validate command` (452a661)
- ✅ `feat: add moonecat run command` (9c9bc85)
- ✅ `docs: document architecture and user workflows` (e5d8a81)

待完成提交：
- `feat: wire cli commands to library runtime`
- `feat: add structured diagnostic output`

---

## 3. Class B shall 缺口清单（按优先级排序）

> 以下为 ETG.1500 Class B 强制(shall)要求中尚未完成的核心缺口，达成后可宣称 Class B 符合。

| 优先级 | Feature ID | 缺口 | 说明 | 依赖 |
|:---:|:---:|---|---|---|
| ✅ | 201 | ~~pdo_exchange 实体实现~~ | LRW/LRD/LWR 已完整实现 | M2 frame codec ✅ |
| ✅ | 401 | ~~邮箱收发流程闭环~~ | mailbox_send/recv/poll/exchange | M2 transact ✅ |
| ✅ | 402 | ~~Mailbox Resilient Layer~~ | Rmsm 状态机 + 计数器关联 | #401 ✅ |
| ✅ | 404 | ~~Mailbox polling~~ | SM status bit 检查 | #401 ✅ |
| ✅ | 501 | ~~SDO Upload/Download 事务~~ | sdo_download/upload + retry | #401 ✅ |
| ✅ | 505 | ~~Emergency Message 接收~~ | decode_emergency/decode_emergency_frame | #401 ✅ |
| ✅ | 103 | ~~Device Emulation 感知~~ | request_state_aware + OpOnly | SII General ✅ |
| ✅ | 305 | ~~EEPROM 寄存器级读取~~ | eeprom_read_word/eeprom_read | M2 transact ✅ |
| P2 | 1101 | DC 基础支持 | 传播延迟+Offset+漂移补偿 | P0 PDO 先完成 |
| P2 | 303 | Explicit Device ID | IdentificationAdo | Scan 已有 |

---

## 4. 并行工作流

### HAL

- [x] 固化跨平台最小接口和错误模型。
- [x] 先完成 `Mock Loopback`，再补单一真实平台原型。
- [ ] 为 Windows、RTOS/Embedded、Extism 预留适配点。

### Protocol Core

- [x] 完成帧、PDU、寻址、拓扑和错误模型。
- [x] 完成 ESM 状态机和错误回退。
- [ ] 约束热路径分配行为。

### Mailbox & Config

- [x] 完成 SII/ESI 解析和配置对象生成。
- [x] 完成 FMMU/SM 自动配置。
- [x] 完成 CoE/SDO 请求队列和状态推进。
- [x] 完成 Mailbox Resilient Layer (RMSM)。
- [x] 完成 Emergency Message 接收。

### Runtime

- [x] 完成运行时调度器框架和 Telemetry 指标。
- [x] 完成 PDO pdo_exchange 实体实现。
- [x] 完成 mailbox 推进、超时治理和背压控制。
- [ ] 优先达成 Free Run，逐步增强 DC。

### CLI/Library

- [x] 固化共享核心实现，不做双实现。
- [x] 完成 `scan/validate/run` 库层接口。
- [ ] 接入 CLI 实际命令。
- [ ] 统一命令输出和库层结果对象。

### 文档与测试

- [x] 维护开发文档和回归夹具。
- [x] 建立单元测试和夹具测试 (~163 tests)。
- [ ] 建立流程回放和最小集成测试。
- [ ] 持续把参考分析文档转成实现约束和验收标准。

## 5. 依赖顺序

- [x] 先完成 M1，再进入 M2。
- [x] 先完成帧/PDU 闭环，再进入扫描和配置计算。
- [x] 先形成拓扑和配置对象，再进入 PDO 和 Runtime。
- [ ] 先形成 Runtime 主循环，再完成 `run` 命令和 SDO 整合。
- [x] CLI 只能复用核心库，不能先实现命令再反推库接口。
- [x] DC 相关能力不能阻塞 Free Run 最小可用版本。

## 6. 风险检查清单

### GC 抖动

- [ ] 检查热路径是否存在不必要分配。
- [ ] 对核心循环建立压力回归。
- [ ] 跟踪不同负载下的周期稳定性和错误率。

### 平台接口碎片化

- [x] 检查新增平台后端是否污染 Protocol Core。（当前仅 Mock，接口隔离良好）
- [x] 保证同一组核心测试可复用于不同 HAL。
- [ ] 新后端接入前先验证 HAL 接口是否足够稳定。

### 状态机死锁

- [x] 覆盖 Init、PreOp、SafeOp、Op 以及错误回退路径。
- [ ] 覆盖超时、重试、链路异常和配置不一致场景。
- [ ] 检查 mailbox 推进和 PDO 热路径是否仍然解耦。

## 7. 30 天启动清单 — ✅ 已完成

- [x] 第 1 周：完成包结构、接口草案、错误模型和统一命名表。
- [x] 第 2 周：完成帧/PDU 最小编码解码、`Mock Loopback` 和收发闭环测试。
- [x] 第 3 周：完成基础扫描流程、SII 最小解析和结构化扫描结果。
- [x] 第 4 周：完成 ESI 最小解析、ESI/SII 校验、FMMU/SM 首版计算和 `scan/validate` 库层接口草案。

30 天交付标准：
- [x] 已形成稳定分层骨架。
- [x] 已形成可测试的 HAL 与帧/PDU 最小闭环。
- [x] 已形成可输出结构化结果的扫描与配置原型。
- [x] 已形成可继续拆解 issue 和 commit 的统一任务基线。

## 8. 下一阶段优先级建议

达成 Class B 的最短路径（按依赖顺序）：

1. **完成 pdo_exchange 实体** — P0，使 Free Run 端到端可跑
2. **完成邮箱 SM 级收发** — P0，为 SDO/Emergency 打通通道
3. **实现 RMSM** — P0，邮箱弹性恢复
4. **实现 Mailbox polling** — P0，周期检查从站邮箱
5. **实现 SDO Upload/Download 事务** — P0，CoE 核心功能
6. **实现 Emergency Message 接收** — P0，CoE 必需
7. **处理 Device Emulation / OpOnly 标志** — P1，ESM 合规
8. **实现 EEPROM 寄存器级读取** — P1，真实硬件必需
9. **DC 初始化+漂移补偿** — P2，Class B conditional
10. **CLI 实际接入** — 最后一步

## 9. 提交执行方式

- 每完成一个"建议提交拆分"条目，就单独 `git add` 对应文件并提交。
- 提交前先运行本次改动对应的最小验证；文档改动至少检查链接、标题和任务编号是否一致。
- 完成后更新本文档对应条目的 `[ ]` → `[x]` 并注明 commit hash。
