# Spec: 本地推送前检查，云端只在发版触发

Status: resolved

## Problem Statement

维护者单人开发。分支一旦开了 PR，之后每次 push 都会以 `pull_request` 的 `synchronize` 事件触发 GitHub Actions，消耗 Actions 分钟，且与发版无关。维护者希望云端只在打 tag 发版时运行。

但现在的 CI 测试线（生成物漂移检查、`flutter analyze`、`flutter test`）本身有价值，直接删掉等于把唯一的检查点丢掉。维护者希望把这些检查挪到本地 `git push` 之前执行，作为第一道也是唯一的日常门禁。

## Solution

本地：用 lefthook 的 `pre-push` 钩子执行一条检查脚本，重跑代码生成并检查生成物漂移，再跑 `flutter analyze` 与 `flutter test`；任一失败阻止 push。

云端：删除 CI 工作流，只保留 `v*` tag 触发的发版工作流。发版工作流复用同一条检查脚本，保证本地与发版执行的检查一致。

新 clone 通过一次 `lefthook install` 启用钩子。紧急情况下 `git push --no-verify` 仍可绕过；这是已记录的取舍，不另加服务端强制。

## User Stories

1. 作为唯一维护者，我希望推送普通分支时 GitHub Actions 不运行，这样不消耗 Actions 分钟。
2. 作为唯一维护者，我希望只有推 `v*` tag 时才触发云端工作流，这样 Actions 只服务发版。
3. 作为维护者，我希望在 `git push` 前自动重跑 build_runner 与 gen-l10n，这样提交的生成物不会落后于源表与 ARB。
4. 作为维护者，我希望生成物落后时 push 被阻止并看到具体文件路径，这样我能立即重跑生成并提交。
5. 作为维护者，我希望漂移检查只关注生成物路径，这样工作区里无关的未提交改动不会导致误报。
6. 作为维护者，我希望 push 前自动跑 `flutter analyze`，这样静态错误不会进入远端。
7. 作为维护者，我希望 push 前自动跑 `flutter test`，这样失败的测试不会进入远端。
8. 作为维护者，我希望整套检查能用一个命令在本地复现，这样排查钩子问题时不必读钩子配置。
9. 作为维护者，我希望发版工作流执行与本地相同的检查脚本，这样"本地通过但发版失败"的分叉不会出现。
10. 作为维护者，我希望发版时仍检查生成物漂移，这样 tag 指向的提交本身是自洽的。
11. 作为维护者，我希望 lefthook 配置入库，这样换机器后只有安装与启用两步。
12. 作为新加入的协作者，我希望文档写清安装与启用钩子的命令，这样我能一次配置好。
13. 作为维护者，我希望钩子串行执行检查，这样 build_runner 与测试不会争抢构建产物。
14. 作为维护者，我希望检查失败时保留重新生成的产物，这样我能直接看 diff 决定提交还是还原。
15. 作为维护者，我希望紧急情况下能用 `git push --no-verify` 绕过，这样钩子故障不阻塞发版。
16. 作为维护者，我希望绕过钩子的风险被文档记录，这样将来恢复云端门禁时有据可依。
17. 作为维护者，我希望删除 CI 工作流后 CLAUDE.md 的常用命令同步更新，这样后续代理不会按旧流程操作。
18. 作为维护者，我希望发版 runbook 不再出现"开 PR 等 CI 为绿"，这样发布步骤与实际一致。
19. 作为维护者，我希望应用代码、数据库 schema、API 行为完全不变，这样本次改动没有运行时风险。
20. 作为维护者，我希望 lefthook 的最低版本要求写入文档，这样不同机器行为一致。
21. 作为维护者，我希望推 tag 时仍能在 Actions 看到唯一一次运行，这样发版仍可审计。
22. 作为维护者，我希望检查脚本的退出码语义明确（0 全过，非 0 在第一个失败步骤停止），这样我能脚本化调用。

## Implementation Decisions

### 云端

- 删除 CI 工作流（ci.yml）。不再有 `push: main`、`pull_request` 或 tag 触发的测试线。
- 保留发版工作流（release.yml），触发仍为 `v*` tag push；校验 tag、签名、构建 APK、draft Release 的 job 顺序与语义不变。
- 发版工作流中原本分开的"静态检查"与"测试"步骤合并为一步：调用本地检查脚本。脚本在干净 checkout 上行为等同于旧步骤，同时新增生成物漂移检查。
- 不新增 `workflow_dispatch`。发版演练仍以 tag 进行（runbook 已有流程）。

### 本地

- 新增 `lefthook.yml`：只定义 `pre-push`，`parallel: false`，命令为检查脚本。不定义 `pre-commit`。不做 format/fix 自动改写，避免钩子修改暂存区。
- 新增检查脚本 `tool/ci/local_checks.sh`，按顺序执行：
  1. `dart run build_runner build --delete-conflicting-outputs`
  2. `flutter gen-l10n`
  3. 生成物漂移判定：只取生成物白名单（drift 生成文件与 l10n 生成目录）的 `git status --porcelain`；有输出则打印 diff 并以非 0 退出。
  4. `flutter analyze`
  5. `flutter test`
- 漂移判定的基准是 git 跟踪状态，而不是工作区快照：源文件改了但生成物没有重新提交，重新生成后就会产生 diff，从而失败。工作区其他改动不参与判断。
- 失败时保留重新生成的产物，不自动 `git checkout`，由维护者查看 diff 后决定提交或还原。
- 脚本以 `set -euo pipefail` 语义运行，任一步失败立即退出，不吞输出。
- 脚本不执行 `flutter pub get`；依赖未安装时由 flutter/dart 自身报错。
- lefthook 通过 Homebrew 安装（`brew install lefthook`），`lefthook install` 写入 `.git/hooks`。最低版本要求在安装时验证并写入文档。
- 钩子可用 `git push --no-verify` 绕过；不加服务端强制。

### 文档

- CLAUDE.md：删除 CI 工作流的触发描述，加入 lefthook 安装/启用命令与检查脚本命令，注明云端只剩发版工作流。
- 发版 runbook：把"开 PR 等 CI 为绿"改为"推送前钩子通过或直接运行检查脚本"；"重跑 CI"一类表述改为"重跑发版工作流"。
- 不新增 ADR：这是流程调整，不改变应用架构。

### 保持

- 应用代码、依赖版本、数据库 schema、ARB 内容、生成物内容均不变；脚本跑完应无 diff。
- 第三方 action 固定完整 commit SHA、Flutter 固定 3.50.0 的策略不变。

## Testing Decisions

- 好测试只验证外部行为。这里的可观察行为是"脚本退出码 + 输出中列出的漂移文件路径"，不是脚本内部实现。
- 不新增 Dart 单测：钩子与脚本是薄胶水，核心检查由 `flutter analyze` 与 `flutter test` 自身覆盖；仓库现有 shell 脚本（版本校验）同样没有单测。
- 手动验收清单：
  1. 干净工作区执行检查脚本，退出 0。
  2. 在 ARB 增加一个 key 但不提交生成物，执行脚本，退出非 0 且输出指出 l10n 生成文件；验收后还原 ARB 与生成物。
  3. 工作区制造无关改动且不提交（例如改 `.vscode/settings.json`），执行脚本仍通过。
  4. `lefthook install` 后提交上述 ARB 改动并 `git push`，push 被阻止并显示脚本输出；确认 `git push --no-verify` 可绕过。
  5. 推送普通分支，GitHub Actions 无运行；推送 `v*` tag（或演练 tag），只有发版工作流运行。
- 发版工作流的改动无法在本地完整验证，验收以一次发版演练 tag 为准（runbook 已有流程）。
- Prior art：`tool/ci/check_release_version.sh` 由发版工作流调用，验证方式是本地运行加发版演练；新脚本沿用同一模式。

## Out of Scope

- `pre-commit` 钩子、`commit-msg` 校验、commitlint。
- format/lint 自动修复与自动暂存。
- 分支保护、required checks、PR 模板。
- 恢复任何云端测试线或做 CI 缓存优化。
- GitHub Actions 用量监控。
- Windows 本地开发支持（脚本按 macOS/Linux bash 编写）。
- 应用代码、现有测试内容、发版构建逻辑的改动。

## Further Notes

- 触发真相：截图中的分支触发来自 `pull_request` 事件的 `synchronize`，不是任意分支 push；删除 CI 工作流后两者都消失。
- 取舍：失去合并前的云端门禁。单人维护可接受；若未来有协作者，优先恢复 PR 触发的 analyze/test，或至少加 branch protection 与发版门禁。
- 调研结论：社区共识是 `pre-commit` 放秒级检查、`pre-push` 放测试；本次全部放 pre-push，与"提交要快、推送把关"一致。
- 与旧 CI 的差异：旧 CI 在干净 clone 上对整树 `git status` 判漂移；新脚本只对生成物路径判定，避免本地未提交改动误报。
- 风险：钩子未安装或被 `--no-verify` 跳过时，日常检查会完全缺位；发版工作流是最后一道门禁。
