# MoonECAT Architecture

## Overview

MoonECAT is a modular EtherCAT master library written in
[MoonBit](https://docs.moonbitlang.com), targeting **ETG.1500 Class B**
compliance. It implements the EtherCAT communication stack from raw Ethernet
frames up to cyclic PDO exchange, SDO/CoE transactions, FoE file transfer,
EoE Ethernet tunneling, DC distributed clock synchronization, and HIL/co-sim
runtime hooks。

## Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│              CLI / Plugin                               │  cmd/main, plugin/extism
├─────────────────────────────────────────────────────────┤
│               Runtime & Orchestrator                    │  runtime/
│  scan · validate · run · diagnosis · monitor · verdict  │
│  configuration · topology · EoE · HIL · co-sim          │
├─────────────────────────────────────────────────────────┤
│          Mailbox & Config                               │  mailbox/
│  SII/ESI · FMMU/SM · CoE/SDO · FoE · EoE · SoE · RMSM │
├─────────────────────────────────────────────────────────┤
│           Protocol Core                                 │  protocol/
│  Frame · PDU · Address · ESM · DC · PDO · Pipeline      │
│  Zero-Copy Codec · Mailbox Transport · FoE Transaction  │
├─────────────────────────────────────────────────────────┤
│           Platform HAL                                  │  hal/
│  Nic · ZeroCopyNic · Clock · FileAccess · FramePool     │
│  hal/mock/ · hal/native/ · hal/mcu/                     │
└─────────────────────────────────────────────────────────┘
```

Each layer depends only on the layers below it. Cross-layer imports are
declared in each package's `moon.pkg` file.

## Package Reference

### `hal/` — Platform Abstraction

- **Traits**: `Nic` (open/send/recv/close), `ZeroCopyNic`
  (acquire_tx/tx_buffer/submit/recv/rx_buffer/release/close), `Clock`
  (now/sleep), `FileAccess` (read_file/write_file), `DiagnosticSink`
  (emit).
- **Types**: `Timestamp(Int64)`, `Duration(Int64)`, `NicHandle`,
  `FramePool` (预分配帧池), `FrameRef` (零拷贝帧引用/值类型),
  `FrameState` (Free/Acquired/Filled/Sending/Sent/Receiving/Received),
  `MutableProcessImage` (可变过程映像, FixedArray 后端).
- **Config**: `MasterConfig` (interface_name, cycle_period_ns,
  recv_timeout_ns, max_retries, dc_enabled),
  `SlaveIdentity` (vendor_id, product_code, revision, serial),
  `SlaveConfig` (position, expected_identity, expected_identification,
  expected_alias_address, configured_address, presence).
- **Errors**: `EcError` suberror 17 variants — LinkDown, SendFailed,
  RecvTimeout, RecvFailed, InvalidFrame, InvalidPdu, UnexpectedWkc,
  EsmTransitionFailed, EsmStateError, MailboxTimeout, MailboxProtocol,
  SdoAbort, SiiReadFailed, EsiParseFailed, ConfigMismatch, NotSupported,
  Internal.

### `hal/mock/` — Test & Verification Backend

- `MockNic` / `FaultNic` / `RecordingNic` / `ReplayNic` / `VirtualNic`:
  多种测试用 NIC 实现，支持帧录制/回放/故障注入。
- `VirtualBus` / `VirtualSlave` / `VirtualSlaveTemplate` / `VirtualMailbox`:
  虚拟总线和虚拟从站模型，可模拟多从站场景。
- `FaultInjection`: 一等故障注入模型 (DropTx/DropRx/DelayRx/CorruptFrame/
  WkcMismatch/Timeout/CustomFault)。
- `ScenarioRunner` / `ProtocolDeviation`: 场景化测试执行器。
- `EventRecorder` / `EventPersistence`: 事件录制与持久化。
- `FuzzConfig` / `FuzzDriver`: 协议模糊测试支持。
- `ZeroCopyMockNic`: 零拷贝路径的 mock 实现。

### `hal/native/` — Native Platform Backend

- **Windows Npcap**: `pcap_findalldevs` / `pcap_open_live` /
  `pcap_next_ex` / `pcap_sendpacket` 封装，运行时动态加载。
- **Linux Raw Socket**: `AF_PACKET` / `SOCK_RAW` / `ETH_P_ETHERCAT`，
  BPF 过滤，errno 分类映射。
- **零拷贝后端**: `NativeZeroCopyNic` 实现 `ZeroCopyNic` trait。
- **FFI 安全**: 整数句柄 ID + C 侧所有权表模型，所有非 primitive 参数
  `#borrow` 标注，接收帧复制后返回。
- **平台隔离**: `moon.pkg` targets 限定 FFI 文件仅在 native 目标构建，
  wasm-gc 下使用 fallback 文件。

### `hal/mcu/` — MCU Abstraction (骨架)

- `McuHal` trait: MCU 级 HAL 骨架，预留 DMA 描述符环映射。
- `EventBridge`: MCU 侧事件桥接。

### `protocol/` — EtherCAT Protocol Core

- **Frame codec**: `EcFrame`, `encode`/`decode`/`encode_pdu_frame_into`/
  `encode_lrw_frame_into`/`encode_zero_data_frame_into` 编解码。
- **PDU**: `Pdu` struct, `find_pdu_by_index`, pipeline 多 PDU datagram。
- **Addressing**: `auto_increment_address`, `configured_address`,
  `broadcast_address`, `logical_address`; `AddressType`/`AddressMode` enum。
- **Transactions**: `transact` / `transact_pdu` / `transact_pdu_retry`;
  register read/write: `read_register_fp` / `read_register_ap` /
  `write_register_fp` / `write_register_ap`。
- **Discovery**: `count_slaves`, `assign_station_address`,
  `read_station_address_ap`, `read_station_alias`, `write_station_alias`,
  `enable_alias_addressing`。
- **ESM engine**: `request_state`/`request_state_ap`/`request_state_aware`,
  `request_state_observe`/`request_state_with_process_data`,
  `transition_through`/`transition_through_ap`/
  `transition_through_with_timeout_policy`/`transition_to_target_strict`,
  `broadcast_state`, `build_transition_path`/`build_transition_route`/
  `build_strict_transition_route`/`build_shutdown_path`,
  `read_al_status`/`read_al_status_ap`/`read_al_status_code`/
  `read_al_status_snapshot`/`clear_al_error`/`recover_al_error_for_transition`,
  `apply_op_only_policy`, `EsmTimeoutPolicy`, `EsmStatusSnapshot`,
  `EsmStateRequestObservation`, `set_slaves_to_default`。
- **DC**: `dc_configure_linear`, `dc_configure_sync0`, `dc_latch_times`,
  `dc_read_port_times`/`dc_read_receive_time`/`dc_read_system_time_64`/
  `dc_read_sof`/`dc_read_sync_window`/`dc_check_support`/`dc_check_sync_window`,
  `dc_compensate_cycle`/`dc_static_sync`/`dc_broadcast_sync_window`,
  `dc_deactivate_sync`/`dc_deactivate_sync_all`,
  `dc_reestimate_propagation_delays`, `DcInitResult`, `DcPortTimes`。
- **PDO**: `PdoContext`, `PdoMapping`, `ProcessImage`,
  `pdo_exchange`/`pdo_exchange_result` (LRW),
  `pdo_read`/`pdo_write` (LRD/LWR),
  `PdoExchangeResult` 含 WKC 结果。
- **零拷贝 PDO**: `pdo_exchange_zero_copy`/`pdo_read_zero_copy`/
  `pdo_write_zero_copy` — MutablePdoContext 路径零 GC 分配。
- **Mailbox Transport**: `mailbox_send`/`mailbox_recv`/`mailbox_poll`/
  `mailbox_exchange` (AP/FP 变体), RMSM 重发支持
  (`mailbox_recv_rmsm`/`mailbox_recv_ap_rmsm`)。
- **SDO**: `sdo_upload`/`sdo_download`/`sdo_upload_complete_access`/
  `sdo_download_complete_access`/`sdo_upload_retry`/`sdo_download_retry`,
  SDO Info: `sdo_info_get_od_list`/`sdo_info_get_od_description`/
  `sdo_info_get_oe_description`。
- **FoE**: `foe_download`/`foe_upload` (FP/AP 变体)，完整文件传输流。
- **EEPROM**: `eeprom_read`/`eeprom_read_ap`/`eeprom_read_word`/
  `eeprom_write_word`/`eeprom_write_word_ap`, `read_sii_bytes`/
  `read_sii_bytes_ap`。
- **SM/FMMU 操作**: `set_sm_enable`, `read_sm_watchdog_config`/
  `write_sm_watchdog_config`, SM 看门狗配置, DL 错误计数器
  `read_dl_error_counters`/`read_dl_error_counters_ap`。
- **设备内省**: `read_device_emulation` (PDI 模拟检测)。
- **寄存器常量**: 完整 ESC 寄存器地址定义 (`reg_al_control` ~
  `reg_watchdog_time_pdi`, DC / FMMU / SM base)。

### `mailbox/` — Mailbox & Configuration

- **SII Parser**: `parse_sii_header`/`parse_sii_preamble`/
  `parse_sii_standard_metadata`/`parse_sii_full_info` 完整解析;
  `parse_sii_general`/`parse_sii_strings`/`parse_sii_fmmu`/
  `parse_sii_fmmu_ex`/`parse_sii_sm`/`parse_sii_pdo`/
  `parse_sii_dc`/`parse_sii_timeouts`/`parse_sii_sync_units`/
  `parse_sii_categories`。聚合模型 `SiiFullInfo`/`SiiData`/
  `SiiPreamble`/`SiiStandardMetadata`。
- **SII 类别框架**: `SiiCategoryEntry` 含 type_code + raw bytes;
  A 类运行时强语义 (General/FMMU/SM/PDO/DC/Timeouts),
  B 类展示工具链 (Strings/DataTypes), C 类厂商扩展保留 Raw。
  `SiiCategoryClass` 含 StandardKnown/StandardUnknown/DeviceSpecific/
  VendorSpecific/ApplicationSpecific; 覆页框架 `SiiOverlayCandidate`。
- **FMMU/SM**: `FmmuConfig`, `SmConfig`, `SlaveMapping`,
  `calculate_slave_mapping`/`calculate_slave_mapping_from_sii`/
  `calculate_fmmu_configs`/`calculate_sm_configs`/
  `apply_pdo_lengths_to_sm_configs`,
  `FmmuDirection` (Outputs/Inputs/MailboxState/DynamicOutputs/DynamicInputs).
- **CoE/SDO**: `MailboxHeader` encode/decode, `SdoTransaction` encode,
  `SdoRequest`/`SdoResponse`/`SdoCommand` 类型,
  `build_sdo_download`/`build_sdo_upload`/完整访问变体/段传输变体,
  `decode_sdo_response`, `sdo_abort_code_description`;
  SDO Info: `SdoInfoObjectDescription`/`SdoInfoEntryDescription`/
  `SdoInfoResponse`。
- **CoE Emergency**: `EmergencyMessage` decode、`CoeService` enum。
- **RMSM**: `Rmsm` 状态机 (Idle/WaitingForResponse/Error),
  `MailboxCounter` (1–7 cycling), `MailboxRepeatState` repeat-request/ack。
- **FoE**: `FoeOpCode`/`FoeResponse`/`FoeErrorCode` 完整编解码，
  `encode_foe_read`/`encode_foe_write`/`encode_foe_data`/`encode_foe_ack`/
  `decode_foe_response`。
- **EoE**: `EoeFrameType`/`EoeResponse`/`EoeResult` 完整编解码，
  `encode_eoe_fragment`/`encode_eoe_get_ip_req`/`encode_eoe_set_ip_req`/
  `decode_eoe_response`。
- **SoE**: `SoeElementFlag`, `encode_soe_read_req`/`encode_soe_write_req`/
  `decode_soe_response`/`SoeResponse`。
- **Mailbox 类型**: `MailboxType` (Err/AoE/EoE/CoE/FoE/SoE/VoE),
  `MailboxConfig::from_sii`。

### `runtime/` — Runtime Orchestrator

- **Scan**: `scan()`/`scan_with_identification_ado`/
  `scan_with_identification_ado_and_station_address_strategy`,
  `ScanReport`/`SlaveReport`, `ScanStationAddressStrategy`
  (PreserveExistingUniqueNonZero/TwinCATCompatible)。
- **Validate**: `validate()`/`validate_configuration()`,
  `ValidateReport`/`ValidateGrade`/`ConfigurationDifference`,
  ENI 配置模型 `ConfigurationModel`/`ConfigurationSlave`/
  `compare_configurations`, `configuration_from_eni_json`/
  `configuration_from_scan`/`configuration_from_expected`/
  `configuration_to_eni_json`。
- **Run**: `run()`/`run_until_fault()`/`run_with_settings()`/
  `run_with_states()`/多种 reporting 变体,
  `RunReport`/`RunPhase`/`RunFault`/`RunLoopSettings`,
  `RunProgress`/`RunProgressSink` trait。
- **Runtime 状态机**: `Runtime::new`/`configure_pdo`/`run_cycle`/
  `run_cycles`/`run_until_fault`, `RuntimeState`
  (Idle/Scanning/Configuring/Running/Stopping/Error), `Telemetry`。
- **DC 集成**: `Runtime::init_dc`, `DcState`
  (Disabled/Measuring/Locked/Drifting), `DcJitterProfiler`/
  `MultiChannelJitterProfiler`, `DriftCompensator`/`DriftCompensationGains`。
- **Diagnosis**: `SlaveDiagnosis`/`DiagnosisSession`,
  `read_slave_diagnosis`/`read_slave_diagnosis_ap`,
  `read_error_register`/`read_diagnosis_counter`,
  `restore_slave_diagnosis_state`/`diagnosis_restore_path`。
- **DiagnosticSurface**: 统一事实层，聚合 state/config/error/runtime/
  monitor/topology 信息, `DiagnosticIssue`/`DiagnosticLevel`/
  `DiagnosticCategory`/`DiagnosticSourceLayer`,
  `diagnostic_surface_from_run`/`diagnostic_surface_from_validate`/
  `diagnostic_surface_from_state_transition`/
  `diagnostic_surface_from_slave_diagnosis`,
  `enrich_surface_with_fingerprint`/`enrich_surface_with_monitors`。
- **Monitor / Verdict**: `MonitorResult`/`Verdict`
  (Pass/Warn/Fail/Block), 内建 monitor:
  `monitor_consecutive_timeouts`/`monitor_cycle_success_rate`/
  `monitor_dc_drift`/`monitor_pdo_configured`/
  `monitor_startup_state`/`monitor_wkc_errors`,
  `MonitorRegistry` (可注册自定义 monitor),
  `VerificationReport` (JSON/Markdown 输出)。
- **Topology**: `TopologyFingerprint`/`TopologyFingerprintMatch`,
  `topology_fingerprint`/`fingerprint_match`,
  `TopologyHealthAnalyzer`/`TopologyHealthReport`/
  `SlaveHealthSnapshot`/`SlaveHealthAccumulator`/`LinkGrade`。
- **Configuration Model**: `ConfigurationModel`/`ConfigurationSlave`/
  `ConfigurationComparisonReport`/`ConfigurationSource`
  (OnlineScan/OfflineConfig/EniImport),
  `ConfigurationProcessDataSummary`/`ConfigurationMailboxProtocols`,
  `SlavePresence` (Mandatory/Optional) for Hot Connect tolerance。
- **ESI/ENI JSON**: `EsiJsonDocument`/`EsiJsonDevice`/`EsiJsonModule`/
  `EsiJsonPdo` — XML ESI 转 JSON 中间模型,
  `EsiOfflineSiiReport` 离线 SII 分析,
  `startup_preparation_from_esi_json`/`parse_esi_json_document`。
- **Startup Preparation**: `SlaveStartupPreparation`/
  `RunStartupPreparation`/`StartupMailboxCommand`/
  `StationStartupMailboxPlan`/`StartupCommandTransition`,
  `build_run_startup_preparation`/`prepare_slave_startup`/
  `refine_startup_preparation_in_preop`/
  `apply_startup_mailbox_commands`。
- **EoE Runtime**: `EoeSwitch` (多从站 EoE 交换机),
  `EoeRelay`/`EoeRelayStats`, `QueueEndpoint`,
  `bridge_eoe_cycle`/`eoe_max_fragment_size`。
- **Process Image Slicing**: `ProcessImageSlice`,
  `partition_by_slave`/`slice_from_mapping`/
  `read_slice_inputs`/`write_slice_outputs`/
  `slice_inputs_view`/`write_slice_outputs_inplace`。
- **Scheduler**: `RunMode` (FreeRun/DcSync), `TaskSchedule`/
  `TaskDescriptor`, `build_task_schedule`/`tasks_due_at_cycle`,
  `MultiRateAnalysis`/`analyze_multi_rate`/`validate_multi_rate`。
- **PDO Auto-Tune**: `PdoAutoTuner`/`AutoTuneConfig`/
  `AutoTuneResult`/`ProbeResult`/`SyncOffsetRecommendation`。
- **Cycle Performance**: `CyclePerfAnalyzer`/`CyclePerfStats`/
  `JitterHistogram`/`PerfTrend`, 通信质量评分
  `CommQualityScorer`/`QualityScore`/`QualityGrade`/`QualityTrend`。
- **HIL / Co-Sim**: `CoSimAdapter` trait / `LoopbackCoSimAdapter`,
  `HilSession`/`HilSessionSummary`/`HilCycleHook`/`SimTime`,
  `CycleHook` trait (on_pre_cycle/on_post_cycle/on_fault),
  `ExternalProcessBridge`/`BridgeTransport`
  (UnixSocket/NamedPipe/SharedMemory)。
- **Timebase**: `Timebase` trait / `VirtualTimebase`,
  `TimebaseSync`/`ClockDomain` (Mcu/Linux/Fpga/Virtual),
  `DomainTimestamp`/`CycleTimingReport`。
- **Master OD**: `MasterObjectDictionary`/`MasterOdEntry`,
  `build_master_od` — 主站对象字典模型。

### `cmd/main/` — CLI Entry Point

CLI 子命令 (`moon run cmd/main <command> -- --backend <backend> ...`):

| 命令 | 功能 | 输出 |
|------|------|------|
| `list-if` | 网络接口枚举 | JSON/text |
| `scan` | 从站发现与身份读取 | ScanReport |
| `validate` | 在线/离线配置比对 | ValidateReport |
| `run` | 完整生命周期: scan→validate→ESM→PDO cycling→shutdown | RunReport |
| `read-sii` | SII EEPROM 读取与解析 | SII 完整信息 |
| `state` | 从站 ESM 状态迁移 (广播/定点) | StateTransitionReport |
| `diagnosis` | 从站诊断 (AL Status, Error Register, DL Counters) | DiagnosticSurface |
| `od` | 从站对象字典浏览 (SDO Info) | OdBrowseReport |

支持后端选择: `mock` / `native` / `native-windows-npcap` / `native-linux-raw`。
支持输出格式: `--json` / `--progress-ndjson` / 默认文本。

### `cmd/eni_json/` — ENI XML→JSON Bridge

ENI (EtherCAT Network Information) XML 描述文件到 JSON 的转换工具，
基于 Milky2018/xml 库解析 ETG.2100 标准 XML，生成
`EsiJsonDocument` 供离线配置、ESI 投影和启动准备使用。

### `plugin/extism/` — Extism WASM Plugin Adapter

- **Host Capability Contract**: `HostCapabilityContract` 描述宿主需提供的
  HAL 能力 (nic_open/send/recv/close, clock, file)。
- **Plugin Entrypoints**: `scan_entry`/`validate_entry`/`run_entry` —
  封装库 API 为 WASM 插件导出入口。
- **Envelope**: `PluginRequest`/`PluginResponse` — 稳定的 JSON
  请求/响应信封，含 version/command/error_code 映射。
- **当前状态**: 边界设计与占位实现完成，实际宿主绑定待后续接入。

### `fixtures/` — Test Fixtures

包含合成 SII EEPROM 二进制数据和预构造的测试用帧数据，
供 mailbox/protocol/runtime 各包的单元测试和快照测试使用。

## Data Flow

### Startup (scan → run)

```
                    ┌─────────┐
  scan()  ─────────►│ NIC     │──► BRD count_slaves
                    │ (Mock/  │──► APWR assign_address
                    │  Native/│──► FPRD read identity
                    │  ZC)    │──► FPRD read station_alias
                    └────┬────┘
                         │
  validate() ◄───────────┘ ScanReport
       │
       ▼ ValidateReport (grade: Pass/Warn/Block)
       │
  prepare_slave_startup() ────────► SII full read → SlaveMapping
       │                             SII DC clock → dc_cycle_period
       │                             ESI init cmds → StartupMailboxCommand
       ▼
  transition_through(PreOp) ──────► Write mailbox/PD SM/FMMU mapping
       │                             Apply startup mailbox commands
       ▼
  transition_through(SafeOp) ─────► DC configure_linear + configure_sync0
       │                             Static sync pre-compensation
       ▼
  transition_through(Op) ─────────► apply_op_only_policy
       │                             (with process data pump if needed)
       ▼
  run_cycles() ◄──────────────────► LRW pdo_exchange (cyclic)
       │                             Monitor checks each cycle
       │                             Emergency polling (if configured)
       ▼
  broadcast_state(Init) ──────────► Shutdown (DC deactivate first)
       │
       ▼ RunReport
```

### PDO Cycle (hot path)

```
  Runtime::run_cycle()
    └─► pdo_exchange(nic, ctx, timeout)          [Bytes path]
        pdo_exchange_zero_copy(nic, ctx, timeout) [ZeroCopy path]
          ├─ encode LRW frame (into pre-allocated buffer)
          ├─ nic.send() / nic.submit()
          ├─ nic.recv()
          ├─ decode response (WKC + data)
          └─ return PdoExchangeResult
    └─► update telemetry (cycles, tx, rx, wkc_errors, timeouts)
    └─► check consecutive errors → trigger recovery
    └─► CycleHook::on_post_cycle (if configured)
    └─► Emergency polling (if stations configured)
```

### Diagnosis Flow

```
  diagnosis(station)
    ├─ read_al_status_snapshot(station)
    │    → EsmState + error_flag + status_code
    ├─ read_error_register(station) via SDO 0x1001:00
    ├─ read_diagnosis_counter(station) via SDO 0x10F3:00
    ├─ read_dl_error_counters(station)
    │    → rx_error, fwd_error, ecat_error, pdi_error, lost_link per port
    └─► SlaveDiagnosis → DiagnosticSurface
         → DiagnosticIssue[] + overall_level + monitor verdicts
```

### HIL / Co-Sim Flow

```
  HilSession::new(cycle_period_ns, task_schedule)
    └─► HilCycleHook[CoSimAdapter]
          ├─ on_pre_cycle: adapter.write_outputs → adapter.step(sim_time)
          ├─   check SimStepResult (Ok/Terminated/Error)
          ├─ on_post_cycle: adapter.read_inputs
          └─ on_fault: adapter.shutdown / directive
    └─► ExternalProcessBridge (Unix/NamedPipe/SharedMemory transport)
          ├─ encode_step_request / decode_step_response
          └─ avg_latency_ns tracking
```

## Testing Strategy

All tests run via `moon test` with zero external dependencies (Native 实机测试除外)。

| Category | Approach | Package |
|----------|----------|---------|
| Frame codec | Encode → decode roundtrip, zero-copy variants | protocol/ |
| PDU pipeline | Multi-PDU build + parse, index lookup | protocol/ |
| Discovery | Mock loopback + BRD/APWR, station address strategies | protocol/ |
| ESM | Transition path validation, timeout policy, observe/snapshot | protocol/ |
| DC | Configure/latch/sync window, drift compensation | protocol/ |
| Mailbox transport | Send/recv/poll/exchange, RMSM retry, AP/FP variants | protocol/ |
| SDO | Upload/download/complete-access/retry/abort/segment | protocol/ |
| FoE | File download/upload, error handling | protocol/ |
| SII/ESI | SII full read, preamble/category/overlay parsing | mailbox/ |
| FMMU/SM | Mapping from ESI data, SM config calculation | mailbox/ |
| CoE/SDO codec | Encode/decode/abort detection, SDO Info | mailbox/ |
| EoE/SoE/Emergency | Encode/decode roundtrip | mailbox/ |
| RMSM | State machine, retry boundary, counter cycling | mailbox/ |
| Runtime | State machine, telemetry, recovery, DC init | runtime/ |
| Scan/Validate | Constructed ScanReport, ConfigurationModel compare | runtime/ |
| Run | End-to-end with mock NIC, until-fault, reporting | runtime/ |
| Diagnosis | DiagnosticSurface construction, issue grading | runtime/ |
| Monitor/Verdict | Built-in monitors, registry, verdict aggregation | runtime/ |
| Topology | Fingerprint hash/match, health analysis | runtime/ |
| Configuration | ENI import/export, online/offline comparison | runtime/ |
| Startup | SlaveStartupPreparation, ESI JSON parsing | runtime/ |
| HIL/Co-Sim | LoopbackCoSimAdapter, HilSession, task scheduling | runtime/ |
| Cycle Perf | Jitter histogram, percentile, trending | runtime/ |
| EoE Runtime | EoeSwitch, relay, fragment reassembly | runtime/ |
| Virtual Bus | Multi-slave scenarios, fault injection | hal/mock/ |
| Fault Injection | Drop/delay/corrupt/WKC mismatch injection | hal/mock/ |
| Replay | Frame recording → deterministic replay | hal/mock/ |
| Scenario | Scripted protocol deviation scenarios | hal/mock/ |
| Native FFI | Error mapping, config objects, handle lifecycle | hal/native/ |
| Native smoke | Windows Npcap / Linux Raw Socket 实机回归 | hal/native/ |
| Extism | Envelope encode/decode, host contract validation | plugin/extism/ |

## Maturity Assessment

| Package | 成熟度 | 说明 |
|---------|--------|------|
| hal/ | **L3 Production** | Nic/ZeroCopyNic/Clock/FileAccess traits 稳定; FramePool 零拷贝架构完成; EcError 17 变体覆盖完整 |
| hal/mock/ | **L4 Verification** | 虚拟总线/虚拟从站/故障注入/录制回放/模糊测试/场景执行器全部就绪 |
| hal/native/ | **L3 Production** | Windows Npcap + Linux Raw Socket 实机闭环; 零拷贝后端; FFI 安全模型文档化 |
| hal/mcu/ | **L1 Foundation** | MCU HAL 骨架和事件桥接，待 DMA 描述符环接入 |
| protocol/ | **L3 Production** | Frame/PDU/ESM/DC/PDO 协议核心完整; 零拷贝编解码; mailbox transport + SDO/FoE/EEPROM 事务层完整; SM/FMMU/DL 操作 |
| mailbox/ | **L3 Production** | SII 完整类别深读 (A/B/C 分层); CoE/SDO/FoE/EoE/SoE 编解码完整; RMSM 状态机; FMMU/SM 映射推导 |
| runtime/ | **L3 Production** | scan/validate/run 完整生命周期; DC 集成; diagnosis + DiagnosticSurface 统一事实层; monitor/verdict; topology fingerprint/health; configuration model/ENI; startup preparation; EoE switch/relay; HIL/co-sim 框架; cycle perf; master OD |
| cmd/main/ | **L3 Production** | 8 个 CLI 子命令: list-if/scan/validate/run/read-sii/state/diagnosis/od; JSON + text + NDJSON 输出; 多后端支持 |
| cmd/eni_json/ | **L2 Core** | ENI XML→JSON 桥接功能 |
| plugin/extism/ | **L2 Core** | Host contract 定义 + envelope 协议 + 占位入口完成; 实际宿主绑定待接入 |
| fixtures/ | **L3 Production** | 合成 SII 二进制 + 测试帧数据 |

### 成熟度等级定义

- **L1 Foundation**: 骨架/接口定义，尚未形成可运行实现
- **L2 Core**: 核心功能已实现，但缺少完整测试或实机验证
- **L3 Production**: 功能完整、测试覆盖良好、已有实机验证证据
- **L4 Verification**: 具备验证/回放/注入能力，可作为验证基础设施使用

Test fixtures live in `fixtures/fixtures.mbt` and provide
`minimal_nop_frame()`, `sample_ek1100_identity()`,
`sample_sii_eeprom()`, and `sample_sii_eeprom_with_pdo()`.

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `EcError::RecvTimeout` | NIC recv timed out | Check cable / increase `timeout_us` |
| `EcError::UnexpectedWkc` | Slave not responding | Verify slave count and ESM state |
| `EcError::EsmTransitionFailed` | State change rejected | Read AL status code for detail |
| `EcError::SdoAbort` | SDO request refused | Check abort code per ETG.1000.6 |
| `ConfigMismatch` | Validate found wrong slave | Re-scan or update SlaveConfig |

## Extending MoonECAT

### Adding a new NIC backend

1. Implement the `Nic` trait in a new package (e.g., `hal/linux/`).
2. Provide `open_`, `send`, `recv`, `close` methods.
3. Import your package in `runtime/moon.pkg`.

### Adding a new CoE service

1. Extend `CoeService` enum in `mailbox/coe.mbt`.
2. Add encode/decode logic in `mailbox/coe_engine.mbt`.
3. Add tests in `mailbox/mailbox_test.mbt`.

### Extism / WASM Host Integration

The library compiles to WASM-GC. To integrate with Extism:
- Export `scan`, `validate`, `run` as host-callable functions.
- Pass NIC operations via host function imports.
- This boundary is designed but not yet implemented.

## Build & Run

```bash
moon check          # Type-check all packages
moon test           # Run all tests
moon test --update  # Update snapshot tests
moon fmt            # Format all MoonBit source
moon info           # Regenerate .mbti interface files
moon run cmd/main   # Run the CLI
```
