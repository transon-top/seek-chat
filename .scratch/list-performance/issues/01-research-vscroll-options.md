# Flutter 虚拟滚动与高性能列表方案调研

Type: research
Status: resolved

## Question

Flutter 中高性能列表/虚拟滚动的可选方案有哪些，各自边界在哪里？必须覆盖并对比：

1. Flutter 内置：`ListView.builder` / `SliverList.builder` / `SliverPrototypeExtentList`、`itemExtent` / `prototypeItem`、`cacheExtent`、`findChildIndexCallback`、`addRepaintBoundaries` / `addAutomaticKeepAlives`。回答：`ListView.builder` 本身是否已是虚拟化？变高 item 下它的已知限制（滚动条估算、跳转、内存、同时 laid-out 的 item 数量、尾部追加时的布局成本）。
2. 第三方包：`super_sliver_list`、`scrollable_positioned_list`、`flutter_list_view`、`two_dimensional_scrollables` 等。逐项：当前版本、发布者、最近更新、pub points / likes、许可证、支持平台、与 Flutter 3.50 / Dart 3.14 的兼容性。
3. 与聊天场景的匹配度：变高 item、流式内容持续增长、列表尾部追加、Sticky Bottom（贴底跟随）、从尾部向上滚动、视口外 item 的销毁/保留策略、是否支持跳转及跳转精度。
4. 与 Markdown 渲染的配合：`gpt_markdown` 的 `SliverGptMarkdown` 能否嵌入各方案；单条消息内部再虚拟化是否可行、是否值得。
5. 已知风险与失败案例（GitHub issues、长期未修复问题）。

所有事实以 Flutter 官方文档/源码、pub.dev、GitHub 仓库为准，标注核查日期。结论给出候选排序与「主选 / 备选 / 不选 + 理由」。

## Deliverable

研究笔记写入 `docs/research/vscroll-options.md`，提交到 `research/vscroll-options` 分支并推送，不合并（无 PR）。票内 Answer 给出一页纸摘要 + 分支提交链接。

## Answer

调研完成（2026-11-20）。完整笔记在 `research/vscroll-options` 分支：
`docs/research/vscroll-options.md`（commit `0e8c4c3bd142b310677c5bde22f63edf8cde949c`，未合并）。
https://github.com/transon-top/seek-chat/blob/0e8c4c3bd142b310677c5bde22f63edf8cde949c/docs/research/vscroll-options.md

**结论：内置方案够用，维持现状。**
- `ListView.builder` 本身已是虚拟化；3.50 冒烟场景 10000 条变高 item、600px 视口，首帧只构建约 12 条。会话列表同理由 `SliverList.builder` 承担。
- 变高 item 边界：`maxScrollExtent` 是推算值；冒烟实测一次 `jumpTo(maxScrollExtent)` 后 `max=84355`、实际 `pixels=78150`，未到底——现有 `_scheduleFollow()` 循环是必要补偿，不要删。
- 无「跳到第 N 项」API，`ensureVisible` 要求目标已构建；当前无此硬需求（见 map Notes）。
- 视口外 item 默认销毁；`AutomaticKeepAlives` 只有子项主动请求才生效。
- 前插历史消息会让索引后移，需补 `findChildIndexCallback`。

**备选：`super_sliver_list` 0.4.1**，仅在出现跳转需求或万级变高列表快速甩动明显不稳时引入。风险：2024-03-26 后无发布，issue #96 无人回复，另有 #83/#85/#88 未修；引入需锁版本并封装回退路径。

**不选**：`scrollable_positioned_list`（仓库 2024-08 归档，构建次数约 `ListView.builder` 2 倍，不能与其他 sliver 组合）；`flutter_list_view`（item 复用要求无状态，与有状态 Markdown 冲突；冒烟 `jumpToIndex(5000)` 后视口 0 个 Text）；`two_dimensional_scrollables`（二维表格，行高需预声明）；对消息使用 `itemExtent` / `prototypeItem` / `SliverPrototypeExtentList`（强制等长会裁切变高消息）。

**Markdown 配合**：`SliverGptMarkdown` 是 sliver，直接作为 `ListView` item 会抛 `RenderRepaintBoundary ... RenderSliverList`；单条消息内部再虚拟化不建议；现有流式节流（50ms–2s）与超 200000 字符退纯文本两道防线保留。

**版本事实（2026-11-20）**：`super_sliver_list` 0.4.1（MIT，301 likes）；`scrollable_positioned_list` 0.3.8（BSD-3，已归档）；`flutter_list_view` 1.1.29（MIT，发布者未验证）；`two_dimensional_scrollables` 0.5.6（BSD-3）。

未测：真实 Markdown 1000/10000 条滚动回看、真机帧耗时与内存、10000 条会话抽屉——交给基线测量票 03。
