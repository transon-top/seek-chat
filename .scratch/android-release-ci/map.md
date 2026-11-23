# Map: Android 发版流水线（GitHub Actions）

## Destination

一套可直接照做的 GitHub Actions Android 发版规格：只有 `main` 上的 `v*` tag 触发，先过生成物检查、`flutter analyze` 与 `flutter test`，再用正式 release keystore 签名构建三个 split APK，自动创建 published GitHub Release 并附带面向用户的版本说明。产出还包括签名、版本号、版本说明与发版检查清单的最佳实践。实现（提交 workflow 文件）不在本图内。

## Notes

- 仓库：`transon-top/open-chat`，当前私有，计划公开；公开后 GitHub-hosted runner 分钟数不再是约束。
- 当前分支 `v1-dev`，稳定分支 `main`；正式发版只基于 `main` 的 tag，`v1-dev` 上的 tag 仅用于测试，不计入发布。
- 工具链：Flutter 3.50.0 stable、Dart SDK `^3.14.0`、Gradle 9.5.0、AGP 9.3.1、Kotlin 2.4.20、`compileSdk 37`；本机已验证。
- Android：`applicationId` 仍是 `com.example.open_chat`；release 当前用 debug 签名；`pubspec` 版本 `0.5.0+1`；构建命令 `flutter build apk --release --split-per-abi`。
- 既有计划：`.scratch/flutter-deepseek-chat/roadmap.md` 的 S6 要求 CI 在 `v1-dev` 执行 `build_runner`、`gen-l10n`、`analyze`、`test`；本图把该测试线扩展到 tag 发版线，不另起炉灶。两条线如何合并见票 05。
- 已定：tag `v*` 为唯一发版触发；workflow 用祖先校验确保 tag 落在 `main`；构建前跑 `analyze` + `test`；新建正式 release keystore 经 GitHub Secrets 注入；产物为 `arm64-v8a` / `armeabi-v7a` / `x86_64` 三个 split APK。
- 待票 04 决定：Release 此前定为自动 published；票 02 建议改为 draft + `git-cliff` notes。tag 与 `pubspec` 版本一致性校验此前预留；票 02 建议恢复为硬校验。
- 提交信息为 emoji 前缀；票 02 实测会破坏 Conventional Commits 解析，`git-cliff` 需一行预处理或把新提交改成 `feat(chat): ✨ ...`。
- 研究约定：findings 写在 `research/<name>` 分支的 `docs/research/`，不合并；票内记录分支、commit 与路径。
- 每个会话先读根目录 `GLOSSARY.md` 与 `docs/adr/`；research 票调用 research 技能，grilling 票调用 grilling + domain-modeling 技能。

## Decisions so far

<!-- 每个已关闭的票一行：票名 + 一句话结论。详细答案在票内。 -->

- [GitHub Actions 构建 Flutter Android 的事实与限制](issues/01-github-actions-flutter-android.md): `ubuntu-24.04` 预装 API 37 可直接构建；固定 JDK 21 + Flutter 3.50.0；NDK 28.2 需显式处理；用 `gh release create --generate-notes`；tag 来源用 merge-base guard；参考耗时首次 12–20 分钟、有缓存 6–10 分钟。
- [版本说明与整套发版流程的最佳实践](issues/02-release-notes-best-practices.md): GitHub 原生 notes 基于 merged PR、直接 push 不收录，不适合本项目；最小方案用 `git-cliff`（加 emoji 预处理）+ `CHANGELOG.md` 同源 + `v1-dev`→`main` merge commit + CI 校验 tag 与 `pubspec` + draft Release + SHA256SUMS + immutable releases。

## Not yet specified

- 版本说明的最终形态：票 02 推荐 `git-cliff` + emoji 预处理 + `CHANGELOG.md` 同源；待票 04 确认
- `tag` 与 `pubspec` 版本一致性校验：票 02 建议恢复为硬校验；待票 04 决定（此前预留）
- Release 发布形态：票 02 建议 draft；此前定为自动 published；待票 04 决定
- 公开仓库后的分支保护、tag 保护与 PR 流程：票 02 建议 `refs/tags/v*` + main 规则集 + `release` environment；待票 04 定稿
- 版本说明的读者、语言（中 / 英 / 双语）与内容分类（待票 04）
- CI 是否校验 `build_runner` / `gen-l10n` 生成物无 diff（事实已由票 01 确认可用 `git diff --exit-code`，待票 05 决定）
- 是否额外提供 universal APK 作为 Release 资产（待票 05）
- 签名与应用身份的迁移：`com.example.open_chat` 是否在首次公开发版前更换（待票 03）

## Out of scope

- iOS 打包与签名
- 自动发布到 Google Play / 国内应用商店（AAB、商店元数据）
- 多 flavor / 多环境打包
- 应用品牌名与图标定稿（属 S6 另一项）
