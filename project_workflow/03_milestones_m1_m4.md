# MoonECAT 里程碑 M1-M4

本文件由原 AI 任务清单拆分整理而来，对应原第 1 节与第 2 节中 M1 到 M4。

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
  - 📦 [cmd/main/main.mbt](../cmd/main/main.mbt) (stub)
- [x] 建立最小测试骨架和样例夹具结构。
  - 📦 [fixtures/fixtures.mbt](../fixtures/fixtures.mbt) + 各包 *_test.mbt (~163 tests)

提交映射（选项 → commit）：
- `包结构边界 + Library/CLI 入口占位` → `daf1957` `feat: scaffold moonecat package layout`
- `HAL 最小接口 + 错误/诊断/配置模型` → `fb12340` `feat: define platform hal contracts`
- `最小测试骨架与夹具` → `4921fdf` `test: add minimal project test harness`

### M2 HAL 与帧/PDU 最小闭环 — ✅ 已完成

- [x] 实现 Ethernet II 与 EtherCAT 基本帧结构的编码、解码和校验。
  - 📦 EcFrame::encode/decode, EtherType 0x88A4 [ETG.1500 #107]
- [x] 实现 PDU 编码、解码、地址模型和缓冲区管理。
  - 📦 EcCommand(15种), PDU header, FrameBuilder [ETG.1500 #101]
- [x] 落地首个可运行后端，优先 `Mock Loopback`。
  - 📦 [hal/mock/loopback.mbt](../hal/mock/loopback.mbt): MockNic + MockClock
- [x] 建立发送、接收、超时和错误返回的统一流程。
  - 📦 [protocol/transact.mbt](../protocol/transact.mbt): transact/transact_pdu/transact_pdu_retry
- [x] 为热路径加入预分配或少分配约束。
  - 📦 FrameBuilder 缓冲区管理
- [x] 补齐帧/PDU 和收发闭环测试。
  - 📦 [protocol/protocol_test.mbt](../protocol/protocol_test.mbt) (~15 tests)

提交映射（选项 → commit）：
- `EtherCAT 帧编解码` → `7d4a727` `feat: add ethercat frame codec`
- `PDU 编解码与管线原语` → `6ca34be` `feat: add pdu pipeline primitives`
- `Mock Loopback 后端` → `641fc49` `feat: add mock loopback hal`
- `帧/PDU 收发闭环测试` → `5ab7859` `test: cover frame and pdu roundtrip`

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
  - 📦 [runtime/scan.mbt](../runtime/scan.mbt) + [runtime/validate.mbt](../runtime/validate.mbt)
- [x] 补齐无真实网卡场景下的夹具测试。
  - 📦 [fixtures/fixtures.mbt](../fixtures/fixtures.mbt) + [mailbox/mailbox_test.mbt](../mailbox/mailbox_test.mbt) + [runtime/runtime_test.mbt](../runtime/runtime_test.mbt)

提交映射（选项 → commit）：
- `基础发现流程与拓扑对象` → `ea96328` `feat: add slave discovery model`
- `SII/ESI 最小解析` → `a8be821` `feat: parse sii and esi metadata`
- `FMMU/SM 自动配置计算` → `bfbe7d5` `feat: calculate fmmu and sync manager mapping`
- `发现与配置夹具测试` → `b38f38c` `test: add discovery and config fixture coverage`
- `网络一致性 4-tuple 校验` → `3a08bff` `fix(validate): compare full identity 4-tuple`
- `按站地址位置校验与边界测试` → `a6069bb` `fix: validate slaves by configured position and add boundary tests`
- `SII/ESI 规范修正` → `2006272` `fix(mailbox): ESI/SII conformance fixes per ETG1000.6`

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
  - 📦 [runtime/runtime_test.mbt](../runtime/runtime_test.mbt) (~13 tests)
- [x] **【缺口】pdo_exchange 实体循环**：完成 LRW/LRD/LWR 实际收发，使 run_cycle 能驱动真实 PDO 交换 [ETG.1500 #201]
  - ✅ 代码审查确认 pdo_exchange 已完整实现 (LRW + logical addressing)
- [x] **【缺口】Device Emulation 感知**：ESM 引擎根据 SII DeviceEmulation 标志跳过 Error Indication Acknowledge [ETG.1500 #103]
  - ✅ [protocol/esm_extensions.mbt](../protocol/esm_extensions.mbt) : read_device_emulation + request_state_aware
- [x] **【缺口】ESM 超时值**：从 SII/ESI 或 ETG.1020 默认值获取 ESM 转换超时 [ETG.1500 §5.3.4]
  - ✅ [protocol/esm_engine.mbt](../protocol/esm_engine.mbt): `EsmTimeoutPolicy` + `esm_default_timeout` + `esm_timeout_for` + `transition_through_with_timeout_policy`
  - ✅ 参考实现映射：SOEM `ecx_statecheck(..., EC_TIMEOUTSTATE)`（全局状态超时）、ethercrab `Timeouts::state_transition`（统一状态迁移超时）、gatorcat `init/preop/safeop/op` 分态超时参数
- [x] **【缺口】OpOnly 标志处理**：ESI OpOnly Flag 为真时，非 Op 状态禁用输出 SM [ETG.1500 §5.3.4]
  - ✅ [protocol/esm_extensions.mbt](../protocol/esm_extensions.mbt) : apply_op_only_policy + set_sm_enable
  - ✅ [mailbox/sii_flags.mbt](../mailbox/sii_flags.mbt) : SiiGeneral::is_op_only/prefers_not_lrw/supports_identification_ado

提交映射（选项 → commit）：
- `ESM 状态流转与回退` → `b4019b1` `feat: add esm transition engine`
- `PDO 周期交换主循环` → `cfd6f14` `feat: add pdo runtime loop`
- `运行时调度与 telemetry` → `ddc6158` `feat: add runtime scheduler and telemetry`
- `Free Run 与恢复路径测试` → `3ccd459` `test: cover free-run and recovery paths`
- `Device Emulation + OpOnly 扩展` → `89f0cc4` `feat: implement P0 gaps — mailbox transport, RMSM, SDO transaction, EEPROM read, ESM extensions`
- `ESM 超时策略（默认值 + 可覆盖策略）` → `51ab95c` `feat(protocol): add ESM timeout policy and defaults`
