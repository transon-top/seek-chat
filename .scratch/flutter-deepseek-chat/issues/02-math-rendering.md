# 数学公式渲染方案调研

Type: research
Status: resolved

## Question

Flutter 端渲染 LLM 输出中的数学公式，有哪些可用方案？重点评估：

- `flutter_math_fork`（及维护状态、继任者）
- `katex_flutter` / `flutter_katex` 等 KaTeX 相关包
- WebView + KaTeX（本地打包 KaTeX 资源）
- `gpt_markdown` 内置的数学支持
- 其他纯 Dart TeX 渲染器

必须回答：

1. 包 / 方案是否存在、版本、维护状态、许可证、平台支持。
2. 语法覆盖：分式、根式、上下标、矩阵、对齐环境、希腊字母、运算符、`\text{}`、`\begin{aligned}` 等常见 LLM 输出。
3. 流式容错：公式半截到达（如 `\frac{a}{`）时是否崩溃；能否保留上次成功渲染结果并降级显示原文。
4. 识别方式：`$...$`、`$$...$$`、`\(...\)`、`\[...\]` 的支持；与 Markdown 解析器的衔接点。
5. 渲染质量与一致性：与 KaTeX 的排版差异、字体（是否需额外字体资源）、深浅色主题。
6. 性能：首次加载、长公式、大量公式、滚动列表内的开销。
7. 交互：选中复制、无障碍；WebView 方案的通信与尺寸测量成本。
8. 风险与降级路径。

结论需给出「主选 + 备选 + 不选及理由」，并与 ticket 01 的 Markdown 库选型相互引用。

## Answer

调研完成（2026-11-18）。完整结论见 `research/math-rendering` 分支：
`docs/research/math-rendering.md`（commit `0e86989f2d59dc050bc2bf1d7d9019782fb7f842`，未合并）。
https://github.com/transon-top/open-chat/blob/0e86989f2d59dc050bc2bf1d7d9019782fb7f842/docs/research/math-rendering.md

**主选：`val_latex_flutter` 0.1.4**

- BSD-3、纯 Dart、全平台；`gpt_markdown` 1.4.1 的内置数学已是同一引擎，零额外接入。
- 唯一同时覆盖：流式半截公式可渲染、解析失败不抛异常、`align` / `gather` / `\ce`、选区复制、读屏、解析缓存。
- 代价：排版字体为 Latin Modern Math，与 KaTeX 视觉不同；字体数据约 2.1 MB 内嵌 + 0.7 MB OTF；0.1.x、单一厂商、Flutter 包无公开源码仓库。

**备选：`katex` 1.0.0 + `katex_dart` 0.1.1**

- 纯 Dart KaTeX 0.17 重写，MIT；但仍是 MVP，无选区 / 流式，需自建 hold-last-good。

**保真降级：WebView + KaTeX 0.16.22**

- 与 chat-demo 同版本、含 mhchem；仅按公式或像素级要求使用，不做全量渲染器。

**不选**

- `flutter_math_fork`：2025-05 后无发布，Flutter 3.29+ 因 `RenderObjectWithLayoutCallbackMixin` 被移除而构建失败，修复 PR 未合并。
- `katex_flutter`：2020 年停更，Dart `<3.0.0`，EUPL-1.2。
- `flutter_katex` / `latex_flutter` / `tex_flutter` / `flutter_math_plus` / `flutter_math_updated`：pub.dev 404。

**必须落到票 08 的决策**

1. 与 chat-demo 要「语义一致」还是「像素一致」；像素一致需换 WebView KaTeX。
2. 流式策略二选一：`streaming: true` 公式随流增长，或关闭并自建 hold-last-good。
3. `gpt_markdown` 默认 `useDollarSignsForLatex=false`，避免 `$5` 价格误判；是否启用单 `$` 需定。
4. 降级链：解析失败 → lastGood → 原文 → 单公式 WebView KaTeX。

**验收样例**：见研究文档第 10 节 15 条（含半截公式、价格误判、中文 `\text{}`、深色/大字号、100 条消息滚动）。
