# SeekChat

This file provides guidance to Claude Code (claude.ai/code) and other agents when working with code in this repository.

## Agent skills

### Issue tracker

Issues and in-progress specs live as markdown files under `.scratch/<feature>/` in this repo. Implemented feature specs live in `docs/features/` and are authoritative. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: one `GLOSSARY.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## 项目

Flutter 版 DeepSeek 聊天应用（iOS + Android）。v1 固定模型 `deepseek-flash`，
API 源默认 `https://api.deepseek.com`，可用
`--dart-define=SEEK_CHAT_API_ORIGIN=<origin>` 覆盖。

已实现功能的行为规格在 `docs/features/`（权威，迭代时同步更新）；未实现或
进行中的决策与票在 `.scratch/<feature>/`（`spec.md` 或 wayfinder 的
`map.md`，加 `issues/NN-*.md`）。
领域术语见根目录 `GLOSSARY.md`，架构决策见 `docs/adr/`。写票、命名领域概念时
先读 `GLOSSARY.md` 并沿用其中词汇。

## 常用命令

```bash
flutter pub get
flutter analyze
flutter test                                   # 全量
flutter test test/shared/api/sse_parser_test.dart          # 单文件
flutter test test/features/chat --plain-name "某用例名"    # 单用例
flutter run

# 代码生成（生成物入库，改表/改 ARB 后必须重跑）
dart run build_runner build --delete-conflicting-outputs   # drift
flutter gen-l10n                                           # ARB

# 构建：只打 Android，按 ABI 分包，产物重命名为 SeekChat-<abi>-release.apk
./tool/build_android_apk.sh
# 产物：build/app/outputs/flutter-apk/SeekChat-{arm64-v8a,armeabi-v7a,x86_64}-release.apk

# 性能基线（需模拟器/真机，不属默认测试）
flutter drive --profile -d <device> \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/list_perf_test.dart

# 输入区端到端集成测试（需模拟器/真机）
flutter test integration_test/composer_test.dart -d <device>

# CI：.github/workflows/ci.yml 在 push/PR 跑 analyze + test（Flutter 3.50.0）
# 本地 act 镜像构建命令见 .github/act/Dockerfile
```

Debug 构建会自动写入 Markdown 样本与历史样本（`lib/dev/mock_seed.dart`）；
`--dart-define=SEEK_CHAT_STRESS_SEED=true` 额外写入 1000 会话压测数据。
Release 不写样本。

## 架构

**分层与依赖方向**：`main → app → features → shared`。功能优先目录，
只有被两个以上功能复用的代码才进 `shared/`。`shared/` 不得 import
`features/`，功能之间不直接 import（先下沉到 `shared/`）。功能目录：
`features/chat`（含 `chat/speech`）、`sessions`、`history`、`settings`。

**启动顺序**（`lib/app/startup.dart`，`main()` 只组装依赖并 `runApp`）：读
`SharedPreferences` → 打开 drift 数据库并 `resetInterruptedReplies()` 把残留
`pending`/`streaming` 置为 `stopped` → debug 样本 → 附件孤儿清理 →
`runApp(ProviderScope(overrides: ...))` 注入 database / repository /
attachmentStore / preferences 四个实例。偏好、数据库与收尾失败进入
`ProviderScope` 外的启动失败页（重试 / 清除本地会话与附件）；样本与清理失败
不阻塞。测试同样用 override + `NativeDatabase.memory()`。

**状态管理**：`flutter_riverpod` 3.5 手写 Provider，不用 `riverpod_generator`。
基础设施 Provider 集中在 `lib/shared/providers.dart`。会话列表用
`StreamProvider` 监听 drift；聊天用
`NotifierProvider.autoDispose.family<ChatController, ChatState, String>`，
流式期间 `ref.keepAlive()`，结束后释放。流式事件在内存合并，只在创建、
请求发出前、终态写库（`ReplyAccumulator`）。App 进入后台时经
`activeChatControllersProvider` 逐个 `flush()`。

**数据层**：drift 四表 `sessions`/`messages`/`attachments`/`message_attachments`
（`lib/shared/data/database.dart`），回复块存 `messages.blocks` JSON 列。
分支模型：`parentId` + 每行的 `selectedChildId`；可见路径 = 从
`sessions.rootMessageId` 沿 `selectedChildId` 走到叶子。`ChatRepository`
直接封装查询与事务，不加 DataSource 抽象层。

**API 层**：`DeepSeekApiClient`（Anthropic 兼容 Messages API）负责请求构造、
WHATWG SSE 解析（`api/sse.dart`）、事件类型化（`api/stream_events.dart`）、
错误分类（`api/errors.dart`）。错误统一为 `ApiException`；
`shared/error_text.dart` 是把 `ApiErrorCondition` 映射为 ARB 文案的唯一入口。
服务端原始错误文本仅 debug 显示。附件上传走同一客户端的 `uploadFile`
（`/anthropic/v1/files`）；语音 ASR/TTS 在
`features/chat/speech/speech_api.dart`（`/v1/tools/*`，与 Messages 端点
分开，`Bearer` 鉴权）。

**UI**：导入 `package:material_ui/material_ui.dart`（不是 `flutter/material.dart`，
后者在 Flutter 3.50 起废弃），`shadcn_ui` 用于目标组件库，两者并存。
聊天页侧栏用自研 `PushMenu`（`shared/widgets/push_menu.dart`），不是
`Scaffold.drawer`（ADR-0001）。全局滚动行为 `appScrollBehavior` 在
`lib/app/app.dart`。

**i18n**：`gen_l10n` + `lib/l10n/app_en.arb`（模板）/`app_zh.arb`，生成物
`lib/l10n/generated/` 入库。`l10n.yaml` 的 header 是必要的：
`AppLocalizations` 改用 `material_ui` 的 Material 委托（见
`lib/app/localization.dart`），生成物里的弃用提示无需修复。

## 约定

- 生成物（`database.g.dart`、`lib/l10n/generated/`）入库，不在 `.gitignore`。
- 静态检查沿用 `flutter_lints`，每次改动跑 `flutter analyze` + `flutter test`。
- 测试用 `ProviderScope` override、内存数据库、`http/testing.dart` 的
  `MockClient`；共享 fixture 在 `test/support/`。
- 日志走 `shared/logging.dart`（仅 debug 输出）；禁止记录 API Key、请求头、
  完整请求体与附件内容。API Key 只经 `shared/security/api_key_store.dart`。
- `shadcn_ui` 锁 `>=0.60.0 <0.61.0`；依赖升级后必须重跑 analyze 与测试。
- 不做一次性大重写：新界面直接用 shadcn_ui，旧界面沿用 material_ui。
