# Flutter 启动失败处理与错误界面最佳实践

Type: research
Status: resolved

## Question

调研以下问题，产出带出处的事实结论，供「启动失败的错误界面」四问决策：

1. `runApp` 之前或期间失败，Flutter 官方推荐的捕获与展示路径：
   `runZonedGuarded`、`PlatformDispatcher.instance.onError`、
   `FlutterError.onError`、`ErrorWidget.builder` 各自的覆盖范围；
   二次 `runApp` 替换根组件是否受支持、有什么限制。
2. 不依赖 `SharedPreferences` 的最小错误 App：主题与语言取值的通行做法；
   失败页与用户已存偏好不一致时的取舍。
3. 各类启动失败的严重性：drift / SQLite 打开与迁移失败的可重试性、
   迁移是否事务回滚、WAL/SHM 文件的性质；`SharedPreferences.getInstance()`
   失败的表现；文件清理失败作为非阻塞项的依据。
4. 「清除本地数据」恢复入口：iOS HIG / App Review 与 Android 对程序自行退出、
   数据重置的约束；确认流与数据丢失文案的通行做法；删除 SQLite 库需覆盖的文件。
5. 启动链的可测试性：Flutter / Dart 官方或成熟项目如何为 bootstrap 注入替身、
   覆盖启动失败路径。
6. 致命错误页的可访问性与本地化最低要求。

范围：只取高可信第一手来源（Flutter、Apple、Android 官方文档，drift 与
shared_preferences 官方文档，相关 API 文档）；只给事实与出处，不写本项目实现方案。

## Answer

已解决（2026-11-23）。Findings 不合并，保存在
`research/startup-failure-best-practices` 分支（commit `584dff1`）：
`docs/research/startup-failure-best-practices.md`。

关键事实：

1. Flutter 现行错误捕获 = `FlutterError.onError`（build/layout/paint）+
   `PlatformDispatcher.instance.onError`（root isolate 未处理错误）+
   `ErrorWidget.builder`（build 兜底）；官方页面不再提 `runZonedGuarded`。
   二次 `runApp` 受支持，替换根并丢弃旧树状态。启动链应显式 try/catch 后用
   二次 `runApp` 渲染错误 App，全局钩子只兜未预期错误。
2. 不读偏好的最小 App 可用系统主题（`ThemeMode.system`）与 `locale: null`
   （Flutter 按系统语言解析）；不阻塞首帧。
3. drift 迁移默认不在事务中；失败后 schema version 不前进，同一实例缓存
   `_migrationError`，`LazyDatabase` 缓存 opener 失败 Future——复用实例重试无效。
   官方建议每一步迁移包事务；`SQLITE_CORRUPT` / `SQLITE_NOTADB` 重试无益。
   本项目 `onUpgrade` 未包事务。
4. 删除 SQLite 需先关闭连接，再删主库及 `<db>-journal` / `-wal` / `-shm`；
   `-wal` 属于持久状态。`SharedPreferences.getInstance()` 失败以 Future error
   返回，插件允许重试，但不保证数据完整；异常类型未文档化。legacy
   `SharedPreferences` API 官方已标注将被弃用。
5. iOS 无优雅退出 API（QA1561，退出表现为崩溃），也无整应用重置 API；
   Android 有 `clearApplicationUserData()`（清除全部动态数据、撤销权限）。
   自建重置须自行定义并写明范围（含安全存储是否包含）。
6. 错误页最低要求：所有文本进 ARB；文字说明不靠颜色；读屏可识别
   （`liveRegion` / `SemanticsService.announce`）；对比度 ≥ 4.5:1；
   文字可放大 200%；点击目标 ≥ 48×48。错误页不自动消失。
7. 可测试性官方拼图：composition root + 构造器注入、Riverpod override、
   drift `NativeDatabase.memory()` + `SchemaVerifier`、shared_preferences
   `setMockInitialValues`；官方无 bootstrap 专项配方，建议抽 `bootstrap(deps)`。

不确定项与风险见 findings 末节：`main()` 同步抛错是否进入
`PlatformDispatcher.onError` 未实测；iOS 退出政策来自 archived QA1561；
drift / SQLite 可重试性分类含工程判断。
