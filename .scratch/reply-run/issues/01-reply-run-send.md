# 01: Send 的 Reply 部分走 ReplyRun

**What to build:** 新建 ReplyRun 模块，只接管 assistant Reply 的执行。发送消息时，controller 仍负责 API Key、user message 写入、附件复制与落库、上传任务清理；随后把 `userMessageId` 交给 Run。Run 创建 Reply 行、构造请求上下文（Visible Path、Latest Reminder、prefix）、消费流、执行 stale 重试、结算并持久化，同时按现有规则采纳标题。附件 port 只负责请求前补齐 serverId 与流中失效修补，不拥有附件生命周期。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] send 端到端：controller 写入 user message 后，Reply 行、流式、终态与持久化全部经 Run
- [ ] Visible Path、Latest Reminder、标题采纳、stop、flush、保存失败行为不变
- [ ] 无 API Key 仍本地失败，不创建 user message 或 Reply
- [ ] 上传失败与 stale `file_id` 重试行为不变；附件 port 只在请求就绪与失效修补时被调用
- [ ] `ReplyRejected` 只表达 Reply 未创建/未发出；user message 是否提交仍由 controller 表达
- [ ] 现有 chat controller 测试原样通过；新增 Reply Run seam 测试
- [ ] `flutter analyze` 与 `flutter test` 通过
