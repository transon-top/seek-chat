# 会话列表 P2

Type: task
Status: open
Blocked by: 03

## Question（实施切片）

按 `decision.md` §2 做两项，不改列表实现，不与消息列表统一封装：

1. 根级 `sessionsProvider`（`lib/app/app.dart:171`）改 `select` 当前 id，避免会话数据变化重建整页。
2. `ScrollEdgeFade`（`lib/shared/widgets/scroll_edge_fade.dart`）合并 `ScrollMetricsNotification`，只重建渐隐带，不整块 `setState`。

## 验收

- 测试：`select` 后会话数据变化不重建整页（widget 测试）；渐隐带隔离能测则测。
- 模拟器 1 轮复测抽屉打开与滚动；数字回填票内。
- 一次提交。
