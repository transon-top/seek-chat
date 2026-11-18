# 会话、消息与分支数据模型（drift）

Type: grilling
Status: open
Blocked by: 05

## Question

把 chat-demo 的 `Session` / `UserMessage` / `AssistantMessage` / `ReplyBlock` / 分支语义落到 drift 表结构：

1. 表设计：sessions、messages、reply_blocks、attachments、drafts（后置）如何拆；thinking / text / tool 块用 JSON 列还是独立表。
2. 分支：`parentId`、`selectedChildId`、`rootMessageId` 的存储与查询；切换版本时保留每条分支的选择。
3. 回复状态：`pending / streaming / done / stopped / error` 的持久化时机；流式期间写库节流策略。
4. 续写：已有 blocks 追加、usage 更新、`latestReminder` 快照。
5. 迁移：schemaVersion、迁移策略；导入导出所需的完整字段（会话、分支、思考块、附件引用）。
6. 会话摘要查询：列表页只读元数据，打开会话才加载消息。
7. 附件：原件存放路径、与消息的关联、删除与导出规则。
8. 领域术语：产出 GLOSSARY.md 条目（Session、Message、Branch、Reply、ReplyBlock、Thinking、Citation、Attachment）。

产出：表 DDL 草案 + Dart 类型草案 + 关键查询清单。
