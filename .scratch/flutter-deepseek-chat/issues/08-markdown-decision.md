# Markdown / 数学 / Mermaid 方案锁定

Type: grilling
Status: resolved
Blocked by: 01, 02, 03

## Question

基于 01 / 02 / 03 的调研结论，锁定渲染栈：

1. 主 Markdown 库与备选；版本锁定。
2. 数学：渲染后端（纯 Dart / WebView + KaTeX / 混合）、识别语法、流式半截公式的容错与「保留上次成功结果」策略。
3. Mermaid：采用哪个包（若用户清单含不存在的包，明确纠正）；若纯 Dart 方案不可用，WebView + mermaid.js 的降级方案与成本。
4. 代码高亮：库选型（如 flutter_highlight / re_highlight / highlight）与主题。
5. 渲染管线：流式节流频率、AST 缓存、局部重绘、稳定 key；长会话性能预算。
6. 交互：选区复制、代码块复制、链接打开、图片缓存。
7. 降级策略：解析失败、超大文档、未知语法。

产出：`markdown.md` 章节，含选型结论、依赖版本、管线图、验收样例（含数学与 Mermaid 的典型 LLM 输出）。

## Comments

2026-11-18 实现记录：聊天页文本块已接入 `MarkdownView`（`lib/ui/markdown_view.dart`），本票保持 open。

- 依赖：`gpt_markdown` 1.4.1、`val_latex_flutter` 0.1.4、`mermaid_flutter` 0.3.2 + `mermaid_core` 0.3.2、`url_launcher` 6.3.3。
- 数学只启用 `\(...\)` / `\[...\]`，`useDollarSignsForLatex: false`，避免 `$5` 误判。
- Mermaid 使用固定 320 高度的 `MermaidView`（缩放、平移、全屏）；流式失败保留上次成功场景，无成功场景时降级为源码文本。
- 链接仅打开 `http` / `https`。
- 仍未定：流式节流频率、长会话性能预算、图片缓存策略、超大文档降级。

## Answer

决策完成（2026-11-18），详见 [`markdown.md`](../markdown.md)。

- **Markdown**：`gpt_markdown` 1.4.1 主选，`flutter_markdown_plus` +
  `flutter_markdown_stream` 备选；caret 声明，`pubspec.lock` 锁实际版本。
- **数学**：`val_latex_flutter` 0.1.4（`gpt_markdown` 内置）；只认
  `\(...\)` / `\[...\]`，单 `$` 关闭；语义与 chat-demo 一致，不做像素一致；
  v1 不实现单公式 WebView 兜底。
- **Mermaid**：`mermaid_flutter` + `mermaid_core` 0.3.2，`codeBuilder` 接入；
  固定 320 高，平移/缩放/全屏；`keepLastGoodSceneOnError` + 源码降级。
- **代码高亮**：复用 `gpt_markdown` 内置 `val_highlight` / `CodeField`，
  不新增依赖；深浅色随主题。
- **管线**：流式按「上次帧耗时 × 2」节流，限制 50 ms–2 s，窗口内合并；
  包内增量分段缓存；消息列表按 id 建 `ValueKey`；流结束立即显示全文。
- **交互**：`SelectionArea` 选区复制；`CodeField` 复制按钮；链接仅
  http(s) 外部打开；Markdown 图片按 chat-demo 转成链接，不加载、无图片缓存。
- **降级**：半截公式不崩溃、Mermaid 保留上次成功场景、未知围栏纯文本、
  单块超 200000 字符转纯文本。
- **验收**：`test/ui/markdown_view_test.dart` 覆盖 12 条样例，全部通过。
- **未验证**：真机性能预算、`mermaid_*` 0.3.x API 稳定性、数学与 KaTeX
  的视觉差异。性能预算只有目标值，未做真机基准。
