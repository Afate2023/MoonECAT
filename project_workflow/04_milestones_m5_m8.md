# MoonECAT 里程碑 M5-M8

本文件由原 AI 任务清单拆分整理而来，对应原第 2 节中 M5 到 M8。

> **进度摘要**：M5-M7 全部完成 ✅；M8 为当前活跃里程碑，涵盖 L2→L4 跨度与主线 A 收口。

| 里程碑 | 领域 | L 级 | 主线 | 状态 |
|:---:|---|:---:|:---:|:---:|
| M5 | CoE/SDO / 邮箱引擎 | L2 | — | ✅ |
| M6 | 网络配置增强 | L2 | — | ✅ |
| M7 | DC 同步 | L2 | — | ✅ |
| M8 | CLI·集成·多后端 | L2-L4 | A | ⚠️ |

## 2. 里程碑任务（续）

### M5 CoE/SDO、邮箱引擎 — ✅ 核心事务已闭环，含分段/CA/Info 【L2】

- [x] 实现 MailboxHeader 编解码。
  - 📦 MailboxHeader::to_bytes/from_bytes + MailboxType 枚举
- [x] 实现 CoE/SDO 请求编码框架。
  - 📦 CoeService/SdoCommand/SdoRequest 类型 + coe_engine 常量
- [x] **【缺口】SDO Upload/Download 事务闭环**：编码 SDO 请求 → 通过邮箱发送 → 等待响应 → 解码结果 [ETG.1500 #501 shall]
  - ✅ [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt) : sdo_download/upload + retry
- [x] **【缺口】Mailbox Resilient Layer (RMSM)**：丢帧恢复状态机 + Counter/Repeat 管理 [ETG.1500 #402 shall]
  - ✅ [mailbox/rmsm.mbt](../mailbox/rmsm.mbt): Rmsm struct + begin/validate/timeout/reset
  - ✅ [mailbox/mailbox.mbt](../mailbox/mailbox.mbt): `MailboxRepeatState`，统一 Repeat Request / RepeatAck 位语义
  - ✅ [protocol/mailbox_transport.mbt](../protocol/mailbox_transport.mbt): `mailbox_recv_rmsm` / `mailbox_recv_ap_rmsm`，在读邮箱超时后触发 SM Repeat 请求并轮询 RepeatAck
  - ✅ [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt): CoE/SDO 读响应、分段上传/下载、SDO Info 全部切到 repeat-aware mailbox receive
  - ✅ [runtime/diagnosis.mbt](../runtime/diagnosis.mbt): diagnosis mailbox 读路径改为 `mailbox_recv_rmsm`；[protocol/mailbox_transport.mbt](../protocol/mailbox_transport.mbt) 的 `mailbox_exchange` / `mailbox_exchange_ap` 也强制经由 RMSM
  - ✅ [protocol/protocol_test.mbt](../protocol/protocol_test.mbt): FP/AP repeat replay mock 覆盖；`moon test protocol` = `109/109`，`moon test mailbox` = `93/93`
- [x] **【缺口】Mailbox polling**：周期性检查 Input-Mailbox 或 Status-Bit [ETG.1500 #404 shall]
  - ✅ [protocol/mailbox_transport.mbt](../protocol/mailbox_transport.mbt): mailbox_poll SM status bit
- [x] **【缺口】Emergency Message 接收**：解码 CoE Emergency 帧并分发到应用 [ETG.1500 #505 shall]
  - ✅ [mailbox/emergency.mbt](../mailbox/emergency.mbt): decode_emergency/decode_emergency_frame
  - ✅ [runtime/runtime.mbt](../runtime/runtime.mbt): poll_emergencies 主循环集成 + configure_emergency_stations → `d0fa1c7`
- [x] SDO 分段传输 (Segmented Transfer) [ETG.1500 #502 should]
  - ✅ [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt): 分段上传循环拼接（toggle / last segment）
  - ✅ [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt): 分段上传起始/分段响应解码
  - ✅ [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt): 分段下载请求构帧 + 分段下载响应解码
  - ✅ [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt): 分段下载请求/响应循环（含 toggle 校验）
- [x] SDO Complete Access [ETG.1500 #503 should, shall if ENI]
  - ✅ [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt): `build_sdo_download_ca` / `build_sdo_upload_ca` + CA bit 编码
  - ✅ [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt): `sdo_download_complete_access` / `sdo_upload_complete_access`
  - ✅ [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt): CA 上传/下载分段续传循环
- [x] SDO Info Service [ETG.1500 #504 should]
  - ✅ [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt): `build_sdo_info_get_od_list_request` + `decode_sdo_info_response`
  - ✅ [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt): `sdo_info_get_od_list`（分片拼接 + list type 头处理）
  - ✅ [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt): `decode_sdo_info_od_list_payload`
  - ✅ [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt): `build_sdo_info_get_od_request` / `build_sdo_info_get_oe_request`
  - ✅ [protocol/sdo_transaction.mbt](../protocol/sdo_transaction.mbt): `sdo_info_get_od_description` / `sdo_info_get_oe_description`

提交映射（选项 → commit）：
- `SDO Upload/Download 事务闭环` → `698052c` `feat: add coe sdo transaction engine`
- `Mailbox Resilient Layer (RMSM)` + `Mailbox polling` + `Emergency Message` → `89f0cc4` `feat: implement P0 gaps — mailbox transport, RMSM, SDO transaction, EEPROM read, ESM extensions`
- `Mailbox Repeat Request/Ack recovery wiring` → `62c4742` `feat(mailbox): recover lost reads with repeat ack`
- `Mailbox Repeat Request/Ack diagnosis/helper closure` → `157c0bf` `feat(runtime): route diagnosis mailbox reads through rmsm`
- `Segmented Transfer（上传）` → `27b9c4b` `feat: add segmented SDO upload path`
- `Complete Access + SDO Info 基础` → `afb1a29` `feat: add complete-access and sdo-info foundations`
- `Segmented Transfer（下载）+ CA 分段续传` → `9266591` `feat: complete segmented sdo and CA continuation`
- `SDO Info OD/OE + 运行态 DC 补偿联动实现`（含 SDO Info 完整收口） → `0971f77` `feat: complete sdo info and runtime dc compensation`
- `格式与接口同步` → `a969b5e` `chore: sync formatted sources and mbti after info`
- `SDO validate_response 误判丢帧修复（Merge PR #1）` → `5d54aca` `Handle validate_response false return: discard stale frames and re-read in SDO transactions`
- `Mailbox retry 事务方法与 SDO 超时修复` → `fe1e2ef` `feat(mailbox): add retry transaction methods and enhance SDO upload/download handling, fix moon test timeout`
- `AL Status Code / SDO Abort Code 描述表` → `d19db2d` `feat(protocol): add AL Status Code and SDO Abort Code description tables per ETG.1000.6`
- `Emergency 主动轮询运行态集成` → `d0fa1c7` `feat(runtime): integrate Emergency mailbox polling into PDO cycle per ETG1000.6`
- `SM Watchdog 寄存器读取与 SafeOp→Op 验证步骤` → `b77ae87` `feat(protocol): add SM Watchdog register read and SafeOp->Op validation step per ETG1000.4`
- `SII Timeout → ESM 转换策略接线` → `d6d26bf` `feat(protocol,runtime): wire SII timeout category to ESM transition policy per ETG.2010`
- `DL/Ph Error Counters 寄存器读取` → `a20f955` `feat(protocol,runtime): add DL/Ph Error Counters read (ESC 0x0300-0x0313) per ETG1000.4`
- `FoE 基础协议` → `4923f4b` `feat(mailbox,protocol): add FoE basic protocol (ETG1000.6 §5.8)`
- `SYNC1 独立配置` → `1acf07d` `feat(protocol): add SYNC1 configuration to dc_configure_sync0 per EtherCAT Compendium §5.5`
- `EEPROM 数据写入` → `c0f4f6a` `feat(protocol): add EEPROM word-level write (ETG1500 #305)`

### M6 网络配置增强 — ✅ 已完成 【L2】

- [x] **EEPROM/SII 寄存器级读取流程**：通过 ESC 寄存器 0x0502-0x0508 读取 EEPROM 内容 [ETG.1500 #305]
  - ✅ [protocol/eeprom.mbt](../protocol/eeprom.mbt): eeprom_read_word/eeprom_read
- [x] **Explicit Device Identification**：读取 IdentificationAdo 进行 Hot Connect 防误插 [ETG.1500 #303 should]
  - ✅ [runtime/scan.mbt](../runtime/scan.mbt): `scan_with_identification_ado(...)` + `SlaveReport.identification`
  - ✅ [hal/config.mbt](../hal/config.mbt): `SlaveConfig.expected_identification`
  - ✅ [runtime/validate.mbt](../runtime/validate.mbt): `IdentificationMismatch` + 显式标识校验
- [x] **Station Alias Addressing**：读取 Register 0x0012 + 激活 DL Control Bit 24 [ETG.1500 #304 may]
  - ✅ [protocol/discovery.mbt](../protocol/discovery.mbt): `read_station_alias` + `enable_alias_addressing`
- [x] Error Register / Diagnosis Object 接口：向应用暴露错误和诊断信息 [ETG.1500 §5.3.5]
  - ✅ [runtime/diagnosis.mbt](../runtime/diagnosis.mbt): `read_error_register`/`read_diagnosis_counter`/`read_slave_diagnosis`
  - ✅ 真实设备诊断路径已稳定：修复 FP 地址打包、ESM 轮询/告警确认、Mailbox 轮询窗口与 CoE 头地址语义，并补齐 diagnosis 专用 prepare/restore helper（commit: `fa72af8`）
  - ✅ diagnosis 邮箱读路径现已接入 RMSM repeat-aware receive，超时仍保留 SM0/SM1/AL 快照诊断信息（commit: `157c0bf`，验证：`moon test runtime` = `105/105`）

提交映射（选项 → commit）：
- `EEPROM/SII 寄存器级读取流程` → `89f0cc4` `feat: implement P0 gaps — mailbox transport, RMSM, SDO transaction, EEPROM read, ESM extensions`
- `Explicit Device Identification (#303)` → `9ce7516` `feat: add explicit device identification validation`
- `Station Alias Addressing` → `fbb3745` `feat: implement IRQ consumption and alias addressing path`
- `Error Register / Diagnosis Object 接口` → `9541967` `feat: wire cli commands and add diagnosis interface`
- `真实设备 diagnosis 传输与 runtime helper 稳定化` → `fa72af8` `Fix real-device diagnosis transport and runtime helpers`
- `显式标识强化校验` → `9284ede` `feat: strengthen explicit identification validation`
- `AP 邮箱诊断路径` → `b70b5e2` `feat(protocol): add AP mailbox diagnosis path`
- `Diagnosis AL State / Error Flag / Status Code 增强` → `2fdf472` `feat(diagnosis): enhance diagnosis reporting with AL state, error flag, and status code`

### M7 DC 同步 — ✅ 基础能力与运行态补偿已完成 【L2】

- [x] DC 初始化流程：传播延迟测量 + Offset 补偿 + Start Time 写入 [ETG.1500 #1101]
  - ✅ [protocol/dc.mbt](../protocol/dc.mbt): `dc_configure_linear`、`dc_configure_sync0`
  - ✅  [runtime/runtime.mbt](../runtime/runtime.mbt): `Runtime::init_dc`
- [x] DC 持续漂移补偿：ARMW 周期帧 [ETG.1500 #1101]
  - ✅ [protocol/dc.mbt](../protocol/dc.mbt): `dc_compensate_cycle` (FRMW)
  - ✅ [runtime/runtime.mbt](../runtime/runtime.mbt): `run_cycle` 周期补偿
- [x] Continuous Propagation Delay compensation [ETG.1500 #1102 should]
  - ✅ [protocol/dc.mbt](../protocol/dc.mbt): `reg_dc_system_delay` 改为基于参考站接收时间差估计
  - ✅ [protocol/dc.mbt](../protocol/dc.mbt): `dc_reestimate_propagation_delays` 运行态重估 + 平滑更新
  - ✅ [runtime/runtime.mbt](../runtime/runtime.mbt): 每 100 周期触发一次连续重估并计数
- [x] Sync window monitoring：读取 Register 0x092C [ETG.1500 #1103 should]
  - ✅ [protocol/dc.mbt](../protocol/dc.mbt): `dc_read_sync_window`

提交映射（选项 → commit）：
- `DC 初始化流程 + SYNC0 + 漂移补偿主路径` → `ce48f37` `feat: implement distributed clock runtime and protocol support`
- `传播延迟估计模型改进` → `4287d29` `feat: improve dc propagation delay estimation`
- `运行态连续传播延迟补偿（周期重估）` → `0971f77` `feat: complete sdo info and runtime dc compensation`

### M8 CLI、文档、最终集成与多后端交付 — ⚠️ Native / Extism 后端待落地 【L2-L4 · 主线 A】

- [x] 实现 `moonecat scan` 命令（库层接口）。
  - 📦 [runtime/scan.mbt](../runtime/scan.mbt): scan() → ScanReport
- [x] 实现 `moonecat validate` 命令（库层接口）。
  - 📦 [runtime/validate.mbt](../runtime/validate.mbt): validate() → ValidateReport
- [x] 实现 `moonecat run` 命令（库层接口框架）。
  - 📦 [runtime/runtime.mbt](../runtime/runtime.mbt): Runtime + run_cycle
- [x] 补全文档：架构、接口、测试方式。
  - 📦 [README.mbt.md](../README.mbt.md) 已更新
- [x] **【缺口】CLI 实际接入**：[cmd/main/main.mbt](../cmd/main/main.mbt) 已接入 Mock HAL + scan/validate/run 流程
  - ✅ 当前已支持 `--backend <mock|native|native-windows-npcap|native-linux-raw>` 与 `--if <interface>` 参数，默认仍为 mock
  - ✅ `run` 已支持 `--startup-state` / `--shutdown-state`，可控制运行前后 EtherCAT 从站状态机迁移
  - ✅ `diagnosis` 已支持通过 Native 后端对指定从站读取 Error Register / Diagnosis Counter，支持 `--station` 与 JSON 输出
  - ✅ `od` 已支持通过 Native 后端对指定从站执行 `OD List` / `OD Description` / `OE Description` 只读浏览，支持 `--station`、`--index`、`--subindex`、`--list-type` 与 JSON 输出（commit: `fcc384e`）
  - ✅ `od` 失败路径已补齐结构化错误输出：JSON `error.category/detail/abort_code` 与文本 `Error Category` / `Abort Code` / `Error Detail` 同步，分类稳定到 `transport-failure` / `protocol-failure` / `unsupported`（commit: `f8f75bd`）
  - ✅ diagnosis 的 mailbox/ESM 准备与恢复逻辑已下沉到 [runtime/diagnosis.mbt](../runtime/diagnosis.mbt)，CLI 保持为薄封装；`Init -> PreOp` 归一化仅用于 diagnosis，不泛化到通用 state 命令（commit: `24e89e6`）
- [x] **【缺口】结构化诊断输出**：scan/validate/run 提供 JSON/human-readable 双格式输出
- [x] **【新增】在线 SII 诊断入口**：CLI 已支持最小 `read-sii` 命令，通过 Native 后端按从站位置读取 EEPROM 窗口并输出 header/general/strings/categories
  - ✅ [cmd/main/main.mbt](../cmd/main/main.mbt) + [cmd/main/main_wbtest.mbt](../cmd/main/main_wbtest.mbt)，代码提交：`26166fc`
  - ✅ 2026-03-22 已进一步从“最小在线诊断入口”收口到共享聚合模型：`read-sii` / `esi-sii` / runtime startup / mailbox mapping 统一改为消费 `SiiFullInfo`，由 [mailbox/sii_parser.mbt](../mailbox/sii_parser.mbt) 的 `parse_sii_full_info` 和 [mailbox/mapping.mbt](../mailbox/mapping.mbt) 的 `calculate_slave_mapping_from_sii` 提供单次解析结果，代码提交：`ebbaf31`
  - ✅ 2026-03-23 已把 protocol 层的完整 EEPROM 补读链路公开为 [protocol/eeprom.mbt](../protocol/eeprom.mbt) 的 `read_sii_bytes` / `read_sii_bytes_ap`，在 ownership 切换和 32/64-bit chunk 兼容基础上按 EEPROM size 自动扩展初始探测窗口，`read-sii` 已切换到该入口，代码提交：`45b7217`
  - ✅ 2026-03-23 已把 `DataTypes(20)`、`Dictionary(80)`、`Hardware(90)`、`Vendor Information(100)`、`Images(110)` 从普通 `Raw` 提升为显式标准保留类别，CLI 与 offline projection 现在会稳定输出类别名和 `known=true`，同时继续保留原始 bytes，代码提交：`5b8f96e`
  - ✅ 2026-03-23 已为全部 category 增加稳定 `category_class` 导出；其中 `Raw` 现可细分为 `standard-unknown` / `device-specific` / `vendor-specific` / `application-specific`，JSON 与文本输出一致暴露该分类，代码提交：`ff93f64`
  - ✅ 2026-03-23 已进一步补出 raw 扩展类别的 typed overlay 挂载点：公共模型新增 `overlay_candidate()` / `dispatch_key()`，CLI categories JSON 与文本 raw-section 新增 `overlay_key`，后续可直接据此挂接厂商/应用特定解析器，代码提交：`ca0a906`
  - ✅ 2026-03-23 已把 raw overlay 输出进一步稳定为 decoder 状态合同：公共模型新增 `decoder_name()` / `status_label()`，CLI categories JSON 与文本 raw-section 新增 `overlay_status` / `overlay_decoder`，当前未注册解码器的扩展 section 会显式标记为 `opaque`，代码提交：`b024aec`
- [x] 评估并整理 Extism 宿主接入边界。
  - ✅ [docs/EXTISM_HOST_BOUNDARY.md](../docs/EXTISM_HOST_BOUNDARY.md): 宿主能力、HAL 适配边界、错误映射与验证清单
  - ✅ [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md): Extism / WASM Host Integration 总览入口
- [ ] **【新增】Native 后端首版**：以 Linux Raw Socket 为优先落地点，Windows Npcap 保持同一 HAL 契约与诊断语义。
  - 规划文档： [docs/NATIVE_BACKEND_PLAN.md](../docs/NATIVE_BACKEND_PLAN.md)
  - 当前状态：已创建 [hal/native/moon.pkg](../hal/native/moon.pkg) Native 包，包含 `native-stub`、native / wasm-gc 双 target 文件、Windows Npcap 与 Linux Raw Socket FFI 包装、统一 `NativeNic`、结构化 `list-if` 输出与最小测试；`moon run cmd/main list-if -- --backend native-windows-npcap --json` 已在本机 Npcap 1.8.4 下跑通（commit: `4eabaf7`），空总线 `scan/validate/run` smoke 与运行稳定化已完成（commit: `1a38d47`），Realtek USB GbE 真实从站扫描已恢复非零身份字段（commit: `263394a`），CLI 已新增 Native `state` 命令用于广播/定点 EtherCAT 从站状态机迁移，`run` 已支持可选 startup/shutdown ESM 状态，Linux Raw Socket 的 MoonBit/C 双层错误码已细化 link-down / privilege / missing-interface / timeout 诊断（commit: `bd95053` 及后续收口）；2026-03-16 又补齐了基于接口元数据的自动候选筛选、固定超时 BRD 探测，以及 scan 站地址规划策略切面（commit: `bff2f5e`），现在在省略 `--if` 的情况下也能自动落到 Realtek USB GbE 并完成真实单从站扫描。随后补齐了 Native 自动选卡 / 省略 `--station` 广播语义的 CLI 覆盖（commit: `5c4dd51`），并把严格 ESM 路径、AL 错误清除和 state/run 统一状态迁移接到实机路径上（commit: `e143fce`）；2026-03-18 再按 EtherCAT Compendium 重排 `run --startup-state op` 的启动阶段、补充基于 AL Status Code 的恢复策略，并把 startup mapping 扩展为同时写入 mailbox `SM0/SM1` 与 PDO SyncManager/FMMU，使真实单从站链路重新稳定进入 `Op`（commit: `a4cb887`）。2026-03-19 又补齐了基于 EEPROM 元数据的完整 SII 补读、`Init -> PreOp` mailbox/diagnosis 严格恢复路径，以及零长度 PDO SM 的位宽回填，当前在新伺服上已重新验证 `state --path --state preop`、`diagnosis` 与 `od` 可用（commit: `e763563`）。2026-03-20 继续补齐了配置类 AL 错误的共享恢复入口、SO 窗口启动 mailbox 命令框架、`esc-regs` / `expected-regs` CLI 诊断入口，以及对 ESC SyncManager/FMMU activation 字段的保真处理（commit: `b3b0717`）；当前 `PreOp + AL 0x001E` 不再在清错阶段误抛异常，而会稳定暴露为真实的 `PreOp -> SafeOp` 输入映射不匹配，后续仍需让 SafeOp 过程映射优先采用 CoE 激活 PDO。2026-04-11 再围绕同一 `VT_EX_CA20_20250225.esi.json` 单从站链路补齐 live startup helper 与 CLI 状态追踪一致性：先在底层启动路径丢弃 stale mailbox frame、修正 PDO 派生 SM 长度覆盖与 diagnosis mailbox 旧帧容忍（commit: `e3baf07`），再在 runtime 中引入按站点复用的 startup preparation、跳过已就绪从站重复 demotion/remap、合并显式 startup mailbox command，并把 DS402 `0x6060` 在 16-bit RxPDO 映射时改为 process-image seed 优先（commit: `7d0ced3`），最后在 CLI `state --path` / `startup-trace` 增加 live PDO audit、mailbox drain 与 scan override 复用（commit: `a2a99d0`）。对应白盒回归已并入 runtime / cmd / mailbox / protocol 测试，全量 `moon test` 为 `1826 passed / 0 failed`；同日已确认 `run --backend native-windows-npcap --esi-json "References\\VT_EX_CA20_20250225.esi.json" --device-index 0 --until-fault` 可以继续作为当前单从站链路回归入口。Raw Socket 完善项与 Npcap 实机 run/ESM 设计见 [docs/NATIVE_REAL_STATE_TRANSITION_DESIGN.md](../docs/NATIVE_REAL_STATE_TRANSITION_DESIGN.md)
  - ✅ 2026-03-30 已修复 [runtime/runtime_wbtest.mbt](../runtime/runtime_wbtest.mbt) 中 `ActivePdoLengthsNic` 白盒测试桩的 `sm_windows` 类型与初始化问题：内部 mailbox SM 窗口改为可变 `Array[Byte]`，仅在响应边界投影为 `Bytes`，从而同时消除 `Bytes` 不可写与 `Int/UInt` 索引不匹配导致的编译失败，并避免写循环里的额外 `Bytes` 重建分配（commit: `5658372`，验证：`moon check runtime`、`moon test runtime/runtime_wbtest.mbt`）。
  - ✅ 参考 [References/EtherCAT_Compendium/EtherCAT_Compendium.md](../References/EtherCAT_Compendium/EtherCAT_Compendium.md) §3.9 Working Counter、§7 EtherCAT State Machine、§7.4 AL Status Codes：Native `diagnosis` 现已在进入 PreOp 前抓取单站 `AL Status(0x0130)` / Error Flag / `AL Status Code(0x0134)` 快照，并与 CoE `0x1001` / `0x10F3` 一并输出，便于 WKC 或 ESM 异常后的逐站定位
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
  - 规划文档： [docs/EXTISM_WASM_BACKEND_PLAN.md](../docs/EXTISM_WASM_BACKEND_PLAN.md)
  - 当前状态：已创建 [plugin/extism/moon.pkg](../plugin/extism/moon.pkg) 包并接入基于 Mock HAL 的 `scan/validate/run` 回放入口，包含 envelope 类型、稳定错误码映射与最小 JSON 回放测试；宿主所需 `nic_*` / `clock_*` / `file_*` / `shared_memory` capability contract 已建模并随 diagnostics 输出，实际 host capability adapter 与共享内存传输仍待接入
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
    - Host capability contract 与 [docs/EXTISM_HOST_BOUNDARY.md](../docs/EXTISM_HOST_BOUNDARY.md) 保持一致，超时单位统一为 ns
    - ESM / PDO / mailbox 行为与 native 语义一致，不新增插件特化状态机
    - 至少有一条最小集成回放覆盖 `scan -> validate -> run -> stop`
    - 错误输出保持稳定字符串码 + 明细消息，能映射到现有 `EcError` 分类
  - 非目标：插件内部直连 Raw Socket、在 `protocol/` 或 `runtime/` 中直接依赖 Extism API、单独维护第二套 CLI 逻辑
  - 依赖：`docs/EXTISM_HOST_BOUNDARY.md`、共享内存信封格式、稳定的库层 API
- [x] **【新增】多后端发布物矩阵**：把 CLI Native、Library Native、Extism Plugin 三类产物的边界、配置与回归入口写清楚。
  - ✅ [docs/BACKEND_RELEASE_MATRIX.md](../docs/BACKEND_RELEASE_MATRIX.md)：已补齐 Native CLI / Native Library / Extism Plugin 的输入、输出、依赖环境与最小验证命令（commit: `5583dcb`）
  - ✅ 当前 Native CLI smoke 已在 Windows Npcap 1.8.4 上实测跑通：`list-if -> scan -> validate -> run`，其中空总线场景返回 `0 slaves / PASS / Done`
  - ✅ 2026-03-12 再验证：`moon test` = `286/286`、`moon test hal/native` = `5/5`、`moon test plugin/extism` = `5/5`，且 `list-if` 与 Realtek USB GbE 接口上的 `scan` 均成功
  - ✅ 2026-03-16 再验证：`moon run cmd/main list-if -- --backend native --json` 已能把 Realtek USB GbE 识别为唯一 `connected=true / wireless=false` 候选；随后 `moon run cmd/main scan -- --backend native --json` 在省略 `--if` 时自动选中该口并扫描到 1 个真实从站（station 4097 / vendor 1894 / product 2320）
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
- `native slave identity recovery`：基于 SII/AP 优先回退链修复真实从站身份读取，并过滤 Native 自发回显帧
- `native interface auto-probe + scan strategy seam`：基于接口元数据过滤候选网卡、固定超时 BRD 自动探测，并把 scan 站地址规划抽成可替换策略接口
- `minimal read-sii cli command`：新增 Native CLI 在线 SII 读取入口与最小 JSON/文本输出
- `shared sii aggregate model`：新增 `SiiFullInfo` 聚合模型并收口 CLI/runtime/offline config/mapping 消费
- `complete online sii byte-read chain`：新增 `read_sii_bytes` / `read_sii_bytes_ap` 并让 `read-sii` 自动扩展到完整 EEPROM 镜像
- `standard reserved sii category recognition`：新增 20/80/90/100/110 的显式类别识别与稳定导出标题
- `sii category class export`：新增 `category_class` 导出并把 Raw 分类细分为 standard/device/vendor/application-specific
- `raw category overlay hook`：新增 `overlay_candidate` / `overlay_key` 作为 typed overlay 挂载点
- `raw category overlay decoder status`：新增 `decoder_name` / `status_label` 与 CLI `overlay_status` / `overlay_decoder`
- `native state transition cli command`：新增 Native CLI 广播/定点 EtherCAT ESM 状态迁移入口与设计文档
- `backend release matrix docs`：Native CLI / Native Library / Extism Plugin 交付边界、环境要求与 smoke 命令
- `native ffi memory safety validation`：ownership 标注、句柄清理与 AddressSanitizer 检查
- `extism wasm adapter entrypoints`：插件导出入口 + 请求/响应信封 + Mock replay 闭环
- `extism host shared-memory transport`：共享内存缓冲区与 host capability 对接
- `extism replay validation`：WASM/宿主最小回放验证与错误码对齐
- `backend release matrix docs`：交付物矩阵、运行方式与回归入口整理

提交映射（选项 → commit）：
- `moonecat scan` 库层接口 → `1c427d7` `feat: add moonecat scan command`
- `moonecat validate` 库层接口 → `3d921de` `feat: add moonecat validate command`
- `moonecat run` 库层接口框架 → `a9dbc96` `feat: add moonecat run command`
- `补全文档（架构/接口/测试方式）` → `f5d3b14` `docs: document architecture and user workflows`
- `CLI 实际接入` + `结构化诊断输出` → `9541967` `feat: wire cli commands and add diagnosis interface`
- `Windows Npcap Native 后端骨架` → `c873347` `feat(native): add windows npcap backend scaffold`
- `Native interface enumeration + runtime loading` → `4eabaf7` `feat(native): load npcap at runtime and enable list-if`
- `Native CLI smoke regression + release matrix docs` → `5583dcb` `test(cli): add native smoke regression and release matrix docs`
- `Native real smoke stability fix` → `1a38d47` `fix(native): stabilize real smoke run path`
- `Native slave identity recovery` → `263394a` `fix(native): recover slave identity from real scans`
- `Native interface auto-probe + scan strategy seam` → `bff2f5e` `feat(native): auto-probe interfaces and extract scan strategy`
- `最小 read-sii CLI 入口` → `26166fc` `feat(cli): add minimal read-sii command`
- `共享 SII 聚合模型` → `ebbaf31` `feat(sii): share aggregated full-info model`
- `在线完整 EEPROM 补读链路` → `45b7217` `feat(protocol): auto-expand complete sii reads`
- `标准保留 SII 类别识别` → `5b8f96e` `feat(sii): recognize standard reserved categories`
- `SII category class 导出` → `ff93f64` `feat(sii): export category classes`
- `Raw SII category overlay 挂载点` → `ca0a906` `feat(sii): add raw category overlay hook`
- `Native EtherCAT 状态迁移 CLI 入口` → `f01a411` `feat(cli): add native ethercat state transition command`
- `Native run 可选 ESM 状态 + Raw Socket 错误分类` → `bd95053` `feat(native): add configurable run states and raw-socket error mapping`
- `Native 自动选卡 + 省略站号广播覆盖` → `5c4dd51` `test(cli): cover native auto-select and broadcast state`
- `严格 ESM 路径接入 state/run` → `e143fce` `feat(esm): wire strict transitions into state and run`
- `Native run Op 启动顺序 + mailbox SM 启动映射修复` → `a4cb887` `fix(runtime): stabilize native op startup sequencing`
- `ActivePdoLengthsNic sm_windows 类型/初始化修复` → `5658372` `fix(runtime): update sm_windows type and initialization for ActivePdoLengthsNic`
- `启动恢复共享入口 + SO mailbox 启动命令 + ESC 映射诊断` → `b3b0717` `Refine startup recovery and ESC mapping diagnostics`
- `Native mailbox diagnosis CLI 入口` → `36cfe87` `feat(cli): add native diagnosis command`
- `真实设备 diagnosis 传输与 runtime helper 稳定化` → `fa72af8` `Fix real-device diagnosis transport and runtime helpers`
- `CLI diagnosis 改为 runtime session helper 薄封装` → `24e89e6` `Refactor CLI diagnosis to use runtime session helpers`
- `对象字典浏览 CLI 入口` → `fcc384e` `feat(cli): add object dictionary browsing command`
- `对象字典浏览错误分类与结构化失败输出` → `f8f75bd` `feat(cli): classify od browse failures`
- `CLI 后端选择（mock/native）` → `04fa2f9` `feat(cli): add selectable mock and native backends`
- `Extism / WASM 插件骨架` → `2484759` `feat(extism): scaffold plugin envelopes and entrypoints`
- `Extism Mock 回放入口` → `9cc3456` `feat(extism): wire mock replay scan validate run entrypoints`
- `Extism host capability contract` → `f0661ce` `feat(extism): describe required host capabilities`
- `接口与格式同步` → `a969b5e` `chore: sync formatted sources and mbti after info`
- `Extism 宿主接入边界整理` → `137f80a` `docs: refresh remaining items and define Extism host boundary`
- `Native run 长跑控制、连续超时故障与 CLI 周期参数` → `71f178e` `feat(runtime): add long-run controls and timeout faults`
- `Npcap 接口列举独立命令` → `6682636` `feat(native): add npcap interface listing command`
- `Linux Raw Socket errno 细化分类` → `2058971` `fix(native): classify linux raw-socket errno codes in C stub`
- `platform stub stdio.h 修复（Linux 编译）` → `cef8362` `fix(platform_stub): include stdio.h for snprintf definition, fix linux error`
- `AP 与 RX noise 诊断加固` → `75b35a4` `fix(native): harden diagnosis against AP and rx noise`
- `诊断超时控制 CLI 入口` → `da2c54b` `feat(cli): add diagnosis timeout controls`
- `startup prep 下沉到 runtime` → `82f6b7e` `refactor(runtime): sink startup prep from cli`
- `SafeOp 前过程数据准备` → `f5644c5` `feat(cli): prepare process data before safeop`
- `Op 启动与 SII DC 准备联动` → `75328b7` `feat(cli): wire op startup with sii dc prep`
- `NDJSON 运行进度与独立 scan CSA 规划` → `0bda199` `feat(runtime): add ndjson run progress and isolated scan CSA planning`
- `run ndjson 故障汇总脚本` → `23c85c1` `feat(scripts): summarize run ndjson faults`
- `SII 字符串 UTF-8 默认解码` → `033b859` `fix(sii): decode strings as utf8 by default`
- `read-sii TxPDO/RxPDO 详情渲染` → `462bed5` `feat(cli): render sii txpdo and rxpdo details`
- `read-sii 输出增强至 siitool 对齐` → `c853946` `feat(cli): enrich read-sii output toward siitool parity`
- `SII category label 消歧` → `41e1442` `test(mailbox): disambiguate category class label`
- `统一配置对象模型` → `d2ba48d` `feat(runtime): add unified configuration model`
- `最小 ENI XML 投影` → `fa82594` `feat(runtime): add minimal ENI XML projection`
- `ENI 配置差异分级` → `6f4241a` `feat(cli): add ENI-backed validation grading`
- `ENI 验证摘要扩展` → `121cafa` `feat(runtime): expand ENI validation summaries`
- `ESI XML → JSON 共享桥` → `1e23be5` `feat(esi): route xml import through shared json bridge`
- `ESI XML 投影到 SII 视图` → `3330009` `feat(cli): project esi xml into sii view`
- `ESI JSON 接入启动流` → `76a40c7` `Wire ESI JSON into startup flow`
- `统一诊断表面投影` → `d7e6c6a` `feat(runtime): unify diagnostic surface across products`
- `Hot Connect 拓扑分级` → `0a602b2` `feat(runtime): add hot-connect topology grading`
- `Preop 映射修复与 mailbox 刷新重试` → `013da5a` `Retry preop mapping refinement after mailbox refresh`
- `启动期诊断与 mailbox 校验` → `136466b` `Add startup diagnostics and mailbox validation`
- `启动路径 stale mailbox frame 丢弃与 PDO 长度覆盖` → `e3baf07` `Handle stale mailbox frames in startup paths`
- `live startup helper 与 DS402 16-bit 模式种子` → `7d0ced3` `Add live startup preparation helper`
- `state/startup-trace live PDO 审计与 mailbox drain` → `a2a99d0` `Audit live PDO state in state and startup trace`
