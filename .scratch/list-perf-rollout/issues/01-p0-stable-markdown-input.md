# P0 稳定 GptMarkdown 输入

Type: task
Status: open

## Question（实施切片）

按 `decision.md` §4 P0 落地，让流式每个 token 的成本从「所有可见回答全文重解析」降为「流式回答尾段」。

- `sources.isEmpty` 时 `inlinePatterns` 传 null（现状只有 `sources == null` 时传 null，空列表仍新建 pattern）。
- 按来源内容缓存 `InlinePattern`；来源变化时显式失效，引用角标不得显示旧数据。
- 在 `MarkdownView` State 缓存 widget 实例；文本与来源都未变时不重建 `GptMarkdown`。
- 给正文 `GptMarkdown` 传 `isStreaming`（现状仅表格内传死 `false`），已完成消息跳过尾段扫描。
- 检查所有 `MarkdownView` 调用点，确认 sources 与 streaming 标记传递正确。

## 验收

- 新增测试：空来源不产生 pattern；来源变化使缓存失效；已完成消息 `isStreaming=false`。
- 现有 chat / markdown 相关测试全绿。
- 模拟器 1 轮复测：流式滚动窗口慢帧占比、打开长会话首屏；数字与命令回填票内 Answer。
- 一次提交到 `v1-dev`（scope `perf(list)`）。
