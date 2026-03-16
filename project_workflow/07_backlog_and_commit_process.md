# MoonECAT 主线 Backlog 与提交方式

本文件由原 AI 任务清单拆分整理而来，对应原第 9 节与第 10 节。

## 9. 主线 Backlog 与完成判定

当前主线 backlog（按依赖顺序）：

1. **配置工具 / ENI 主线**：完成 [02_productization_tracks.md](./02_productization_tracks.md) 中的统一配置对象、差异报告与 ENI 导入边界。
2. **对象字典浏览产品化**：完成 [02_productization_tracks.md](./02_productization_tracks.md) 中的 CLI / JSON 浏览表面与错误分类。
3. **主站对象字典与统一诊断表面**：完成 [02_productization_tracks.md](./02_productization_tracks.md) 中的统一结果对象、分层诊断汇聚与告警等级。
4. **拓扑变化 / Hot Connect**：把显式设备标识扩展成稳定的拓扑差异与 Hot Connect 分组能力。
5. **Native 后端首版收口**：真实网卡恢复可用后，补齐 Native `scan/validate/run` 闭环、错误语义冻结与内存安全检查。
6. **Extism / WASM 产品化**：在前述模型稳定后，补宿主入口、共享内存路径与最小集成回放。
7. **SII 全量产品面**：把 `read-sii` 从最小在线诊断入口扩展到稳定 category 深读与配置工具可复用 JSON。

主线完成判定：

- [ ] 0.3、0.4、0.5 三个拆解节的验收标准全部完成。
- [ ] `scan`、`validate`、`state`、`diagnosis`、对象字典浏览与配置差异报告形成统一 CLI / JSON 输出规范。
- [ ] Native 与 Extism 两条产品面共享同一配置对象、诊断对象和错误分类。
- [x] [MoonECAT项目申报书.md](../MoonECAT项目申报书.md) 中 Phase 2、Phase 3、Phase 4 的证据项全部从“进行中/未开始”更新为已完成或已验证。

## 10. 提交执行方式

- 每完成一个"建议提交拆分"条目，就单独 `git add` 对应文件并提交。
- 新增能力先补 Section 8 的“参考实现（本地代码）/ MoonECAT 对应实现”，再落测试与实现；缺少映射时不直接编码。
- 提交前先运行本次改动对应的最小验证；文档改动至少检查链接、标题和任务编号是否一致。
- 完成后更新本文档对应条目的 `[ ]` → `[x]` 并注明 commit hash。
