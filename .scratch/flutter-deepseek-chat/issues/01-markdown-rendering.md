# Markdown 渲染库方案调研

Type: research
Status: resolved

## Question

Flutter 端渲染 LLM 输出的 Markdown，有哪些可用方案？重点评估 `gpt_markdown`，并与 `flutter_markdown`（含维护状态与继任者）、`flutter_markdown_plus`、`markdown_widget`、`super_markdown`、`flutter_smooth_markdown`、`markdown_forge` 等对比。

必须回答：

1. 包是否存在、当前版本、发布者、最近更新时间、pub points / likes、许可证、支持平台。
2. 流式增量更新能力：文本逐段到达时能否低开销重渲染？是否支持稳定 key、局部更新、节流。
3. 块级覆盖：标题、段落、列表（含任务列表）、引用、表格、围栏代码 + 语法高亮、行内代码、链接、图片、粗斜体、删除线、水平线。
4. 数学公式：内置支持还是可插拔？inline `$...$` / `\(...\)`、block `$$...$$` / `\[...\]` 的识别方式；与 ticket 02 的渲染后端如何衔接。
5. Mermaid：是否内置或可注入自定义 fenced code 渲染器；与 ticket 03 如何衔接。
6. 交互：文本选中 / 复制、链接点击回调、图片加载与缓存、自定义 widget 嵌入。
7. 扩展性：自定义 AST 节点或 block renderer 的难度；源码结构是否清晰。
8. 风险：维护停滞、与 Flutter 新版本兼容、许可证限制、长文档性能。

结论需给出排序与推荐，明确「主选 + 备选 + 不选及理由」。所有事实以 pub.dev、GitHub 仓库、官方文档为准，注明来源与核查日期。

## Answer

调研完成（2026-11-18）。完整结论见 `research/markdown-rendering` 分支：
`docs/research/markdown-rendering.md`（commit `fb899688e392768f3e27d98ae7efcbeff5a90516`，未合并）。
https://github.com/transon-top/seek-chat/blob/fb899688e392768f3e27d98ae7efcbeff5a90516/docs/research/markdown-rendering.md

**主选：`gpt_markdown` 1.4.1**

- BSD-3；要求 Flutter >= 3.44 / Dart >= 3.12；1.4.0 有破坏性迁移。
- 包内分段缓存：只重建仍增长的尾段；长文档用 `SliverGptMarkdown`。
- 内置 LaTeX（含流式半成品）、57 种语言代码高亮、表格、任务列表、脚注、引用、GitHub Alerts。
- Mermaid 通过 `codeBuilder` 接入。

**备选：`flutter_markdown_plus` + `flutter_markdown_stream`（+ `flutter_markdown_plus_latex`）**

- 生态大、API 稳定；但流式、数学、高亮、Mermaid 均需外部拼装；围栏代码无内置高亮。

**不选**

- `flutter_markdown`：已停止、已下架。
- `markdown_widget`：19 个月无发布。
- `markdown_forge`：0.1.1，无流式，Mermaid 仅 2 类图。
- `super_markdown`：pub.dev 404，不存在。

**限制**

- 未编译、未真机 benchmark；性能数字来自维护者自测。
- 流式期间文本选择不稳定；父列表若每 token 重建所有气泡，包内缓存救不了。
- `mermaid_core` 在 pub.dev 标记 license unknown，但包内 LICENSE 为 MIT（票 03 已核实）。
