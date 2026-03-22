# MoonECAT 主线 Backlog 与提交方式

本文件由原 AI 任务清单拆分整理而来，对应原第 9 节与第 10 节。

## 9. 主线 Backlog 与完成判定

当前主线 backlog（按依赖顺序）：

1. **拓扑变化 / Hot Connect**：把显式设备标识扩展成稳定的拓扑差异与 Hot Connect 分组能力，并补 optional/multiple-slave 场景的 Native 实机证据。
2. **Native 后端首版收口**：在现有真实链路闭环基础上，补齐错误语义冻结与 AddressSanitizer/等价内存安全检查命令。
3. **Extism / WASM 产品化**：在现有 envelope + Mock 回放基础上，补宿主入口、bytes-only 输入、共享内存路径与最小集成回放。
4. **SII 全量产品面**：把 `read-sii` 从最小在线诊断入口扩展到稳定 category 深读、字符串解码一致性与配置工具可复用 JSON。

主线完成判定：

- [x] 0.3、0.4、0.5 三个拆解节的验收标准全部完成。
- [x] `scan`、`validate`、`state`、`diagnosis`、对象字典浏览与配置差异报告形成统一 CLI / JSON 输出规范。
- [ ] Native 与 Extism 两条产品面共享同一配置对象、诊断对象和错误分类。
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

- `标准保留 SII 类别识别` → `5b8f96e` `feat(sii): recognize standard reserved categories`
- `在线完整 EEPROM 补读链路` → `45b7217` `feat(protocol): auto-expand complete sii reads`
- `SII 聚合模型共享到 CLI/runtime/offline mapping` → `ebbaf31` `feat(sii): share aggregated full-info model`
- `启动恢复共享入口 + SO mailbox 启动命令 + ESC 映射诊断` → `b3b0717` `Refine startup recovery and ESC mapping diagnostics`
- `Native 自动选卡 + 省略站号广播覆盖` → `5c4dd51` `test(cli): cover native auto-select and broadcast state`
- `严格 ESM 路径接入 state/run` → `e143fce` `feat(esm): wire strict transitions into state and run`
- `Native run Op 启动顺序 + mailbox SM 启动映射修复` → `a4cb887` `fix(runtime): stabilize native op startup sequencing`
- `Native run 长跑控制 + 连续超时故障 + CLI 周期参数` → `71f178e` `feat(runtime): add long-run controls and timeout faults`
- `Native 自动选卡探测 + scan 站地址策略切面` → `bff2f5e` `feat(native): auto-probe interfaces and extract scan strategy`
