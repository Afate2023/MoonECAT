# AR7M2 MoonECAT Stack-Owned Provider Identity 研究

## 范围与证据边界

本任务在 `MoonECAT/isochronon_provider` 内实现 typed
`inspect-bus-identity` commissioning operation。它消费 AR7M1 的 exact
`ProviderDeviceInstanceBinding`，通过 Lockwire `LinkSession` 字节边界执行有界
EtherCAT identity metadata 读取，并输出 ordered topology、identity strength、typed
effect witness、local TX echo relation 和 provider-owned assurance normalization。

本任务不打开 NIC、不选择 ProjectDocument 路径、不执行完整 scan、PDO、mailbox、
DC 或 cyclic runner，也不把 simulation/replay/fault/native-contract fixture 提升为
live evidence 或 accepted claim。真实接口、从站、pcap/tshark 和独立 verifier 仍由
AR7V/AR7B3 承担。

## Existing Implementation Survey

### MoonECAT 协议实现

- `protocol/transact.mbt` 的 `transact` 会调用 `nic.recv(timeout)`；调用者传入的是
  relative `@hal.Duration`，每次忽略非 EtherCAT frame 后都会重新使用完整 timeout，
  不能证明 caller-owned single absolute deadline。
- `protocol/pipeline.mbt` 的 `FrameBuilder::build` 固定 source MAC 为
  `02:00:00:00:00:01`。AR7B1 已从 exact resolved Npcap binding 重新观察 current
  MAC，因此 provider 不能继续调用该默认 builder，也不允许 source-MAC override。
- `protocol/discovery.mbt` 的 `count_slaves` 只返回 BRD working counter；它不读取
  identity、比较 ordered topology 或保存 actual serial，不能作为
  `inspect-bus-identity` result。
- `protocol/eeprom.mbt` 已实现 SII controller ownership、busy/NACK poll 与 AP/FP
  read，但 retry/poll 常量私有且每个 register transaction 继续使用 relative
  timeout。`read_sii_bytes_ap` 会先读至少 128 bytes 并可能继续读取完整 EEPROM，超出
  本 operation 仅需 SII header words 8..15 的 16-byte identity metadata 范围。
- `EcFrame`/`Pdu` codec 与 APRD/APWR/BRD address helpers 已公开，足以由 provider
  构造 custom source-MAC 单-PDU frame，并以 MoonECAT decoder 作为 normative
  protocol decoder复用。

### Lockwire 与 AR7 contract

- `lockwire/runtime` 的 `LinkSession::poll_rx(deadline)` 已使用
  `@clock.DomainInstant` 并验证 clock domain；`RxObservation` 保存 payload、长度、
  timestamp、direction、backend sequence 和 buffer provenance。provider adapter
  应直接保持这个 absolute deadline，不再降为 MoonECAT relative timeout。
- `LinkSession` 记录所有 submitted/accepted/RX bytes，并不含 EtherCAT 过滤。这与
  “Lockwire 只负责怎么跑”边界一致；exact own-TX echo 的识别和
  `ignored-local-tx-echo` relation 必须留在 MoonECAT provider。
- AR7B2 已提供 provider-owned `ProviderCaptureFilterAsset` 与 bounded pcapng policy。
  MoonECAT 只需固定 EtherCAT/non-VLAN BPF asset；one-interface、262144 snaplen、
  10 seconds、4096 packets、16 MiB 与 zero-drop gate 继续由 Lockwire capture policy
  执行。
- 根 `provider_moonecat` 仍返回 `CommissioningActionReceipt.facts` string，并通过旧
  `LinkSessionNic` 重置 timeout。本任务只建立新的 nested public seam；删除旧包和
  composition/Workbench consumer migration 统一留给 AR7M3。

## Abstraction And Interface Proposal

### 1. Explicit context、policy 与 transport port

- `EthernetFrameContext` 只接受 resolved binding digest、重新观察到的 6-byte
  current MAC 和 exact clock domain；API 不提供 source override。
- `InspectBusIdentityPolicy` 显式固定 max slaves、max wire transactions、retry-safe transport
  retry、SII status polls、SII NACK retry、ignored observations 和 retry backoff。
  所有值进入 canonical policy digest 和 operation trace。
- `IdentityLinkPort` 是 provider-owned byte adapter。它的 `poll` 参数始终是调用者
  原始 absolute deadline；`from_link_session` 只做 TX lease、RX
  observation/release 和错误归一化，不解析 EtherCAT。fixture source 只有
  simulation/replay/fault/native-contract/runtime-unverified，全部固定
  `live_verified=false`。

### 2. Bounded single-outstanding identity engine

- 每个 request 只含一个 PDU；engine 只有在前一个 response、timeout 或明确
  retry-safe transport failure 结束后才可提交下一个 request。transport retry 仍
  复用同一 deadline，backoff 通过显式 `sleep_until` port 执行，不存在
  whole-action retry。只有 port 明确报告 retry-safe、且确认旧 outstanding 已终止的
  fixture failure 才重试；live `LinkSession` 的 ambiguous submit/poll failure 一律
  fail closed。
- 首先用一个 BRD `0x0000` working counter取得 actual count。随后按 physical
  position 使用 APRD/APWR，只临时取得 SII controller ownership，并读取 header
  words 8..15：vendor/product/revision/serial 共 16 bytes；每个 position 结束必须
  尝试恢复 PDI ownership。
- SII ownership active 期间，engine 从 max transaction budget 中保留
  `max_transport_retries + 1` 个 cleanup slot；普通 poll/read 不得消耗该保留量，
  因此 budget exhaustion 仍可尝试恢复 PDI ownership。
- request 在 provider 内补齐到不含 FCS 的 60-byte Ethernet minimum，使 Npcap
  观察到的 local transmit 可以与 accepted request 做 exact bytes 比较。exact echo
  被 provider 忽略并记录 `ignored-local-tx-echo`；其他 response 必须通过 MoonECAT
  frame/PDU command、index、address、length 和 WKC 校验。

### 3. Typed result、effects 与 topology verdict

- expected topology 是按 `physical_position == array index` 排列的 exact binding
  closure，并拒绝 duplicate node/role/position。
- observed record 始终保存 actual vendor/product/revision/serial、raw 16-byte identity
  digest 和 selected profile match。serial pin 为 `None` 时匹配任意 actual serial，
  但 actual serial 不得丢失。
- topology issue 明确区分 extra、missing、reordered、model/revision mismatch 和
  serial mismatch；只有完整 ordered match 才通过。全部 profile 固定 serial 时强度
  为 `UnitIdentity`，否则为 `ModelAndTopology`；失败为 `NoIdentityAssurance`。
- effect witness 区分 bus population probe、identity metadata read 和 volatile SII
  controller mutation，truth point 只到 `tx-accepted-by-backend`，不声称 on-wire、
  device-applied 或 live verified。

### 4. Assurance decoder 与 capture asset

- `isochronon_provider/assurance` 只把 private-field typed result 归一化为 exact
  `moonecat.inspect-bus-identity` facts。它不自行创建 `Passed`
  `AssuranceAssessment`、不签名、不签发 claim；runtime/capture/external oracle
  provenance 不完整时始终标记为不可签发。
- provider 导出 immutable EtherCAT/non-VLAN `ProviderCaptureFilterAsset`，BPF text
  不进入 ProjectDocument 或 Lockwire generic config。

## 验证计划

- sim/replay/fault/native-contract fixtures 共用 raw frame responder；验证 source MAC、
  single outstanding、所有 poll 使用同一 deadline、显式 retry/backoff、exact echo
  relation 和 no-live provenance。
- topology 正例覆盖 optional serial 与 pinned serial；负例覆盖 extra、missing、
  reordered、identity/serial mismatch、duplicate/non-contiguous expected binding。
- source-level/request-log gate 证明只访问 BRD type register 与 SII
  `0x0500/0x0502/0x0508`、word 8..15，不出现完整 EEPROM/PDO/mailbox/DC operation。
- 覆盖 defensive arrays/bytes、canonical digest、capture filter identity、assurance
  decoder、public `.mbti` 与外部 consumer；完成 all-target check/test、format、info、
  reference constraint、README/TASKS backfill、fresh-eyes audit 和单一 nested commit。

## 实现结果

- 新增 `isochronon_provider` public package。`EthernetFrameContext` 固定 exact
  resolved binding digest、runtime current MAC 与 clock domain；没有 source-MAC
  override。`IdentityLinkPort::from_link_session` 直接保持 `DomainInstant` deadline，
  不再转换成旧 `@hal.Duration`。
- `inspect_bus_identity` 每帧只有一个 PDU，并补齐到不含 FCS 的 60 bytes。首个 BRD
  只取 bus population WKC；随后每个 position 只访问 SII config/control/data，读取
  header words 8..15 的 vendor/product/revision/actual serial。所有 request/response
  使用 MoonECAT codec，未调用完整 scan、`read_sii_bytes_ap`、PDO、mailbox 或 DC。
- policy 把 wire transaction、retry-safe transport retry、status poll、NACK retry、
  ignored observation 和 backoff 全部显式固定并进入 digest/trace。live
  `LinkSession` ambiguous failure 不可重试；SII active 时预留 cleanup requests，失败
  路径仍尝试恢复 PDI ownership。
- result 以 private fields、defensive projections 和 length-framed canonical bytes
  固定 ordered observations、actual serial、profile verdict、extra/missing/reordered/
  identity issues、identity strength、effects、echo relations、trace、deadline 和全部
  input digests。effect truth point 只到 `tx-accepted-by-backend`。
- 新增 `isochronon_provider/assurance`，仅归一化
  `moonecat.inspect-bus-identity` protocol facts；它始终要求外部 evidence，不能创建
  passed assessment 或 claim。provider-owned capture filter 固定为
  `ether proto 0x88a4 and not vlan`。
- `isochronon_provider/fixtures` 覆盖 simulation/replay/fault/native-contract；四种
  source 与 `RuntimeUnverified` 均固定 `live_verified=false`。外部 consumer 直接导入
  provider/assurance public packages，未依赖 root compatibility facade。

## Audit And Validation

- fresh-eyes audit/review：最终 `PASS`，Critical/High/Medium/Low 均为 0。审查覆盖
  source-MAC、single outstanding、absolute deadline、retry safety、SII cleanup、完整
  canonical digest、defensive projection、独立 bytes decoder、topology semantics、
  protocol/Lockwire owner boundary 和 no-live claim matrix。
- 审查中修复 3 类问题：ambiguous live poll failure 不再进入 retry；SII ownership
  active 后为 PDI restore 保留 `max_transport_retries + 1` 个 transaction；assurance
  decoder 从仅消费进程内对象改为对 exact digest-pinned canonical bytes 做 bounded、
  section-counted、完整消费解析，且校验 passing observation/effect/echo/trace shape。
- `moon check --target all`：PASS；workspace 既有 52 warnings、0 errors。
- `moon test --target all`：wasm 3011/3011、wasm-gc 3011/3011、JS
  3012/3012、native 3157/3157。
- `moon test MoonECAT/isochronon_provider --target all`：四目标各 8/8；
  `moon test MoonECAT/isochronon_provider/assurance --target all`：四目标各 1/1。
- 两个 external consumer `moon test . --target all`：device-profile 与 provider
  consumer 均四目标各 1/1。`moon fmt --check`、`moon info`、`git diff --check`、
  no-full-SII/no-PDO/no-mailbox/no-DC/no-path/no-NIC source scan 均通过。
- 本任务没有打开“以太网 2”或任何 NIC，没有读取真实从站，没有产生 pcap/tshark、
  timing、connected/runtime verified 或 accepted claim；真实证据仍由 AR7V 保持
  Blocked，root composition migration 仍由 AR7M3 承担。
