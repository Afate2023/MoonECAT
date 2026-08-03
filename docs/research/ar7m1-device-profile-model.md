# AR7M1 MoonECAT DeviceProfile 模型研究

## 范围与证据边界

本任务只在 MoonECAT owner 内建立 reusable ESI typed library、closed-world 多型号 catalog、candidate→preview→activate 和 exact `ProviderDeviceInstanceBinding`。它不扫描目录、不读取 ProjectDocument 任意路径、不自动选择最高 revision、不连接设备、不打开 NIC，也不把 ESI 声明提升为 observed identity、vendor-authenticated 或 live evidence。

用户提供资产 `C:\Users\afate\Downloads\蓝海华腾EtherCAT上位机监控软件\ESI\VT_EX_CA20_20250705.xml` 的只读 intake 为 427143 bytes，SHA-256 `B43DB4729C60F4DE54B4C769D4D0E308B0884FAE66D85BF45ECCAE4A3A417FC2`。文件声明 vendor `#x556666`、product `40200` (`0x00009D08`)、revision `2025070500` (`0x78B41FA4`)、type/name `EX_CA20`、profile `402`，未声明 `SerialNo`。这些均是 ESI declared facts，不是当前物理从站事实。

## Existing Implementation Survey

### 当前 MoonECAT owner

- `cmd/eni_json/esi_projection.mbt` 已完整实现 streaming XML→`runtime.EsiJsonDocument` projection，覆盖 device/module、SM、PDO、DC、mailbox、EEPROM 与 init command；但函数仍是 executable package 私有实现，runtime/provider 无法作为 typed library 复用。
- `runtime/esi_json.mbt` 已公开 `EsiJsonDocument`、canonical-like JSON stringify/parse 与 offline SII projection；当前 `EsiJsonDevice.serial` 是必填 `UInt`，converter 用 `0` 表达 XML 未声明 serial，无法区分 model wildcard 与确切 unit serial。
- `cmd/eni_json/main_wbtest.mbt` 已有多组 ESI XML fixtures；CLI 只需要 `convert_esi_xml_to_json_string`，可在 converter 提升后保留为薄 adapter。
- MoonECAT root package 当前只公开 version，没有 device-profile facade；没有 closed-world catalog、candidate/preview/activation、profile digest 或 instance binding。
- `src/EtherCAT.net-callflow-analysis.md` 记录参考实现会扫描目录、缓存并在 exact revision 缺失时回退同 product 的最高 revision；该行为适合工程工具便利性，但与本任务 exact revision、closed-world activation 裁决冲突，明确不采用。

### ESI schema 与 identity 语义

- `References/EtherCATInfo.xsd`/`EtherCATBase.xsd` 与 ETG.2000 本地规范把 `Vendor/Id`、`Device/Type ProductCode/RevisionNo` 和 optional `SerialNo` 作为 ESI 描述字段；一个 source 可描述多个 device/revision，不能把一个文件等同一个物理实例。
- 现有 `EsiJsonDocument.devices` 已天然支持一个 source 内多个 device，`modules` 是 source-shared projection。每个 selected profile 因而应固定 exact source asset、vendor/product/revision 与 per-device canonical JSON，而不是按 display name 或数组 index 运行时选择。
- ESI source digest 必须针对输入 bytes 计算后与 composition 声明值比较；先 decode 为 String 再 hash 会丢失 BOM/原始 byte identity。

## Abstraction And Interface Proposal

### 1. Typed converter 与 immutable candidate

- 把现有 XML projection 移入 `device_profile` library，公开 `esi_json_document_from_xml`/`convert_esi_xml_to_json_string`；`cmd/eni_json` 仅委托 library。
- `DeviceProfileCandidate::from_esi_xml` 接收 bounded embedded bytes、asset ID 与 declared SHA-256，先校验 exact bytes digest，再 UTF-8 decode/parse；不接受路径、上传 handle 或 dynamic provider。
- candidate 为 document 中每个 device 生成 private-field `DeviceProfile`：source asset/digest、vendor/product/revision、optional serial、display facts、per-device canonical JSON 与 typed profile digest。typed document accessor 每次重新 parse canonical JSON，避免暴露可变数组。

### 2. Preview、activation 与 closed-world catalog

- `DeviceProfilePreview::new(candidates)` defensive copy 并拒绝 duplicate asset、duplicate exact profile identity；canonical order/digest 与注册顺序无关。
- `DeviceProfileSelection` 必须同时给出 exact asset ID、vendor/product/revision 和 expected profile digest。`DeviceProfileCatalog::activate(preview, selections)` 只保留选中 closure，拒绝 missing/duplicate/mismatched selection，不按名称、product-only 或 highest revision fallback。
- activated catalog digest 只由 selected profiles 产生；额外未选合法 candidate 不影响 activation、resolution 或 digest。runtime 只能从 activated catalog `resolve_exact` 得到 `ActivatedDeviceProfile`，不能消费 candidate/preview。

### 3. Profile 与实例绑定分离

- `DeviceProfile` 只表达可复用 model/revision 声明；optional serial 为 `None` 时不假装 unit identity。
- `ProviderDeviceInstanceBinding` 由 activated profile 构造，固定 provider-neutral device node ID、protocol role binding ID、exact profile pin、physical position 与 typed `MoonEcatDeviceConfig`，并有独立 canonical digest。
- binding 不含 live observed identity；AR7M2 才把 actual ordered topology/serial 与该 expected profile 比较。ProjectDocument 仍不保存 EtherCAT 字段，root composition migration 留给 AR7M3。

## 验证计划

- converter 旧 CLI fixtures 保持通过；新增 multi-device/multi-revision、optional serial、source digest mismatch、bad UTF-8/XML、duplicate asset/profile negative tests。
- preview/catalog 对声明顺序无关；exact selection、missing/duplicate/digest mismatch、同 product 不同 revision、额外未选 candidate 不影响 activated digest。
- binding 固定 exact activated profile/placement/config，defensive typed document 与数组 projection；candidate/preview 不提供 runtime resolve。
- package/root facade/public `.mbti`、external consumer、all-target tests、reference constraint、README/architecture/TASKS backfill、fresh-eyes audit 与 single nested-repo commit。

## 实现结果

- 原 `cmd/eni_json/esi_projection.mbt` 的 ESI projection 已迁入 reusable
  `device_profile/esi_projection.mbt`；CLI 仅保留调用 library 的薄函数。
- `DeviceProfileCandidate` 在任何 decode 前校验最大 4 MiB 与原始 bytes 的
  lowercase SHA-256；`DeviceProfilePreview` 和 `DeviceProfileCatalog` 分别固定
  import preview 与 selected-only activation closure。
- exact selection 固定 asset/vendor/product/revision/profile digest；没有目录、
  文件路径、display-name、product-only 或 highest-revision resolution API。
- `EsiJsonDevice.serial` 已改为 `UInt?`。派生 JSON 会省略 `None`，因此 parser
  同时接受 missing/null optional field 与旧 numeric serial；SII projection 仅在
  需要固定 32-bit header 的边界把缺失 serial 降为 `0`。
- `ProviderDeviceInstanceBinding` 只包含 expected profile pin、工程 node/role、
  physical position 与 typed MoonECAT config；observed topology/identity 留给
  AR7M2。
- MoonECAT root facade 和 `compat/device_profile_consumer` 证明外部消费者无需
  导入 child package；`pkg.generated.mbti` 与 `runtime/pkg.generated.mbti` 记录
  新公开面和 optional serial 变更。

## Audit And Validation

- fresh-eyes audit：PASS；Critical/High/Medium/Low 均为 0。审查覆盖原始 bytes
  digest、bounded intake、duplicate/ambiguous profile、selected-only digest、
  defensive array/document、exact resolution、optional serial、无 path/NIC/live
  API 以及 public facade。
- 审计过程中发现并修复 1 个兼容性缺陷：MoonBit `ToJson` 会省略 `None`
  字段，而旧 ESI JSON parser 要求 optional key 必须存在。现在 missing/null
  均解为 `None`，旧 numeric serial 仍可解析。
- 用户 ESI 只读复核：427143 bytes；SHA-256
  `B43DB4729C60F4DE54B4C769D4D0E308B0884FAE66D85BF45ECCAE4A3A417FC2`。
  测试 fixture 固定其 vendor/product/revision 与 absent serial 声明，不读取
  任意运行时路径。
- `moon check --target all`：PASS；现有 workspace 52 warnings、0 errors。
- `moon test --target all`：wasm 3002/3002、wasm-gc 3002/3002、JS
  3003/3003、native 3148/3148。
- `moon test device_profile --target all`：四目标各 6/6；
  `moon test cmd/eni_json --target all`：四目标各 10/10；external consumer
  四目标各 1/1。
- `moon fmt`、`moon info`、`git diff --check` 与 no-path/no-live source scan：PASS。
