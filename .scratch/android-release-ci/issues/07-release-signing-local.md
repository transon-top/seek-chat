# 07: 正式签名本地闭环

**What to build:** 生成正式 release keystore，完成离线备份与恢复演练；本机 release 构建改用正式证书签名。release 构建缺少签名材料时立即失败，debug 构建不受影响。

**Blocked by:** 无（可立即开始）。

**Status:** ready-for-agent

- [ ] keystore 按定案生成：PKCS12、RSA 4096、`SHA256withRSA`、10000 天、alias `seekchat`、文件名 `seekchat-release.p12`、单一密码；存放在仓库外，权限 600。
- [ ] 两份加密离线备份放在不同物理介质与地点，另加一份密码管理器附件；密码只存密码管理器，并留一份离线恢复码。
- [ ] 备份恢复演练：用备份副本构建一次 release，`apksigner verify --print-certs` 通过，记录证书 SHA-256 指纹备查。
- [ ] Gradle 的 release 签名从 `android/key.properties` 读取；文件缺失或 keystore 不存在时 release 构建立即失败并给出明确错误，不再回退 debug 签名。
- [ ] `key.properties`、`*.p12`、`*.keystore`、`*.jks` 均被忽略；`git status` 不出现任何签名材料。
- [ ] 本机 `flutter build apk --release --split-per-abi` 产出三个 APK，`apksigner verify --print-certs` 显示 `CN=SeekChat`。
- [ ] debug 构建与 debug 模式 `flutter run` 不受影响。
- [ ] keystore 的 base64 与密码已备好，供 08 写入 GitHub environment secret。
