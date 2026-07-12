# Native FFI Safety Notes

> **迁移状态（2026-07-02）**：MoonECAT 已删除旧 `hal/native/`
> package、MoonBit native FFI 声明、C stubs 和 native backend tests。
> 本文件保留为历史安全边界说明，不再作为 MoonECAT 内新增 native FFI
> 的实现指南。

## 当前边界

- MoonECAT 不再拥有 `pcap_t*`、raw socket fd、Npcap DLL loading、Linux
  `AF_PACKET` socket、pcap writer 或 native zero-copy C ABI。
- MoonECAT 只保留 `@hal.Nic`、`@hal.ZeroCopyNic`、`@hal.Clock` 等 trait，
  以及 mock/replay/runtime/protocol 实现。
- 真实 NIC/session C ABI 由 Isochronon Lockwire native layer 拥有。
- MoonECAT live delivery 只能通过 provider-owned harness，例如
  `fieldbus_core/moonecat_master_harness`，把 Lockwire session wrapper 适配成
  MoonECAT HAL trait。

## 历史实现原则

旧 `hal/native/` 曾采用以下原则；这些原则已经迁移到 Lockwire/native
侧继续适用：

- native 资源不直接暴露给 MoonBit 协议层。
- C 侧拥有真实 handle table，MoonBit 侧只持有可审计 descriptor 或 wrapper。
- 非 primitive FFI 参数必须明确 `#borrow` / `#owned` 语义。
- live open/send/capture 必须有显式 allow gate，不得由默认 mock/replay
  测试路径触发。
- pcap/tshark、真实 NIC、设备互操作和认证 evidence 必须明确标注，不得用
  offline 或 pending 输出替代。

## 后续要求

- 不要在 MoonECAT 新增 `native-stub`、`extern "c"` live NIC 声明或
  `hal/native` replacement package。
- 如果 provider harness 需要 MoonECAT runner，应调用已经公开的泛型
  `@hal.Nic` / `@hal.ZeroCopyNic` runner，而不是让 MoonECAT import
  `mokomoking2501/lockwire`。
- 若需要审计旧实现，可从 git history 查看删除前的 `hal/native/` 文件。
