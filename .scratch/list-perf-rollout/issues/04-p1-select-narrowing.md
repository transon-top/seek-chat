# P1 重建收窄（条件）

Type: task
Status: open
Blocked by: 02

## Question（条件实施）

按 `decision.md` §4 P1：只有当《P0 稳定 GptMarkdown 输入》与《初始窗口》落地后的复测仍不满足 §7 流式口径时才实施。

- 触发时：用 Riverpod `select` 把每条消息的订阅收窄到自身；`ChatPage` 只 select 会话级字段。
- 不为每条消息建独立 provider。

若复测已达标：不改代码，在 Answer 记录前两票的复测数字与「不触发」结论后结票。

## 验收

- 触发时：改动的 widget 测试 + 模拟器复测回填。
- 不触发时：引用《P0》与《初始窗口》复测数字说明判定依据。
