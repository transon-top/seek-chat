# 02: Regenerate 与 Edit 走 ReplyRun

**What to build:** 重新生成与编辑提问改经 Reply Run 模块。重新生成在同一 user Message 下创建新的 Reply 版本并选中；编辑创建一个新的 user Message 版本、复制附件引用并在同一事务里创建 pending Reply。两条路径的流式、标题与结算都由模块完成，controller 只做路由与状态镜像。

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] 重新生成产生新版本，旧 Reply 与其子树保留，并生成新的 Latest Reminder 快照
- [ ] 编辑产生同父的新提问版本与新 Reply，旧回答不进入请求上下文
- [ ] 空白编辑复用原附件，不丢附件引用
- [ ] stop、flush、标题采纳行为与现状一致
- [ ] 现有 controller 测试原样通过；新增 seam 测试覆盖编辑事务与重新生成的版本选中
- [ ] `flutter analyze` 与 `flutter test` 通过
