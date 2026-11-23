# 发布签名与应用身份

Type: grilling
Status: open

## Question

首次公开发版前，发布签名与应用身份如何定？

需要敲定：

1. 新建 release keystore 的参数：key algorithm、key size、validity、alias、dname；建议的有效期与 Android 上架要求。
2. keystore 的本机保存位置、备份方式（至少两处离线备份）与丢失后的后果；密码由谁保管、放在哪里。
3. GitHub Secrets 的命名与最少集合（如 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`）；公开仓库下如何避免泄漏，是否需要 environment 审批。
4. 本地 release 构建如何复用同一 keystore：`android/key.properties` + 本机副本；保持 `key.properties`、`*.jks`、`*.keystore` 不入库。
5. `applicationId` 是否在首次公开发版前从 `com.example.open_chat` 更换为正式包名？更换会导致已装 debug 签名包无法覆盖升级，是否接受先卸载。
6. 是否保留本地 debug 签名的 release 构建路径，还是所有 release 都走正式签名。

产出一份决策：keystore 参数、保存与备份、secrets 清单、`applicationId` 是否现在更换。
