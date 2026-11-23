# 04: 启动失败页与重试

Status: ready-for-agent
Blocked by: 03

## What to build

启动失败时用户能看到错误页并重试：

- **阻塞并进入失败页**：prefs 读取失败、数据库打开/迁移失败、残留回复收尾失败。
- **不阻塞**：debug 样本写入失败、附件孤儿清理失败，正常进入应用。
- 失败时由 `main()` 捕获，二次 `runApp` 一个 `ProviderScope` 外的最小错误 App；页面含错误图标、标题、说明、主按钮「重试」，无退出按钮。
- 主题与语言：prefs 已读到时用已存 `ThemeMode` 与 `locale`；未读到时用 `ThemeMode.system` + `locale: null`（系统解析）。
- 重试从头重跑整条启动链：新建数据库实例、重新读取 prefs；不复用缓存的失败实例或失败结果；成功后二次 `runApp` 真实应用。
- debug 构建在说明后附原始异常；release 不显示。
- 可访问性：文案全走 ARB；说明为 `liveRegion`；标题为语义 header；点击目标 ≥ 48×48；对比度 ≥ 4.5:1；随系统字号放大到 200%；页面不自动消失。

## Acceptance criteria

- [ ] 数据库打开/迁移失败、prefs 失败、残留回复收尾失败均显示启动失败页。
- [ ] debug 样本写入失败、附件孤儿清理失败不显示错误页，正常进入应用。
- [ ] 首次失败、重试成功：数据库工厂被调用两次，进入聊天页。
- [ ] prefs 失败时页面使用系统主题与系统语言。
- [ ] prefs 成功、数据库失败时页面沿用已存主题与语言。
- [ ] 重试不复用失败的数据库实例或 prefs 失败结果。
- [ ] debug 构建显示原始异常；release 不显示。
- [ ] 说明为 `liveRegion`，标题为语义 header，点击目标 ≥ 48×48，系统字号 200% 下不截断，页面不自动消失。
- [ ] ARB 新增 `startupFailedTitle`、`startupFailedBody`，复用 `retry`；en/zh 与生成物同步。
- [ ] `flutter analyze` 与全量 `flutter test` 通过。
