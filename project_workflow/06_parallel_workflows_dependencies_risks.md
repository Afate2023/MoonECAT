# MoonECAT 并行工作流、依赖顺序与风险清单

本文件由原 AI 任务清单拆分整理而来，对应原第 4、5、6 节。

## 4. 并行工作流

### HAL

- [x] 固化跨平台最小接口和错误模型。
- [x] 先完成 `Mock Loopback`，再补单一真实平台原型。
- [ ] 落地 Native 后端：Linux Raw Socket 优先，Windows Npcap 与同一 HAL 契约对齐。
- [ ] 落地 Extism / WASM Host Adapter：通过宿主函数与共享内存映射 `Nic/Clock/FileAccess`。
- [ ] 为 RTOS/Embedded 保留与 Native / Extism 不冲突的 HAL 扩展位。

### Protocol Core

- [x] 完成帧、PDU、寻址、拓扑和错误模型。
- [x] 完成 ESM 状态机和错误回退。
- [ ] 约束热路径分配行为。

### Mailbox & Config

- [x] 完成 SII/ESI 解析和配置对象生成。
- [x] 完成 FMMU/SM 自动配置。
- [x] 完成 CoE/SDO 请求队列和状态推进。
- [x] 完成 Mailbox Resilient Layer (RMSM)。
- [x] 完成 Emergency Message 接收。
- [ ] 继续补 ENI 导入的配置工具数据模型，使 online/offline 两条配置来源在共享校验路径之外，进一步共享 SM/FMMU/PDO/诊断摘要等更完整配置语义。
- [ ] 把已完成的 SDO Info / Complete Access / segmented 能力上浮到 CLI / 配置工具表面，形成稳定的对象字典浏览输出。
- [ ] 补拓扑指纹与 Hot Connect group/optional segment 配置模型，使配置工具可表达“必选链路”与“可选链路”而不新增第二套校验语义。
- [x] 补 SII category 深度解码与稳定 JSON 结构，支撑 `read-sii`、offline config 和配置工具共用更完整的 EEPROM/ESI 语义。已于 2026-03-22 先按 ETG.2010 补齐 `Timeouts(70)`、AoE mailbox bit、`CurrentOnEBus` signed decode 和 `esi-sii` AoE 投影保真（commit: `cdac077`）；同日继续补齐 `FMMUX(42)`、`SyncUnit(43)`、未知 category 原始保留、Vendor Info、ESC Config Area B 和 dynamic process-data `SM type 0x05/0x06`，并让 `read-sii` JSON/文本输出消费同一扩展模型（commit: `43b36e8`）。随后再引入共享 `SiiFullInfo` 聚合模型，把 CLI `read-sii`、offline `esi-sii`、runtime startup 和 mailbox mapping 全部切到同一份 SII 派生结果（commit: `ebbaf31`）。2026-03-23 又把 ownership + 32/64-bit EEPROM 读取扩展链路收口为 protocol 级 `read_sii_bytes` / `read_sii_bytes_ap`，使 `read-sii` 可在给定初始窗口后自动补读完整 EEPROM（commit: `45b7217`）；随后继续把 20/80/90/100/110 提升为显式标准保留类别并接入 parser / CLI / offline projection 的稳定标题与 known 标志（commit: `5b8f96e`）；最后再导出 `category_class` 并把 Raw 分类细分为 `standard-unknown` / `device-specific` / `vendor-specific` / `application-specific`（commit: `ff93f64`）。验证：`moon test protocol` `111/111`、`moon test cmd/main` `70/70`、`moon test runtime` `105/105`、后续定向回归 `moon test` `187/187`（mailbox + cmd/main + runtime）。

### Runtime

- [x] 完成运行时调度器框架和 Telemetry 指标。
- [x] 完成 PDO pdo_exchange 实体实现。
- [x] 完成 mailbox 推进、超时治理和背压控制。
- [ ] 先在 Native 后端完成 Free Run 真实链路闭环，再逐步增强 DC 集成验证。
- [x] 为 Extism / WASM 路径补一套不改变语义的回放式运行编排验证。
- [x] 在拓扑差异、WKC 异常、AL Status/AL Code、Diagnosis History 基础上形成统一诊断汇聚模型，服务 CLI / Library / 配置工具。
- [ ] Free Run / DC 稳定后评估 Multiple Tasks 与 process image 分区，不提前引入第二套调度语义。
- [ ] 把拓扑差异分级扩展到 Hot Connect / optional segment，保证 runtime 继续独占 `Pass/Warn/Block` 与 difference category 的裁定逻辑。
- [ ] 为 Native 长链 smoke 固化启动前后状态、诊断 surface 与运行时 telemetry 的联合回归，避免后端验证长期停留在单命令 smoke。

### CLI/Library

- [x] 固化共享核心实现，不做双实现。
- [x] 完成 `scan/validate/run` 库层接口。
- [x] 接入 CLI 实际命令。
- [x] 统一命令输出和库层结果对象。
- [x] 增加面向配置工具的统一数据表面：ENI 导入结果、对象字典浏览结果、拓扑差异报告、主站对象字典视图。

### 文档与测试

- [x] 维护开发文档和回归夹具。
- [x] 建立单元测试和夹具测试 (~163 tests)。
- [x] 建立流程回放和最小集成测试。
  - ✅ [runtime/runtime_test.mbt](../runtime/runtime_test.mbt): `replay integration minimal flow: scan->validate->run->stop`
  - ✅ commit: `898616e` `test(runtime): add minimal replay integration flow`
- [x] 持续把参考分析文档转成实现约束和验收标准。
  - ✅ [docs/REFERENCE_CONSTRAINTS.md](../docs/REFERENCE_CONSTRAINTS.md): 建立“参考调用流 -> 实现约束 -> 测试验收”映射矩阵
  - ✅ commit: `bc236ed` `docs: map reference callflows to constraints and tests`

## 5. 依赖顺序

- [x] 先完成 M1，再进入 M2。
- [x] 先完成帧/PDU 闭环，再进入扫描和配置计算。
- [x] 先形成拓扑和配置对象，再进入 PDO 和 Runtime。
- [x] 先形成 Runtime 主循环，再完成 `run` 命令和 SDO 整合。
- [x] CLI 只能复用核心库，不能先实现命令再反推库接口。
- [x] DC 相关能力不能阻塞 Free Run 最小可用版本。
- [ ] 先完成 Native FFI 包脚手架，再分别落 Linux Raw Socket / Windows Npcap 绑定。
- [ ] 先冻结 Native HAL 错误语义与句柄生命周期，再开放 CLI 在真实后端上的 smoke 验证。
- [x] 先冻结 ENI / online scan 的统一配置对象模型，再开放配置工具或网页工作台入口，避免形成第二套配置语义。
- [x] 先冻结 Extism 请求/响应信封和 host capability contract，再落共享内存优化。
- [x] Extism / WASM 只能包装既有库入口，不能先写插件逻辑再反推 `runtime/` 改接口。

## 6. 风险检查清单

### GC 抖动

- [x] 检查热路径是否存在不必要分配。
  - ✅ [runtime/runtime_test.mbt](../runtime/runtime_test.mbt) `Pressure: free-run core loop remains stable at high cycle count`（1000 周期稳定计数）
- [x] 对核心循环建立压力回归。
  - ✅ [runtime/runtime_test.mbt](../runtime/runtime_test.mbt) `Pressure: timeout-heavy loop keeps accounting consistent`
- [x] 跟踪不同负载下的周期稳定性和错误率。
  - ✅ [runtime/runtime_test.mbt](../runtime/runtime_test.mbt) `Pressure: telemetry remains monotonic across different loads`
  - ✅ commit: `e4bff92` `test(runtime): add pressure regression coverage for core loop`

### 平台接口碎片化

- [x] 检查新增平台后端是否污染 Protocol Core。（当前仅 Mock，接口隔离良好）
- [x] 保证同一组核心测试可复用于不同 HAL。
- [ ] Native 后端接入前先验证 HAL 接口是否足够稳定。
- [x] Extism / WASM 适配前先冻结 host capability contract 与请求/响应信封格式。
- [x] Native 与 Extism 两条路径共用同一组 scan/validate/run 语义验收，不允许演化出双语义。

### FFI / 宿主边界

- [x] 检查 Native FFI 中所有非 primitive 参数是否已标注 `#borrow` / `#owned`，避免默认语义漂移。
  - ✅ [hal/native/windows_npcap_ffi.mbt](../hal/native/windows_npcap_ffi.mbt) 与 [hal/native/linux_raw_socket_ffi.mbt](../hal/native/linux_raw_socket_ffi.mbt) 的 `Bytes` 输入均已显式标注 `#borrow`
- [x] 检查所有外部句柄是使用 finalizer external object 还是 `#external type`，并为每类句柄记录释放责任。
  - ✅ 当前采用“整数句柄 ID + C stub 内部句柄表”策略，释放责任已记录在 [docs/NATIVE_FFI_SAFETY.md](../docs/NATIVE_FFI_SAFETY.md)
- [x] 检查 `.c` stub、`native-stub`、`targets` 配置是否只作用于 Native 路径，不破坏 wasm-gc 构建。
  - ✅ [hal/native/moon.pkg](../hal/native/moon.pkg) 已将 FFI 文件限制在 `native`，fallback 文件限制在 `wasm-gc`
- [x] 检查 Extism 宿主是否只暴露 HAL 等价能力，不把对象字典、ESM、PDO 语义上推到宿主。
- [ ] 检查共享内存协议是否明确长度、所有权、超时与回收责任，避免 run 路径出现隐式复制与悬垂缓冲区。

### 状态机死锁

- [x] 覆盖 Init、PreOp、SafeOp、Op 以及错误回退路径。
- [x] 覆盖超时、重试、链路异常和配置不一致场景。
  - ✅ 超时/链路异常: [runtime/runtime_test.mbt](../runtime/runtime_test.mbt) `Recovery: run_cycles records RecvTimeout and continues` + `Runtime run_cycle propagates LinkDown on broken NIC`
  - ✅ 配置不一致: [runtime/runtime_test.mbt](../runtime/runtime_test.mbt) `run with mock loopback: validation fails when slaves expected but not found`
  - ✅ 重试边界: [mailbox/mailbox_test.mbt](../mailbox/mailbox_test.mbt) `Rmsm record_timeout allows retries up to max`
  - ✅ commit: `97845a4` `test(runtime): cover timeout and link-down recovery paths`
- [x] 检查 mailbox 推进和 PDO 热路径是否仍然解耦。
  - ✅ [runtime/runtime_test.mbt](../runtime/runtime_test.mbt) `Decoupling: mailbox diagnosis failure does not block PDO run loop`
  - ✅ commit: `5f7629a` `test(runtime): verify mailbox and PDO path decoupling`
