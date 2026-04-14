# 零拷贝 HAL 设计（C-6 ~ C-8）

> **实现状态（2026-04-14）**：本设计已全面落地。`FramePool` + `FrameRef` + `FrameState` 状态机已实现于 `hal/`；`ZeroCopyNic` trait 已定义；`ZeroCopyMockNic` 测试双已实现；`zero_copy_codec.mbt` 和 `zero_copy_pdo.mbt` 已实现于 `protocol/`；Native 零拷贝后端已实现于 `hal/native/`。

> 本文档定义 MoonECAT 零拷贝帧管理架构，目标是消除 PDO 周期热路径中的全部 `Bytes` 堆分配。

---

## 1. 问题分析

当前 `pdo_exchange_result` 每周期至少 5 次 GC 堆分配：

```
Bytes::makei(total, ...)         ← 输出聚合
FrameBuilder → @buffer.new()     ← 帧编码 buffer
EcFrame::encode → buf.to_bytes() ← 帧序列化
nic.recv() → moonbit_make_bytes  ← C stub 接收分配
EcFrame::decode → Bytes::makei   ← PDU data 拷贝
```

在 1 kHz 周期下，每秒 5000+ 次分配和 GC 压力，不可接受于嵌入式和硬实时场景。

## 2. 设计原则

| 原则 | 说明 |
|---|---|
| **预分配复用** | 所有帧 buffer 在初始化时一次性分配，运行态零分配 |
| **FixedArray 热路径** | 用 `FixedArray[Byte]`（可变、固定长度）替代 `Bytes`（不可变）做热路径 buffer |
| **#external 直映射** | 嵌入式后端用 `#external type DmaRing` 直接引用 C/硬件管理的 DMA 描述符环 |
| **平台正交** | `ZeroCopyNic` trait 统一合同，平台差异封装在 FFI 后端 |
| **向后兼容** | 原 `Nic` trait + `Bytes` 路径保留，零拷贝作为可选升级路径 |

## 3. 核心类型

### 3.1 FramePool — 预分配帧池

```
FramePool
├── frames : FixedArray[FixedArray[Byte]]  // N 帧 × max_frame_size
├── states : FixedArray[FrameState]        // 每槽状态机
├── lengths : FixedArray[Int]              // 每槽有效数据长度
└── capacity : Int                         // 池容量（典型值 16~32）
```

**FrameState 状态机**：

```
Free → Acquired → Filled → Sending → Sent → Free
                                  ↓
                              Receiving → Received → Free
```

- `Free`：可分配
- `Acquired`：已被调用方占用，可写入数据
- `Filled`：数据已填充，等待提交发送
- `Sending`：正在发送（平台后端持有）
- `Sent`：发送完成，可回收
- `Receiving`：正在接收（平台后端持有）
- `Received`：接收完成，可读取

### 3.2 FrameRef — 零拷贝帧引用

```
FrameRef
├── pool_id : Int       // 所属池 ID（支持多池场景）
├── slot : Int          // 帧槽索引
├── offset : Int        // 有效数据起始偏移
├── length : Int        // 有效数据长度
```

`FrameRef` 是轻量值类型（4 个 Int），不持有堆引用。通过 `pool.data(ref)` 获取底层 `FixedArray[Byte]` 引用进行就地读写。

### 3.3 ZeroCopyNic trait

```moonbit
pub(open) trait ZeroCopyNic {
  /// 打开网络接口
  open_(String) -> Self raise EcError
  /// 从预分配池获取一个 TX 帧槽（零分配）
  acquire_tx(Self) -> FrameRef raise EcError
  /// 获取帧槽的可写 buffer 引用
  tx_buffer(Self, FrameRef) -> FixedArray[Byte]
  /// 提交已填充的帧进行发送
  submit(Self, FrameRef, length~ : Int) -> Unit raise EcError
  /// 等待接收帧（返回引用到预分配 RX buffer）
  recv(Self, timeout~ : Duration) -> FrameRef raise EcError
  /// 获取接收帧的只读 buffer
  rx_buffer(Self, FrameRef) -> FixedArray[Byte]
  /// 释放帧引用回池
  release(Self, FrameRef) -> Unit
  /// 关闭网络接口
  close(Self) -> Unit
}
```

## 4. 平台后端映射

### 4.1 Windows Npcap

```
ZeroCopyNic.acquire_tx → 返回 FrameRef 指向 MoonBit 侧 FramePool
ZeroCopyNic.submit     → pcap_sendpacket(pool.frames[ref.slot])
                          // FixedArray[Byte] 通过 #borrow 传入 C
                          // pcap_sendpacket 同步拷贝到内核，返回后 buffer 安全复用
ZeroCopyNic.recv       → pcap_next_ex → 直接写入 pool.frames[rx_slot]
                          // C stub 接收到预分配槽而非 moonbit_make_bytes
```

**Npcap 高级特性（待评估）**：
- `pcap_sendqueue_queue` + `pcap_sendqueue_transmit`：批量发送，减少系统调用
- 发送队列预分配可与 FramePool 映射

### 4.2 Linux Raw Socket

```
ZeroCopyNic.submit → send(fd, pool.frames[ref.slot], len, 0)
                      // FixedArray[Byte] 通过 #borrow 传入
ZeroCopyNic.recv   → recv(fd, pool.frames[rx_slot], max_frame_size, 0)
                      // 直接接收到预分配槽
```

### 4.3 Linux AF_XDP（未来）

AF_XDP 提供真正的内核旁路零拷贝：

```
UMEM（用户态共享内存）
├── Fill Ring   → 提交空帧地址给内核
├── Comp Ring   ← 内核归还已发送帧地址
├── TX Ring     → 提交待发送帧地址
└── RX Ring     ← 内核推送已接收帧地址

FramePool.frames 映射到 UMEM 区域
FrameRef.slot 直接对应 UMEM 帧偏移
→ 数据在用户态和内核之间零拷贝
```

### 4.4 Linux DPDK（未来）

```
rte_mempool     → 映射为 FramePool（mbufs 预分配）
rte_mbuf        → 映射为 FrameRef
rte_eth_tx_burst → 批量提交
rte_eth_rx_burst → 批量接收
→ 完全绕过内核协议栈
```

### 4.5 嵌入式 MCU（CherryECAT 风格）

```moonbit
#external
type DmaRing  // C 管理的 DMA 描述符环，不经过 GC

// FFI 直接操作硬件 DMA 描述符
extern "c" fn dma_acquire_tx(ring : DmaRing) -> Int = "dma_acquire_tx_slot"
extern "c" fn dma_get_buffer(ring : DmaRing, slot : Int) -> FixedArray[Byte] = "dma_get_buffer"
extern "c" fn dma_submit(ring : DmaRing, slot : Int, len : Int) -> Unit = "dma_submit_tx"
```

嵌入式后端中：
- `FramePool` 映射到 `__attribute__((section(".DMA_SRAM")))` 静态数组
- Ethernet 头在 init 阶段预填充到每个 TX buffer 槽
- Cache 一致性由 C stub 的 `SCB_CleanDCache_by_Addr` / `SCB_InvalidateDCache_by_Addr` 保证
- `FrameRef.slot` 直接对应 DMA 描述符索引

## 5. ProcessImage 就地映射（C-8）

当前 `ProcessImage.inputs`/`outputs` 是 `Bytes`（不可变），每周期必须整体重建。

**改进方向**：引入 `MutableProcessImage`，底层用 `FixedArray[Byte]`：

```
MutableProcessImage
├── outputs : FixedArray[Byte]  // 可就地修改
├── inputs  : FixedArray[Byte]  // 接收后可就地读取
├── output_size : Int
└── input_size : Int
```

PDO 交换流程从：
```
encode(...) → Bytes → send → recv → Bytes → decode → new Bytes → image.inputs = ...
```
变为：
```
encode_into(tx_frame, image.outputs) → submit → recv → decode_into(rx_frame, image.inputs)
```

全部操作在预分配 `FixedArray[Byte]` 上就地完成，零 GC 分配。

## 6. 热路径分配对比

| 操作 | 当前（Bytes） | 零拷贝（FixedArray） |
|---|---|---|
| 输出聚合 | `Bytes::makei` | 就地写入 `image.outputs` |
| 帧编码 | `@buffer.new + to_bytes()` | `encode_into(tx_frame)` |
| 帧发送 | `nic.send(bytes)` 拷贝 | `nic.submit(ref)` 零拷贝 |
| 帧接收 | `moonbit_make_bytes` 分配 | `nic.recv()` 写入预分配槽 |
| 帧解码 | `Bytes::makei` per PDU | `decode_into(image.inputs)` |
| **每周期分配** | **≥5 次** | **0 次** |

## 7. 实施路线

| 步骤 | 产出 | 阶段 |
|---|---|---|
| C-6a | `FramePool` + `FrameRef` + `FrameState` 核心类型 | hal/ |
| C-6b | `ZeroCopyNic` trait 定义 | hal/ |
| C-6c | `MockZeroCopyNic` 测试后端 | hal/mock/ |
| C-7a | Npcap 零拷贝 FFI stub | hal/native/ |
| C-7b | Linux Raw Socket 零拷贝 FFI stub | hal/native/ |
| C-7c | AF_XDP / DPDK / 嵌入式占位设计 | docs/ |
| C-8a | `MutableProcessImage` 类型 | protocol/ |
| C-8b | `encode_into` / `decode_into` 就地编解码 | protocol/ |
| C-8c | `pdo_exchange_zero_copy` 热路径集成 | protocol/ |

## 8. MoonBit FFI 关键约束

| 约束 | 应对 |
|---|---|
| `Bytes` 不可变（无 `op_set`） | 热路径用 `FixedArray[Byte]` |
| `FixedArray` 可通过 FFI `#borrow` 传递 | C 侧接收 `uint8_t*` |
| `#external` 类型不经过 GC | 嵌入式 DMA 描述符用此标注 |
| `moonbit_make_bytes` 触发 GC 分配 | 零拷贝 recv 改为写入预分配 `FixedArray` |
| 无裸指针暴露 | `FrameRef` 为值类型索引，非指针 |
