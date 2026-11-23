# 03: 启动链前置改造

Status: ready-for-agent
Blocked by: 无（可立即开始）

## What to build

启动失败处理的前置改造，不改变现有成功启动行为：

- 数据库 `onUpgrade` 在事务中执行，迁移失败回滚、schema version 不前进，同一库文件可再次打开并完成迁移。
- 启动链抽成可注入的 `bootstrap(deps)`：数据库工厂、prefs 加载、残留回复收尾、debug 样本、附件清理全部可替换；`main()` 只组装真实实现并 `runApp`。
- `SharedPreferences.getInstance()` 提前到数据库打开之前，为后续失败页提供主题与语言偏好。

本票只提供接缝，不新增错误界面。

## Acceptance criteria

- [ ] `onUpgrade` 在事务中执行；迁移中途失败后回滚，schema version 不前进。
- [ ] 迁移失败后再次打开同一数据库文件可完成迁移。
- [ ] `bootstrap(deps)` 可由测试驱动，五个依赖全部可注入替身。
- [ ] prefs 读取发生在数据库打开之前。
- [ ] `main()` 只注入真实实现并 `runApp`；成功启动路径的用户可见行为与现状一致。
- [ ] `flutter analyze` 与全量 `flutter test` 通过。
