# Extism / WASM Backend Plan

> **实现状态（2026-04-14）**：`plugin/extism/` 已实现边界设计和占位入口（`HostCapabilityContract` + envelope 协议 + scan/validate/run entry stubs）。实际 Extism PDK 绑定和完整验证闭环待推进。

本文件把 MoonECAT 的 Extism / WASM 后端从“边界定义”推进到“可实施计划”。
它建立在 [docs/EXTISM_HOST_BOUNDARY.md](docs/EXTISM_HOST_BOUNDARY.md) 之上，目标是明确包边界、导出入口、宿主协定和最小验证闭环。

## 1. 目标

- 复用现有 `scan`、`validate`、`run` 库接口，不复制协议实现。
- 在不修改 `protocol/`、`mailbox/`、`runtime/` 协议语义的前提下，提供可被 Extism 宿主调用的插件入口。
- 对控制面使用稳定的 envelope，对周期数据使用共享内存缓冲区，避免热路径重复序列化。

## 2. 非目标

- 不在插件内部直接接 Raw Socket、Npcap 或任何平台网卡 API。
- 不新增插件专用 ESM、PDO 或 mailbox 状态机。
- 不派生第二套 CLI 或第二套运行时调度器。

## 3. 建议包布局

- `hal/extism/`
  - Host capability 适配器，负责把宿主函数映射为 `@hal.Nic`、`@hal.Clock`、`@hal.FileAccess` 语义。
- `cmd/extism/` 或 `plugin/extism/`
  - 插件入口层，负责导出 `scan`、`validate`、`run`。
- `docs/`
  - 保留 host contract、envelope 版本、共享内存协议和回放验证说明。

约束：

- `protocol/`、`mailbox/`、`runtime/` 不允许引入 Extism API。
- 插件只依赖公开的库层入口，不直接调用内部 helper。

## 4. 插件导出入口

建议稳定导出以下三个入口：

- `scan(request_bytes) -> response_bytes`
- `validate(request_bytes) -> response_bytes`
- `run(request_bytes) -> response_bytes`

说明：

- `request_bytes` / `response_bytes` 可承载 JSON 文本或二进制 envelope。
- 导出层只做解析、错误映射、调用库 API、结果封装。

## 5. Envelope 协议

所有导出入口共用统一 envelope。

请求字段建议：

- `version`
- `command`
- `request_id`
- `timeout_ns`
- `payload`
- `shared_memory` 可选描述

响应字段建议：

- `version`
- `request_id`
- `ok`
- `error_code`
- `error_message`
- `payload`
- `diagnostics`

要求：

- `error_code` 必须可稳定映射到 `EcError` 族。
- `diagnostics` 字段名要与 Native CLI / Library 保持一致。

## 6. Shared Memory 约定

共享内存仅用于大块周期数据，不承担协议语义。

最小字段：

- `buffer_id`
- `offset`
- `length`
- `direction` (`tx` / `rx` / `bidirectional`)
- `owner` (`host` / `plugin`)

约束：

- 宿主负责缓冲区生命周期和回收。
- 插件只在约定区间内读写，不缓存超出调用周期的裸指针。
- 超时语义依然由 `timeout_ns` 和 `EcError::RecvTimeout` 等分类表达。

## 7. Host Capability Contract

沿用 [docs/EXTISM_HOST_BOUNDARY.md](docs/EXTISM_HOST_BOUNDARY.md) 的最小契约：

- `nic_open`
- `nic_send`
- `nic_recv`
- `nic_close`
- `clock_now_ns`
- `clock_sleep_ns`
- `read_file` 可选
- `write_file` 可选

补充约束：

- 宿主只暴露 HAL 等价能力，不上推对象字典、PDO、ESM 等协议级操作。
- `nic_recv` 返回的数据必须保留完整链路层头，插件侧负责按现有协议逻辑解码。

## 8. 状态管理

优先采用短生命周期命令模型：

- `scan`、`validate` 为一次请求一次响应。
- `run` 由宿主显式创建、推进、停止，不隐式常驻。

长周期 `run` 的建议：

- 宿主持有 run session id。
- 插件对外暴露 `run-start`、`run-step`、`run-stop` 或保持单 `run` 但由 envelope 描述 phase。
- 无论采用哪种形态，都不能改变现有 runtime 的状态机语义。

## 9. 验收路径

最小可接受闭环：

1. `scan` 通过宿主 NIC 能发现设备或返回明确空结果。
2. `validate` 对相同输入给出与 Native 路径等价的校验结果。
3. `run` 最小回放覆盖 `scan -> validate -> run -> stop`。
4. `RecvTimeout`、`UnexpectedWkc`、`EsmTransitionFailed` 映射到稳定错误码。
5. 插件在无文件系统宿主场景下仍可用 bytes 输入完成 `validate`。

## 10. 交付拆分建议

- `extism adapter package scaffold`
- `extism envelope and error mapping`
- `extism shared-memory transport`
- `extism replay validation`
- `extism docs and release notes`