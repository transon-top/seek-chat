# 09: git-cliff 生成 Release 说明（不落库 CHANGELOG）

**What to build:** 用 git-cliff 从 commit 生成面向用户的 Release 说明初稿。只服务 GitHub Release，不在仓库生成或提交 `CHANGELOG.md`。

**Blocked by:** 无（可立即开始）。

**Status:** resolved

- [x] 新增 `cliff.toml`，配置 emoji 前缀预处理，使 `✨ feat(chat): ...` 这类提交能解析出 type 与 scope，`!` 破坏性标记不丢失。
- [x] 分类为 新增 / 修复 / 改进 / 破坏性变更 四类；merge、chore 等噪音提交按需过滤。
- [x] 一条本地命令可生成指定 tag 的 Release 初稿；对当前历史实跑，分类与条目正确。
- [x] 初稿给出结构与技术条目，供人工改写成中英双语、中文在前、每版 10 条以内的最终说明。
- [x] 仓库不新增 `CHANGELOG.md`，发版流程不依赖仓库内 changelog 文件。

## Comments

- 2026-11-25：`cliff.toml` 落地。用 git-cliff 2.14.2 对当前历史跑
  `git cliff --config cliff.toml --unreleased --tag v1.0.0`，emoji 剥离、四类分组、
  merge/chore 过滤均正确；fixture 仓库验证了 `feat!:` 进入「破坏性变更」且不从
  「新增」重复出现。CI 用 `--current`（tag 已在 HEAD），本地预检用
  `--unreleased --tag`。命令与人工润色约定写入 `docs/runbooks/release.md`。

## Answer

`cliff.toml` 提供 emoji 前缀预处理（`^[^a-zA-Z]+` + 正文 emoji 清除）、
新增 / 修复 / 改进 / 破坏性变更四类分组、merge/chore 过滤；一条命令可生成指定
tag 的初稿，仓库不新增 `CHANGELOG.md`。最终说明仍由人工改写成中英双语、10 条以内。
