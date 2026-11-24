# 03: Contract，删除旧选择状态与回调

**What to build:** 选择与生命周期命令全部经 SessionLifecycle 后，删除 ChatHome 的 selectedId / draft / openedLatest / focusRequests / currentId / pendingCreatedId / historyEpoch，删除 ChatPage 的第二份 session id，删除抽屉的 onOpen / onDeleted / cancelSession 等回调与直接 repository 写入。ChatPage 的新对话入口直接调用模块并本地聚焦；列表变化只按当前 id 与 generation 触发必要重建。

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] 选择状态只存在于 SessionLifecycle，ChatHome 与 ChatPage 不再保存副本
- [ ] 抽屉与搜索页只调用模块命令，不再直接写 repository
- [ ] 新对话焦点由 ChatPage 本地处理，ChatHome 不再中转 focus 计数
- [ ] 列表数据变化与标题变化不导致不必要的 ChatPage 重建
- [ ] 全量现有测试通过；模块测试覆盖所有状态迁移
- [ ] `flutter analyze` 与 `flutter test` 通过
