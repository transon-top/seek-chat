# Android 发版手册

发版入口：在 `main` 的合并提交上打 `vX.Y.Z` tag 并 push。`.github/workflows/release.yml`
负责校验、签名构建三个 split APK、生成版本说明初稿并创建 **draft** Release；
人工核对并 publish。非 `main` 分支上的 tag 只构建、不发布。

工作流细节与决策见 `.scratch/android-release-ci/`。

## 一次性准备

### 1. 生成 release keystore

只在首次发版前做一次。生成后不要重新生成，也不要用同名新文件覆盖。

```bash
mkdir -p ~/keystores && chmod 700 ~/keystores
keytool -genkeypair -v \
  -keystore ~/keystores/seekchat-release.p12 \
  -storetype PKCS12 \
  -alias seekchat \
  -keyalg RSA -keysize 4096 -sigalg SHA256withRSA \
  -validity 10000 \
  -dname "CN=SeekChat, OU=Android, O=Transon Top, C=CN"
chmod 600 ~/keystores/seekchat-release.p12
```

- PKCS12 的 key password 必须与 store password 相同，只维护一个密码。
- 密码用长随机字母数字串，避开 `\`、`:`、`=`、`#`、`!`。
- 密码只放密码管理器，另留一份离线恢复码；仅你本人持有。

### 2. 本机 key.properties

`android/key.properties` 已被忽略，不入库。内容：

```properties
storeFile=/Users/transon/keystores/seekchat-release.p12
storePassword=<password>
keyAlias=seekchat
keyPassword=<password>
```

没有该文件或 keystore 不存在时，release 构建立即失败；debug 构建不受影响。

### 3. 加密备份与恢复演练

- 两份加密备份放不同物理介质、不同地点；密码管理器再存一份附件。
- 备份就是同一个 `.p12` 文件，签名身份与机器无关；另一台机器放仓库外副本并改
  `key.properties` 指向它即可。
- 恢复演练：用备份副本构建一次 release，核对证书指纹：

  ```bash
  ./tool/build_android_apk.sh
  apksigner verify --print-certs \
    build/app/outputs/flutter-apk/SeekChat-arm64-v8a-release.apk
  ```

  记下 `SHA-256 digest`（填入 07 票备查）。它不是秘密，用于以后核对 CI 产物签名。
  `apksigner` 在 `$ANDROID_HOME/build-tools/<版本>/apksigner`；本机没有 Java 时先设
  `JAVA_HOME`。

### 4. GitHub environment 与 secrets

在仓库 Settings → Environments 建 `release`：

- Deployment branches and tags：只允许 `v*` tag，**不要**勾选分支。
- Environment secrets 只加两个：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`。
  alias `seekchat` 已硬编码在工作流，不设 `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`。

生成 base64（直接复制到剪贴板，不要写入仓库文件）：

```bash
base64 -i ~/keystores/seekchat-release.p12 | tr -d '\n' | pbcopy
```

keystore 与密码另存一份到密码管理器。

### 5. 规则集与仓库设置

- `main` 规则集：禁止 force push、禁止删除（单人开发不强制 PR）。
- `refs/tags/v*` 规则集：禁止更新、禁止删除。**先完成 6 的测试 tag 演练再开启**，
  否则测试 tag 无法删除。
- 规则集与经典分支保护在私有 Free 仓库不可用（API 返回 403，需 GitHub Pro
  或仓库公开）。仓库公开后立即补上；开启顺序仍是先删测试 tag、再开 tag 保护。
- 开启 **immutable releases**（Settings → General 或 Releases 设置）。
- Actions 默认权限设为只读；workflow 已按 job 最小化声明。
- 第三方 action 全部固定完整 commit SHA；升级时同时改版本注释并重跑发版工作流。

## 版本号与 tag 规则

- `pubspec.yaml` 的 `version: x.y.z+n` → Android `versionName=x.y.z`、`versionCode=n`。
- tag 必须是 `vX.Y.Z`，且 `X.Y.Z` 与 `pubspec.yaml` 完全一致。
- `+n` 必须严格大于上一个可达 `v*` tag 所在提交的 `+n`；第一个 tag 跳过该检查。
- split APK 的实际 versionCode = ABI 编号 × 1000 + n（arm32=1、arm64=2、x86_64=4）。
- 暂不引入 rc / beta；需要时先补 tag 规则再使用。
- 现有历史 tag 已清空（2026-11-25 核对远端为空）；正式发布从 `v1.0.0` 起。

本地可预检（任意脚本可先跑）：

```bash
./tool/ci/check_release_version.sh v1.0.0
```

## 发版流程

### 0. 前置检查

```bash
git fetch --tags
git tag -l 'v*'                 # 确认测试 tag 已删、旧 tag 为空
git switch main && git pull --ff-only
```

- `release` environment 两个 secret 存在。
- 签名指纹已记录，备份可用。
- 上次发版后是否改过签名材料；改过则必须先解决，不能直接发版。

### 1. 在发布分支最后一次提交 bump 版本

```bash
git switch -c chore/release-1.0.0
# 编辑 pubspec.yaml：version: 1.0.0+1
git add pubspec.yaml
git commit -m "🔧 chore(release): 发布 v1.0.0"
./tool/ci/check_release_version.sh v1.0.0   # bump 之后、打 tag 之前跑
git push origin chore/release-1.0.0
```

只改 `pubspec.yaml`，不提交 `CHANGELOG.md`（本仓库不维护该文件）。合并前在本地跑
`./tool/ci/local_checks.sh`（推送前钩子也会自动执行）。本地版本校验依赖完整 tag
历史，换过 clone 时先 `git fetch --tags`。

### 2. 生成版本说明初稿（可选，发布后也可在 draft 里改）

```bash
git cliff --config cliff.toml --unreleased --tag v1.0.0 > /tmp/release-notes-v1.0.0.md
```

未安装 git-cliff：`brew install git-cliff`，或从
<https://github.com/orhun/git-cliff/releases> 下载 2.14.2。
初稿只给结构与技术条目；最终说明按下面约定人工改写：面向用户、中英双语、
中文在前、分「新增 / 修复 / 改进 / 破坏性变更」、每版 10 条以内。

### 3. 合并到 main 并打 tag

```bash
git switch main && git pull --ff-only
git merge --no-ff chore/release-1.0.0 -m "Merge chore/release-1.0.0 into main for v1.0.0"
git push origin main
git tag v1.0.0
git push origin v1.0.0
```

必须用 merge commit，不要 squash / fast-forward；tag 打在 `main` 的合并提交上。

### 4. 核对 draft Release

```bash
gh run watch                    # 构建约 6–20 分钟
gh release view v1.0.0          # 应显示 draft
```

- 资产：`SeekChat-arm64-v8a-release.apk`、`SeekChat-armeabi-v7a-release.apk`、
  `SeekChat-x86_64-release.apk`、`SHA256SUMS`，共四个。
- 不提供 universal APK。
- Release body 是 git-cliff 初稿；改成中英双语、中文在前、10 条以内、面向用户。
  技术细节不要放进 Release body。
- 构建失败时不会创建 Release；修好后见「失败处置」。

### 5. 安装验证

```bash
mkdir -p /tmp/seekchat-v1.0.0
gh release download v1.0.0 --dir /tmp/seekchat-v1.0.0
cd /tmp/seekchat-v1.0.0
sha256sum -c SHA256SUMS          # macOS: shasum -a 256 -c SHA256SUMS
apksigner verify --print-certs SeekChat-arm64-v8a-release.apk
```

- 指纹必须与一次性准备中记录的 `CN=SeekChat` 指纹一致。
- 真机安装、覆盖升级、启动与核心聊天流程可用。
- **已装 debug 签名包的设备必须先卸载**，否则无法安装正式签名包。

### 6. Publish

```bash
gh release edit v1.0.0 --draft=false
```

或在 Release 页面点 Publish。只有确认资产与说明无误后才 publish；publish 后
immutable releases 会锁定 tag 与资产，不能再改。

### 7. 发布后验证

- Release 显示为 latest，四个资产可下载。
- 下载后 `sha256sum -c` 一致，签名指纹正确。
- 用发布页链接实际安装一次。
- 需要时把版本说明同步到外部渠道（本项目暂无应用商店发布）。

## 失败处置

| 现象 | 处置 |
| --- | --- |
| tag 与 `pubspec.yaml` 不一致 | 本地修正后 **bump 到下一个补丁版本** 重新打 tag；已开启的 tag 规则集禁止重打同一 tag。 |
| `+n` 未递增 | 同上：改 `+n`（必要时升补丁版本），在发布分支提交后重新合并、打新 tag。 |
| 缺少 signing material | 检查 `release` environment 的两个 secret 与 tag 是否匹配 `v*`；补好后重跑 workflow（同一 tag）。 |
| draft 不出现 | 看 build job 的 `on_main` 输出是否为 `true`；tag 不在 `main` 祖先链时只构建不发布。 |
| 构建中途失败 | 修代码后 bump 补丁版本打新 tag；未创建 Release，不会留下半成品。 |
| 重复运行同一 tag | 构建可重复；Release 已存在时只更新资产，不覆盖人工编辑的说明。 |

规则集开启后不要为了复用 tag 临时放开删除权限，除非确认该 tag 从未被下载过。
常规做法永远是发新补丁版本。

## 回滚与补丁发版

- 已 publish 的 Release 与 tag 受 immutable releases 保护，不能改资产、删 tag 或重打。
- 有问题的版本：在发布分支修复 → bump 补丁版本（如 `1.0.1+2`）→ 合并 `main`
  → 打 `v1.0.1` → 走同一流程创建 draft、验证后 publish。这是唯一可复用的回滚路径。
- 若问题仅限说明文案，可在 Release 页面编辑说明（不改资产）；tag 保持不动。
- 紧急下线：删除外部渠道的下载链接，同时尽快发布补丁版本。

## 首次 v1.0.0 额外注意

- 旧 tag 已清空，git-cliff 初稿会覆盖全部历史；需要人工精选到 10 条以内。
- 首次发布前完成测试 tag 演练：在一个未合并到 `main` 的提交（如发布分支）上打
  一个与当前 `pubspec` 一致的 tag（当前为 `v0.5.0`，`+1`，且无上一个 tag），
  确认 Actions 构建成功但 `on_main=false`、没有创建 Release，然后删除该 tag。
  **演练必须在开启 `refs/tags/v*` 规则集之前完成。**
- 若所选提交已经在 `main` 祖先链上（例如刚合并过），演练 tag 会被判定为可发布；
  换一个未合并的提交或临时提交再演练。
- 首次安装正式签名包前卸载 debug 签名包。
