# Native Backend Plan

本文件细化 MoonECAT Native 后端的目录、文件、FFI 约束与验证步骤。
Windows 路径参考附带的 Npcap SDK，Linux 路径以 Raw Socket 为首个落点。

## 1. 目标

- 在不污染 `protocol/`、`mailbox/`、`runtime/` 的前提下，为真实网卡提供 HAL 实现。
- 先打通 Linux Raw Socket，再补 Windows Npcap；两条路径共用同一 HAL 语义与错误分类。
- Native 路径可用于 CLI smoke 验证和后续真实性能/诊断回归。

## 2. 参考依据

Windows Npcap SDK：

- 设备枚举：`pcap_findalldevs`
- 设备打开：`pcap_open_live`
- 接收：`pcap_next_ex`
- 发送：`pcap_sendpacket`，见 `Examples-pcap/sendpack/sendpack.c`
- 设备列表示例：`Examples-pcap/iflist/iflist.c`

当前 Npcap 示例给出的关键事实：

- Windows 使用 `LoadNpcapDlls()` 做 DLL 目录预设。
- 设备名由 `pcap_findalldevs()` 返回，后续直接传给 `pcap_open_live()`。
- 接收缓冲区由 `pcap_next_ex()` 管理，调用方若要持久化必须复制。
- 发送可直接使用 `pcap_sendpacket()`。

## 3. 建议包布局

- `hal/native/`
  - `moon.pkg`
  - `native_types.mbt`
  - `native_errors.mbt`
  - `native_nic.mbt`
  - `ffi_native.mbt` 仅 native
  - `windows_npcap_ffi.mbt` 仅 native
  - `linux_raw_socket_ffi.mbt` 仅 native
  - `platform_stub.c`
  - `native_test.mbt`

说明：

- `ffi_*.mbt` 只放原始 FFI 声明和最薄包装。
- `native_nic.mbt` 放安全 MoonBit API 与 HAL trait 适配。
- `platform_stub.c` 只提供公共桥接函数，不承载协议逻辑。

## 4. MoonBit FFI 约束

- 使用 `moon.pkg` 的 `native-stub` 和 `targets` 限定 native 文件。
- 原始 `extern "c" fn` 保持私有，对外只暴露安全包装层。
- 所有非 primitive 参数都必须显式标 `#borrow` 或 `#owned`。
- 句柄类型按生命周期决定：
  - 若 C 资源由 MoonBit GC 辅助释放，用 external object + finalizer。
  - 若生命周期完全由 C API 手工控制，用 `#external type`。
- 接收到的帧数据因 `pcap_next_ex()` 缓冲区非持久，必须复制到 MoonBit `Bytes` 后再返回。

## 5. 文件级工作项

### `hal/native/moon.pkg`

- 导入 `afate/MoonECAT/hal`
- 配置 `native-stub`
- 用 `targets` 把 `ffi_native.mbt`、`windows_npcap_ffi.mbt`、`linux_raw_socket_ffi.mbt` 限定在 native

### `hal/native/native_types.mbt`

- `NativeBackendKind`
- `NativeNicConfig`
- `NativeNic`
- 可能的 handle wrapper 类型

### `hal/native/native_errors.mbt`

- 平台错误到 `EcError` 的集中映射
- Npcap / Win32 / errno 文本归一化

### `hal/native/ffi_native.mbt`

- 公共 FFI 类型别名
- 平台无关的 helper extern

### `hal/native/windows_npcap_ffi.mbt`

- `pcap_findalldevs` 路径包装
- `pcap_open_live` 路径包装
- `pcap_next_ex` 路径包装
- `pcap_sendpacket` 路径包装
- `pcap_close` 路径包装

### `hal/native/linux_raw_socket_ffi.mbt`

- socket open / bind / send / recv / close
- 非阻塞与超时换算

### `hal/native/platform_stub.c`

- 包含 `moonbit.h`
- 按平台桥接 Npcap / Raw Socket
- 为 Native 后端提供统一 C 入口名

### `hal/native/native_nic.mbt`

- 对外安全构造器
- `@hal.Nic` trait 适配
- 后续可补 `Clock` / `FileAccess` 的本地实现接入点

### `hal/native/native_test.mbt`

- 先做非真实网卡单元测试：参数校验、错误码映射、配置对象
- 真实设备 smoke test 保持显式、可选执行

## 6. Npcap 专项注意事项

- 接口名使用 Npcap 返回的设备名，例如 `\\Device\\NPF_{GUID}`。
- 打开时优先 `pcap_open_live(name, snaplen, promisc, timeout_ms, errbuf)`。
- 发送用 `pcap_sendpacket`，失败信息取 `pcap_geterr`。
- 接收用 `pcap_next_ex`：
  - `1` 为成功
  - `0` 视为超时，映射 `RecvTimeout`
  - 其他负值视为读取错误，映射 `RecvFailed(...)`
- 首版只接受 `DLT_EN10MB`；其它 datalink 类型先映射 `NotSupported(...)`。

## 7. 验收路径

1. 包级：Native 包在非主路径下存在，默认不影响现有 Mock 测试。
2. 编译级：`moon check --target native` 可通过。
3. 行为级：真实 NIC 上至少能完成设备打开、发送、超时接收和关闭。
4. 语义级：发送/接收/超时/链路异常均能映射为现有 `EcError`。
5. CLI 级：后续可把 `cmd/main` 从 Mock 切换为可选 native backend。

## 8. 建议提交拆分

- `native ffi scaffold`
- `native linux raw socket binding`
- `native windows npcap binding`
- `native error mapping and tests`
- `native cli smoke integration`