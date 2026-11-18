# Open Chat

Flutter 版 DeepSeek 聊天应用（iOS + Android）。规格与票在
`.scratch/flutter-deepseek-chat/`，领域术语见 `GLOSSARY.md`。

## 当前实现

- 应用壳与启动兜底：残留的 `pending`/`streaming` 回复置为 `stopped`。
- 数据层：drift 四表（`sessions`、`messages`、`attachments`、
  `message_attachments`），分支、版本切换、续写、附件引用与清理。
- API 客户端：请求构造、WHATWG SSE 解析、事件合并、错误分类、Key 校验、
  按请求取消。v1 固定模型 `deepseek-flash`。

聊天界面、附件上传、语音、导入导出等由后续票实现。

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
