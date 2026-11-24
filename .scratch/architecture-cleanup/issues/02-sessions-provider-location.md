# 02: 把 sessionsProvider 移出 widget 文件

**What to build:** 会话列表的全局 StreamProvider 目前定义在会话抽屉 widget 文件里，app 为了拿数据源 import 一个 1,351 行的 widget。把 provider 移到不依赖 widget 的会话数据模块（例如 `sessions_providers.dart` 或 `session_lifecycle.dart`），抽屉与 app 都从数据模块 import。无行为变化。建议在 session-lifecycle 票 01 之前完成，避免同一 provider 两处改。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 全局会话列表 provider 不再定义在 widget 文件里
- [ ] app、抽屉与测试改为从数据模块 import
- [ ] 列表流行为、错误重试与 autoDispose 语义不变
- [ ] 现有 app 与抽屉测试通过
- [ ] `flutter analyze` 与 `flutter test` 通过
