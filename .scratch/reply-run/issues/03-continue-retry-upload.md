# 03: Continue 与 RetryUpload 走 ReplyRun

**What to build:** 续写与附件重试改经 ReplyRun。续写不新建 Reply 行，Run 调用 continuation 开始逻辑并保留原 prefix、thinking、search 与 Latest Reminder 快照；附件重试同样复用原行，但默认重新生成 Latest Reminder 快照且不带 assistant prefix。stale 附件修补经注入的 port 执行，重试条件由 Run 判断。

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] 续写复用同一 Reply 行并追加块，prefix 与快照不丢
- [ ] 附件重试复用同一行、无 prefix、按现有规则重新生成快照
- [ ] stale 附件只在收到内容块前重试，最多两次，退避与终止条件不变
- [ ] 两条意图均不产生重复 Reply 行
- [ ] 现有 continuation 与 retry 测试原样通过；新增 seam 测试覆盖两条路径的请求差异
- [ ] `flutter analyze` 与 `flutter test` 通过
