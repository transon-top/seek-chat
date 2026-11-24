# 06: v1-dev 测试线：生成物无漂移 + 固定环境

**What to build:** 分支与 PR 的 CI 在固定 `ubuntu-24.04` 与 Flutter 3.50.0 上重跑 drift 与 l10n 代码生成；生成物与提交不一致立即失败。`flutter analyze` 与 `flutter test` 照旧执行。tag push 不再触发这条测试线，避免与发版线重复。

**Blocked by:** 无（可立即开始）。

**Status:** ready-for-agent

- [ ] push 到任意分支与开 PR 都会触发；push tag 不触发。
- [ ] runner 固定 `ubuntu-24.04`，Flutter 固定 3.50.0 stable，不再用 `ubuntu-latest` / 浮动版本。
- [ ] 依次执行 `dart run build_runner build --delete-conflicting-outputs` 与 `flutter gen-l10n`，随后 `git diff --exit-code`；有 diff 时 job 失败并指出漂移文件。
- [ ] `flutter analyze` 与 `flutter test` 继续执行；`integration_test` 不进 CI。
- [ ] 在干净 clone 上对当前 `v1-dev` 头提交整条 job 为绿。
- [ ] 本次改动引入或触碰的第三方 action 固定完整 commit SHA。
