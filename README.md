# SeekChat

Flutter 版 DeepSeek 聊天应用（iOS + Android）。v1 固定模型 `deepseek-flash`，
API 源默认 `https://api.deepseek.com`，可用
`--dart-define=SEEK_CHAT_API_ORIGIN=<origin>` 覆盖。

已实现功能的行为规格见 [docs/features/](docs/features/README.md)；领域术语见
[GLOSSARY.md](GLOSSARY.md)，架构决策见 [docs/adr/](docs/adr/)。

## 功能文档

- 聊天：[回复](docs/features/chat/replies.md) ·
  [渲染](docs/features/chat/rendering.md) ·
  [联网搜索](docs/features/chat/web-search.md) ·
  [内容安全](docs/features/chat/safety.md)
- 输入：[输入区与附件](docs/features/input/composer-attachments.md) ·
  [按住说话与朗读](docs/features/input/speech.md)
- 会话：[会话抽屉](docs/features/sessions/session-drawer.md)
- 设置与数据：[设置与用户元信息](docs/features/settings/settings-metadata.md) ·
  [历史导入导出](docs/features/settings/history-archive.md)

未实现功能与进行中的决策记录在 `.scratch/<feature>/`。

## 开发命令

```bash
flutter pub get
dart run build_runner build    # 修改 drift 表后重新生成 database.g.dart
flutter gen-l10n               # 修改 lib/l10n/*.arb 后重新生成
flutter analyze
flutter test
flutter run
```

构建 Android APK：

```bash
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`。
