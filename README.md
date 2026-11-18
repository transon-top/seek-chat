# Open Chat

Flutter 版 DeepSeek 聊天应用（iOS + Android）。规格与票在
`.scratch/flutter-deepseek-chat/`，架构见
`.scratch/flutter-deepseek-chat/architecture.md`，领域术语见 `GLOSSARY.md`。

## 当前实现

- 应用壳与启动兜底：残留的 `pending`/`streaming` 回复置为 `stopped`。
- 数据层：drift 四表（`sessions`、`messages`、`attachments`、
  `message_attachments`），分支、版本切换、续写、附件引用与清理。
- API 客户端：请求构造、WHATWG SSE 解析、事件合并、错误分类、Key 校验、
  按请求取消。v1 固定模型 `deepseek-flash`。
- 最小聊天闭环：会话列表（新建、重命名、删除）、聊天页（发送、流式、
  停止、重新生成、续写、自动标题）、设置页（API Key 校验与安全存储）。
- 回复渲染：`gpt_markdown` 渲染 Markdown、代码高亮与复制、链接外部打开；
  `val_latex_flutter` 渲染 `\(...\)` 与 `\[...\]`；`mermaid` 围栏由
  `mermaid_flutter` 绘制，解析失败降级为源码。

界面为临时最简实现；附件上传、语音、导入导出、双语与主题由后续票实现。

## 开发命令

```bash
flutter pub get
dart run build_runner build    # 修改 drift 表后重新生成 database.g.dart
flutter analyze
flutter test
flutter run
```

API 源默认 `https://api.deepseek.com`，可用
`--dart-define=OPEN_CHAT_API_ORIGIN=<origin>` 覆盖。
