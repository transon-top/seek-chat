# 01: Current Session 状态与启动解析

**What to build:** 引入 SessionLifecycle 模块，接管「当前是哪个 Session」：启动时打开最近会话、新对话草稿、首次发送创建 Session、发送失败丢弃空会话、导入后重置。状态用 Draft / Open / Pending 表达，Pending 在会话列表出现该 id 后转为 Open。ChatHome 不再自己持有选择字段与 epoch，ChatPage 不再自己决定创建或丢弃。抽屉的置顶、重命名与删除本票不动。依据 `spec.md`。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 启动时列表首次就绪打开最近会话；列表为空保持草稿；已有显式选择不被覆盖
- [ ] 新对话不创建 Session 行；首次发送只创建一行，列表滞后期间页面不回落
- [ ] 发送失败丢弃刚创建的空会话与孤儿附件，回到草稿
- [ ] 导入后 generation 递增、回到草稿，ChatPage 以新 key 重建，旧草稿附件不保留
- [ ] 列表元数据变化但当前 id 不变时 ChatPage 不重建
- [ ] 现有 app 测试原样通过；新增模块状态迁移单测
- [ ] `flutter analyze` 与 `flutter test` 通过
