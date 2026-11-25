# 07: 正式签名本地闭环

**What to build:** 生成正式 release keystore，完成离线备份与恢复演练；本机 release 构建改用正式证书签名。release 构建缺少签名材料时立即失败，debug 构建不受影响。

**Blocked by:** 无（可立即开始）。

**Status:** claimed

- [ ] keystore 按定案生成：PKCS12、RSA 4096、`SHA256withRSA`、10000 天、alias `seekchat`、文件名 `seekchat-release.p12`、单一密码；存放在仓库外，权限 600。
- [ ] 两份加密离线备份放在不同物理介质与地点，另加一份密码管理器附件；密码只存密码管理器，并留一份离线恢复码。
- [ ] 备份恢复演练：用备份副本构建一次 release，`apksigner verify --print-certs` 通过，记录证书 SHA-256 指纹备查。
- [x] Gradle 的 release 签名从 `android/key.properties` 读取；文件缺失或 keystore 不存在时 release 构建立即失败并给出明确错误，不再回退 debug 签名。
- [x] `key.properties`、`*.p12`、`*.keystore`、`*.jks` 均被忽略；`git status` 不出现任何签名材料。
- [x] 本机 `flutter build apk --release --split-per-abi` 产出三个 APK，`apksigner verify --print-certs` 显示 `CN=SeekChat`。
- [x] debug 构建与 debug 模式 `flutter run` 不受影响。
- [ ] keystore 的 base64 与密码已备好，供 08 写入 GitHub environment secret。

## Comments

- 2026-11-25：`android/app/build.gradle.kts` 改为从 `android/key.properties` 读签名；
  缺文件或 keystore 不存在时 `preReleaseBuild` 立即失败（没有 signingConfig 时 AGP 会
  静默产出未签名 APK，所以不用 `validateSigningRelease`）；移除 debug 签名回退；
  `android/.gitignore` 增加 `**/*.p12`。
- 本地用临时 keystore 验证：release 构建三个 split APK 成功，`apksigner` 显示
  `CN=SeekChat`；无 `key.properties` 时 release 2 秒内失败；debug APK 构建正常。
  临时 keystore 与 `key.properties` 已删除，未产生真实签名身份。
- 待办（用户执行）：按 `docs/runbooks/release.md` 生成正式 keystore、两份离线备份、
  恢复演练并记录真实证书指纹；本机写 `key.properties`。
- 2026-11-25：正式 keystore 已生成：`~/keystores/seekchat-release.p12`（PKCS12、
  RSA 4096、SHA256withRSA、10000 天、alias `seekchat`，权限 600）；密码生成在
  `~/keystores/seekchat-release.password`（600，待用户导入密码管理器后删除）。
  本机 `android/key.properties` 已指向主副本。
- 恢复演练通过：用 keystore 副本构建三个 split APK，`apksigner` 输出
  `CN=SeekChat, OU=Android, O=Transon Top, C=CN`。
- 证书指纹（apksigner）：`12042e1e58594c4eef6c71e51c8656a91aff2097e86ec43afc1ed9e596caf38b`
- 2026-11-25：密码已存入用户密码管理器；keystore 备份与校验值已放到
  `/Users/transon/Downloads/同步空间/配置备份/keystores/`，附换机手册 `README.md`。
- 2026-11-25：`~/keystores/seekchat-release.password` 已用 keytool 验证可打开
  keystore 后删除；`~/keystores/` 只剩 `.p12`。GitHub `release` environment 的两个
  secret 已写入。
- 仍待用户执行：两块离线介质备份；纸质离线恢复码。
