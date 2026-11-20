# 列表性能与虚拟滚动：方案决策

日期：2026-11-20

输入：票 01「Flutter 虚拟滚动与高性能列表方案调研」、票 02「每消息渲染成本与重建范围调研」、票 03「列表基线测量」。完整事实见各票 Answer 与 `evidence/baseline.md`。

终点：本文件是本图的最后产出。实施作为后续 effort，按第 8 节顺序推进；本图不含代码改动。

## 结论摘要

两个列表都保持 Flutter 内置实现，不引入第三方列表包。真正的成本不在列表实现，而在三处：打开长会话时跳底的一次性大构建、流式每个事件把所有可见助手正文整篇重解析、以及重内容渲染。对应决策：首屏改 UI 层初始窗口；流式先做「稳定 `GptMarkdown` 输入」P0；渲染降级只取 mermaid 闭合渲染、表格列宽与图片 `cacheWidth`。

## 1. 消息列表：保持 `ListView.builder`

**决定**：维持 `ListView.builder`（`lib/features/chat/messages_view.dart:128`），不引入 `super_sliver_list` 或其他第三方列表包。不采用 `itemExtent` / `prototypeItem` / `SliverPrototypeExtentList`，强制等长会裁切变高消息。

**理由**：

- `ListView.builder` 本身已是虚拟化：3.50 冒烟场景 10000 条变高 item、600px 视口，首帧只构建约 12 条。
- 滚动 build 很便宜（基线 build p90 0.71–0.93ms）；掉帧来自光栅化与重内容，换列表实现不解决。
- 唯一备选 `super_sliver_list` 0.4.1 自 2024-03-26 无发布，issue #96 无人回复，#83/#85/#88 未修。

**备选路径（不现在做）**：若未来出现「跳到第 N 条消息」需求，或万级变高列表快速甩动明显不稳，再引入 `super_sliver_list` 并锁版本、封装回退。`scrollable_positioned_list`（已归档）、`flutter_list_view`（与有状态 Markdown 冲突）、`two_dimensional_scrollables`（二维表格）不选。

## 2. 会话列表：保持 `SliverList.builder`

**决定**：维持 `CustomScrollView` + `SliverList.builder`（`lib/features/sessions/session_drawer.dart:452-488`），不与消息列表统一封装。两列表场景不同：会话列表是分组吸顶、行高固定；消息列表是变高、流式、跟随底部，统一只会多一层间接。

只做两项 P2：

1. 根级 `sessionsProvider`（`lib/app/app.dart:171`）改 `select` 当前 id，避免会话数据变化重建整页。
2. `ScrollEdgeFade`（`lib/shared/widgets/scroll_edge_fade.dart:37-42`）合并 `ScrollMetricsNotification`，只重建渐隐带。

10000 个会话未测；真机复测后若长尾仍明显，再单独起 effort。

## 3. 首屏定位：UI 层初始窗口

**决定**：打开会话时只渲染可见路径末尾的最近 50 条消息；用户向上滚动接近已渲染范围的起点时，每次向前补 40 条，直到全部消息进入渲染范围。窗口只扩不缩，重新打开会话时重置。保留现有非反向 `ListView.builder` 与 `_scheduleFollow()` 的 `jumpTo(maxScrollExtent)` 跟随逻辑。

**理由**：基线显示 1000 条消息首屏 1966–5623ms，其中单个 build 帧 1578–4461ms，成本就是跳底时一次性构建全部行。只构建 50 条后，同一帧成本按条目数下降；配合第 4 节的 P0，目标 <300ms 可达。消息已在内存（`chat_repository.loadConversation` 全量返回），本决策不改数据层。

**为何不选 `reverse: true`**：反向列表底部即 offset 0，确实免跳转，但会破坏 Sticky Bottom 的「内容不足一屏时从视口顶部开始」（`GLOSSARY.md`），需要额外布局补偿；且历史消息插入方向、顶部渐隐与边距都要翻转。初始窗口不改变定位语义，风险小。

**与分页加载的区别**：初始窗口只影响渲染范围，不改变消息的可见路径与请求上下文；数据层仍一次读取。

**实现注意**（交给后续 effort）：

- 前插历史时补 `findChildIndexCallback`，否则按键值复用会错位。
- 顶部补历史后按插入高度补偿滚动位置，避免视口跳动。
- 版本切换或编辑导致消息数变化时，重新计算窗口以保证当前视口消息仍在范围内。

## 4. 流式重建隔离

**决定**：分两步。

- **P0（必做）**：稳定 `GptMarkdown` 输入——`sources.isEmpty` 时传 null；按来源内容缓存 `InlinePattern`；在 `MarkdownView` State 缓存 widget 实例；补传 `isStreaming`，已完成消息跳过尾段扫描。目标：每 token 成本从「所有可见回答全文」降为「流式回答尾段」。
- **P1（先测后拆）**：P0 落地并复测后仍不达标，再用 Riverpod `select` 把每条消息的订阅收窄到自身，`ChatPage` 只 select 会话级字段。不为每条消息建独立 provider。

**风险**：缓存 `InlinePattern` / widget 后，来源变化而正文未变时可能显示旧引用角标，需要显式失效路径。

## 5. 渲染降级

**取**：

1. mermaid 等围栏闭合后再渲染，流式半成品不渲染。代价：失去边生成边预览。
2. 表格改固定/比例列宽、单元格不每格嵌套完整 `GptMarkdown`、无横向溢出时去掉 `ShaderMask`。需视觉验收。
3. 附件图片加 `cacheWidth` / `cacheHeight`，避免全分辨率解码。

**不取**：

- `SliverGptMarkdown`：它是 sliver，直接作为 `ListView` item 会抛 `RenderRepaintBoundary ... RenderSliverList`；为它把整列表改成 `CustomScrollView` 收益不抵成本。
- 全局 keep-alive 滚动项：CPU 换内存，低端机更糟。
- LaTeX：已有全局 LRU 256，不动。

## 6. 分页加载（仅建议，不落地）

数据层分页不进本次实施范围。触发条件：真机在 10000 条消息场景下打开耗时或内存超出第 7 节口径。触发时要点：

- 按可见路径从末尾倒序分页查询消息，与 `selectedChildId` 版本链保持一致。
- 请求上下文仍需要完整可见路径，分页只影响读取与渲染，不改发送逻辑。
- 与初始窗口的关系：窗口先落地；若窗口不足再升级为数据层分页。

## 7. 验收口径与风险

| 验收标准 | 口径 | 改造前基线（模拟器，仅相对参考） |
| --- | --- | --- |
| 滚动稳定 60fps | 1000 条消息滚动窗口，合计 >16.7ms 的帧占比 <5%，无持续长帧 | 9.5–16.6% |
| 打开首屏可感知即开 | 打开 1000 条消息的会话，最后一条消息进入树 <300ms | 1966–5623ms |
| 流式期间滚动不阻塞 | mock 流式窗口内滚动慢帧占比 ≤10%，无可感知卡顿 | 0.4–11.2% |
| 会话列表 | 1000 会话抽屉首行可见 <300ms；滚动无持续掉帧 | 106–247ms；慢帧 1.4–71.6% 波动大 |
| 内存 | 打开长会话后 RSS 不劣于改造前基线 | 341–430MB |

所有验收以真机 profile 复测为准；模拟器数值只看相对关系。基线测量方法见 `evidence/baseline.md`。

**风险清单**：

- 初始窗口：顶部补历史时滚动锚点跳动；前插错位需 `findChildIndexCallback`；版本切换/编辑改变消息数时窗口失效。
- mermaid 延迟渲染：流式中不再有图表预览，用户感知变化。
- 表格列宽：换行与横向滚动行为改变，需视觉验收。
- `GptMarkdown` 缓存：引用角标可能过期，需显式失效。
- 首屏 50 条窗口内含重内容时，<300ms 仍可能不达标；P0 与渲染降级需先于或同步于窗口落地。
- 10000 条消息与 10000 个会话的压力场景未测，结论不覆盖。
- 未选第三方列表包；若未来需要跳转能力，`super_sliver_list` 维护停滞是引入风险。

## 8. 实施顺序（后续 effort 的输入）

1. **P0 输入稳定**：`sources.isEmpty` 传 null、缓存 `InlinePattern`、补 `isStreaming`。风险低、收益最大。落地后复测流式与首屏。
2. **初始窗口**：最后 50 条起步、向上每次补 40 条、`findChildIndexCallback`、滚动锚点补偿。落地后复测首屏。
3. **渲染降级**：图片 `cacheWidth` / `cacheHeight`、mermaid 闭合后渲染、表格列宽与 `ShaderMask`。
4. **P1 重建收窄**：仅当第 1、2 步复测仍不达标再投入，用 `select` 收窄。
5. **会话列表 P2**：`sessionsProvider` select、`ScrollEdgeFade` 局部重建。

每一步后按第 7 节口径复测；数字以真机 profile 为准。

## 不做清单

- 不引入第三方列表包。
- 不改 `reverse: true`。
- 不用 `SliverGptMarkdown`。
- 不做全局 keep-alive。
- 不在本次做数据层分页。
- 不动 LaTeX 缓存。
- 不做项目外的列表（设置页、附件条、来源列表、Markdown 表格）。
