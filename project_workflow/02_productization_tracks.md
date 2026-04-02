# MoonECAT 产品化拆解

本文件由原 AI 任务清单拆分整理而来，对应原 0.3 到 0.7 节。

> **成熟度定位**：产品化拆解覆盖 **L3 Product Surface** 与部分 **L4 Verification & Hardening**，横跨主线 A（Native Runtime）与主线 B（验证运行时）。

| 章节 | 领域 | L 级 | 主线 | 完成度 |
|---|---|:---:|:---:|:---:|
| §0.3 | OD 浏览产品化 | L3 | A | 6/6 ✅ |
| §0.4 | 配置工具 / ENI | L3 | A | 6/6 ✅ |
| §0.5 | 主站 OD / 统一诊断 | L3 | A | 6/6 ✅ |
| §0.6 | 拓扑 / Hot Connect | L3-L4 | B | 4/5 ⚠️ |
| §0.7 | Native / Extism 收口 | L4 | A+C | 3/7 ⚠️ |

## 0.3 对象字典浏览产品化拆解 【L3 · 主线 A】

> 目标不是重复实现 CoE 事务，而是把已经落仓的 `SDO Info / Complete Access / Segmented Transfer` 能力组织成稳定的 CLI / 配置工具表面。

最新回填：已在 [cmd/main/main.mbt](../cmd/main/main.mbt) 新增 Native `od` 命令，并在 [runtime/diagnosis.mbt](../runtime/diagnosis.mbt) 抽出通用 mailbox prepare/restore helper；代码提交：`fcc384e` `feat(cli): add object dictionary browsing command`。随后又补齐 `od` 失败路径的结构化分类与文本/JSON 输出，代码提交：`f8f75bd` `feat(cli): classify od browse failures`。2026-03-16 再次在 `\Device\NPF_{21208AED-855D-48E0-B0AF-A5B92C93EEDC}`（Realtek USB GbE）上对真实从站执行 `od --station 4097 --json`，成功返回 `OD List` 索引数组，完成最小实机 smoke。

- [x] 定义对象字典浏览统一结果对象：覆盖 `OD List`、`OD Description`、`OE Description` 与来源从站信息；当前以 `OdBrowseReport` 承载，错误分类后续继续细化。
- [x] 设计 CLI 入口：至少包含“列出对象索引”“查看对象描述”“查看子项描述”三类只读查询。
- [x] 统一输出模型：文本输出服务人工诊断，JSON 输出服务后续配置工具/网页工作台直接消费。
- [x] 明确与 ENI / online scan 的关联：浏览入口复用当前 scan 结果与 `--station` 定位，不再引入第二套寻址模型。
- [x] 明确失败语义：当前已把 `MailboxTimeout/RecvTimeout/LinkDown` 归入 `transport-failure`，把 `MailboxProtocol/SdoAbort/UnexpectedWkc` 归入 `protocol-failure`，把 `NotSupported` 归入 `unsupported`，并保留 abort/detail 字段。
- [x] 建立最小验证：已补 CLI white-box 解析/输出/错误分类测试，并于 2026-03-16 在真实从站上复跑 Native `od --station 4097 --json`，确认 `OD List` 路径可用。

对象字典浏览产品化验收标准：

- [x] CLI 能稳定输出 `OD List`、单个对象描述、单个子项描述。
- [x] JSON 结果对象可被配置工具直接复用，不需要再次解析文本。
- [x] 错误输出能区分“协议失败”“传输失败”“从站不支持”三类情形。
- [x] 不修改既有库层 CoE 事务 public API 的语义，仅在产品面增加封装与结果组织。

## 0.4 配置工具 / ENI 主线拆解 【L3 · 主线 A】

> 目标是把 online scan、离线 ENI、启动比对和差异报告纳入同一配置对象模型，而不是维护两套配置来源、两套校验语义。

最新回填：已新增 [runtime/configuration.mbt](../runtime/configuration.mbt)，引入 `ConfigurationModel` / `ConfigurationSlave` / `ConfigurationComparisonReport` 统一配置对象，并让 [runtime/validate.mbt](../runtime/validate.mbt) 改走 `configuration_from_scan` / `configuration_from_expected` / `compare_configurations` / `validate_configuration` 同一路径；ENI 工作流现已进一步收口为“[cmd/eni_json/main.mbt](../cmd/eni_json/main.mbt) 基于 `Milky2018/xml` 做 XML→JSON 中转，[runtime/configuration_eni.mbt](../runtime/configuration_eni.mbt) 只接收 ENI JSON 中间格式并投影到同一 `ConfigurationModel`”，把 `Slave/Info` 下的从站顺序、站地址、Identity、Identification，以及 `SM/FMMU/PDO + mailbox/DC` 的最小通用摘要接入统一模型，并兼容十进制、`#x` 与 `0x` 数值写法；ESI/SII 路径则补成同一原则：由 [cmd/eni_json/esi_projection.mbt](../cmd/eni_json/esi_projection.mbt) 把 ESI XML 解析为共享 JSON 中转模型，[runtime/esi_json.mbt](../runtime/esi_json.mbt) 统一承载 `xml -> struct -> json -> struct -> sii-view` 的唯一中转语义，[cmd/main/esi_projection.mbt](../cmd/main/esi_projection.mbt) 仅消费 `--esi-json` 并复用现有 `read-sii` 文本/JSON 输出，不再直接解析 XML。这样后续无论配置工具导入还是 JSON 缓存回放，都只需要一套中转模型；同时 [cmd/main/main.mbt](../cmd/main/main.mbt) 已改为 `validate --eni-json <path>` 与 `esi-sii -- --esi-json <path>` 分别接入两条 JSON 桥，并在文本/JSON 输出中暴露稳定结构。设计依据与参考实现映射延续 EtherCAT_Compendium 的 “Configuration Tool + ESI/ENI + startup comparison” 工程流，以及 CherryECAT 脚本式 ENI 字段提取与 SOEM sample ENI / ESI 中 `0x` 数值、`Mailbox`、`Dc`、`Fmmu` 结构的共同结论：XML 解析 DTO 必须物理隔离在独立工具中，runtime 仅消费规范化 JSON 中间格式，避免形成第二套校验语义。代码提交：`49a95d7` `feat(config): isolate eni xml behind json bridge`。2026-03-16 在真实单从站链路上复跑 `validate --json`，返回 `grade=Pass`、`difference_count=0`，确认统一配置比较路径在 Native 实机上仍保持闭环。

- [x] 定义统一配置对象模型：当前已承载 online scan 结果、离线期望配置、最小 ENI 导入结果与统一差异列表。
- [x] 定义 ENI 导入最小边界：当前已覆盖从站顺序、站地址、身份信息、Identification，以及最小 `SM/FMMU/RxPDO/TxPDO + mailbox/DC` 摘要。
- [x] 明确 online scan 到统一配置对象的投影规则，避免“扫描结果对象”和“配置结果对象”长期分叉。
- [x] 设计启动比对结果：当前已提供 `Pass/Warn/Block` 三级结论，其中 `Extra` 归入 `Warn`，缺失/身份/地址/Identification 差异归入 `Block`；后续继续细化到拓扑差异、身份差异、配置差异、可忽略差异。
- [x] 设计 JSON 输出模型：当前 `validate` JSON 已输出 `expected_source` / `actual_source` / `grade` / totals 与完整 `differences[]`，CLI 与 Extism 可直接供配置工具消费。
- [x] 建立最小验证：已补 unified model / compare / validate 兼容语义测试，新增 ENI 导入夹具的成功/失败用例，并于 2026-03-16 在真实总线上复跑 Native `validate --json`。

配置工具 / ENI 主线验收标准：

- [x] online scan 与 ENI import 能进入同一配置对象模型。
- [x] 启动比对结果可稳定输出“通过 / 警告 / 阻塞”三级结论与完整具体差异项。
- [x] CLI 输出同时支持人工阅读和配置工具复用；Extism 返回结构与 CLI 对齐。
- [x] 不新增第二套拓扑/配置语义，`scan/validate` 与 ENI 路径共享同一核心校验规则。

## 0.5 主站对象字典与统一诊断表面拆解 【L3 · 主线 A】

> 目标是把 AL / WKC / DC / 拓扑 / 配置摘要汇聚到一个稳定结果对象，避免 CLI、库和配置工具各自维护状态解释逻辑。

最新回填：已在 [runtime/diagnosis.mbt](../runtime/diagnosis.mbt) 新增 `DiagnosticSurface` / `DiagnosticIssue` / `ConfigurationSurfaceSummary` / `RuntimeMetricsSummary` 等统一结果对象，并提供 `diagnostic_surface_from_validate` / `diagnostic_surface_from_run` / `diagnostic_surface_from_state_transition` / `diagnostic_surface_from_slave_diagnosis` 四条 runtime 级构造器，把寄存器、Mailbox/CoE、拓扑/配置差异与运行时遥测统一映射到 `Block/Degrade/Info` 三级结论；[cmd/main/main.mbt](../cmd/main/main.mbt) 已让 `validate/state/diagnosis/run` JSON 一致附带 `surface`，Extism [plugin/extism/entrypoints.mbt](../plugin/extism/entrypoints.mbt) 的 `validate/run` 也复用同一结果对象序列化；回放与白盒覆盖已补到 [runtime/runtime_test.mbt](../runtime/runtime_test.mbt)、[cmd/main/main_wbtest.mbt](../cmd/main/main_wbtest.mbt)、[plugin/extism/extism_test.mbt](../plugin/extism/extism_test.mbt)。2026-03-16 在真实从站上复跑 Native `diagnosis --station 4097 --json`，返回 `AL State=Init`、`AL Error Flag=false`、`AL Status Code=0`，并带出统一 `surface`。

- [x] 定义主站对象字典最小范围：当前 `DiagnosticSurface` 已承载主站状态、配置摘要、从站站地址摘要、诊断计数器与运行态关键指标。
- [x] 定义统一诊断结果对象：当前已覆盖 AL State / AL Code、WKC、Diagnosis History、运行态遥测以及拓扑/配置差异摘要。
- [x] 明确诊断来源分层：当前已按 `Registers`、`Mailbox`、`Topology`、`Configuration`、`RuntimeTelemetry`、`StateTransition` 分层。
- [x] 明确错误与告警等级：当前已统一为 `Block` / `Degrade` / `Info`。
- [x] 设计 CLI / 配置工具共享输出模型：当前 CLI 与 Extism `validate/state/diagnosis/run` JSON 已统一附带 `surface`，文本输出继续保持运维友好。
- [x] 建立最小验证：已补 runtime/CLI/Extism 回放与白盒测试，并于 2026-03-16 在真实从站上复跑 Native `diagnosis --station 4097 --json`。

主站对象字典与统一诊断表面验收标准：

- [x] 至少有一个统一结果对象能同时服务 CLI、库和配置工具。
- [x] 相同诊断输入在不同产品面输出同一状态结论和错误分类。
- [x] 现有 `diagnosis`、`state`、`validate` 中重复的状态解释逻辑可以收敛到统一模型。
- [x] 不把平台专属实现细节泄漏进诊断 public surface。

## 0.6 拓扑变化 / Hot Connect 主线拆解 【L3-L4 · 主线 B】

> 目标是把“显式标识校验”扩展成稳定的启动期拓扑比较与 Hot Connect 能力，而不是继续停留在 4-tuple 单点校验。设计依据以 EtherCAT_Compendium 对 topology comparison / Hot Connect group 的描述为主，并参考 GatorCAT、ethercrab、SOEM 在从站顺序、站地址、别名地址、链路位置恢复上的共同做法。

建议参考实现锚点：

- GatorCAT：扫描期保留从站顺序、地址与 identity，用于启动时确定 group/position 预期。
- ethercrab：以稳定 `SubDevice`/identity 视图承接扫描与后续运行，不为 Hot Connect 单独复制第二套状态对象。
- SOEM：在配置初始化与状态检查路径里，把“发现到的从站拓扑”与“预期配置”持续绑定，而不是只做一次松散匹配。
- EtherCAT_Compendium：Hot Connect group、Explicit Device Identification、拓扑变化告警必须服务启动判断和后续运维诊断，而不只是导入时字段保存。

- [x] 定义拓扑指纹对象：当前统一配置对象已覆盖 `position / configured_address / alias_address? / identity / identification / process_data_summary 摘要`，作为 scan、offline config、ENI JSON 共用的最小比较单元。
- [x] 定义 Hot Connect group / optional segment 模型：当前已通过 `SlavePresence::{Mandatory, Optional(group_id)}` 把“必须存在”和“允许缺失”的从站集合编码进统一配置对象，避免把可选组逻辑散落到 CLI。
- [x] 扩展差异分类：当前已补 `OptionalMissing` 与 `AliasAddressMismatch`，并让 `category/grade` 继续由 runtime 统一裁定；后续如需更细标签，在同一差异模型内扩展。
- [x] 定义启动期告警策略：当前已把“可选组缺失”降为 `Warn`，并保持主链路缺失、站地址/别名漂移、身份冲突为 `Block`。
- [ ] 设计最小证据链：replay/fixture 级拓扑变化回放已补齐；2026-03-16 已在真实单从站链路上复核 `scan/validate` 的 topology surface 与统一差异输出。后续仍缺“optional slave 缺失仍可启动”和“mandatory slave 缺失阻塞启动”两条实机分支证据。

拓扑变化 / Hot Connect 验收标准：

- [x] online scan、offline config、ENI JSON 对同一拓扑指纹使用同一对象模型，不引入新的 Hot Connect 专用比较路径。
- [x] `validate` 与后续配置工具可稳定区分“阻塞型拓扑异常”和“可降级 optional group 缺失”。
- [x] 统一差异输出既能服务 CLI 文本，也能直接供配置工具/Extism JSON 复用。
- [ ] 至少有一条回放测试与一条 Native smoke 证明 Hot Connect 分级不是纸面模型。

## 0.7 Native / Extism 后续收口补充 【L4 · 主线 A+C】

> 目标不是继续扩展命令数量，而是把已有 Native/Extism 表面收敛成可发布、可验证、可维护的后端产品面。参考依据以 Npcap SDK、IGH Raw Socket 路径、GatorCAT NIC 封装，以及 Extism Host boundary 设计文档为主。

- [x] Native：补“真实链路持续运行”证据，把 `scan -> validate -> state -> diagnosis -> run` 串成同一网卡会话下的最小长链 smoke，并记录空总线/单从站两类基线。2026-03-14 已在 `\\Device\\NPF_{21208AED-855D-48E0-B0AF-A5B92C93EEDC}`（Realtek USB GbE）上顺序跑通 `list-if -> scan -> validate -> read-sii -> diagnosis -> state --station 4097 --path --state preop -> od --station 4097 -> run`：扫描到 1 个从站（4097 / alias 0 / vendor 1894 / product 2320），`validate` 为 `Pass`，`diagnosis` 返回 `AL State=Init` 且无错误，`state` 成功将 4097 从 `Init` 迁到 `PreOp`，`od` 成功返回对象索引列表，`run` 返回 `cycles_ok=10`、`final_phase=Done`；2026-03-18 又在同一 Realtek USB GbE 链路上复跑省略 `--if` 的 `scan --backend native-windows-npcap --json` 与 `run --backend native-windows-npcap --startup-state op --cycles 10 --json`，确认自动选卡仍命中单从站（4097 / vendor 1894 / product 2320），且在补齐严格 ESM 路径、启动阶段重排、AL code 恢复策略和 mailbox `SM0/SM1` 启动映射后，`run` 再次稳定返回 `cycles_ok=10`、`final_phase=Done`、`fault=null`；与先前空总线基线一起，已形成两类 Native smoke 证据。
- [x] Native：SII 完整类别深读计划已补齐到 [docs/SII_FULL_READ_DESIGN.md](../docs/SII_FULL_READ_DESIGN.md)，并按 ETG.2010 + siitool / EtherCAT.net.ui_sii / ethercrab 的共同边界，把类别拆成“运行时强语义类别”“展示/工具链类别”“厂商/应用扩展类别”三层。当前 `read-sii` 已输出 preamble/standard/header/strings/general/FMMU/FMMU_EX/SM/SyncUnit/DC/PDO/Timeouts/categories/raw-category，不再是仅 header/general 的最小形态；2026-03-22 已先后完成 `Timeouts(70)`、AoE mailbox protocol 位、`CurrentOnEBus` signed decode、`FMMUX(42)`、`SyncUnit(43)`、未知/vendor category 的 `type_code + raw bytes` 保留、Vendor Info、ESC Config Area B，以及 dynamic process-data `SM type 0x05/0x06` 的建模与 CLI 输出，代码提交 `cdac077` 与 `43b36e8`。同日继续把 CLI `read-sii`、offline `esi-sii`、runtime startup 和 mailbox mapping 收口到共享 `SiiFullInfo` 聚合模型：由 [mailbox/sii_parser.mbt](../mailbox/sii_parser.mbt) 新增 `parse_sii_full_info`，由 [mailbox/mapping.mbt](../mailbox/mapping.mbt) 新增 `calculate_slave_mapping_from_sii`，并让 [cmd/main/main.mbt](../cmd/main/main.mbt)、[cmd/main/esi_projection.mbt](../cmd/main/esi_projection.mbt)、[runtime/run.mbt](../runtime/run.mbt)、[runtime/esi_json.mbt](../runtime/esi_json.mbt) 复用同一份 SII 派生结果，代码提交 `ebbaf31` `feat(sii): share aggregated full-info model`。随后把 protocol 层 ownership/32-bit-64-bit EEPROM 补读逻辑收口为公开 `read_sii_bytes` / `read_sii_bytes_ap`，使 `read-sii` 在给定初始探测窗口后可按 EEPROM size 自动补读完整 SII 镜像，代码提交 `45b7217` `feat(protocol): auto-expand complete sii reads`。2026-03-23 继续把 20/80/90/100/110 从普通 `Raw` 提升为显式标准保留类别，统一接入 parser、offline ESI category code 映射与 `read-sii` JSON/文本标题输出，但仍保持 raw-bytes 导出、不伪造结构字段，代码提交 `5b8f96e` `feat(sii): recognize standard reserved categories`。同日再为所有 category 导出稳定 `category_class`，把 `Raw` 条目细分为 `standard-unknown` / `device-specific` / `vendor-specific` / `application-specific`，并在 `read-sii` / `esi-sii` JSON 与文本 raw-section 中统一输出，代码提交 `ff93f64` `feat(sii): export category classes`。随后继续补出 typed overlay 挂载点：由 [mailbox/sii.mbt](../mailbox/sii.mbt) 新增 `SiiOverlayScope`、`SiiOverlayCandidate`、`SiiCategoryEntry::overlay_candidate()`，由 [cmd/main/main.mbt](../cmd/main/main.mbt) 在 categories JSON / raw 文本输出中新增 `overlay_key`，使扩展 category 后续可直接按 `device-specific:0005`、`vendor-specific:1234`、`application-specific:2001` 这类稳定 key 叠加 typed overlay，代码提交 `ca0a906` `feat(sii): add raw category overlay hook`。验证证据已更新为：`moon test` 定向回归 `87 passed / 0 failed`（mailbox + cmd/main + runtime）。至此，SII 完整类别深读框架项闭环完成；后续若继续做厂商定制 section，只需要在该分类框架上叠加 typed overlay，而不是再改主 parser 边界。
- [x] Native：SII raw overlay 合同已进一步稳定到“可区分已注册/未注册 decoder”的层级。2026-03-23 在 [mailbox/sii.mbt](../mailbox/sii.mbt) 为 `SiiOverlayCandidate` 新增 `decoder_name()` / `status_label()`，并让 [cmd/main/main.mbt](../cmd/main/main.mbt) 的 `read-sii` JSON 与文本 raw-section 同步导出 `overlay_status` / `overlay_decoder`，当前对没有真实厂商样本支撑的扩展 section 明确标记为 `opaque` 而不是伪造 typed decode，代码提交 `b024aec` `feat(sii): expose overlay decoder status`。验证：`moon test mailbox/mailbox_test.mbt` + `cmd/main/main_wbtest.mbt` `173 passed / 0 failed`，全量 `moon test` `413 passed / 0 failed`。
- [x] Native：SII 解析对齐 ETG2010 v1.0.2 规范审计。2026-03-31 对照 ETG2010 Tables 7-15 做全量审计，修补 5 项缺口：① `FmmuDirection` 新增 `DynamicOutputs`(0x05) / `DynamicInputs`(0x06)（Table 9）；② `SiiGeneral` 新增 `group_idx_dup` 字段（Table 7, byte 0x0E）；③ `SiiPdo` 新增 8 个 flags 位辅助方法 `is_mandatory` / `is_default` / `is_fixed_content` / `is_virtual_content` / `is_module_align` / `is_depend_on_slot` / `is_depend_on_slot_group` / `is_overwritten_by_module`（Table 15）；④ `SiiGeneral::identification_method()` 提取 flags bits 3-4（Table 8）；⑤ 联动更新 [mailbox/mapping.mbt](../mailbox/mapping.mbt) `calculate_fmmu_configs` + `FmmuConfig::to_bytes`、[runtime/esi_json.mbt](../runtime/esi_json.mbt) 编解码、[cmd/main/main.mbt](../cmd/main/main.mbt) `fmmu_usage_name` 的所有 match 分支。新增 5 个测试覆盖全部新增 API，代码提交 `2074429` `fix(sii): align SII parsing with ETG2010 v1.0.2 conformance gaps`。验证：`moon check` 0 errors，`moon test` `435 passed / 0 failed`。审计结论：当前 SII 实现已无 ETG2010 运行时显著缺口。
- [x] 基础协议：AL Status Code 和 SDO Abort Code 人可读描述表。2026-04-01 对照 ETG.1000.6 Table 11（AL Status Code）和 Table 40（SDO Abort Transfer）补齐两张描述表：① [protocol/esm.mbt](../protocol/esm.mbt) 新增 `al_status_code_description()` 覆盖 50+ 标准码；② [mailbox/coe_engine.mbt](../mailbox/coe_engine.mbt) 新增 `sdo_abort_code_description()` 覆盖 30+ 标准码；③ 所有 CLI 输出路径（diagnosis/esc-regs/run startup trace/OD browse）的文本和 JSON 同步接入人可读描述（JSON 新增 `al_status_code_description` / `abort_code_description` 字段）；④ ESM 引擎 `clear_al_error` / `clear_al_error_ap` 错误消息附带描述。新增 4 个测试，代码提交 `d19db2d` `feat(protocol): add AL Status Code and SDO Abort Code description tables per ETG.1000.6`。验证：`moon check` 0 errors，`moon test` `439 passed / 0 failed`。
- [ ] Native：把 AddressSanitizer/等价内存安全检查固定成文档化命令，覆盖句柄泄漏、重复 close、错误 ownership 标注三类风险。
- [ ] Extism：补 host capability adapter 的最小闭环，优先打通 `nic_open/send/recv/close + clock_now/sleep`，共享内存优化保持第二阶段，不让能力边界长期停在 contract 文档。
- [ ] Extism：增加“无文件系统宿主”回放，验证 `scan/validate/run` 的 bytes 输入路径，确保插件产品面不依赖本地路径语义。
- [ ] Extism：补 shared-memory transport 的长度/所有权/回收责任回放测试，确保 run 路径不会因为隐式复制或悬垂缓冲区形成宿主侧事故。

## 0.8 基础协议精细化缺口（2026-04-01 审计）

> 来源：对照 ETG.1000.4/5/6、ETG.1500、EtherCAT Compendium 逐项与当前代码交叉验证。以下为已确认的精细化缺口，不影响 Class B 强制功能覆盖率（17/17 = 100%），但影响实机可用性或诊断深度。

- [x] **PreferNotLRW SII 标志**：`PdoContext` 增加 `block_lrw` 字段，`pdo_exchange_result` 自动分派 LRD+LWR 或 LRW；runtime 三条启动路径均从 SII General flags 推导设置。WKC 按 SOEM 惯例对 LWR 做 ×2 归一化。→ `0021a62`
- [x] **Emergency 主动轮询**：Runtime 增加 `emergency_stations` 字段和 `configure_emergency_stations()`、`poll_emergencies()` 方法；PDO 交换后逐站轮询 SM Input 状态，解码 CoE Emergency 帧并计入 `Telemetry.emergency_events`；`run()` 从 startup mailbox plans 自动配置轮询目标；CLI JSON 三处输出均含 `emergency_events`。→ `d0fa1c7`
- [x] **SM Watchdog 验证**：新增 5 个 Watchdog ESC 寄存器常量（0x0400-0x0442）、`SmWatchdogConfig` 结构体及 `read_sm_watchdog_config()` 读取函数；`ValidateSmWatchdog` 步骤插入 SafeOp→Op 启动序列（WarmupProcessData 之后、TransitionToOp 之前），逐站读取看门狗配置作诊断快照，不阻塞状态转换（ESC 自身通过 AL Status Code 0x001B 强制执行看门狗故障）。→ `b77ae87`

## 0.9 协议精细化缺口第二轮（2026-03-31 审计）

> 来源：对照 ETG.1000.4/5/6、ETG.1500 Table 1、EtherCAT Compendium 与代码现状交叉验证。以下缺口按实机可用性影响排序。

### 已就绪机制未接线

- [x] **SII Timeout → ESM Runtime 接线**：`esm_timeout_policy_from_sii_timeouts()` 将 SII category 41 超时映射为 `EsmTimeoutPolicy`；`transition_to_target_strict_with_timeout_policy()` 支持策略感知严格转换；`RunStartupPreparation.esm_timeout_policies` 存储每站策略并贯穿 `transition_stations_for_startup` 全链路。`d6d26bf`

### DLL 诊断层

- [x] **DL/Ph Error Counters 寄存器读取**：ESC 0x0300-0x0313（RX Error Counter×4 端口、Forwarded RX Error Counter×4、ECAT Processing Unit Error Counter、PDI Error Counter、Lost Link Counter×4）。已新增 5 组寄存器常量、`PortErrorCounters`/`DlErrorCounters` 结构体、`read_dl_error_counters` (FP) / `read_dl_error_counters_ap` (AP)，并接入 `SlaveDiagnosis` 和 CLI diagnosis JSON/text 输出。commit: `a20f955` [ETG.1000.4 §6.4, EtherCAT Compendium §3.3]

### 协议层缺失

- [x] **FoE 基础协议**：FoE 帧编解码层（`mailbox/foe.mbt`）+ 事务状态机（`protocol/foe_transaction.mbt`）已完成。支持 FoeOpCode (Read/Write/Data/Ack/Error/Busy)、FoeErrorCode (15 标准码)、FoeResponse 解析，以及 `foe_download`/`foe_upload` (FP+AP) 多包传输含 RMSM 计数器管理和 Busy 重试。commit: `4923f4b` [ETG.1500 #701 Class A shall; ETG.1000.6 §5.8]

### DC 同步扩展

- [x] **SYNC1 独立配置**：`dc_configure_sync0` 已扩展可选参数 `sync1_cycle_ns`，当 >0 时写入 `reg_dc_cycle1`(0x09A4) 并将 activation byte 从 0x03 改为 0x07（cyclic+SYNC0+SYNC1）。向后兼容，默认值 0U 不改变现有行为。commit: `1acf07d` [EtherCAT Compendium §5.5]

### 低优先级（may/should，不阻塞 Class B）

- [x] **EEPROM 数据写入**：已实现 `eeprom_write_word` (FP) / `eeprom_write_word_ap` (AP) word 级 16-bit 写入。写入流程遵循 SOEM 参考：① 获取 Master 所有权 → ② 写 16-bit 数据到 `reg_sii_data`(0x0508) → ③ 发送写命令 `0x0201` + 地址到 `reg_sii_control`(0x0502) → ④ 等待 busy 清除 → ⑤ 恢复 PDI 所有权。含 NACK 重试（≤3 次）和错误清除。commit: `c0f4f6a` [ETG.1500 #305 Write may]
- [x] **Watchdog 写入配置**：新增 `write_sm_watchdog_config(nic, station, divider, pdi_time, pdata_time, timeout)` 写入 3 个看门狗寄存器（0x0400 divider、0x0410 PDI、0x0420 PData），补全 §0.8 中仅有只读 `read_sm_watchdog_config` 的缺口。commit: `d7004dd` [ETG.1000.4 §6.3 shall basic]
- [x] **Station Alias 写入**：新增 `write_station_alias(nic, station, alias, timeout)` 写入 2 字节到 `reg_station_alias`(0x0012)，补全仅有 `read_station_alias` 的缺口。commit: `d7004dd` [ETG.1000.4 §5 may]
- [x] **EoE 基础协议**：EoE 帧编解码层 (`mailbox/eoe.mbt`) 已完成。支持 `EoeFrameType` 枚举（FragData..GetAddrFilterResp）、`EoeResult` 枚举（Success/UnspecifiedError/UnsupportedFrameType/NoIpSupport/NoDhcpSupport/NoFilterSupport）、`encode_eoe_fragment`/`encode_eoe_set_ip_req`/`encode_eoe_get_ip_req` 编码函数、`decode_eoe_response` → `EoeResponse`（Fragment | IpResponse）解码。commit: `d7004dd` [ETG.1000.6 §5.7; ETG.1500 shall if EoE slaves]。后续在此基础上实现了完整 EoE Virtual Switch 引擎（`eoe_switch.mbt` + `eoe_endpoint.mbt` + `eoe_relay.mbt`）与异步桥接包（`eoe_async/`），详见 §0.11。
- [x] **SoE 基础协议**：SoE 帧编解码层 (`mailbox/soe.mbt`) 已完成。支持 `SoeOpCode` 枚举（ReadReq..Emergency）、`SoeElementFlag` 枚举（DataState..Default）及 `soe_element_flags` 组合、`encode_soe_read_req`/`encode_soe_write_req` 编码函数、`decode_soe_response` → `SoeResponse`（ReadData | WriteAck | Error | Notification）。commit: `d7004dd` [ETG.1000.6 §5.6; ETG.1500 should if SoE slaves]

### 延后设计决策（may/optimization，无参考实现支持或非运行时关键）

- [ ] **Mailbox Status Bit FMMU 映射轮询**：当前通过直接寄存器读取检查 SM status bit，功能等价完整；FMMU 映射到 cyclic PDO 的优化路径 SOEM/ethercrab 均不实现。延后理由：optimization only, functionally complete。[ETG.1500 #404 细节]
- [ ] **帧重复发送**：SII `frame_repeat_support` 标志已解析和 CLI 输出，但 runtime 不根据此标志重复发送周期帧。传输层已有重试机制（transport retry）。延后理由：SOEM/ethercrab 均不基于 SII 标志做帧重复。[ETG.1500 #203 may]
- [ ] **Slave-to-Slave 通信**：完全未实现，ENI 复制映射配置与 runtime 数据搬运均缺失。延后理由：无参考实现支持（SOEM 无、ethercrab 无），属 Safety Master 范畴。[ETG.1500 §5.14]
- [ ] **VoE (Vendor-specific over EtherCAT)**：仅有 `MailboxType::VoE`(0x0F) 类型定义，无帧编解码和事务。延后理由：厂商专属协议，需具体设备样本才能验证，on-demand。[ETG.1000.6 §5.9 may]
- [ ] **DC LATCH0/LATCH1 输入事件捕获**：未实现外部 LATCH 信号寄存器读写（0x09AE-0x09B7）。延后理由：仅服务外部传感器时间戳采集用例，当前无实机目标。[EtherCAT Compendium §5.5 may]

## 0.10 ESM / DC 深度审计改进（2026-03-31）

> 来源：对照 SOEM `ec_config.c`/`ec_dc.c`、ethercrab、gatorcat 参考实现，以及 ETG.1000.4/5/6 规范，对已实现的 ESM Engine 和 DC 模块进行深度质量审计并修补。

### ESM Engine 改进

- [x] **总线初始化寄存器清除（CRITICAL）**：新增 `set_slaves_to_default()` 函数，通过 BWR 广播清除 FMMU(0x0600, 48B)、SM(0x0800, 32B)、DC sync activation、CRC counters(0x0300, 8B)、IRQ mask(→0x0004)、Station Alias、AL Control(Init+Ack)、EEPROM config(PDI→Master)，匹配 SOEM `ecx_set_slaves_to_default` 完整序列。commit: `006c952` [ETG.1000.4 §6; SOEM ec_config.c:90]
- [x] **broadcast_state Error Ack 位**：`broadcast_state()` 新增 `ack_error? : Bool` 可选参数，设置时写入 `target_byte | 0x10`（bit 4 = Error Ack）。原有默认行为不变。commit: `006c952` [ETG.1000.6 §5.3.2]

### DC 模块改进

- [x] **4 端口接收时间读取**：新增 `dc_read_port_times()` 读取 0x0900-0x090F 全部 16 字节，返回 `DcPortTimes{ port0, port1, port2, port3 }`，为拓扑感知延迟算法提供基础。commit: `006c952` [ETG.1000.4 §9.2; SOEM ec_dc.c]
- [x] **DC 支持检测**：新增 `dc_check_support()` 检查 DL Information 寄存器(0x0008) bit 2，判断从站是否支持 DC。commit: `006c952` [ETG.1000.4 §6.1]
- [x] **64 位系统时间**：新增 `dc_read_system_time_64()` 读取完整 8 字节 DC system time(0x0910)，避免 32 位 ~4.3 秒溢出。`dc_configure_sync0` 启动时间计算已改用 64 位。commit: `006c952` [ETG.1000.4 §9.2]
- [x] **DCSOF 读取**：新增 `dc_read_sof()` 读取 64 位 DC receive timestamp(0x0918)，用于精确系统时间偏移计算。commit: `006c952` [SOEM ec_dc.c]
- [x] **DC 去激活路径**：新增 `dc_deactivate_sync()` (单站) 和 `dc_deactivate_sync_all()` (广播)，为关机/错误恢复提供 DC 关闭路径。commit: `006c952`
- [x] **le_u64 / write_u64 辅助函数**：新增 64 位小端编解码辅助函数。commit: `006c952`

### 新增寄存器常量

- [x] `reg_dl_information` (0x0008)、`reg_dl_port` (0x0101)、`reg_irq_mask` (0x0200)、`reg_dc_speed_count` (0x0930)、`reg_dc_time_filter` (0x0934)。commit: `006c952`

### 延后项（审计确认，当前不阻塞）

- [ ] **拓扑感知传播延迟算法**：当前 `dc_configure_linear` 使用 `abs_diff_u32` 简单差值，对非线性拓扑（分支/星型）不准确。需要利用已实现的 `dc_read_port_times` 4 端口数据实现 SOEM 风格的 entry port 检测、parent-child 遍历、累积延迟。延后理由：需拓扑模型配合，当前无分支拓扑实机验证目标。
- [ ] **AssignActivate → CUC 写入接线**：SII `assign_activate` 已解析但未自动写入 0x0980。延后理由：需与拓扑感知 DC init 流程一同设计。
- [ ] **Sync 收敛验证调用**：`dc_read_sync_window()` 存在但未在 DC init 后自动调用验证时钟同步收敛。延后理由：运行时诊断层已可手动调用。

## 0.11 ETG.1500 Master Classes 全量审计（2026-04-01）

> 来源：对照 ETG.1500 v1.0.2 Table 1 全部特性条目，逐项审查 MoonECAT 已实现功能的覆盖度与合规性，修补发现的缺口。

### 审计范围

读取 ETG.1500 §5.3–§5.15、§6（Feature Packs）全文，对照 Table 1 所有特性 ID 与 `shall/should/may` 分级，逐一检查 `protocol/`、`mailbox/`、`runtime/` 各包的实现状态。

### 审计结果摘要（30+ features）

| Feature ID | Feature | 分级 | 状态 |
|---|---|---|---|
| 101 | Service Commands | shall | ✅ 全部 EtherCAT 命令已实现 |
| 102 | IRQ field | should | ✅ PdoExchangeResult.irq |
| 103 | Device Emulation | shall | ✅ read_device_emulation, request_state_aware |
| 104 | ESM | shall | ✅ 完整 ESM Engine + SII 超时 |
| 105 | Error Handling | shall | ✅ DlErrorCounters, AL Status Code |
| 107 | EtherCAT Frame Types | shall | ✅ |
| 201 | Cyclic PDO | shall | ✅ LRW + split LRD/LWR |
| 301 | Online scanning / ENI | shall | ✅ 双路径已实现 |
| 302 | Compare Network config | shall | ✅ compare_configurations |
| 303 | Explicit Device ID | should | ✅ runtime/scan + validate |
| 304 | Station Alias | may | ✅ read/write + enable |
| 305 | EEPROM Access | shall | ✅ read + write |
| 401 | Mailbox | shall | ✅ send/recv/exchange |
| 402 | Resilient Layer (RMSM) | shall | ✅ 计数器管理 |
| 404 | Mailbox polling | shall | ✅ **本次修复：MailboxState FMMU 映射** |
| 501–504 | SDO Up/Down/Seg/CA/Info | shall | ✅ 全部已实现 |
| 505 | Emergency | shall | ✅ 解码 + 主动轮询 |
| 601 | EoE Protocol | shall | ✅ 帧编解码 + Virtual Switch 引擎 |
| 602 | Virtual Switch | shall(A) | ✅ EoeSwitch 引擎 + endpoint/relay/async bridge；L2 路由延后 |
| 701–703 | FoE + Boot | shall | ✅ download/upload + Boot state |
| 801 | SoE Services | shall(A) | ✅ 帧编解码 |
| 1101 | DC support | shall | ✅ 完整 DC |
| 1102 | Continuous Prop Delay | should | ✅ dc_reestimate_propagation_delays |
| 1103 | Sync window monitoring | should | ✅ **本次修复：broadcast BRD 0x092C** |
| 1301 | Master OD | should(A)/may(B) | ✅ build_master_od + CLI master-od |

### 本次修复

- [x] **DC 广播同步窗口监测（#1103）**：新增 `dc_broadcast_sync_window()` 使用 BRD 读取 0x092C，返回所有 DC 从站的 ORed System Time Difference + WKC；新增 `dc_check_sync_window()` 提供阈值比较便捷接口，处理有符号二补数转换。commit: `bc08348` [ETG.1500 §5.13.3]
- [x] **FMMU MailboxState 映射（#404）**：修改 `calculate_fmmu_configs()` 不再跳过 MailboxState 方向，当 SII 声明 MailboxState FMMU 时，映射 SM1（输入邮箱）状态字节（SM_base + idx*8 + 5）到逻辑地址空间为 1 字节只读 FMMU；修复 `FmmuConfig::to_bytes` 中 MailboxState 方向字节从 0x00（无访问）改为 0x01（读访问）。commit: `bc08348` [ETG.1500 §5.6.4]

### EoE Virtual Switch 引擎（#601/#602）

2026-04-01 在 §0.9 EoE 帧编解码基础上，分三阶段实现 EoE Virtual Switch 引擎与异步桥接：

- [x] **Phase 1 — EoeSwitch 核心引擎**：[runtime/eoe_switch.mbt](../runtime/eoe_switch.mbt) 实现多站 EoE 虚拟交换机，含分片发送（`send_frame`）、多片重组（`process_received`）、mailbox 轮询（`poll`）、接收队列排空（`drain_rx`）、IP 配置（`set_ip/get_ip`）。`eoe_max_fragment_size()` 按 32 字节对齐计算最大分片。Runtime 集成：`Runtime.eoe_switch` 字段在 `run_cycle()` 中自动轮询。commit: `3222e4c`
- [x] **Phase 2 — QueueEndpoint + bridge_eoe_cycle**：[runtime/eoe_endpoint.mbt](../runtime/eoe_endpoint.mbt) 实现同步队列端点（`QueueEndpoint`）与一次性桥接函数 `bridge_eoe_cycle(sw, ep, nic, timeout) -> (rx, tx)`，供无 async 运行时的嵌入式环境使用。commit: `3222e4c`
- [x] **Phase 3 — EoeRelay 嵌入式中继**：[runtime/eoe_relay.mbt](../runtime/eoe_relay.mbt) 实现基于回调的同步中继 `EoeRelay::relay_cycle(sw, nic, timeout, rx_handler, tx_provider)`，适用于裸机/RTOS 等无队列环境。commit: `3222e4c`
- [x] **Async Bridge**：[eoe_async/eoe_async.mbt](../eoe_async/eoe_async.mbt) 引入 `moonbitlang/async` v0.16.8 依赖，实现 `EoeAsyncBridge`：async Queue TX/RX 通道 + 后台 `poll_loop` 任务，提供 `send()`/`recv()` 异步 API 与 `try_send()`/`try_recv()` 同步回退。独立包隔离，避免 MSVC 要求影响 runtime 测试。commit: `d52808d`

验证：32 个 EoE 相关测试（runtime 包，wasm-gc/native），4 个 async bridge 同步测试（wasm-gc）。`moon test` 全量通过。

### Master OD (#1301)

2026-04-01 实现主站对象字典。[runtime/master_od.mbt](../runtime/master_od.mbt) 新增 `build_master_od()` 构造 CoE 风格 OD，覆盖标准对象 0x1000-0x10FF（DeviceType、ErrorRegister、ManufacturerDeviceName、Identity 等），支持 ScanReport / Telemetry / DiagnosticSurface 可选注入；`MasterObjectDictionary` 提供 `format_text()` / `to_json()` / `indices()` 产品面 API。CLI 新增 `master-od` 命令含 `--json` 支持。commit: `d280dde`

### 延后项（审计确认，当前不阻塞）

- [ ] **EoE L2 路由 (#602 完整)**：EoeSwitch 引擎已实现站间收发与分片/重组，但跨站 L2 帧路由（基于 MAC 地址的端口转发表）尚未实现。延后理由：需要完整的网络栈集成（ARP/DHCP/TAP），为独立大特性。[ETG.1000.6 §5.7]
- [ ] **AoE (#901)**：ADS over EtherCAT 为 should，Beckhoff 特有协议，优先级低。

## 延后项汇总（2026-04-01 整理）

> 以下汇总散落在 §0.6–§0.11 各节中的所有延后项，按领域分类，方便后续统一排期。

### 协议层延后

| 来源 | 条目 | 分级 | 延后理由 |
|---|---|---|---|
| §0.11 | **EoE L2 路由 (#602 完整)** | shall(A) | EoeSwitch 引擎已实现站间收发与分片/重组，但跨站 L2 帧路由（基于 MAC 地址的端口转发表）需要完整的网络栈集成（ARP/DHCP/TAP），为独立大特性。 |
| §0.11 | **AoE (#901)** | should | Beckhoff 特有 ADS over EtherCAT 协议，优先级低，需具体设备样本。 |
| §0.9 | **VoE** | may | 仅有 `MailboxType::VoE`(0x0F) 类型定义，无帧编解码和事务。厂商专属协议，on-demand。 |
| §0.9 | **Slave-to-Slave 通信** | — | ENI 复制映射配置与 runtime 数据搬运均缺失。无参考实现支持（SOEM 无、ethercrab 无），属 Safety Master 范畴。 |
| §0.9 | **Mailbox Status Bit FMMU 映射轮询** | optimization | 当前通过直接寄存器读取检查 SM status bit，功能等价完整；FMMU 映射到 cyclic PDO 的优化路径 SOEM/ethercrab 均不实现。 |
| §0.9 | **帧重复发送** | may | SII `frame_repeat_support` 标志已解析和 CLI 输出，传输层已有重试机制。SOEM/ethercrab 均不基于 SII 标志做帧重复。 |

### DC 深度延后

| 来源 | 条目 | 延后理由 |
|---|---|---|
| §0.10 | **拓扑感知传播延迟算法** | `dc_configure_linear` 使用简单差值，对分支/星型拓扑不准确。需利用已实现的 `dc_read_port_times` 4 端口数据实现 SOEM 风格 entry port 检测、parent-child 遍历、累积延迟。需拓扑模型配合，当前无分支拓扑实机目标。 |
| §0.10 | **AssignActivate → CUC 写入接线** | SII `assign_activate` 已解析但未自动写入 0x0980。需与拓扑感知 DC init 流程一同设计。 |
| §0.10 | **Sync 收敛验证调用** | `dc_read_sync_window()` 存在但未在 DC init 后自动调用验证时钟同步收敛。运行时诊断层已可手动调用。 |
| §0.9 | **DC LATCH0/LATCH1 输入事件捕获** | 未实现外部 LATCH 信号寄存器读写（0x09AE-0x09B7）。仅服务外部传感器时间戳采集用例，当前无实机目标。 |

### 产品面延后

| 来源 | 条目 | 延后理由 |
|---|---|---|
| §0.6 | **Hot Connect 实机分支证据** | replay/fixture 级回放已补齐；仍缺"optional slave 缺失仍可启动"和"mandatory slave 缺失阻塞启动"两条实机分支证据。 |
| §0.7 | **Native AddressSanitizer 文档化** | 把 ASan/等价内存安全检查固定成文档化命令，覆盖句柄泄漏、重复 close、错误 ownership 标注三类风险。 |
| §0.7 | **Extism host capability adapter** | 打通 `nic_open/send/recv/close + clock_now/sleep` 最小闭环，共享内存优化保持第二阶段。能力边界停在 contract 文档。 |
| §0.7 | **Extism 无文件系统宿主回放** | 验证 `scan/validate/run` 的 bytes 输入路径，确保插件产品面不依赖本地路径语义。 |
| §0.7 | **Extism shared-memory transport 回放** | 补长度/所有权/回收责任回放测试，确保 run 路径不因隐式复制或悬垂缓冲区形成宿主侧事故。 |