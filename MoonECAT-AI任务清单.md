# MoonECAT AI 任务清单

本清单基于 [MoonECAT项目申报书.md](MoonECAT项目申报书.md) 与 [ETG.1500 Master Classes](ETG1500_V1i0i2_D_R_MasterClasses/ETG1500_V1i0i2_D_R_MasterClasses.md) 整理，用于把项目目标转成可执行任务和可追踪提交。范围保持不变：产品面为 `Library API + CLI(scan/validate/run)` 双入口，目标对齐 ETG.1500 `Class B`，`EoE/FoE/SoE/AoE/VoE` 继续排除在外。

## 0. ETG.1500 Class B 功能对照表

> 来源：ETG.1500 Table 1 — M=Mandatory, C=Conditional, ✅=已实现, ⚠️=部分, ❌=未实现, ➖=排除

| Feature ID | 功能 | Class B 要求 | 状态 | 对应模块 | 备注 |
|:---:|---|---|:---:|---|---|
| **基础功能 (5.3)** | | | | | |
| 101 | Service Commands (全部 DLPDU 命令) | shall if ENI | ✅ | [protocol/codec.mbt](protocol/codec.mbt) | 15 种 EcCommand 全部映射 |
| 102 | IRQ Field in datagram | should | ✅ | [protocol/pdu.mbt](protocol/pdu.mbt), [runtime/runtime.mbt](runtime/runtime.mbt), [runtime/scheduler.mbt](runtime/scheduler.mbt) | IRQ 已编解码透传并在主循环计数 (`irq_events`) |
| 103 | Slaves with Device Emulation | shall | ✅ | [protocol/esm_extensions.mbt](protocol/esm_extensions.mbt) | read_device_emulation + request_state_aware + OpOnly |
| 104 | EtherCAT State Machine (ESM) | shall | ✅ | [protocol/esm.mbt](protocol/esm.mbt), [protocol/esm_engine.mbt](protocol/esm_engine.mbt) | Init/PreOp/SafeOp/Op/Boot + 回退路径 |
| 105 | Error Handling (WKC 等) | shall | ✅ | [runtime/scheduler.mbt](runtime/scheduler.mbt) | WKC 校验 + 连续错误计数 + 诊断指标 |
| 106 | VLAN | may | ➖ | — | 不实现 |
| 107 | EtherCAT Frame Types (0x88A4) | shall | ✅ | [protocol/frame.mbt](protocol/frame.mbt) | Ethernet II + EtherType 0x88A4 |
| 108 | UDP Frame Types | may | ➖ | — | 不实现 |
| **过程数据交换 (5.4)** | | | | | |
| 201 | Cyclic PDO | shall | ✅ | [protocol/pdo.mbt](protocol/pdo.mbt), [runtime/runtime.mbt](runtime/runtime.mbt) | pdo_exchange LRW 已完整实现 |
| 202 | Multiple Tasks | may | ➖ | — | Free Run 单任务优先 |
| 203 | Frame repetition | may | ➖ | — | 不实现 |
| **网络配置 (5.5)** | | | | | |
| 301 | Online scanning / ENI import (至少一种) | shall (至少一种) | ✅ | [runtime/scan.mbt](runtime/scan.mbt) | Online scanning 已实现 |
| 302 | Compare Network configuration (boot-up) | shall | ✅ | [runtime/validate.mbt](runtime/validate.mbt) | Vendor/Product/Revision/Serial 4-tuple 校验 |
| 303 | Explicit Device Identification | should | ✅ | [runtime/scan.mbt](runtime/scan.mbt), [runtime/validate.mbt](runtime/validate.mbt), [hal/config.mbt](hal/config.mbt) | IdentificationAdo 读取 + 显式标识校验已接入 |
| 304 | Station Alias Addressing | may | ✅ | [protocol/discovery.mbt](protocol/discovery.mbt) | `read_station_alias` + `enable_alias_addressing` (0x0012 + Bit24) |
| 305 | Access to EEPROM (Read shall, Write may) | Read shall | ✅ | [protocol/eeprom.mbt](protocol/eeprom.mbt) | eeprom_read_word/eeprom_read via ESC 0x0502-0x0508 |
| **邮箱支持 (5.6)** | | | | | |
| 401 | Support Mailbox (基础传输) | shall | ✅ | [protocol/mailbox_transport.mbt](protocol/mailbox_transport.mbt) | mailbox_send/recv/poll/exchange 已闭环 |
| 402 | Mailbox Resilient Layer (RMSM) | shall | ✅ | [mailbox/rmsm.mbt](mailbox/rmsm.mbt) | Rmsm 状态机 + 计数器关联 + 重复检测 + 重试 |
| 403 | Multiple Mailbox channels | may | ➖ | — | 不实现 |
| 404 | Mailbox polling | shall | ✅ | [protocol/mailbox_transport.mbt](protocol/mailbox_transport.mbt) | mailbox_poll SM status bit 检查 |
| **CoE (5.7)** | | | | | |
| 501 | SDO Up/Download (normal + expedited) | shall | ✅ | [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt) | sdo_download/upload + retry 事务已闭环 |
| 502 | Segmented Transfer | should | ⚠️ | [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt), [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt) | 已支持分段上传拼接；分段下载待补 |
| 503 | Complete Access | should (shall if ENI) | ⚠️ | [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt), [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt) | 已支持 CA 位编码与 CA Upload/Download 事务入口；CA 分段续传待补 |
| 504 | SDO Info service | should | ⚠️ | [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt) | 已支持 Get OD List 请求构造与 SDO Info 响应头解码；OD读取流程待补 |
| 505 | Emergency Message | shall | ✅ | [mailbox/emergency.mbt](mailbox/emergency.mbt) | decode_emergency/decode_emergency_frame |
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
| 1101 | DC support | shall if DC | ✅ | [protocol/dc.mbt](protocol/dc.mbt), [runtime/runtime.mbt](runtime/runtime.mbt) | 已实现 DC 初始化 + SYNC0 + FRMW 漂移补偿 |
| 1102 | Continuous Propagation Delay compensation | should | ✅ | [protocol/dc.mbt](protocol/dc.mbt), [runtime/runtime.mbt](runtime/runtime.mbt) | 运行态周期重估+平滑写回+计数 telemetry 已完成 |
| 1103 | Sync window monitoring | should | ✅ | [protocol/dc.mbt](protocol/dc.mbt) | dc_read_sync_window |
| **Slave-to-Slave (5.14)** | | | | | |
| — | Slave-to-Slave via Master | — | ➖ | — | 暂不实现 |
| **Master 信息 (5.15)** | | | | | |
| 1301 | Master Object Dictionary | may | ➖ | — | Class B 可选 |

**Class B 强制(shall)功能覆盖率：17/17 = 100%**

---

## 1. 使用规则

- 任务完成后再打勾，不能按预期完成时补充阻塞说明。
- 每次提交只覆盖一个清晰目标，避免把无关改动混进同一个 commit。
- 优先提交可验证结果，例如接口、测试、最小闭环、文档更新。
- 提交顺序必须服从依赖关系，不能先做 CLI 再倒逼核心库改接口。
- 新增能力默认遵循固定链路：先补 `Reference_Project` / 标准映射，再生成 MoonECAT 实现与测试，再执行最小验证、提交，最后回填本清单与 memory。

## 2. 里程碑任务

### M1 基础骨架与包结构 — ✅ 已完成

- [x] 建立稳定的 MoonBit 包结构，明确 HAL、Protocol Core、Mailbox、Runtime、CLI 的目录边界。
  - 📦 hal/, protocol/, mailbox/, runtime/, fixtures/, cmd/main/
- [x] 定义 HAL 最小接口，覆盖收发、计时、调度、文件访问和统一错误码。
  - 📦 Nic/Clock/FileAccess trait + EcError 枚举
- [x] 定义核心错误模型、诊断事件模型和基础配置对象。
  - 📦 EcError(16 变体) + DiagnosticEvent + MasterConfig/NicConfig
- [x] 建立 `Library API` 与 `CLI` 的入口占位，保证共享核心实现。
  - 📦 [cmd/main/main.mbt](cmd/main/main.mbt) (stub)
- [x] 建立最小测试骨架和样例夹具结构。
  - 📦 [fixtures/fixtures.mbt](fixtures/fixtures.mbt) + 各包 *_test.mbt (~163 tests)

提交映射（选项 → commit）：
- `包结构边界 + Library/CLI 入口占位` → `feat: scaffold moonecat package layout`
- `HAL 最小接口 + 错误/诊断/配置模型` → `feat: define platform hal contracts`
- `最小测试骨架与夹具` → `test: add minimal project test harness`

### M2 HAL 与帧/PDU 最小闭环 — ✅ 已完成

- [x] 实现 Ethernet II 与 EtherCAT 基本帧结构的编码、解码和校验。
  - 📦 EcFrame::encode/decode, EtherType 0x88A4 [ETG.1500 #107]
- [x] 实现 PDU 编码、解码、地址模型和缓冲区管理。
  - 📦 EcCommand(15种), PDU header, FrameBuilder [ETG.1500 #101]
- [x] 落地首个可运行后端，优先 `Mock Loopback`。
  - 📦 [hal/mock/loopback.mbt](hal/mock/loopback.mbt): MockNic + MockClock
- [x] 建立发送、接收、超时和错误返回的统一流程。
  - 📦 [protocol/transact.mbt](protocol/transact.mbt): transact/transact_pdu/transact_pdu_retry
- [x] 为热路径加入预分配或少分配约束。
  - 📦 FrameBuilder 缓冲区管理
- [x] 补齐帧/PDU 和收发闭环测试。
  - 📦 [protocol/protocol_test.mbt](protocol/protocol_test.mbt) (~15 tests)

提交映射（选项 → commit）：
- `EtherCAT 帧编解码` → `1aeb2f3` `feat: add ethercat frame codec`
- `PDU 编解码与管线原语` → `3cb23a2` `feat: add pdu pipeline primitives`
- `Mock Loopback 后端` → `43045fe` `feat: add mock loopback hal`
- `帧/PDU 收发闭环测试` → `fcfa689` `test: cover frame and pdu roundtrip`

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
  - 📦 [runtime/scan.mbt](runtime/scan.mbt) + [runtime/validate.mbt](runtime/validate.mbt)
- [x] 补齐无真实网卡场景下的夹具测试。
  - 📦 [fixtures/fixtures.mbt](fixtures/fixtures.mbt) + [mailbox/mailbox_test.mbt](mailbox/mailbox_test.mbt) + [runtime/runtime_test.mbt](runtime/runtime_test.mbt)

提交映射（选项 → commit）：
- `基础发现流程与拓扑对象` → `9739150` `feat: add slave discovery model`
- `SII/ESI 最小解析` → `4dde9ff` `feat: parse sii and esi metadata`
- `FMMU/SM 自动配置计算` → `f64ccba` `feat: calculate fmmu and sync manager mapping`
- `发现与配置夹具测试` → `5b72cd9` `test: add discovery and config fixture coverage`
- `网络一致性 4-tuple 校验` → `773692c` `fix(validate): compare full identity 4-tuple`
- `SII/ESI 规范修正` → `b95a431` `fix(mailbox): ESI/SII conformance fixes per ETG1000.6`

### M4 ESM、PDO 周期通信、运行时编排 — ✅ 已完成

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
  - 📦 [runtime/runtime_test.mbt](runtime/runtime_test.mbt) (~13 tests)
- [x] **【缺口】pdo_exchange 实体循环**：完成 LRW/LRD/LWR 实际收发，使 run_cycle 能驱动真实 PDO 交换 [ETG.1500 #201]
  - ✅ 代码审查确认 pdo_exchange 已完整实现 (LRW + logical addressing)
- [x] **【缺口】Device Emulation 感知**：ESM 引擎根据 SII DeviceEmulation 标志跳过 Error Indication Acknowledge [ETG.1500 #103]
  - ✅ [protocol/esm_extensions.mbt](protocol/esm_extensions.mbt) : read_device_emulation + request_state_aware
- [x] **【缺口】ESM 超时值**：从 SII/ESI 或 ETG.1020 默认值获取 ESM 转换超时 [ETG.1500 §5.3.4]
  - ✅ [protocol/esm_engine.mbt](protocol/esm_engine.mbt): `EsmTimeoutPolicy` + `esm_default_timeout` + `esm_timeout_for` + `transition_through_with_timeout_policy`
  - ✅ 参考实现映射：SOEM `ecx_statecheck(..., EC_TIMEOUTSTATE)`（全局状态超时）、ethercrab `Timeouts::state_transition`（统一状态迁移超时）、gatorcat `init/preop/safeop/op` 分态超时参数
- [x] **【缺口】OpOnly 标志处理**：ESI OpOnly Flag 为真时，非 Op 状态禁用输出 SM [ETG.1500 §5.3.4]
  - ✅ [protocol/esm_extensions.mbt](protocol/esm_extensions.mbt) : apply_op_only_policy + set_sm_enable
  - ✅ [mailbox/sii_flags.mbt](mailbox/sii_flags.mbt) : SiiGeneral::is_op_only/prefers_not_lrw/supports_identification_ado

提交映射（选项 → commit）：
- `ESM 状态流转与回退` → `3652ca4` `feat: add esm transition engine`
- `PDO 周期交换主循环` → `88e4a3a` `feat: add pdo runtime loop`
- `运行时调度与 telemetry` → `e5886a4` `feat: add runtime scheduler and telemetry`
- `Free Run 与恢复路径测试` → `0ec6ce2` `test: cover free-run and recovery paths`
- `Device Emulation + OpOnly 扩展` → `ff166d4` `feat: implement P0 gaps — mailbox transport, RMSM, SDO transaction, EEPROM read, ESM extensions`
- `ESM 超时策略（默认值 + 可覆盖策略）` → `394a457` `feat(protocol): add ESM timeout policy and defaults`

### M5 CoE/SDO、邮箱引擎 — ✅ 核心事务已闭环，含分段/CA/Info

- [x] 实现 MailboxHeader 编解码。
  - 📦 MailboxHeader::to_bytes/from_bytes + MailboxType 枚举
- [x] 实现 CoE/SDO 请求编码框架。
  - 📦 CoeService/SdoCommand/SdoRequest 类型 + coe_engine 常量
- [x] **【缺口】SDO Upload/Download 事务闭环**：编码 SDO 请求 → 通过邮箱发送 → 等待响应 → 解码结果 [ETG.1500 #501 shall]
  - ✅ [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt) : sdo_download/upload + retry
- [x] **【缺口】Mailbox Resilient Layer (RMSM)**：丢帧恢复状态机 + Counter/Repeat 管理 [ETG.1500 #402 shall]
  - ✅ [mailbox/rmsm.mbt](mailbox/rmsm.mbt): Rmsm struct + begin/validate/timeout/reset
- [x] **【缺口】Mailbox polling**：周期性检查 Input-Mailbox 或 Status-Bit [ETG.1500 #404 shall]
  - ✅ [protocol/mailbox_transport.mbt](protocol/mailbox_transport.mbt): mailbox_poll SM status bit
- [x] **【缺口】Emergency Message 接收**：解码 CoE Emergency 帧并分发到应用 [ETG.1500 #505 shall]
  - ✅ [mailbox/emergency.mbt](mailbox/emergency.mbt): decode_emergency/decode_emergency_frame
- [x] SDO 分段传输 (Segmented Transfer) [ETG.1500 #502 should]
  - ✅ [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt): 分段上传循环拼接（toggle / last segment）
  - ✅ [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt): 分段上传起始/分段响应解码
  - ✅ [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt): 分段下载请求构帧 + 分段下载响应解码
  - ✅ [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt): 分段下载请求/响应循环（含 toggle 校验）
- [x] SDO Complete Access [ETG.1500 #503 should, shall if ENI]
  - ✅ [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt): `build_sdo_download_ca` / `build_sdo_upload_ca` + CA bit 编码
  - ✅ [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt): `sdo_download_complete_access` / `sdo_upload_complete_access`
  - ✅ [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt): CA 上传/下载分段续传循环
- [x] SDO Info Service [ETG.1500 #504 should]
  - ✅ [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt): `build_sdo_info_get_od_list_request` + `decode_sdo_info_response`
  - ✅ [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt): `sdo_info_get_od_list`（分片拼接 + list type 头处理）
  - ✅ [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt): `decode_sdo_info_od_list_payload`
  - ✅ [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt): `build_sdo_info_get_od_request` / `build_sdo_info_get_oe_request`
  - ✅ [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt): `sdo_info_get_od_description` / `sdo_info_get_oe_description`

提交映射（选项 → commit）：
- `SDO Upload/Download 事务闭环` → `f161c3c` `feat: add coe sdo transaction engine`
- `Mailbox Resilient Layer (RMSM)` + `Mailbox polling` + `Emergency Message` → `ff166d4` `feat: implement P0 gaps — mailbox transport, RMSM, SDO transaction, EEPROM read, ESM extensions`
- `Segmented Transfer（上传）` → `ce75e4e` `feat: add segmented SDO upload path`
- `Complete Access + SDO Info 基础` → `250e770` `feat: add complete-access and sdo-info foundations`
- `Segmented Transfer（下载）+ CA 分段续传` → `f9fc97c` `feat: complete segmented sdo and CA continuation`
- `SDO Info OD/OE + 运行态 DC 补偿联动实现`（含 SDO Info 完整收口） → `766037d` `feat: complete sdo info and runtime dc compensation`
- `格式与接口同步` → `594e30c` `chore: sync formatted sources and mbti after info`

### M6 网络配置增强 — ✅ 已完成

- [x] **EEPROM/SII 寄存器级读取流程**：通过 ESC 寄存器 0x0502-0x0508 读取 EEPROM 内容 [ETG.1500 #305]
  - ✅ [protocol/eeprom.mbt](protocol/eeprom.mbt): eeprom_read_word/eeprom_read
- [x] **Explicit Device Identification**：读取 IdentificationAdo 进行 Hot Connect 防误插 [ETG.1500 #303 should]
  - ✅ [runtime/scan.mbt](runtime/scan.mbt): `scan_with_identification_ado(...)` + `SlaveReport.identification`
  - ✅ [hal/config.mbt](hal/config.mbt): `SlaveConfig.expected_identification`
  - ✅ [runtime/validate.mbt](runtime/validate.mbt): `IdentificationMismatch` + 显式标识校验
- [x] **Station Alias Addressing**：读取 Register 0x0012 + 激活 DL Control Bit 24 [ETG.1500 #304 may]
  - ✅ [protocol/discovery.mbt](protocol/discovery.mbt): `read_station_alias` + `enable_alias_addressing`
- [x] Error Register / Diagnosis Object 接口：向应用暴露错误和诊断信息 [ETG.1500 §5.3.5]
  - ✅ [runtime/diagnosis.mbt](runtime/diagnosis.mbt): `read_error_register`/`read_diagnosis_counter`/`read_slave_diagnosis`

提交映射（选项 → commit）：
- `EEPROM/SII 寄存器级读取流程` → `ff166d4` `feat: implement P0 gaps — mailbox transport, RMSM, SDO transaction, EEPROM read, ESM extensions`
- `Explicit Device Identification (#303)` → `8c6070f` `feat: add explicit device identification validation`
- `Station Alias Addressing` → `690427d` `feat: implement IRQ consumption and alias addressing path`
- `Error Register / Diagnosis Object 接口` → `f4696dc` `feat: wire cli commands and add diagnosis interface`

### M7 DC 同步 — ✅ 基础能力与运行态补偿已完成

- [x] DC 初始化流程：传播延迟测量 + Offset 补偿 + Start Time 写入 [ETG.1500 #1101]
  - ✅ [protocol/dc.mbt](protocol/dc.mbt): `dc_configure_linear`、`dc_configure_sync0`
  - ✅  [runtime/runtime.mbt](runtime/runtime.mbt): `Runtime::init_dc`
- [x] DC 持续漂移补偿：ARMW 周期帧 [ETG.1500 #1101]
  - ✅ [protocol/dc.mbt](protocol/dc.mbt): `dc_compensate_cycle` (FRMW)
  - ✅ [runtime/runtime.mbt](runtime/runtime.mbt): `run_cycle` 周期补偿
- [x] Continuous Propagation Delay compensation [ETG.1500 #1102 should]
  - ✅ [protocol/dc.mbt](protocol/dc.mbt): `reg_dc_system_delay` 改为基于参考站接收时间差估计
  - ✅ [protocol/dc.mbt](protocol/dc.mbt): `dc_reestimate_propagation_delays` 运行态重估 + 平滑更新
  - ✅ [runtime/runtime.mbt](runtime/runtime.mbt): 每 100 周期触发一次连续重估并计数
- [x] Sync window monitoring：读取 Register 0x092C [ETG.1500 #1103 should]
  - ✅ [protocol/dc.mbt](protocol/dc.mbt): `dc_read_sync_window`

提交映射（选项 → commit）：
- `DC 初始化流程 + SYNC0 + 漂移补偿主路径` → `533285d` `feat: implement distributed clock runtime and protocol support`
- `传播延迟估计模型改进` → `d52498b` `feat: improve dc propagation delay estimation`
- `运行态连续传播延迟补偿（周期重估）` → `766037d` `feat: complete sdo info and runtime dc compensation`

### M8 CLI、文档、最终集成与多后端交付 — ⚠️ Native / Extism 后端待落地

- [x] 实现 `moonecat scan` 命令（库层接口）。
  - 📦 [runtime/scan.mbt](runtime/scan.mbt): scan() → ScanReport
- [x] 实现 `moonecat validate` 命令（库层接口）。
  - 📦 [runtime/validate.mbt](runtime/validate.mbt): validate() → ValidateReport
- [x] 实现 `moonecat run` 命令（库层接口框架）。
  - 📦 [runtime/runtime.mbt](runtime/runtime.mbt): Runtime + run_cycle
- [x] 补全文档：架构、接口、测试方式。
  - 📦 [README.mbt.md](README.mbt.md) 已更新
- [x] **【缺口】CLI 实际接入**：[cmd/main/main.mbt](cmd/main/main.mbt) 已接入 Mock HAL + scan/validate/run 流程
  - ✅ 当前已支持 `--backend <mock|native|native-windows-npcap|native-linux-raw>` 与 `--if <interface>` 参数，默认仍为 mock
- [x] **【缺口】结构化诊断输出**：scan/validate/run 提供 JSON/human-readable 双格式输出
- [x] 评估并整理 Extism 宿主接入边界。
  - ✅ [docs/EXTISM_HOST_BOUNDARY.md](docs/EXTISM_HOST_BOUNDARY.md): 宿主能力、HAL 适配边界、错误映射与验证清单
  - ✅ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): Extism / WASM Host Integration 总览入口
- [ ] **【新增】Native 后端首版**：以 Linux Raw Socket 为优先落地点，Windows Npcap 保持同一 HAL 契约与诊断语义。
  - 规划文档： [docs/NATIVE_BACKEND_PLAN.md](docs/NATIVE_BACKEND_PLAN.md)
  - 当前状态：已创建 [hal/native/moon.pkg](hal/native/moon.pkg) Native 包，包含 `native-stub`、native / wasm-gc 双 target 文件、Windows Npcap 与 Linux Raw Socket FFI 包装、统一 `NativeNic`、结构化 `list-if` 输出与最小测试；`moon run cmd/main list-if -- --backend native-windows-npcap --json` 已在本机 Npcap 1.8.4 下跑通（commit: `061928d`），`scan/validate/run` 的真实网卡 smoke 仍待补全
  - 目标范围：真实网卡收发、时钟/休眠、可选抓包与文件输出；不把平台专属逻辑带入 `protocol/`、`mailbox/`、`runtime/`
  - 建议目录：`hal/native/` 或按平台拆分 `hal/linux/`、`hal/windows/`
  - MoonBit Native FFI 工作包：
    - `moon.mod.json` 评估是否切换 `preferred-target: native`，若暂不切换则至少为 FFI 文件做 `targets` 限定，避免影响 wasm 构建链路
    - 在后端包的 `moon.pkg` 中声明 `native-stub`，将 `ffi.mbt` 与平台相关 `.c` stub 绑定在同一包内
    - 原始 `extern "c" fn` 保持私有，仅对外暴露安全 MoonBit 包装层，不允许把裸 FFI 签名扩散到 `runtime/`
    - 对非 primitive 参数显式标注 `#borrow` / `#owned`；不确定生命周期时默认禁止 `#borrow`
    - NIC 句柄、pcap handle、socket fd 按生命周期选择 `type Handle` + finalizer 或 `#external type`，并在清单中记录原因
    - 字符串、接口名、设备路径统一按 UTF-8 `Bytes` 穿越 FFI；宿主返回文本时再在 MoonBit 侧解码
  - 平台拆解建议：
    - Linux：`AF_PACKET` / Raw Socket 收发、非阻塞轮询、超时换算、接口索引解析
    - Windows：Npcap handle 打开、收发、超时与错误码映射；仅在 HAL 层处理 Win32/Npcap 差异
    - Common：统一 `Nic/Clock/FileAccess` 适配器、错误映射、抓包导出接口
  - 验收标准：
    - `scan/validate/run` 三条库层路径能经由真实 NIC 跑通最小闭环
    - Native 后端 `Nic/Clock/FileAccess` 实现与 Mock 共享同一组核心语义测试
    - `RecvTimeout`、`LinkDown`、`UnexpectedWkc`、`EsmTransitionFailed` 的错误分类与现有 telemetry 语义保持一致
    - Free Run 模式先稳定，DC 仅复用现有运行态能力，不额外引入平台特化调度语义
    - Native 目标下 `moon check`、`moon test` 可独立执行，且 FFI 文件不会污染非 native 目标
    - 至少有一条 AddressSanitizer/等价内存安全检查路径用于发现句柄泄漏、悬垂引用或错误 ownership 注解
  - 非目标：本阶段不引入多任务调度、冗余链路、平台专属 Runtime 分叉
  - 依赖：HAL 契约稳定、热路径分配约束继续收紧、CLI 输出模型保持不变、MoonBit Native FFI 包配置收口
- [ ] **【新增】Extism / WASM 后端首版**：以宿主能力映射 + 共享内存缓冲区为核心，导出插件入口而不复制协议实现。
  - 规划文档： [docs/EXTISM_WASM_BACKEND_PLAN.md](docs/EXTISM_WASM_BACKEND_PLAN.md)
  - 当前状态：已创建 [plugin/extism/moon.pkg](plugin/extism/moon.pkg) 包骨架，包含 envelope 类型、占位导出入口、错误码映射与最小 JSON 测试；尚未接入实际 host capability adapter
  - 目标范围：基于 moonbit-pdk / Extism 的插件封装，复用现有 `scan/validate/run` 库接口
  - 宿主前提：宿主负责 NIC open/send/recv/close、clock now/sleep、可选 file read/write；插件只持有句柄和序列化请求/响应
  - 数据边界：控制面优先 JSON/Bytes 信封；周期数据优先共享内存缓冲区，避免每周期大块拷贝
  - 插件封装工作包：
    - 导出 `scan`、`validate`、`run` 三个稳定入口，禁止复制第二套调度逻辑
    - 定义请求/响应 envelope：版本号、命令类型、payload、错误码、诊断摘要
    - 定义共享内存缓冲区协定：所有权、可见性、长度字段、超时语义、宿主回收责任
    - Host capability contract 中的 `nic_*`、`clock_*`、`file_*` 保持最小集，不把插件宿主变成新的协议层
    - 明确插件内状态保持策略：短生命周期命令式调用优先，长周期 run 由宿主显式启动/停止
  - 兼容性约束：
    - WASM/Extism 路线不得要求修改现有 `scan/validate/run` 返回模型，只允许增加序列化层
    - 错误码、telemetry 字段名、状态迁移顺序需与 Native CLI/Library 保持同一规范
    - 插件入口要允许无文件系统宿主运行，因此 ESI/SII 等输入必须支持 bytes 直传
  - 验收标准：
    - 提供稳定的插件导出入口，对齐 `scan`、`validate`、`run`
    - Host capability contract 与 [docs/EXTISM_HOST_BOUNDARY.md](docs/EXTISM_HOST_BOUNDARY.md) 保持一致，超时单位统一为 ns
    - ESM / PDO / mailbox 行为与 native 语义一致，不新增插件特化状态机
    - 至少有一条最小集成回放覆盖 `scan -> validate -> run -> stop`
    - 错误输出保持稳定字符串码 + 明细消息，能映射到现有 `EcError` 分类
  - 非目标：插件内部直连 Raw Socket、在 `protocol/` 或 `runtime/` 中直接依赖 Extism API、单独维护第二套 CLI 逻辑
  - 依赖：`docs/EXTISM_HOST_BOUNDARY.md`、共享内存信封格式、稳定的库层 API
- [ ] **【新增】多后端发布物矩阵**：把 CLI Native、Library Native、Extism Plugin 三类产物的边界、配置与回归入口写清楚。
  - ✅ [docs/BACKEND_RELEASE_MATRIX.md](docs/BACKEND_RELEASE_MATRIX.md)：已补齐 Native CLI / Native Library / Extism Plugin 的输入、输出、依赖环境与最小验证命令（commit: `8aa93aa`）
  - ✅ 当前 Native CLI smoke 已在 Windows Npcap 1.8.4 上实测跑通：`list-if -> scan -> validate -> run`，其中空总线场景返回 `0 slaves / PASS / Done`
  - 验收标准：
    - 明确每类产物的输入、输出、依赖环境与最小验证命令
    - 文档区分“后端差异”与“协议语义”，避免把平台问题写进协议清单
    - 后续 commit 可以按“HAL 适配 / 入口封装 / 集成验证 / 文档发布”独立回填

建议提交拆分（未完成）：
- `native ffi package scaffold`：FFI 包布局、`moon.pkg` `native-stub`、target gating、基础 stub 框架
- `linux raw-socket nic binding`：Linux Raw Socket extern + 安全包装 + 错误映射
- `windows npcap nic binding`：Npcap extern + 安全包装 + 错误映射
- `native interface enumeration + runtime loading`：Windows Npcap 动态加载、Linux Raw Socket 枚举、CLI `list-if` JSON 输出
- `native backend cli smoke path`：CLI 复用 native HAL 跑通 scan/validate/run
- `native real smoke stability fix`：空总线 `run` 跳过无效 ESM 广播，CLI `run` 采用 probe/run 双实例 NIC 路径
- `backend release matrix docs`：Native CLI / Native Library / Extism Plugin 交付边界、环境要求与 smoke 命令
- `native ffi memory safety validation`：ownership 标注、句柄清理与 AddressSanitizer 检查
- `extism wasm adapter entrypoints`：插件导出入口 + 请求/响应信封
- `extism host shared-memory transport`：共享内存缓冲区与 host capability 对接
- `extism replay validation`：WASM/宿主最小回放验证与错误码对齐
- `backend release matrix docs`：交付物矩阵、运行方式与回归入口整理

提交映射（选项 → commit）：
- `moonecat scan` 库层接口 → `04b1e6d` `feat: add moonecat scan command`
- `moonecat validate` 库层接口 → `452a661` `feat: add moonecat validate command`
- `moonecat run` 库层接口框架 → `9c9bc85` `feat: add moonecat run command`
- `补全文档（架构/接口/测试方式）` → `e5d8a81` `docs: document architecture and user workflows`
- `CLI 实际接入` + `结构化诊断输出` → `f4696dc` `feat: wire cli commands and add diagnosis interface`
- `Windows Npcap Native 后端骨架` → `92c9a5e` `feat(native): add windows npcap backend scaffold`
- `Native interface enumeration + runtime loading` → `061928d` `feat(native): load npcap at runtime and enable list-if`
- `Native CLI smoke regression + release matrix docs` → `8aa93aa` `test(cli): add native smoke regression and release matrix docs`
- `Native real smoke stability fix` → `8ac4ce6` `fix(native): stabilize real smoke run path`
- `CLI 后端选择（mock/native）` → `c004811` `feat(cli): add selectable mock and native backends`
- `Extism / WASM 插件骨架` → `57e6521` `feat(extism): scaffold plugin envelopes and entrypoints`
- `接口与格式同步` → `594e30c` `chore: sync formatted sources and mbti after info`
- `Extism 宿主接入边界整理` → `db9bb9e` `docs: refresh remaining items and define Extism host boundary`

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
| ✅ | 1101 | ~~DC 基础支持~~ | DC 初始化 + Offset + SYNC0 + FRMW 已完成 | P0 PDO ✅ |
| ✅ | 303 | ~~Explicit Device ID~~ | IdentificationAdo 读取与校验已接入 | M6 ✅ |

---

## 8. Reference_Project实现核对矩阵（调用流 + 本地源码）

> 调用流依据：[src/SOEM-callflow-analysis.md](src/SOEM-callflow-analysis.md)、[src/CherryECAT-callflow-analysis.md](src/CherryECAT-callflow-analysis.md)、[src/ethercrab-callflow-analysis.md](src/ethercrab-callflow-analysis.md)、[src/EtherCAT.net-callflow-analysis.md](src/EtherCAT.net-callflow-analysis.md)、[src/gatorcat-callflow-analysis.md](src/gatorcat-callflow-analysis.md)、[src/igh-callflow-analysis.md](src/igh-callflow-analysis.md)  
> 本地实现依据：SOEM、CherryECAT、ethercrab、EtherCAT.NET、gatorcat、IGH 各参考实现源码（见下表具体文件与行号链接）

| 功能 | 调用流文档依据 | 参考实现（本地代码） | MoonECAT 对应实现 | 结论 |
|---|---|---|---|---|
| Native NIC backend / `list-if` / 真实链路入口 | [gatorcat-callflow-analysis.md:44](src/gatorcat-callflow-analysis.md#L44) [ethercrab-callflow-analysis.md:74](src/ethercrab-callflow-analysis.md#L74) [igh-callflow-analysis.md:90](src/igh-callflow-analysis.md#L90) | Npcap SDK: [UserBridge.c:44](Reference_Project/npcap-sdk-1.16/Examples-remote/UserLevelBridge/UserBridge.c#L44) (`LoadNpcapDlls`) + [UserBridge.c:110](Reference_Project/npcap-sdk-1.16/Examples-remote/UserLevelBridge/UserBridge.c#L110) (`pcap_findalldevs_ex`) + [UserBridge.c:193](Reference_Project/npcap-sdk-1.16/Examples-remote/UserLevelBridge/UserBridge.c#L193) (`pcap_open`)；IGH: [generic.c:219](Reference_Project/ethercat/devices/generic.c#L219) (`sock_create_kern`) + [generic.c:234](Reference_Project/ethercat/devices/generic.c#L234) (`sockaddr_ll`)；GatorCAT: [nic.zig:182](Reference_Project/gatorcat/src/module/nic.zig#L182) (`npcap.pcap_open`) | [hal/native/platform_stub.c](hal/native/platform_stub.c) [hal/native/windows_npcap_ffi.mbt](hal/native/windows_npcap_ffi.mbt) [hal/native/linux_raw_socket_ffi.mbt](hal/native/linux_raw_socket_ffi.mbt) [hal/native/native_nic.mbt](hal/native/native_nic.mbt) [cmd/main/main.mbt](cmd/main/main.mbt) | 已完成真实空总线 smoke：Windows Npcap 1.8.4 / Realtek USB GbE 接口上已验证 `list-if -> scan -> validate -> run`；稳定化修复已提交于 `8ac4ce6` |
| 扫描/拓扑/基础发现 | [SOEM-callflow-analysis.md:157](src/SOEM-callflow-analysis.md#L157) [CherryECAT-callflow-analysis.md:178](src/CherryECAT-callflow-analysis.md#L178) [ethercrab-callflow-analysis.md:191](src/ethercrab-callflow-analysis.md#L191) | SOEM: [ec_config.c:172](Reference_Project/SOEM/src/ec_config.c#L172) (`ecx_config_init`) Cherry: [ec_slave.c:955](Reference_Project/CherryECAT/src/ec_slave.c#L955) (`ec_slaves_scanning`) ethercrab: [maindevice.rs:263](Reference_Project/ethercrab/src/maindevice.rs#L263) (`SubDevice::new`) | [runtime/scan.mbt](runtime/scan.mbt) [protocol/discovery.mbt](protocol/discovery.mbt) | 已对齐 |
| ESM 状态机与回退 | [SOEM-callflow-analysis.md:465](src/SOEM-callflow-analysis.md#L465) [IGH-callflow-analysis.md:486](src/igh-callflow-analysis.md#L486) | SOEM: [ec_main.c:1017](Reference_Project/SOEM/src/ec_main.c#L1017) (`ecx_writestate`) + [ec_main.c:1052](Reference_Project/SOEM/src/ec_main.c#L1052) (`ecx_statecheck`)；IGH: [fsm_slave_config.c:223](Reference_Project/ethercat/master/fsm_slave_config.c#L223) (`ec_fsm_slave_config_state_start`) | [protocol/esm.mbt](protocol/esm.mbt) [protocol/esm_engine.mbt](protocol/esm_engine.mbt) [protocol/esm_extensions.mbt](protocol/esm_extensions.mbt) | 已对齐 |
| PDO 周期交换 | [CherryECAT-callflow-analysis.md:321](src/CherryECAT-callflow-analysis.md#L321) [gatorcat-callflow-analysis.md:172](src/gatorcat-callflow-analysis.md#L172) [ethercrab-callflow-analysis.md:286](src/ethercrab-callflow-analysis.md#L286) | Cherry: [ec_master.c:769](Reference_Project/CherryECAT/src/ec_master.c#L769) (`ec_master_period_process`)；gatorcat: [MainDevice.zig:430](Reference_Project/gatorcat/src/module/MainDevice.zig#L430) (`sendRecvCyclicFrames`)；ethercrab: [mod.rs:865](Reference_Project/ethercrab/src/subdevice_group/mod.rs#L865) (`tx_rx`) | [protocol/pdo.mbt](protocol/pdo.mbt) (`pdo_exchange`) [runtime/runtime.mbt](runtime/runtime.mbt) | 已对齐 |
| Mailbox 传输与轮询 | [SOEM-callflow-analysis.md:378](src/SOEM-callflow-analysis.md#L378) [CherryECAT-callflow-analysis.md:63](src/CherryECAT-callflow-analysis.md#L63) | SOEM: [ec_main.c:1521](Reference_Project/SOEM/src/ec_main.c#L1521) (`ecx_mbxsend`) + [ec_main.c:1592](Reference_Project/SOEM/src/ec_main.c#L1592) (`ecx_mbxreceive`) + [ec_main.c:1506](Reference_Project/SOEM/src/ec_main.c#L1506) (`ecx_mbxhandler`)；Cherry: [ec_mailbox.c:31](Reference_Project/CherryECAT/src/ec_mailbox.c#L31) (`ec_mailbox_send`) + [ec_mailbox.c:84](Reference_Project/CherryECAT/src/ec_mailbox.c#L84) (`ec_mailbox_receive`) | [protocol/mailbox_transport.mbt](protocol/mailbox_transport.mbt) | 已对齐 |
| CoE SDO 事务 | [CherryECAT-callflow-analysis.md:416](src/CherryECAT-callflow-analysis.md#L416) [ethercrab-callflow-analysis.md:389](src/ethercrab-callflow-analysis.md#L389) [EtherCAT.net-callflow-analysis.md:143](src/EtherCAT.net-callflow-analysis.md#L143) | SOEM: [ec_coe.c:856](Reference_Project/SOEM/src/ec_coe.c#L856) (`ecx_readPDOmap`)；ethercrab: [mod.rs:180](Reference_Project/ethercrab/src/mailbox/coe/mod.rs#L180) (`mailbox_write_read`) + [mod.rs:561](Reference_Project/ethercrab/src/mailbox/coe/mod.rs#L561) (`sdo_read`) + [mod.rs:371](Reference_Project/ethercrab/src/mailbox/coe/mod.rs#L371) (`sdo_write`)；EtherCAT.NET: [EcUtilities.cs:728](Reference_Project/EtherCAT.NET/src/EtherCAT.NET/EcUtilities.cs#L728) (`SdoWrite`) + [EcUtilities.cs:773](Reference_Project/EtherCAT.NET/src/EtherCAT.NET/EcUtilities.cs#L773) (`TryReadSdoValue`) | [protocol/sdo_transaction.mbt](protocol/sdo_transaction.mbt) [mailbox/coe_engine.mbt](mailbox/coe_engine.mbt) | 已对齐 |
| Emergency 消息 | [SOEM-callflow-analysis.md:378](src/SOEM-callflow-analysis.md#L378) [IGH-callflow-analysis.md:741](src/igh-callflow-analysis.md#L741) | IGH: [coe_emerg_ring.c:105](Reference_Project/ethercat/master/coe_emerg_ring.c#L105) (`ec_coe_emerg_ring_push`)；SOEM: [ec_main.c:194](Reference_Project/SOEM/src/ec_main.c#L194) (`ecx_mbxemergencyerror`) | [mailbox/emergency.mbt](mailbox/emergency.mbt) | 已对齐（环形缓冲增强待做） |
| EEPROM/SII 读取 | [SOEM-callflow-analysis.md:157](src/SOEM-callflow-analysis.md#L157) [ethercrab-callflow-analysis.md:440](src/ethercrab-callflow-analysis.md#L440) | SOEM: [ec_main.c:1880](Reference_Project/SOEM/src/ec_main.c#L1880) (`ecx_readeeprom`) + [ec_main.c:2157](Reference_Project/SOEM/src/ec_main.c#L2157) (`ecx_readeepromFP`)；Cherry: [ec_sii.c:118](Reference_Project/CherryECAT/src/ec_sii.c#L118) (`ec_sii_read`)；ethercrab: [eeprom.rs:47](Reference_Project/ethercrab/src/subdevice/eeprom.rs#L47) (`read_chunk`) | [protocol/eeprom.mbt](protocol/eeprom.mbt) [mailbox/sii_parser.mbt](mailbox/sii_parser.mbt) | 已对齐 |
| DC 初始化与运行补偿 | [SOEM-callflow-analysis.md:443](src/SOEM-callflow-analysis.md#L443) [CherryECAT-callflow-analysis.md:225](src/CherryECAT-callflow-analysis.md#L225) [ethercrab-callflow-analysis.md:333](src/ethercrab-callflow-analysis.md#L333) [EtherCAT.net-callflow-analysis.md:125](src/EtherCAT.net-callflow-analysis.md#L125) | SOEM: [ec_dc.c:250](Reference_Project/SOEM/src/ec_dc.c#L250) (`ecx_configdc`) + [ec_dc.c:33](Reference_Project/SOEM/src/ec_dc.c#L33) (`ecx_dcsync0`)；Cherry: [ec_master.c:752](Reference_Project/CherryECAT/src/ec_master.c#L752) (`ec_master_dc_sync_with_pi`)；ethercrab: [dc.rs:424](Reference_Project/ethercrab/src/dc.rs#L424) (`configure_dc`) + [dc.rs:469](Reference_Project/ethercrab/src/dc.rs#L469) (`run_dc_static_sync`)；EtherCAT.NET: [EcMaster.cs:277](Reference_Project/EtherCAT.NET/src/EtherCAT.NET/EcMaster.cs#L277) (`ConfigureDc`) + [EcMaster.cs:457](Reference_Project/EtherCAT.NET/src/EtherCAT.NET/EcMaster.cs#L457) (`CompensateDcDrift`) | [protocol/dc.mbt](protocol/dc.mbt) [runtime/runtime.mbt](runtime/runtime.mbt) [runtime/run.mbt](runtime/run.mbt) | 已对齐 |
| Alias Addressing | [gatorcat-callflow-analysis.md:90](src/gatorcat-callflow-analysis.md#L90) | gatorcat: [MainDevice.zig:259](Reference_Project/gatorcat/src/module/MainDevice.zig#L259) + [esc.zig:20](Reference_Project/gatorcat/src/module/esc.zig#L20) (`dl_control_enable_alias_address`) | [protocol/discovery.mbt](protocol/discovery.mbt) (`read_station_alias` / `enable_alias_addressing`) | 已对齐 |
| Explicit Device ID | [gatorcat-callflow-analysis.md:60](src/gatorcat-callflow-analysis.md#L60) [ethercrab-callflow-analysis.md:191](src/ethercrab-callflow-analysis.md#L191) | gatorcat: [Scanner.zig:230](Reference_Project/gatorcat/src/module/Scanner.zig#L230) (`identity.vendor_id/product_code/revision_number/serial_number`)；ethercrab: [maindevice.rs:263](Reference_Project/ethercrab/src/maindevice.rs#L263) (`SubDevice::new`) + [mod.rs:160](Reference_Project/ethercrab/src/subdevice/mod.rs#L160) (`eeprom.identity`) + [mod.rs:184](Reference_Project/ethercrab/src/subdevice/mod.rs#L184) (`alias_address`) | [runtime/scan.mbt](runtime/scan.mbt) + [runtime/validate.mbt](runtime/validate.mbt) + [hal/config.mbt](hal/config.mbt) | 已对齐 |

---

## 4. 并行工作流

### HAL

- [x] 固化跨平台最小接口和错误模型。
- [x] 先完成 `Mock Loopback`，再补单一真实平台原型。
- [ ] 落地 Native 后端：Linux Raw Socket 优先，Windows Npcap 与同一 HAL 契约对齐。
- [ ] 落地 Extism / WASM Host Adapter：通过宿主函数与共享内存映射 `Nic/Clock/FileAccess`。
- [ ] 为 RTOS/Embedded 保留与 Native / Extism 不冲突的 HAL 扩展位。

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
- [ ] 先在 Native 后端完成 Free Run 真实链路闭环，再逐步增强 DC 集成验证。
- [ ] 为 Extism / WASM 路径补一套不改变语义的回放式运行编排验证。

### CLI/Library

- [x] 固化共享核心实现，不做双实现。
- [x] 完成 `scan/validate/run` 库层接口。
- [x] 接入 CLI 实际命令。
- [x] 统一命令输出和库层结果对象。

### 文档与测试

- [x] 维护开发文档和回归夹具。
- [x] 建立单元测试和夹具测试 (~163 tests)。
- [x] 建立流程回放和最小集成测试。
  - ✅ [runtime/runtime_test.mbt](runtime/runtime_test.mbt): `replay integration minimal flow: scan->validate->run->stop`
  - ✅ commit: `420a99a` `test(runtime): add minimal replay integration flow`
- [x] 持续把参考分析文档转成实现约束和验收标准。
  - ✅ [docs/REFERENCE_CONSTRAINTS.md](docs/REFERENCE_CONSTRAINTS.md): 建立“参考调用流 -> 实现约束 -> 测试验收”映射矩阵
  - ✅ commit: `44dfea1` `docs: map reference callflows to constraints and tests`

## 5. 依赖顺序

- [x] 先完成 M1，再进入 M2。
- [x] 先完成帧/PDU 闭环，再进入扫描和配置计算。
- [x] 先形成拓扑和配置对象，再进入 PDO 和 Runtime。
- [x] 先形成 Runtime 主循环，再完成 `run` 命令和 SDO 整合。
- [x] CLI 只能复用核心库，不能先实现命令再反推库接口。
- [x] DC 相关能力不能阻塞 Free Run 最小可用版本。
- [ ] 先完成 Native FFI 包脚手架，再分别落 Linux Raw Socket / Windows Npcap 绑定。
- [ ] 先冻结 Native HAL 错误语义与句柄生命周期，再开放 CLI 在真实后端上的 smoke 验证。
- [ ] 先冻结 Extism 请求/响应信封和 host capability contract，再落共享内存优化。
- [ ] Extism / WASM 只能包装既有库入口，不能先写插件逻辑再反推 `runtime/` 改接口。

## 6. 风险检查清单

### GC 抖动

- [x] 检查热路径是否存在不必要分配。
  - ✅ [runtime/runtime_test.mbt](runtime/runtime_test.mbt) `Pressure: free-run core loop remains stable at high cycle count`（1000 周期稳定计数）
- [x] 对核心循环建立压力回归。
  - ✅ [runtime/runtime_test.mbt](runtime/runtime_test.mbt) `Pressure: timeout-heavy loop keeps accounting consistent`
- [x] 跟踪不同负载下的周期稳定性和错误率。
  - ✅ [runtime/runtime_test.mbt](runtime/runtime_test.mbt) `Pressure: telemetry remains monotonic across different loads`
  - ✅ commit: `7c91dcf` `test(runtime): add pressure regression coverage for core loop`

### 平台接口碎片化

- [x] 检查新增平台后端是否污染 Protocol Core。（当前仅 Mock，接口隔离良好）
- [x] 保证同一组核心测试可复用于不同 HAL。
- [ ] Native 后端接入前先验证 HAL 接口是否足够稳定。
- [ ] Extism / WASM 适配前先冻结 host capability contract 与请求/响应信封格式。
- [ ] Native 与 Extism 两条路径共用同一组 scan/validate/run 语义验收，不允许演化出双语义。

### FFI / 宿主边界

- [ ] 检查 Native FFI 中所有非 primitive 参数是否已标注 `#borrow` / `#owned`，避免默认语义漂移。
- [ ] 检查所有外部句柄是使用 finalizer external object 还是 `#external type`，并为每类句柄记录释放责任。
- [ ] 检查 `.c` stub、`native-stub`、`targets` 配置是否只作用于 Native 路径，不破坏 wasm-gc 构建。
- [ ] 检查 Extism 宿主是否只暴露 HAL 等价能力，不把对象字典、ESM、PDO 语义上推到宿主。
- [ ] 检查共享内存协议是否明确长度、所有权、超时与回收责任，避免 run 路径出现隐式复制与悬垂缓冲区。

### 状态机死锁

- [x] 覆盖 Init、PreOp、SafeOp、Op 以及错误回退路径。
- [x] 覆盖超时、重试、链路异常和配置不一致场景。
  - ✅ 超时/链路异常: [runtime/runtime_test.mbt](runtime/runtime_test.mbt) `Recovery: run_cycles records RecvTimeout and continues` + `Runtime run_cycle propagates LinkDown on broken NIC`
  - ✅ 配置不一致: [runtime/runtime_test.mbt](runtime/runtime_test.mbt) `run with mock loopback: validation fails when slaves expected but not found`
  - ✅ 重试边界: [mailbox/mailbox_test.mbt](mailbox/mailbox_test.mbt) `Rmsm record_timeout allows retries up to max`
  - ✅ commit: `bc33a9f` `test(runtime): cover timeout and link-down recovery paths`
- [x] 检查 mailbox 推进和 PDO 热路径是否仍然解耦。
  - ✅ [runtime/runtime_test.mbt](runtime/runtime_test.mbt) `Decoupling: mailbox diagnosis failure does not block PDO run loop`
  - ✅ commit: `5f1e012` `test(runtime): verify mailbox and PDO path decoupling`

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

## 9. 下一阶段优先级建议（剩余项）

剩余高优先任务（按依赖顺序）：

1. **Native 后端首版**：先以 Linux Raw Socket 打通真实网卡的 `scan/validate/run` 最小闭环，并冻结其 HAL 契约与错误语义。
2. **Native CLI smoke 验证**：把现有 CLI 在真实后端上跑通，确认输出格式、诊断字段和 Mock 路径一致。
3. **Extism / WASM 适配入口**：补插件导出层与 host capability 映射，保持核心协议层零感知。
4. **Extism 共享内存数据路径**：补控制面信封与周期数据缓冲区约定，避免热路径序列化放大。
5. **后端发布物矩阵文档**：明确 Native CLI、Native Library、Extism Plugin 的交付边界、依赖和回归入口。

## 10. 提交执行方式

- 每完成一个"建议提交拆分"条目，就单独 `git add` 对应文件并提交。
- 新增能力先补 Section 8 的“参考实现（本地代码）/ MoonECAT 对应实现”，再落测试与实现；缺少映射时不直接编码。
- 提交前先运行本次改动对应的最小验证；文档改动至少检查链接、标题和任务编号是否一致。
- 完成后更新本文档对应条目的 `[ ]` → `[x]` 并注明 commit hash。
