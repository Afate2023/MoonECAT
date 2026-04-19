# MoonECAT Backend Release Matrix

本文档把当前三类交付物的边界固定下来：Native CLI、Native Library、Extism Plugin。
协议语义保持一致，后端只负责 HAL / 宿主能力差异。

## 1. Native CLI

### 输入

- CLI 子命令：`list-if`、`scan`、`validate`、`run`、`read-sii`、`state`、`diagnosis`、`od`
- 后端选择：`--backend <mock|native|native-windows-npcap|native-linux-raw>`
- 真实网卡：`--if <interface>`

### 输出

- Human-readable 文本
- JSON：字段名与库层 `ScanReport`、`ValidateReport`、`RunReport` 对齐

### 依赖环境

- Windows：已安装 Npcap 运行时，`wpcap.dll` / `Packet.dll` 位于 `C:\Windows\System32\Npcap`
- Linux：支持 `AF_PACKET` raw socket，进程具备 root 或 `CAP_NET_RAW`，通常还需要 `CAP_NET_ADMIN` 以便 promisc 模式
- MoonBit 默认以 native 目标运行本模块；CLI 参数必须放在 `moon run ... --` 之后

### 最小验证命令

```powershell
moon run cmd/main list-if -- --backend native --json
moon run cmd/main scan -- --backend native --if <interface> --json
moon run cmd/main validate -- --backend native --if <interface> --json
moon run cmd/main diagnosis -- --backend native --if <interface> --json
moon run cmd/main state -- --backend native --if <interface> --station <configured-address> --path --state preop --json
moon run cmd/main read-sii -- --backend native --if <interface> --position 0 --words 128 --json
moon run cmd/main od -- --backend native --if <interface> --station <configured-address> --json
moon run cmd/main run -- --backend native --if <interface> --json
```

### 当前已验证

- Windows Npcap 1.8.4：
  `moon run cmd/main list-if -- --backend native-windows-npcap --json`
- Windows 非 EtherCAT 链路 smoke：
  `scan -> validate -> run` 在空总线场景下成功返回 0 slaves / PASS / Done
- 2026-03-11 实测接口：
  `\\Device\\NPF_{21208AED-855D-48E0-B0AF-A5B92C93EEDC}`
  （Realtek USB GbE Family Controller）
- 2026-03-11 实测结果：
  `scan` => `{"slave_count":0,"slaves":[]}`；
  `validate` => `{"total_expected":0,"total_found":0,"all_ok":true,"result_count":0}`；
  `run` => `cycles_requested=10`、`cycles_ok=10`、`final_phase=Done`
- 2026-03-14 同接口单从站长链实测：
  `scan` => `slave_count=1`，从站 `position=0 / station=4097 / alias=0 / vendor=1894 / product=2320 / revision=512`；
  `validate` => `grade=Pass`、`difference_count=0`；
  `read-sii` => 成功输出 `preamble/standard_metadata/header/strings/general/FMMU/SM/DC/categories`；
  `diagnosis` => `station=4097`、`AL State=Init`、`AL Error Flag=false`、`AL Status Code=0`；
  `state --station 4097 --path --state preop` => `current_state=Init`、`final_state=PreOp`、`status_code=0`；
  `od --station 4097` => 成功返回 `OD List` 索引数组；
  `run` => `cycles_requested=10`、`cycles_ok=10`、`final_phase=Done`

## 2. Native Library

### 输入

- `@native.NativeNic::open_with_config(...)`
- 现有库入口：`@runtime.scan`、`@runtime.validate`、`@runtime.run`

### 输出

- 与 CLI 相同的结构化报告对象
- 不新增平台特化语义

### 依赖环境

- 与 Native CLI 相同
- 非 native target 下通过 fallback 文件维持 wasm-gc 构建不污染

### 最小验证命令

```powershell
moon test hal/native/native_test.mbt
moon test hal/native/native_test.mbt --target native
```

### 当前状态

- Windows Npcap：接口枚举、open/send/recv/close、运行时动态加载已实现
- Linux Raw Socket：接口枚举、open/send/recv/close 已实现
- 真实 `scan/validate/run` 回归通过 `scripts/regression-real-device.ps1` 驱动；`--record <ndjson>` 把帧级事件流落盘，`scripts/replay-diff.ps1` 把同一份 NDJSON 通过 `cmd/main replay --trace ... --json` 重放并与 live `run-summary` 做稳定字段（slave_count / topology_fingerprint / verdict）比对
- CLI `run` 对真实网卡采用“先探测、再重新打开 NIC 执行 run”的路径，避免在同一真实句柄上重复扫描导致 smoke 回归
- `RecordingNicAdapter[N]` 适配器允许把任意 `@hal.Nic` 实现（包括 `NativeNic`）包成可记录链路，不再局限于 `VirtualNic`

### EoE / FoE（L3 交付面）

| 协议 | 库层实现 | 测试覆盖 | 现状 |
| --- | --- | --- | --- |
| **EoE** | `mailbox/eoe.mbt`（帧编解码 + EoeResult） + `mailbox/eoe_switch.mbt` / `eoe_endpoint.mbt` / `eoe_relay.mbt`（Virtual Switch 引擎） + `mailbox/eoe_async/`（异步桥） | `runtime/runtime_test.mbt`、`runtime/runtime_wbtest.mbt`、`mailbox/mailbox_test.mbt` 中含 fragment/IP request/response、Virtual Switch 端点路由、relay 调度等多组用例 | ✅ 帧层 + Virtual Switch 已闭环；CLI 暴露面后续按 feature pack 增量交付，**不阻塞 Native Library L3 验收** |
| **FoE** | `mailbox/foe.mbt`（FoeOpCode/ErrorCode/Response） + `protocol/foe_transaction.mbt`（download/upload + RMSM 计数器 + Busy 重试） | `protocol/integration_test.mbt`（含 download/upload 多包 + Busy 重试 + 错误码端到端用例）、`mailbox/mailbox_test.mbt` | ✅ FoE FP+AP 多包传输事务已闭环；CLI 暴露面后续按 feature pack 增量交付，**不阻塞 Native Library L3 验收** |

> EoE/FoE 已正式纳入 Native Library L3 交付面（库层 API + 库内事务 +
> 库层测试）。CLI 子命令（如 `eoe-bridge`、`foe-download`/`foe-upload`）
> 列入后续 feature pack，不在 L3 验收闸门内，但库层契约必须保持稳定。

## 3. Extism Plugin

### 输入

- 宿主提供 `nic_*`、`clock_*`、`file_*` 最小能力集
- 请求/响应 envelope

### 输出

- 稳定错误码
- 与 CLI / Library 对齐的诊断字段

### 依赖环境

- Extism / moonbit-pdk 宿主
- 不要求插件内部直接访问 raw socket 或 pcap

### 最小验证命令

```powershell
moon test plugin/extism/extism_test.mbt
```

### 当前状态

- 仅完成 envelope、entrypoints、错误码映射骨架
- 宿主 capability adapter 与共享内存路径待补齐

## 4. 环境注意事项

### Windows Npcap

- 建议安装兼容 WinPcap 模式
- `list-if` 成功不代表 EtherCAT 总线存在，只代表链路层打开与枚举成功
- 当前实现按 Npcap SDK 示例先 `SetDllDirectory(...\\Npcap)`，再动态加载 `wpcap.dll`
- 当前 CLI `run` 会先用一条探测会话生成 expected，再重新打开同一接口执行正式 `run`，这属于真实后端所需行为，不改变库层 `RunReport` 语义

### Linux Raw Socket

- 建议使用独立测试口，避免在业务网卡上直接做 EtherCAT 广播
- 需要 root 或为运行二进制授予 raw socket 能力，例如：

```bash
sudo setcap cap_net_raw,cap_net_admin+ep /path/to/moonecat
```

## 5. 回归原则

- 先验证 `list-if`，再验证 `scan`，最后验证 `validate/run`
- 真实链路 smoke 优先接受“空总线成功返回”，不要求本机必须连接 EtherCAT 从站
- 后端差异只能体现在 HAL 与环境说明，不允许漂移到 `ScanReport`、`ValidateReport`、`RunReport` 语义