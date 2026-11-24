# 汇总并确认 workflow 规格

Type: grilling
Status: open
Blocked by: 01, 02, 03, 04

## Question

把票 01–04 的结论组装成一份可直接照做的 workflow 规格，并确认没有遗漏。

需要覆盖：

1. 触发：`main` 上的 `v*` tag；祖先校验的具体步骤与失败行为（失败 / 跳过）。
2. 与既有 S6 计划的关系：`v1-dev` 上运行 `build_runner`、`gen-l10n`、`analyze`、`test` 的测试线，是与发版共用一条 workflow，还是拆成两条；两条的触发条件。
3. 构建前检查：依赖安装、生成物是否要求无 diff、`flutter analyze`、`flutter test` 的范围（是否含 `integration_test`）。
4. 构建：JDK / Flutter / Android SDK / NDK 的固定方式；Gradle 与 pub 缓存；`flutter build apk --release --split-per-abi`。
5. 签名：从 secrets 还原 keystore、生成 `key.properties`、权限与清理；构建日志不得出现密码。
6. 发布：三个 APK 的命名、上传为 Release 资产、是否额外提供 universal APK 资产、自动 notes、draft Release（票 04 已定）、失败时是否留下半成品 Release。
7. 权限与并发：`permissions: contents: write` 的最小集合、`concurrency`、超时、runner 选择。
8. 操作清单：从 bump 版本到打 tag 的完整人工步骤，以及发布后验证与回滚。
9. 风险与未知项：SDK / NDK 下载、构建时长、免费额度（公开后）、secrets 泄漏面、`applicationId` 迁移。

产出：`.scratch/android-release-ci/workflow-spec.md`，经用户确认后本图完成。
