# 06: 启动失败规格归档

Status: ready-for-agent
Blocked by: 04, 05

## What to build

把已实现的启动行为收敛为权威规格，并清掉进行中的决策目录：

- 在 `docs/features/` 新增启动行为规格：启动顺序、阻塞与非阻塞失败、启动失败页形态与主题/语言来源、重试语义、清除本地数据的删除与保留范围、可访问性要求。
- 更新 `docs/features/README.md`：索引新增该规格，§3 删除「启动失败错误界面：未实现」，更新最后核对日期与适用版本（如适用）。
- 规格的「验证」列出覆盖测试文件。
- 删除 `.scratch/startup-failure/`。

## Acceptance criteria

- [ ] 新增启动行为规格，内容与实现一致，使用 `GLOSSARY.md` 术语。
- [ ] README 索引与 §3 已更新，最后核对日期更新。
- [ ] 规格列出验证测试文件名。
- [ ] `.scratch/startup-failure/` 已删除。
- [ ] `flutter analyze` 与全量 `flutter test` 通过。
