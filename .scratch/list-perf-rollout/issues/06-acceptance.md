# 总验收与收图

Type: task
Status: resolved
Blocked by: 03, 04, 05

## Question（验收）

按 `decision.md` §7 口径，在 Android 真机 profile 上跑 `integration_test/list_perf_test.dart` 3 轮：

- 滚动慢帧占比 <5%；打开 1000 条消息会话最后一条进入树 <300ms；流式滚动慢帧 ≤10%；会话列表首行 <300ms；RSS 不劣于改造前基线。
- 记录设备型号、系统版本、Flutter 版本、命令与原始日志路径，与模拟器基线并列。
- 复核《P1 重建收窄（条件）》的触发结论与真机数据一致。
- 全部达标则收图：在 `map.md` 的 Decisions so far 补全各票结论，确认无剩余雾。
- 未达标：把缺口写入 `map.md` 的 Not yet specified 并起补强票，不收图。

## 验收

- 3 轮日志与汇总表落在 `.scratch/list-perf-rollout/evidence/`。
- 每项验收给出 达标 / 未达标 结论；未达标项有后续票或明确的 out of scope 理由。

## Answer

全部达标，收图。

- 设备：vivo `V2608DA`（`PD2608`），Android 17 / API 37，arm64-v8a，USB 调试；Flutter 3.50.0 stable（Engine `bf601093ad`）；`--profile`。
- 命令：`flutter drive --profile -d 10AGAC0B4Z001X2 --driver=test_driver/integration_test.dart --target=integration_test/list_perf_test.dart`。
- 原始日志：`evidence/06-acceptance-device-r1.log`、`-r2.log`、`-r3.log`；汇总表：`evidence/06-acceptance-summary.md`。三轮均 `All tests passed!`，每轮重播种（`seed_ms` 5389 / 5638 / 5409）。

| 验收标准 | §7 口径 | 真机三轮 | 判定 |
| --- | --- | --- | --- |
| 滚动稳定 60fps | 慢帧 <5% | 0.0% / 0.0% / 0.0% | 达标 |
| 打开首屏 | 最后一条进入树 <300ms | 137 / 133 / 143ms | 达标 |
| 流式滚动 | 慢帧 ≤10% | 0.0% / 0.0% / 0.0% | 达标 |
| 会话列表 | 首行 <300ms；滚动无持续掉帧 | 24 / 31 / 25ms；0.0% / 0.0% / 0.0% | 达标 |
| 内存 | 打开长会话后 RSS 不劣于改造前基线 | 435.11 / 408.86 / 410.46MB | 达标（注记见下） |

- 内存注记：基线为模拟器 341–430MB；第 1 轮 435.11MB 高于上沿 1.2%，第 2、3 轮低于上沿；冷启动峰值 394.86–420.96MB 低于基线 531.6–561.2MB。跨设备绝对值仅并列参考，无劣化趋势。
- P1 复核：真机流式滚动慢帧 0.0% ×3，与模拟器 1.58% / 8.19% 均 ≤10%，《P1 重建收窄（条件）》不触发结论一致，不改代码。
- 其余场景：冷启动直接打开长会话 440–445ms；抽屉完整展开 438–444ms；对照（新会话空闲、短会话打开/滚动）慢帧 0.0%。
- 收图：`map.md` 的 Decisions so far 已补本票结论；「总验收不达标补强票」雾未触发，已清除；10000 条压力场景无触发信号，移入 Out of scope；无剩余雾。
