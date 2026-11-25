# 06: 分支测试线：生成物无漂移 + 固定环境

**What to build:** 分支与 PR 的 CI 在固定 `ubuntu-24.04` 与 Flutter 3.50.0 上重跑 drift 与 l10n 代码生成；生成物与提交不一致立即失败。`flutter analyze` 与 `flutter test` 照旧执行。tag push 不再触发这条测试线，避免与发版线重复。

**Blocked by:** 无（可立即开始）。

**Status:** claimed

- [x] push 到任意分支与开 PR 都会触发；push tag 不触发。
- [x] runner 固定 `ubuntu-24.04`，Flutter 固定 3.50.0 stable，不再用 `ubuntu-latest` / 浮动版本。
- [x] 依次执行 `dart run build_runner build --delete-conflicting-outputs` 与 `flutter gen-l10n`，随后 `git diff --exit-code`；有 diff 时 job 失败并指出漂移文件。
- [x] `flutter analyze` 与 `flutter test` 继续执行；`integration_test` 不进 CI。
- [ ] 在干净 clone 上对当前 `main` 头提交整条 job 为绿。
- [x] 本次改动引入或触碰的第三方 action 固定完整 commit SHA。

## Comments

- 2026-11-25：`.github/workflows/ci.yml` 改为分支 push / PR 触发，`ubuntu-24.04` +
  Flutter 3.50.0；新增 `build_runner` + `gen-l10n` 重跑与 `git status` 漂移检查；
  `flutter analyze` / `flutter test` 保留；`integration_test` 不进 CI；两个 action
  固定完整 SHA。
- 待验证：推送分支后看 CI 为绿（本地无法替代 runner 环境）。
