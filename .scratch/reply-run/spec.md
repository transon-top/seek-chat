# Spec: Reply Run 深化

Status: open

## 目标

把一次 assistant Reply 的执行收进一个模块 `ReplyRun`：从已有 `userMessageId` 或 `replyId` 开始，拥有请求上下文、流、stale 重试、状态迁移、终态落盘与标题采纳。`ChatController` 保留 turn 级写入与 UI 状态，不再包含流合并与结算逻辑。行为不变：DB schema、Reply 状态机、请求协议、UI 文案都不改。

## 现状

- 五条意图（send / regenerate / edit / continue / retryUpload）各自重复 key 检查、建行、加载、流式、结算的编排（`chat_controller.dart:177`、`:259`、`:311`、`:392`、`:439`）。
- 一条 assistant 回复被逐字段重建三次：`_liveReply`（`:946`）、`_copyReply`（`:969`）、`_settleInterrupted`（`chat_repository.dart:1163`）。
- 状态规则分散在 accumulator、controller、repository、`reply_rules.dart` 与 `messages_view.dart:997`。
- 请求上下文一半在 `buildMessageRequest`（`request.dart:134`），一半在 `_prepareRequest`（`chat_controller.dart:647`）。
- UI 只读 `ChatState`，从不接触 accumulator，已经具备清晰的观察 seam。

## 已定决策

### 边界

`ReplyRun` 只拥有 assistant Reply，不拥有整个 turn。

- **controller 保留**：API Key 门禁；user message 写入（`addUserMessage` / `editUserMessage` 事务）；附件复制与落库；上传任务清理；busy；`ChatState` 镜像；`ref.keepAlive()`；stop / flush 转发；`send` 的 `submitted` 语义。
- **ReplyRun 拥有**：创建或复用 Reply 行；Visible Path 切片、Latest Reminder 快照、continuation prefix；请求构造；SSE 消费与块合并；stale `file_id` 重试（最多 2 次、1s/2s 退避、收到内容块后不再重试）；终态结算与落盘；标题采纳规则与写库；`onSnapshot`。
- **附件 port 只做请求就绪与失效修补**：请求前补齐 serverId；流中 `file_id` 失效时清理并补传。port 不复制附件、不落库、不管理上传任务。
- **标题**：`ReplyRun` 是自动标题的唯一写者，规则仍是「标题为空、未取消、`end_turn` / `max_tokens`」。用户重命名是另一条显式路径，规则互斥；spec 不引入第二个自动写者。

### 接口

文件：`lib/features/chat/reply_run.dart`。

- `ReplyRun` 构造依赖：`sessionId`、`ChatRepository`、`DeepSeekApiClient`、附件 port、`void Function(AssistantMessage) onSnapshot`、可选 clock。
- 入口：`Future<ReplyOutcome> run(ReplyIntent intent)`；`ReplyIntent` 为 sealed：
  - `SendReply(userMessageId, thinking, search, titleEnabled)`——user message 已由 controller 写入。
  - `RegenerateReply(userMessageId, titleEnabled)`——Run 创建同 user 下的新 Reply。
  - `EditReply(replyId, titleEnabled)`——编辑事务已创建 pending Reply，Run 接管。
  - `ContinueReply(replyId, titleEnabled)`——Run 调用 continuation 开始逻辑。
  - `RetryUpload(replyId, titleEnabled)`——Run 调用 continuation 开始逻辑，但无 prefix、默认重建 Latest Reminder 快照。
- 控制：`void stop()`、`Future<void> flush()`。
- 观察：同步 `onSnapshot` 回调，快照类型复用 `AssistantMessage`；流式期间每事件一次。
- 结果：`Future<ReplyOutcome>`，sealed 两变体：
  - `ReplySettled(AssistantMessage reply, LocalMessage? saveError)`
  - `ReplyRejected(LocalMessage localError)`——只表示 Reply 未创建或未发出；user message 是否提交由 controller 的结果表达。

### 行为约束

- 严格行为不变；现有 controller / accumulator / request / repository 测试全部保留并保持绿色。
- `flush` 仍写 streaming 中间态，失败只 `debugLog`，不阻塞。
- 保存终态失败仍进入 `ChatState.error`（`errorSaveReplyFailed`），由 `ReplySettled.saveError` 传给 controller。
- stale-file 重试规则不变；上传失败在请求前立即终止。
- `retryUpload` 与 continuation 的差异保留：前者无 prefix、默认重新生成快照。
- 一次会话同时只有一条 in-flight 回复；时间戳保证 parent 与版本顺序。
- 错误文案映射仍走 `shared/error_text.dart`，本模块只产出 `LocalMessage` / `ReplyError` 数据。
- `ReplyRun` 不 import `features/sessions`；标题写库通过 repository，规则与用户重命名互斥。

## 非目标

- 不改 DB schema、Reply 状态机、请求协议、ARB 文案。
- 不拥有 user message、附件落库、上传任务、凭证门禁与 Session 选择。
- 不做附件管线深化（候选 3）与凭证门禁统一（候选 7）。
- 不修 `resetInterruptedReplies` 的 thinking 隐患；见 `.scratch/reply-status-settle/issues/01-reset-interrupted-thinking.md`。
- 不改 UI 渲染、Initial Window、Session 导航。

## 测试

现有测试作为行为安全网原样保留。新增 `test/features/chat/reply_run_test.dart`，只经公共 seam：

- 发送后的 Reply：建行、流式、persist done；快照按事件到达。
- `ReplyRejected`：Reply 未创建，controller 负责 user message 结果。
- 保存终态失败：返回 `saveError`，回复仍按终态快照交给 UI。
- stop：保留已收到块，persist stopped；请求前 stop 不发送。
- flush：persist streaming 快照；失败不抛出。
- 标题采纳：空标题、正常结束才采纳并写库。
- continuation：复用同一行、保留前缀与快照。
- retryUpload：无 prefix、重新生成快照。
- stale `file_id`：调用 port，重建请求后重发；收到内容块后不重试。
- 中断结算规则：display settle 与启动 UPDATE 使用同一规则。

验收命令：`flutter analyze` + `flutter test`。

## 迁移

1. `issues/01-reply-run-send.md`：建 `ReplyRun`，send 的 Reply 部分走新 seam。
2. `issues/02-regenerate-edit.md`：迁 regenerate / edit。
3. `issues/03-continue-retry-upload.md`：迁 continue / retryUpload。
4. `issues/04-remove-old-choreography.md`：删除 controller 旧编排，收紧接口，补齐 seam 测试。

## 术语

`GLOSSARY.md` 已新增「Reply Run（回复执行）」。
