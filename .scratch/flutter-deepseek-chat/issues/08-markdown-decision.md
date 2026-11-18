# Markdown / 数学 / Mermaid 方案锁定

Type: grilling
Status: open
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
