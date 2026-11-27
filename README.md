<p align="center">
  <img src="docs/images/logo.png" alt="SeekChat" width="120">
</p>

# SeekChat

[English](README.en.md) | 简体中文

Flutter 版 DeepSeek 聊天应用，当前面向 **Android** 发布。

> 本项目是个人自用 App 的公开分享：功能按个人使用习惯迭代，不提供商业支持，
> 也不保证适配所有设备。

模型固定为 `deepseek-flash`；API 源默认 `https://api.deepseek.com`，可用
`--dart-define=SEEK_CHAT_API_ORIGIN=<origin>` 覆盖。

## 隐私

- **无遥测、无广告**：不接入任何统计、分析、广告、崩溃上报或推送 SDK，
  也不向第三方服务器发送使用数据。
- **只需自己的 Key**：App 不内置 API Key，启动后在设置里填写自己的
  DeepSeek API Key 即可使用。
- **只请求 DeepSeek 官方接口**：对话、附件上传、语音转写与朗读都发往同一
  API 源，默认官方 `https://api.deepseek.com`；Key 只出现在该源的
  `Authorization` 头中，不写数据库、日志或导出包。
- **例外**：联网搜索的来源站点图标会按搜索结果中的 URL 远程加载；点击消息
  中的链接交给系统浏览器打开，App 本身不请求。
- **Markdown 图片不加载**，只显示可点击地址。
- 会话、附件与设置只存本机；API Key 存 `flutter_secure_storage`，Android
  禁用系统备份（`allowBackup=false`）。

## 功能

- 流式回复、停止、重新生成、编辑提问、续写与分支版本切换
- Markdown、代码高亮与复制、数学公式、Mermaid 图、链接与图片
- 联网搜索与深度思考开关，工具时间线与引用来源
- 附件上传、图片横条、按住说话转写、朗读
- 会话分组、搜索、置顶、多选、重命名与删除
- 历史导入导出、深浅色主题、字号、语言与所在地设置
- 输入与输出内容审核、错误分类与本地化文案

完整行为规格见 [docs/features/](docs/features/README.md)。

## 环境要求

- Flutter 3.50.0（stable，与发版一致）
- Dart SDK `^3.14.0`
- JDK 21 与 Android SDK（构建 Android 时需要）

## 快速开始

```bash
flutter pub get
flutter run
```

启动后在「设置 → API Key」填入 DeepSeek API Key 即可对话。API Key 只存
`flutter_secure_storage`，不写数据库、日志与导出包。

## 构建 APK

```bash
./tool/build_android_apk.sh
```

按 ABI 分包，产物重命名为 `SeekChat-<abi>-release.apk`，位于
`build/app/outputs/flutter-apk/`。release 构建需要 `android/key.properties`
与正式 keystore，缺失时立即失败。

## 开发

```bash
dart run build_runner build --delete-conflicting-outputs   # 改 drift 表后
flutter gen-l10n                                           # 改 ARB 后
flutter analyze
flutter test
./tool/ci/local_checks.sh                                  # 生成物漂移 + analyze + test
```

代码生成物（`database.g.dart`、`lib/l10n/generated/`）入库，改动后必须重跑。

Git 钩子：`brew install lefthook`，再每台机器跑一次
`./tool/ci/install_git_hooks.sh`（pre-push 自动执行 `local_checks.sh`）。

## 发版

在 `main` 上打 `v*` tag 触发 [.github/workflows/release.yml](.github/workflows/release.yml)，
校验版本、签名构建并创建 draft Release。详见
[docs/runbooks/release.md](docs/runbooks/release.md)。

## 项目结构

```text
lib/
  app/        启动、路由、主题与本地化
  features/   chat、sessions、history、settings
  shared/     API、数据层、模型、组件、安全存储
  l10n/       ARB 与生成物
docs/
  features/   已实现功能的行为规格（权威）
  adr/        架构决策
  runbooks/   发版手册
```

依赖方向 `app → features → shared`；`shared/` 不反向 import `features/`。

## 文档

- 功能规格：[docs/features/](docs/features/README.md)
- 领域术语：[GLOSSARY.md](GLOSSARY.md)
- 架构决策：[docs/adr/](docs/adr/)
