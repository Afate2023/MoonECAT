# 在线智能启动 TODO

本文档记录真实从站链路上“在线智能启动”当前已验证结论、建议命令和待收口事项。

## 1. 当前结论

- `run --esi-json` 在真实 EX_CA20 从站上已经跑通，说明“加了 ESI 就必现启动失败”并不成立。
- 2026-04-23 的实机结果更接近“从站状态残留 / 外部主站干扰 / 断电前现场状态”问题，而不是稳定复现的 ESI 启动逻辑错误。
- `--esi-json` 当前更适合作为启动准备和 PDO/InitCmd 的增强输入；真实 `run` 路径仍应以在线探测和在线细化为主，而不是盲目离线覆盖。

## 2. 本次实机验证

设备与输入：

- 后端：`native-windows-npcap`
- 接口：`\\Device\\NPF_{82A62AE6-53AD-431E-8283-4E7F3F2CE4B3}`
- 从站：`EX_CA20`
- ESI：`References/VT_EX_CA20_20250225.esi.json`

执行命令：

```powershell
moon run cmd/main run -- --backend native-windows-npcap --if '\Device\NPF_{82A62AE6-53AD-431E-8283-4E7F3F2CE4B3}' --esi-json References/VT_EX_CA20_20250225.esi.json --device-index 0 --startup-state op --shutdown-state none --cycles 20 --timeout-ms 50 --record artifacts/real-device-20260423-esi.ndjson
```

终端结果：

```text
MoonECAT Run Report
===================
Slaves found: 1
Validation: PASS
Mode: FixedCycles
CyclePeriodNs: 1000000
OutputPeriodNs: none
Cycles: 20/20 OK
Phase: Done
Telemetry: tx=20 rx=20 timeouts=0 irq_events=0 dc_delay_updates=0 wkc_errors=0
Fault: none
```

回放验证：

```powershell
moon run cmd/main replay -- --trace artifacts/real-device-20260423-esi.ndjson --cycles 20
```

```text
MoonECAT Replay Report
======================
Verdict: Pass
Remaining events: 2748
MoonECAT Run Report
===================
Slaves found: 0
Validation: PASS
Mode: FixedCycles
CyclePeriodNs: 1000000
OutputPeriodNs: none
Cycles: 20/20 OK
Phase: Done
Telemetry: tx=20 rx=20 timeouts=0 irq_events=0 dc_delay_updates=0 wkc_errors=0
Fault: none
```

说明：

- replay 已证明记录文件可用。
- 但仅凭 NDJSON 重放时，replay 侧 scan 推导可能退化成 `Slaves found: 0`。
- 因此凡是要形成“证据级”回放材料，应该把 live `scan --json` 和 `--record` 产物一并归档。

## 3. 推荐实机取证顺序

建议按下面顺序采集，以便截图和后续转验证 markdown：

```powershell
moon run cmd/main scan -- --backend native-windows-npcap --if '\Device\NPF_{82A62AE6-53AD-431E-8283-4E7F3F2CE4B3}' --json > artifacts/real-device-20260423-scan.json
moon run cmd/main validate -- --backend native-windows-npcap --if '\Device\NPF_{82A62AE6-53AD-431E-8283-4E7F3F2CE4B3}' --json
moon run cmd/main diagnosis -- --backend native-windows-npcap --if '\Device\NPF_{82A62AE6-53AD-431E-8283-4E7F3F2CE4B3}' --station 4097 --json
moon run cmd/main startup-trace -- --backend native-windows-npcap --if '\Device\NPF_{82A62AE6-53AD-431E-8283-4E7F3F2CE4B3}' --station 4097 --esi-json References/VT_EX_CA20_20250225.esi.json --device-index 0 --json
moon run cmd/main run -- --backend native-windows-npcap --if '\Device\NPF_{82A62AE6-53AD-431E-8283-4E7F3F2CE4B3}' --esi-json References/VT_EX_CA20_20250225.esi.json --device-index 0 --startup-state op --shutdown-state none --cycles 20 --timeout-ms 50 --record artifacts/real-device-20260423-esi.ndjson
moon run cmd/main replay -- --trace artifacts/real-device-20260423-esi.ndjson --scan-json artifacts/real-device-20260423-scan.json --cycles 20
```

## 4. 在线智能启动待办

- 冻结“在线优先、ESI 增强”的规则文档，明确 `run` / `state --path` / `startup-trace` 在给定 `--esi-json` 时哪些步骤仍必须以 live 结果为准。
- 给 `startup-trace` 增加更直接的人类可读结论，至少明确：准备来源、PDO 策略、是否发生 live refinement、是否应用 InitCmd 过滤。
- 为真实链路录制提供一键证据打包流程，默认同时输出 `scan.json + run.ndjson + replay summary`，避免只留 trace 导致 `slave_count` 丢失。
- 补一个“外部主站/上位机刚接触过从站”的告警项，在启动前提示可能存在状态残留、watchdog 或 mailbox 污染。
- 把 `startup-diff` / `mailbox-readback` 纳入实机问题缩小模板，用于区分“ESI 声明不一致”和“在线状态残留”。
- 增加一次断电重启后的连续两轮 `run --esi-json` 实机回归，验证问题是否已从“稳定失败”收敛为“偶发现场条件”。
- 形成截图友好的验证模板 markdown，直接贴入命令、终端输出和结论，减少人工整理成本。

## 5. 当前判断

- 现阶段不应再把“EX_CA20 + `--esi-json` 无法进入 run”当成确定性回归结论。
- 更准确的说法是：该路径曾受现场状态影响而失败，但在从站断电重启后，同版命令已可成功进入 `run` 并完成 20 个周期。
- 下一步重点应该从“继续猜测 ESI 是否坏了”转向“把在线准备、证据采集和 replay 附件收口成稳定流程”。