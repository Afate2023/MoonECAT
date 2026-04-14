# MoonECAT SII Full Read Design

> **实现状态（2026-04-14）**：本设计已全面落地。`mailbox/sii_parser.mbt` + `mailbox/sii.mbt` + `mailbox/sii_flags.mbt` 实现了完整的 SII 三层解析（A: preamble/B: fixed header+area/C: full category）。已支持 Strings(10)/General(30)/FMMU(40)/SyncM(41)/FMMU_EX(42)/SyncUnit(43)/TxPDO(50)/RxPDO(51)/DC(60)/Timeouts(70) 深解析，未识别类别保留为 `Raw`。`SiiFullInfo` 聚合模型、`SiiCategoryClass`/`SiiOverlayCandidate` 框架均已实现。CLI `read-sii` 命令可输出结构化 JSON。

本文档定义 MoonECAT 的 SII 完整类别深读计划。目标不是再做一套 ESI 解析器，而是把实时链路上的 EEPROM 读取、现有 mailbox SII parser、CLI 输出和后续配置工具消费统一到一条稳定路径，并把 ETG.2010 规定的类别覆盖范围拆成可执行阶段。

## 1. 设计目标

- 真实从站扫描时，identity 以 SII EEPROM 为准，不依赖 ESC 普通寄存器的偶然映射。
- 读取结果同时支持四种用途：
  1. 运行时 scan / validate 的 identity 与 mailbox 能力基线
  2. mailbox / FMMU / SyncManager / PDO / DC 映射推导
  3. `read-sii` / `esi-sii` 的稳定文本与 JSON 输出
  4. 后续 offline config / 配置工具共享的 EEPROM 语义模型
- 类别层必须保留原始 `type_code + raw bytes`，即使当前没有深解析，也不能丢弃未知、vendor-specific 或 application-specific section。
- 读取链路兼容 Windows Npcap 与 Linux Raw Socket，协议语义一致。

## 2. 参考实现结论

- siitool：把 EEPROM 视为原始字节流，先解析 preamble / fixed header，再按 category header 顺序遍历已知 section。
- EtherCAT.net.ui_sii：在线读取时先切换 EEPROM ownership，再根据 32/64-bit 读取宽度分块读出原始字节流，随后统一进入 category 模型；实际生成 EEPROM 内容时只覆盖通用类别，不处理 80/90/100/110。
- ethercrab：偏运行时消费，覆盖 identity / general / strings / sync manager / fmmu / fmmu_ex / PDO 等运行期高价值 section，不主动建模保留型/展示型类别。
- 三者的共同结论：
  - identity 固定头字段必须从 EEPROM header 读取。
  - 已知类别可以逐项深解析，但 category 边界与 raw bytes 必须完整保留。
  - 运行期真正刚需的深读重点是 General、FMMU、FMMU_EX、SyncM、SyncUnit、PDO、DC、Timeouts；DataTypes、Dictionary、Hardware、Vendor Information、Images 更偏展示/工具链消费。

## 3. 当前审计结论

### 3.1 已完成的固定头/类别建模

- 固定头：
  - preamble / standard metadata
  - identity / mailbox offsets / mailbox protocols
  - Vendor Info
  - ESC Configuration Area B
- 已深解析类别：
  - Strings (10)
  - General (30)
  - FMMU (40)
  - SyncM (41)
  - FMMU_EX (42)
  - SyncUnit (43)
  - TxPDO (50)
  - RxPDO (51)
  - DC (60)
  - Timeouts (70)
- 已落地的保留策略：
  - 未识别 category 保留为 `Raw`
  - category 记录 `type_code`
  - CLI 输出原始 category 预览

### 3.2 尚未完成的“完整类别深读”范围

按 ETG.2010 Table 5，当前仍未形成独立深读策略的范围有：

- DataTypes (20)
- Dictionary (80)
- Hardware (90)
- Vendor Information (100)
- Images (110)
- Device specific (01-09)
- Vendor specific (0x0800-0x1FFF, 0x3000-0xFFFE)
- Application specific (0x2000-0x2FFF)

这些类别里，20/80/90/100/110 属于“标准编号但当前规范内容保留或弱定义”的类别；其实现重点不是立即做强语义反序列化，而是先建立稳定的保留、索引、导出和后续增量解析能力。

### 3.3 当前文档/实现中的过时点

- category 终止标记的规范值是 `0xFFFF`，不是 `0x7FFF`。
- 为兼容旧 synthetic fixture，parser 可以接受历史 `0x7FFF`，但在线读取、生成和文档计划都应以 `0xFFFF` 为准。
- `parse_sii_header` 不能要求在线 scan 一次性读完整个扩展头；标准头必须允许独立解析，Vendor Info / Area B 走按长度可选解析。

## 4. 类别分层策略

### 4.1 A 类：运行时强语义类别

这些类别直接影响 runtime / mailbox / mapping / validate，要求完整结构化解析并有稳定测试：

- General (30)
- FMMU (40)
- SyncM (41)
- FMMU_EX (42)
- SyncUnit (43)
- TxPDO / RxPDO (50 / 51)
- DC (60)
- Timeouts (70)

要求：

- 结构体字段与 ETG.2010 表格逐字节对齐
- fixture + CLI + 运行时消费三层一致
- 对保留位保持无损读取，不把未知 flag 静默抹掉

### 4.2 B 类：展示/工具链类别

这些类别主要服务 `read-sii`、offline config 和未来配置工具：

- Strings (10)
- DataTypes (20)
- Dictionary (80)
- Hardware (90)
- Vendor Information (100)
- Images (110)

要求：

- 第一阶段先做到“边界正确 + 原始数据保留 + JSON 可导出”
- 第二阶段按类别逐步引入结构化子模型，不阻塞 runtime 主线
- 对规范仍标注 `Reserved for future use` 的类别，不伪造语义字段

### 4.3 C 类：厂商/应用扩展类别

- Device specific (01-09)
- Vendor specific (0x0800-0x1FFF, 0x3000-0xFFFE)
- Application specific (0x2000-0x2FFF)

要求：

- 一律先作为 `Raw` 保留
- category 索引、长度、原始 hex 预览稳定输出
- 后续若某个厂商 XML / 参考项目出现稳定子结构，再以“typed view over raw bytes”的方式增量加入，不污染通用 parser

## 5. 完整类别深读计划

### Phase 1：在线读取链路收口

目标：让“完整类别深读”拥有稳定数据源，而不是只依赖合成 fixture。

- protocol 层补齐：
  - `eeprom_to_master`
  - `eeprom_to_pdi`
  - 32/64-bit 读取宽度探测
  - `read_sii_bytes(station, start_byte, byte_count?)`
- 停止条件统一为：
  1. 优先使用 EEPROM size 字段
  2. 次选 category end marker `0xFFFF`
  3. 最后才是尾部 `0xFF` 裁剪
- 验收：
  - Native 在线读取与 fixture 解析共享同一 parser 入口
  - `scan` 可只读标准头，`read-sii` 可读完整 EEPROM

### Phase 2：统一聚合模型

目标：从“分散的 section 解析函数”收口为一个完整结果对象。

- 新增 `SiiFullInfo` 或同等聚合对象，建议至少包含：

```text
raw_bytes
preamble
standard_metadata
header
categories
strings
general?
fmmu
fmmu_ex
sync_managers
sync_units
tx_pdo
rx_pdo
dc_clocks
timeouts?
raw_categories
```

- 统一从 `categories` 派生 typed views，避免 CLI / runtime 各自重复遍历。
- 验收：
  - `read-sii`
  - `esi-sii`
  - offline config
  都消费同一聚合对象或其稳定序列化结果。

### Phase 3：标准保留类别接入

目标：把“已知编号但未深读”的标准类别纳入稳定输出面。

- DataTypes (20)
  - 第一阶段：作为标准类别单独识别，不再混入普通 Raw
  - 输出：`category_code`、长度、hex 预览、原始字节
  - 第二阶段：若后续 ETG / 参考实现出现稳定布局，再单独建 typed model
- Dictionary (80)
  - 第一阶段：识别并导出 raw bytes
  - 第二阶段：仅在明确布局后做只读 view，不与 CoE 在线对象字典浏览耦合
- Hardware (90)
- Vendor Information (100)
- Images (110)
  - 统一策略：先保留和导出，再按实际样本决定是否值得做 typed view

验收：

- 这些类别在 JSON 中不再只是 `Raw Category XXXX`，而是明确显示标准类别名
- 仍然不伪造不存在的结构字段

### Phase 4：厂商/应用扩展类别框架

目标：为真实设备样本建立“可扩展但不污染核心”的深读挂载点。

- 在 `Raw` 之上增加分类字段：
  - `standard-unknown`
  - `device-specific`
  - `vendor-specific`
  - `application-specific`
- CLI 与 JSON 输出暴露：
  - `type_code`
  - `category_class`
  - `byte_length`
  - `preview_hex`
- 后续若 Renesas / Beckhoff / 其他样本证明某类扩展 section 稳定，再通过单独模块做 typed overlay

### Phase 5：参考比对与实机证据

目标：把“类别深读”从代码正确推进到结果可核对。

- 与 siitool 对比：
  - fixed header
  - strings
  - general
  - sync manager
  - PDO
  - DC
- 与 EtherCAT.net.ui_sii 对比：
  - XML -> EEPROM 投影后能否在 MoonECAT 中稳定回读同类字段
- 与 ethercrab 对比：
  - identity / general / strings / sync manager / fmmu / fmmu_ex / PDO 的运行时高价值字段
- Native 证据：
  - 至少一条 `scan -> read-sii --json -> run`
  - 至少一条 `esi-sii -- --esi-json ...` 与 `read-sii --json` 的字段对照样本

## 6. 输出模型要求

### 6.1 JSON 输出

- 固定头字段完整输出
- 每个 category 必须输出：
  - `category`
  - `title`
  - `category_code`
  - `known`
  - `byte_length`
  - `preview_hex`
- typed category 额外输出结构化字段
- 未深读标准类别与厂商类别至少输出原始字节或可截断预览

### 6.2 文本输出

- 继续面向人工诊断
- 已知类别打印结构化字段
- 未知/扩展类别至少打印：编号、长度、hex 预览

## 7. 验证策略

- fixture：继续用合成 EEPROM 做 parser 单元测试
- 受控 NIC：模拟在线 EEPROM 读回，锁定 scan / identity 回归
- 真机：至少覆盖 `scan -> read-sii --json -> run`
- 参考比对：
  - 与 siitool 对比 header / category 解析结果
  - 与 EtherCAT.net.ui_sii 对比 General / SM / PDO / mailbox 投影
  - 与 ethercrab 对比运行时高价值 section 的解释结果

## 8. 当前状态与下一批执行项

### 2026-03-23 交付摘要

本轮 SII 深读框架已经形成一条完整提交链，代码提交与对应回填如下：

1. `ebbaf31` `feat(sii): share aggregated full-info model`
   - 引入 `SiiFullInfo`
   - 把 `read-sii` / `esi-sii` / runtime startup / mailbox mapping 收口到同一份聚合结果
2. `165603d` `docs(workflow): backfill sii aggregate model`
   - 回填共享聚合模型的 workflow 映射、阶段状态与验证证据
3. `45b7217` `feat(protocol): auto-expand complete sii reads`
   - 在 protocol 层公开 `read_sii_bytes` / `read_sii_bytes_ap`
   - 让在线路径可按 EEPROM size 自动扩展为完整镜像读取
4. `bc16d3b` `docs(workflow): backfill complete sii read chain`
   - 回填在线完整 EEPROM 补读链路的 workflow 证据
5. `5b8f96e` `feat(sii): recognize standard reserved categories`
   - 把 20/80/90/100/110 从普通 `Raw` 提升为显式标准保留类别
   - JSON / 文本输出稳定显示类别名，同时保留 raw bytes
6. `092352e` `docs(workflow): backfill standard sii categories`
   - 回填标准保留类别识别的 workflow 映射与验证证据
7. `ff93f64` `feat(sii): export category classes`
   - 导出 `category_class`
   - 把 `Raw` 细分为 `standard-unknown` / `device-specific` / `vendor-specific` / `application-specific`
8. `332b8b8` `docs(workflow): backfill sii category classes`
   - 回填 category class 导出的 workflow 状态与完成结论
9. `ca0a906` `feat(sii): add raw category overlay hook`
   - 引入 `SiiOverlayScope` / `SiiOverlayCandidate`
   - 为扩展 raw category 增加 `overlay_candidate()` 与稳定 `overlay_key`
10. `0346be1` `docs(workflow): backfill raw sii overlay hook`
   - 回填 overlay hook 的 workflow 映射、阶段状态与验证证据
11. `41e1442` `test(mailbox): disambiguate category class label`
   - 修复 `moon test` 中 `VendorSpecific` 构造器歧义，恢复全量回归通过

交付结果不是单个 parser 增量，而是一条稳定产品链：

- 在线读取：可以从最小探测窗口自动扩展到完整 EEPROM
- 聚合模型：CLI / runtime / offline projection 不再各自重复遍历 category
- 标准保留类别：20/80/90/100/110 已脱离普通 Raw，进入稳定导出面
- 扩展类别：vendor/application/device-specific 现已有 `category_class`、`overlay_candidate()` 与 `overlay_key`，后续可继续叠加 typed overlay

验证证据：

- `moon test protocol` `111/111`
- `moon test cmd/main` `70/70`
- `moon test runtime` `105/105`
- 后续聚合回归 `moon test` `187/187`（mailbox + cmd/main + runtime）
- 最新全量回归 `moon test` `414/414`

### 当前已落实

- `scan` 已改为优先从 SII EEPROM header 读取 identity
- 标准 fixed header 已覆盖 Vendor Info 与 ESC Configuration Area B
- 已深解析类别覆盖 10/30/40/41/42/43/50/51/60/70
- 已保留未知 category 的 `type_code + raw bytes`
- `read-sii` / `esi-sii` 已输出稳定 JSON / 文本结构
- 标准保留类别 20/80/90/100/110 已有显式类别名与稳定导出面
- 扩展 raw category 已有 `category_class` 与 `overlay_key`，可作为 typed overlay 的统一挂载点

### 后续建议方向

1. 基于 `overlay_key` 为真实样本落第一个 vendor-specific typed overlay
2. 为 `DataTypes` / `Dictionary` / `Hardware` / `Vendor Information` / `Images` 选择是否继续增加只读 typed view
3. 补 `read-sii --json` 与 `esi-sii` / 参考实现的字段对照证据

到这一步，MoonECAT 的 SII 已经从“只覆盖关键运行时类别”推进到“完整类别深读框架已建立，可继续按样本叠加增量解析”的状态。