# MoonECAT 形式化验证路线图 MVP

> 基于仓库 `Afate2023/MoonECAT` 现有代码结构，将四阶段验证计划映射到具体的文件、函数和可交付成果。
>
> 前置依赖：MoonBit ≥ 0.9（`proof_requires` / `proof_ensures` / `proof_invariant` / `.mbtp` 谓词文件 / `moon prove` 命令可用）。

---

## 仓库现状总结

| 包 | 核心文件 | 可验证热点 |
|---|---|---|
| `protocol/` | `codec.mbt` · `zero_copy_codec.mbt` · `pdu.mbt` · `frame.mbt` · `address.mbt` | 帧编解码、PDU 解析、地址计算 |
| `protocol/` | `esm.mbt` · `esm_engine.mbt` · `dc.mbt` · `discovery.mbt` | ESM 状态机、DC 时钟补偿、从站发现 |
| `protocol/` | `pdo.mbt` · `sdo_transaction.mbt` · `mailbox_transport.mbt` | PDO 循环、SDO 分段传输、邮箱收发 |
| `mailbox/` | `sii_parser.mbt` · `rmsm.mbt` · `mailbox.mbt` · `coe_engine.mbt` | SII 解析、RMSM 状态机、CoE 分段传输 |
| `runtime/` | `scan.mbt` · `drift_compensation.mbt` | 多从站遍历、漂移补偿 PI 控制 |
| `hal/` | `hal.mbt` · `error.mbt` · `frame_pool.mbt` | Nic trait、EcError 错误模型、帧池分配 |

现有测试基础扎实（`protocol_test.mbt` 131KB、`runtime_test.mbt` 224KB、`mailbox_test.mbt` 123KB），可在此基础上渐进引入形式化验证。

---

## 第一阶段：接口契约化与边界防御 (Contracts & Boundary Defense)

**目标：** 利用 `proof_requires` 和 `proof_ensures`，为最底层的纯函数建立数学承诺，彻底消除底层数组越界风险。

### 1.1 帧解析器前置条件

**目标文件：** `protocol/codec.mbt`

**目标函数：** `EcFrame::decode` (第 89–159 行)

当前代码已有手写防御检查：

```moonbit
// codec.mbt L90-93
if data.length() < ethernet_header_len + ecat_header_len {
  raise @hal.EcError::InvalidFrame(
    "frame too short: " + data.length().to_string(),
  )
}
```

**MVP 动作：** 将隐式假设升级为编译器可检查的契约：

```moonbit
pub fn EcFrame::decode(data : Bytes) -> EcFrame raise @hal.EcError {
  proof_requires(data.length() >= 16)  // ethernet_header_len(14) + ecat_header_len(2)
  // ... 现有逻辑不变
}
```

底层 helper 函数同步加固：

| 函数 | 文件 : 行 | 添加的前置条件 |
|---|---|---|
| `read_u16_le(data, offset)` | `codec.mbt:3` | `proof_requires(offset >= 0 && offset + 1 < data.length())` |
| `read_u32_le(data, offset)` | `codec.mbt:10` | `proof_requires(offset >= 0 && offset + 3 < data.length())` |
| `write_u16_le(buf, value)` | `codec.mbt:19` | 无副作用，仅写 buffer，无需前置 |
| `write_u32_le(buf, value)` | `codec.mbt:26` | 同上 |

### 1.2 零拷贝编解码边界安全

**目标文件：** `protocol/zero_copy_codec.mbt`

这些函数直接操作 `FixedArray[Byte]`，是 PDO 零拷贝热路径，最容易因越界导致内存安全问题。

#### `write_u16_le_fixed` / `write_u32_le_fixed` / `read_u16_le_fixed` (第 8–35 行)

```moonbit
fn write_u16_le_fixed(buf : FixedArray[Byte], offset : Int, value : UInt) -> Unit {
  proof_requires(offset >= 0 && offset + 1 < buf.length())
  // ...
}

fn write_u32_le_fixed(buf : FixedArray[Byte], offset : Int, value : UInt) -> Unit {
  proof_requires(offset >= 0 && offset + 3 < buf.length())
  // ...
}

fn read_u16_le_fixed(buf : FixedArray[Byte], offset : Int) -> UInt {
  proof_requires(offset >= 0 && offset + 1 < buf.length())
  // ...
}
```

#### `encode_lrw_frame_into` (第 44–94 行)

```moonbit
pub fn encode_lrw_frame_into(
  buf : FixedArray[Byte], ..., data_len : Int,
) -> Int {
  proof_requires(data_len >= 0)
  proof_requires(buf.length() >= ethernet_header_len + ecat_header_len + pdu_header_len + data_len + wkc_len)
  // 即 buf.length() >= 28 + data_len
  proof_ensures(result >= 0 && result <= buf.length())
  // ...
}
```

#### `decode_pdu_response_from` (第 154–206 行)

```moonbit
pub fn decode_pdu_response_from(
  buf : FixedArray[Byte], buf_len : Int,
  target : FixedArray[Byte], target_offset : Int, target_len : Int,
) -> (UInt, UInt) raise @hal.EcError {
  proof_requires(buf_len >= 0 && buf_len <= buf.length())
  proof_requires(target_offset >= 0 && target_offset + target_len <= target.length())
  // ...
}
```

#### `decode_pdu_response_slice` (第 213–257 行)

```moonbit
pub fn decode_pdu_response_slice(
  buf : FixedArray[Byte], buf_len : Int,
  skip : Int,
  target : FixedArray[Byte], target_offset : Int, target_len : Int,
) -> (UInt, UInt) raise @hal.EcError {
  proof_requires(buf_len >= 0 && buf_len <= buf.length())
  proof_requires(skip >= 0)
  proof_requires(target_offset >= 0 && target_offset + target_len <= target.length())
  // ...
}
```

### 1.3 序列化对称性证明 (Encode/Decode Roundtrip)

**新建文件：** `protocol/codec_proof.mbt`

**核心定理：** `∀ frame : EcFrame, EcFrame::decode(frame.encode()) == frame`

实际可先做子定理（更容易通过 SMT 求解器）：

#### 子定理 1：u16 往返

```moonbit
proof fn u16_roundtrip(v : UInt) -> Unit {
  proof_requires(v <= 0xFFFFU)
  let buf = @buffer.new(size_hint=2)
  write_u16_le(buf, v)
  let bytes = buf.to_bytes()
  let result = read_u16_le(bytes, 0)
  proof_ensures(result == v)
}
```

#### 子定理 2：u32 往返

```moonbit
proof fn u32_roundtrip(v : UInt) -> Unit {
  let buf = @buffer.new(size_hint=4)
  write_u32_le(buf, v)
  let bytes = buf.to_bytes()
  let result = read_u32_le(bytes, 0)
  proof_ensures(result == v)
}
```

#### 子定理 3：EcCommand 字节往返

基于 `pdu.mbt` 第 22–65 行覆盖全部 15 个 EtherCAT 命令类型：

```moonbit
proof fn eccommand_byte_roundtrip(cmd : EcCommand) -> Unit {
  let b = cmd.to_byte()
  let recovered = EcCommand::from_byte(b)  // 不应 raise
  proof_ensures(recovered == cmd)
}
```

#### 子定理 4：完整帧往返

```moonbit
proof fn frame_encode_decode_roundtrip(frame : EcFrame) -> Unit {
  proof_requires(frame.dst_mac.length() == 6)
  proof_requires(frame.src_mac.length() == 6)
  proof_requires(frame.pdus.length() > 0)
  let encoded = frame.encode()
  let decoded = EcFrame::decode(encoded)
  proof_ensures(decoded == frame)
}
```

### 1.4 地址计算正确性

**目标文件：** `protocol/address.mbt` (第 1–86 行，全部为纯函数)

**新建文件：** `protocol/address_proof.mbt`

```moonbit
proof fn configured_address_roundtrip(station : UInt, offset : UInt) -> Unit {
  proof_requires(station <= 0xFFFFU && offset <= 0xFFFFU)
  let addr = configured_address(station, offset)
  proof_ensures(address_station(addr) == station)
  proof_ensures(address_offset(addr) == offset)
}

proof fn broadcast_address_has_zero_station(offset : UInt) -> Unit {
  proof_requires(offset <= 0xFFFFU)
  let addr = broadcast_address(offset)
  proof_ensures(address_station(addr) == 0U)
  proof_ensures(address_offset(addr) == offset)
}

proof fn read_write_command_consistency(t : AddressType) -> Unit {
  // read_command 和 write_command 必须使用同一寻址模式的对称命令
  let r = read_command(t)
  let w = write_command(t)
  let rw = readwrite_command(t)
  proof_ensures(r != w && r != rw && w != rw)
}
}
```

### 1.5 FramePool 读写边界

**目标文件：** `hal/frame_pool.mbt` (第 174–277 行)

```moonbit
pub fn FramePool::write_byte(self : FramePool, fref : FrameRef, offset : Int, value : Byte) -> Unit {
  proof_requires(fref.slot >= 0 && fref.slot < self.capacity)
  proof_requires(offset >= 0 && offset < self.frame_size)
  // ...
}

pub fn FramePool::write_bytes(self : FramePool, fref : FrameRef, offset : Int, src : FixedArray[Byte], src_offset : Int, count : Int) -> Unit {
  proof_requires(fref.slot >= 0 && fref.slot < self.capacity)
  proof_requires(offset >= 0 && offset + count <= self.frame_size)
  proof_requires(src_offset >= 0 && src_offset + count <= src.length())
  // ...
}

pub fn FramePool::write_u16_le(self : FramePool, fref : FrameRef, offset : Int, value : Int) -> Unit {
  proof_requires(offset >= 0 && offset + 1 < self.frame_size)
  // ...
}

pub fn FramePool::write_u32_le(self : FramePool, fref : FrameRef, offset : Int, value : Int) -> Unit {
  proof_requires(offset >= 0 && offset + 3 < self.frame_size)
  // ...
}
```

### ✅ 第一阶段交付件

| 交付件 | 内容 |
|---|---|
| `protocol/codec.mbt` | 底层 `read_u16_le` / `read_u32_le` 加 `proof_requires` |
| `protocol/zero_copy_codec.mbt` | `encode_lrw_frame_into` · `encode_pdu_frame_into` · `decode_pdu_response_from` · `decode_pdu_response_slice` · `decode_pdu_wkc_only` 加契约 |
| `protocol/codec_proof.mbt` (**新**) | u16 / u32 / EcCommand / Frame 完整 roundtrip 证明 |
| `protocol/address_proof.mbt` (**新**) | 地址拼接 / 拆分幂等性证明 |
| `hal/frame_pool.mbt` | `write_byte` / `write_bytes` / `read_bytes` / `write_u16_le` / `write_u32_le` / `read_u16_le` / `read_u32_le` 加边界 `proof_requires` |
| CI 步骤 | `moon prove` 跑通全部契约 |

**预估工期：2–3 周**

---

## 第二阶段：核心业务逻辑的数学定义 (Predicates & Domain Modeling)

**目标：** 利用 `.mbtp` 谓词文件，消除核心状态机的自然语言歧义，将 ETG 1000 规范中的关键定义翻译为可机器检查的谓词。

### 2.1 ESM 状态机合法跃迁

**依据代码：** `protocol/esm.mbt` 第 41–56 行 `EsmState::can_transition`

**新建文件：** `protocol/esm.mbtp`

```
predicate valid_esm_transition(from: EsmState, to: EsmState) {
  (from == Init   && to == PreOp)  ||
  (from == Init   && to == Boot)   ||
  (from == PreOp  && to == SafeOp) ||
  (from == PreOp  && to == Init)   ||
  (from == SafeOp && to == Op)     ||
  (from == SafeOp && to == PreOp)  ||
  (from == SafeOp && to == Init)   ||
  (from == Op     && to == SafeOp) ||
  (from == Op     && to == PreOp)  ||
  (from == Op     && to == Init)   ||
  (from == Boot   && to == Init)
}
```

然后在 `esm_engine.mbt` 的关键入口处引用：

```moonbit
// esm_engine.mbt — transition_through (第 624–652 行)
pub fn[N : @hal.Nic] transition_through(nic : N, station : UInt, path : Array[EsmState], timeout : @hal.Duration) -> EsmState raise @hal.EcError {
  // 证明路径中每一步都是合法跃迁
  proof_requires(path.length() >= 1)
  // ∀ i ∈ [0, path.length()-1), valid_esm_transition(path[i], path[i+1])
  // ...
}
```

### 2.2 PreOp→SafeOp / SafeOp→Op 前提条件谓词

基于 `esm_engine.mbt` 第 157–179 行 `request_state_with_process_data` 的显式检查：

```text
// protocol/esm.mbtp 续

predicate safeop_to_op_ready(pdo_ctx: PdoContext) {
  pdo_ctx.logical_size > 0
}

predicate esm_path_well_formed(path: Array[EsmState]) {
  path.length() >= 1 &&
  forall(i, 0 <= i < path.length() - 1 =>
    valid_esm_transition(path[i], path[i+1]))
}
```

### 2.3 拓扑扫描一致性

**依据代码：** `runtime/scan.mbt` 第 59–123 行 `scan` 函数

**新建文件：** `runtime/scan.mbtp`

```
predicate scan_topology_consistent(report: ScanReport) {
  report.slave_count == report.slaves.length() &&
  all_station_addresses_unique(report.slaves) &&
  all_positions_sequential(report.slaves)
}

predicate all_station_addresses_unique(slaves: Array[SlaveReport]) {
  forall(i, j, 0 <= i < j < slaves.length() =>
    slaves[i].station_address != slaves[j].station_address)
}

predicate all_positions_sequential(slaves: Array[SlaveReport]) {
  forall(i, 0 <= i < slaves.length() =>
    slaves[i].position == i)
}
```

在 `scan` 函数尾部添加后置条件：

```moonbit
pub fn[N : @hal.Nic] scan(nic : N, timeout : @hal.Duration) -> ScanReport raise @hal.EcError {
  // ...
  proof_ensures(scan_topology_consistent(result))
}
```

### 2.4 RMSM 协议不变量

**依据代码：** `mailbox/rmsm.mbt` (第 1–195 行)

**新建文件：** `mailbox/rmsm.mbtp`

```text
// 邮箱计数器永远在 1-7 范围内循环
predicate valid_mailbox_counter(counter: Byte) {
  counter >= 0x01 && counter <= 0x07
}

// begin_transaction 后状态必须是 WaitingForResponse
predicate rmsm_post_begin(rmsm: Rmsm) {
  rmsm.state is WaitingForResponse(_) &&
  valid_mailbox_counter(rmsm.current_counter())
}

// validate_response 成功后状态必须回到 Idle
predicate rmsm_post_validate_ok(rmsm: Rmsm) {
  rmsm.state is Idle
}
}
```

### ✅ 第二阶段交付件

| 交付件 | 内容 |
|---|---|
| `protocol/esm.mbtp` (**新**) | ESM 跃迁合法性、SafeOp→Op 就绪条件、路径良构性谓词 |
| `runtime/scan.mbtp` (**新**) | 拓扑一致性、地址唯一性、位置连续性谓词 |
| `mailbox/rmsm.mbtp` (**新**) | 计数器范围、RMSM 状态转换合法性谓词 |
| `protocol/esm_engine.mbt` | `transition_through` 等关键入口加 `proof_requires` / `proof_ensures` |
| `runtime/scan.mbt` | `scan` 函数加 `proof_ensures(scan_topology_consistent(result))` |

**预估工期：2 周**

---

## 第三阶段：循环推理与复杂算法证明 (Loop Invariants & Complex Algorithms)

**目标：** 利用 `proof_invariant` 攻克协议栈中最容易出错的循环遍历操作。

### 3.1 PDO 从站映射内存安全

**目标函数：** `protocol/pdo.mbt` — `PdoContext::build` (第 73–109 行)

```moonbit
for i = 0; i < slave_mappings.length(); i = i + 1 {
  let (sm, station) = slave_mappings[i]
  let out_len = sm.output_bytes
  let in_len = sm.input_bytes
  // ...
  current_logical = current_logical + out_len.reinterpret_as_uint()
  current_logical = current_logical + in_len.reinterpret_as_uint()
  out_offset = out_offset + out_len
  in_offset = in_offset + in_len
} where {
  proof_invariant(current_logical >= logical_base)
  proof_invariant(out_offset >= 0)
  proof_invariant(in_offset >= 0)
  // 偏移量单调递增，不会溢出
  proof_invariant(current_logical - logical_base ==
    (out_offset + in_offset).reinterpret_as_uint())
}
```

### 3.2 FramePool 生命周期安全

**目标文件：** `hal/frame_pool.mbt` — `acquire` (第 67–79 行)

```moonbit
pub fn FramePool::acquire(self : FramePool) -> FrameRef raise EcError {
  // ...
  for i = 0; i < self.capacity; i = i + 1 {
    let idx = (start + i) % self.capacity
    // ...
  } where {
    // 循环不会访问越界 slot
    proof_invariant(idx >= 0 && idx < self.capacity)
    // free_count 守恒：acquire 最多减少 1 个 Free slot
    proof_invariant(count_free_after >= count_free_before - 1)
  }
}
```

FramePool 状态转换合法性：

```text
// 合法的帧状态跃迁 (参见 frame_pool.mbt 第 3 行注释)
// Free → Acquired → Filled → Sending → Sent → Free
// Free → Receiving → Received → Free
predicate valid_frame_state_transition(from: FrameState, to: FrameState) {
  (from == Free      && to == Acquired)  ||
  (from == Acquired  && to == Filled)    ||
  (from == Filled    && to == Sending)   ||
  (from == Sending   && to == Sent)      ||
  (from == Sent      && to == Free)      ||
  (from == Free      && to == Receiving) ||
  (from == Receiving && to == Received)  ||
  (from == Received  && to == Free)
}
```

### 3.3 SDO 分段传输 Toggle Bit 正确性

**目标函数：** `protocol/sdo_transaction.mbt`

#### `sdo_upload_collect_segmented` (第 487–542 行)

```moonbit
let mut toggle = false
while !current.last_segment {
  // ...
  if seg_resp.toggle != toggle {
    raise @hal.EcError::MailboxProtocol(context + ": segment toggle mismatch")
  }
  // ...
  toggle = !toggle
} where {
  // Toggle bit 在每次迭代中严格交替
  proof_invariant(toggle != prev_toggle)
  // 累积数据长度单调递增
  proof_invariant(acc.length() >= prev_acc_length)
}
```

#### `sdo_download_segmented` (第 606–670 行)

```moonbit
let mut offset = 0
let mut toggle = false
while offset < data.length() {
  let remain = data.length() - offset
  let chunk_len = if remain > 7 { 7 } else { remain }
  // ...
  offset += chunk_len
  toggle = !toggle
} where {
  // 偏移量严格递增，保证循环终止
  proof_invariant(offset >= 0 && offset <= data.length())
  proof_invariant(offset > prev_offset)
  // Toggle bit 严格交替
  proof_invariant(toggle != prev_toggle)
}
```

**终止性证明：** 每轮 `chunk_len >= 1`（因 `remain > 0` 且 `chunk_len = min(remain, 7) >= 1`），故 `offset` 严格递增，循环必然终止。

### 3.4 DC 漂移补偿有界性

**目标文件：** `runtime/drift_compensation.mbt` — `DriftCompensator::compensate` (第 91–122 行)

```moonbit
pub fn DriftCompensator::compensate(self : DriftCompensator, ...) -> Int64 {
  // ...
  self.integral_error_ns = self.integral_error_ns + error
  if self.integral_error_ns > self.max_integral_ns {
    self.integral_error_ns = self.max_integral_ns
  } else if self.integral_error_ns < -self.max_integral_ns {
    self.integral_error_ns = -self.max_integral_ns
  }
  // ...
  proof_ensures(self.integral_error_ns >= -self.max_integral_ns &&
                self.integral_error_ns <= self.max_integral_ns)
  // anti-windup 保证积分项永远有界
}
```

**目标文件：** `protocol/dc.mbt` — `dc_static_sync` (第 315–324 行) 和 `dc_configure_linear` (第 329–372 行)

```moonbit
pub fn[N : @hal.Nic] dc_static_sync(nic : N, reference_station : UInt, iterations : Int, timeout : @hal.Duration) -> Unit raise @hal.EcError {
  proof_requires(iterations >= 0)
  for _i = 0; _i < iterations; _i = _i + 1 {
    dc_compensate_cycle(nic, reference_station, timeout)
  } where {
    proof_invariant(_i >= 0 && _i <= iterations)
  }
}
```

### 3.5 SII 类别解析遍历安全

**目标函数：** `mailbox/sii_parser.mbt` — `parse_sii_categories` (第 393–416 行)

```moonbit
pub fn parse_sii_categories(data : Bytes) -> Array[SiiCategoryEntry] {
  // ...
  let mut word_offset = sii_category_start
  while word_offset * 2 + 3 < data.length() {
    let cat_type = read_sii_word(data, word_offset)
    let cat_size_words = read_sii_word(data, word_offset + 1)
    if cat_type == sii_cat_end || cat_type == sii_cat_legacy_end || cat_type == 0U {
      break
    }
    // ...
    word_offset = word_offset + 2 + cat_size_words.reinterpret_as_int()
  } where {
    // word_offset 严格递增（cat_size_words >= 0），保证终止
    proof_invariant(word_offset >= sii_category_start)
    proof_invariant(word_offset > prev_word_offset)
    // 所有读取操作不越界
    proof_invariant(word_offset * 2 + 3 < data.length())
  }
}
```

### ✅ 第三阶段交付件

| 交付件 | 涉及文件 | 证明内容 |
|---|---|---|
| PDO 映射安全 | `protocol/pdo.mbt` | 偏移量单调递增、不越界、逻辑地址连续 |
| FramePool 安全 | `hal/frame_pool.mbt` | slot 索引不越界、状态转换合法、free_count 守恒 |
| SDO 分段完整性 | `protocol/sdo_transaction.mbt` | Toggle 交替、offset 严格递增、循环终止、数据完整重组 |
| DC 补偿收敛 | `runtime/drift_compensation.mbt` · `protocol/dc.mbt` | 积分项有界 (anti-windup)、静态同步循环终止 |
| SII 解析安全 | `mailbox/sii_parser.mbt` | 类别遍历 word_offset 递增、不越界、终止 |

**预估工期：3–4 周**

---

## 第四阶段：AI 协作与持续验证工程化 (AI Collaboration & CI/CD)

**目标：** 将验证从"专家手写"转化为"AI 辅助 + 机器校验"的标准工程实践。

### 4.1 优先让 AI 攻克的函数

| 函数 | 文件 | 难度原因 |
|---|---|---|
| `dc_configure_linear` | `protocol/dc.mbt:329` | 多从站遍历 + 偏移计算 + 延迟平滑，不变量涉及三层嵌套 |
| `dc_reestimate_propagation_delays` | `protocol/dc.mbt:377` | 运行时重估 + 指数移动平均，需证明平滑因子有界 |
| `sdo_info_collect_payload` | `protocol/sdo_transaction.mbt:673` | 多段拼接 + opcode 校验 + RMSM 交互 |
| `coe_engine` 分段下载 | `mailbox/coe_engine.mbt` | 状态机嵌套循环 + Toggle + 超时 + 重试 |
| `mailbox_repeat_read_fp` | `protocol/mailbox_transport.mbt:99` | RMSM RepeatAck 循环 + SM 窗口验证 |

### 4.2 AI 辅助工作流

```
┌──────────────────────────────────────────────────────────┐
│  开发者写:  fn dc_configure_linear(...) { ... }         │
│  开发者写:  proof_ensures(所有从站 DC 偏移已写入)         │
│                       ↓                                  │
│  AI Agent:  自动推测 proof_invariant(???)                │
│             生成中间断言和循环不变量候选                    │
│                       ↓                                  │
│  moon prove: Z3 求解器校验                               │
│    ✅ → 合并入代码                                       │
│    ❌ → 反例发回 AI → 修正 → 再校验                      │
└──────────────────────────────────────────────────────────┘
```

### 4.3 CI/CD 集成

```yaml
# .github/workflows/prove.yml
name: Formal Verification

on:
  push:
    branches: [base, main]
  pull_request:

jobs:
  prove:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install MoonBit
        run: |
          curl -fsSL https://cli.moonbitlang.com/install.sh | bash

      - name: Formal Verification
        run: moon prove

      - name: Unit Tests
        run: moon test

      - name: Interface Consistency
        run: moon info
```

### 4.4 渐进式覆盖率跟踪

建议在 `docs/` 或 CI artifacts 中维护一张覆盖率表：

| 包 | 总公开函数数 | 已加 proof_requires | 已加 proof_ensures | 已证明 roundtrip | 循环不变量 |
|---|---|---|---|---|---|
| `protocol/` | ~60 | — | — | — | — |
| `mailbox/` | ~40 | — | — | — | — |
| `hal/` | ~20 | — | — | — | — |
| `runtime/` | ~30 | — | — | — | — |

每次 PR 更新此表，作为形式化验证进度的可见指标。

### ✅ 第四阶段交付件

| 交付件 | 内容 |
|---|---|
| `.github/workflows/prove.yml` (**新**) | CI 中集成 `moon prove` + `moon test` + `moon info` |
| `docs/FORMAL_VERIFICATION_COVERAGE.md` (**新**) | 覆盖率跟踪表 |
| AI 协作模板 | 标准化的"函数 + 意图 → AI 猜不变量 → Z3 校验"流程文档 |

**预估工期：持续迭代**

---

## 时间线总览

```
Week 1-3   ┃ P1: 接口契约化
           ┃ ├─ codec.mbt / zero_copy_codec.mbt proof_requires
           ┃ ├─ codec_proof.mbt roundtrip 证明
           ┃ ├─ address_proof.mbt 幂等性证明
           ┃ └─ frame_pool.mbt 边界契约
           ┃
Week 4-5   ┃ P2: 谓词定义
           ┃ ├─ esm.mbtp ESM 跃迁谓词
           ┃ ├─ scan.mbtp 拓扑一致性谓词
           ┃ └─ rmsm.mbtp 计数器/状态谓词
           ┃
Week 6-9   ┃ P3: 循环不变量
           ┃ ├─ pdo.mbt PDO 映射安全
           ┃ ├─ sdo_transaction.mbt Toggle Bit 证明
           ┃ ├─ frame_pool.mbt 状态机安全
           ┃ ├─ sii_parser.mbt 遍历安全
           ┃ └─ drift_compensation.mbt 有界性
           ┃
Week 10+   ┃ P4: AI + CI
           ┃ ├─ .github/workflows/prove.yml
           ┃ ├─ AI 辅助复杂不变量 (dc, coe, mailbox_transport)
           ┃ └─ 覆盖率持续跟踪
```

---

## 快速启动：从这一��开始

在 `protocol/codec.mbt` 的 `read_u16_le` 函数中加入：

```moonbit
fn read_u16_le(data : Bytes, offset : Int) -> UInt {
  proof_requires(offset >= 0 && offset + 1 < data.length())
  data[offset].to_int().reinterpret_as_uint() |
  (data[offset + 1].to_int().reinterpret_as_uint() << 8)
}
```

运行 `moon prove`。**这一行就能让编译器帮你证明所有调用 `read_u16_le` 的地方都不会越界。** 从这里开始，逐步扩展到整个协议栈。