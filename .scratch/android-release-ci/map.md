# Map: Android 发版流水线（GitHub Actions）

## Destination

一套可直接照做的 GitHub Actions Android 发版规格：只有 `main` 上的 `v*` tag 触发，先过生成物检查、`flutter analyze` 与 `flutter test`，再用正式 release keystore 签名构建三个 split APK，自动创建 draft GitHub Release（人工润色说明后手动 publish）并附带面向用户的版本说明。产出还包括签名、版本号、版本说明与发版检查清单的最佳实践。实现（提交 workflow 文件）不在本图内。

## Notes

- 仓库：`transon-top/seek-chat`，当前私有，计划公开；公开后 GitHub-hosted runner 分钟数不再是约束。
- 稳定分支 `main`；正式发版只基于 `main` 的 tag，非 `main` 分支上的 tag 仅用于测试，不计入发布。
- 工具链：Flutter 3.50.0 stable、Dart SDK `^3.14.0`、Gradle 9.5.0、AGP 9.3.1、Kotlin 2.4.20、`compileSdk 37`；本机已验证。
- Android：`applicationId` 已定为 `com.transon_top.seekchat`（原 `com.example.open_chat`）；release 当前用 debug 签名；`pubspec` 版本 `0.5.0+1`；构建命令 `flutter build apk --release --split-per-abi`。
- 既有计划：`.scratch/flutter-deepseek-chat/roadmap.md` 的 S6 要求 CI 在开发分支执行 `build_runner`、`gen-l10n`、`analyze`、`test`；本图把该测试线扩展到 tag 发版线，不另起炉灶。两条线如何合并见票 05。
- 已定：tag `v*` 为唯一发版触发；workflow 用祖先校验确保 tag 落在 `main`；构建前跑 `analyze` + `test`；新建正式 release keystore 经 GitHub Secrets 注入；产物为 `arm64-v8a` / `armeabi-v7a` / `x86_64` 三个 split APK。
- 提交信息为 emoji 前缀；票 02 实测会破坏 Conventional Commits 解析，`git-cliff` 需一行预处理或把新提交改成 `feat(chat): ✨ ...`（票 04 已定：预处理 + 允许新格式）。
- 研究约定：findings 写在 `research/<name>` 分支的 `docs/research/`，不合并；票内记录分支、commit 与路径。
- 每个会话先读根目录 `GLOSSARY.md` 与 `docs/adr/`；research 票调用 research 技能，grilling 票调用 grilling + domain-modeling 技能。

## Decisions so far

<!-- 每个已关闭的票一行：票名 + 一句话结论。详细答案在票内。 -->

- [GitHub Actions 构建 Flutter Android 的事实与限制](issues/01-github-actions-flutter-android.md): `ubuntu-24.04` 预装 API 37 可直接构建；固定 JDK 21 + Flutter 3.50.0；NDK 28.2 需显式处理；用 `gh release create --generate-notes`；tag 来源用 merge-base guard；参考耗时首次 12–20 分钟、有缓存 6–10 分钟。
- [版本说明与整套发版流程的最佳实践](issues/02-release-notes-best-practices.md): GitHub 原生 notes 基于 merged PR、直接 push 不收录，不适合本项目；最小方案用 `git-cliff`（加 emoji 预处理）+ `CHANGELOG.md` 同源 + 开发分支→`main` merge commit + CI 校验 tag 与 `pubspec` + draft Release + SHA256SUMS + immutable releases。
- [发布签名与应用身份](issues/03-signing-and-app-identity.md): PKCS12 + RSA 4096 + 10000 天 + alias `seekchat`；本机 `android/key.properties`、两份加密离线备份、单一密码；CI 只存 `ANDROID_KEYSTORE_BASE64` 与 `ANDROID_KEYSTORE_PASSWORD` 于 `release` environment；release 缺 keystore 即失败；首次公开发版前做一次备份恢复演练。
- [版本说明形态与版本号流程](issues/04-release-notes-and-versioning.md): git-cliff + `CHANGELOG.md` 同源（emoji 预处理）；面向用户、中英双语、四类、10 条以内；tag↔pubspec 硬校验且 `+n` 递增；bump 在发布分支最后一次提交；发布分支→`main` merge commit，tag 打 main；draft Release；最小保护集（main 规则集 + `refs/tags/v*` + release environment）；暂不引入 rc；现有 tag 清空，从 `v1.0.0+1` 起。
- [git-cliff 生成 Release 说明](issues/09-release-notes-git-cliff.md): `cliff.toml` 四类分组、emoji 预处理；不落库 `CHANGELOG.md`（覆盖票 04 第 8 条），只生成 Release 说明初稿，发布前人工改写。
- [分支测试线：生成物无漂移 + 固定环境](issues/06-ci-test-line-codegen-drift.md): 云端分支/PR 测试线已删除；检查改由本地 lefthook `pre-push`（`tool/ci/local_checks.sh`）与发版工作流执行，见 `.scratch/pre-push-checks/spec.md`。

## Not yet specified

<!-- 票 04 收口后，剩余待决项已全部并入票 05 的问题清单（生成物 diff 校验、universal APK）；本图只剩票 05。 -->

## Out of scope

- iOS 打包与签名
- 自动发布到 Google Play / 国内应用商店（AAB、商店元数据）
- 多 flavor / 多环境打包
- 应用品牌名与图标定稿（属 S6 另一项）
