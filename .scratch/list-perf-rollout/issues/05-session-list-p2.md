# 会话列表 P2

Type: task
Status: resolved
Blocked by: 03

## Question（实施切片）

按 `decision.md` §2 做两项，不改列表实现，不与消息列表统一封装：

1. 根级 `sessionsProvider`（`lib/app/app.dart:171`）改 `select` 当前 id，避免会话数据变化重建整页。
2. `ScrollEdgeFade`（`lib/shared/widgets/scroll_edge_fade.dart`）合并 `ScrollMetricsNotification`，只重建渐隐带，不整块 `setState`。

## 验收

- 测试：`select` 后会话数据变化不重建整页（widget 测试）；渐隐带隔离能测则测。
- 模拟器 1 轮复测抽屉打开与滚动；数字回填票内。
- 一次提交。

## Answer

- `ChatHome` 只 `select` 会话来源的加载阶段；数据变化改由 `ref.listen` 消化，仅当 `_current` 算出的当前会话 id 变化时才 `setState`。标题、更新时间、排序等列表数据变化不再重建 `ChatPage`。
- `ScrollEdgeFade` 的 `ScrollMetricsNotification` 改为内部 `ValueNotifier` 信号，与 `ScrollController` 合并为同一个 `Listenable` 交给 `AnimatedBuilder`；只重建渐隐带，不再整块 `setState`。
- 测试：`test/app/app_test.dart` 新增「session data changes do not rebuild the page while the current session is stable」——`renameSession` 后 `ChatPage` widget 实例保持不变；删除当前会话后实例更新且 `sessionId` 为 `null`。渐隐带隔离无法从组件树外观测，显示行为仍由 `test/shared/widgets/scroll_edge_fade_test.dart` 覆盖。
- 模拟器 1 轮（`evidence/05-session-list-p2-simulator-r1.log`，`Medium_Phone_API_37.0 -gpu host`；库内已有 1053 个会话，上轮为 1001）：
  - `drawer_open_1000_sessions`：`first_row_ms` 485、build p90 18.34ms、慢帧 100%（13 帧）。
  - `drawer_scroll_1000_sessions`：build p90 8.3ms、慢帧 73.95%（上轮 69.35%）、RSS 334.8MB。
  - 同轮对照 `control_idle_new_chat` 慢帧 91.67%，抽屉数字仍由模拟器光栅化主导，构建侧无回归；真机口径留给《总验收与收图》。
- `flutter analyze` 无问题，全量 `flutter test` 379 项通过。
