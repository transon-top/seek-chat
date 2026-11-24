# 02: 删除命令与抽屉 adapter

**What to build:** 把单删/批删收进 SessionLifecycle 的领域命令。抽屉只保留多选、确认框与列表 UI，调用删除命令而不再直接删除 repository 行。删除顺序为：停掉该 Session 的活动回复 → 删除行 → 删除孤儿附件文件 → 更新当前选择；删除当前后打开剩余最近会话，无剩余回草稿。置顶与重命名本票不动，继续留在抽屉 + repository。

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] 单删/批删：删除前停掉活动回复；行与孤儿附件删除；当前选择按规则回落
- [ ] 删除非当前 Session 不改变选择
- [ ] 批量删除维持现状：repository 异常中断后续删除（隔离修复见票 04）
- [ ] 命令失败时选择状态不变，异常交给 UI 用现有 toast 提示
- [ ] 附件文件删除失败只记录日志，不阻塞
- [ ] 置顶/重命名行为不变，仍由抽屉直接调用 repository
- [ ] 现有抽屉测试原样通过；新增命令单测覆盖 stop 顺序、回落与失败不变
- [ ] `flutter analyze` 与 `flutter test` 通过
