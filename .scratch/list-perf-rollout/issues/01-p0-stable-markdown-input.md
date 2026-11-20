# P0 稳定 GptMarkdown 输入

Type: task
Status: resolved

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

## Answer

已落地。

改动（`lib/features/chat/markdown_view.dart`）：

- `sources` 为 null 或空列表时 `inlinePatterns` 传 null，不再为空来源新建 pattern。
- 引用角标 `InlinePattern` 按来源内容（`index` / `url` / `title`）缓存；内容签名变化时才重建，来源为空时清空，角标不会残留旧数据。
- `_MarkdownViewState` 按（已节流正文、来源签名、`streaming`、`style`、`dense`、`disableLinks`）缓存正文 widget；输入未变时返回同一实例，Flutter 以 identical 短路，`GptMarkdown` 子树不重建。
- 正文 `GptMarkdown` 补 `isStreaming: widget.streaming`；已完成消息为 false，跳过尾段扫描。表格内仍为 false。
- 调用点检查：正文传 `view.sources` 与 `reply.isInFlight`；思考与前言传 `streaming && isLast`；拒绝文本无来源且非流式，均正确。

测试：

- `test/features/chat/markdown_view_test.dart` 新增 3 项：空来源不装 pattern；输入不变复用 `GptMarkdown` 实例、来源内容变化后失效；`isStreaming` 随 `streaming` 传递。
- `flutter test test/features/chat test/dev/markdown_samples_test.dart`：135 项全绿；`dart analyze` 改动文件无问题。

复测（模拟器 `Medium_Phone_API_37.0`，`-gpu host`，profile，1 轮）：

```
flutter drive --profile -d emulator-5554 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/list_perf_test.dart
```

| 场景 | 本次 | 改造前基线（3 轮） |
| --- | --- | --- |
| 流式静止 build p50 / max | 0.18 / 0.41ms | 0.11–0.40 / 0.68–8.49ms |
| 流式 + 滚动慢帧占比 | 1.58% | 0.4–11.2% |
| 聊天列表滚动 1000 条慢帧占比 | 0% | 9.5–16.6% |
| 打开 1000 条消息首屏 | 1651ms（build max 1312.85ms） | 1966–5623ms |
| 抽屉首行 / 滚动慢帧 | 68ms / 1.78% | 106–247ms / 1.4–71.6% |
| 打开长会话后 RSS | 409.97MB | 341–430MB |

原始日志：`evidence/p0-simulator-r1.log`。

首屏仍有单帧 1.3s 构建，符合预期：那是《初始窗口》的目标，本票只收敛流式每 token 成本。

P1 判定按图门禁留到《初始窗口》落地后合并复测，本票不预判。
