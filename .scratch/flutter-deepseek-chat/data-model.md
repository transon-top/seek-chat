# 数据模型：会话、消息与分支（drift）

票：`06-data-model`。行为来源：`https://github.com/deepseek-ai/chat-demo` 的 IndexedDB 实现（`db.ts`、`types.ts`、`branches.ts`、`store.ts`、`history/*`）。请求与流式语义见 [`api.md`](api.md)；导入导出细节见票 17。

## 0. 决策摘要

| # | 决策 | 结论 |
| --- | --- | --- |
| 1 | 内容块存储 | `messages.blocks` 单个 JSON 列，不建 `reply_blocks` 表 |
| 2 | 消息表形态 | 单表 `messages`，`role` 判别，角色专属列可空 |
| 3 | 附件 | `attachments` 元数据 + `message_attachments` 关联；`server_id` 存在附件行上 |
| 4 | 流式落盘 | 只在状态迁移时写入；后台补一次；启动时残留 `pending`/`streaming` 置 `stopped` |
| 5 | 原件存放 | 应用支持目录下的文件，数据库存相对路径 |
| 6 | 草稿 | v1 不建表，只在内存 |
| 7 | 主键与时间 | 文本 UUID v4；epoch 毫秒 `INTEGER` |
| 8 | 迁移 | `schemaVersion` 从 1 起，`stepByStep`，禁止 destructive fallback |
| 9 | 路径查询 | 递归 CTE 取可见路径；兄弟版本按 `parent_id` 查询 |
| 10 | `updated_at` | 提交、重新生成、编辑、续写时更新；重命名与自动标题不更新 |
| 11 | 列与 JSON 边界 | 可筛选字段留列；`blocks`、`stop_details`、`usage`、`error` 用 JSON |
| 12 | 删除时序 | 先数据库事务，提交后删文件；启动清理孤儿 |
| 13 | 导出覆盖 | 字段齐全即可，ZIP 映射由票 17 决定 |

数据库文件：`open_chat.sqlite`，打开后执行 `PRAGMA foreign_keys = ON`。

## 1. DDL 草案（schemaVersion 1）

```sql
CREATE TABLE sessions (
  id              TEXT    NOT NULL PRIMARY KEY,
  title           TEXT    NOT NULL DEFAULT '',
  created_at      INTEGER NOT NULL,          -- epoch 毫秒（UTC）
  updated_at      INTEGER NOT NULL,
  root_message_id TEXT                       -- 选中分支的第一条；空会话为 NULL
                                             -- 根版本切换或编辑第一条提问时更新
);

CREATE INDEX sessions_updated_at ON sessions (updated_at DESC);

CREATE TABLE messages (
  id                TEXT    NOT NULL PRIMARY KEY,
  session_id        TEXT    NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
  parent_id         TEXT,                    -- 同会话消息 id；根版本为 NULL
  selected_child_id TEXT,                    -- 当前选中的下一条；无后继为 NULL
  role              TEXT    NOT NULL CHECK (role IN ('user', 'assistant')),
  created_at        INTEGER NOT NULL,
  text              TEXT,                    -- user 专用
  model             TEXT,                    -- assistant 专用，可空
  thinking          INTEGER,                 -- assistant 专用布尔快照
  search            INTEGER,                 -- assistant 专用布尔快照
  latest_reminder   TEXT,                    -- assistant 专用，本轮系统信息快照；格式见 api.md §3.3
  prefix            INTEGER,                 -- assistant 专用，是否可作续写前缀
  status            TEXT    CHECK (status IN ('pending', 'streaming', 'done', 'stopped', 'error')),
  stop_reason       TEXT,
  blocks            TEXT,                    -- assistant 专用，JSON 数组
  stop_details      TEXT,                    -- JSON
  usage             TEXT,                    -- JSON
  error             TEXT,                    -- JSON
  CHECK (
    (role = 'user' AND text IS NOT NULL) OR
    (role = 'assistant' AND status IS NOT NULL)
  )
);

CREATE INDEX messages_session ON messages (session_id, created_at);
CREATE INDEX messages_parent  ON messages (session_id, parent_id, created_at);

CREATE TABLE attachments (
  id         TEXT    NOT NULL PRIMARY KEY,
  name       TEXT    NOT NULL,
  size       INTEGER NOT NULL,
  is_image   INTEGER NOT NULL DEFAULT 0,
  mime_type  TEXT    NOT NULL DEFAULT '',
  local_path TEXT,                           -- 相对应用支持目录；原件缺失为 NULL
  server_id  TEXT                            -- Files API file_id，按附件 id 全局共享
);

CREATE TABLE message_attachments (
  message_id    TEXT    NOT NULL REFERENCES messages (id) ON DELETE CASCADE,
  attachment_id TEXT    NOT NULL REFERENCES attachments (id),
  position      INTEGER NOT NULL,
  PRIMARY KEY (message_id, attachment_id)
);

CREATE INDEX message_attachments_attachment ON message_attachments (attachment_id);
```

约束说明：

- `parent_id`、`selected_child_id`、`root_message_id` 不加外键。分支指针由仓储层在同一事务内维护；v1 不删除单条消息，不存在悬空引用。加自引用外键会让建表、级联删除和 drift 生成复杂化，收益为零。
- 一个附件原件可被多条消息引用。chat-demo 的 `saveServerIds` 会把 `serverId` 写回所有引用同一附件 id 的消息，`reuploadInvalidatedFiles` 也会清掉所有匹配引用；因此 `server_id` 是附件行上的共享状态，不放在关联上。
- `attachments` 不随会话级联删除；会话删除后按引用计数清理。
- 消息顺序：同一会话内 `ORDER BY created_at, id`；版本兄弟同序。

## 2. JSON 列结构

字段名与协议保持一致；chat-demo 的本地扩展字段用 camelCase。

### 2.1 `blocks`

```jsonc
// thinking
{ "type": "thinking", "thinking": "…", "signature": "…",
  "startedAt": 1730000000000, "endedAt": 1730000002000, "elapsedSeconds": null }

// text
{ "type": "text", "text": "…",
  "citations": [{ "type": "web_search_result_location", "url": "…", "title": null,
                  "cited_text": "…", "encrypted_index": "" }],
  "isTemplate": true }

// server_tool_use：协议原样
{ "type": "server_tool_use", "id": "…", "name": "deepseek_web_search",
  "input": { "action": "search", "queries": ["…"] }, "kind": "search" }

// web_search_tool_result：协议原样
{ "type": "web_search_tool_result", "tool_use_id": "…", "kind": "search", "content": [] }

// web_fetch_tool_result：协议原样
{ "type": "web_fetch_tool_result", "tool_use_id": "…", "kind": "read_link",
  "content": { "type": "web_fetch_result", "url": "…", "content": { … } },
  "signature": "…" }
```

- 序列化必须保留未知字段以外的全部既有字段；`citation` 的 `encrypted_index` 恒空也保留。
- 思考块缺 `startedAt`/`endedAt` 时用 `elapsedSeconds`（导入数据）。
- 模板文本用 `isTemplate: true`，不进入请求上下文。

### 2.2 `error`

```jsonc
{ "kind": "http | stream | network | interrupted | protocol | upload",
  "message": "服务端原文或异常文本",
  "status": 429,
  "localMessage": { "key": "uploadParseFailed", "params": {} },
  "retryable": true }
```

`localMessage` 是本地化键与参数，界面渲染时再翻译。只有 `upload` 使用 `retryable`。

### 2.3 `usage`、`stop_details`

按协议原样 JSON。`usage` 保存最近一次非空值；`stop_details` 仅在拒答等场景存在。

## 3. 分支模型

- `sessions.root_message_id` 指向当前选中分支的第一条消息。空会话为 `NULL`。
- 每条消息有 `parent_id` 和 `selected_child_id`。显示与请求上下文共用同一条路径：从 root 出发沿 `selected_child_id` 走到底。
- 切换版本：父节点非空时只改父节点的 `selected_child_id`；切到根版本的兄弟时改 `sessions.root_message_id`。每个节点保留自己的选择，切回来时下游路径原样恢复。
- 根版本可以有多个 `parent_id = NULL` 的消息（编辑第一条提问），由 `root_message_id` 选择；在根下追加新版本时同步把 `root_message_id` 指向新消息。
- 重新生成：在用户消息下插入新的 assistant，更新该用户消息的 `selected_child_id`；旧回答及其子树不动。
- 编辑提问：以原用户消息的 `parent_id` 为父插入新的 user，复制其附件关联，再插入新的 pending assistant；父节点非空时更新其 `selected_child_id`，否则更新 `root_message_id`；旧子树不动。
- 续写：不新建消息，更新原 assistant 行；沿用原 `latest_reminder`、`model`、`thinking`、`search` 快照，并把会话 `updated_at` 前移。

## 4. 回复状态与落盘时机

状态机沿用 `api.md` §6。落盘点：

| 时点 | 写入 |
| --- | --- |
| 创建回复 | 插入 `status='pending'`、`blocks='[]'` 的 assistant 行；更新会话 `updated_at` |
| 附件补齐、请求发出前 | 写入 `latest_reminder` |
| 流式期间 | **不写库**；仅在内存合并，UI 每帧刷新 |
| `done` / `stopped` / `error` | 写入 `blocks`、`status`、`stop_reason`、`stop_details`、`usage`、`error`；未结束的思考块补 `endedAt` |
| 续写 | 更新同一 assistant 行；沿用原快照；会话 `updated_at` 前移 |
| 应用进入后台 | 若该会话在流式中，flush 当前内存回复一次 |
| 启动 | `UPDATE messages SET status='stopped' WHERE status IN ('pending','streaming')` |
| 打开会话 | 同一条兜底仅对本次加载结果生效；不单独写库 |
| 导出 / 导入前 | 残留的 `pending`/`streaming` 按 `stopped` 处理（票 17） |

理由：SQLite 是单写者，流式高频写入放大 I/O；后台补写覆盖被系统杀死的常见场景；启动兜底保证不会出现永远悬空的生成状态。

## 5. 关键查询清单

```sql
-- Q1 会话列表：只读元数据
SELECT id, title, created_at, updated_at
FROM sessions ORDER BY updated_at DESC;

-- Q2 打开会话：先取会话行（含 root_message_id），再取全部消息（含所有分支）
SELECT * FROM sessions WHERE id = ?;
SELECT * FROM messages WHERE session_id = ? ORDER BY created_at, id;
SELECT * FROM message_attachments WHERE message_id IN (…) ORDER BY position;
SELECT * FROM attachments WHERE id IN (…);

-- Q3 可见路径：递归 CTE，按深度排序
WITH RECURSIVE path(id, depth) AS (
  SELECT root_message_id, 0 FROM sessions
   WHERE id = ? AND root_message_id IS NOT NULL
  UNION ALL
  SELECT m.selected_child_id, p.depth + 1
    FROM messages m JOIN path p ON m.id = p.id
   WHERE m.selected_child_id IS NOT NULL
)
SELECT m.* FROM path p JOIN messages m ON m.id = p.id ORDER BY p.depth;

-- Q4 某节点的兄弟版本
SELECT * FROM messages
 WHERE session_id = ? AND parent_id IS ?
 ORDER BY created_at, id;

-- Q5 重新生成 / 编辑：同一事务
INSERT INTO messages (…) VALUES (…);
-- 父节点非空：
UPDATE messages SET selected_child_id = ? WHERE id = ?;
-- 父节点为 NULL（根版本）：
UPDATE sessions SET root_message_id = ? WHERE id = ?;
UPDATE sessions SET updated_at = ? WHERE id = ?;

-- Q6 续写：同一条 assistant 行，会话时间前移
UPDATE messages
   SET blocks = ?, usage = ?, stop_reason = ?, stop_details = ?,
       status = 'pending', error = NULL
 WHERE id = ?;
UPDATE sessions SET updated_at = ? WHERE id = ?;

-- Q7 删除会话前的附件引用
SELECT DISTINCT ma.attachment_id
  FROM message_attachments ma
  JOIN messages m ON m.id = ma.message_id
 WHERE m.session_id = ?;

-- Q8 删除会话（级联消息与关联），随后查孤儿
DELETE FROM sessions WHERE id = ?;
SELECT id FROM attachments
 WHERE id NOT IN (SELECT attachment_id FROM message_attachments);

-- Q9 导出索引的消息数
SELECT COUNT(*) FROM messages WHERE session_id = ?;
```

附件原件读写：

- 路径：`<Application Support>/attachments/<attachment.id>`，`attachments.local_path` 存 `attachments/<id>`。不要存绝对路径：iOS 容器路径会变。
- 写入顺序：先写文件，再提交数据库行。数据库失败留下孤儿文件，由启动清理删除。
- 删除顺序：事务删除会话与行，提交后删除不再被引用的文件；文件删除失败不回滚数据。
- 删除会话不删除远端 Files API 文件，与 chat-demo 一致。
- 原件缺失（`local_path IS NULL`）的附件只展示元数据，不进入请求，界面不提供补传。

## 6. 导入导出字段覆盖

模型需保留归档回转所需的全部字段：

- 会话：`title`（空串对应归档 `null`）、`created_at`、`updated_at`、`root_message_id`。
- 消息树：`parent_id`、`role`、`created_at`、当前选中链。
- 助手：`status`（归档七种状态到本地五状态的映射由票 17 定义）、`thinking`、`search`、累计 `usage`、全部块（思考签名、引用、工具调用与结果签名）。
- 附件：`name`、`size`、`is_image`、`mime_type`、引用关系、`local_path`；归档的 `token_usage`/`width`/`height` 本地不保存，导出为 `null`，与 chat-demo 行为一致。
- 附件导出规则：只把有原件的图片写入 ZIP；文档附件只导出元数据，`export_path` 为 `null`；`server_id` 不导出。删除规则见 §5。
- 思考耗时：本地存起止毫秒；导出为 `elapsed_secs`，导入时写 `elapsedSeconds`。

ZIP 结构、覆盖导入、暂存事务与失败回滚由票 17 决定。

## 7. Dart 类型草案

### 7.1 drift 表

```dart
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get rootMessageId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get parentId => text().nullable()();
  TextColumn get selectedChildId => text().nullable()();
  TextColumn get role => text().check(isIn(['user', 'assistant']))();
  IntColumn get createdAt => integer()();
  TextColumn get textContent => text().named('text').nullable()();
  TextColumn get model => text().nullable()();
  BoolColumn get thinking => boolean().nullable()();
  BoolColumn get search => boolean().nullable()();
  TextColumn get latestReminder => text().nullable()();
  BoolColumn get prefix => boolean().nullable()();
  TextColumn get status => text()
      .check(isIn(['pending', 'streaming', 'done', 'stopped', 'error']))
      .nullable()();
  TextColumn get stopReason => text().nullable()();
  TextColumn get blocks => text().nullable()();       // JSON
  TextColumn get stopDetails => text().nullable()();  // JSON
  TextColumn get usage => text().nullable()();        // JSON
  TextColumn get error => text().nullable()();        // JSON

  @override
  Set<Column> get primaryKey => {id};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get size => integer()();
  BoolColumn get isImage => boolean().withDefault(const Constant(false))();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  TextColumn get localPath => text().nullable()();
  TextColumn get serverId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class MessageAttachments extends Table {
  TextColumn get messageId =>
      text().references(Messages, #id, onDelete: KeyAction.cascade)();
  TextColumn get attachmentId => text().references(Attachments, #id)();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {messageId, attachmentId};
}
```

### 7.2 领域类型

```dart
enum ReplyStatus { pending, streaming, done, stopped, error }

final class Session {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? rootMessageId;
}

sealed class Message {
  final String id;
  final String? parentId;
  final String? selectedChildId;
  final DateTime createdAt;
}

final class UserMessage extends Message {
  final String text;
  final List<Attachment> attachments;
}

final class AssistantMessage extends Message {
  final ChatModel? model;
  final bool? thinking;
  final bool? search;
  final String? latestReminder;
  final bool prefix;
  final ReplyStatus status;
  final List<ReplyBlock> blocks;
  final StopReason? stopReason;
  final StopDetails? stopDetails;
  final MessageUsage? usage;
  final ReplyError? error;
}

sealed class ReplyBlock {}

final class ThinkingPart extends ReplyBlock {
  final String thinking;
  final String? signature;
  final int? startedAt;     // epoch 毫秒
  final int? endedAt;       // epoch 毫秒
  final int? elapsedSeconds;
}

final class TextPart extends ReplyBlock {
  final String text;
  final List<TextCitation> citations;
  final bool isTemplate;
}

// ServerToolUseBlock / WebSearchToolResultBlock / WebFetchToolResultBlock
// 按 api.md 的协议类型实现，JSON 原样读写。

final class Attachment {
  final String id;
  final String name;
  final int size;
  final bool isImage;
  final String mimeType;
  final String? localPath;  // 相对应用支持目录
  final String? serverId;   // 按附件 id 共享
}

enum ReplyErrorKind { http, stream, network, interrupted, protocol, upload }

final class ReplyError {
  final ReplyErrorKind kind;
  final String message;
  final int? status;
  final LocalMessage? localMessage;
  final bool? retryable;
}
```

数据库列用 snake_case，Dart 字段与 JSON 用 camelCase；转换在 drift 表映射与 JSON 编解码层完成。

`model`、`thinking`、`search`、`latestReminder` 在历史消息中可以缺省；请求构造时按 `api.md` 的规则回退。

## 8. 迁移

- drift `schemaVersion = 1`；`onCreate` 建上述四张表与索引。
- `MigrationStrategy` 使用 `stepByStep`，后续每版必须提供显式 `from → to`；不配置 `beforeOpen` 之外的破坏性回退，不调用 `deleteEverything`。
- 升级失败让应用进入可重试的错误态，不自动清库。
- 导出格式版本独立于数据库版本；当前归档版本为 3（票 17 维护）。

## 9. 术语

术语表见仓库根目录 [`GLOSSARY.md`](../../GLOSSARY.md)。
