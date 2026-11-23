# Map: 启动失败的错误界面

> 状态：决策完成（2026-11-23），可进入实现。实现不在本图内。

## Destination

定案启动失败时的处理：哪些失败阻塞启动、应用级错误界面的形态与文案、
错误界面的落点与首帧主题/语言来源、测试接缝；产出可直接照做的界面规格
（含 ARB 键清单与测试路径）。实现不在本图内。

## Notes

- 来源：`docs/features/README.md` §3 指向本图；票 01 从已删除的
  `.scratch/flutter-deepseek-chat/issues/22-startup-failure.md` 迁来。
- 既有事实：`main()` 在 `runApp` 前依次打开 drift 库、`resetInterruptedReplies()`、
  读 `SharedPreferences`、debug 样本、附件孤儿清理；除 debug 样本与孤儿清理外
  均未捕获异常。`AppDatabase.open()` 是 `LazyDatabase`，数据库打开与迁移失败
  在首次查询（`resetInterruptedReplies()`）才暴露。
- 附件孤儿清理已定：失败不阻塞，下次启动再试（`docs/features/sessions/session-drawer.md`）。
- 已有同类界面：会话列表加载失败页（`sessionsLoadFailed` + 重试），但位于
  `ProviderScope` 内、依赖已注入的四个基础设施实例。
- 启动失败时 `AppLocalizations` 与 shadcn 主题都可用（纯内存构造），但主题与
  语言偏好来自 `SharedPreferences`，失败界面需决定取偏好还是取系统默认。
- 文案走 ARB（`app_en.arb` 模板 / `app_zh.arb`）；错误文案唯一映射点
  `lib/shared/error_text.dart` 依赖 `ApiErrorCondition`，不覆盖启动失败。
- 会话开始前读 `GLOSSARY.md` 与 `docs/adr/`；本图票型为 grilling，
  调用 grilling + domain-modeling 技能。
- 研究约定：findings 写在 `research/<name>` 分支的 `docs/research/`，不合并、
  不开 PR；票内记录分支、commit 与路径。

## Decisions so far

<!-- 每个已关闭的票一行：票名 + 一句话结论。详细答案在票内。 -->

- [Flutter 启动失败处理与错误界面最佳实践](issues/02-startup-failure-best-practices.md): 捕获路径用 `FlutterError.onError` + `PlatformDispatcher.onError` + `ErrorWidget.builder`，启动链显式 try/catch 后二次 `runApp`；drift 迁移默认不在事务中且实例缓存失败，重试必须新建实例；重置须先关连接再删主库与 `-journal`/`-wal`/`-shm`；iOS 无优雅退出与整应用重置 API，Android 有 `clearApplicationUserData()`；错误页可用系统主题与 `locale: null` 渲染。Findings 在 `research/startup-failure-best-practices` 分支 `584dff1`。
- [启动失败的错误界面](issues/01-startup-failure.md): 除 debug 样本与附件清理外，启动失败全部阻塞并进入启动失败页；失败页在 `ProviderScope` 外由二次 `runApp` 渲染，prefs 提前读取，失败时用系统主题/语言；重试重建全部实例；重置先关库再删主库与 `-journal`/`-wal`/`-shm` 及附件目录，保留设置与 API Key；`onUpgrade` 包事务；新增 7 个 ARB 键并复用 `retry`/`cancel`；测试见 `test/app/startup_test.dart`。

## Not yet specified

<!-- 暂无：票 01 的四个问题已是全部已知待决项。 -->

## Out of scope

- 启动失败以外的运行时错误界面（会话加载失败、回复错误已有规格）
- 崩溃上报与遥测
- 自动清库、自动无限重试（只在人工触发时重置）
- iOS / Android 原生启动崩溃（Dart 尚未执行的阶段）
