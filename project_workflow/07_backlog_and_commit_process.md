# MoonECAT 主线 Backlog 与提交方式

本文件由原 AI 任务清单拆分整理而来，对应原第 9 节与第 10 节。

> **权威来源**：三条主线（A/B/C）完整路线图与 L1-L4 成熟度审计已整合进 [08_integrated_roadmap_and_backlog.md](08_integrated_roadmap_and_backlog.md)。本文件维护 **可执行 Backlog** 与提交方式规范。

## 9. 主线 Backlog 与完成判定

当前主线 backlog（按优先级 P0→P2 排列，对齐 08 文件三条主线）：

### P0 · 主线 A — Native Runtime Baseline

1. **Native 后端首版收口**：在现有真实链路闭环基础上，补齐错误语义冻结与 AddressSanitizer / 等价内存安全检查命令。
2. **SII 全量产品面**：`read-sii` 深度解码框架已闭环 ✅（含 overlay hook、category class、decoder 状态合同）；后续仅剩厂商样本挂接。

### P1 · 主线 B — Verification Runtime

3. **拓扑变化 / Hot Connect**：显式标识 + 别名 + 4-tuple + 可选组分级已落地，仍缺 optional/mandatory 双分支实机证据。
4. **事件溯源验证引擎**：定义 EventStream 采集边界 → Replay 幂等性 → Monitor/Verdict 最小合同（新增，源自 08 文件主线 B）。

### P2 · 主线 C — HIL-Ready Runtime Boundary

5. **Extism / WASM 产品化**：在现有 envelope + Mock 回放基础上，补宿主入口、bytes-only 输入、共享内存路径与最小集成回放。
6. **HIL 测试拓扑定义**：至少 1 从站 + 1 实时 NIC 的最小硬件在环验证流程（新增，源自 08 文件主线 C）。

主线完成判定（以 L1-L4 成熟度为标尺）：

- [x] **L1-L2 全量完成**：0.3、0.4、0.5 三个拆解节验收标准全部完成；Class B 17/17 = 100%。
- [x] **L3 产品面闭合**：`scan`、`validate`、`state`、`diagnosis`、OD 浏览与配置差异报告形成统一 CLI / JSON 输出规范。
- [ ] **L4 验证加固**：Native 与 Extism 两条产品面共享同一配置对象、诊断对象和错误分类；事件溯源 Replay 幂等性验证通过。
- [x] [MoonECAT项目申报书.md](../MoonECAT项目申报书.md) 中 Phase 2、Phase 3、Phase 4 的证据项全部从“进行中/未开始”更新为已完成或已验证。

## 10. 提交执行方式

- 每完成一个"建议提交拆分"条目，就单独 `git add` 对应文件并提交。
- 新增能力先补 Section 8 的“参考实现（本地代码）/ MoonECAT 对应实现”，再落测试与实现；缺少映射时不直接编码。
- 提交前先运行本次改动对应的最小验证；文档改动至少检查链接、标题和任务编号是否一致。
- 完成后更新本文档对应条目的 `[ ]` → `[x]` 并注明 commit hash。
- 代码提交完成后，如影响 `project_workflow` 中的“建议提交拆分/提交映射/验收证据”，需在同一轮工作内回填对应 commit hash；只有文档必须引用代码提交号且需要单独评审时，才拆成后续 docs commit。

提交后固定回填表单：

- `本次代码提交`: `<hash>` `<type(scope): summary>`
- `对应 workflow 文件`: `<project_workflow/xx_*.md>`
- `建议提交拆分`: 把对应条目标记为已完成，或在条目后补 `commit: <hash>`
- `提交映射`: 补一行 `` `能力/条目名` → `<hash>` `<subject>` ``
- `当前状态/最新回填/验收证据`: 若本次提交改变了阶段状态、实机结论、测试结论或使用方式，同步改写对应段落，不只补 hash
- `最近回填`: 在本文末尾追加一行，保持最近几次提交可追踪
- `是否拆 docs commit`: 默认 `否`；只有文档需要独立评审、且必须引用刚产生的代码 hash 时才拆开

执行顺序固定为：最小验证 → 代码提交 → 回填对应 workflow 内容 → 视需要单独提交 docs。不要把“先提交代码，之后有空再补 workflow”当成可接受流程。

最近回填：

- `Mock FMMU 逻辑 PDO 路由与多从站回归` → `e1fee13` `feat(mock): add FMMU logical PDO routing`
- `Raw SII overlay decoder 状态合同` → `b024aec` `feat(sii): expose overlay decoder status`
- `Raw SII category overlay 挂载点` → `ca0a906` `feat(sii): add raw category overlay hook`
- `SII category class 导出` → `ff93f64` `feat(sii): export category classes`
- `标准保留 SII 类别识别` → `5b8f96e` `feat(sii): recognize standard reserved categories`
- `在线完整 EEPROM 补读链路` → `45b7217` `feat(protocol): auto-expand complete sii reads`
- `SII 聚合模型共享到 CLI/runtime/offline mapping` → `ebbaf31` `feat(sii): share aggregated full-info model`
- `启动恢复共享入口 + SO mailbox 启动命令 + ESC 映射诊断` → `b3b0717` `Refine startup recovery and ESC mapping diagnostics`
- `Native 自动选卡 + 省略站号广播覆盖` → `5c4dd51` `test(cli): cover native auto-select and broadcast state`
- `严格 ESM 路径接入 state/run` → `e143fce` `feat(esm): wire strict transitions into state and run`
- `Native run Op 启动顺序 + mailbox SM 启动映射修复` → `a4cb887` `fix(runtime): stabilize native op startup sequencing`
- `Native run 长跑控制 + 连续超时故障 + CLI 周期参数` → `71f178e` `feat(runtime): add long-run controls and timeout faults`
- `Native 自动选卡探测 + scan 站地址策略切面` → `bff2f5e` `feat(native): auto-probe interfaces and extract scan strategy`
- `ActivePdoLengthsNic sm_windows 类型/初始化修复` → `5658372` `fix(runtime): update sm_windows type and initialization for ActivePdoLengthsNic`
- [历史回填] M1 包结构/HAL/测试骨架 hash 补齐 → `daf1957`/`fb12340`/`4921fdf`
- [历史回填] M3 按站地址位置校验边界测试 → `a6069bb`
- [历史回填] M5 SDO validate_response 丢帧修复 + mailbox retry → `5d54aca`/`fe1e2ef`
- [历史回填] M6 Identification 强化 + AP 诊断 + Diagnosis 增强 → `9284ede`/`b70b5e2`/`2fdf472`
- [历史回填] M8 Native 后端: Npcap 列举/errno 分类/stdio.h/AP noise/startup prep/process data/DC prep/ndjson/preop retry/启动诊断 → `6682636`/`2058971`/`cef8362`/`75b35a4`/`82f6b7e`/`f5644c5`/`75328b7`/`0bda199`/`23c85c1`/`013da5a`/`136466b`
- [历史回填] M8 SII: UTF-8 解码/TxRxPDO 渲染/siitool 对齐/category label → `033b859`/`462bed5`/`c853946`/`41e1442`
- [历史回填] M8 ENI/配置/诊断: 统一配置模型/ENI XML 投影/差异分级/摘要扩展/ESI JSON 桥/ESI SII 视图/ESI 启动接入/诊断超时/统一诊断/Hot Connect → `d2ba48d`/`fa82594`/`6f4241a`/`121cafa`/`1e23be5`/`3330009`/`76a40c7`/`da2c54b`/`d7e6c6a`/`0a602b2`
