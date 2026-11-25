# SeekChat 架构与测试评估

> 评估日期：2026-11-24
> 基准：`docs/research/dart-flutter-architecture-best-practices.md`；官方引文与完整来源列表见该文档，本文只记录 SeekChat 的对照结论，引用保留官方 URL。
> 范围：SeekChat 当前代码、`.scratch/reply-run/spec.md` 与 issues、`.scratch/session-lifecycle/spec.md` 与 issues

## 1. 结论摘要

1. **分层形状正确，不需要补一个正式 domain layer。** Flutter 官方明确 domain layer 是可选的，只在逻辑挤爆 ViewModel 或重复逻辑反复出现时引入（[Guide to app architecture · Optional: Domain layer](https://docs.flutter.dev/app-architecture/guide)，2026-11-24；[Architecture recommendations · Separation of concerns](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）。SeekChat 的 `features/`（UI + feature-local logic）+ `shared/`（data + infrastructure）符合官方 case study 的「data by type, UI by feature」结构（[Architecture case study · Package structure](https://docs.flutter.dev/app-architecture/case-study)，2026-11-24）。真正的问题是 `ChatController` 把 ViewModel 状态与 data-layer orchestration 混在一起，不是「缺一层」。
2. **Reply Run 应收窄到 assistant Reply。** 让一个短命对象拥有 request context、stream、retry、settlement 是合理的；把 user message / 整个 turn / 首次附件上传也塞进去，会让它跨 aggregate，并与 `GLOSSARY` 对 Reply Run 的定义（「一次驱动 Reply 从创建或续写开始、到结算为止的执行」）冲突。建议 controller 负责 intent 的行创建与附件落库，`ReplyRun` 从「已有 Reply + userMessageId」开始。
3. **SessionLifecycle 用 Notifier 是对的，但应只拥有 selection/create/delete/import。** rename/pin 不改变当前会话，也不触发任何状态迁移；放进同一 notifier 只增加浅接口。更关键：spec 要求 `ChatPage` 调用该模块的命令，却没有给出「不跨 feature import」的接线方式；按仓库「功能之间不直接 import」的规则，必须改为 app 层回调注入，或明确修规。
4. **现有代码大部分与官方一致**：drift 内存库测试、`autoDispose.family` + `keepAlive`、sealed 状态/意图、单一错误映射点、`flutter_lints`。偏离集中在「view 直接写 repository」、`ChatHome` 在 build 中修改状态、`sessionsProvider` 定义在 widget 文件里、`features` 向上 import `app/theme.dart`；都是局部改动，不影响整体架构。
5. **测试结构符合官方推荐的「unit/widget 为主、integration 覆盖关键用例」**（16,228 测试行 vs 26,235 lib 行）。缺口在端到端 integration：核心 reply 生命周期与 import/delete-all reset 没有设备级覆盖，最多补 1–2 条，不值得扩大测试金字塔底层。

## 2. SeekChat 对照评估

先给现状量化（`lib` 不含生成物与 `*.g.dart`）：

| 项 | 值 |
| --- | --- |
| lib 行数 | 26,235 |
| test 行数 | 16,228（56 个文件；test:lib ≈ 0.62） |
| integration_test 行数 | 663（2 个文件） |
| `ChatController` | 1,159 行 |
| `ChatRepository` | 1,203 行 |
| `SessionDrawer` | 1,351 行 |
| `ChatPage` | 1,021 行 |
| 测试分布 | chat 6,273；shared 3,939；app 2,469；history 1,617；sessions 869；settings 480；support 408；dev 173 |

### 2.1 符合官方指导的部分

- **两层形状 + feature-first UI。** `features/chat|sessions|history|settings` 是 UI + feature-local logic，`shared/data|api|models|prefs|widgets` 是 data + infrastructure。官方 case study 正是「data by type, UI by feature」（[Architecture case study · Package structure](https://docs.flutter.dev/app-architecture/case-study)，2026-11-24）。`shared/` 的命名把「data layer」和「shared kernel」混在一起，但结构上等价于官方的 `data/` + `ui/core/`，不需要为了命名重构。
- **没有 domain layer。** 官方说 domain layer 可选，只在逻辑挤爆 ViewModel 或重复逻辑出现时加（[Architecture recommendations · Separation of concerns](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）。SeekChat 的纯规则模块 `lib/shared/models/reply_rules.dart`（`isUsableReply`、`canContinueReply`、`replyThinkingSeconds`）与 `lib/features/chat/reply_view.dart`（从持久化块纯函数推导 UI 模型）正是「不新增层、只抽纯规则」的做法，符合官方「add use-cases only when needed」。
- **依赖方向基本单向。** `app → features → shared` 没有反向 import；`shared` 不 import `features`；feature 之间没有 import（本次 grep 为空）。这比官方「layers communicate with adjacent layers」更严格，但是健康的。
- **drift 内存库测试。** 仓库在 `startup_test`、`app_test`、`chat_controller_test`、`session_drawer_test` 等处统一用 `NativeDatabase.memory()`；与 drift 官方测试指南一致（[Testing · Setup](https://drift.simonbinder.eu/testing/)，2026-11-24）。没有为了「unit test」把 repository mock 掉，这保留了 SQL/事务/stream 的真实行为，是加分项。
- **`autoDispose.family` + 流式期间 `keepAlive`。** `chatControllerProvider` 是 `NotifierProvider.autoDispose.family<ChatController, ChatState, String>`，流式期间 `ref.keepAlive()`、结束后释放。官方明确建议 family 开 autoDispose 以避免 per-parameter 泄漏，并允许用 `ref.keepAlive` 决定何时停止自动销毁（[Family](https://riverpod.dev/docs/concepts2/family)，2026-11-24；[Automatic disposal · Fine-tuned disposal with ref.keepAlive](https://riverpod.dev/docs/concepts2/auto_dispose)，2026-11-24）。官方 keepAlive 示例偏「缓存成功请求」，SeekChat 用于「in-flight 请求保活」，属于同一机制的合理扩展；官方未专门讨论这一用法。
- **sealed / final / immutable 的使用。** `AssistantMessage`、`UserMessage`、`Attachment` 等都是 `final class`；`ChatState` 字段全 `final` 且有 `copyWith`；spec 里的 `ReplyIntent`、`ReplyOutcome`、`CurrentSession` 都计划用 sealed。官方支持 sealed + exhaustive switch（[Class modifiers · sealed](https://dart.dev/language/class-modifiers)，2026-11-24；[Branches · Exhaustiveness checking](https://dart.dev/language/branches)，2026-11-24），Effective Dart 也要求用 class modifier 表达意图（[Effective Dart: Design](https://dart.dev/effective-dart/design)，2026-11-24）。
- **单一错误映射点。** `lib/shared/error_text.dart` 把 `ApiErrorCondition` 映射为 ARB 文案，服务端原文只在 debug 且 `other` 时附加。官方要求 View 不含业务逻辑、错误展示在 UI 层完成（[Guide to app architecture · Views](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）；把纯映射函数放在 `shared/` 是可接受的折中，且避免每个页面重复 switch。
- **DI 通过 ProviderScope override。** `main()` 注入 database / repository / attachmentStore / preferences，测试同样 override。官方 Strongly recommend 使用 dependency injection（[Architecture recommendations · App structure](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24），Riverpod override 是等价实现（[Testing your providers · Setting up a test](https://riverpod.dev/docs/how_to/testing)，2026-11-24）。
- **手写 provider 而非 riverpod_generator。** 官方说 codegen 完全可选，只有已经在用 codegen 时才值得（[About code generation · Should I use code generation?](https://riverpod.dev/docs/concepts/about_code_generation)，2026-11-24）。仓库已经为 drift 跑 build_runner，但为了 Riverpod 迁移 generator 的收益不足以抵消改动面；保持手写是官方允许的。

### 2.2 偏离官方指导的部分

- **`ChatController` 混合了 ViewModel 与 data-layer orchestration。** 1,159 行里同时有：`ChatState` 镜像、五条 intent 的编排（`send` / `regenerate` / `editMessage` / `continueReply` / `retryUpload`）、请求构造（`_prepareRequest`）、SSE 消费（`_consume`）、附件上传/补传（`_ensureAttachments`、`_reuploadInvalidatedFiles`）、终态落盘（`_finish`）、标题采纳（`_adoptTitle`）。官方把「请求重试、错误处理、持久化」归 data layer（[Guide to app architecture · Repositories](https://docs.flutter.dev/app-architecture/guide)，2026-11-24），把 UI state / UI logic 归 ViewModel（[Guide to app architecture · View models](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）。这不是「行数太多」的问题，而是职责跨界。Reply Run 的提取方向正确。
- **View 直接写 repository。** `SessionDrawer` 直接 `ref.read(chatRepositoryProvider).setSessionsPinned(...)`、`.renameSession(...)`、`.deleteSession(...)`，并在 widget 内做 `title.trim()` 和「全部已置顶则取消」的组合。官方 case study 明确：

  > "Private methods prevent the view, which has access to the view model, from calling methods on the repository directly."

  （[Communicating between layers · Dependency injection](https://docs.flutter.dev/app-architecture/case-study/dependency-injection)，2026-11-24）

  这是本次评估中最明确的 layering 偏离。SessionLifecycle 的「抽屉改为 adapter」正是修这一点。
- **`ChatHome` 在 build 中修改状态。** `_current(sessions)` 在 `build()` 里写 `_openedLatest`、`_selectedId`、`_pendingCreatedId`；`build()` 还调用 `ref.read(sessionsProvider).requireValue`。官方要求 View 只做展示与转发（[Guide to app architecture · Views](https://docs.flutter.dev/app-architecture/guide)，2026-11-24），Riverpod 要求不要在 provider 初始化时做 side effect、不要在 widget 中初始化 provider（[DO/DON'T](https://riverpod.dev/docs/root/do_dont)，2026-11-24）。当前实现靠「只在首次列表就绪时写一次」保持行为正确，但这是脆弱模式；SessionLifecycle 的 `resolveInitial()` 应改为显式动作，不能在 build 中触发。
- **`features` 向上 import `app/`。** `session_drawer.dart`、`session_skeleton.dart`、`session_search_page.dart` import `../../app/theme.dart`；`messages_view.dart`、`markdown_view.dart` import `../../app/markdown_theme.dart`。这违反仓库自己写的 `main → app → features → shared` 依赖方向，也与官方「layers communicate with adjacent layers」不符（[Common architecture concepts · Layered architecture](https://docs.flutter.dev/app-architecture/concepts)，2026-11-24）。主题 token 是 shared UI infrastructure，应下沉到 `shared/theme/` 或 `shared/widgets/`。这是独立于两份 spec 的架构债。
- **`sessionsProvider` 定义在 widget 文件里。** `lib/features/sessions/session_drawer.dart:25` 定义 `StreamProvider.autoDispose<List<SessionSummary>>`，`app.dart` 再 import 这个 widget 文件来使用数据源。Riverpod 要求 provider 是 top-level final、声明在 class/function 之外（[DO/DON'T](https://riverpod.dev/docs/root/do_dont)，2026-11-24；[Providers · What is a provider?](https://riverpod.dev/docs/concepts2/providers)，2026-11-24），它满足了这一点；但官方把 data-layer 对象与 UI 分开（[Architecture case study · Package structure](https://docs.flutter.dev/app-architecture/case-study)，2026-11-24），「widget 文件承载全局数据源」不利于发现与测试。放在 `session_lifecycle.dart` 或独立的 `sessions_providers.dart` 更合适。官方没有硬性规定 provider 的文件位置，所以这是可读性/一致性改进，不是违规。
- **`ChatRepository` 没有抽象接口。** 官方 recommendations 把「Use abstract repository classes」标为 **Strongly recommend**，理由是可为 dev/staging 提供不同实现（[Architecture recommendations · App structure](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）。SeekChat 只有一个实现，测试用真实内存库而非 mock，因此当前收益接近零；这是一个**可接受的偏离**，等出现第二个环境/实现时再抽接口，不应为了对齐文档而加一层空抽象。
- **列表模型暴露可变 `List`。** `AssistantMessage.blocks` 是 `List<ReplyBlock>`，`ChatState.messages` 也是 `List<Message>`；官方 Strongly recommend immutable data models（[Architecture recommendations · Handling data](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24），Effective Dart 也要求优先 `final`（[Effective Dart: Design](https://dart.dev/effective-dart/design)，2026-11-24）。但流式路径每个事件都复制列表，`List.unmodifiable` 会增加热路径分配；当前「字段 final + 生产端复制」是**可接受的性能折中**，不建议为了形式上的 immutability 改热路径。

### 2.3 其它可接受但值得记录的点

- **`activeChatControllersProvider` 是可变全局 Set。** 它承担「活动 ChatController 注册表」，供后台 flush 与删除前 stop 使用。官方不鼓励全局可访问对象、推荐 DI（[Architecture recommendations · App structure](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24），但这里是一个受控的 lifecycle registry，改成显式 registry 对象不会减少多少耦合。可接受；如果 SessionLifecycle 的 `stopSession` port 继续扩大，再考虑把 registry 抽成 `shared` 的接口。
- **`reply_rules.dart` 放在 `shared/models` 而不是 `features/chat`。** 原因是 `shared/api/request.dart` 也用它；如果放回 feature，shared 就必须 import features，反而破坏依赖方向。这是「shared 作为 shared kernel」的合理用法，虽然其中包含 chat 领域规则。可接受。
- **`error_text.dart` 依赖 `l10n/generated`。** 它不是纯 data layer，但它是纯函数映射，不持有状态，也不反向依赖 features。可接受。
- **`sessionsProvider` 是 `StreamProvider.autoDispose`，而 `app.dart` 用 `ref.listen` 保活。** Riverpod 官方提醒 autoDispose provider 在测试里用 `container.listen` 保活，避免 `read` 中途丢状态（[Testing your providers · Setting up a test](https://riverpod.dev/docs/how_to/testing)，2026-11-24）。当前 app 层的 `ref.listen` 会保活；测试已有覆盖。可接受，但 SessionLifecycle 若改为在 notifier 中读列表，需确认保活路径。

## 3. 两份 spec 的语义与边界评估

### 3.1 Reply Run：语义所有权与更窄边界

**spec 的主张：** `ReplyRun` 接收五条 intent，拥有「用户消息写入 + Reply 行 + 请求上下文 + 流 + 重试 + 结算 + 标题采纳」，`ChatController` 退化为 intent 路由、busy、API Key 门禁、keepAlive、stop/flush 转发与 `ChatState` 镜像（`.scratch/reply-run/spec.md`）。

**语义所有权：偏宽。** `GLOSSARY.md` 的定义是：

> 「Reply Run（回复执行）：一次驱动 Reply 从创建或续写开始、到结算为止的执行。新建、重新生成与编辑产生新的 Reply，也产生新的 Run；续写与附件重试不新建 Reply，而是同一条 Reply 的新 Run。」

定义的主语是 **Reply**，不是 turn。spec 把 user message 的写入也纳入 Run，于是 `SendIntent` 的 Run 同时拥有 user message、Reply、附件上传就绪、请求上下文、标题（Session 元数据）四类对象。这不是「一个 run 的自然边界」，而是「一次 turn 的编排」。如果坚持这个边界，模块名应改为 `TurnRun`，并明确 upload task 清理、附件落库等 turn 级副作用由谁负责；当前 spec 没有回答 `uploadTasksProvider.remove(...)` 归谁（现有 controller 在 `send` 成功后移除上传任务，见 `chat_controller.dart:233-235`）。

**god-module 风险：中等。** 五条 intent + 请求构造 + SSE 消费 + stale-file 重试 + 标题采纳 + 附件 port + `onSnapshot` + clock，最终很可能是一个 600–900 行的对象：仅现有 `_stream`（109 行）、`_prepareRequest`（54 行）、`_consume`（63 行）、`_finish`（37 行）就约 260 行，再加附件补齐、标题采纳与五条 intent 的建行逻辑。它仍然只服务「一次 run」，不是无限膨胀的 service locator，所以不是典型 god object；但它把 feature 的全部行为集中到一个类，测试和评审的认知负担没有比 controller 小多少——只是从「controller 兼做 data 工作」变成「run 兼做 turn 工作」。

**接口宽度 vs 深度：宽接口做得不错，但依赖面偏宽。** `run(ReplyIntent)` 是单一入口 + sealed 五变体，符合「窄接口、深实现」；`ReplyOutcome` 用 sealed 两变体也正确。问题在构造依赖：`sessionId`、`ChatRepository`、`DeepSeekApiClient`、附件 port、`onSnapshot`、clock。把 repository 直接给 run，等于让 run 同时做 domain 编排与持久化；官方 use-case 的定义是「take data from repositories and make it suitable for the UI layer」（[Guide to app architecture · Optional: Domain layer](https://docs.flutter.dev/app-architecture/guide)，2026-11-24），并不要求 use-case 拥有写库。更窄的做法是 run 仍调用 repository，但只调用与 Reply 行/块/状态相关的写方法；user message、附件、session title 的写入留在 controller 或独立 repository 方法。

**可测试性：好，但测试面偏大。** 构造注入 + 公共 seam + `onSnapshot` 让测试不需要 Riverpod；spec 要求「只经公共 seam」也是正确的。官方推荐 ViewModel 测试用 fake repository（[Testing each layer · ViewModel unit tests](https://docs.flutter.dev/app-architecture/case-study/testing)，2026-11-24），Riverpod 推荐 mock notifier 依赖的 repository（[Testing your providers · Mocking Notifiers](https://riverpod.dev/docs/how_to/testing)，2026-11-24）。宽边界意味着 seam 测试要覆盖「建 user message + 建 Reply + 附件 port + 流 + 结算 + 标题」；窄边界只需覆盖「流 + 重试 + 结算 + 标题」，测试更聚焦。

**Riverpod fit：好。** run 不认识 Riverpod，controller 持有当前 run 并负责 `keepAlive`、busy、stop/flush 转发。Riverpod 官方把 provider 生命周期交给 notifier、把逻辑放在 `build`/方法中（[Providers · Creating a provider](https://riverpod.dev/docs/concepts2/providers)，2026-11-24）；短命普通对象是官方未专门讨论、但不冲突的模式。Riverpod 3 的 Mutations 是为 side effect 提供 loading/error 状态的新机制，但仍标注 experimental（[What's new in Riverpod 3.0 · Mutations (experimental)](https://riverpod.dev/docs/whats_new)，2026-11-24），不建议现在采用。

**分层：可接受。** `features/chat/reply_run.dart` 是 feature-local domain service，依赖 `shared/data` + `shared/api`，没有引入新层。它不违反 `main → app → features → shared`。但宽边界让它同时触碰 Session（标题）与 user message（turn），跨了 aggregate；窄边界只碰 Reply，语义更干净。

**结论：采用更窄的 Reply Run。** 具体边界建议：

- **controller 保留**：API Key 门禁；`SendIntent` 的 user message 写入与附件落库；`EditIntent` 的 user message 版本事务；上传任务清理；busy / `ChatState` 镜像；keepAlive / stop / flush 转发。
- **ReplyRun 拥有**：给定 `userMessageId`（或已有 `replyId`）后，创建/复用 Reply 行；Visible Path 切片、Latest Reminder 快照、continuation prefix；请求构造；SSE 消费与块合并；stale `file_id` 重试（最多 2 次、1s/2s 退避、收到内容块后不再重试）；终态结算（done/stopped/error）；标题采纳规则与写库；`onSnapshot`。
- **附件 port 收窄**：只保留「流式过程中发现 `file_id` 失效时，补齐 serverId 并重发」这一件事；首次附件上传/落库不属于 run。
- **结果**：`ReplySettled` / `ReplyRejected` 保留；`ReplyRejected` 只表示「Reply 未创建/未发出」，user message 是否已落库由 controller 的 intent 处理结果表达。这样 `send` 的「user message 是否提交」不再塞进 Run outcome。

这个边界与 GLOSSARY 一致，也符合官方「use-case 依赖 repository、但不拥有 repository」的定位（[Guide to app architecture · Data access with use-cases](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）。

### 3.2 SessionLifecycle：语义所有权与更窄边界

**spec 的主张：** `NotifierProvider<SessionLifecycleController, SessionLifecycleState>`，状态 `CurrentSession = Draft | Open(id) | Pending(id)` + `generation`；命令包括 `startNew`、`open`、`resolveInitial`、`createForFirstMessage`、`discardCreated`、`rename`、`setPinned`、`delete`、`historyReplaced`（`.scratch/session-lifecycle/spec.md`）。

**语义所有权：核心状态部分正确，rename/pin 偏宽。** `CurrentSession` 的三个变体有真实不变量：

- 最多一个当前 Session；
- `Pending` 在列表出现同 id 后转 `Open`；
- 删除当前后回落到剩余最近；无剩余回 `Draft`；
- 导入后 `generation++` 并回 `Draft`。

这些不变量只有 selection/create/delete/import 会改变。`rename` 与 `setPinned` **不读也不写当前选择**，不参与任何状态迁移；它们只是 repository 写操作。把它们放进同一个 notifier，等于把「当前会话状态机」扩成「所有 Session 写命令的总线」。spec 自己的目标句也只说「当前是哪个 Session 以及影响它的生命周期命令」——rename/pin 不影响当前 Session，按 spec 自己的定义就应排除。

**god-notifier 风险：低到中等。** 9 个公开命令不算爆炸，但其中 `rename`/`setPinned` 是浅包装；notifier 的测试面会从「状态迁移」扩大到「trim、空标题、未变化、批量置顶」等纯 repository 行为。Riverpod 官方没有 notifier 大小阈值（[DO/DON'T](https://riverpod.dev/docs/root/do_dont)，2026-11-24 未涉及），所以这是语义判断，不是违规判断。

**接口宽度 vs 深度：窄边界更深。** 宽接口：9 个方法，其中 2 个没有状态迁移；窄接口：7 个方法（`startNew`、`open`、`resolveInitial`、`createForFirstMessage`、`discardCreated`、`delete`、`historyReplaced`），每个都改变或解析当前选择。`delete` 是真正的深操作：stop 活动回复 → repository 事务 → 删除孤儿文件 → 更新选择；它必须留在模块里。`rename`/`setPinned` 是浅操作，留在 drawer 直接调用 repository 的代价只是「view 直接访问 data layer」这一条已知偏离；如果在意这条，另起一个薄的 `SessionActions` notifier 比合并进 lifecycle 更清晰。

**Riverpod fit：正确。** 当前选择被 `ChatHome`、`ChatPage`、`SessionDrawer`、搜索页共享，属于共享业务状态，不是单个 widget 的 ephemeral state；用 `NotifierProvider` 符合官方「providers 用于 shared business state」（[DO/DON'T](https://riverpod.dev/docs/root/do_dont)，2026-11-24）。`resolveInitial()` 必须是显式动作（app 初始化或首次列表就绪回调），不能在 `build` 中触发；官方禁止在 provider 初始化时做 side effect（[DO/DON'T](https://riverpod.dev/docs/root/do_dont)，2026-11-24）。spec 说「只在首次列表就绪时生效」，但没有说由谁、在何时调用；implementation 时必须把它接到 `ref.listen`/`initState`，不能重蹈 `_current(sessions)` 在 build 里改状态的覆辙。

**分层：有两个问题。**

1. **跨 feature import。** spec 写「`features/sessions` 不得 import `features/chat`」，但没说 `ChatPage`（`features/chat`）会 import `SessionLifecycle`（`features/sessions`）来调用 `startNew()` / `createForFirstMessage()`。这违反仓库 CLAUDE.md 的「功能之间不直接 import」和官方「layers communicate adjacent」的精神。三种修法：
   - **推荐**：`ChatHome`（app 层）把 `startNew`、`createForFirstMessage`、`discardCreated` 作为回调传给 `ChatPage`，保持 chat 不 import sessions；`ChatPage` 只在本地处理焦点。当前代码已经是回调形状（`onSessionCreated` / `onSessionDiscarded`），改造成本低。
   - 或者把 `SessionLifecycle` 的只读接口/命令 port 定义在 `shared/`，由 app 层 override 为真实实现；代价是多一层抽象。
   - 或者明确修规：允许 `chat → sessions` 单向依赖，禁止反向。这是最省代码但会留下长期例外，需要在 CLAUDE.md 写清楚。
2. **`stopSession` 函数类型 provider。** spec 计划在 `shared/providers.dart` 放一个默认 no-op 的函数 provider，app 层 override 为读取 `activeChatControllersProvider` 并 `stop()`。这是 composition-root seam，方向正确（shared 不 import features，app 负责接线）；但函数类型接口很宽（任意 `String → void`），测试与替换都靠约定。可接受，建议加一个明确的 typedef 与注释，说明它只用于「删除前停止活动回复」。

**结论：采用更窄的 SessionLifecycle。** 具体边界：

- **SessionLifecycle 拥有**：`CurrentSession` 状态、`generation`、`resolveInitial`、`startNew`、`open`、`createForFirstMessage`、`discardCreated`、`delete`、`historyReplaced`。
- **rename / setPinned 暂留 drawer + repository**：它们不改变当前选择；drawer 的 `title.trim()` 与「全部已置顶则取消」是 UI 组合，保留在 adapter 可接受。若后续要消除「view 直接写 repository」，再加一个独立的 `SessionActions` notifier（只有 rename/pin），不要塞回 lifecycle。
- **跨 feature 接线**：优先用 app 层回调；若选择修规，必须在 CLAUDE.md 明确单向例外。
- **`generation`**：保留在 lifecycle state 中作为 import epoch 可以；它本质上是「强制重建 ChatPage」的 key，不是业务状态。可以在注释中说明，避免后来者把它当领域概念。

### 3.3 更窄边界的对比结论

| 维度 | Reply Run 宽边界 | Reply Run 窄边界 | SessionLifecycle 宽边界 | SessionLifecycle 窄边界 |
| --- | --- | --- | --- | --- |
| 语义所有权 | 拥有 turn，跨 user message + Reply + Session title | 只拥有 Reply 执行，符合 GLOSSARY | 拥有 selection + 所有 Session 写命令 | 拥有 selection 与影响它的命令 |
| god-module 风险 | 中（700–900 行、多 port） | 低到中（核心流 + 结算） | 低到中（rename/pin 浅包装） | 低 |
| 接口宽度/深度 | 单入口深，但依赖面宽 | 单入口深，依赖面窄 | 9 方法，2 个无状态迁移 | 7 方法，均有状态迁移 |
| 可测试性 | 好，但 seam 测试面大 | 好，测试聚焦 | 好，但包含纯 repository 用例 | 好，测试即状态机 |
| Riverpod fit | 好（controller 管生命周期） | 好 | 好（shared business state） | 好 |
| 分层 | 可接受，跨 aggregate | 干净，feature-local | 有跨 feature import 问题 | 同样有，需接线修法 |

**判断：两份 spec 都应改窄。** Reply Run 的宽边界收益（少一次 user message 写入的重复）小于它带来的语义混乱与附件/turn 副作用归属问题；窄边界仍能消掉五条 intent 共有的 stream/retry/settle 重复，这是当前代码最大的重复源。SessionLifecycle 的宽边界在「消除 view 直接写 repository」上有价值，但代价是把浅命令塞进状态机；更干净的做法是先把 selection 状态机做深，rename/pin 留待独立 action 层。

## 4. 优化方向

按 impact / effort / risk 排序。每条写「做什么 / 为什么 / 来源 / 代价」。

### 4.1 收窄并落地 Reply Run（高 impact / 中 effort / 中 risk）

- **做什么**：按 3.1 的窄边界实现 `ReplyRun`：controller 负责 intent 级行创建与附件落库，run 负责 Reply 行之后的请求上下文、流、重试、结算、标题采纳。
- **为什么**：当前五条 intent 重复 key 检查、建行、加载、流式、结算；一条 assistant 回复被 `_liveReply`、`_copyReply`、`_settleInterrupted` 三处重建。官方把请求重试、错误处理、持久化归 data layer，把 UI 状态归 ViewModel（[Guide to app architecture · Repositories / View models](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）；把共有执行收进一个 feature-local 模块，比新增正式 domain layer 更符合「add use-cases only when needed」（[Architecture recommendations · Separation of concerns](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）。
- **代价**：四个 issue 的迁移顺序不变，但 issue 01 的接口要改小；`ReplyOutcome` 的 `send` 提交语义要重新表达。现有 controller/repository 测试保留，新增 `reply_run_test.dart` 用 fake repository/client（官方推荐 fake，见 [Testing each layer · ViewModel unit tests](https://docs.flutter.dev/app-architecture/case-study/testing)，2026-11-24）。

### 4.2 收窄 SessionLifecycle 并修跨 feature 接线（高 impact / 中 effort / 中 risk）

- **做什么**：只保留 `CurrentSession` 状态机与 selection/create/delete/import；rename/pin 暂留 drawer + repository。`ChatPage` 通过 `ChatHome` 回调获取 `startNew` / `createForFirstMessage` / `discardCreated`，不 import `features/sessions`。
- **为什么**：rename/pin 不改变当前选择，不参与状态不变量；把它们并入会让 notifier 变成命令总线。跨 feature import 违反仓库规则，也违背官方分层通信规则（[Common architecture concepts · Layered architecture](https://docs.flutter.dev/app-architecture/concepts)，2026-11-24）。用回调保持 chat 与 sessions 解耦，符合官方「view 通过 ViewModel/事件通信」的方向（[Guide to app architecture · Views](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）。
- **代价**：`ChatHome` 仍要持有少量接线代码；`focusRequests` 可以随 `startNew` 回调去掉。`stopSession` 函数 provider 保留，但加 typedef 与注释。若未来要消除 drawer 直接写 repository，再加独立 `SessionActions`。

### 4.3 移除 `ChatHome.build` 中的状态写入（中 impact / 低 effort / 低 risk）

- **做什么**：把 `_current(sessions)` 的首次选择逻辑移入 `SessionLifecycle.resolveInitial()`，由 `initState`/`ref.listen` 在列表首次就绪时显式调用；`build` 只读当前 id 与 generation。
- **为什么**：官方要求 View 只展示与转发（[Guide to app architecture · Views](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）；Riverpod 明确不要在 provider 初始化/widget 中做 side effect（[DO/DON'T](https://riverpod.dev/docs/root/do_dont)，2026-11-24）。当前「build 中写字段」依赖调用顺序，容易在列表刷新时出现难复现的状态。
- **代价**：需要定义「首次列表就绪」的触发点；现有 `app_test.dart` 的启动用例要改为等待 `resolveInitial` 完成。风险低，因为行为规格不变。

### 4.4 下沉 `features → app/theme` 的向上依赖（中 impact / 低 effort / 低 risk）

- **做什么**：把 `lib/app/theme.dart` 与 `lib/app/markdown_theme.dart` 中供 feature 使用的 token/样式移到 `lib/shared/theme/`，`app` 与 `features` 都向下依赖；`session_drawer`、`session_skeleton`、`session_search_page`、`messages_view`、`markdown_view` 改 import。
- **为什么**：仓库声明 `main → app → features → shared`，但 5 个 feature 文件反向 import `app/`；官方要求层间只与相邻层通信（[Common architecture concepts · Layered architecture](https://docs.flutter.dev/app-architecture/concepts)，2026-11-24）。这是纯移动，不改行为。
- **代价**：机械改 import + 跑 analyze/test；`appThemeSeed` 等仍可留在 app，只移动 feature 需要的 token。风险低。

### 4.5 把 `sessionsProvider` 移出 widget 文件（中低 impact / 极低 effort / 低 risk）

- **做什么**：把 `sessionsProvider` 从 `session_drawer.dart` 移到 `session_lifecycle.dart` 或新建 `sessions_providers.dart`；drawer 与 app 都 import 数据模块。
- **为什么**：官方把 data layer 对象与 UI 分开（[Architecture case study · Package structure](https://docs.flutter.dev/app-architecture/case-study)，2026-11-24）；`app.dart` 目前为了拿数据源 import 一个 1,351 行的 widget 文件，发现性与测试都不好。官方没有硬性规定 provider 文件位置，所以这是可读性/一致性改进，不是违规修复。
- **代价**：移动一个顶层 final + 改 import；无行为变化。

### 4.6 为新 seam 补测试，但不重写现有测试（中 impact / 中 effort / 低 risk）

- **做什么**：`reply_run_test.dart` 用 fake repository + fake client 覆盖 send/regenerate/edit/continue/retryUpload 的流式、stop、flush、标题采纳、stale-file 重试、Rejected；`session_lifecycle_test.dart` 用 `ProviderContainer.test` + fake repository 覆盖 Draft/Open/Pending 迁移、删除回落、导入 generation、命令失败。现有 controller/repository/widget 测试原样保留。
- **为什么**：官方要求每个 service/repository/ViewModel 都有 unit test，并优先 fake（[Architecture recommendations · Testing](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24；[Testing each layer](https://docs.flutter.dev/app-architecture/case-study/testing)，2026-11-24）。Riverpod 推荐用 `ProviderContainer.test`、不共享 container、不 mock notifier 本身（[Testing your providers](https://riverpod.dev/docs/how_to/testing)，2026-11-24）。
- **代价**：fake 需要跟随 repository 接口演进；如果 fake 与真实 repository 偏差过大，会出现「测试绿、线上错」。因此保留现有真实内存库测试作为行为安全网，fake 只用于新模块的快速单测。

### 4.7 补 1–2 条关键路径 integration test（中 impact / 中 effort / 低 risk）

- **做什么**：在 `integration_test/` 增加一条「发送 → SSE 流式 → 停止/完成 → 重开会话看到终态」的真机/模拟器用例；如果成本允许，再加一条「导入归档 → 删除全部 → 回到草稿且 generation 递增」。
- **为什么**：官方测试配比要求「enough integration tests to cover all the important use cases」（[Testing Flutter apps](https://docs.flutter.dev/testing/overview)，2026-11-24）；当前 integration 只有 list perf 与 composer，核心 reply 生命周期和 import reset 没有设备级覆盖。官方 integration 页只讲运行方式，没有给数量标准（[Check app functionality with an integration test](https://docs.flutter.dev/testing/integration-tests)，2026-11-24），所以按「核心用例」取舍，不追求全覆盖。
- **代价**：需要设备/模拟器与 CI runner；维护成本高于 unit/widget（官方取舍表）。不要为每个 intent 写 integration，只覆盖一条主路径与一条数据重置路径。

### 4.8 可选：`ChatRepository` 继续增长时拆 drift DAO（低 impact / 中 effort / 低 risk）

- **做什么**：如果 `ChatRepository` 继续超过约 1,500 行或新增大量查询，按表/查询组抽 `@DriftAccessor` DAO（sessions、messages、attachments、search），repository 保留为 facade 与事务编排。
- **为什么**：drift 官方建议「查询多了就拆 DAO」（[DAOs](https://drift.simonbinder.eu/dart_api/daos/)，2026-11-24）；Flutter 官方仍要求 repository 作为数据真相源（[Architecture recommendations · Separation of concerns](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）。两者可以并存：DAO 是查询模块化，repository 是对外接口。
- **代价**：新增生成代码与 mixin，事务跨 DAO 时要小心（事务必须 `await`，见 [Transactions](https://drift.simonbinder.eu/dart_api/transactions/)，2026-11-24）。当前 1,203 行尚未到必须拆的程度，**不是本轮优先项**。

## 5. 不建议做的改动

1. **不要新增正式 domain layer / 每个操作一个 use-case。** 官方明确 domain layer 可选、多数 app 加了只是 overhead；只有逻辑挤爆 ViewModel 或重复逻辑反复出现才加（[Architecture recommendations · Separation of concerns](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24；[Guide to app architecture · Optional: Domain layer](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）。SeekChat 用两个 feature-local 模块 + 两个纯规则模块足够。
2. **不要为了对齐「abstract repository classes」而给 `ChatRepository` 加空接口。** 官方这条的目的是 dev/staging 多实现（[Architecture recommendations · App structure](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）；当前只有一个实现且测试用真实内存库，加接口只会增加跳转。等第二个实现出现再抽。
3. **不要迁移到 riverpod_generator。** 官方说 codegen 可选，只有已经在用 codegen 时才值得，且 generator 仍较慢（[About code generation · Should I use code generation?](https://riverpod.dev/docs/concepts/about_code_generation)，2026-11-24）。手写 provider 是官方支持的路径；迁移会改动大量文件与生成物，收益不匹配。
4. **不要把现有真实内存库测试整体换成 mock repository。** drift 官方推荐用 `NativeDatabase.memory()` 测 data layer（[Testing](https://drift.simonbinder.eu/testing/)，2026-11-24）；现有测试覆盖 SQL、事务、可见路径，换成 mock 会丢掉这些保障。只在新模块的 unit test 里用 fake。
5. **不要引入 nested ProviderScope / provider scoping。** 官方说 scoping 很复杂、未来可能重做，适用场景只有页面级定制、性能优化、避免传参（[Scoping providers](https://riverpod.dev/docs/concepts2/scoping)，2026-11-24）。SeekChat 没有这些需求，app 级 override 已足够。
6. **不要采用 Riverpod Mutations / offline persistence。** 两者在 3.0 仍标注 experimental（[What's new in Riverpod 3.0 · Mutations (experimental) / Offline persistence (experimental)](https://riverpod.dev/docs/whats_new)，2026-11-24）。Reply Run 的 side effect 用普通对象 + notifier 转发即可。
7. **不要按行数硬拆 `ChatController`。** 官方没有 ViewModel 行数上限；拆分的依据是职责（UI state vs data orchestration）与测试 seam，不是 1,000 行阈值。按职责拆出 Reply Run 后，controller 自然会降到可维护规模。
8. **不要为了形式 immutability 在流式热路径上 `List.unmodifiable`。** 官方建议 immutable data models（[Architecture recommendations · Handling data](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24），但当前每个 SSE 事件都会重建 reply；给 `blocks`/`messages` 加不可变包装会增加分配。保持「字段 final + 生产端复制」即可。
9. **不要引入 go_router / freezed / ChangeNotifier 以「对齐官方推荐」。** 这些推荐是 Conditional 或针对多页面导航/大型模型（[Architecture recommendations · Handling data / App structure](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）；SeekChat 是单聊天页 + 抽屉 + sheet，现有导航与不可变类已够用。
