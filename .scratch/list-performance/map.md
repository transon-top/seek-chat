# Map: 列表性能与虚拟滚动

## Destination

一份调研结论：Flutter 高性能列表/虚拟滚动方案清单，以及本项目聊天消息列表与历史会话列表是否适用虚拟滚动、选哪个方案（或保持现状 + 局部优化）的明确建议。实现不在本图内。

## Notes

- 范围：聊天消息列表（`lib/features/chat/messages_view.dart:128`，`ListView.builder`）与历史会话列表（`lib/features/sessions/session_drawer.dart:452`，`CustomScrollView` + `SliverList.builder`）。其他列表不在本图。
- 规模目标：单会话 1000 条消息内流畅、10000 条压力；会话列表 1000 个会话内流畅、10000 个压力。
- 验收标准：(1) 滚动稳定 60fps，无持续掉帧；(2) 打开长会话首屏可感知即开（约 <300ms）；(3) 流式输出期间滚动不阻塞。
- 约束：第三方包可评估，内置优先；第三方须过维护活跃度、包体积、与 Sticky Bottom（跟随底部，见 `GLOSSARY.md`）兼容三关。
- 跳转到指定历史消息不是硬指标（现状无此能力）。
- 允许结论超出「虚拟滚动」范畴：token 级重建隔离、图片 `cacheWidth`、`SliverGptMarkdown`、分页加载等。分页只写建议，不落地。
- 既有性能预算（`.scratch/flutter-deepseek-chat/map.md`）：单帧 ≤16.7ms、200 条消息流畅；本图在其上做专项加深。
- 事实基线（2026-11-20 探查）：聊天列表与会话列表均已懒构建；无分页，打开会话全量加载（`lib/shared/data/chat_repository.dart:134-162`）；每个流式 token 重建 `ChatPage` 与全部可见 item（`lib/features/chat/chat_controller.dart:727-733`、`lib/features/chat/chat_page.dart:368-370`）；每消息重内容为 `gpt_markdown` / mermaid / LaTeX / 表格；`gpt_markdown 1.4.1` 自带视口懒渲染 `SliverGptMarkdown` 但未用；无任何第三方列表包。
- 每个会话开始先读 `GLOSSARY.md` 与 `docs/agents/domain.md`；按需调用 grilling、domain-modeling、research。

## Decisions so far

<!-- 每个已关闭的票一行：票名 + 一句话结论。详细答案在票内。 -->

- [Flutter 虚拟滚动与高性能列表方案调研](issues/01-research-vscroll-options.md): 内置方案已够（`ListView.builder` 本身即虚拟化）；备选 `super_sliver_list` 0.4.1（维护停滞，仅在跳转/极端甩动需要时引入）；不选 `scrollable_positioned_list` / `flutter_list_view` / `two_dimensional_scrollables`。
- [每消息渲染成本与重建范围调研](issues/02-research-render-cost.md): 流式每个 SSE 事件会让所有可见助手正文整篇重解析（`InlinePattern` 每次 build 新建导致分段缓存失效）；P0 是稳定 `GptMarkdown` 输入 + 补 `isStreaming`；表格、mermaid、`SelectionArea`、图片为次要成本。

## Not yet specified

- 若选第三方列表包：迁移方案与回退策略（依赖决策票结论）
- 若结论建议分页：历史消息分页加载的数据层设计（依赖决策票结论）
- 重建隔离的落地切法：流式期间按消息拆分订阅（依赖决策票结论）

## Out of scope

- 落地实施改造（本图终点是结论）
- 其他列表：设置页、附件条、来源列表、Markdown 表格（范围只含消息列表与会话列表）
- API 请求上下文截断与服务端延迟优化（不影响列表渲染成本）
- 搜索结果定位 / 跳转到历史消息能力本身（未来功能，非本图）
