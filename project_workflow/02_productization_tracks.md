# MoonECAT 产品化拆解

本文件由原 AI 任务清单拆分整理而来，对应原 0.3 到 0.7 节。

## 0.3 对象字典浏览产品化拆解

> 目标不是重复实现 CoE 事务，而是把已经落仓的 `SDO Info / Complete Access / Segmented Transfer` 能力组织成稳定的 CLI / 配置工具表面。

最新回填：已在 [cmd/main/main.mbt](../cmd/main/main.mbt) 新增 Native `od` 命令，并在 [runtime/diagnosis.mbt](../runtime/diagnosis.mbt) 抽出通用 mailbox prepare/restore helper；代码提交：`3832187` `feat(cli): add object dictionary browsing command`。随后又补齐 `od` 失败路径的结构化分类与文本/JSON 输出，代码提交：`6bdaa00` `feat(cli): classify od browse failures`。2026-03-16 再次在 `\Device\NPF_{21208AED-855D-48E0-B0AF-A5B92C93EEDC}`（Realtek USB GbE）上对真实从站执行 `od --station 4097 --json`，成功返回 `OD List` 索引数组，完成最小实机 smoke。

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

## 0.4 配置工具 / ENI 主线拆解

> 目标是把 online scan、离线 ENI、启动比对和差异报告纳入同一配置对象模型，而不是维护两套配置来源、两套校验语义。

最新回填：已新增 [runtime/configuration.mbt](../runtime/configuration.mbt)，引入 `ConfigurationModel` / `ConfigurationSlave` / `ConfigurationComparisonReport` 统一配置对象，并让 [runtime/validate.mbt](../runtime/validate.mbt) 改走 `configuration_from_scan` / `configuration_from_expected` / `compare_configurations` / `validate_configuration` 同一路径；ENI 工作流现已进一步收口为“[cmd/eni_json/main.mbt](../cmd/eni_json/main.mbt) 基于 `Milky2018/xml` 做 XML→JSON 中转，[runtime/configuration_eni.mbt](../runtime/configuration_eni.mbt) 只接收 ENI JSON 中间格式并投影到同一 `ConfigurationModel`”，把 `Slave/Info` 下的从站顺序、站地址、Identity、Identification，以及 `SM/FMMU/PDO + mailbox/DC` 的最小通用摘要接入统一模型，并兼容十进制、`#x` 与 `0x` 数值写法；ESI/SII 路径则补成同一原则：由 [cmd/eni_json/esi_projection.mbt](../cmd/eni_json/esi_projection.mbt) 把 ESI XML 解析为共享 JSON 中转模型，[runtime/esi_json.mbt](../runtime/esi_json.mbt) 统一承载 `xml -> struct -> json -> struct -> sii-view` 的唯一中转语义，[cmd/main/esi_projection.mbt](../cmd/main/esi_projection.mbt) 仅消费 `--esi-json` 并复用现有 `read-sii` 文本/JSON 输出，不再直接解析 XML。这样后续无论配置工具导入还是 JSON 缓存回放，都只需要一套中转模型；同时 [cmd/main/main.mbt](../cmd/main/main.mbt) 已改为 `validate --eni-json <path>` 与 `esi-sii -- --esi-json <path>` 分别接入两条 JSON 桥，并在文本/JSON 输出中暴露稳定结构。设计依据与参考实现映射延续 EtherCAT_Compendium 的 “Configuration Tool + ESI/ENI + startup comparison” 工程流，以及 CherryECAT 脚本式 ENI 字段提取与 SOEM sample ENI / ESI 中 `0x` 数值、`Mailbox`、`Dc`、`Fmmu` 结构的共同结论：XML 解析 DTO 必须物理隔离在独立工具中，runtime 仅消费规范化 JSON 中间格式，避免形成第二套校验语义。代码提交：`0d96a43` `feat(config): isolate eni xml behind json bridge`。2026-03-16 在真实单从站链路上复跑 `validate --json`，返回 `grade=Pass`、`difference_count=0`，确认统一配置比较路径在 Native 实机上仍保持闭环。

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

## 0.5 主站对象字典与统一诊断表面拆解

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

## 0.6 拓扑变化 / Hot Connect 主线拆解

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

## 0.7 Native / Extism 后续收口补充

> 目标不是继续扩展命令数量，而是把已有 Native/Extism 表面收敛成可发布、可验证、可维护的后端产品面。参考依据以 Npcap SDK、IGH Raw Socket 路径、GatorCAT NIC 封装，以及 Extism Host boundary 设计文档为主。

- [x] Native：补“真实链路持续运行”证据，把 `scan -> validate -> state -> diagnosis -> run` 串成同一网卡会话下的最小长链 smoke，并记录空总线/单从站两类基线。2026-03-14 已在 `\\Device\\NPF_{21208AED-855D-48E0-B0AF-A5B92C93EEDC}`（Realtek USB GbE）上顺序跑通 `list-if -> scan -> validate -> read-sii -> diagnosis -> state --station 4097 --path --state preop -> od --station 4097 -> run`：扫描到 1 个从站（4097 / alias 0 / vendor 1894 / product 2320），`validate` 为 `Pass`，`diagnosis` 返回 `AL State=Init` 且无错误，`state` 成功将 4097 从 `Init` 迁到 `PreOp`，`od` 成功返回对象索引列表，`run` 返回 `cycles_ok=10`、`final_phase=Done`；2026-03-18 又在同一 Realtek USB GbE 链路上复跑省略 `--if` 的 `scan --backend native-windows-npcap --json` 与 `run --backend native-windows-npcap --startup-state op --cycles 10 --json`，确认自动选卡仍命中单从站（4097 / vendor 1894 / product 2320），且在补齐严格 ESM 路径、启动阶段重排、AL code 恢复策略和 mailbox `SM0/SM1` 启动映射后，`run` 再次稳定返回 `cycles_ok=10`、`final_phase=Done`、`fault=null`；与先前空总线基线一起，已形成两类 Native smoke 证据。
- [ ] Native：补 SII 完整类别深读计划，按 siitool / SOEM `readeepromAP/FP` 经验继续完善 category 深度解码。当前 `read-sii` 已输出 preamble/standard/header/strings/general/FMMU/SM/DC/PDO/categories，不再是仅 header/general 的最小形态；2026-03-16 已修正 strings UTF-8 解码并在真实从站上确认 `group_name/order_name/name` 可读，后续重点转为稳定 JSON 结构、全量类别覆盖与配置工具复用。
- [ ] Native：把 AddressSanitizer/等价内存安全检查固定成文档化命令，覆盖句柄泄漏、重复 close、错误 ownership 标注三类风险。
- [ ] Extism：补 host capability adapter 的最小闭环，优先打通 `nic_open/send/recv/close + clock_now/sleep`，共享内存优化保持第二阶段，不让能力边界长期停在 contract 文档。
- [ ] Extism：增加“无文件系统宿主”回放，验证 `scan/validate/run` 的 bytes 输入路径，确保插件产品面不依赖本地路径语义。
- [ ] Extism：补 shared-memory transport 的长度/所有权/回收责任回放测试，确保 run 路径不会因为隐式复制或悬垂缓冲区形成宿主侧事故。