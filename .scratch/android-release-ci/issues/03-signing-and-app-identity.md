# 发布签名与应用身份

Type: grilling
Status: resolved

## Question

首次公开发版前，发布签名与应用身份如何定？

需要敲定：

1. 新建 release keystore 的参数：key algorithm、key size、validity、alias、dname；建议的有效期与 Android 上架要求。
2. keystore 的本机保存位置、备份方式（至少两处离线备份）与丢失后的后果；密码由谁保管、放在哪里。
3. GitHub Secrets 的命名与最少集合（如 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`）；公开仓库下如何避免泄漏，是否需要 environment 审批。
4. 本地 release 构建如何复用同一 keystore：`android/key.properties` + 本机副本；保持 `key.properties`、`*.jks`、`*.keystore` 不入库。
5. `applicationId` 已在改名时从 `com.example.open_chat` 更换为 `com.transon_top.seekchat`；已装 debug 签名包无法覆盖升级，接受先卸载。
6. 是否保留本地 debug 签名的 release 构建路径，还是所有 release 都走正式签名。

产出一份决策：keystore 参数、保存与备份、secrets 清单；`applicationId` 已定，不再讨论。

## Answer

已与用户逐轮确认，全部按推荐采纳。

### 1. Keystore 参数

- 格式 PKCS12；RSA 4096；`SHA256withRSA`；有效期 10000 天（约 27.4 年）；alias `seekchat`；dname `CN=SeekChat, OU=Android, O=Transon Top, C=CN`。
- 文件名 `seekchat-release.p12`。
- PKCS12 的 key password 必须等于 store password，只维护一个密码。
- 密码取长随机字母数字串，避开 `\`、`:`、`=`、`#`、`!` 等 `key.properties` 转义问题。
- 生成命令：

  ```bash
  keytool -genkeypair -v \
    -keystore seekchat-release.p12 \
    -storetype PKCS12 \
    -alias seekchat \
    -keyalg RSA -keysize 4096 -sigalg SHA256withRSA \
    -validity 10000 \
    -dname "CN=SeekChat, OU=Android, O=Transon Top, C=CN"
  ```

### 2. 保存、备份、密码与丢失后果

- 主副本 `~/keystores/seekchat-release.p12`，权限 `600`，仓库外。
- 两份加密备份，放两块不同物理介质、不同地点；再加一份密码管理器附件。备份就是同一 `.p12` 文件，签名身份与机器无关；家里电脑放同一文件的仓库外副本，`key.properties` 指过去即可，两台机器签出的 APK 可互相覆盖升级（`versionCode` 仍需递增）。
- 禁止在两台机器各自生成新 keystore，也不要用同名新文件覆盖原文件。
- 密码只存密码管理器，另留一份离线恢复码；仅用户本人持有。
- 丢失后果：同一 `applicationId` 无法用新证书覆盖升级，用户必须卸载（丢失本地数据）；无 Play App Signing，无恢复通道。首次公开发版前成本低，发布后不可逆。

### 3. Secrets 与 environment

- 只建两个 secret：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`。alias `seekchat` 硬编码在 workflow；不设 `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`。
- base64 生成：`base64 -i seekchat-release.p12 | tr -d '\n'`；同时存一份到密码管理器。
- 建 `release` environment，两个 secret 放环境级；部署 tag 规则只允许 `v*`；不设 required reviewer。
- 发版 job 必须声明 `environment: release`，否则拿不到环境 secret。

### 4. 本地 release 构建

- `android/key.properties` 已被 `.gitignore` 覆盖，内容：

  ```properties
  storeFile=/Users/transon/keystores/seekchat-release.p12
  storePassword=<password>
  keyAlias=seekchat
  keyPassword=<password>
  ```

- Gradle 从该文件读取 release 签名配置；CI 构建时在 workspace 现场生成同结构文件，`storeFile` 指向 `$RUNNER_TEMP` 的解码副本。
- 不用环境变量或 Gradle 属性传密码。

### 5. 签名策略

- 移除 release 回退 debug 签名。release 构建缺少 `key.properties` 或 keystore 时立即失败，并输出明确错误；debug 构建不受影响。
- 本机 `flutter run --release` 需要存在 `key.properties`。
- `applicationId` 固定 `com.transon_top.seekchat`，不再讨论；已装 debug 签名包无法覆盖升级，接受先卸载。

### 6. 公开仓库防泄漏

- 仅 `push.tags: v*` 触发；禁止 `pull_request_target`。
- keystore 解码到 `$RUNNER_TEMP`，`chmod 600`；`key.properties` 只存在 workspace。
- 清理步骤用 `if: always()` 删除 keystore 与 `key.properties`。
- 不打印密钥或密码，不开启 shell xtrace，不上传 keystore / `key.properties` 为 artifact。
- 第三方 action 固定完整 commit SHA，不用浮动的 `@vN`。

### 7. 备份恢复演练

- 首次公开发版前，在一台机器上用备份副本签一次 release APK，用 `apksigner verify --print-certs` 核对证书 SHA-256 指纹，确认备份可用。
- 指纹生成后记入本票备查；它不是秘密，可用于以后确认 CI 产物的签名来源。

### 移交

- 票 05 的 workflow 规格需覆盖：secrets 解码、`key.properties` 生成、`environment: release`、清理步骤、action SHA 固定。
- 应用侧实现（本图外）：`android/app/build.gradle.kts` 读取 `key.properties`，release 缺签名即失败。
- 票 04 / 05 的发版检查清单加入首次恢复演练与指纹记录。
