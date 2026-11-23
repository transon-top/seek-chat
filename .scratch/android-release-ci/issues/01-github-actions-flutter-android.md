# GitHub Actions 构建 Flutter Android 的事实与限制

Type: research
Status: resolved

## Question

在 2026-11 的 GitHub Actions 上，为这个 Flutter 项目构建 Android APK 需要哪些事实与限制？逐项给出官方来源与核查日期；区分「文档明确」与「推断」。

必须回答：

1. `ubuntu-latest` 当前镜像预装哪些 Android SDK API level？`compileSdk 37` 是否可直接构建；若不能，如何用 `sdkmanager` 安装、接受 licenses，耗时多少。
2. AGP 9.3.1 + Gradle 9.5.0 要求哪个 JDK 版本？runner 预装哪些 JDK；如何固定（`actions/setup-java` 或 `subosito/flutter-action` 的 `java-version`）。
3. Flutter 3.50.0 默认 NDK 版本是多少；runner 是否预装；未预装时安装方式与耗时。`flutter_soloud` / `record` / `photo_manager` / `sqlite3` 等原生依赖是否引入额外构建要求。
4. `subosito/flutter-action` 当前主版本、推荐用法、缓存机制；如何精确 pin Flutter 3.50.0。
5. Gradle 缓存（`gradle/actions/setup-gradle` 或 `actions/cache`）当前推荐写法；首次与后续构建的耗时差异量级。
6. 私有仓库与公开仓库的 Actions 免费额度现状；公开仓库使用 secrets 与接受 fork PR 的安全注意事项。
7. 类似本项目（Flutter + 多个原生依赖）在 GitHub-hosted runner 上的合理构建耗时估计；首次构建与有缓存构建分别估计。
8. 产物上传：`actions/upload-artifact` 当前主版本与保留期；创建 GitHub Release 的当前推荐方式（`gh release create`、`softprops/action-gh-release` 或官方 API），如何附加多个 split APK 并启用自动 release notes。
9. 只允许 `main` 分支的 tag 触发：`on.push.tags` 的原生限制；用 `git merge-base --is-ancestor` 校验 tag 所指提交属于 `origin/main` 的正确写法（`actions/checkout` 的 `fetch-depth`、fetch main）；是否存在官方原生分支过滤。
10. 其他坑：Android SDK licenses、Gradle 内存、job 超时、ABI split 的 versionCode、`flutter test` 在 CI 的注意点、`build_runner` / `gen-l10n` 生成物在 CI 的处理方式。

结论需给出一份最小可行 workflow 骨架（仅示意，不写入仓库），并列出最大风险与仍不确定的事实。

## Answer

调研完成（2026-11-23）。完整结论见 `research/github-actions-flutter-android` 分支：
`docs/research/github-actions-flutter-android.md`（commit `5fd195c658a3e6c008ff5d88cda19227198e11c7`，未合并）。
https://github.com/transon-top/open-chat/blob/5fd195c658a3e6c008ff5d88cda19227198e11c7/docs/research/github-actions-flutter-android.md

关键事实：

- `ubuntu-latest` = Ubuntu 24.04（镜像 `20261116.376.1`），预装 `android-37.0`、build-tools 37.0.0、cmdline-tools 12.0；`compileSdk 37` 可直接构建。建议固定 `ubuntu-24.04` 防镜像漂移。
- AGP 9.3 最低 JDK 17，Gradle 9.5 支持 JVM 17–26。`subosito/flutter-action` 无 `java-version` 输入，必须用 `actions/setup-java@v6`；固定 JDK 21，因为 AGP 9.3.1 的 lint 在 JDK 17 崩溃。
- Flutter 3.50.0 默认 NDK `28.2.13676358`；runner 预装 27.3 / 29.0 / 30.0，且 `ANDROID_NDK_HOME` 默认指向 27.3。AGP 在 licenses 已接受时可自动下载 NDK；需显式 pin 并核对 `ANDROID_NDK_HOME`。
- `subosito/flutter-action` 当前 v2.23.0：`channel: stable` + `flutter-version: '3.50.0'` + `cache: true`。
- Gradle 缓存用 `gradle/actions/setup-gradle@v6`；公开仓库增强缓存免费。参考耗时：首次约 12–20 分钟，有缓存约 6–10 分钟（推断，需实跑校准）。
- 公开仓库标准 runner 免费；私有 Free 约 2000 Linux 分钟/月。
- `actions/upload-artifact` 当前 v7.0.2，默认保留 90 天；Release 用 runner 预装的 `gh release create --generate-notes`，或 `softprops/action-gh-release@v3`（可重跑更新）；需 `permissions: contents: write`。
- tag 来源校验：`on.push.tags` 无原生分支过滤；`checkout` 用 `fetch-depth: 0`，再 `git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main`，用 `git merge-base --is-ancestor "$GITHUB_SHA" refs/remotes/origin/main`；返回 1 表示不在 main 上，其他非零是错误，需区分。
- 其他：`-Xmx8G` 在私有 8 GB runner 有 OOM 风险（`android/gradle.properties`）；job 上限 6 小时；split APK 自动加 `ABI_VERSION * 1000`；生成物已入库，可用 `git diff --exit-code` 防漂移；`flutter test` 依赖宿主 libsqlite3（runner 已装）。

最大风险：debug 签名 + `com.example.open_chat`（票 03）；AGP 9.3.1 在 JDK 17 的 lint 崩溃；私有 runner 内存；NDK 版本错位；缺少 tag 来源 guard。所有耗时与 NDK 自动下载行为需首次实跑确认。
