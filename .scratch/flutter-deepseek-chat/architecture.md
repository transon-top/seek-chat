# 应用架构

本文锁定票 07「应用架构与项目结构」的决策，约束 `api.md`、`data-model.md` 与
`GLOSSARY.md` 之上的代码组织。迁移已按第 12 节完成第 1–6 步（目录、Riverpod、
ARB、安全项），第 7 步 shadcn_ui 随票 09 / 10 接入；每一步保持
`flutter analyze` 与 `flutter test` 通过。

## 1. 分层与目录

功能优先（feature-first）+ 共享核心。功能目录拥有自己的界面与控制器；
只有被两个以上功能复用的代码才进 `shared/`。

```
lib/
  main.dart          # 启动、数据库打开、残留状态收尾、ProviderScope
  app/               # OpenChatApp、路由表、主题、locale 接线、错误文案映射
  features/
    chat/            # 聊天页、消息控件、ChatController
    sessions/        # 会话列表
    settings/        # 设置页
    search/          # 搜索进度、引用抽屉与来源卡片（票 12）
    history/         # 导入导出（票 17）
  shared/
    api/             # DeepSeekApiClient、SSE、request、errors
    data/            # drift 数据库、ChatRepository、AttachmentStore
    models/          # 领域与协议类型、JSON 编解码
    prefs/           # shared_preferences 封装
    security/        # ApiKeyStore
    speech/          # 语音权限与朗读偏好（票 21，聊天与设置共用）
    providers.dart   # 基础设施 Provider，features 与 main 共用
    error_text.dart  # 本地化错误文案的唯一映射点
    logging.dart     # 仅 debug 构建输出的日志
  l10n/              # ARB 与生成的 AppLocalizations
```

依赖方向固定为 `main → app → features → shared`。`shared/` 不得 import
`features/`；功能之间不直接 import，共享逻辑先下沉到 `shared/`。

现有代码迁移映射：

| 现在 | 目标 |
| --- | --- |
| `lib/api/` | `lib/shared/api/` |
| `lib/data/` | `lib/shared/data/` |
| `lib/models/` | `lib/shared/models/` |
| `lib/app.dart` | `lib/app/` |
| `lib/chat/` | `lib/features/chat/` |
| `lib/ui/chat_page.dart`、`lib/ui/markdown_view.dart` | `lib/features/chat/` |
| `lib/ui/home_page.dart` | `lib/features/sessions/` |
| `lib/settings/settings_page.dart` | `lib/features/settings/` |
| `lib/settings/api_key_store.dart` | `lib/shared/security/` |

`test/` 目录跟随源码同名分层移动。

## 2. 状态管理与依赖注入

使用 `flutter_riverpod` 3.5，手写 Provider，不引入 `riverpod_generator`。

- 基础设施用同步 `Provider`（定义在 `shared/providers.dart`）：`appDatabaseProvider`、`chatRepositoryProvider`、
  `apiClientProvider`、`apiKeyStoreProvider`、`attachmentStoreProvider`、
  `sharedPreferencesProvider`。
- 启动顺序留在 `main()`：打开数据库、`resetInterruptedReplies()`、附件孤儿清理，
  然后 `runApp(ProviderScope(...))`。启动失败的处理见 `api.md` 与票 10。
- 会话列表用 `StreamProvider`，底层新增 `ChatRepository.watchSessions()`
  监听 drift 查询；界面不再手写 `_load()`。
- 聊天控制器用 `NotifierProvider.autoDispose.family<ChatController, ChatState, String>`
  （参数为 `sessionId`）。流式事件由 `Notifier` 手动合并，不用 `StreamProvider`：
  合并、停止与终态写库顺序是 `api.md` 的契约，`StreamProvider` 无法表达。
- 流式期间控制器调用 `ref.keepAlive()`，结束后释放；用户离开聊天页不会取消请求，
  回到同一会话拿到同一个控制器与内存中的最新回复。`ref.onDispose` 负责兜底取消。
- 路由沿用 `Navigator` 1.0 + `MaterialPageRoute`。v1 没有深链与 Web URL，
  不引入 `go_router` 或 `auto_route`。

## 3. 并发与生命周期

- 每个会话同一时间只允许一个生成中的回复；不同会话可以并行生成，与
  `chat-demo` 的 `streaming: Record<sessionId, AbortController>` 一致。
  会话内的闸门由 `ChatController.busy` 与 `ActiveReply`（`sessionId`、`replyId`、
  `abort`）表达，不设全局锁。
- 切换会话不取消后台流；多个会话可同时显示生成中状态。
- App 进入 `paused` / `hidden` 时把各控制器内存中的回复补写一次
  （`data-model.md` §4）。v1 不申请 iOS 后台执行权限；系统挂起或杀掉进程后，
  下次启动把残留 `pending`/`streaming` 置为 `stopped`。
- 音频同一时刻只有一个通道：录音与朗读互斥，规则见 [`speech.md`](speech.md) §4.3。

## 4. 数据层边界

- drift 的 `AppDatabase` 就是数据源；`ChatRepository` 直接封装查询与事务，
  不额外增加 `DataSource` 接口层。
- `AttachmentStore` 只管理原件文件与孤儿清理；数据库元数据仍归 `ChatRepository`。
- 流式期间不写库；只在创建、请求发出前与终态迁移时落盘（`data-model.md` §4）。
- 会话列表的响应式更新由 drift watch 提供，不引入第二套缓存。

## 5. 错误处理与日志

- 传输与协议错误继续统一为 `ApiException`（`api/errors.dart`），
  `kind`、`status`、`condition`、`retryable` 是 UI 的唯一判断依据。
- `shared/error_text.dart` 提供唯一的本地化映射函数，把 `ApiErrorCondition`
  映射为 ARB 文案；features 直接复用，未知异常统一显示「发生错误，请重试」。服务端原文只在 debug 构建显示，
  release 构建不展示原始 `message`。
- 回复级错误按 `data-model.md` §2.2 存 `kind`、`message`、`status`、
  `localMessage`（键与参数）与 `retryable`；界面优先渲染 `localMessage`，
  未知键回退到按 `kind` 的通用文案，服务端 `message` 仅 debug 显示。
- 日志使用 `dart:developer` 的 `log`，仅在 `kDebugMode` 输出。禁止记录 API Key、
  请求头、完整请求体与附件内容。v1 不引入日志 SDK 或崩溃上报。

## 6. 配置与设置

- `AppConfig` 只读编译期常量：API origin 来自
  `--dart-define=OPEN_CHAT_API_ORIGIN`，默认 `https://api.deepseek.com`；
  模型固定 `deepseek-flash`。
- 不建 Feature flag 框架，也没有远程配置。行为差异由用户设置或票内常量控制。
- 本机设置对齐 `chat-demo`：语言、主题偏好、所在地、朗读音色、深度思考、
  联网搜索、侧栏状态。首次默认：语言跟随系统、主题跟随系统、所在地为空、
  音色 `stella`、思考与搜索关闭；之后保存用户选择。
- 设置用 `shared_preferences` 持久化，经由 `shared/prefs/` 封装；API Key
  不进 `shared_preferences`，只走安全存储。字段与键名由票 16、18、20 定稿。

## 7. 安全

- API Key 只经 `ApiKeyStore` 读写。iOS 使用
  `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`：
  设备首次解锁后可读，且不随备份迁移到新设备。它不提供后台执行能力，
  后台行为见第 3 节。Android 使用 `flutter_secure_storage` v11
  默认密码套件，v1 不启用生物识别。
- Key 不写数据库、不进日志、不进导出包、不进崩溃上报；导出格式由票 17 定义。
- Android `allowBackup="false"`：聊天记录通过导入导出迁移，避免系统备份把
  安全存储密文与数据库恢复到新设备。
- 收到 401 时不清除 Key，只提示用户到设置中更新。
- 移动端 BYOK 的 Key 仍可被逆向提取；v1 接受此风险，生产分发改用服务端代理
  不在本版范围。

## 8. UI 组件库

- 目标组件库为 `shadcn_ui` 0.60.x。它依赖 `material_ui ^1.11.1`，与现有渲染栈
  兼容；`gpt_markdown`、`mermaid_flutter` 继续使用 `material_ui` 控件。
- 现有页面在票 09 / 10 定稿前保持 `material_ui`；新界面直接用 shadcn_ui，
  不做一次性重写。

## 9. i18n 与主题

- 使用官方 `gen_l10n` + ARB：`lib/l10n/app_en.arb`（模板）与
  `lib/l10n/app_zh.arb`，生成物输出到 `lib/l10n/generated/` 并入库。
  `l10n.yaml` 固定 `arb-dir`、`output-dir`、`output-class: AppLocalizations`。
- `MaterialApp` 接入 `AppLocalizations.delegate`、`GlobalMaterialLocalizations` 等
  委托，`supportedLocales` 为中英两种。
- 语言与主题偏好存在设置状态中，切换行为（是否即时生效、是否影响已生成内容）
  由票 18 定。主题提供浅色、深色与跟随系统三档；shadcn_ui 主题从同一
  Material 主题种子构建。

## 10. 测试边界与质量门槛

- 单元测试：`shared/api`（SSE、事件解析、请求构造）、`shared/data`
  （drift 内存库上的仓库与附件清理）、各功能控制器（合并、并发、错误映射）、
  `features/history` 的 ZIP 归档读写与覆盖导入。
- widget 测试：每个功能页面，使用 `ProviderScope` override、`NativeDatabase.memory()`
  与 `http/testing.dart` 的 `MockClient`；覆盖空态、错误态与关键交互。
- `integration_test` 只覆盖平台插件：安全存储、文件选择、录音与播放。
  在模拟器手动执行，不进入默认测试套件；首次需要时再加依赖。
- 质量门槛：每次改动运行 `flutter analyze` 与 `flutter test`；不设覆盖率百分比，
  不引入 golden 测试。新分支、循环、解析或金额/安全相关逻辑必须带测试。

## 11. 代码生成与版本策略

- 代码生成只有两链：drift（`drift_dev` + `build_runner`）与 gen_l10n。
  不引入 `freezed` / `json_serializable`；领域与协议模型保持手写，
  未知字段容错与协议原样保存由 `models/json.dart` 负责。
- 生成物（`database.g.dart`、`lib/l10n/generated/`）入库，checkout 后无需先
  生成即可测试。
- 命令：

```bash
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter analyze
flutter test
```

- 直接依赖使用 caret 范围；`shadcn_ui` 因 pre-1.0 锁 `>=0.60.0 <0.61.0`；
  `pubspec.lock` 入库。升级依赖后必须重跑 analyze 与测试。
- 暂不添加 CI 配置；发布前再加 GitHub Actions，至少执行上述四条命令。

### 依赖清单

版本以 `pubspec.lock` 为准；本表是锁定时的直接依赖快照。

| 包 | 版本 | 用途 |
| --- | --- | --- |
| `flutter` | SDK | 运行时与界面框架 |
| `material_ui` | `^1.1.0`（锁 1.11.1） | Material 3 基础与 shadcn_ui 底座 |
| `flutter_riverpod` | `^3.5.0`（新增） | 状态管理、依赖注入 |
| `shadcn_ui` | `>=0.60.0 <0.61.0`（新增） | 目标组件库 |
| `shared_preferences` | `^2.5.6`（新增） | 本机设置 |
| `flutter_localizations` | SDK（新增） | 本地化委托 |
| `intl` | `^0.20.2`（新增直接依赖） | gen_l10n 运行时 |
| `cupertino_icons` | `^1.0.8` | 图标资源 |
| `http` | `^1.6.0` | 网络、SSE、AbortableRequest |
| `drift` | `^2.35.4` | 数据库 |
| `sqlite3` | `^3.9.1` | drift 原生实现 |
| `path_provider` | `^2.1.6` | 应用目录 |
| `path` | `^1.9.1` | 路径拼接 |
| `uuid` | `^4.6.0` | 主键 |
| `flutter_secure_storage` | `^11.2.0` | API Key |
| `gpt_markdown` | `^1.4.1` | Markdown 与代码高亮 |
| `mermaid_flutter` | `^0.3.2` | Mermaid 绘制 |
| `mermaid_core` | `^0.3.2` | Mermaid 解析与主题 |
| `url_launcher` | `^6.3.3` | 外部链接 |
| `file_picker` | `^13.4.0`（新增） | 相册、文件选择与导出保存（票 13、17） |
| `archive` | `^3.6.1`（新增） | 历史归档 ZIP 读写（票 17） |
| `record` | `^7.2.0` | 语音输入录音 |
| `flutter_soloud` | `^5.3.0` | 朗读 PCM 流式播放 |
| `permission_handler` | `^13.0.2` | 麦克风权限状态与跳系统设置 |
| `drift_dev` | `^2.35.3`（dev） | drift 代码生成 |
| `build_runner` | `^2.17.1`（dev） | 代码生成入口 |
| `flutter_test` | SDK（dev） | 单元与 widget 测试 |
| `flutter_lints` | `^6.0.0`（dev） | 静态规则 |
| `val_latex_flutter` | `^0.1.4`（dev） | 数学渲染的测试断言 |

## 12. 迁移顺序

1. 加入新依赖与 `l10n.yaml`，保持行为不变。
2. 按第 1 节移动目录与测试，修正 import；`flutter analyze` 与 `flutter test` 全绿。
3. 接入 Riverpod 基础设施 Provider 与 `ProviderScope`，设置状态改 `shared_preferences`。
4. `ChatController` 改为 `Notifier` + family + `keepAlive`；会话内的
   `ActiveReply` 保证单请求；会话列表改 `watchSessions()` + `StreamProvider`。
5. 错误文案迁入 ARB，日志收口到调试封装。
6. 落实安全选项与 Android `allowBackup="false"`。
7. shadcn_ui 随票 09 / 10 接入。

## 13. 交由后续票决定

- 票 09 / 10：shadcn_ui 主题、布局、控件与动效。
- 票 12：搜索进度、引用抽屉、来源卡片。
- 票 16 / 18：设置字段、语言切换与主题行为。
- 票 17：导出格式与覆盖导入；导出包不含 API Key。
- 票 20：设置与数据管理界面。
- 票 21：语音输入与朗读已定稿，见 [`speech.md`](speech.md)。
