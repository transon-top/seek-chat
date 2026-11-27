# SeekChat

[中文](#中文) · [English](#english)

---

## 中文

Flutter 版 DeepSeek 聊天应用，支持 iOS 与 Android。v1 固定模型
`deepseek-flash`，API 源默认 `https://api.deepseek.com`，可用
`--dart-define=SEEK_CHAT_API_ORIGIN=<origin>` 覆盖。

### 功能

- **聊天**：流式回复、停止、重新生成、编辑提问、续写、多版本分支切换、自动标题
- **渲染**：Markdown、代码高亮与复制、数学公式、Mermaid 图表、链接与图片
- **联网搜索与深度思考**：独立开关、工具时间线、引用角标、网页来源抽屉
- **输入区**：照片与文件附件（图片、PDF、Word、PPT 等，按扩展名白名单）、
  草稿附件、上传状态
- **语音**：按住说话输入、朗读回答、音色选择
- **会话抽屉**：时间分组、搜索、置顶、重命名、多选批量置顶与删除
- **设置**：主题、字体大小、语言（中文 / English）、所在地、朗读音色、API Key
- **数据**：API Key 仅存安全存储；本地 drift/SQLite 持久化；历史 ZIP 导入导出

### 环境要求

- Flutter 3.50.0（与发版工作流一致）
- Dart SDK `^3.14.0`

### 快速开始

```bash
flutter pub get
flutter run
```

启动后进入设置填入 API Key。Debug 构建会自动写入 Markdown 与历史样本；
`--dart-define=SEEK_CHAT_STRESS_SEED=true` 额外写入 1000 会话压测数据。

### 开发命令

```bash
dart run build_runner build --delete-conflicting-outputs   # 改 drift 表后重新生成
flutter gen-l10n                                           # 改 ARB 后重新生成
flutter analyze
flutter test                                               # 全量
flutter test test/shared/api/sse_parser_test.dart          # 单文件
```

生成物（`database.g.dart`、`lib/l10n/generated/`）入库，不在 `.gitignore`。

### 构建 Android APK

```bash
./tool/build_android_apk.sh
# 产物：build/app/outputs/flutter-apk/SeekChat-{arm64-v8a,armeabi-v7a,x86_64}-release.apk
```

release 需要 `android/key.properties` 与正式 keystore，缺失时立即失败。

### 发版

在 `main` 上打 `v*` tag 触发 GitHub Actions：校验版本、签名构建、创建 draft
Release。本地预检：

```bash
./tool/ci/check_release_version.sh v1.1.0
```

### 本地检查与钩子

```bash
./tool/ci/local_checks.sh        # 生成物漂移 + analyze + test
brew install lefthook            # 每台机器一次
./tool/ci/install_git_hooks.sh   # 安装 pre-push 钩子
```

### 项目结构

- 分层：`lib/main.dart → lib/app → features → shared`，只有被两个以上功能复用的代码进 `shared/`
- 功能目录：`features/chat`（含 `chat/speech`）、`sessions`、`history`、`settings`
- 状态管理：`flutter_riverpod`，手写 Provider
- 数据：drift 四表 `sessions` / `messages` / `attachments` / `message_attachments`
- 路由：`go_router`

### 文档

- [已实现功能的行为规格](docs/features/README.md)（权威）
- [领域术语](GLOSSARY.md)
- [架构决策记录](docs/adr/)
- 未实现与进行中的决策记录在本地 `.scratch/<feature>/`（不入库）

---

## English

A Flutter DeepSeek chat client for iOS and Android. v1 uses the fixed model
`deepseek-flash`; the API origin defaults to `https://api.deepseek.com` and can
be overridden with `--dart-define=SEEK_CHAT_API_ORIGIN=<origin>`.

### Features

- **Chat**: streaming replies, stop, regenerate, edit prompt, continue, branch
  switching across versions, auto titles
- **Rendering**: Markdown, syntax-highlighted code with copy, math, Mermaid
  diagrams, links and images
- **Web search & deep thinking**: independent toggles, tool timeline, citation
  badges, source drawer
- **Input**: photo and file attachments (images, PDF, Word, PPT and more, per an
  extension allowlist), draft attachments, upload status
- **Voice**: hold-to-talk input, read replies aloud, voice selection
- **Session drawer**: time groups, search, pin, rename, multi-select batch pin
  and delete
- **Settings**: theme, font size, language (中文 / English), location, voice,
  API key
- **Data**: API key stored only in secure storage; local drift/SQLite
  persistence; ZIP import/export of chat history

### Requirements

- Flutter 3.50.0 (matches the release workflow)
- Dart SDK `^3.14.0`

### Getting started

```bash
flutter pub get
flutter run
```

Open Settings and enter your API key. Debug builds seed Markdown and history
samples; `--dart-define=SEEK_CHAT_STRESS_SEED=true` additionally seeds 1000
sessions for stress testing.

### Development

```bash
dart run build_runner build --delete-conflicting-outputs   # after changing drift tables
flutter gen-l10n                                           # after changing ARB files
flutter analyze
flutter test                                               # full suite
flutter test test/shared/api/sse_parser_test.dart          # single file
```

Generated files (`database.g.dart`, `lib/l10n/generated/`) are committed and not
gitignored.

### Building an Android APK

```bash
./tool/build_android_apk.sh
# Output: build/app/outputs/flutter-apk/SeekChat-{arm64-v8a,armeabi-v7a,x86_64}-release.apk
```

Release builds require `android/key.properties` and a signing keystore; the
script fails fast when they are missing.

### Releasing

Push a `v*` tag on `main` to trigger GitHub Actions: version check, signed
build, draft Release. Local pre-check:

```bash
./tool/ci/check_release_version.sh v1.1.0
```

### Local checks and hooks

```bash
./tool/ci/local_checks.sh        # generated-file drift + analyze + test
brew install lefthook            # once per machine
./tool/ci/install_git_hooks.sh   # installs the pre-push hook
```

### Project layout

- Layers: `lib/main.dart → lib/app → features → shared`; only code shared by
  two or more features goes into `shared/`
- Features: `features/chat` (incl. `chat/speech`), `sessions`, `history`,
  `settings`
- State management: `flutter_riverpod` with hand-written providers
- Data: four drift tables `sessions` / `messages` / `attachments` /
  `message_attachments`
- Routing: `go_router`

### Docs

- [Behavior specs for implemented features](docs/features/README.md)
  (authoritative)
- [Glossary](GLOSSARY.md)
- [Architecture decision records](docs/adr/)
- Unimplemented and in-progress decisions live in `.scratch/<feature>/` (local
  only, gitignored)
