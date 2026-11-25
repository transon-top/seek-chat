# 08: tag 触发的签名构建与产物

**What to build:** 向仓库 push `v*` tag 时，在固定工具链上校验 tag 来源与版本一致性，用 `release` environment 的 secrets 还原 keystore，构建三个已签名 split APK 并上传为 artifact。不在 `main` 祖先链上的 tag 只构建、不发布，供发版演练使用。

**Blocked by:** 07。

**Status:** claimed

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
- [ ] 用非 `main` 分支上的测试 tag 实跑一次：校验通过、三个 APK 构建并上传、发布被跳过；验证后删除测试 tag。

## Comments

- 2026-11-25：`.github/workflows/release.yml` 落地：`v*` tag 触发；`fetch-depth: 0` +
  fetch main + `merge-base --is-ancestor` 三分支处理（0/1/其他）；
  `tool/ci/check_release_version.sh` 校验 tag 与 pubspec 一致及 `+n` 递增（本地临时仓库
  覆盖通过、不一致、未递增、无上一 tag 四种情况）；`ubuntu-24.04` + JDK 21 +
  Flutter 3.50.0 + NDK 28.2.13676358；`environment: release`；keystore 解码到
  `$RUNNER_TEMP`、`key.properties` 只写 workspace、`if: always()` 清理；构建用
  `tool/build_android_apk.sh`，上传三个 APK + `SHA256SUMS`；并发组按 tag 互斥、
  超时 60 分钟、默认只读权限；action 全部固定 SHA。
- 核对：远端当前没有任何 tag，旧 `v0.3.0` / `v0.4.0` / `v0.5.0` 已不存在，无需清理。
- 2026-11-25：`release` environment 已建，部署策略只允许 `v*` tag；
  `ANDROID_KEYSTORE_BASE64` 与 `ANDROID_KEYSTORE_PASSWORD` 两个 environment secret
  已写入；Actions 默认权限设为只读；immutable releases 已开启。
- 2026-11-25：测试 tag `v0.5.0` 在 main 合并提交实跑成功（run `45562861470`）：
  NDK、analyze、test、签名构建、artifact 上传、draft Release 全部通过；三个 APK
  的 `SHA256SUMS` 校验一致，arm64 APK 指纹为 `12042e1e...caf38b`。
  仓库无独立开发分支，测试 tag 直接打在 main，因此 release job 会创建
  draft；验证后已删除 draft 与测试 tag。
- 待办（用户执行）：仓库公开后补 tag 规则集，再按 `v1.0.0` 流程发布。
