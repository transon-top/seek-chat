# 总验收与收图

Type: task
Status: open
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
