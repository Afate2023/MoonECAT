# Native FFI Safety Notes

> **实现状态（2025-07）**：本文档描述的保守所有权模型已完整落地于 `hal/native/`。FFI 句柄生命周期由 MoonBit 端管理，`platform_stub.c` 提供公共桥接，wasm-gc 后端有 fallback 安全路径。

本文档记录 MoonECAT Native 后端当前的 FFI ownership、句柄释放责任与最小内存安全验证路径。

## 1. 当前句柄策略

- MoonBit 侧不直接持有 `pcap_t*`、`socket fd` 之类裸宿主句柄。
- `hal/native/native_nic.mbt` 只暴露 `handle_id : Int`，真实宿主句柄由 `hal/native/platform_stub.c` 内部静态表管理。
- 关闭责任由 MoonBit 显式调用 `NativeNic::close()` 触发，C stub 在 `moonecat_windows_npcap_close` / `moonecat_linux_raw_socket_close` 中释放底层资源。
- 当前没有使用 finalizer external object，也没有使用 `#external type` 暴露资源句柄；原因是首版 Native 后端优先选择“整数句柄 ID + C 侧所有权表”的更保守模型，避免跨语言生命周期耦合。

## 2. 非 primitive 参数 ownership 注解

当前 Native FFI 中所有跨边界的非 primitive 输入参数都已显式标注：

- `hal/native/windows_npcap_ffi.mbt`
  - `ffi_windows_npcap_open(name : Bytes)` 使用 `#borrow(name)`
  - `ffi_windows_npcap_send(data : Bytes)` 使用 `#borrow(data)`
- `hal/native/linux_raw_socket_ffi.mbt`
  - `ffi_linux_raw_socket_open(name : Bytes)` 使用 `#borrow(name)`
  - `ffi_linux_raw_socket_send(data : Bytes)` 使用 `#borrow(data)`

说明：

- 这些参数仅在单次 FFI 调用期间使用，C 侧不会持久化 `Bytes` 指针，因此采用 `#borrow`。
- 接收路径统一由 C stub 分配返回 `moonbit_bytes_t`，MoonBit 侧再按普通 `Bytes` 使用；不会把宿主暂存缓冲区直接暴露给上层。

## 3. Native target gating

- `hal/native/moon.pkg` 已通过 `targets` 把 `ffi_native.mbt`、`windows_npcap_ffi.mbt`、`linux_raw_socket_ffi.mbt` 限定在 `native` 目标。
- 对应 fallback 文件只在 `wasm-gc` 下参与构建。
- `native-stub` 仅声明 `platform_stub.c`，不会污染非 Native 路径的协议层与运行时层。

## 4. 释放责任矩阵

| 资源 | 创建位置 | 释放位置 | 责任方 |
|---|---|---|---|
| Windows `pcap_t*` | `platform_stub.c` `moonecat_windows_npcap_open` | `platform_stub.c` `moonecat_windows_npcap_close` | MoonBit 通过 `NativeNic::close()` 触发，C stub 实际释放 |
| Linux raw socket fd | `platform_stub.c` `moonecat_linux_raw_socket_open` | `platform_stub.c` `moonecat_linux_raw_socket_close` | MoonBit 通过 `NativeNic::close()` 触发，C stub 实际释放 |
| 枚举结果文本/JSON | `platform_stub.c` 内部栈/临时缓冲区 | 转换为 `moonbit_bytes_t` 后交给 MoonBit GC | C stub 复制，MoonBit GC 回收返回值 |
| 接收帧 `Bytes` | `platform_stub.c` 中复制到 `moonbit_make_bytes` | MoonBit GC | C stub 分配返回对象，MoonBit GC 回收 |

## 5. 最小内存安全验证路径

当前仓库提供一条 Linux/clang AddressSanitizer 验证路径，用于排查 Native stub 的句柄泄漏、悬垂引用与越界写入。

示例：

```powershell
$env:CC = "clang"
$env:CFLAGS = "-fsanitize=address -fno-omit-frame-pointer"
$env:LDFLAGS = "-fsanitize=address"
moon test hal/native
```

约束：

- 该路径主要面向 Linux Raw Socket stub；Windows Npcap 路径优先使用等价的调试 CRT / 外部泄漏检测工具。
- 若在 CI 中加入该检查，建议与普通 `moon test` 分开执行，避免把 sanitizer 依赖带入默认开发路径。

## 6. 后续仍待完成的真正缺口

- 为 Extism host adapter 明确同等级 ownership 约束。
- 增加真实 NIC 关闭/重开压力回归，覆盖多次 open/close 后句柄槽位复用。
- 若后续将句柄改为 finalizer external object，需要重新审视 `NativeNic` 的所有权模型与关闭语义。