# 启动兜底需要闭合 thinking 块并更新 updated_at

Type: task
Status: open

## 问题

`resetInterruptedReplies`（`lib/shared/data/chat_repository.dart:771`）把所有 `pending` / `streaming` 回复直接置为 `stopped`，但：

- 不闭合打开的 thinking 块（没有结束时间）。
- 不更新会话 `updated_at`。

后续显示期结算（`loadMessagesForDisplay` / `loadConversation(settleInterrupted: true)`，`chat_repository.dart:1163`）只在状态仍为 in-flight 时补做 thinking 闭合；此时状态已是 `stopped`，会跳过。结果是重启后残留回复可能永久保留未闭合的 thinking 块。

## 修复方向

二选一，优先保持单条 UPDATE 的启动开销：

1. 在启动 UPDATE 同时闭合 opening thinking 块并 bump `updated_at`（需要按行处理 JSON，可能改为事务内批量读取 + 更新）。
2. 让显示期结算也能识别「已 stopped 但 thinking 未闭合」的残留并补闭合；启动 UPDATE 保持现状。

## 验收

- 新增 repository 测试：`pending` 回复带未闭合 thinking 块，启动 reset 后块有结束时间，`updated_at` 被更新；`done` 回复不受影响。
- 现有 `test/shared/data/chat_repository_test.dart` 的启动兜底断言保持绿色。
- 行为修复单独提交，不与 Reply Run 重构混在一起。

## 备注

来自 2026-11-24 架构评审；`ReplyRun` 深化明确不修此项。
