# 11: 发版手册、保护与首次发布

**What to build:** 仓库内新增一份可直接照做的发版手册，完成 GitHub 侧的保护与权限设置，并按手册走完 `v1.0.0` 首次发布。发布按钮由用户执行。

**Blocked by:** 10。

**Status:** claimed

- [ ] 新增 `docs/runbooks/release.md`：前置检查（签名指纹、secrets、旧 tag 已清、测试 tag 已删）、在 `v1-dev` 最后一次提交把 `pubspec` bump 到 `1.0.0+1`、以 merge commit 合入 `main`、在 merge commit 打 `v1.0.0`、push tag、核对 draft、安装验证、publish、发布后验证、回滚与补丁发版。
- [ ] 手册写明失败处置：tag 与版本不一致、`+n` 未递增、签名材料缺失、draft 不出现。
- [ ] 手册提示：清空旧 tag 后 `v1.0.0` 的 git-cliff 初稿覆盖全部历史，需按 10 条以内人工精选；已装 debug 签名包需卸载后才能安装正式签名包。
- [ ] GitHub 设置完成：`main` 规则集禁止强推与删除；`refs/tags/v*` 规则集禁止更新与删除；`release` environment 只允许 `v*` tag；secrets 仅环境级；开启 immutable releases。
- [ ] 全部 workflow 的第三方 action 已固定完整 commit SHA，审计通过。
- [ ] 旧 tag `v0.3.0` / `v0.4.0` / `v0.5.0` 已清空（08 未完成则在此完成，需用户确认）。
- [ ] 按手册完成 `v1.0.0` 发布：Release 为 published，三个 APK 与 `SHA256SUMS` 可下载且校验一致，安装后签名与 07 记录的指纹一致。
- [ ] 发布后验证与回滚路径可执行，并已写入手册。
- [ ] `CLAUDE.md` 的构建与发版说明同步：release 构建需要签名材料，发版入口是 `main` 上的 `v*` tag。

## Comments

- 2026-11-25：新增 `docs/runbooks/release.md`，覆盖一次性准备（keystore、备份、
  恢复演练、environment/secrets、规则集、immutable releases）、版本号规则、完整发版
  checklist、失败处置、回滚与首次 v1.0.0 注意事项。`AGENTS.md`（`CLAUDE.md` 符号链接）
  已同步构建/发版命令与 CI 说明。workflow 的第三方 action 已全部固定 SHA。
- 核对：远端无任何 tag，旧 tag 清理项已满足。
- 2026-11-25：GitHub 侧已完成：`release` environment（仅 `v*` tag）、两个 secret、
  Actions 默认只读、immutable releases。规则集与分支保护在私有 Free 仓库不可用
  （API 403，需 GitHub Pro 或公开仓库）；已写入手册，公开后补上。
- 待办（用户执行）：仓库公开后配置 main / tag 规则集；测试 tag 演练；
  `v1.0.0` 发布与发布后验证。
