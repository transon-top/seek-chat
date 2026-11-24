# 08: tag 触发的签名构建与产物

**What to build:** 向仓库 push `v*` tag 时，在固定工具链上校验 tag 来源与版本一致性，用 `release` environment 的 secrets 还原 keystore，构建三个已签名 split APK 并上传为 artifact。不在 `main` 祖先链上的 tag 只构建、不发布，供 `v1-dev` 测试使用。

**Blocked by:** 07。

**Status:** ready-for-agent

- [ ] push `v*` tag 触发发版 workflow；分支与 PR 不触发。
- [ ] 来源校验：checkout 拉全历史并 fetch `origin/main`，用 `git merge-base --is-ancestor` 判断。退出码 1 表示不在 `main` 上：继续构建但标记为不发布；其他非零退出码视为错误并让 job 失败。
- [ ] 版本校验在构建前失败：tag `vX.Y.Z` 必须等于 `pubspec.yaml` 的 `x.y.z`；`+n` 必须严格大于上一个可达 `v*` tag 所指提交的 `+n`；无上一个 tag 时跳过递增检查。
- [ ] 先清空旧 `v0.3.0` / `v0.4.0` / `v0.5.0` tag（远端操作，需用户确认），否则 `0.5.0+1` 的测试 tag 无法通过递增检查。
- [ ] 工具链固定：`ubuntu-24.04`、JDK 21（`actions/setup-java`）、Flutter 3.50.0、NDK `28.2.13676358`；启用 Gradle 缓存；新增第三方 action 固定完整 commit SHA。
- [ ] 建 `release` environment，只存 `ANDROID_KEYSTORE_BASE64` 与 `ANDROID_KEYSTORE_PASSWORD` 两个 secret；alias 硬编码 `seekchat`。
- [ ] 构建 job 声明 `environment: release`；keystore 解码到 runner 临时目录并 `chmod 600`，`key.properties` 只生成在 workspace；清理步骤用 `if: always()` 删除两者。
- [ ] 日志、artifact 与 shell 输出不出现密码、keystore、`key.properties`；不开启 xtrace。
- [ ] `flutter analyze` 与 `flutter test` 在构建前通过；`flutter build apk --release --split-per-abi` 产出三个 APK 并上传为 artifact。
- [ ] 同一 tag 的并发运行互斥，并设合理超时（如 60 分钟）；workflow 默认权限 `contents: read`。
- [ ] 用 `v1-dev` 上的测试 tag 实跑一次：校验通过、三个 APK 构建并上传、发布被跳过；验证后删除测试 tag。
