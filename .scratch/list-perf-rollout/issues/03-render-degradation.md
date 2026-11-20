# 渲染降级

Type: task
Status: resolved
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

## Answer

已落地。

改动：

- `lib/features/chat/markdown_view.dart`
  - mermaid 围栏只在 `closed` 时交给 `_MermaidBlock`；未闭合的围栏（流式半成品或截断输出）按普通代码块显示，闭合后当帧切换为图表。
  - mermaid 解析失败时整块换为代码块（`CodeField`，语言标签 `mermaid`）；出错回调在 build 中，延到帧后切换。不再用图表容器里的等宽纯文本降级。
  - 表格：`IntrinsicColumnWidth` + 每格嵌套 `GptMarkdown` 改为 `LayoutBuilder` 下的 `FixedColumnWidth`（可视宽度均分，每列至少 100；超出视口横向滚动）与纯 `Text` 单元格，对齐交给 `Text.textAlign`。包已把单元格解析为纯文本（`_plainText`），去掉逐格 `GptMarkdown` 文本内容不变，省掉每格一次完整 Markdown 解析与固有尺寸测量。
- `lib/shared/widgets/horizontal_fade_scroll.dart`：无横向溢出（`maxScrollExtent ≤ 0.5`）时不挂两层 `ShaderMask`；可滚动期间遮罩行为与 150ms 过渡不变。表宽固定为「视口宽均分」后，两列表格不再溢出，多数表格省掉遮罩。
- `lib/features/chat/attachments_view.dart`：草稿条与消息内缩略图按显示尺寸解码（`ResizeImage(width: 逻辑尺寸 × dpr, height: 同, policy: fit)`），避免全分辨率解码，`fit` 内切不拉伸、长截图解码内存有上限；全屏预览保持原图。

测试：

- `test/features/chat/markdown_view_test.dart` 新增 5 项：未闭合 mermaid 按代码渲染；闭合后切换为图表；表格单元格无嵌套 `GptMarkdown`；表格无溢出时不挂 `ShaderMask`；溢出时挂 2 层；mermaid 解析失败改为断言代码块降级。
- `test/shared/widgets/horizontal_fade_scroll_test.dart`：内容不足一屏改为断言无渐隐遮罩；`test/features/chat/attachments_view_test.dart` 新增缩略图 `ResizeImage`（192×192、`fit`）断言。
- 全量 `flutter test` 378 项全绿；`dart analyze` 改动文件无问题。

复测（模拟器 `Medium_Phone_API_37.0`，`-gpu host`，profile，1 轮）：

```
flutter drive --profile -d emulator-5554 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/list_perf_test.dart
```

| 场景 | 本轮 | 票 02 复测 | 改造前基线（3 轮） |
| --- | --- | --- | --- |
| 打开 1000 条消息首屏 | 345ms（build max 52.34ms） | 347ms（build max 95.56ms） | 1966–5623ms |
| 聊天列表滚动 1000 条慢帧 | 4.35%（build p90 0.64ms） | 9.52%（build max 6.29ms） | 9.5–16.6% |
| 流式 + 滚动慢帧占比 | 12.74%（build p90 0.98ms） | 8.19%（build max 2.9ms） | 0.4–11.2% |
| 流式静止慢帧 | 1.72% | 0% | — |
| 抽屉首行 / 滚动慢帧 | 147ms / 69.35% | 270ms / 55.6% | 106–247ms / 1.4–71.6% |
| 打开长会话后 RSS | 360.96MB | 365.98MB | 341–430MB |

读数注意：本轮模拟器光栅明显偏慢（空白对话对照慢帧 59.09%，raster p50 18.52ms），滚动慢帧以光栅为主，构建侧很便宜（列表滚动 build p90 0.64ms、流式滚动 build p90 0.98ms）。流式滚动慢帧高于上轮来自光栅（单帧 raster max 312ms），构建侧无回归。按图门禁本票不判 §7 阈值，真机 3 轮留给《总验收与收图》。

视觉验收（待用户确认）：

- `evidence/03-table-2col.png`：两列表格，列宽均分整行、行分隔线、无表头底色。
- `evidence/03-table-3col.png`：三列（左/中/右对齐）与长单元格换行。
- `evidence/03-mermaid.png`：闭合围栏渲染图表；未闭合围栏按代码显示由新增测试覆盖，截图为静态消息无法展示流式过程。
- `evidence/03-mermaid-fallback.png`：解析失败的 mermaid 改为代码块展示（按验收反馈调整）。
- 预期变化：表格单元格内容本就由包解析为纯文本，样式无额外变化；表格不再按内容收缩列宽，短表也会撑满可视宽度。
- 用户已确认（首轮反馈：解析失败的降级按代码块展示，已改）。
