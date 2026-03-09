# EtherCrab 完整项目调用流分析 & 代码利用特点解析

> 基于 ethercrab v0.6.0 源码的深度分析  
> 生成日期: 2026-03-03

---

## 目录

1. [项目总览](#1-项目总览)
2. [核心架构分层](#2-核心架构分层)
3. [完整调用流分析](#3-完整调用流分析)
   - 3.1 [启动与初始化调用流](#31-启动与初始化调用流)
   - 3.2 [PDU 通信底层调用流](#32-pdu-通信底层调用流)
   - 3.3 [SubDevice 发现与配置调用流](#33-subdevice-发现与配置调用流)
   - 3.4 [状态机转换调用流](#34-状态机转换调用流)
   - 3.5 [周期性过程数据 (PDI) 调用流](#35-周期性过程数据-pdi-调用流)
   - 3.6 [Distributed Clock (DC) 调用流](#36-distributed-clock-dc-调用流)
   - 3.7 [SDO/CoE 邮箱调用流](#37-sdocoe-邮箱调用流)
   - 3.8 [EEPROM 读写调用流](#38-eeprom-读写调用流)
4. [代码设计特点深度解析](#4-代码设计特点深度解析)
5. [代码审查意见](#5-代码审查意见)

---

## 1. 项目总览

EtherCrab 是一个用纯 Rust 编写的高性能 **async-first** EtherCAT MainDevice（主站）实现，支持 `std` 和 `no_std` 环境。项目采用零堆分配（`no_std` 兼容）的设计理念，所有缓冲区在编译期通过 const generics 确定大小。

### 关键 Crate 组成

| Crate | 用途 |
|-------|------|
| `ethercrab` | 主 crate，EtherCAT MainDevice 实现 |
| `ethercrab-wire` | 线上编解码 trait 定义 |
| `ethercrab-wire-derive` | 编解码 derive 宏 |

### 核心公开类型

| 类型 | 作用 |
|------|------|
| `MainDevice` | EtherCAT 主控制器，驱动整个通信 |
| `PduStorage` | 静态 PDU 帧存储，编译期确定大小 |
| `PduLoop` / `PduTx` / `PduRx` | PDU 发送/接收循环核心 |
| `SubDeviceGroup` | SubDevice 分组，管理 PDI 和状态转换 |
| `SubDevice` / `SubDeviceRef` | 子设备元数据与操作引用 |
| `Command` / `WrappedRead` / `WrappedWrite` | EtherCAT PDU 命令构建器 |

---

## 2. 核心架构分层

```
┌─────────────────────────────────────────────────────────────────┐
│                    📱 用户应用层 (Application)                   │
│  init_single_group() → iter() → sdo_read/write() → tx_rx()     │
├─────────────────────────────────────────────────────────────────┤
│                 📦 分组管理层 (SubDeviceGroup)                   │
│  SubDeviceGroup<N, PDI, Lock, State, DC>                        │
│  状态机 typestate: Init → PreOp → PreOpPdi → SafeOp → Op       │
├─────────────────────────────────────────────────────────────────┤
│               🔧 子设备层 (SubDevice / SubDeviceRef)             │
│  配置、EEPROM、邮箱、SDO/CoE、DC、状态管理                      │
├─────────────────────────────────────────────────────────────────┤
│                 📡 命令层 (Command / Wrapped*)                   │
│  BRD, BWR, FPRD, FPWR, APRD, APWR, LRW, LWR, FRMW            │
│  Builder pattern: Command::fprd() → .receive::<T>()             │
├─────────────────────────────────────────────────────────────────┤
│                 🔄 PDU 循环层 (PduLoop)                         │
│  PduStorage → try_split() → (PduTx, PduRx, PduLoop)           │
│  alloc_frame() → push_pdu() → mark_sendable() → .await         │
├─────────────────────────────────────────────────────────────────┤
│              🌐 网络传输层 (std::tx_rx_task)                     │
│  Linux: raw socket / io_uring / XDP                             │
│  Windows: pcap                                                   │
│  no_std: 用户自行实现 PduTx/PduRx 驱动                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 完整调用流分析

### 3.1 启动与初始化调用流

```
用户代码
  │
  ├── PduStorage::<MAX_FRAMES, MAX_PDU_DATA>::new()  // 编译期创建静态存储
  │     └── const assert: N ≤ u8::MAX, N 为 2 的幂, DATA ≥ 28
  │
  ├── PDU_STORAGE.try_split()  // 运行时一次性拆分为三个句柄
  │     ├── compare_exchange(is_split, false → true)  // 原子 CAS 保证只拆分一次
  │     ├── → PduTx { storage: PduStorageRef }
  │     ├── → PduRx { storage: PduStorageRef }
  │     └── → PduLoop { storage: PduStorageRef }
  │
  ├── MainDevice::new(pdu_loop, timeouts, config)
  │     └── 初始化: num_subdevices=0, dc_reference_configured_address=0
  │
  ├── tokio::spawn(tx_rx_task(&interface, tx, rx))  // 独立线程处理网络 I/O
  │     ├── [Linux]   → raw socket / io_uring 收发
  │     ├── [Windows] → pcap 抓包/发包
  │     └── PduTx.replace_waker() → 注册 waker 实现异步唤醒
  │
  └── maindevice.init_single_group::<N, PDI>(ethercat_now)
        └── maindevice.init::<N, _>(now, default_group, |g, _sd| Ok(g))
              └── [详见 §3.3 SubDevice 发现与配置调用流]
```

### 3.2 PDU 通信底层调用流

这是整个项目最核心的通信通道。每一次 register 读写、SDO 操作、过程数据交换最终都归结到 PDU 帧的发送与接收。

```
调用方 (e.g. Command::fprd().receive::<T>())
  │
  ├── WrappedRead::common(maindevice, len)
  │     └── maindevice.single_pdu(command, data, len_override)
  │           │
  │           ├── pdu_loop.alloc_frame()
  │           │     ├── frame_idx 原子递增 (wrapping, mod N)
  │           │     ├── CAS: FrameState::None → FrameState::Created
  │           │     └── 返回 CreatedFrame (零拷贝写入视图)
  │           │
  │           ├── frame.push_pdu(command, data, len_override)
  │           │     ├── 写入 PDU header (command code, address, flags)
  │           │     ├── 序列化 payload 到帧缓冲区
  │           │     ├── 写入 Ethernet + EtherCAT frame headers
  │           │     └── 分配唯一 PDU index (pdu_idx 原子递增)
  │           │
  │           ├── frame.mark_sendable(pdu_loop, timeout, retries)
  │           │     ├── CAS: FrameState::Created → FrameState::Sendable
  │           │     └── 返回 impl Future (ReceiveFrameFut)
  │           │
  │           ├── pdu_loop.wake_sender()
  │           │     └── tx_waker.wake() → 唤醒 TX 任务
  │           │
  │           └── frame.await  ← 挂起等待响应
  │                 │
  │    ┌────────────┼──── TX 任务线程 ────────────────────┐
  │    │            │                                      │
  │    │  PduTx::next_sendable_frame()                     │
  │    │    ├── 遍历所有帧槽                                │
  │    │    ├── CAS: Sendable → Sending                    │
  │    │    └── 返回 SendableFrame                          │
  │    │                                                    │
  │    │  frame.send_blocking(|bytes| network_send(bytes)) │
  │    │    ├── CAS: Sending → Sent                        │
  │    │    └── 通过回调写入网络接口                         │
  │    └────────────────────────────────────────────────────┘
  │                 │
  │    ┌────────────┼──── RX 任务线程 ────────────────────┐
  │    │            │                                      │
  │    │  PduRx::receive_frame(ethernet_bytes)             │
  │    │    ├── 解析 Ethernet 帧                            │
  │    │    │   ├── 校验 EtherType == 0x88a4               │
  │    │    │   └── 过滤自发帧 (src_addr 检查)             │
  │    │    ├── 解析 EtherCAT frame header                 │
  │    │    ├── 提取 PDU index → 查找对应帧槽              │
  │    │    │   └── frame_index_by_first_pdu_index()       │
  │    │    ├── claim_receiving() // CAS: Sent → RxBusy    │
  │    │    ├── 复制响应数据到帧缓冲区                      │
  │    │    └── mark_received() // → RxDone + wake()       │
  │    │                                                    │
  │    └────────────────────────────────────────────────────┘
  │                 │
  │           ← Future 被唤醒, Poll::Ready
  │           ├── first_pdu(handle) → ReceivedPdu
  │           │     ├── 校验 working counter (WKC)
  │           │     └── 返回响应数据零拷贝视图
  │           └── T::unpack_from_slice(data) → 反序列化为目标类型
  │
  └── 返回 Result<T, Error>
```

#### FrameElement 状态机

```
None ─alloc→ Created ─mark_sendable→ Sendable ─TX task→ Sending
  ↑                                                        │
  │           ┌──────────────────────────────────────────── │
  │           │                                             ↓
  └─drop()── RxProcessing ←poll()── RxDone ←mark_received── Sent
                                        ↑                    │
                                        │    ┌───────────────┘
                                        │    ↓
                                        RxBusy (claim_receiving)
```

### 3.3 SubDevice 发现与配置调用流

```
MainDevice::init()
  │
  ├── count_subdevices()
  │     └── Command::brd(RegisterAddress::Type).receive_wkc::<u8>()
  │           // WKC = 每个 SubDevice 递增的 working counter 即为设备数
  │
  ├── reset_subdevices()
  │     ├── BWR AlControl::reset()          // 广播重置所有设备至 INIT
  │     ├── blank_memory() × 16             // 清空所有 FMMU (16个)
  │     ├── blank_memory() × 16             // 清空所有 SM (16个)
  │     ├── blank_memory() DC 寄存器        // 重置 DC 相关寄存器
  │     │     (DcCyclicUnitControl, DcSystemTime, DcSystemTimeOffset,
  │     │      DcSystemTimeTransmissionDelay, DcSystemTimeDifference,
  │     │      DcSyncActive, DcSyncStartTime, DcSync0CycleTime, DcSync1CycleTime)
  │     └── BWR DcControlLoopParam3/1       // 设置 DC 控制环参数
  │
  ├── 为每个 SubDevice 设置 configured address
  │     └── for idx in 0..num_subdevices:
  │           APWR(idx, ConfiguredStationAddress) = BASE_ADDR + idx
  │           // BASE_SUBDEVICE_ADDRESS = 0x1000
  │
  ├── 逐一创建 SubDevice 实例
  │     └── SubDevice::new(maindevice, index, configured_address)
  │           ├── wait_for_state(Init)          // 等待设备进入 INIT
  │           ├── set_eeprom_mode(Master)       // EEPROM 控制权移交 Master
  │           ├── eeprom.identity()             // 读取 identity (vendor, product, serial)
  │           ├── eeprom.device_name()          // 读取设备名称
  │           ├── FPRD SupportFlags             // 读取功能标志 (DC支持等)
  │           ├── FPRD ConfiguredStationAlias   // 读取别名地址
  │           └── FPRD DlStatus → Ports         // 读取端口链接状态 → 拓扑信息
  │
  ├── dc::configure_dc(maindevice, subdevices, now)
  │     └── [详见 §3.6 DC 调用流]
  │
  ├── SubDevice 分组（通过 group_filter 闭包）
  │     └── for each subdevice:
  │           ├── group_filter(&groups, &subdevice) → &dyn SubDeviceGroupHandle
  │           └── unsafe { group.push(subdevice) }
  │
  ├── 按组初始化 (into_pre_op)
  │     └── for each group:
  │           SubDeviceGroupRef::into_pre_op(pdi_offset, maindevice)
  │             └── for each subdevice in group:
  │                   SubDeviceRef::configure_mailboxes()
  │                     ├── set_eeprom_mode(Master)
  │                     ├── eeprom.sync_managers()          // 读取 SM 配置
  │                     ├── configure_mailbox_sms()         // 配置 SM0/SM1 邮箱
  │                     │     ├── eeprom.mailbox_config()   // 读取默认邮箱配置
  │                     │     ├── eeprom.general()          // 读取 General 类别
  │                     │     └── 写入 SM 寄存器配置         // FPWR
  │                     ├── set_eeprom_mode(Pdi)            // EEPROM 移交 PDI
  │                     ├── request_subdevice_state(PreOp)  // INIT → PRE-OP
  │                     └── set_eeprom_mode(Master)         // EEPROM 恢复 Master
  │
  └── wait_for_state(PreOp)  // 等待所有 SubDevice 到达 PRE-OP
```

### 3.4 状态机转换调用流

SubDeviceGroup 的 typestate 转换链:

```
SubDeviceGroup<..., PreOp>
  │
  ├── into_pre_op_pdi()           // 配置 FMMU, 获得 PDI 访问权
  │     └── configure_fmmus()
  │           ├── 第一轮: configure_fmmus(MasterRead)   // 配置输入映射
  │           │     └── [CoE 设备] configure_pdos_coe()
  │           │     └── [非CoE]    configure_pdos_eeprom()
  │           └── 第二轮: configure_fmmus(MasterWrite)  // 配置输出映射
  │                 // 结果: PDI 布局为 IIIIOOOO (输入在前, 输出在后)
  │
  ├── .configure_dc_sync()        // (可选) 配置 DC SYNC0/SYNC1
  │     └── [详见 §3.6]
  │
  ├── into_safe_op()
  │     └── transition_to(SafeOp)
  │           ├── for each SD: request_subdevice_state_nowait(SafeOp)
  │           │     └── FPWR AlControl ← AlControl::new(SafeOp)
  │           └── wait_for_state(SafeOp)
  │                 └── loop { is_state() → push_state_checks into frame → send → check }
  │
  └── into_op()
        └── transition_to(Op)
              ├── for each SD: request_subdevice_state_nowait(Op)
              └── wait_for_state(Op)

完整快捷路径:
  group.into_op() = into_safe_op() → .into_op()
                  = into_pre_op_pdi() → transition(SafeOp) → transition(Op)
```

### 3.5 周期性过程数据 (PDI) 调用流

```
应用周期循环:
  loop {
    group.tx_rx(&maindevice)  // 或 tx_rx_dc()
      │
      ├── pdi.write()                  // 获取 PDI 写锁
      │
      ├── loop {  // 大 PDI 可能需要多帧发送
      │     ├── alloc_frame()
      │     │
      │     ├── [如果 PDI 未发完]
      │     │     push_pdu_slice_rest(LRW(start_addr), pdi_chunk)
      │     │     // LRW = Logical Read Write, 一次操作同时读写 PDI
      │     │     // 帧容量限制: 尽可能填满当前帧
      │     │
      │     ├── [如果帧有剩余空间]
      │     │     push_state_checks(subdevices_iter, frame)
      │     │     // 打包 FPRD(AlStatus) 检查, 每帧最多 128 个
      │     │     // 与 PDI 数据复用同一帧避免额外网络开销
      │     │
      │     ├── mark_sendable() → wake_sender() → .await
      │     │
      │     ├── 处理收到的 PDI 响应:
      │     │     process_received_pdi_chunk()
      │     │     ├── 仅更新输入部分 (read_pdi_len 以前的字节)
      │     │     └── 输出部分由用户直接修改 PDI 缓冲区
      │     │
      │     └── 处理状态检查 PDU:
      │           AlControl::unpack_from_slice() → 记录各 SD 状态
      │   }
      │
      └── 返回 TxRxResponse { working_counter, subdevice_states, extra }

    // 用户处理过程数据:
    for mut sd in group.iter(&maindevice) {
      let io = sd.io_raw_mut();    // PdiIoRawWriteGuard (获取写锁)
      io.inputs();                  // &[u8] 只读
      io.outputs().iter_mut()...    // &mut [u8] 可写
    }
    // PdiIoRawWriteGuard drop → 释放写锁

    tick_interval.tick().await;
  }
```

### 3.6 Distributed Clock (DC) 调用流

#### 3.6.1 初始化阶段 (dc::configure_dc)

```
dc::configure_dc(maindevice, subdevices, now)
  │
  ├── latch_dc_times()
  │     ├── BWR DcTimePort0 ← 0u32         // 广播锁存接收时间
  │     └── for each DC-capable SD:
  │           ├── FPRD DcReceiveTime → u64   // 读取 DC 接收时间
  │           └── FPRD DcTimePort0 → [u32;4] // 读取四端口时间戳
  │
  ├── 拓扑分析: 为每个 SubDevice 识别父节点
  │     └── find_subdevice_parent(parents, subdevice)
  │           ├── 无前置设备 → 无父节点 (根设备)
  │           ├── 前置设备为 LineEnd → 向上回溯找 Fork/Cross (分支点)
  │           └── 其他 → 直接前置设备为父节点
  │
  ├── 配置传播延迟和偏移
  │     └── for each DC-capable SD:
  │           configure_subdevice_offsets()
  │             ├── 计算传播延迟 (propagation_delay)
  │             │   ├── Passthrough: parent_delta / 2
  │             │   ├── Fork (子设备): children_loop_time - this_prop_time) / 2
  │             │   ├── Fork (下游): parent_delta / 2
  │             │   └── Cross: 类似 Fork 但使用 intermediate 时间
  │             └── write_dc_parameters()
  │                   ├── FPWR DcSystemTimeOffset ← -(dc_receive_time) + now
  │                   └── FPWR DcSystemTimeTransmissionDelay ← propagation_delay
  │
  └── 返回 dc_master (DC 参考时钟设备)

dc::run_dc_static_sync(maindevice, dc_master, iterations)
  └── for i in 0..iterations (默认 10000):
        FRMW(dc_ref, DcSystemTime)  // 将参考时钟时间分发到所有设备
```

#### 3.6.2 运行阶段 (tx_rx_dc)

```
group.tx_rx_dc(&maindevice)
  │
  ├── FRMW(dc_ref, DcSystemTime) → u64        // 读取当前 DC 系统时间
  │     // 打包在 PDI 帧的第一个 PDU 位置
  │
  ├── LRW(pdi_start) ← pdi_data               // 过程数据读写
  │
  ├── FPRD AlStatus × N                        // SubDevice 状态检查
  │
  └── 计算同步信息:
        cycle_start_offset = time % sync0_period
        next_cycle_wait = (sync0_period - cycle_start_offset) + sync0_shift
        → CycleInfo { dc_system_time, next_cycle_wait, cycle_start_offset }
```

### 3.7 SDO/CoE 邮箱调用流

```
subdevice.sdo_read::<T>(index, sub_index)
  │
  └── Coe::new(&subdevice_ref).sdo_read(index, sub_index)
        │
        ├── [标准 SDO 上传]
        │     mailbox_write_read(SdoNormal::upload(...))
        │       │
        │       ├── wait_for_mailboxes()
        │       │     ├── 检查 OUT 邮箱是否为空 (读取 SM status)
        │       │     │   └── 如果满则读取清空 (最多重试 10 次)
        │       │     └── 等待 IN 邮箱可写 (轮询 SM status)
        │       │           └── .timeout(mailbox_echo)
        │       │
        │       ├── FPWR(write_mailbox.address) ← SdoNormal 请求包
        │       │     └── with_len(write_mailbox.len) // 填充完整邮箱长度
        │       │
        │       └── wait_for_mailbox_response(read_mailbox)
        │             ├── 轮询 SM status 等待 OUT 邮箱有数据
        │             │   └── .timeout(mailbox_response)
        │             └── FPRD(read_mailbox.address) → ReceivedPdu
        │
        ├── 解析邮箱头 (MailboxHeader)
        │     ├── 验证 mailbox_type == CoE
        │     └── 验证 counter 匹配
        │
        ├── 解析 CoE 头 (CoeHeader)
        │     └── 验证 service == SdoResponse
        │
        ├── [如果 expedited] → 直接从 4 字节数据字段解析
        ├── [如果 normal]   → 从后续 payload 解析
        └── [如果 segmented] → 多轮 mailbox 交互拼接完整数据
              └── loop:
                    SdoSegmented::upload_request() → write_read → 拼接
                    直到 more_follows == false


subdevice.sdo_write::<T>(index, sub_index, value)
  └── Coe::new().sdo_write(index, sub_index, value)
        └── mailbox_write_read(SdoExpedited::download(...))
              // 同上邮箱交互流程

subdevice.sdo_write_array(index, values)
  └── sdo_write(index, 0, 0u8)              // 清零计数
      for (i, v) in values:
        sdo_write(index, i+1, v)             // 写每个子索引
      sdo_write(index, 0, len as u8)         // 设置总数
```

### 3.8 EEPROM 读写调用流

```
SubDeviceEeprom (via EepromDataProvider trait)
  │
  ├── DeviceEeprom::read_chunk(start_word)     // 从设备 EEPROM 读取
  │     ├── FPWR SiiConfig ← setup             // 配置 SII 接口
  │     ├── FPWR SiiAddress ← start_word       // 设置起始地址
  │     ├── FPWR SiiConfig ← read_command      // 发送读命令
  │     ├── 轮询等待 EEPROM 就绪               // loop { FPRD SiiConfig → check busy }
  │     │     └── .timeout(eeprom)
  │     └── FPRD SiiData → [u8; 4/8]           // 读取数据
  │
  └── EepromRange<P> (实现 embedded_io_async::Read/Write)
        ├── read()  → 偏移管理 + 逐 chunk 读取
        └── write() → 逐 word 写入 + CRC 校验

高层 EEPROM 操作:
  eeprom.identity()           → SII Category 解析
  eeprom.device_name()        → 字符串解析
  eeprom.sync_managers()      → SM 配置列表
  eeprom.fmmus()              → FMMU 使用列表
  eeprom.maindevice_read_pdos()  → RxPDO 映射
  eeprom.maindevice_write_pdos() → TxPDO 映射
  eeprom.mailbox_config()     → 邮箱默认配置
```

---

## 4. 代码设计特点深度解析

### 4.1 Typestate 模式 — 编译期状态机安全

EtherCrab 大量使用 **typestate 模式** 将 EtherCAT 状态机编码到类型系统中：

```rust
pub struct SubDeviceGroup<
    const MAX_SUBDEVICES: usize,
    const MAX_PDI: usize,
    R: RawRwLock = DefaultLock,
    S = PreOp,        // ← 状态 typestate
    DC = NoDc,        // ← DC 配置 typestate
>
```

**具体状态类型**: `Init`, `PreOp`, `PreOpPdi`, `SafeOp`, `Op`

**效果**:
- `tx_rx()` 仅在 `HasPdi` trait bound (PreOpPdi/SafeOp/Op) 的状态下可用
- `configure_dc_sync()` 仅在 `IsPreOp` (PreOp/PreOpPdi) 状态下可调用
- `tx_rx_dc()` 仅在 `HasPdi + HasDc` 状态下可用
- 状态转换是 `self → NewType` 的消费性转换，不可能在错误状态调用方法

**优势**: 在编译期彻底消除了非法状态转换的可能性。

### 4.2 Const Generics — 零堆分配的 no_std 兼容

所有缓冲区大小在编译期确定:

```rust
static PDU_STORAGE: PduStorage<MAX_FRAMES, MAX_PDU_DATA> = PduStorage::new();
let group: SubDeviceGroup<MAX_SUBDEVICES, PDI_LEN> = ...;
```

**关键 const generic 参数**:
- `PduStorage<N, DATA>`: N 个帧槽位,每个 DATA 字节
- `SubDeviceGroup<MAX_SUBDEVICES, MAX_PDI>`: 最多 MAX_SUBDEVICES 个设备, PDI 长度不超过 MAX_PDI

**容器选择**: 全部使用 `heapless` crate 的定长集合 (`heapless::Vec`, `heapless::Deque`, `heapless::String`, `heapless::FnvIndexMap`)，完全避免堆分配。

### 4.3 原子状态机 — 无锁帧管理

`FrameElement` 使用 `AtomicFrameState` 实现无锁的帧生命周期管理:

```
None → Created → Sendable → Sending → Sent → RxBusy → RxDone → RxProcessing → None
```

每个状态转换使用 `compare_exchange` (CAS) 操作:

```rust
// alloc_frame: None → Created
status.compare_exchange(FrameState::None, FrameState::Created, ...)
// mark_sendable: Created → Sendable
status.compare_exchange(FrameState::Created, FrameState::Sendable, ...)
// TX task: Sendable → Sending
status.compare_exchange(FrameState::Sendable, FrameState::Sending, ...)
```

**优势**: 
- 完全无锁，TX/RX 线程和用户 async 代码可安全并发操作
- 状态不匹配会立即返回错误 (`PduError::SwapState`)，不会死锁
- `AtomicWaker` 实现跨线程的 Future 唤醒

### 4.4 Builder Pattern + Fluent API — 命令构建

```rust
// 读操作构建
Command::fprd(address, register)    // → WrappedRead
    .ignore_wkc()                   // 可选: 忽略 WKC 校验
    .receive::<AlControl>(maindevice)  // 发送并解码
    .await?;

// 写操作构建
Command::fpwr(address, register)    // → WrappedWrite
    .with_wkc(num_subdevices)       // 可选: 设定期望 WKC
    .with_len(mailbox_len)          // 可选: 覆盖长度
    .send(maindevice, data)         // 发送
    .await?;
```

**设计特点**:
- `WrappedRead` / `WrappedWrite` 是 `Copy + Clone` 的小型值，零开销
- 默认 WKC=1，可通过 `.ignore_wkc()` / `.with_wkc(n)` 调整
- `receive::<T>()` 自动从 `T::PACKED_LEN` 推导 PDU 读取长度
- 所有地址类型 (`u16` register) 都接受 `impl Into<u16>` (RegisterAddress 枚举自动转换)

### 4.5 零拷贝 PDI 访问 — RwLock + UnsafeCell

PDI 使用 `RwLock<MySyncUnsafeCell<[u8; MAX_PDI]>>` 实现:

```rust
pdi: RwLock<R, MySyncUnsafeCell<[u8; MAX_PDI]>>
```

**读写分离**:
- `tx_rx()` 获取写锁:更新输入区域,发送输出区域
- `io_raw()` 获取读锁: 只读访问输入+输出
- `io_raw_mut()` 获取写锁: 用户修改输出

**PDI 布局**: `[inputs...][outputs...]` — 输入在前输出在后的连续内存

`SubDevicePdi` 通过 `IoRanges` 记录每个 SubDevice 的输入/输出在 PDI 中的字节偏移范围，实现精确的子设备级数据隔离。

### 4.6 异步超时框架 — Future Combinator

自定义 `TimeoutFuture` 包装器，不依赖 tokio 的超时机制:

```rust
impl<T: Future<Output = Result<O, Error>>> IntoTimeout<O> for T {
    fn timeout(self, timeout: LabeledTimeout) -> TimeoutFuture<...> { ... }
}
```

**标签化超时**: 每个超时携带 `TimeoutKind` (Pdu, StateTransition, Eeprom, MailboxEcho, MailboxResponse)，错误信息中可精确定位超时原因。

**跨平台 Timer**:
- `std`: `async_io::Timer`
- `no_std`: `embassy_time::Timer`
- `miri`: `core::future::Pending` (测试用)

### 4.7 帧合并优化 — 多 PDU 装箱

`tx_rx()` / `tx_rx_dc()` 实现了智能帧合并:

```rust
// 一个以太网帧中可以包含:
frame.push_pdu(FRMW, dc_time, ...);           // DC 同步 PDU
frame.push_pdu_slice_rest(LRW, pdi_chunk);     // PDI 数据 (填满剩余空间)
push_state_checks(subdevices, &mut frame);      // 状态检查 PDU (剩余空间继续填)
```

**设计要点**:
- `push_pdu_slice_rest` 将 PDI 数据切分到帧最大容量
- 状态检查 PDU 与 PDI 数据复用同一帧，减少帧数量
- 大 PDI 自动拆分为多帧，后续帧继续装入状态检查
- 帧上限 128 个状态检查 PDU，避免 PDU index 耗尽

### 4.8 EEPROM 的 embedded_io_async 抽象

```rust
pub trait EepromDataProvider: Clone {
    async fn read_chunk(&mut self, start_word: u16) -> Result<impl Deref<Target = [u8]>, Error>;
    async fn write_word(&mut self, start_word: u16, data: [u8; 2]) -> Result<(), Error>;
    async fn clear_errors(&self) -> Result<(), Error>;
}
```

通过实现 `embedded_io_async::Read/Write` for `EepromRange<P>`，将 EEPROM 访问抽象为流式 I/O。`DeviceEeprom` (真实硬件) 和 `FileProvider` (文件, 用于测试) 都实现相同 trait，便于测试解耦。

### 4.9 sealed trait — 防止下游扩展

```rust
#[sealed::sealed]
pub trait SubDeviceGroupHandle: Sync {
    fn id(&self) -> GroupId;
    unsafe fn push(&self, subdevice: SubDevice) -> Result<(), Error>;
    fn as_ref(&self) -> SubDeviceGroupRef<'_>;
}
```

`SubDeviceGroupHandle` 使用 `sealed` crate 保证只有 `SubDeviceGroup` 可以实现此 trait，防止用户创建非法的 Group 实现。

### 4.10 defmt/log 双日志系统

通过自定义 `fmt` 模块实现 `defmt` 和 `log` 的统一日志抽象:

```rust
fmt::debug!("Discovered {} SubDevices", num_subdevices);
```

编译时根据 feature flag 选择具体后端，`no_std` 使用 `defmt`，`std` 使用 `log`。

### 4.11 ethercrab-wire 协议编解码

自定义 derive 宏将 EtherCAT 线上协议编码规则声明化:

```rust
#[derive(EtherCrabWireReadWrite)]
#[wire(bytes = 16)]
pub struct SdoExpedited {
    #[wire(bytes = 6)]
    pub header: MailboxHeader,
    #[wire(bytes = 2)]
    pub coe_header: CoeHeader,
    #[wire(bytes = 4)]
    pub sdo_header: SdoHeader,
    #[wire(bytes = 4)]
    pub data: [u8; 4],
}
```

支持位级精确控制: `#[wire(bits = 3, post_skip = 1)]`。

---

## 5. 代码审查意见

### ✅ Good Practices

1. **Typestate 模式的彻底应用**: 状态机安全性在编译期保证，完全无运行时开销，是 Rust 类型系统的教科书级应用。

2. **零分配设计**: 全栈使用 `heapless` + const generics，真正做到了 `no_std` 首要支持而非事后添加。

3. **清晰的帧生命周期管理**: FrameElement 的 8 态原子状态机，配合 CAS 操作，实现了高效的无锁帧复用。

4. **优秀的文档与示例**: `lib.rs` 中完整的 EK1100 示例、每个公开方法的文档示例、FAQ.md、SPECNOTES.md 等都做到了工业级文档水平。

5. **全面的测试覆盖**: 集成测试使用 pcap 录制回放实现了真实网络流量的确定性测试（replay-*.rs），单元测试覆盖帧构建、状态转换、大规模分帧等边界情况。

6. **`#[deny(missing_docs)]`**: 强制公开 API 文档完整性。

7. **`retain` 设计**: PDI 布局 `IIIIOOOO` (输入连续、输出连续) 的设计简化了 LRW 操作的数据处理，减少了内存碎片化。

8. **平台抽象**: `std` 模块通过条件编译隔离平台特定代码（Linux raw socket / io_uring / XDP / Windows pcap），核心逻辑完全平台无关。

9. **ethercrab-wire derive 宏**: 实现了声明式的线上协议编解码，避免了手工解析的错误倾向性，且支持位级精度。

10. **帧合并优化**: 将 DC 同步、PDI 数据、状态检查合并到同一以太网帧中发送，最大化网络带宽利用率。

---

*本文档基于 ethercrab v0.6.0 源码的静态分析生成，覆盖了从应用层到网络传输层的完整调用链路。*
