# Native Real-NIC State Transition Design

> **实现状态（2025-07）**：ESM 状态迁移引擎已全面实现于 `protocol/esm_engine.mbt` + `protocol/esm_extensions.mbt`，包含 `request_state`（10+ 目标状态变体）、`transition_through`、`broadcast_state`、`observe_state_transition`，支持 timeout policy 和 override。CLI `state` 命令已实现广播与定点迁移。Windows Npcap 实机验证已通过。Linux 实机验证待补。

本文档聚焦两件仍在推进中的 Native 主题：

- Linux Raw Socket 后端从“可编译骨架”走向“可实机闭环”的完善项
- Windows Npcap 实机链路上，从 `scan/run` 扩展到 EtherCAT 从站 ESM 状态迁移的运行设计

## 1. 当前基线

当前仓库已经具备：

- Windows Npcap 的 `list-if -> scan -> validate -> run` 空总线 smoke 路径
- Npcap 实机扫描中的非零从站身份恢复
- Native CLI 在线 `read-sii`
- 新增 CLI `state` 命令，可通过 Native 后端触发 EtherCAT 从站状态迁移

当前仓库尚未完全具备：

- Linux Raw Socket 的实机回归闭环与错误分类细化
- Npcap 实机 `run` 路径与 ESM 定点确认迁移之间的统一策略
- 广播迁移与定点确认迁移的明确操作边界文档

## 2. Linux Raw Socket 完善项

Raw Socket 后端下一阶段的完成标准，不是“已有 open/send/recv 包装”，而是以下能力全部闭环：

1. 接口枚举结果稳定化

- 输出接口索引、名称、是否 up/running、MTU 的结构化字段
- 与 CLI `list-if --json` 输出格式保持一致

2. 接收路径错误语义细化

- 区分 `EAGAIN/EWOULDBLOCK` 到 `RecvTimeout`
- 区分 `ENETDOWN/ENODEV` 到 `LinkDown`
- 其它 socket 错误归类到 `RecvFailed(...)`

3. 发送路径与回显过滤一致化

- 保持与 Npcap 路径同样的自发包过滤策略
- 避免把本机发出的 EtherCAT 帧误当作从站响应

4. 实机 smoke 闭环

- 至少完成 Linux 上的 `list-if -> scan -> validate -> run`
- 若无从站，空总线结果仍应稳定返回 `0 slaves / PASS / Done`

5. ESM 迁移闭环

- 支持 CLI `state` 命令在 Raw Socket 后端发起广播迁移
- 支持按站地址进行定点 `request_state` / `transition_through`
- AL Status / AL Status Code 读回失败时保持明确错误分类

## 3. Npcap 实机 run 与状态迁移设计

Windows Npcap 实机路径需要区分两类状态迁移：

### 3.1 广播迁移

适用场景：

- 总线级统一切换到 `Init` / `PreOp` / `SafeOp` / `Op`
- `run` 之前的粗粒度准备动作
- `run` 结束后的 best-effort 收尾

实现方式：

- 直接使用 `@protocol.broadcast_state(...)`
- 优点是开销小、总线级一致
- 缺点是不确认每个从站的最终 AL 状态

### 3.2 定点确认迁移

适用场景：

- 某个站点的恢复、调试、故障定位
- 需要读取 AL Status / AL Status Code 做确认
- 从 `Op -> SafeOp -> PreOp -> Init` 或 `Init -> PreOp -> SafeOp -> Op` 的可追踪路径

实现方式：

- 使用 CLI `state --station <configured-address>`
- 直接请求时走 `@protocol.request_state(...)`
- 路径迁移时走 `@protocol.transition_through(...)`

### 3.3 run 路径为何暂不直接暴露复杂 ESM 编排

当前 `run` 命令仍保持单一职责：

- scan
- validate
- 广播切到 `Op`
- 运行 PDO 周期
- best-effort 广播切回 `Init`

原因：

- `run` 的核心目标是 Free Run / PDO 周期闭环，不是调试型状态机控制台
- 实机状态迁移通常需要按站确认、读 AL Status Code、处理 rollback，语义比 `run` 粗路径更重
- 因此先单独引入 `state` 命令，避免把 `run` 的稳定 smoke 语义打碎

## 4. CLI `state` 命令约定

### 4.1 广播模式

```powershell
moon run cmd/main state -- --backend native-windows-npcap --if <interface> --state safeop
```

语义：

- 对整条总线广播写 AL Control
- 输出 WKC，不强制确认每个站点最终状态

### 4.2 定点直接模式

```powershell
moon run cmd/main state -- --backend native-windows-npcap --if <interface> --state op --station 4097
```

语义：

- 对单个 configured station 发起 `request_state`
- 读回确认状态与 AL Status Code

### 4.3 定点路径模式

```powershell
moon run cmd/main state -- --backend native-windows-npcap --if <interface> --state boot --station 4097 --path
```

语义：

- 若当前状态无法直接到目标状态，则先回退到 `Init` 再前进
- 示例：`Op -> SafeOp -> PreOp -> Init -> Boot`

## 5. Native `run --until-fault` 实机长跑验证

该验证面向真实网卡和真实从站，不是空总线 smoke。目标是确认以下三点：

- Native 后端在长时间 PDO 循环下持续输出稳定的结构化进度
- 运行时在超时/WKC/DC 漂移等恢复条件出现时能以 `fault + surface` 收敛
- CLI 与库层职责保持分离：库层只产出结构化进度，CLI 负责文本或 NDJSON 渲染

### 5.1 前置条件

- 已完成 `list-if -> scan -> validate` 基线确认
- Windows 使用 `native-windows-npcap`，Linux 使用 `native-linux-raw`
- 若总线上有真实从站，建议先记录至少一个 configured station 地址，便于需要时用 `state --station ... --path` 回到 `PreOp`

### 5.2 推荐命令

```powershell
moon run cmd/main run -- --backend native-windows-npcap --if <interface> --json --progress-ndjson --until-fault --cycle-period-us 1000 --output-period-ms 1000 --max-consecutive-timeouts 5 --startup-state op --shutdown-state init
```

说明：

- `--json --progress-ndjson` 让进度与最终总结共用 NDJSON，不会破坏 JSON 消费方
- `--output-period-ms` 控制 `run-progress` 行输出周期
- `--until-fault` 只会在运行时故障时自然退出；人工 `Ctrl+C` 停止不会生成最终 `run-summary`
- `--startup-state op` 维持当前实机 `run` 的默认目标语义；若只想验证到 `SafeOp`，可显式改成 `--startup-state safeop`

### 5.3 产物与通过标准

- 正常长跑过程中，日志应持续出现 `{"kind":"run-progress", ...}` 行
- 若由运行时故障退出，最后应出现 `{"kind":"run-summary", ...}` 行
- `run-summary.summary.fault` 与 `run-summary.summary.surface` 应能说明故障类别，而不是只给出裸字符串错误
- 若人工 `Ctrl+C` 停止，只要求保留连续 `run-progress` 行；此时没有 `run-summary` 属于当前设计预期

### 5.4 建议执行顺序

1. `list-if --json` 确认接口名稳定且后端选择正确。
2. `scan --json` 记录从站数量、station address 和身份。
3. `validate --json` 确认在线拓扑与当前预期一致。
4. 若此前链路存在状态残留，先执行一次 `state --station <configured-address> --path --state preop`。
5. 再执行 `run --json --progress-ndjson --until-fault ...`，观察 NDJSON 进度流与最终 fault 收敛。

### 5.5 批处理脚本

仓库提供了可直接复用的 PowerShell 脚本 [scripts/validate-native-until-fault.ps1](scripts/validate-native-until-fault.ps1)。示例：

```powershell
pwsh -File scripts/validate-native-until-fault.ps1 -Interface "\\Device\\NPF_{GUID}" -Backend native-windows-npcap -Station 4097
```

脚本会依次产出：

- `01-list-if.json`
- `02-scan.json`
- `03-validate.json`
- `04-state-preop.json`（仅在提供 `-Station` 时）
- `05-run.ndjson`
- `06-fault-summary.json`（当 `05-run.ndjson` 存在时，由 [scripts/summarize-run-ndjson.ps1](../scripts/summarize-run-ndjson.ps1) 自动汇总）

`05-run.ndjson` 适合后续做事件回放、故障归档或外部日志采集。
`06-fault-summary.json` 则把最后一个 `run-summary`、最近一次 `run-progress`、故障 payload 与 diagnostic surface 收敛成单个 JSON，便于实机验证后快速归档最终故障摘要；若日志只包含 `run-progress` 而没有 `run-summary`，该工具会显式标记为 `no-run-summary`，表示更可能是人工 `Ctrl+C` 停止或采集被截断。

## 6. 后续实现顺序

建议按以下顺序继续：

1. 补 Linux Raw Socket 的 errno 到 `EcError` 精细映射
2. 补 Linux 实机 smoke 记录与至少一条真实接口回归说明
3. 为 `state` 命令增加实机回归脚本和文档示例
4. 评估是否要把 `run` 的启动/收尾状态改成可配置项；若改，只允许在保留默认 `Op -> Init` 语义的前提下扩展

## 7. 非目标

- 当前阶段不在 `run` 中引入每站逐步确认的复杂 ESM 编排
- 不在 Native HAL 里加入平台专属 Runtime 分叉
- 不把 Raw Socket / Npcap 差异上推到 `protocol/` 或 `runtime/`