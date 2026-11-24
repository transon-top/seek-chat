# 10: draft Release

**What to build:** tag 在 `main` 上且构建成功后，自动创建 draft GitHub Release，附三个 split APK、`SHA256SUMS` 与 git-cliff 初稿。不提供 universal APK；人工润色说明后手动 publish。

**Blocked by:** 08、09。

**Status:** ready-for-agent

- [ ] 仅当来源校验判定 tag 属于 `main`、且构建与测试成功时创建 draft；非 `main` 的 tag 不创建。
- [ ] draft 绑定对应 tag，资产包含三个 APK 与 `SHA256SUMS`（三个 APK 的 SHA-256）。
- [ ] Release body 用 git-cliff 初稿自动填充；发布前人工改写成中英双语、中文在前、每版 10 条以内、面向用户。
- [ ] 不生成 universal APK。
- [ ] 构建失败时不留任何半成品 Release。
- [ ] 重复运行同一 tag 的 workflow 不会失败（Release 已存在时更新或跳过），也不产生重复资产。
- [ ] 发布 job 独占 `contents: write`，构建 job 保持只读；Release 在人工 publish 前始终是 draft。
- [ ] 首次全流程（11）中验证：draft 出现、资产齐全、说明可润色，确认后才 publish。
