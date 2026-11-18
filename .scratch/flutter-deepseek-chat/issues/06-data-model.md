# 会话、消息与分支数据模型（drift）

Type: grilling
Status: resolved
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

## Answer

数据模型锁定为 drift 四表：`sessions`、`messages`、`attachments`、`message_attachments`；内容块存 `messages.blocks` JSON，不建 `reply_blocks` 表。主键用文本 UUID v4，时间用 epoch 毫秒整数；流式期间不写库，只在状态迁移与后台切换时落盘，启动时把残留 `pending`/`streaming` 置为 `stopped`。附件原件存应用支持目录，`server_id` 存在附件行上并在所有引用间共享。v1 不建 drafts 表。

完整 DDL 草案、JSON 列结构、分支语义、落盘时机、关键查询清单、Dart 类型草案与迁移策略见 [`data-model.md`](../data-model.md)。领域术语已写入仓库根目录 [`GLOSSARY.md`](../../../GLOSSARY.md)。

关键结论：

- 可见路径用递归 CTE 沿 `selected_child_id` 取；兄弟版本按 `parent_id` 查询。
- 重新生成与编辑提问插入新版本并更新父节点选择；父节点为空（根版本）时改 `sessions.root_message_id`；旧子树保留。打开会话需同时读取 `sessions` 行。
- 续写更新同一条 assistant 行，追加块、更新 usage，并前移会话 `updated_at`；沿用原 `latest_reminder` 等快照。
- `updated_at` 只在提交、重新生成、编辑、续写时变化；重命名与自动标题不改变列表顺序。
- 删除会话先提交数据库事务，再清理无引用原件；启动时兜底清理孤儿。
- 附件导出规则：仅有原件的图片写入 ZIP，文档只导出元数据，`server_id` 不导出。
- 导出所需字段已覆盖，ZIP 映射与覆盖导入由票 17 决定。
