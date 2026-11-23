import '../shared/models/types.dart';

/// ZH
/// Markdown 渲染样本：debug 构建写入一个测试会话，冒烟测试复用同一份数据。
///
/// user 文本只作类别标签；覆盖内容全部在 assistant 的回复块里。
///
/// EN
/// Markdown rendering samples: debug builds seed a test session; smoke tests reuse it.
///
/// User text only labels the category; all covered content lives in assistant reply blocks.
final class MarkdownSample {
  const MarkdownSample({
    required this.label,
    required this.prompt,
    required this.blocks,
    this.thinking = false,
  });

  final String label;
  final String prompt;
  final List<ReplyBlock> blocks;

  /// ZH
  /// 样本回复创建时是否打开深度思考，仅影响消息元数据。
  ///
  /// EN
  /// Whether the sample reply enables deep thinking; affects message metadata only.
  final bool thinking;
}

/// ZH
/// 超过 `MarkdownView.plainTextLimit`（200000）的正文，验证降级为纯文本。
///
/// EN
/// Body over `MarkdownView.plainTextLimit` (200000), verifying plain-text fallback.
String _longText() => '# 超长内容\n\n**不应解析**\n\n${'超长内容测试。' * 28573}';

final List<MarkdownSample> markdownSamples = [
  MarkdownSample(
    label: '标题与行内样式',
    prompt: '第 1 类：标题与行内样式',
    blocks: [
      const TextBlock(
        text: r'''# H1 一级标题
## H2 二级标题
### H3 三级标题
#### H4 四级标题
##### H5 五级标题
###### H6 六级标题

段落：**粗体**、*斜体*、***粗斜体***、~~删除线~~、`inline code`、转义 \*星号\*。

中文标点：「引号」、—— 破折号、…… 省略号，混排 English words 与表情 🙂🚀。

行尾两空格换行  
这是第二行；单个换行
这是紧接着的一行。''',
      ),
    ],
  ),
  MarkdownSample(
    label: '列表与任务',
    prompt: '第 2 类：列表与任务',
    blocks: [
      const TextBlock(
        text: r'''- 无序项
  - 嵌套无序项
    - 第三层
- [x] 已完成任务
- [ ] 未完成任务

1. 有序项
2. 第二项
   1. 嵌套有序
3. 第三项

- 列表项内的 **粗体** 与 `代码`''',
      ),
    ],
  ),
  MarkdownSample(
    label: '引用与分割线',
    prompt: '第 3 类：引用与分割线',
    blocks: [
      const TextBlock(
        text: r'''> 一层引用
> > 二层引用
>
> 引用内 **粗体** 与 [链接](https://example.com/quote)
>
> - 引用内列表

---

分割线上方的正文。''',
      ),
    ],
  ),
  MarkdownSample(
    label: '表格',
    prompt: '第 4 类：表格',
    blocks: [
      const TextBlock(
        text: r'''| 左对齐 | 居中 | 右对齐 |
|:-------|:----:|-------:|
| 苹果 | 🍎 | 3.50 |
| **粗体** | `code` | [链接](https://example.com) |
| 很长很长很长很长很长的单元格内容用来测试换行 | 短 | 1 |

列数不齐的表格：

| 列 A | 列 B |
|---|
| a | b | c |''',
      ),
    ],
  ),
  MarkdownSample(
    label: '代码块',
    prompt: '第 5 类：代码块',
    blocks: [
      const TextBlock(
        text: r'''```dart
Future<void> main() async {
  final reply = await client.stream('你好');
  print(reply);
}
```

```python
def fib(n: int) -> int:
    return n if n < 2 else fib(n - 1) + fib(n - 2)
```

```bash
flutter run -d ios --debug
```

```json
{"model": "deepseek-flash", "stream": true}
```

```
无语言围栏，保留缩进：
  两空格
    四空格
```''',
      ),
    ],
  ),
  MarkdownSample(
    label: '链接',
    prompt: '第 6 类：链接',
    blocks: [
      const TextBlock(
        text: r'''命名链接：[Open Chat](https://example.com/chat)

裸 URL：https://example.com/bare 与 www.example.com

邮箱：<mailto:test@example.com> 或 test@example.com

非法地址：[危险链接](javascript:alert(1)) 与 [无协议](example.com/no-scheme)

锚点：[跳转](#section)''',
      ),
    ],
  ),
  MarkdownSample(
    label: '图片',
    prompt: '第 7 类：图片（本应用渲染为可点链接）',
    blocks: [
      const TextBlock(
        text: r'''![示例图片](https://example.com/image.png)

![行内图片](https://example.com/inline.png) 夹在文字中间。

![无协议](example.com/pic.jpg "标题")

![相对路径](./assets/local.png)''',
      ),
    ],
  ),
  MarkdownSample(
    label: '数学公式',
    prompt: '第 8 类：数学公式',
    blocks: [
      const TextBlock(
        text: r'''行内公式 \(E = mc^2\) 与质能方程。

块级公式：

\[
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
\]

矩阵：

\[
\begin{pmatrix}
a & b \\
c & d
\end{pmatrix}
\]

美元符号不转公式：$100 与 $200，以及 $x^2$ 应保持原文。''',
      ),
    ],
  ),
  MarkdownSample(
    label: 'mermaid 图表',
    prompt: '第 9 类：mermaid 图表',
    blocks: [
      const TextBlock(
        text: r'''```mermaid
flowchart LR
  A[开始] --> B{判断}
  B -->|是| C[执行]
  B -->|否| D[结束]
```

```mermaid
sequenceDiagram
  participant U as 用户
  participant S as 服务端
  U->>S: 发送消息
  S-->>U: 流式返回
```

错误语法降级为源码：

```mermaid
not a valid diagram @@
```''',
      ),
    ],
  ),
  MarkdownSample(
    label: '引用角标',
    prompt: '第 10 类：引用角标（含无来源）',
    blocks: [
      const TextBlock(
        text: 'DeepSeek 发布了新的模型，公告见官方博客。',
        citations: [
          TextCitation(
            url: 'https://example.com/deepseek',
            title: 'DeepSeek 发布公告',
            citedText: 'DeepSeek 发布新的模型。',
            encryptedIndex: '',
          ),
        ],
      ),
      const TextBlock(text: '这一条引用了不存在的来源 [citation:9]，角标应整体消失。'),
    ],
  ),
  MarkdownSample(
    label: 'Alert 与原始 HTML',
    prompt: '第 11 类：Alert 与原始 HTML',
    blocks: [
      const TextBlock(
        text: r'''> [!NOTE]
> 这是一条提示。

> [!WARNING]
> 这是一条警告。

<div align="center">原始 HTML 不解析，应原样显示</div>

<span>行内 HTML</span> 与 <br> 标签，以及 &amp; 实体。''',
      ),
    ],
  ),
  MarkdownSample(
    label: '思考块',
    prompt: '第 12 类：思考块（小号字、链接只留文字）',
    thinking: true,
    blocks: [
      const ThinkingBlock(
        thinking: r'''用户想比较两个方案。我先列出**成本**与**维护负担**两个维度。

参考 [内部文档](https://example.com/doc)，思考内的链接只显示文字。''',
        signature: 'mock-signature',
        elapsedSeconds: 3,
      ),
      const TextBlock(
        text: r'''## 结论

- 方案 A **成本低**，维护简单
- 方案 B 功能多，但 `维护负担` 更重

推荐方案 A。''',
      ),
    ],
  ),
  MarkdownSample(
    label: '半截回复',
    prompt: '第 13 类：流式中途截断（未闭合表格、链接与围栏）',
    blocks: [
      const TextBlock(
        text: r'''这是流式输出中途被截断的半截回复。

见 [半截链接](https://example

| 列 A | 列 B |
|------|------|
| 1 | 2

```dart
void main() {
  final x = 1; // 围栏未闭合''',
      ),
    ],
  ),
];

/// ZH
/// 超长文本单独成会话：200000 字会占满滚动区，混进总样本会挡住其它类别。
///
/// EN
/// Long text gets its own session: 200000 chars fill the viewport and hide other samples.
final MarkdownSample longTextSample = MarkdownSample(
  label: '超长文本降级',
  prompt: '超长文本（>200000 字，应降级为纯文本）',
  blocks: [TextBlock(text: _longText())],
);
