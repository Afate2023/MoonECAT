# MoonECAT Backend Release Matrix

本文档把当前三类交付物的边界固定下来：Native CLI、Native Library、Extism Plugin。
协议语义保持一致，后端只负责 HAL / 宿主能力差异。

## 1. Native CLI

### 输入

- CLI 子命令：`list-if`、`scan`、`validate`、`run`
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
moon run cmd/main run -- --backend native --if <interface> --json
```

### 当前已验证

- Windows Npcap 1.8.4：
  `moon run cmd/main list-if -- --backend native-windows-npcap --json`
- Windows 非 EtherCAT 链路 smoke：
  `scan -> validate -> run` 在空总线场景下成功返回 0 slaves / PASS / Done

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
- 真实 `scan/validate/run` 回归尚未补成自动化硬件测试

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