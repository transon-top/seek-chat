# 票 07 Android 真机验收证据

- 日期：2026-11-22
- 设备：vivo V2608DA（产品 PD2608），Android 17（API 37）
- 屏幕：1216×2660 物理，560 dpi（逻辑约 347×760 dp），系统字号 1.12
- 构建：`flutter build apk --debug`（HEAD `6eefa77`）；横条关闭项单独用
  `flutter build apk --debug --dart-define=OPEN_CHAT_PHOTO_STRIP=false`
- 主题：应用内设置切换浅 / 深色，未改系统夜间模式

## 截图索引

| 文件 | 状态 |
| --- | --- |
| `launch.png` | 浅色空态：`+` / 语音两个 28 描边圆，无发送 |
| `typed-light.png` / `typed-dark.png` | 有文本：语音隐藏、发送 40 实心占位 |
| `typed-light-keyboard.png` | 输入法聚焦态 |
| `panel-light.png` | 浅色面板（照片权限拒绝横条 + 三宫格） |
| `panel-limited-light.png` | 受限访问：管理卡 + 3 张照片 + 三宫格 |
| `panel-full-light.png` | 完全访问：照片横条 + 三宫格 |
| `panel-dark.png` | 深色面板（完全访问） |
| `panel-denied-dark.png` | 深色面板拒绝横条 |
| `panel-photo-strip-off.png` | `OPEN_CHAT_PHOTO_STRIP=false`：只剩三宫格，未申请照片权限 |
| `draft-image-light.png` / `draft-file-light.png` | 草稿：图片 / PDF + 失败原因 |
| `draft-no-text-light.png` | 无文本有附件（上传失败）：`+` / 语音 / 发送共存，发送禁用 |
| `draft-file-uploaded-light.png` | 附件全部 done：发送可用（ui.md §5.2） |
| `album-picker.png` | 系统照片选择器（Android Photo Picker） |
| `file-picker.png` | 系统文件选择器（SAF） |
| `camera-step1.png` / `camera-permission.png` | 相机（系统相机 Intent）与返回后界面 |
| `recording-light.png` / `recording-dark.png` | 录音浮层「松手发送，上滑取消」 |
| `cancelling-light.png` / `cancelling-dark.png` | 取消态「松开取消」 |
| `transcribing-light.png` / `transcribing-dark.png` | 识别中浮层 |
| `busy-light.png` / `busy-dark.png` | 生成中：`+` 禁用、发送变停止、无语音 |
| `panel-back-light.png` | 面板展开时返回键收面板（页面保留） |
| `panel-tap-input-dark.png` | 面板展开时点输入框：面板收起、键盘弹出 |
| `search-page-light.png` / `search-page-dark.png` | 会话搜索页 |
| `session-list-light.png` / `list-dark.png` | 会话列表 |
| `settings-light.png` / `settings-dark.png` | 设置页 |

注意：`album-picker.png`、`panel-full-light.png`、`panel-dark.png` 含相册缩略图
（个人照片），提交或分享前请先脱敏；目录当前未被 git 忽略。

## 实测结论

- 右栏按钮：`+` / `×` / 语音语义命中区 140×140 px（40 dp），发送 141×141 px；
  视觉 28 描边圆 / 40 实心圆与 ui.md §5.2 / §5.8 一致，深浅色对比正常。
- 空态发送收敛：无文本无附件不渲染发送；有文本发送占位、语音隐藏；面板展开
  `+`→`×`；生成中 `+` 禁用、发送变停止、无语音。
- 无文本有附件：上传中 / 失败时发送禁用；全部 done 时发送可用（ui.md §5.2
  表格），票 07 原描述「发送禁用」仅适用于上传中 / 失败。
- 面板返回键：先收面板，页面不退出（Android 返回键事件）。
- 搜索页返回：命中区实测 168×168 px（48 dp，Material 最小触控目标把 44
  撑到 48），与搜索框命中区相接、无间距；点返回正常回列表，未误触搜索框。
- 照片权限三态：受限（管理卡 + 3 张）、完全（横条）、拒绝（横条降级）
  均按规格显示；拒绝态左右无溢出。
- 相机 → 系统相机 → 确定 → 返回后草稿新增（附件在横向滚动行末尾，首屏
  不可见，需左滑）；照片未写入系统相册。
- 语音：按住 → 上滑 ≥80dp 进入「松开取消」→ 释放丢弃；静音录音识别结束
  提示「未识别到语音内容」；真实 ASR 通道可用。
- 真实请求：设置内已有掩码 API Key（非本次输入），发送 Hello / Hi 均流式
  返回并落库。
- 横条关闭构建：面板仅三宫格，无照片横条、无照片权限申请。

## 未覆盖 / 待人工

- iOS 真机（无设备）：iOS 10 状态对图、受限授权「管理」返回重载、HEIC。
- 预测性返回动画（系统手势导航 + `enableOnBackInvokedCallback` 未验证）；
  仅验证返回键顺序。
- 空图库、读取失败两种横条降级；HEIC 转码成功率与方向。
- 输入法与面板同时收起的空窗只能目测，截图无法定论。
- 402 / 411 dp 宽度对图：本机逻辑宽约 347 dp，比目标更窄，可作为溢出下界。

## 遗留状态

- 照片权限已恢复为「禁止」（安装前状态）。
- 麦克风权限测试后仍为「允许」（原为未授予），如需恢复请撤销
  `android.permission.RECORD_AUDIO`。
- 会话里留有一条测试消息（Hello / Hi）及调试样本；应用当前为默认 debug 构建。
