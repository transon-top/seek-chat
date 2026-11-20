# 渲染降级

Type: task
Status: open
Blocked by: 02

## Question（实施切片）

按 `decision.md` §5 取三项降级：

1. mermaid 围栏闭合后才渲染，流式半成品不渲染。`codeBuilder` 已带 `closed` 参数（`lib/features/chat/markdown_view.dart`）。
2. 表格改固定 / 比例列宽；单元格不再每格嵌套完整 `GptMarkdown`；无横向溢出时去掉 `ShaderMask`。现状见 `_tableBuilder`（`defaultColumnWidth: IntrinsicColumnWidth`）。
3. 附件图片加 `cacheWidth` / `cacheHeight`（`lib/features/chat/attachments_view.dart`），避免全分辨率解码。

不取：`SliverGptMarkdown`、全局 keep-alive、LaTeX 改动。

## 验收

- 表格与 mermaid 的截图 / 预览交用户确认。预期变化：表格换行与横向滚动行为、流式中无图表预览。
- 相关现有测试全绿；能覆盖的逻辑（如 mermaid 闭合判定）补测试。
- 模拟器 1 轮复测滚动慢帧占比；数字回填票内。
- 一次提交。
