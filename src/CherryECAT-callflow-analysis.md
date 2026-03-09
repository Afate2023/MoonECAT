# CherryECAT 完整项目调用流分析 & 代码审查报告

> 审查日期: 2026-03-03  
> 项目版本: CherryECAT (Apache-2.0)  
> 审查范围: 全部源码 (include/, src/, osal/, port/, demo/)

---

## 目录

1. [项目架构总览](#1-项目架构总览)
2. [分层架构与模块职责](#2-分层架构与模块职责)
3. [完整调用流分析](#3-完整调用流分析)
4. [代码审查结果](#4-代码审查结果)
5. [总结与建议](#5-总结与建议)

---

## 1. 项目架构总览

CherryECAT 是一个面向嵌入式 RTOS 环境的 EtherCAT 主站协议栈实现，采用 C 语言编写，支持 FreeRTOS、RT-Thread、ThreadX 等多种 RTOS，目前已适配 HPMicro、Renesas、STM32H7 等硬件平台。

### 1.1 模块依赖关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                     Demo / Application Layer                     │
│  (demo/hpmicro/main.c, ec_pdo_callback, ethercat CLI)           │
└─────────────┬───────────────────────────────────────────────────┘
              │
┌─────────────▼───────────────────────────────────────────────────┐
│                    Command Interface (ec_cmd.c)                  │
│  CLI命令解析: start/stop/slaves/coe_read/coe_write/foe/eoe...   │
└─────────────┬───────────────────────────────────────────────────┘
              │
┌─────────────▼───────────────────────────────────────────────────┐
│                    Master Core (ec_master.c)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐     │
│  │ 周期性PDO处理 │  │ 非周期线程    │  │ 从站扫描线程        │     │
│  │ (htimer ISR) │  │ (nonperiod)  │  │ (scan_thread)      │     │
│  └───────┬──────┘  └──────┬───────┘  └────────┬───────────┘     │
│          │                │                   │                  │
│  ┌───────▼────────────────▼───────────────────▼───────────┐     │
│  │         Datagram Queue (发送/接收管理)                    │     │
│  │  ec_master_queue_datagram → ec_master_send_datagrams     │     │
│  │  ec_master_receive_datagrams                             │     │
│  └─────────────────────────┬─────────────────────────────┘     │
└─────────────────────────────┼─────────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────────┐
│                    Slave Management (ec_slave.c)               │
│  扫描 → SII读取 → 状态机切换(INIT→PREOP→SAFEOP→OP)            │
│  SM/FMMU配置 → DC时钟同步 → PDO映射                            │
└──────┬──────────┬───────────┬──────────────────────────────────┘
       │          │           │
┌──────▼──┐ ┌────▼────┐ ┌────▼────┐
│ CoE     │ │ FoE     │ │ EoE     │    ← 应用层协议
│(ec_coe) │ │(ec_foe) │ │(ec_eoe) │
└──────┬──┘ └────┬────┘ └────┬────┘
       │         │           │
┌──────▼─────────▼───────────▼──────────────────────────────────┐
│                    Mailbox Layer (ec_mailbox.c)                 │
│  ec_mailbox_fill_send → ec_mailbox_send → ec_mailbox_receive   │
└───────────────────────────┬───────────────────────────────────┘
                            │
┌───────────────────────────▼───────────────────────────────────┐
│                    Datagram Layer (ec_datagram.c)               │
│  报文创建 (APRD/APWR/FPRD/FPWR/BRD/BWR/LRD/LWR/LRW...)       │
└───────────────────────────┬───────────────────────────────────┘
                            │
┌───────────────────────────▼───────────────────────────────────┐
│                    Network Device (ec_netdev.c)                │
│  帧组装/发送 → PHY管理(chry_phy) → 链路状态检测                  │
└───────────────────────────┬───────────────────────────────────┘
                            │
┌───────────────────────────▼───────────────────────────────────┐
│              Hardware Abstraction                               │
│  ┌─────────────────────┐  ┌──────────────────────────────┐    │
│  │ OSAL (FreeRTOS/RTT/ │  │ Port (netdev_hpmicro.c /     │    │
│  │ ThreadX / NuttX)    │  │ netdev_renesas / netdev_stm32)│    │
│  │ 线程/信号量/互斥锁    │  │ DMA/ENET驱动/中断              │    │
│  └─────────────────────┘  └──────────────────────────────┘    │
└───────────────────────────────────────────────────────────────┘
```

---

## 2. 分层架构与模块职责

### 2.1 核心模块

| 模块 | 文件 | 职责 |
|------|------|------|
| **Master** | `ec_master.c/h` | 主站生命周期管理、周期性处理、datagram队列调度、DC同步PI控制 |
| **Slave** | `ec_slave.c/h` | 从站扫描、SII解析、状态机管理、SM/FMMU/DC配置 |
| **Datagram** | `ec_datagram.c/h` | EtherCAT datagram构建、内存管理、各种命令类型封装 |
| **Mailbox** | `ec_mailbox.c/h` | 邮箱协议通用层：发送/接收/状态轮询 |
| **CoE** | `ec_coe.c/h` | CAN over EtherCAT: SDO上传/下载 (expedited/normal/segmented) |
| **FoE** | `ec_foe.c/h` | File over EtherCAT: 文件读写 (声明但未实现) |
| **EoE** | `ec_eoe.c/h` | Ethernet over EtherCAT: 以太网隧道 (声明但未实现) |
| **SII** | `ec_sii.c/h` | Slave Information Interface: EEPROM读写 |
| **NetDev** | `ec_netdev.c/h` | 网络设备抽象、PHY管理、帧收发统计 |
| **Slave Table** | `ec_slave_table.c` | 预定义从站配置表 (PDO映射) |
| **CMD** | `ec_cmd.c/h` | CLI命令行工具接口 |
| **Timestamp** | `ec_timestamp.c/h` | 高精度纳秒时间戳 (RISC-V MCYCLE / ARM DWT) |

### 2.2 辅助模块

| 模块 | 文件 | 职责 |
|------|------|------|
| **OSAL** | `ec_osal.h`, `ec_osal_freertos.c` 等 | 操作系统抽象层 |
| **Port** | `ec_port.h`, `netdev_*.c` | 硬件平台适配 |
| **Definitions** | `ec_def.h` | 协议常量/类型定义 |
| **Error** | `ec_errno.h` | 错误码定义 |
| **Log** | `ec_log.h` | 日志宏 (彩色输出) |
| **Utility** | `ec_util.h` | 工具宏 (字节读写/对齐/字节序) |
| **List** | `ec_list.h` | 双向链表实现 |
| **Config** | `cherryecat_config_template.h` | 配置模板 |
| **PHY** | `phy/chry_phy*.h` | PHY驱动层 (DP83847/KSZ8081/LAN8720等) |

---

## 3. 完整调用流分析

### 3.1 系统初始化流程

```
main()
  ├── board_init()                          // 硬件初始化
  ├── xTaskCreate(task_start)               // 创建启动任务
  └── vTaskStartScheduler()                 // 启动调度器

task_start()
  ├── shell_init()                          // 初始化Shell
  ├── ec_master_cmd_init(&g_ec_master)      // 注册CLI命令
  └── ec_master_init(&g_ec_master, 0)       // 【核心】初始化主站
        ├── memset(master, 0, ...)
        ├── ec_timestamp_init()                    // 初始化纳秒时间戳
        │     └── ec_get_cpu_frequency()           // 获取CPU频率
        │
        ├── ec_netdev_init(0)                      // 初始化网络设备
        │     ├── ec_netdev_low_level_init()        // 底层Ethernet初始化
        │     │     ├── board_init_enet_pins()        // GPIO配置
        │     │     ├── board_reset_enet_phy()        // PHY复位
        │     │     ├── enet_init(ENET)               // MAC+DMA初始化
        │     │     └── 填充TX缓冲区以太网头(dst=FF:FF:FF:FF:FF:FF, type=0x88A4)
        │     │
        │     ├── chry_phy_init()                    // PHY初始化
        │     └── 设置netdev名称/MAC/链路状态
        │
        ├── ec_datagram_init(main_datagram)        // 主datagram (1486字节)
        ├── ec_datagram_init(dc_ref_sync_datagram) // DC参考时钟同步datagram
        ├── ec_datagram_init(dc_all_sync_datagram) // DC全从站同步datagram
        │
        ├── ec_osal_mutex_create(scan_lock)        // 创建扫描互斥锁
        ├── ec_osal_sem_create(nonperiod_sem)      // 创建非周期信号量
        │
        ├── ec_osal_thread_create("ec_nonperiod")  // 【线程1】非周期处理线程
        │     └── ec_master_nonperiod_thread()
        │           └── while(1):
        │                 sem_take(nonperiod_sem, 10ms)
        │                 enter_critical → ec_master_send() → leave_critical
        │
        ├── ec_osal_thread_create("ec_scan")       // 【线程2】从站扫描线程
        │     └── ec_master_scan_thread()
        │           └── while(1):
        │                 ec_slaves_scanning(master)
        │                 sleep(100ms)
        │
        ├── ec_osal_timer_create("ec_linkdetect")  // 链路检测定时器 (1s)
        │     └── ec_netdev_linkpoll_timer()
        │           └── ec_netdev_poll_link_state() // PHY状态轮询
        │
        └── ec_master_enter_idle()                 // 进入IDLE阶段
              └── thread_resume(nonperiod_thread)
```

### 3.2 从站扫描流程 (`ec_slaves_scanning`)

```
ec_slaves_scanning(master)
  │
  ├── 【阶段1: 链路检测】
  │   for each netdev:
  │     检测link_state变化(up/down)
  │     link_down → ec_master_stop() → ec_master_clear_slaves()
  │
  ├── 【阶段2: 广播探测】
  │   for each netdev:
  │     BRD(AL_STAT) → 获取working_counter = 在线从站数
  │     如果数量变化 → 标记rescan_required
  │
  ├── 【阶段3: 总线扫描 (rescan_required时)】
  │   ec_master_stop()
  │   ec_master_clear_slaves()                      // 清理旧从站
  │   malloc(slave_count * sizeof(ec_slave_t))      // 分配从站数组
  │   │
  │   for each netdev:
  │     BWR(STATION_ADDR, 0)                         // 清除站地址
  │     BWR(RCV_TIME, 0)                             // 清除接收时间
  │   │
  │   for each slave_index:
  │     ├── APWR(STATION_ADDR, station_addr)          // 设置站地址(1001+)
  │     ├── FPRD(AL_STAT)                             // 读取AL状态
  │     ├── FPRD(TYPE, 12)                            // 读取基本信息
  │     │     → base_type, revision, build, fmmu_count, sync_count
  │     │     → port_desc, dc_supported, dc_range
  │     │
  │     ├── if dc_supported:
  │     │     FPRD(SYS_TIME) → 读取系统时间
  │     │     FPRD(RCV_TIME) → 读取端口接收时间
  │     │     FPRD(RCVT_ECAT_PU) → 计算system_time_offset
  │     │
  │     ├── FPRD(ESC_DL_STAT) → 读取端口链路状态
  │     │
  │     ├── 【SII EEPROM全量读取】
  │     │   do { ec_sii_read(offset) } while cat_type != 0xFFFF
  │     │   → 确定SII总大小 → malloc → 全量读取
  │     │   → 解析: vendor_id, product_code, revision_number
  │     │   → 解析: mailbox配置, 协议支持
  │     │   → 解析categories: STRINGS, GENERAL, SM, TXPDO, RXPDO
  │     │
  │     └── ec_slave_config(slave)                    // 配置从站
  │
  ├── 【阶段4: DC计算】
  │   ec_master_calc_dc(master)
  │     ├── ec_master_find_dc_ref_clock()             // 找参考时钟(第一个DC从站)
  │     ├── ec_master_calc_topology()                 // 计算拓扑结构
  │     └── ec_master_calc_transmission_delays()       // 计算传输延迟
  │
  └── 【阶段5: 持续状态监控】
      ec_master_scan_slaves_state(master)
        for each slave:
          FPRD(AL_STAT) → 检查状态变化
          如有ACK_ERR → ec_slave_state_clear_ack_error()
          如状态不匹配 → ec_slave_config(slave)
```

### 3.3 从站配置流程 (`ec_slave_config`)

```
ec_slave_config(slave)
  │
  ├── 【Step 1】 切换到INIT
  │   ec_slave_state_change(slave, INIT)
  │     FPWR(AL_CTRL, INIT) → 等待FPRD(AL_STAT)==INIT
  │
  ├── 【Step 2-3】 清除FMMU和SM
  │   FPWR(FMMU[0], 0x00 * fmmu_count)
  │   FPWR(SYNCM[0], 0x00 * sync_count)
  │
  ├── 【Step 4】 清除DC激活
  │   FPWR(CYC_UNIT_CTRL, 0)
  │
  ├── 【Step 5-6 (BOOT模式)】
  │   if requested_state==BOOT && FOE支持:
  │     配置Bootstrap SM0/SM1
  │     切换到BOOT状态
  │
  ├── 【Step 7-8】 配置Mailbox SM并切换到PREOP
  │   if CoE支持:
  │     FPWR(SYNCM[0:1], MBX_SM配置)
  │   ec_slave_state_change(slave, PREOP)
  │
  ├── 【Step 9-20 (CoE PDO配置)】
  │   if enable_pdo_assign:
  │     SDO Download 0x1C12 = [清空→写入→设置计数]   // RxPDO Assignment
  │     SDO Download 0x1C13 = [清空→写入→设置计数]   // TxPDO Assignment
  │   if enable_pdo_configuration:
  │     SDO Download PDO Mapping Objects              // PDO Mapping
  │
  ├── 【Step 21-22】 配置PDO SM和FMMU
  │   FPWR(SYNCM[2:3], PDO_SM配置)
  │   FPWR(FMMU[0:1], FMMU配置)
  │
  ├── 【Step 23-27 (DC配置)】
  │   if dc_assign_activate:
  │     FPWR(SYS_TIME_OFFSET, offset+delay)
  │     FPWR(SYNC0_CYC_TIME, cycle_time)
  │     wait SYS_TIME_DIFF < 100ns                   // 等待DC同步
  │     FPWR(START_TIME_CO, start_time)
  │     FPWR(CYC_UNIT_CTRL, dc_assign_activate)
  │
  ├── 【Step 28-29】 切换到SAFEOP → OP
  │   ec_slave_state_change(slave, SAFEOP)
  │   ec_slave_state_change(slave, OP)
  │
  └── return 0 (成功)
```

### 3.4 主站启动流程 (`ec_master_start`)

```
ec_master_start(master)
  │
  ├── 等待scan_done
  ├── mutex_take(scan_lock)
  │
  ├── for each slave:
  │     计算 logical_start_address (累加)
  │     计算 odata_size, idata_size
  │     配置 SM pdo_assign & pdo_mapping
  │     更新 SM length, FMMU配置
  │     累加 actual_pdo_size
  │     #ifdef PDO_MULTI_DOMAIN:
  │       ec_datagram_init_static(slave.pdo_datagram, pdo_buffer)
  │     expected_working_counter += 3
  │
  ├── #ifndef PDO_MULTI_DOMAIN:
  │     ec_datagram_init_static(master.pdo_datagram, pdo_buffer, actual_pdo_size)
  │     ec_datagram_lrw(0, actual_pdo_size)              // 单LRW覆盖所有从站
  │
  ├── ec_htimer_start(cycle_time, ec_master_period_process) // 启动硬件定时器
  │
  ├── for each slave:
  │     requested_state = OP, force_update = true
  │
  └── mutex_give(scan_lock)
```

### 3.5 周期性PDO处理 (`ec_master_period_process`) - **实时路径**

```
ec_master_period_process(arg)                          // 硬件定时器中断回调
  │
  ├── if phase != OPERATION → return
  │
  ├── 【DC同步处理】
  │   if dc_ref_clock && dc_sync_with_dc_ref_enable:
  │     读取dc_all_sync_datagram → dc_ref_systime
  │     ec_master_dc_sync_with_pi(delta) → PI控制 → offsettime
  │     ec_htimer_update(cycle_time + offset)           // 动态调整定时器周期
  │   else:
  │     写入master系统时间 → dc_ref_sync_datagram
  │     queue(dc_ref_sync_datagram)
  │
  │   queue(dc_all_sync_datagram)                       // 读取DC参考时间
  │
  ├── 【PDO数据排队】
  │   #ifndef MULTI_DOMAIN:
  │     queue(master.pdo_datagram)                       // 单个LRW datagram
  │   #else:
  │     for each slave: queue(slave.pdo_datagram)        // 每从站独立datagram
  │
  ├── 【发送】
  │   ec_master_send(master)
  │     ├── 超时检查: 清理timed_out的datagram
  │     ├── 链路检查: 链路down时标记ERROR
  │     └── ec_master_send_datagrams(netdev_idx)
  │           ├── 从datagram_queue取出状态为QUEUED的datagram
  │           ├── 组装EtherCAT帧 (帧头+多个datagram+填充)
  │           ├── ec_netdev_send() → ec_netdev_low_level_output()
  │           └── 标记datagram为SENT
  │
  └── 【性能统计】
      记录 period_ns, send_exec_ns, offset_ns
```

### 3.6 接收处理流程

```
硬件中断 → ec_netdev_receive(netdev, frame, size)
  │
  ├── 更新统计: rx_count, rx_bytes
  └── ec_master_receive(master, netdev_idx, ec_data, ec_size)
        │
        ├── ec_master_receive_datagrams()
        │     ├── 校验帧头大小/帧长度
        │     ├── while(cmd_follows):
        │     │     解析datagram_header: type, index, data_size
        │     │     在datagram_queue中匹配: index+state+type+size
        │     │     if 匹配:
        │     │       复制接收数据 (非写命令时)
        │     │       设置working_counter
        │     │       状态→RECEIVED, unqueue, sem_give(waiter)
        │     │     else:
        │     │       stats.unmatched++
        │
        ├── if phase != OPERATION → return
        │
        └── 【PDO回调分发】
            #ifndef MULTI_DOMAIN:
              if pdo_datagram.state == RECEIVED:
                for each slave:
                  slave.config.pdo_callback(slave, output, input)
                actual_working_counter = pdo_datagram.wc
            #else:
              for each slave:
                if slave.pdo_datagram.state == RECEIVED:
                  slave.config.pdo_callback(slave, output, input)
                  actual_working_counter += slave.pdo_wc
```

### 3.7 阻塞式Datagram发送 (`ec_master_queue_ext_datagram`)

用于非周期操作（扫描、CoE、SII读写等）：

```
ec_master_queue_ext_datagram(master, datagram, wakeup=true, waiter=true)
  │
  ├── enter_critical
  │   datagram.waiter = true
  │   ec_master_queue_datagram(datagram)                // 加入队列
  │   sem_give(nonperiod_sem)                           // 唤醒非周期线程发送
  ├── leave_critical
  │
  ├── sem_take(datagram.wait, FOREVER)                  // 阻塞等待接收/超时
  │
  └── 检查结果:
      RECEIVED && wc>0 → return 0
      RECEIVED && wc==0 → return -EC_ERR_WC
      TIMED_OUT → return -EC_ERR_TIMEOUT
      ERROR → return -EC_ERR_IO
```

### 3.8 CoE SDO传输流

```
ec_coe_download(master, slave_idx, datagram, index, subindex, buf, size, CA)
  │
  ├── size <= 4:
  │   ec_coe_download_expedited()                       // 加速传输
  │     mailbox_fill_send(COE, 12B) → 填充SDO头 → mailbox_send()
  │     mailbox_receive() → 验证响应
  │
  ├── size <= max_data_size:
  │   ec_coe_download_common()                          // 普通传输
  │     mailbox_fill_send(COE, 12B+data) → 填充SDO头+size字段 → mailbox_send()
  │     mailbox_receive() → 验证响应
  │
  └── size > max_data_size:
      ec_coe_download_common() (首段)
      while(remaining > 0):
        ec_coe_download_segment()                       // 分段传输
          mailbox_fill_send(COE, 3B+seg) → toggle → mailbox_send()
          mailbox_receive() → 验证toggle

ec_coe_upload(master, slave_idx, datagram, index, subindex, buf, maxsize, size, CA)
  │
  ├── mailbox_fill_send(COE, upload_request)
  ├── mailbox_send() → mailbox_receive()
  │
  ├── 判断expedited:
  │   是 → 直接复制4字节以内数据
  │   否 → 复制首段数据
  │         while(offset < total_size):
  │           发送segment_upload请求 → toggle
  │           接收segment_upload响应 → 复制数据
  │           检查last标志
  └── return total_size
```

---

## 4. 代码审查结果

### ✅ Good Practices (优秀实践)

---

#### G-01: 清晰的分层架构设计

项目采用了非常清晰的分层架构：应用层 → 命令层 → 协议层 → 报文层 → 网络设备层 → 硬件抽象层。每层职责明确，耦合度低。特别是 `ec_osal.h` 和 `ec_port.h` 的抽象设计，使得多 RTOS / 多硬件平台适配非常方便。

#### G-02: 完善的 EtherCAT 协议实现

从站扫描 → SII 读取解析 → 状态机管理 → CoE SDO (expedited/normal/segmented) → PDO映射配置 → DC时钟同步的完整实现链路健全。PI 控制器进行 DC 同步的实现也是工业级做法。

#### G-03: 良好的错误码体系

`ec_errno.h` 定义了详尽的错误码，涵盖了各协议层的错误类型。每个错误都有清晰的注释说明。

#### G-04: `EC_FAST_CODE_SECTION` 用于实时关键路径

将 `ec_master_send_datagrams()`、`ec_master_receive_datagrams()`、`ec_master_period_process()` 等实时关键函数标记为 `EC_FAST_CODE_SECTION`，支持将关键代码放置到快速执行内存（如 TCM/ITCM），对实时性能有显著提升。

#### G-05: 多域 PDO (CONFIG_EC_PDO_MULTI_DOMAIN) 可选配置

通过编译宏支持单 LRW datagram（低开销，所有从站共享一个逻辑域）和多域模式（每从站独立 datagram，更灵活），适应不同应用场景。

#### G-06: 详尽的 CLI 诊断工具

`ec_cmd.c` 提供了丰富的诊断命令（master状态、slave详情、PDO读写、CoE SDO读写、SII读写、性能统计），极大方便了调试和现场问题排查。

#### G-07: PHY 驱动抽象层设计

`phy/chry_phy.h` 提供了统一的 PHY 驱动接口，支持 DP83847、DP83848、KSZ8081、LAN8720、RTL8201、RTL8211 等主流 PHY 芯片，通过函数指针实现多态，扩展性好。

#### G-08: 协议错误字符串映射

`ec_common.c` 提供了 AL Status Code、Mailbox Error、SDO Abort Code、FoE/EoE Error Code 到可读字符串的映射，错误信息输出友好。

#### G-09: 从站配置表的预定义支持

`ec_slave_table.c` 预定义了多种从站（HPM IO、CIA402 CSP/CSV、Leadshine、SG-ELC、Inovance SV660N 多种模式），开箱即用的体验良好。

---

## 5. 总结与建议

### 架构层面建议

1. **线程安全**: 周期性定时器回调（`ec_master_period_process`）与非周期线程共享 `datagram_queue`，前者在中断上下文运行但通过 `ec_osal_enter_critical_section` 在非周期线程中保护。需确保所有平台的 `ec_htimer_cb` 不在 ISR 中运行，或在 ISR 中也保护队列操作。

2. **可测试性**: 当前缺少单元测试框架。建议至少为 datagram 组装/解析、CoE 协议编解码、SII 解析增加 host-side 单元测试。

3. **配置验证**: `ec_master_start()` 中大量使用 `EC_ASSERT_MSG` 进行配置验证。在生产环境中 assert 可能被禁用（`CONFIG_EC_ASSERT_DISABLE`），此时这些检查全部失效。建议关键检查改用条件判断+错误返回。

4. **文档**: 头文件注释质量较高，但缺少架构级别的设计文档和 API 使用指南。`README.md` 提供了基本信息，但移植指南和 API 参考文档不足。
