# MoonECAT AI 任务清单

本清单基于 [MoonECAT项目申报书.md](e:\Repos\EtherCAT\MoonECAT\MoonECAT项目申报书.md) 整理，用于把项目目标转成可执行任务和可追踪提交。范围保持不变：产品面为 `Library API + CLI(scan/validate/run)` 双入口，目标对齐 ETG.1500 `Class B`，`EoE/FoE` 继续排除在外。

## 1. 使用规则

- 任务完成后再打勾，不能按预期完成时补充阻塞说明。
- 每次提交只覆盖一个清晰目标，避免把无关改动混进同一个 commit。
- 优先提交可验证结果，例如接口、测试、最小闭环、文档更新。
- 提交顺序必须服从依赖关系，不能先做 CLI 再倒逼核心库改接口。

## 2. 里程碑任务

### M1 基础骨架与包结构

- [ ] 建立稳定的 MoonBit 包结构，明确 HAL、Protocol Core、Mailbox、Runtime、CLI 的目录边界。
- [ ] 定义 HAL 最小接口，覆盖收发、计时、调度、文件访问和统一错误码。
- [ ] 定义核心错误模型、诊断事件模型和基础配置对象。
- [ ] 建立 `Library API` 与 `CLI` 的入口占位，保证共享核心实现。
- [ ] 建立最小测试骨架和样例夹具结构。

完成标准：
- 仓库结构稳定，后续功能不需要大规模重排目录。
- 分层边界能通过接口和类型直接看出来。
- 至少存在可编译的最小测试或空实现样例。

建议提交拆分：
- `feat: scaffold moonecat package layout`
- `feat: define platform hal contracts`
- `test: add minimal project test harness`

### M2 HAL 与帧/PDU 最小闭环

- [ ] 实现 Ethernet II 与 EtherCAT 基本帧结构的编码、解码和校验。
- [ ] 实现 PDU 编码、解码、地址模型和缓冲区管理。
- [ ] 落地首个可运行后端，优先 `Mock Loopback`。
- [ ] 建立发送、接收、超时和错误返回的统一流程。
- [ ] 为热路径加入预分配或少分配约束。
- [ ] 补齐帧/PDU 和收发闭环测试。

完成标准：
- 在 Mock 或单平台环境中可重复完成一轮收发闭环。
- 帧/PDU 正常路径和基本错误路径可测试。
- HAL 接口无需回退即可支撑后续真实后端接入。

建议提交拆分：
- `feat: add ethercat frame codec`
- `feat: add pdu pipeline primitives`
- `feat: add mock loopback hal`
- `test: cover frame and pdu roundtrip`

### M3 拓扑发现、SII/ESI、配置计算

- [ ] 实现基础从站发现流程和拓扑结果对象。
- [ ] 支持 SII 读取与基础解析。
- [ ] 支持 ESI 最小可用子集解析，聚焦配置所需字段。
- [ ] 实现 Vendor ID、Product Code 和一致性校验。
- [ ] 实现 FMMU/SM 自动配置计算。
- [ ] 提供 `scan` 和 `validate` 可复用的库层接口。
- [ ] 补齐无真实网卡场景下的夹具测试。

完成标准：
- 可以输出结构化扫描结果。
- 可以对给定 ESI/SII 输入执行一致性校验。
- FMMU/SM 计算结果可被运行时直接消费。

建议提交拆分：
- `feat: add slave discovery model`
- `feat: parse sii and esi metadata`
- `feat: calculate fmmu and sync manager mapping`
- `test: add discovery and config fixture coverage`

### M4 ESM、PDO 周期通信、运行时编排

- [ ] 实现 ESM 状态流转和错误回退路径。
- [ ] 实现位置寻址、别名寻址和逻辑寻址核心流程。
- [ ] 实现 PDO 周期通信的发送、接收和映射装载。
- [ ] 实现运行时调度器，统一周期循环、超时治理和背压控制。
- [ ] 加入 DC PLL 的接口和状态推进框架。
- [ ] 输出抖动、重试、状态迁移等诊断指标。
- [ ] 补齐 Free Run 主流程和关键错误回退测试。

完成标准：
- 测试环境中可演示从初始化到周期 PDO 交换的主流程。
- ESM 正常路径和关键异常路径可回归。
- Runtime 可以统一驱动 PDO 循环和事务推进。

建议提交拆分：
- `feat: add esm transition engine`
- `feat: add pdo runtime loop`
- `feat: add runtime scheduler and telemetry`
- `test: cover free-run and recovery paths`

### M5 CoE/SDO、CLI、诊断与文档完善

- [ ] 实现 CoE/SDO Upload、Download 和 SDO Info 的事务推进机制。
- [ ] 实现 mailbox 请求队列、超时、重试和关联 ID。
- [ ] 实现 `moonecat scan` 命令。
- [ ] 实现 `moonecat validate` 命令。
- [ ] 实现 `moonecat run` 命令。
- [ ] 输出结构化诊断结果、日志和调试接口。
- [ ] 补全文档：架构、接口、测试方式、常见问题、典型示例。
- [ ] 评估并整理 Extism 宿主接入边界。

完成标准：
- SDO 事务可单独测试，并可被运行时整合推进。
- CLI 三类命令直接复用库层能力。
- 文档能覆盖安装、运行、调试和扩展入口。

建议提交拆分：
- `feat: add coe sdo transaction engine`
- `feat: add moonecat scan command`
- `feat: add moonecat validate command`
- `feat: add moonecat run command`
- `docs: document architecture and user workflows`
