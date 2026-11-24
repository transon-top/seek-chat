# 01: Send 走 ReplyRun

**What to build:** 把一条 Reply 的生命周期收进新的 Reply Run 模块，并让发送一条消息的完整路径经它完成：用户 Message 与 Reply 行落库、请求上下文（Visible Path、Latest Reminder 快照、续写前缀规则）、流式合并、自动标题采纳、终态结算与持久化都在一个接口之后。聊天 controller 只保留 busy、API Key 门禁、keepAlive、stop/flush 转发与 ChatState 镜像。附件就绪与 stale 修补通过注入的 port 执行，现有补齐逻辑搬进该 port 的 adapter。依据 `spec.md` 的已定决策。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 发送消息端到端经新模块完成，Visible Path、Latest Reminder、标题采纳、stop、flush、上传失败与 stale `file_id` 重试行为不变
- [ ] 无 API Key 仍本地失败，不创建任何消息行
- [ ] 终态保存失败进入 ChatState 错误，同时已结算快照仍交给 UI
- [ ] 现有 chat controller 测试原样通过
- [ ] 新增 Reply Run seam 测试：发送成功、Rejected 不建行、保存失败、stop、flush、标题采纳、附件 port 调用时机
- [ ] `flutter analyze` 与 `flutter test` 通过
