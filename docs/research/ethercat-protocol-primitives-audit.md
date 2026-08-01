# EtherCAT 协议原语完整性审计

审计日期：2026-08-01

## Scope

本审计回答的是“MoonECAT 作为 EtherCAT 主站库，协议原语是否完整”，而不只是 Mailbox 是否完整。审计范围分成两类：

1. 线协议原语：封装、头、位域、命令/服务判别值、错误帧、寄存器实体及其编码/解码。
2. 主站服务原语：主站能够发起或接收的读、写、状态转换、邮箱事务和应用协议事务。

以下内容不直接记作 MoonECAT 缺失：

- PHY 线路编码、ESC 内部端口转发和 PDI 硬件实现；它们位于网卡或从站控制器边界之外。
- ETG.1000.4 的 PSM、DHSM、SYSM、RMSM、SIISM、MIISM、DCSM，以及 ETG.1000.6 的从站侧 FSPM/ARPM/DMPM 状态机本体。主站需要实现相应的访问和恢复行为，但不需要复制从站内部状态机。
- ESI XML 模型本身。它是配置描述模型，不是线上帧原语；本审计只检查其数据是否能投影到 SII、SM、FMMU、PDO、DC 和 Mailbox 配置。

规范基线为仓库内 ETG.1000.1 至 ETG.1000.6 v1.0.2、ETG.2010 v1.0.2、ETG.2000 v1.0.18 和 ETG.1500。参考实现为 SOEM、IgH EtherCAT Master、CherryECAT 和 EtherCrab。参考实现中晚于本地规范的扩展值单独标记，不能反推为本地规范必选项。

状态含义：

- 完整：主站所需闭集值及主要线编码/解码和服务路径均存在，未发现规范偏差。
- 部分：有可工作的主路径，但缺少结构化位域、反向编解码、严格校验或次级服务。
- 缺失：规范中存在且对通用主站有意义，当前没有对应原语。
- 偏差：当前实现与规范或多个参考实现明确冲突。
- 不适用：从站/PHY 内部原语，不属于 MoonECAT 主站库责任。
- 需额外规范：ETG.1000 本地资料没有给出完整编码，不能仅凭参考项目补成“规范实现”。

本轮共审计 80 个原语族：21 个完整、36 个部分实现、7 个已确认规范偏差、11 个缺失、4 个主站不适用、1 个需要额外权威规范。这里的“部分实现”包含“服务能工作但底层仍是裸位域”的情况，因此不能把 36 项全部当成独立功能缺陷；真正应先处理的是 7 项偏差及其公共依赖。

## Existing Implementation Survey

### 1. 物理层和传输边界

| 原语族 | 规范原语 | MoonECAT 现状 | 状态 | 结论 |
|---|---|---|---|---|
| PhS 发送/接收 | Ph-user-data transmit/receive | hal.Nic、NativeNic 和 ZeroCopyNic 提供原始以太网收发 | 完整 | 已形成主站所需的物理传输边界。 |
| PHY 特性/复位 | link characteristics、PH-RESET、线路编码、极性、SOF/EOF | 由操作系统网卡、驱动或 ESC 实现 | 不适用 | 不应在 MoonECAT 协议包中复制。可在 HAL 增加链路状态能力，但不是 EtherCAT 帧原语缺失。 |
| 以太网封装 | EtherType 0x88A4、Ethernet II header | protocol/frame.mbt | 完整 | 编码和解码均存在。 |
| UDP 封装 | EtherCAT over UDP | 无 | 缺失 | ETG.1000.4 定义了该封装；常规实时主站可先列为可选传输。 |

### 2. 数据链路服务和 DLPDU

| 原语族 | 规范原语 | MoonECAT 现状 | 状态 | 结论 |
|---|---|---|---|---|
| EtherCAT Frame Header | Length、Reserved、Type | codec 只保留 Length/Type 的运行结果 | 部分 | 缺少公开头实体和 Reserved 校验；解码未严格验证最后一个 PDU 的 M 位与声明长度一致。 |
| Datagram Header | CMD、IDX、ADP/ADO、LEN、Reserved、C、M、IRQ | PduHeader 保存 command/index/address/raw len_flags/irq | 部分 | LEN、Reserved、Circulating、More 仍是未约束的裸位域；编码会重建 LEN/M，但解码不暴露也不验证保留位/C。 |
| Datagram 命令闭集 | NOP、APRD、APWR、APRW、FPRD、FPWR、FPRW、BRD、BWR、BRW、LRD、LWR、LRW、ARMW、FRMW | EcCommand 0x00 至 0x0E 全部存在 | 完整 | 与 ETG、SOEM、IgH、CherryECAT 一致。通用 transact_pdu 允许所有命令。 |
| Datagram Index | IDX 8 bit、请求/响应关联、循环分配 | DatagramIndexSource、DatagramSession、FrameBuilder、按 index 查找响应 | 完整 | Index 属于 DLPDU 层，不属于 CoE/Mailbox。周期操作可以持续递增，但它不应改变 Mailbox Cnt 规则。 |
| 物理/逻辑地址 | Auto-increment、Configured、Broadcast、Logical | AddressType 和地址构造函数均存在 | 偏差 | auto_increment_address(position) 直接发送 position；规范处理和 EtherCrab 均使用 16 位二补数负位置，即 position 1 应发 0xFFFF。 |
| Read 服务 | APRD、FPRD、BRD、LRD | read_register_ap/fp、count_slaves、pdo_read 和通用事务 | 完整 | 线上命令完整；广播/逻辑路径由通用或 PDO API 覆盖。 |
| Write 服务 | APWR、FPWR、BWR、LWR | write_register_ap/fp、broadcast_state、pdo_write 和通用事务 | 完整 | 线上命令完整。 |
| Read/Write 服务 | APRW、FPRW、BRW、LRW、ARMW、FRMW | LRW/PDO 与 FRMW/DC 有高层路径，其余可由通用事务发出 | 部分 | 线编码完整；缺少按每种组合命令表达 WKC 期望和语义的结构化服务结果。 |
| Working Counter | WKC 16 bit 及按命令的递增语义 | Pdu.wkc、PDO 期望 WKC、若干事务检查 WKC | 部分 | 字段本身完整；缺少统一的 expected-WKC 规则和命令级诊断实体。 |
| 多 PDU 链 | M/Next、声明长度、每 PDU WKC | FrameBuilder 和 codec 支持多 PDU | 部分 | 应补严格的长度/M 链一致性校验和保留位校验。 |
| Network Variable | Publisher header、PubID、CntNV、CYC、NV Index/HASH/LEN/Q/DATA | 无 | 缺失 | ETG.1000.3/4 定义，但主流 EtherCAT 主站很少使用；优先级低于核心控制和 Mailbox。 |
| DL Mailbox 服务 | Mailbox write、Mailbox read update、Mailbox read | mailbox_send、mailbox_poll、mailbox_recv 及 AP 版本 | 部分 | 主服务存在；声明 Length 截断、通用 ERR 分派和规范化 repeat 恢复尚缺。 |
| DL local read/write/event | DLS-user 与 ESC 内部交互 | 主站通过寄存器访问观察结果 | 不适用 | 这是从站内部接口，不是主站 API 缺口。 |

### 3. ESC 属性和寄存器原语

| 原语族 | 规范原语 | MoonECAT 现状 | 状态 | 结论 |
|---|---|---|---|---|
| Register Address | ESC 寄存器地址和宽度 | discovery.mbt 中散列 UInt 常量 | 部分 | 缺少 RegisterAddress/width/access 元数据；FMMU 数量、SM 数量、RAM 大小、Port Descriptor 等基础地址也未完整收录。 |
| DL Information | Type、Revision、Build、FMMU/SM/RAM 数量、Port Descriptor、SupportFlags | Type/Revision/Build、0x0008 支持位有部分读取 | 部分 | 缺少端口类型和能力位的结构化解码。EtherCrab 的 RegisterAddress、PortType、SupportFlags 可作为接口参考。 |
| Station Address | Configured Station Address、Configured Station Alias、alias enable | 读写和 enable_alias_addressing 已有 | 完整 | 基本服务完整。 |
| DL Control/Port Control | forwarding/loop/temporary/alias 及每端口控制 | 只有原始地址和少量位操作 | 部分 | 缺少 typed DlControl、DlPortControl 和 roundtrip codec。 |
| DL Status | PDI operational、link/loop/signal、port communication | 扫描/拓扑逻辑读取原始值 | 部分 | 缺少 typed DlStatus；EtherCrab 有完整字段模型。 |
| DLS-user special registers | user control/status/special | 无专用实体 | 缺失 | 可先保留 raw-register 逃生口，后补结构化寄存器。 |
| Event Request/Mask | AL event request/mask、DLS-user event request/mask | reg_irq_mask 及初始化写入 | 部分 | 缺少事件位闭集、请求解码和 mask 类型。 |
| Error statistics | RX、Forwarded/Previous、Malformed/EPU、PDI/Local Problem、Lost Link | DlErrorCounters 读取大部分 0x0300 至 0x0313 | 部分 | 核心读取已覆盖；命名受新旧规范差异影响，缺 reset 操作和可选统计实体。 |
| Watchdog | Divider、PDI time、Process Data time/status、SM/PDI counters | WatchdogConfigSnapshot、配置和读取 | 部分 | 缺 0x0443 PDI watchdog counter 及结构化 status 位。 |
| SII controller | ownership、Busy/NACK/Error/R64、NOP/READ/WRITE/RELOAD | FP/AP READ、WRITE、ownership、busy/error 重试已实现 | 部分 | RELOAD 命令 0x0300 和公开 SiiCommand/SiiControlStatus 原语缺失。 |
| MII management | MII control/status、PHY address、PHY data | 无 | 缺失 | 对诊断主站有价值，但优先级低；PHY 本体仍属硬件边界。 |
| FMMU channel | logical/physical start、length、bit ranges、read enable、write enable、activate | FmmuConfig 只有 encode；direction 合并成单一枚举 | 部分 | 规范允许读/写使能位独立组合；应提供 from_bytes 和独立 access flags。 |
| SyncManager channel | start、length、Control、Status、Activate/Enable、PDI control、repeat ack、buffer state | SmConfig 的 control/status/activate 是裸 Byte，只提供 encode；MailboxRepeatState 单独处理 bit 1 | 部分 | 缺少 Control、Status、Enable/PDI 字段的结构化实体和 decode。 |
| Distributed Clocks | receive-time latch、system time/offset/delay/diff、filter、SYNC0/1 start/cycle/activate、FRMW sync | dc.mbt 已有发现、测量、配置和同步流程 | 部分 | 服务层覆盖较广；寄存器位域、能力、latch 和 activation flags 仍是裸值，延时模型也较简化。 |
| DL user memory | mailbox/buffer access type | 由 generic register/PDO 和 SM 配置访问 | 部分 | 不需要另造内存协议，但 SyncManager 类型应表达 mailbox 与 buffer 锁定语义。 |
| PSM/DHSM/SYSM/RMSM/SIISM/MIISM/DCSM | ESC 内部协议机 | 不实现 | 不适用 | 只审计主站可观察和驱动这些状态机所需的寄存器/服务。 |

### 4. 应用层通用原语、SII、过程数据和 ESM

| 原语族 | 规范原语 | MoonECAT 现状 | 状态 | 结论 |
|---|---|---|---|---|
| FAL 标量编码 | Boolean、BIT2..BIT8、TimeOfDay/TimeDifference、signed/unsigned 8..64、Float32/64、Octet/Visible/Unicode String | 通用 Bytes 和零散 LE 整数 helper | 部分 | 传输任意对象不受阻，但没有统一 FalDataType/codec；尤其 CoE OD data type ID 仍是裸 UInt。 |
| Process Data ASE | process output、process input、update input | ProcessImage、PdoContext、LRD/LWR/LRW 和 runtime cycle | 完整 | 主站周期数据服务已形成完整高层路径。 |
| SII ASE | read、write、reload | EEPROM read/write 和完整镜像读取 | 部分 | reload 缺失；typed command/status 也缺失。 |
| SII 固定区 | PDI controls/config、alias、identity、mailbox offsets/sizes、mailbox protocol、EEPROM size/version | SiiPreamble/SiiData/SiiStandardMetadata | 完整 | 固定区解析覆盖面较好。 |
| SII categories | Strings(10)、DataTypes(20)、General(30)、FMMU(40)、SyncM(41)、FMMU_EX(42)、SyncUnit(43)、TxPDO(50)、RxPDO(51)、DC(60)、Timeouts(70)、Dictionary(80)、Hardware(90)、VendorInfo(100)、Images(110) | 标准类别均识别；关键类别 typed，其他类别保留 raw | 完整 | 对通用主站而言，未知/厂商类别保留 raw 是正确的前向兼容策略，不应误报为线原语缺失。 |
| Isochronous Sync ASE | sync class/attributes、周期和启动时间 | DC 和 runtime cycle 有相关行为 | 部分 | 缺一个统一的同步能力/模式/约束实体；不能仅以寄存器写入替代服务模型。 |
| AL Control/Status wire | requested/current state、ack/error、application-specific | EsmState、EsmStatusSnapshot 和寄存器读写 | 部分 | 缺 typed AlControl/AlStatus roundtrip；EsmState 不表示 None/Unknown。 |
| AL Status Code | 16-bit code 闭集/扩展 | al_status_code_description(UInt) | 部分 | 有描述表但不是可 roundtrip 的类型，未知值与版本扩展边界不清晰。 |
| ESM/AR service | AL Control、AL State Changed、Start/Stop mailbox/input/output/bootstrap | esm_engine 的状态转换、配置、回滚和严格观察 | 部分 | 主站主路径完整；规范中的本地管理服务没有作为独立可组合原语暴露。 |
| 从站 FAL/ESM 协议机 | AP-context、FSPM、ARPM、DMPM | 不实现 | 不适用 | 主站只需正确驱动 AL Control/Status 和服务通道。 |

### 5. Mailbox 公共层

| 原语族 | 规范原语 | MoonECAT 现状 | 状态 | 结论 |
|---|---|---|---|---|
| Mailbox Type | ERR=0、EoE=2、CoE=3、FoE=4、SoE=5、VoE=15；AoE=1 来自通行实现/独立协议 | MailboxType 全部存在 | 完整 | 主流实现使用的判别值闭集完整。需注明本地 ETG.1000.4 v1.0.2 表 29 把 0x01 写成 reserved，而 SOEM/CherryECAT 将其定义为 AoE；注释中 EoE/FoE “out of scope” 已过时。 |
| Mailbox Header | Length U16、Address U16、Channel U6、Priority U2、Type U4、Cnt U3、Reserved U1 | MailboxHeader 有字段和 codec | 偏差 | Channel 被错误地按 2 bit 编解码；规范为低 6 bit，Priority 才是高 2 bit。Reserved 位未校验。 |
| Mailbox Frame boundary | 6-byte header + ServiceData[Length] | 各协议直接接收完整 SM 输入窗口 | 缺失 | 没有统一 MailboxFrame；必须先验证 6+Length 不越界，再仅把声明范围交给子协议。当前 EoE/SoE 会把 SM padding 当 payload。 |
| Mailbox ERR | Type=0x0001、Detail=0x0001..0x0008 | 只有 MailboxType::Err，无错误 payload codec | 缺失 | 必须在进入 CoE/EoE/FoE/SoE 解码前统一识别。CherryECAT 的 0x0009 ServiceInWork 是较新扩展，应作为 Unknown/Extension 保留。 |
| Mailbox Cnt | 1..7 wrap、0 reserved/unsupported；主/从方向各自独立序列 | MailboxCounter 生成 1..7；Rmsm 强制响应 Cnt 等于本次请求 Cnt | 偏差 | ETG.1000.4 明确规定主站和从站的 Cnt 独立。响应只应按从站接收序列检测丢失/重复，不能与请求 Cnt 配对。 |
| Mailbox Read Repeat | SM Repeat Request、Repeat Ack、backup buffer/re-read | MailboxRepeatState 和 mailbox_recv_rmsm 实现一次恢复 | 部分 | 低层 toggle/ack 基本存在；应从错误命名的 Rmsm 中拆出主站 MailboxReadRecovery，并验证完整 SM 状态转换。 |
| RMSM 名称/归属 | 每个从站读邮箱 SM 内部的 Resilient Mailbox State Machine | mailbox/rmsm.mbt 用该名表示主站事务追踪器 | 偏差 | 这是概念归属错误。周期失败后调用 reset 只是复位本地主站对象，不是复位从站 RMSM，也不是复位 EtherCAT ESM。 |
| Mailbox transport | send/poll/recv/exchange，FP/AP | protocol/mailbox_transport.mbt | 部分 | 核心访问存在；公共 frame/ERR/Cnt/repeat 语义修正后才能成为可靠的统一传输层。 |

给定故障字节可按公共层唯一解码：

- 04 00：Length = 4。
- 00 00：Address = 0。
- 00：Channel = 0，Priority = 0。
- 40：Type = ERR，Cnt = 4。
- 01 00：Error Type = Mailbox Command。
- 02 00：Detail = MBXERR_UNSUPPORTEDPROTOCOL。
- 20 11 00 c0 00 00：位于 6 + Length = 10 之后，是 SM 输入窗口 padding/旧数据，不属于该错误帧。

因此 04000000004001000200201100c00000 不是 SDO Abort，也不能先按 CoE 最小长度报 “SDO response frame too short”。

### 6. CoE 原语

| 原语族 | 规范原语 | MoonECAT 现状 | 状态 | 结论 |
|---|---|---|---|---|
| CoE Header | Number U9、Reserved U3、Service U4 | 在各函数内拼装/拆解，无公开实体 | 部分 | 应提供 CoeHeader roundtrip 和 reserved/number 语义。 |
| CoE Service | Emergency=1、SDO Req=2、SDO Res=3、TxPDO=4、RxPDO=5、TxPDO RR=6、RxPDO RR=7、SDO Info=8 | CoeService 合并两个 RR，并把 TxPDO/RxPDO 错映射为 5/6 | 偏差 | 这是确定的线上编码错误；0x04 当前还会被拒绝。 |
| SDO initiate download | expedited、normal、size indicated、complete access | build_sdo_download、segmented init、complete access | 完整 | 服务流程已有，但 command header 仍是按位手写。 |
| SDO download segments | toggle、last、unused count、data | build_sdo_download_segment_request 和 transaction | 完整 | 已有分段状态流程。 |
| SDO initiate upload | expedited/normal response、size indicated、complete access | build/decode 和 transaction | 完整 | 已有主路径。 |
| SDO upload segments | toggle、last、unused count、data | build_sdo_upload_segment_request 和 reassembly | 完整 | 已有分段状态流程。 |
| SDO command header | Client/Server command specifier、CA、expedited/size/toggle/last/n | SdoCommand 只列高层五项，实际位域分散在 coe_engine | 部分 | 请求/响应的相同 3-bit 值含义不同，不能用一个扁平枚举覆盖；应拆 Initiate/Segment request/response 头。 |
| SDO Abort | abort command、index/subindex、32-bit abort code | decode_sdo_response 和 abort description | 完整 | 已能产生 SdoAbort；建议用 Unknown(UInt) 的结构类型替代字符串表。 |
| SDO Info Header | Opcode 1..7、Incomplete、FragmentsLeft | SdoInfoResponse.opcode 是 Byte | 部分 | 缺 SdoInfoOpcode 闭集和 header codec。 |
| SDO Info services | Get OD List req/res、Get OD req/res、Get OE req/res、Error | 前三组请求/响应和多片重组已实现 | 部分 | Opcode 7 SDO Info Error 的 32-bit abort code 未解码；应先于具体 payload 分派。 |
| Emergency | error code、error register、5-byte data | EmergencyMessage 和 full-frame decoder | 部分 | 线 payload 基本完整；error-register bits、标准 error code 和 ESM 诊断数据没有 typed vocabulary。 |
| PDO over Mailbox | TxPDO、RxPDO | 无 frame codec/服务 | 缺失 | 当前 PDO 只走逻辑过程映像；CoE mailbox PDO 是另一组规范原语。 |
| PDO Remote Request | TxPDO RR、RxPDO RR | 合并成一个错误服务枚举，无 codec | 缺失 | 必须拆成 0x06/0x07 两个原语。 |
| Command object | CoE Command header/data | 无 | 缺失 | 规范定义但主流使用较少，优先级低于 SDO/ERR 修复。 |
| Object Dictionary vocabulary | ObjectCode、DataType ID、access/value-info、0x1000/0x1001/0x1008/0x1009/0x100A/0x1018、PDO/SM assignment objects | SDO Info 描述中多为 UInt/Byte；映射逻辑使用部分常用 index | 部分 | 应补数据类型、对象代码和访问位的闭集；常用对象内容可作为独立语义层，不应塞入 wire codec。 |

### 7. EoE、FoE、SoE、AoE 和 VoE

| 原语族 | 规范原语 | MoonECAT 现状 | 状态 | 结论 |
|---|---|---|---|---|
| EoE Frame Type | Fragment=0、Timestamp=1、Set IP req/res=2/3、Set filter req/res=4/5、Get IP req/res=6/7、Get filter req/res=8/9 | EoeFrameType 全部存在 | 完整 | 闭集值与 CherryECAT 一致。 |
| EoE Header | frame type、port、last fragment、time appended/requested、fragment no、offset/buffer size、frame no/result | 部分字段私有拼装；time flags 未表达 | 部分 | 应形成 EoeHeader，按 frame type 解释第二字。 |
| EoE Fragment service | 分片、首片总帧长、后续片 offset、frame number、重组、timestamp stripping | mailbox codec + runtime/eoe_switch | 偏差 | 分片/重组存在，但发送端把首片 offset 写成 0；SOEM 按规范在首片写总帧长的 32-byte 单位，后续片才写当前位置。接收端也未校验 offset/port/连续性，且未剥离 appended timestamp。 |
| EoE IP parameters | MAC、IP、subnet、gateway、DNS IP、DNS name 及 include flags | Set 只支持 IP/subnet/gateway；Get 返回 raw Bytes | 部分 | 缺 MAC/DNS 字段和 typed response。Flags 是 1 byte；当前不是“把值写成长度”，但内容不完整。 |
| EoE address filter | Set/Get filter req/res | 仅有 frame-type 枚举和通用响应分支 | 缺失 | 缺请求/响应结构和 codec。 |
| EoE results | 0x0000、0x0001、0x0002、0x0201、0x0401；0x0202 为参考项目扩展 | EoeResult 含核心值及 NoDhcpSupport | 完整 | 需把扩展来源记录清楚，并保留 Unknown。 |
| FoE opcodes | Read、Write、Data、Ack、Error、Busy | FoeOpCode 全部存在，读写事务均有 | 完整 | 主服务较完整。 |
| FoE Read/Write/Data/Ack/Error | password/packet number/error code/text | codecs 和 upload/download transaction | 完整 | Error 扩展表可继续与 CherryECAT 对齐，但不影响核心线结构。 |
| FoE Busy | Done U16、Entire U16、BusyText | FoeResponse::FoeBusy 不带字段 | 偏差 | 当前丢弃规范定义的进度和文本；短 Ack/Error 还会默认为 0，应改为截断错误。 |
| SoE opcodes | ReadReq/Res、WriteReq/Res、Notification、Emergency | SoeOpCode 1..6 全部存在 | 完整 | 闭集值已有；本地 ETG.1000.6 未提供完整 SoE 章节时，应以单独 SoE 规范和 IgH/SOEM 交叉验证。 |
| SoE Header | opcode、incomplete、error、drive no、element flags、IDN/fragments-left | 私有位拼装和部分响应字段 | 部分 | 缺公开 header 和 fragments-left；错误位和 incomplete 含义未形成类型。 |
| SoE transfer | segmented read/write、notification、emergency、error codes | 只支持单帧 Read/Write；Notification/Emergency 合并 | 部分 | IgH 显示完整实现需要 read reassembly、write fragmentation、独立 Emergency 和 typed error。 |
| AoE | Mailbox type + ADS/AoE header/commands/errors | 只有 MailboxType::AoE | 需额外规范 | ETG.1000 本地资料未定义 ADS/AoE 完整编码；需要 Beckhoff ADS/AoE 规范后另审，不能凭猜测补齐。 |
| VoE | vendor-specific opaque service data | 只有 MailboxType::VoE | 缺失 | 至少应提供保留 header/length/counter 的 opaque VendorMailboxFrame，让厂商层自行解释 payload。 |

### 8. 参考项目对照

| 参考项目 | 观察到的原语实现 | 对 MoonECAT 的直接证据 |
|---|---|---|
| SOEM | ec_type.h 收录 0x00..0x0E datagram、Mailbox Type、CoE Service 1..8、SDO Info 1..7、FoE 1..6、SoE 1..6、EEPROM NOP/READ/WRITE/RELOAD；ec_coe/eoe/foe/dc 实现主站事务 | 证明闭集值、EEPROM Reload 和 EoE 完整 IP 参数并非纯理论原语。 |
| IgH EtherCAT Master | datagram.c/h、mailbox.c、fsm_soe.c、fsm_foe.c 采用严格邮箱长度/错误处理和完整分段状态机 | 证明 generic Mailbox ERR 应在协议分派前处理，以及 SoE 分段/FoE Busy 是可落地的主站责任。 |
| CherryECAT | ec_datagram.h/ec_def.h 收录 mailbox error、CoE service、EoE type/result、FoE opcode/error 等闭集 | 直接暴露 MoonECAT CoE 0x04..0x07 映射错误；0x0009、0x0202 等只能标为新版本扩展。 |
| EtherCrab | command/mod.rs 使用 0u16.wrapping_sub(position)；register、dl_status、al_control、al_status_code、sync_manager_channel 提供 typed wire entities | 直接证明 auto-increment ADP 应取二补数；同时给出适合 Rust/MoonBit 这类强类型语言的寄存器原语边界。 |

### 9. 已确认的协议问题

以下不是“以后可以更完整”的泛化建议，而是当前编码/语义偏差，或会直接造成错误分派的公共原语缺失：

1. protocol/address.mbt 的 auto_increment_address 对 position 没有取 16 位二补数。
2. MailboxHeader 把 Channel 当成 2 bit；规范是 6 bit。
3. CoeService 的 TxPDO/RxPDO/两个 Remote Request 映射错误且不完整。
4. Rmsm::validate_response 把主站请求 Cnt 与从站响应 Cnt 强制相等；规范明确两条序列独立。
5. 所有协议解码器缺少统一 Mailbox ERR 前置分派，导致合法的 10-byte ERR 被误判成 CoE/SDO 太短或协议类型错误。
6. EoE/SoE 等解码路径按物理 SM 窗口长度取 payload，而不是按 Mailbox Length 截断，padding 会泄漏到上层。
7. FoE Busy 丢弃 Done、Entire、BusyText。
8. EoE 发送首片没有在 Frame Offset 字段携带总帧长，接收重组也忽略该约束。

## Abstraction And Interface Proposal

建议先建立原语所有权，再补协议功能。不要继续在各事务函数里重复手写位移和长度判断。

### A. protocol：EtherCAT/DL wire primitives

- EthercatFrameHeader：length、frame_type，并在 decoder 校验 reserved。
- DatagramFlags：length、circulating、more；reserved 只允许 0。
- DatagramHeader/Pdu：保留 command、index、address、irq、wkc；encode/decode roundtrip。
- AutoIncrementPosition：唯一负责 position 到 16-bit ADP 二补数转换。
- RegisterAddress：地址、宽度、访问属性；上层可以继续接受 raw UInt 作为厂商扩展逃生口。
- typed register values：DlInformation、DlControl、DlPortControl、DlStatus、EventBits、WatchdogStatus、SiiControlStatus、MiiControlStatus、FmmuChannel、SyncManagerChannel、DcActivation。
- WkcExpectation/WkcVerdict：与帧 codec 分离，由服务层按命令、站数和 FMMU 映射计算。

### B. mailbox：统一 envelope 和协议分派

- MailboxHeader：修正 Channel=U6，验证 reserved/counter/declared length。
- MailboxFrame：header + service_data，decode 后彻底丢弃 6+Length 之外的 SM padding。
- MailboxErrorType、MailboxErrorDetail、MailboxError：支持 Unknown(UInt)，先于子协议分派。
- MailboxRxSequence：只追踪从站发出的 Cnt 序列和重复/丢失。
- MailboxTxCounter：只生成主站写出的 Cnt 序列。
- MailboxReadRecovery：只实现 Repeat Request/Ack 和读邮箱备份重放。不要再称主站对象为 RMSM。
- MailboxPayload：CoE/EoE/FoE/SoE/AoE/VoE/Err 的统一 dispatch；未知/暂不支持协议保留 raw payload。

### C. 应用协议 wire codecs

- CoE：CoeHeader、八种 CoeService、分离的 SDO initiate/segment request/response header、SdoInfoOpcode/Header/Error、PDO/RR frame。
- EoE：EoeHeader、EoeIpParameters、EoeAddressFilter、Timestamp；runtime 只负责 session、fragmentation 和 reassembly。
- FoE：FoeHeader 与带 Done/Entire/Text 的 Busy；transaction 只负责 packet/retry state。
- SoE：SoeHeader、SoeErrorCode、分段 reader/writer、独立 Notification/Emergency。
- VoE：opaque frame。
- AoE：取得独立权威规范后设计，不以 CherryECAT 常量代替规范。

### D. 语义层

- FalDataType/CoeDataType、ObjectCode、AccessFlags 和常用对象模型不应混入通用 mailbox codec。
- ESI/SII 解析结果负责产生 SmConfig、FmmuConfig、PdoMapping、MailboxConfig 和 DcConfig。
- ESM、SDO、FoE、SoE、EoE 的事务状态机只消费已经验证过的 wire entity，不再自行读取原始数组偏移。

## Risks And Open Questions

1. 本地 ETG.1000 文档版本是 2013 v1.0.2，而 CherryECAT/SOEM 含后续扩展。实现应使用 Unknown(raw) 保留前向兼容，不能把所有参考常量标成 v1.0.2 normative。
2. AoE/ADS 和完整 SoE 需要各自权威规范。当前只能确认参考实现行为，不能声称 ETG.1000 已覆盖其全部语义。
3. 修改 auto-increment ADP 会打破当前依赖错误正值 position 的 mock 测试；必须同时修 VirtualBus/fixtures，并用线字节断言锁住 0、0xFFFF、0xFFFE。
4. 修正 Mailbox Cnt 后，现有大量集成测试把 response counter 复制为 request counter，会掩盖从站独立序列。测试模型需要两个独立计数源。
5. 引入严格 Mailbox Length 后，一些现有测试可能把物理 SM padding 当协议 payload。应把“raw SM window”和“decoded MailboxFrame”分成两个 API。
6. 寄存器规范在 ESC 版本间有可选字段和命名差异。RegisterAddress 必须允许 capability gating 和 raw access，不能设计成不允许扩展的巨大枚举。
7. “全部原语”不等于一次性公开所有类型。先让 wire codec 有闭集和 roundtrip，再选择稳定的 public surface，避免 .mbti 无控制膨胀。

## Implementation Targets

按依赖关系建议分批实施：

### P0：修复当前 SDO 周期故障相关的公共根因

1. 新增 MailboxFrame/MailboxError，统一按 Length 截断，并在 CoE/EoE/FoE/SoE 前分派 ERR。
2. 修正 Mailbox Channel 宽度，补 reserved/length/truncation/padding 测试。
3. 修正 CoE Service 0x04..0x07，拆 TxPDO/RxPDO Remote Request。
4. 拆分 Tx counter、Rx sequence 和 read-repeat recovery；移除 request Cnt == response Cnt 假设，并澄清/弃用 Rmsm 名称。
5. 修正 auto-increment ADP 二补数，并更新 mock 总线和线字节测试。

### P1：补齐核心 DL/AL 原语

1. EthercatFrameHeader、DatagramFlags 和严格多 PDU 解码。
2. RegisterAddress 与 DlInformation/DlControl/DlStatus/Event/Watchdog typed values。
3. AlControl/AlStatus/AlStatusCode。
4. SiiCommand/SiiControlStatus 和 EEPROM Reload。
5. FmmuChannel/SyncManagerChannel 双向 codec，独立 read/write enable、repeat 和 buffer state。
6. SdoInfoOpcode/Error、CoeDataType/ObjectCode/AccessFlags。

### P2：补齐已有应用协议

1. FoE Busy 完整字段和严格短帧拒绝。
2. EoE 完整 IP 参数、timestamp、address filter，以及重组 offset/port/连续性校验。
3. SoE segmented read/write、fragments-left、Emergency 和 error vocabulary。
4. CoE mailbox PDO 和两个 remote request。

### P3：可选或依赖额外规范

1. EtherCAT over UDP。
2. Network Variable/PNV。
3. MII management typed services。
4. CoE Command object。
5. VoE opaque wrapper。
6. AoE/ADS：先引入权威规范，再审计和实现。

## Implementation Follow-up (2026-08-01)

P0 已实现并按原始线格式测试：

1. 新增 `MailboxFrame`、`MailboxErrorType`、`MailboxErrorDetail` 和 `MailboxError`。所有应用协议解码入口先按 Mailbox `Length` 建立边界，并优先分派 `ERR`。
2. 样例 `04000000004001000200201100c00000` 被解码为 `Mailbox Command / Unsupported Protocol`；`c000...` 不再作为 CoE 数据，而被视为 SM 物理窗口 padding。
3. Mailbox Channel 改为 U6，Priority 保持 U2；解码拒绝 Counter/Type 字节的保留位。
4. CoE 0x04..0x07 修正为 TxPDO、RxPDO、TxPDO Remote Request、RxPDO Remote Request，`decode_sdo_response` 严格要求 SDO Response service。
5. 主站发送 Cnt 与从站发送 Cnt 改为独立序列；同一非零从站 Cnt 只用于重复帧识别，不再要求响应 Cnt 回显请求 Cnt。
6. 新增首选名称 `MailboxSession`；`Rmsm` 仅为兼容名称。`reset()`/`reset_for_retry()` 的注释和 CLI 说明明确限定为本地主站对象，不会复位从站 RMSM 或 EtherCAT ESM。
7. Auto-increment ADP 改为零基位置的 16 位二补数，VirtualBus 和独立 scan mock 同步修正；线字节测试覆盖 position 0/1/2/3。

验证结果：`moon test` 共 1918 项通过，0 失败；已完成实现后协议审计，未发现剩余 P0 阻断项。现有两条 MoonBit 编译警告位于未改动的 analysis/runtime 代码，不属于本任务。

## Sources

本次均使用仓库内资料，访问日期 2026-08-01：

- references/ETG1000_2_CHN_EcatPhysicalLayer_V1i0i2_C01：PhS 原语、PHY/MDS/MAU 边界。
- references/ETG1000_3_CHN_EcatDLLServices_V1i0i2_C01：第 5 章 Read/Write/Read-Write、PNV、Mailbox 服务；第 6 章 local interactions。
- references/ETG1000_4_CHN_EcatDLLServices_V1i0i2_C01：第 5 章 frame/datagram/network variable/mailbox；第 6 章 ESC attributes；第 7 章 user memory；第 8 章及附录 A 的从站状态机。
- references/ETG1000_5_CHN_EcatALServices_V1i0i2_C01：第 5 章数据类型 ASE；第 6 章 Process Data、SII、Isochronous Sync、CoE、EoE、FoE、MBX 和 AR 服务。
- references/ETG1000_6_CHN_EcatALProtocols_V1i0i2_C01：第 5 章 AL/CoE/EoE/FoE wire encoding；第 6 章从站协议机。
- references/ETG2010_S_R_V1i0i2_EtherCATSIISpecification：SII 固定区、标准 categories 和扩展保留规则。
- references/ETG2000_S_R_V1i0i18_ESI-Specification：ESI 配置模型及其 SII/SM/FMMU/PDO/DC/Mailbox 投影。
- Reference_Project/SOEM/include/soem/ec_type.h、src/ec_main.c、src/ec_coe.c、src/ec_eoe.c、src/ec_foe.c、src/ec_dc.c。
- Reference_Project/ethercat/master/datagram.c、datagram.h、mailbox.c、fsm_soe.c、fsm_foe.c。
- Reference_Project/CherryECAT/include/ec_datagram.h、include/ec_def.h、src/ec_mailbox.c。
- Reference_Project/ethercrab/src/command/mod.rs、register.rs、dl_status.rs、al_control.rs、al_status_code.rs、sync_manager_channel.rs、mailbox/coe/headers.rs。
