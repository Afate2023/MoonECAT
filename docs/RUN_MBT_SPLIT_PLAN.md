# `runtime/run.mbt` 拆分计划（Plan-Only）

> 本文档为**纯计划**，不在本轮提交动 `run.mbt` 实际代码。落地前需要至少
> 一次单独的 PR 评审，并配合 `moon info` 的 `.mbti` 0-diff 校验。

## 1. 现状

- 文件：`runtime/run.mbt`
- 行数：**3079 行**（截至本计划撰写时）
- 角色：聚集了 EtherCAT 主站从启动准备 → 配置 → 周期运行 → 收尾的几乎所有
  公共入口；同时混杂大量私有助手（mailbox 命令派发、PDO 重映射、DC 周期
  推断、ESM 转换决策、报告格式化）。
- 测试：`runtime/run_test.mbt`、`runtime/runtime_test.mbt` 通过 blackbox
  测试覆盖 `pub fn` 入口；同包内 `_wbtest.mbt` 调用部分私有函数。

## 2. 拆分目标

按 **EtherCAT 启动到运行的阶段** 切分文件，使每个文件围绕一个明确的
"业务相位"组织：

| 新文件                               | 业务相位                                | 内容范围                                                                       |
| ------------------------------------ | --------------------------------------- | ------------------------------------------------------------------------------ |
| `runtime/run_types.mbt`              | 公共类型 / 枚举                         | `RunPhase`, `RunFault`, `RunLoopSettings`, `RunReport`, `SlaveStartupPreparation`, `RunStartupPreparation`, `StartupCommandTransition`, `StartupMailboxCommand`, `StationStartupMailboxPlan`, `SmWatchdogValidation` |
| `runtime/run_startup_prepare.mbt`    | 启动准备（SII/ESI → preparation）       | `build_run_startup_preparation`, `prepare_slave_startup`, `startup_preparation_from_esi_offline_report`, `startup_preparation_from_esi_json`, `run_startup_preparation_from_slave_preparations`，及对应私有助手（`merge_startup_mailbox_commands`, `derive_startup_mailbox_commands`, `derive_startup_outputs*`, ds402 mode seed 派系函数等） |
| `runtime/run_configure.mbt`          | 配置阶段（PreOp / SafeOp 邮箱命令应用） | `refine_startup_preparation_in_preop`, `apply_startup_mailbox_commands`, `apply_presafeop_startup_mailbox_commands`, `apply_safeop_startup_mailbox_commands`, `write_mailbox_mapping`, `write_process_data_mapping`，及 `mailbox_sm_*`, `find_pdo_entry_byte_offset`, `expected_wkc_from_slave_mappings` 等私有助手 |
| `runtime/run_loop.mbt`               | 周期运行（`run` / `run_with_*` 入口）   | `run`, `run_with_settings`, `run_with_settings_reporting_to`, `run_until_fault`, `run_with_states`, `run_with_states_until_fault`, `run_with_states_and_settings`, `run_with_states_and_settings_prepared_reporting_to`, `run_with_scan_and_states_and_settings_prepared_reporting_to`, `run_with_states_and_settings_reporting_to`，以及 `build_operational_startup_steps`, `classify_startup_recovery_strategy`, `runtime_fault_from_runtime`, `resolve_run_loop_config`, `resolve_progress_every_cycles` |
| `runtime/run_report_format.mbt`      | 报告格式化                              | `RunReport::format`, `run_fault_text`，及任何只服务于报告渲染的私有助手        |
| `runtime/run.mbt`（保留为门面）       | 文档 + re-export                        | 仅放包级文档注释，避免外部引用断裂；类型与函数仍按 MoonBit 包语义对外可见       |

> **注**：实际行号区间需在落地 PR 中以 `moon ide outline` 重新确认；上表
> 是按当前文件 `Select-String` 出来的符号顺序得到的近似分组，落地时若发
> 现某个私有助手被多个文件引用，则保留在 `run_types.mbt` 或新建一个
> `runtime/run_internal.mbt`（下文 §5 兜底策略）。

## 3. 公共 API（`.mbti`）影响分析

按 MoonBit 模块语义，`runtime` 包的 `.mbti` 由该包**所有 `.mbt` 文件**汇总
生成，与文件切分无关。因此预期：

- `runtime/pkg.generated.mbti` **0 行变更**（即 `moon info && moon fmt`
  之后 git diff 必须为空）。
- 所有现有 `pub fn` 签名保持不变，包括 `run_with_*` 系列、
  `RunLoopSettings::*`、`RunReport::format`。
- 内部 `fn` 仍然只在包内可见，跨文件直接调用合法（同包内）。

校验方法：

```powershell
# 落地后强制校验
git diff --exit-code runtime/pkg.generated.mbti
```

若 `.mbti` 出现 diff，说明某个被外部依赖的符号意外发生了 visibility 或
签名变化，必须回滚到拆分前的边界。

## 4. 测试影响

- **Blackbox 测试**（`runtime/run_test.mbt` 等以 `_test.mbt` 结尾且声明
  `package "MoonECAT/runtime"` 的文件）：仅依赖 `pub fn`，零修改。
- **Whitebox 测试**（`runtime/*_wbtest.mbt`）：可直接访问私有 `fn`。
  拆分后所有私有 `fn` 仍在 `runtime` 包内，故仍可访问，但需确认无文件级
  循环依赖。
- 落地后必跑：

  ```powershell
  moon test
  moon test --target native
  ```

  期望与拆分前**测试结果与覆盖率完全一致**（`scripts/regression-real-device.ps1`
  与 `replay-diff.ps1` 在拆分前/后各跑一次，输出 NDJSON header / verdict
  必须 byte-by-byte 一致）。

## 5. 兜底策略：跨文件私有依赖

部分私有助手会被多个新文件引用（典型如 `mailbox_sm_*`、`bytes_match_at_offset`、
`decode_le_u32_payload`）。拆分时按以下顺序处理：

1. 优先归属到**唯一调用方**所在文件。
2. 若有 ≥2 个新文件调用，则升入 `runtime/run_internal.mbt`（不导出）。
3. 严禁为了拆文件而将私有 `fn` 改成 `pub fn` —— 这类变化必须有独立的
   API review。

## 6. 落地分步（建议提交序列）

为了让每一步都有独立的 PR 可审，建议按**抽取 → 编译 → 测试 → 提交**
的循环，每次只移动一个新文件的内容：

| Step | PR 主题                        | 移动到                           | 验收                                |
| ---- | ------------------------------ | -------------------------------- | ----------------------------------- |
| S1   | 抽取公共类型                   | `run_types.mbt`                  | `moon info` 0-diff，全部测试通过    |
| S2   | 抽取启动准备                   | `run_startup_prepare.mbt`        | 同上                                |
| S3   | 抽取配置阶段                   | `run_configure.mbt`              | 同上 + 真机回归（item 1 脚本）     |
| S4   | 抽取周期运行入口                | `run_loop.mbt`                   | 同上                                |
| S5   | 抽取报告格式化 + 文件清空      | `run_report_format.mbt` / `run.mbt` 仅留文档 | 同上 + `replay-diff.ps1` 跑通 |

每一步都要求：

- `moon check` / `moon check --target native` 干净；
- `moon info && moon fmt` 后 `pkg.generated.mbti` 与 `.mbt` 排版无非预期 diff；
- `moon test` 全绿；
- 真机回归（如可用）verdict 与拆分前一致。

## 7. 不在本计划范围

- `Runtime` 结构体本身（在 `runtime/runtime.mbt`）的拆分。
- `RunProgressSink` 协议族的重组。
- 任何对外 API 的语义改动（参数顺序、错误类型、字段命名）。
- ESM / DC / mailbox 子模块的进一步分包。

以上内容若日后需要，**必须**走独立设计 + API review 流程，与本计划解耦。
