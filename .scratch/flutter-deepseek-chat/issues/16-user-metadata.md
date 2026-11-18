# 用户元信息：语言与所在地

Type: grilling
Status: open
Blocked by: 05

## Question

1. chat-demo 的 `latest_reminder` 角色与 `src/services/chat/latestReminder.ts`、`locationData.ts` 的行为。
2. 设置页：语言（中文 / 英文）与所在地（国家 / 城市）的选择与持久化。
3. 传递格式：`latest_reminder` 的 content 模板；每轮请求的位置；回答版本快照。
4. 与界面语言的关系：界面语言是否独立于传给模型的语言；默认值。
5. 未设置时的默认行为；修改后对后续请求的影响。
6. 隐私说明与清除入口。

产出：`user-metadata.md` 章节 + 模板样例。

## Comments

- 2026-11-18：`latest_reminder` 的插入位置（对应 user 前、快照变化才插）与回答版本快照语义已由票 05 锁定，见 [`../api.md`](../api.md) §3.3。本票只需锁定 content 的取值模板与样例。
