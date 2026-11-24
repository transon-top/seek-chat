# 03: Contract，删除旧选择状态与回调

**What to build:** 选择与删除命令全部经 SessionLifecycle 后，删除 ChatHome 的 selectedId / draft / openedLatest / focusRequests / currentId / pendingCreatedId / historyEpoch，删除 ChatPage 的第二份 session id，删除抽屉的 onOpen / onDeleted / cancelSession 等删除回调与直接删除 repository 的代码。ChatHome 仍保留三个命令回调与当前 id 的接线；置顶/重命名继续直接在抽屉调用 repository。新对话焦点由 ChatPage 本地处理。

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] 选择状态只存在于 SessionLifecycle，ChatHome 与 ChatPage 不再保存副本
- [ ] 抽屉与搜索页只调用模块命令；置顶/重命名是唯一保留的直接 repository 写路径
- [ ] 新对话焦点由 ChatPage 本地处理，ChatHome 不再中转 focus 计数
- [ ] 列表数据变化与标题变化不导致不必要的 ChatPage 重建
- [ ] 全量现有测试通过；模块测试覆盖所有状态迁移
- [ ] `flutter analyze` 与 `flutter test` 通过
