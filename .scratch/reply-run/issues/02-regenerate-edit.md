# 02: Regenerate 与 Edit 的 Reply 部分走 ReplyRun

**What to build:** 重新生成与编辑提问的 Reply 执行改经 ReplyRun。重新生成由 controller 找到 user message，Run 在同一 user 下创建新的 Reply 版本并流式结算；编辑由 controller 完成 `editUserMessage` 事务（新 user 版本、附件引用、pending Reply），Run 接管已创建的 Reply 行。user message、附件复制与上传任务仍由 controller 负责。

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] 重新生成产生新版本，旧 Reply 与其子树保留，并生成新的 Latest Reminder 快照
- [ ] 编辑产生同父的新提问版本与新 Reply，旧回答不进入请求上下文
- [ ] 空白编辑复用原附件，不丢附件引用
- [ ] stop、flush、标题采纳行为与现状一致
- [ ] `ReplyRejected` 只在 Reply 未创建/未发出时出现；编辑事务失败由 controller 处理
- [ ] 现有 controller 测试原样通过；新增 seam 测试覆盖编辑事务后的接管与重新生成
- [ ] `flutter analyze` 与 `flutter test` 通过
