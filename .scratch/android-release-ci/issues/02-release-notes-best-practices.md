# 版本说明与整套发版流程的最佳实践

Type: research
Status: resolved

## Question

单人开发的公开 Flutter Android 应用，发版时的版本说明（release notes）与整套发布流程，2026 年的最佳实践是什么？逐项给出官方或一手来源与核查日期；区分事实与建议。

背景：仓库当前私有、计划公开；`main` 为稳定线；提交信息已是 emoji + Conventional Commits 形式（如 `✨ feat(chat): ...`）；发布方式为 `main` 上打 `v*` tag，GitHub Actions 构建并创建 Release。

必须回答：

1. GitHub 原生自动生成 release notes：基于 PR 还是 commit？直接 push 到 `main` 的提交是否收录？`generate_release_notes` / `gh release create --generate-notes` 的用法；`.github/release.yml` 能配置什么（分类、排除、标签）。
2. Conventional Commits 规范；提交信息如何转成面向用户的版本说明；emoji 前缀的影响。
3. 工具对比（2026 年现状、维护状态、Flutter/Dart 适配）：git-cliff、release-please、semantic-release、standard-version、changesets。各自侵入性、配置成本、是否需要机器人 PR、与 tag / 版本 bump 的关系。
4. `CHANGELOG.md`（Keep a Changelog）与 GitHub Release notes 的取舍；公开仓库用户通常在哪里看变更。
5. 版本号策略：`pubspec` 的 `x.y.z+n`、tag `vX.Y.Z`、Android versionCode 的关系；单人项目使用 SemVer 的实用做法；预发布（rc）怎么打 tag。
6. 单人 + 公开仓库的发版流程最佳实践：功能分支 → `main` 的分支与 PR 方式、tag 保护、发布前检查清单、产物校验、发布后验证与回滚。
7. 版本说明内容最佳实践：面向用户还是开发者；分类（新功能 / 修复 / 破坏性变更）；中英双语；长度；链接；已知问题。
8. 公开仓库中的签名 secrets 安全实践：keystore base64、密码、最小权限、environment 审批。
9. 可选供应链实践：APK SHA256、Sigstore / SLSA、GitHub artifact attestations；对单人项目是否过度。
10. 给出「最小可持续方案」与「进阶方案」两档，说明理由与维护成本。

结论需明确推荐哪一种 notes 生成方式、版本号与 tag 流程，以及公开仓库下最少需要哪些保护措施。

## Answer

调研完成（2026-11-23）。完整结论见 `research/release-notes-best-practices` 分支：
`docs/research/release-notes-best-practices.md`（commit `948725af1a796d82e8b0cfba1f37384474f68fda`，未合并）。
https://github.com/transon-top/seek-chat/blob/948725af1a796d82e8b0cfba1f37384474f68fda/docs/research/release-notes-best-practices.md

关键结论：

- GitHub 原生自动 notes 基于**已合并的 PR**，不是 commit；直接 push 到 `main` 的提交不收录。当前功能分支 → `main` 一次合入的模型下，原生 notes 最多只有一条 release PR，不适合本项目。
- emoji 前缀有实际破坏：`conventional-commits-parser@7.0.0` 解析 `✨ feat(chat): ...` 得到 type/scope/subject 全为 null，`✨ feat!:` 连 breaking 都丢；`git-cliff 2.14.2` 默认跳过这类提交。加 `commit_preprocessors = [{ pattern = '^[^a-zA-Z]+', replace = '' }]` 恢复；新提交可改为 `feat(chat): ✨ ...`。
- 选 **git-cliff**：commit-based，与单人开发兼容。release-please 的 `dart` strategy 能自动 bump `+n`，但要求 PR-only、PAT 与额外权限；semantic-release 要 Node 与整套发布契约；changesets 面向 npm/monorepo；standard-version 已弃用。
- `CHANGELOG.md` 与 Release notes 同源生成：`git cliff --unreleased --tag vX.Y.Z --prepend CHANGELOG.md`，Release body 用同一份。
- 版本关系：`pubspec x.y.z+n` → `versionName=x.y.z`、`versionCode=+n`；tag `vX.Y.Z` 必须与 `x.y.z` 一致并由 CI 硬校验。split APK 实际 versionCode = ABI 编号 × 1000 + `+n`（arm32=1、arm64=2、x86_64=4）；`0.5.0+1` 的 arm64 APK 是 2001。每次发版 `+n` 必须递增；rc 用 `v0.6.0-rc.1` + `--prerelease`。
- 合并方式：功能分支用 squash；发布分支 → `main` 用 merge commit，不要 squash，否则 notes 失去明细。tag 只打 `main`。
- 签名 secrets：keystore base64 存 environment secret；`release` environment 限制 `v*` tag；顶层 `contents: read`，仅 release job `contents: write`；第三方 action pin 完整 SHA；开 2FA。
- 供应链：SHA256SUMS 必做；immutable releases 建议开（自带 Sigstore bundle attestation）；公开仓库 Free 可用 artifact attestations；自建 Cosign/SLSA 对单人过度。
- 最小可持续方案：git-cliff + emoji 预处理 + `CHANGELOG.md`；手动改 `pubspec` + tag + CI 校验；tag workflow 构建、SHA256、**draft** release；公开后加 `refs/tags/v*` 与 main 规则集；SHA256SUMS + immutable releases。每次发版约 5–10 分钟。
- 进阶方案（release-please + PR-only + 审批 + attestations）仅在第二贡献者、多发布渠道或高频发版时值得；当前不推荐。

未实测：未在 GitHub Actions 实跑；「直接 push 不收录」无官方明文，依据文档承诺 merged PR + 社区实证。
