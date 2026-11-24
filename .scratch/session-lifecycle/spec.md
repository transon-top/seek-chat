# Spec: Session 选择与生命周期深化

Status: open

## 目标

把「当前是哪个 Session」以及真正改变它的命令收进一个模块 `SessionLifecycle`。ChatHome 不再持有选择字段，ChatPage 不再保存第二份 session id，抽屉不再直接执行删除。删除当前会话后的回落、会话列表滞后、导入重置都由模块一处解释。行为不变。

## 现状

- ChatHome 持有 `_selectedId` / `_draft` / `_openedLatest` / `_focusRequests` / `_historyEpoch` / `_currentId` / `_pendingCreatedId`（`lib/app/app.dart:198-224`）。
- `_current(sessions)` 在 build 期间修改状态（`:231-244`）；`_currentId` 仅用于抑制列表数据变化导致的 ChatPage 重建（`:211-217`）；导入后靠 `ValueKey(_historyEpoch)` 强制重建 ChatPage（`:355`）。
- ChatPage 另有 `_sessionId`，首次发送时自己 `createSession`，失败后自己删空会话并回调 ChatHome（`lib/features/chat/chat_page.dart:99`、`:241`、`:283-296`）。
- 抽屉直接调用 repository 做置顶、重命名、单删/批删（`lib/features/sessions/session_drawer.dart:243-303`、`:385-387`）；单删与批删重复同一序列。
- 删除当前会话后，`_current` 回落到列表最近的 Session；无剩余则为 null（Draft）。
- 空会话在首条消息落库前不出现在会话列表（`lib/shared/data/chat_repository.dart:53-59`）。

## 已定决策

### 模块与状态

1. 位置 `lib/features/sessions/session_lifecycle.dart`；手写 `NotifierProvider<SessionLifecycleController, SessionLifecycleState>`。
2. 状态：sealed `CurrentSession = Draft | Open(id) | Pending(id)`，加 `generation`（导入 epoch）。`Pending` 表示 Session 行已创建、会话列表流尚未包含。
3. 不缓存 Session 列表；继续使用现有 `sessionsProvider`。模块结合列表解析 Pending → Open、删除后的回落与启动初始选择。
4. `resolveInitial()` 只在首次列表就绪时生效：有显式选择则保持，否则打开最近 Session；列表为空则保持 Draft。必须由 ChatHome 在 `initState` / `ref.listen` 中显式调用，不能在 build 中触发。
5. `startNew()` 进入 Draft，不创建行。首次发送由 `createForFirstMessage()` 建行并返回 id，模块进入 Pending；列表出现后转 Open。
6. `discardCreated(id)` 只在当前为同一 Pending 时删除该行与孤儿附件，回到 Draft。

### 命令

- `startNew()`
- `open(id)`
- `resolveInitial()`
- `Future<String> createForFirstMessage()`
- `Future<void> discardCreated(id)`
- `Future<void> delete(Set<String> ids)`：逐个 `stopSession(id)` → repository 事务 → 删除孤儿附件文件（失败只 `debugLog`）→ 更新当前选择。repository 异常向上抛，已完成的删除不回滚；每成功删除一个就更新一次选择。
- `void historyReplaced()`：`generation++`，当前回到 Draft；上传任务清空仍由导入适配器完成。

### 明确排除

`rename` 与 `setPinned` 不进入模块，继续留在抽屉 + repository：

- 它们不读也不写当前选择，不参与任何状态迁移；放进同一 notifier 只会把状态机扩成所有 Session 写命令的总线。
- 抽屉的 `title.trim()`、空与未变化判断、「全部已置顶则取消」是 UI 组合，保留在 adapter。
- 这是已知的「view 直接写 repository」偏离；若以后要消除，另起一个薄的 `SessionActions` 模块，不要塞回 lifecycle。

### 接线与分层

1. `features/sessions` 不得 import `features/chat`。`stopSession` 通过 `shared/providers.dart` 中的 typedef + 默认 no-op provider 注入，app 层在 `ProviderScope` 覆盖为读取活动 ChatController 集合并 `stop()` 的实现。测试覆盖为 fake。
2. `features/chat` 不得 import `features/sessions`。ChatPage 不直接调用 `SessionLifecycle`；ChatHome（app 层）把 `startNew`、`createForFirstMessage`、`discardCreated` 作为回调传给 ChatPage，并继续传入当前 id。ChatPage 的新对话焦点在本地处理。
3. 抽屉与搜索页属于 `features/sessions`，可以直接读取模块命令；删除由模块执行，置顶/重命名仍直接调用 repository。
4. ChatHome 只触发 `resolveInitial()`、读取当前 id 与 `generation`，并把 `generation` 作为 ChatPage 的 key。
5. 命令失败：模块不改选择状态，异常向上抛，由 adapter 用现有 toast 提示。

### 行为约束

- 严格行为不变；现有 `app_test.dart`、抽屉与搜索测试保留并保持绿色。
- 删除当前 Session 后打开剩余列表中最近的 Session；无剩余则 Draft。
- 批量删除维持现状：repository 异常中断后续删除（缺陷见票 04）。
- 删除全部维持现状：不触发导入式重置（缺陷见票 05）。
- 导入后 ChatPage 重建，旧草稿附件与上传任务不得跨数据保留。
- 列表数据变化但当前 id 不变时，ChatPage 不重建（现有列表性能测试保护）。
- `rename` 与 `setPinned` 不改变 `updated_at`；删除事务返回孤儿附件行。

## 非目标

- 不缓存完整会话列表，不改 `sessionsProvider` 的查询与排序。
- 不把多选、搜索、菜单状态搬进模块。
- 不把 `rename` / `setPinned` 搬进模块。
- 不修批量删除失败隔离（票 04）与删除全部重置（票 05）。
- 不改 Session Drawer 视觉、搜索匹配或历史归档服务。
- 不改 DB schema、ARB 文案。

## 测试

现有测试作为行为安全网。新增 `test/features/sessions/session_lifecycle_test.dart`：

- 启动：列表就绪打开最近会话；列表为空保持 Draft；已显式选择不被覆盖。
- 新对话：`startNew` 不建行；首次发送建一行并进入 Pending；列表出现后转 Open。
- 失败发送：`discardCreated` 删除行与附件，回到 Draft。
- 删除：删当前后回落最近；删非当前不动；无剩余回 Draft；`stopSession` 在删除前调用；文件删除失败不阻塞。
- 导入：`historyReplaced` 递增 generation 并回到 Draft。
- 命令失败：选择状态不变，异常抛出。

验收命令：`flutter analyze` + `flutter test`。

## 迁移

1. `issues/01-current-session-state.md`：模块、状态、启动解析、新对话/首次创建、导入重置；ChatPage 经 app 回调使用命令。
2. `issues/02-lifecycle-commands.md`：删除命令、`stopSession` port、孤儿附件清理；抽屉改为删除 adapter；置顶/重命名保持原状。
3. `issues/03-contract.md`：删除 ChatHome / ChatPage / 抽屉旧的选择字段与删除回调，收紧接口。
4. `issues/04-bulk-delete-isolation.md`：修复批量删除的 per-session 失败隔离（行为修复）。
5. `issues/05-delete-all-reset.md`：删除全部触发与导入相同的重置（行为修复）。

## 术语

`GLOSSARY.md` 已新增「Current Session（当前会话）」。
