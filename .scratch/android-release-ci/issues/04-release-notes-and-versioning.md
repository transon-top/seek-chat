# 版本说明形态与版本号流程

Type: grilling
Status: resolved
Blocked by: 02

## Question

基于票 02 的调研，敲定版本说明与版本号流程：

1. 版本说明的生成方式：GitHub 自动 notes、仓库内 `CHANGELOG.md`、git-cliff 等工具，还是「自动 notes 初稿 + 手动润色」。
2. 版本说明的读者与语言：面向最终用户还是开发者；中文、英文或双语；分类与长度。
3. tag 命名与版本号来源：`vX.Y.Z` 与 `pubspec.yaml` 的 `x.y.z+n` 如何对应；是否恢复「tag 与 pubspec 版本一致」的 CI 校验（此前预留）。
4. 发版前版本 bump 由谁、在哪一步完成；是否允许直接以 tag 覆盖 `--build-name` / `--build-number` 而不改 `pubspec`。
5. 预发布（rc / beta）是否需要单独的 tag 规则与 Release 标记。
6. `v1-dev` → `main` 的合并与 tag 时机：PR、直接 merge 还是 fast-forward；tag 打在 `main` 的哪个提交上。
7. 公开仓库后的分支保护、tag 保护与 Release 权限；是否需要 draft Release（当前决定为自动 published，若调研有反例再改）。
8. `CHANGELOG.md` 是否保留；若保留，由人写还是工具生成。

产出一份决策：notes 来源与格式、版本号 / tag 流程、发布前检查清单、分支与 tag 保护。

## Answer

定案（2026-11-23，两轮拷问后逐项确认）。

1. **版本说明生成方式**：`git-cliff` 从 commit 生成初稿，发布前人工润色；Release body 与根目录 `CHANGELOG.md` 同源。emoji 前缀在 `cliff.toml` 加 `commit_preprocessors` 预处理（`^[^a-zA-Z]+` 替换为空），或新提交改用 `feat(chat): ✨ ...` 格式。
2. **读者与语言**：面向最终用户；中英双语，中文在前、英文在后；分类为 新增 / 修复 / 改进 / 破坏性变更；每版 10 条以内；技术细节只进 `CHANGELOG.md`，不进 Release body。
3. **tag 与版本一致性**：硬校验。tag `vX.Y.Z` 必须等于 `pubspec.yaml` 的 `x.y.z`，不一致在构建前失败。另校验 `+n` 严格大于上一个 `v*` tag 所指提交的 `pubspec.yaml` 的 `+n`（`git show <tag>:pubspec.yaml` 比对）。
4. **版本 bump 流程**：人工在 `v1-dev` 最后一步完成，同一次提交里改 `pubspec` 的 `x.y.z` 与 `+n`、更新 `CHANGELOG.md`；merge 到 `main` 后打 tag。首个正式版为 `1.0.0+1`。现有 tag（`v0.3.0`、`v0.4.0`、`v0.5.0`）全部清空，正式发布从 `v1.0.0` 起算；清 tag 属操作步骤，写入票 05 清单。
5. **预发布**：暂不引入 rc / beta。单人开发用 `v1-dev` 的 CI 构建自测；需要时再定 `vX.Y.Z-rc.N` 的 tag 规则、prerelease 标记与 `+n` 占用。
6. **合并与 tag 落点**：`v1-dev` → `main` 用 merge commit（不 squash、不 fast-forward）；tag 打在 `main` 的 merge commit 上，祖先校验兜底。
7. **保护与权限**：`main` 规则集（禁止 force push、禁止删除，不强制 PR）；`refs/tags/v*` 规则集（禁止更新、禁止删除）；`release` environment 只允许 `v*` tag，secrets 只存该 environment；workflow 默认 `contents: read`，仅 release job 用 `contents: write`。等第二贡献者出现再收紧 PR 流程。
8. **Release 形态与 CHANGELOG**：CI 创建 **draft** Release，附三个 split APK 与 git-cliff 初稿；人工润色 notes、下载验证 APK 后手动 publish。`CHANGELOG.md` 保留，由 git-cliff 本地生成、随 bump 提交。

核查事实（2026-11-23）：`pubspec` 当前 `0.5.0+1`；仓库无 `CHANGELOG.md`、`.github/`、`cliff.toml`；远端 `transon-top/seek-chat`。

留给票 05 实现：`+n` 递增校验步骤、生成物无 diff 校验、universal APK 取舍、workflow 并发 / 超时 / runner。
