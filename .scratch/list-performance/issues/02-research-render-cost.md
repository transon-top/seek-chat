# 每消息渲染成本与重建范围调研

Type: research
Status: resolved

## Question

在判断「列表是否适合虚拟滚动」之前，先量化每条消息的渲染成本来源与重建范围。必须回答：

1. `gpt_markdown` 1.4.1 内部的渲染与缓存路径：分段缓存、`SliverGptMarkdown` 的视口懒渲染机制、流式节流；对本项目「每条消息一个 `GptMarkdown`」意味着什么。
2. 重内容单项成本：mermaid（固定 320px `MermaidView`，`lib/features/chat/markdown_view.dart:394-425`）、LaTeX、表格（`IntrinsicColumnWidth` + 每格嵌套 `GptMarkdown`，`markdown_view.dart:240-299`）、`SelectionArea`、附件图片（`Image.file` 无 `cacheWidth`，`attachments_view.dart:356`）。哪些在滚动/流式时成本最高？
3. 重建范围：流式 token 到达时 `ChatPage` 整页重建（`lib/features/chat/chat_controller.dart:727-733`、`lib/features/chat/chat_page.dart:368-370`）对列表 item 的实际影响；`ScrollEdgeFade` 在每个 `ScrollMetricsNotification` `setState`（`lib/shared/widgets/scroll_edge_fade.dart:37-42`）的成本；会话列表 `sessionsProvider` 在 app 根被 watch（`lib/app/app.dart:171`、`session_drawer.dart:98`）导致的重建范围。
4. 卸载代价：消息 item 离开视口即销毁（无 keep-alive），思考块展开状态、编辑态、计时器（1s/2s Timer，`messages_view.dart:851`、`:1129`）随滚动销毁重建的成本与行为影响。
5. 官方与社区关于「ListView 内重内容」「单条消息内再嵌 Sliver」的性能建议。

事实以包源码（`~/.pub-cache`）、Flutter SDK 源码与官方文档为准，标注文件与行号。结论输出「成本排序 + 不换列表实现即可削减的成本」。

## Deliverable

研究笔记写入 `docs/research/render-cost.md`，提交到 `research/render-cost` 分支并推送，不合并（无 PR）。票内 Answer 给出一页纸摘要 + 分支提交链接。

## Answer

调研完成（2026-11-20）。完整笔记在 `research/render-cost` 分支：
`docs/research/render-cost.md`（commit `a0dd58f90ca1383eb28cc88528347d1b1e32cf03`，未合并）。
https://github.com/transon-top/seek-chat/blob/a0dd58f90ca1383eb28cc88528347d1b1e32cf03/docs/research/render-cost.md

**成本排序（按聊天页实际影响）**
1. **流式重解析**：每个 SSE 事件，视口 + cacheExtent 内所有带 `sources` 的助手正文整篇重解析、重渲染。原因链：`markdown_view.dart:144-146` 每次 build 新建 `InlinePattern` → `markdown_config.dart:1213-1218` 按实例身份比较 → `incremental.dart:247-249` 清空分段缓存 → `messages_view.dart:128-159` + `scroll_delegate.dart:580` 让所有活动 item 跟父级重建。即流式时不是只算尾段，而是全文 × 可见回答数。
2. **表格**：`IntrinsicColumnWidth` 每列每格 max/min 内在测量再真实布局（约 3×R×C 次单元格工作）；每格嵌套完整 `GptMarkdown`；`HorizontalFadeScroll` 常驻 `ShaderMask`（saveLayer 类开销）。`markdown_view.dart:240-299`、`table.dart:94-119, 1064-1100`。
3. **mermaid**：build 里同步解析布局，无 isolate、无跨实例缓存；忽略 `closed`，流式半成品每个更新窗口都重算，离屏回来再算。`markdown_view.dart:161-166, 394-425`、`mermaid_diagram.dart:28-34, 217-234`。
4. **`SelectionArea`**：每条消息至少 1 个（思考/前言/正文/拒答），对应多个 SelectableRegion/delegate/手势注册。
5. **LaTeX 与图片**：数学有全局 LRU 256，通常不是瓶颈；附件图片全分辨率解码进 ImageCache，属内存/GC 成本。

**不换列表实现即可削减**
- P0：稳定 `GptMarkdown` 输入——`sources.isEmpty` 时传 null；按来源内容缓存 `InlinePattern`；在 `MarkdownView` State 缓存 widget 实例，`_shown` 未变时让 Flutter 短路。预期每 token 成本从「所有可见回答全文」降为「流式回答尾段」。补传 `isStreaming: widget.streaming`，已完成消息跳过尾段扫描。
- P1：表格改固定/比例列宽、单元格不每格完整 `GptMarkdown`、无横向溢出时去掉 `ShaderMask`；mermaid 等围栏闭合后再渲染；附件加 `cacheWidth/cacheHeight`。
- P2：`ScrollEdgeFade` 合并指标通知只重建渐隐带；根级 `sessionsProvider` 改 `select` 当前 id；编辑/展开态提到小状态，不整条 keep-alive。

**风险**
- 缓存 `InlinePattern`/widget 后，来源变化而正文未变时可能显示旧引用角标，需显式失效。
- 固定表格列宽改变换行与横向滚动，需视觉验收；mermaid 延迟渲染失去边生成边预览。
- 不要把 sliver 塞进 `ListView` item，也不要用每条消息一个 shrinkWrap 的 `CustomScrollView`；全局 keep-alive 所有重消息是 CPU 换内存，低端机更糟。

**证据强度**：成本排序由源码与官方文档推导；毫秒级数字来自 `gpt_markdown` 官方测量，未在真机 profile 重跑。做架构决策前按笔记第 8 节在目标机型验证——交给基线测量票 03。
