# Spec: Reply Run 深化

Status: open

## 目标

把一条 Reply 从意图到结算的生命周期收进一个模块 `ReplyRun`，让状态迁移、块合并、请求上下文、标题采纳与终态落盘只有一处解释。行为不变：DB schema、Reply 状态机、UI 文案与请求协议都不改。`ChatController` 退化为意图路由、UI 状态镜像与 Riverpod 生命周期适配。

## 现状

- 五条意图（send / regenerate / edit / continue / retryUpload）各自重复 key 检查、建行、加载、流式、结算的编排（`chat_controller.dart:177`、`:259`、`:311`、`:392`、`:439`）。
- 一条 assistant 回复被逐字段重建三次：`_liveReply`（`:946`）、`_copyReply`（`:969`）、`_settleInterrupted`（`chat_repository.dart:1163`）。
- 状态规则分散在 accumulator、controller、repository、`reply_rules.dart` 与 `messages_view.dart:997`。
- 请求上下文一半在 `buildMessageRequest`（`request.dart:134`），一半在 `_prepareRequest`（`chat_controller.dart:647`）。
- UI 只读 `ChatState`，从不接触 accumulator，已经具备清晰的观察 seam。

## 已定决策

### 模块边界

1. 模块接收用户意图，拥有整个 turn：用户消息写入 + Reply 行 + 请求上下文 + 流 + 重试 + 结算 + 标题采纳。
2. 每条回复一个短命 `ReplyRun`。controller 持有当前 run，负责 `ref.keepAlive()`、busy、把 `stop()` / `flush()` 转发给 run；模块不认识 Riverpod。
3. Visible Path 切片、Latest Reminder 快照、continuation 前缀规则进模块；可见路径与快照的持久化也由模块调用 repository 完成。
4. 中断结算的纯规则（in-flight → stopped、闭合 thinking）移入模块的规则单元；启动期全局 UPDATE 仍留在 repository，但复用同一规则。
5. 附件走注入的 port：请求前补齐 serverId、stale `file_id` 修补都由 port 执行；模块只拥有「何时补齐、何时重试、满足什么条件才重试」。候选 3 的附件管线将来实现该 port。
6. API Key 门禁留在 controller；缺失 Key 不创建 run，沿用现有本地错误路径。run 接收已就绪的客户端或 Key。

### 接口

文件：`lib/features/chat/reply_run.dart`。

- `ReplyRun` 构造依赖：`sessionId`、`ChatRepository`、`DeepSeekApiClient`、附件 port、`void Function(AssistantMessage) onSnapshot`、可选 clock。
- 入口：`Future<ReplyOutcome> run(ReplyIntent intent)`；`ReplyIntent` 为 sealed，五变体：
  - `SendIntent(text, readyAttachmentIds, thinking, search)`
  - `RegenerateIntent(userMessageId)`
  - `EditIntent(messageId, text, attachmentIds)`
  - `ContinueIntent(replyId)`
  - `RetryUploadIntent(replyId)`
- 控制：`void stop()`、`Future<void> flush()`。
- 观察：同步 `onSnapshot` 回调，快照类型复用 `AssistantMessage`；流式期间每事件一次。
- 结果：`Future<ReplyOutcome>`，sealed 两变体：
  - `ReplySettled(AssistantMessage reply, LocalMessage? saveError)`
  - `ReplyRejected(LocalMessage localError)`——用户消息未落库，`send` 的 `submitted` 等价于非 Rejected。

### 行为约束

- 严格行为不变；现有 controller / accumulator / request / repository 测试全部保留并保持绿色。
- `flush` 仍写 streaming 中间态，失败只 `debugLog`，不阻塞。
- 保存终态失败仍进入 `ChatState.error`（`errorSaveReplyFailed`），由 `ReplySettled.saveError` 传给 controller。
- 标题采纳规则不变：标题为空、未取消、`end_turn` / `max_tokens`；`ReplyRun` 负责规则与写库，快照携带已采纳标题。
- stale-file 重试规则不变：最多 2 次、1s/2s 退避、只在未收到内容块前重试、上传失败立即终止。
- `retryUpload` 与 continuation 的差异保留：前者无 prefix、默认重新生成 Latest Reminder 快照。
- 一次会话同时只有一条 in-flight 回复；时间戳保证 parent 与版本顺序。
- 错误文案映射仍走 `shared/error_text.dart`，本模块只产出 `LocalMessage` / `ReplyError` 数据。

## 非目标

- 不改 DB schema、Reply 状态机、请求协议、ARB 文案。
- 不修 `resetInterruptedReplies` 的 thinking 隐患；见 `.scratch/reply-status-settle/issues/01-reset-interrupted-thinking.md`。
- 不做附件管线深化（候选 3）与凭证门禁统一（候选 7）。
- 不改 UI 渲染、Initial Window、Session 导航。

## 测试

现有测试作为行为安全网原样保留。新增 `test/features/chat/reply_run_test.dart`，只经公共 seam：

- send：建用户消息与 Reply、流式、persist done；快照按事件到达。
- Rejected：不写任何行，错误为本地 `LocalMessage`。
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

1. `issues/01-reply-run-send.md`：建 `ReplyRun` 并让 send 走新 seam。
2. `issues/02-regenerate-edit.md`：迁 regenerate / edit。
3. `issues/03-continue-retry-upload.md`：迁 continue / retryUpload。
4. `issues/04-remove-old-choreography.md`：删除 controller 旧编排，收紧接口，补齐 seam 测试。

## 术语

`GLOSSARY.md` 已新增「Reply Run（回复执行）」。
