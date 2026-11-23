# 会话抽屉：搜索、置顶与多选

Type: task
Status: resolved

## Question

按 [`spec.md`](../spec.md) 实现会话抽屉改造：

1. **抽屉头**：删除 `Fleepseek` 文字标、右上收起按钮、「开启新对话」胶囊；
   顶部改常驻搜索入口。关闭只靠左滑、点对话区、系统返回。
2. **搜索**：点击搜索入口后侧栏向右展开到全屏、对话层完全移出，搜索页自动聚焦；
   匹配会话标题与消息正文；250ms 防抖；防抖与查询期间显示搜索骨架；
   结果行 = 圆形会话图标 + 标题 + 相对时间 + 单行片段，按 `updatedAt` 倒序；
   清除按钮、返回、空白态与无结果态按规格；点结果关闭抽屉并打开会话。
3. **骨架**：首次加载与搜索加载共用 6 行静态骨架，删除现有进度条。
4. **长按菜单**：去掉行尾三点；长按弹 `重命名 / 置顶或取消置顶 / 多选 / 删除`，
   锚定该行，轻震动，读屏暴露「会话操作」长按动作。
5. **多选模式**：叠在列表第一行分组头右侧的「多选」图标与长按菜单「多选」两个入口；
   标题替换为「选择对话 / 已选择 N 个对话」+ X；行内圆形勾选；
   底部「置顶 | 删除」操作栏；0 选中禁用；批量操作完成退出；
   与搜索互斥。
6. **置顶**：`sessions.pinned` 列 + 「置顶」分组，组内按 `updatedAt` 倒序；
   置顶不改 `updatedAt`；批量按钮按选中状态切换「置顶 / 取消置顶」。
7. **批量删除**：确认「删除 N 个对话」；先取消流，再逐个删库与回收孤儿附件；
   当前会话被删时切到剩余最近会话，全删回空聊天。
8. **数据**：`schemaVersion` 1 → 2，显式 `onUpgrade`；`Session` /
   `SessionSummary` 增加 `pinned`；归档导出会话文件与索引写真实 `pinned`，
   导入读会话文件 `pinned`，缺失按 `false`；归档格式版本保持 3。
9. **文案**：新增 ARB key 见 `spec.md` §8，中英同步。

预期落点：

- `lib/shared/data/database.dart`（+ 重新生成 `database.g.dart`）
- `lib/shared/models/types.dart`
- `lib/shared/data/chat_repository.dart`
- `lib/features/sessions/session_drawer.dart`
- `lib/features/sessions/session_search_page.dart`（新）
- `lib/features/history/history_zip.dart`
- `lib/app/app.dart`（`SessionDrawer` 去掉 `onNewChat`）
- `lib/l10n/app_en.arb`、`lib/l10n/app_zh.arb`（+ `flutter gen-l10n`）
- `test/features/sessions/session_drawer_test.dart`、
  `test/features/sessions/session_search_page_test.dart`、`test/features/history/*`、
  `test/shared/data/*`、`test/dev/mock_seed_test.dart`

## 验收

- `flutter analyze` 无问题。
- `flutter test` 全绿，至少覆盖 `spec.md` §9 的自动化项。
- 双主题、中英文、字号 0.8–2.0 手动检查搜索页、骨架、长按菜单、勾选、底部操作栏。
- 300 条以上会话（`SEEK_CHAT_STRESS_SEED=true`）下搜索无明显卡顿。
- 导出 → 导入后置顶状态保持；导入旧归档时全部未置顶。

## Answer

已实现（2026-11-21）。

- 数据：`sessions.pinned`、`schemaVersion 2`（`onUpgrade` 加列）、
  `Session` / `SessionSummary` 增加 `pinned`；归档导出与导入读写 `pinned`。
- 搜索：`ChatRepository.searchSessions()` 匹配标题、用户正文与 assistant 文本块，
  转义 `%`/`_`/`\`，返回 `SessionSearchHit`；片段按前 18 / 后 60 字截取。
  assistant 正文从 `blocks` 解析，思考块与工具块不参与匹配。
- 界面：抽屉头部换搜索入口；多选图标叠在第一行分组头右侧；点击搜索后抽屉
  向右展开到全屏、对话层完全移出；
  `SessionSearchPage`（自动聚焦、清除、骨架、
  无结果虚线放大镜、相对时间）；长按操作卡；多选标题、勾选、底部置顶 / 删除栏；
  进入 / 退出多选时搜索入口与标题淡入淡出、勾选圈槽位 0 ↔ 32 带动行文字横移；
  置顶分组。
- 返回：`PushMenuController.backHandler` 让搜索先收键盘再收回、多选先退出、
  最后才关抽屉；抽屉收起时自动退出多选与搜索。
- 测试：`chat_repository_test`（置顶、搜索、转义、片段）、
  `session_drawer_test`（置顶分组、长按、多选、批量删除、系统返回、搜索页往返）、
  `session_search_page_test`（骨架、命中、无结果、清除）、
  `history_service_test`（`pinned` 归档往返）。

验证：`flutter analyze` 无问题；`flutter test` 420 项全绿。

## Comments
