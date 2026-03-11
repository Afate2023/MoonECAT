# MoonECAT SII Full Read Design

本文档定义 MoonECAT 后续读取从站 SII 全信息的落地设计。目标不是再做一套 ESI 解析器，而是把实时链路上的 EEPROM 读取、现有 mailbox SII parser、以及后续 CLI/库层输出收敛成一条稳定路径。

## 1. 设计目标

- 真实从站扫描时，identity 以 SII EEPROM 为准，不再依赖 ESC 普通寄存器的偶然映射。
- 读取结果同时支持三种用途：
  1. 运行时扫描与 validate 的 identity 基线
  2. mailbox/FMMU/SM/PDO 映射推导
  3. CLI/调试输出的完整从站元信息
- 读取链路兼容 Windows Npcap 与 Linux Raw Socket，协议语义保持一致。

## 2. 参考实现结论

- siitool：把 EEPROM 视为一段原始字节流，先解析 preamble/stdconfig，再按 category header 遍历 strings/general/fmmu/sync manager/pdo/dc。
- EtherCAT.net.ui_sii：在线读取时先切换 EEPROM ownership，再根据 32/64-bit 读取宽度按块顺序读出原始字节流，随后统一进入 SII category 模型。
- 两个参考实现都说明：
  - identity 固定头字段位于 EEPROM header，不应从普通寄存器硬编码读取。
  - category 层应保留 raw bytes，再做分层解析，而不是直接丢弃未识别 section。

## 3. 分层方案

### 3.1 协议层

新增或补齐以下能力，放在 protocol 包：

- EEPROM ownership 切换：`eeprom_to_master` / `eeprom_to_pdi`
- EEPROM 读取宽度探测：32-bit 或 64-bit
- 原始字节流读取：`read_sii_bytes(station, start_byte, byte_count?)`
- 读取停止条件：
  - 优先用 EEPROM size 字段
  - 次选 category end marker `0x7FFF`
  - 最后才是连续 `0xFF` 尾部裁剪

### 3.2 mailbox 解析层

在现有 parser 基础上扩展，而不是重写：

- 保留现有：`parse_sii_header`、`parse_sii_categories`、`parse_sii_general`、`parse_sii_sm`、`parse_sii_pdo`
- 增补：
  - `SiiPreamble`
  - `SiiStringsSection`
  - `SiiDcSection`
  - `SiiFullInfo`
- `SiiFullInfo` 建议结构：

```text
raw_bytes
preamble
header
categories
strings
general
sm_entries
fmmu_dirs
tx_pdos
rx_pdos
dc_info
```

### 3.3 运行时层

- `scan` 只要求 `SiiData` 中的 identity 固定头字段即可。
- `validate` 继续对比 `vendor_id/product_code/revision/serial`，不引入平台差异。
- mailbox/PDO 配置使用 `SiiFullInfo` 中的 SM/FMMU/PDO section，而不是再次重复读 EEPROM。

### 3.4 CLI / 诊断层

建议增加独立命令：

```powershell
moon run cmd/main read-sii -- --backend native-windows-npcap --if <interface> --station 0 --json
```

输出分三层：

- `header`: vendor/product/revision/serial/mailbox offsets
- `general`: flags、CoE/FoE/EoE/SoE、physical ports、identification ado
- `categories`: strings/sm/fmmu/pdo/dc 的结构化结果

## 4. 实施顺序

1. 固定 `scan` 使用 SII header identity
2. 补 protocol 层 ownership 切换与读宽度探测
3. 增加 `read_sii_bytes`
4. 扩展 parser 到 `SiiFullInfo`
5. 增加 `read-sii` CLI 与 JSON 输出
6. 用真实从站与 fixture 双路径回归验证

## 5. 验证策略

- fixture：继续用合成 EEPROM 做 parser 单元测试
- 受控 NIC：模拟在线 EEPROM 读回，锁定 scan/identity 回归
- 真机：至少覆盖 `scan -> read-sii --json -> run`
- 参考比对：
  - 与 siitool 对比 header/category 解析结果
  - 与 EtherCAT.net.ui_sii 对比 General/SM/PDO 基本字段

## 6. 当前已落实

- `scan` 已改为优先从 SII EEPROM header 读取 identity
- Windows Npcap 已修复本机发包回捕问题，真实从站已可被发现
- 当前仍缺：EEPROM ownership 切换、32/64-bit 读宽度探测、完整 category 在线读取命令