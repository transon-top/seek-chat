# 输入区改版规格（决策完成，供执行图使用）

状态：`.scratch/composer-redesign` 全部决策票已关闭；本文是执行图的唯一入口。
来源：本图票 01–06（答案在各自票内），回写到 `ui.md`、`speech.md`、
`attachments.md`、`GLOSSARY.md` 的段落已同步。实现不在本图内。

## 1. 目标与非目标

**目标**：把聊天输入区改成参考截图的形态：

- 输入卡常驻底部；空态问候语在剩余区域居中，剩余高度 <96 隐藏。
- 右侧按钮矩阵：`+`、麦克风、发送 / 停止；有文本时麦克风隐藏。
- 按住说话：按下即录、松手转写并尝试发送、上滑 80dp 取消、蓝色动态浮层。
- `+` / `×` 内联附件面板：设备最近照片横条 + 拍照 / 相册 / 文件三宫格。
- 草稿附件行改为单行横滑、卡片内移除徽标、扩展名色块图标。

**非目标**：推荐问句胶囊、logo 与时段问候、图片生成与再编辑、拖拽 / 粘贴附件、
桌面 / Web、流式语音识别与实时字幕、草稿跨页面 / 进程持久化。

## 2. 依赖与平台配置

```yaml
dependencies:
  photo_manager: ^3.12.0
  image_picker: ^1.2.4
  image_picker_android: <跟随 image_picker>
  image_picker_platform_interface: <跟随 image_picker>
  # 既有：file_picker 13.4.0 只保留「选择文件」
```

- iOS `Info.plist`：
  - `NSPhotoLibraryUsageDescription`
  - `NSCameraUsageDescription`
  - `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = true`
- Android `AndroidManifest.xml`：
  - `READ_MEDIA_IMAGES`
  - `READ_MEDIA_VISUAL_USER_SELECTED`
  - `READ_EXTERNAL_STORAGE`（`android:maxSdkVersion="32"`）
- 构建开关：`--dart-define=SEEK_CHAT_PHOTO_STRIP=false` 只关闭 Android 照片横条
  及其权限申请；面板只剩三宫格，高度随内容收缩。
- 不新增动效 / 渐变库；浮层用 `CustomPainter` 自绘。

## 3. 实现落点

| 文件 | 改动 |
| --- | --- |
| `lib/features/chat/chat_page.dart` | 空态问候语布局与隐藏规则；`_addAttachments` 拆成面板入口；发送闸门保持 |
| `lib/features/chat/composer.dart` | `minLines: 1`、两态占位、按钮矩阵、`+`/`×`、面板挂载、`AnimatedSize` |
| `lib/features/chat/attachments_view.dart` | 草稿行单行横滑、64 / 210×64、卡片内徽标、色块图标、上传 / 失败覆盖层 |
| `lib/features/chat/attachment_panel.dart`（新增） | 面板壳、开合与键盘时序、返回键优先、三宫格 |
| `lib/features/chat/photo_strip.dart`（新增） | `photo_manager` 读取 / 骨架 / 勾选 / 权限四态 / 管理格 / 重试 |
| `lib/features/chat/photo_import.dart`（新增） | 横条资产与相机 / 相册产物转 JPEG、嗅探、失败与上限处理 |
| `lib/features/chat/speech/speech_controller.dart` | 显式 `startFromPress` / `finishFromRelease` / `cancelFromGesture`、`_starting` 单飞、先插入再尝试发送 |
| `lib/features/chat/speech/voice_button.dart` | `Listener` 按住手势、pointer id、80dp 阈值、触感、语义 tap / 自定义动作 |
| `lib/features/chat/speech/voice_overlay.dart`（新增） | 蓝色动态浮层、三文案、32 根波形、减少动画静态帧 |
| `lib/features/chat/speech/recording_status.dart` | 删除（被浮层取代） |
| `lib/shared/models/types.dart` | `DraftAttachment` 增加仅内存的 `sourceAssetId` |
| `lib/shared/models/types.dart` / 上传任务 | 横条取消选中时丢弃在途结果（沿用现有移除语义） |
| `lib/l10n/app_en.arb`、`app_zh.arb` | §5 的键；删除 §5 标记的废弃键；重跑 `flutter gen-l10n` |
| `lib/features/chat/chat_page.dart` / `composer.dart` | 无 API Key 时麦克风与发送提示 `errorNoApiKey` |

规格权威段落：`ui.md` §1.3 / §3.4 / §3.8 / §5.2 / §5.7 / §5.8 / §6.2 / §7 /
§8.1 / §8.2；`speech.md` §1–§3、§6.1、§7–§8、§10–§11；`attachments.md`
§1、§9、§10。本文与上述文档冲突时，以票 05、06 的覆盖关系为准（见 §4）。

## 4. 行为要点与覆盖关系

- 票 03 的「录音中开关可用」被票 05 / 06 覆盖：录音与识别期间浮层覆盖输入卡与
  草稿行，`+`、麦克风、发送、开关均不可见、不可操作。
- 票 03 / 05 的「转写中发送槽加载圈」被票 06 覆盖：识别中显示同一蓝色浮层，
  文案「识别中」，不提供取消；取消只来自后台、切会话、离开页面与销毁。
- 票 05 的「取消态转暖色 / 警示色」被票 06 覆盖：取消态不变色，只换文案。
- 转写成功：先插入输入框，再按发送闸门尝试发送；任一条件不满足只插入并 Toast，
  转写结果永不丢失（`speech.md` §3.4）。
- 首次麦克风授权：系统弹窗造成 pointer cancel 且无 PointerUp；授权后本次不开录，
  提示「已授权麦克风，请再按住说话」。

按钮矩阵、面板尺寸、浮层视觉、照片横条与权限降级的完整表格见
`ui.md` §5.2 / §5.7 / §5.8 与 `attachments.md` §9，不在本文重复。

## 5. 文案（ARB）

新增 / 改值：

| key | zh | en |
| --- | --- | --- |
| `composerHint`（改值） | 发消息或按住说话 | Message or hold to talk |
| `composerHintWithAttachments` | 发消息 | Message |
| `addAttachment` | 添加附件 | Add attachment |
| `closeAttachmentPanel` | 收起附件面板 | Close attachment panel |
| `holdToTalk` | 按住说话 | Hold to talk |
| `takePhoto` | 拍照 | Take photo |
| `photoPermissionDenied` | 无法访问照片 | Can't access photos |
| `photoLimitedManage` | 管理 | Manage |
| `photoLimitedManageSemantics` | 管理可访问照片 | Manage accessible photos |
| `photoStripEmpty` | 没有最近照片 | No recent photos |
| `photoStripLoadFailed` | 无法读取照片 | Couldn't load photos |
| `photoUnreadable` | 无法读取这张照片 | Couldn't read this photo |
| `photoTileSelected` | 照片，第 {index} 张，已选 | Photo {index}, selected |
| `photoTileUnselected` | 照片，第 {index} 张，未选 | Photo {index}, not selected |
| `voiceHoldToSend` | 松手发送，上滑取消 | Release to send, slide up to cancel |
| `voiceReleaseToCancel` | 松开取消 | Release to cancel |
| `voiceRecognizing` | 识别中 | Recognizing |
| `voiceMicGrantedRetry` | 已授权麦克风，请再按住说话 | Microphone access granted. Hold to talk again. |
| `voiceRecordSemantics` | 录音中，双击结束并发送 | Recording. Double-tap to finish and send. |
| `voiceCancelRecording` | 取消录音 | Cancel recording |
| `voiceCancelled` | 已取消 | Recording cancelled |
| `voiceRecognizingSemantics` | 正在识别 | Recognizing speech |
| `voiceSendFailedInserted` | 发送失败，已放入输入框 | Couldn't send. The text is in the message field. |
| `voiceInsertedGenerating` | 生成中，转写内容已插入输入框 | Generating. Transcription inserted. |
| `voiceInsertedUploading` | 附件上传中，转写内容已插入输入框 | Attachments uploading. Transcription inserted. |
| `voiceInsertedNotSent` | 转写内容已插入输入框，未自动发送 | Transcription inserted. Not sent automatically. |

`photoTile*` 的 `{index}` 从 1 起，在模板声明 placeholder。

删除：`voiceInput`、`voiceInputRecording`、`voiceInputStop`、
`voiceInputTranscribing`、`voiceInputCancel`。

复用：`errorNoApiKey`、`retry`、`settingsOpenSystemSettings`、`uploadMaxFiles`、
`uploadMaxMBSize`、`uploadFromPhotos`、`uploadFromFiles`、`removeAttachment`、
`voiceInputPermissionDenied`、`voiceInputNoDevice`、`voiceInputFailed`、
`voiceInputEmpty`、`voiceInputLimitReached`、`voiceInputInterrupted`。

## 6. 测试清单

### 6.1 现有测试改动

- `test/features/chat/composer_test.dart`：占位两态与文本非空隐藏；按钮矩阵逐行；
  `minLines: 1`（官方窄屏约 1.25 行高）、输入框下缘到按钮行 16；
  `+`/`×` 切换；面板开合与点输入框收起；无 Key 提示。
- `test/features/chat/attachments_view_test.dart`：单行横滑、图片 64 / 文件卡 210×64、
  卡片内移除徽标、扩展名色块、上传中 / 可重试 / 不可重试覆盖层。
- `test/features/chat/speech/speech_controller_test.dart`：
  `idle → starting → recording → transcribing → idle`；松手早于 start 的取消；
  连按单飞；首次授权不开录；上滑阈值纯函数；cap 后松手 no-op；
  自动发送闸门与各 Toast；后台 / 切会话取消。
- `test/features/chat/speech/speech_widgets_test.dart`：浮层三文案、波形静态骨架、
  语义 tap 与「取消录音」动作、减少动画冻结。
- `test/features/chat/upload_tasks_test.dart`：取消选中丢弃在途结果（沿用现有用例，
  补横条来源附件）。

### 6.2 新增测试

- 照片横条 widget 测试（注入 fake asset provider）：30 张顺序、骨架、勾选与
  `sourceAssetId` 派生、50 上限置灰、空图库 / 读取失败 / 拒绝 / 受限「管理」格。
- 转码单测：JPEG 直通、HEIC 走 `thumbnailDataWithSize`、输出非 JPEG 拒绝、
  64 MB 上限、mime 与文件名 `.jpg`。
- 面板交互：展开 / 收起时长与曲线、Android 返回优先收面板、横屏 45% 内部滚动、
  生成中按钮禁用、录音中不可见。
- 集成测试（真机）：照片权限（允许 / 受限 / 拒绝）、相机、系统相册、系统文件选择器、
  按住 / 上滑 / 松手、来电中断、后台取消、浮层与输入法切换。
- 双语 × 深浅四组合的文本溢出检查（动态字体 2.0、320 宽）。

## 7. 真机视觉验收

对照 `prototype/composer_redesign/screenshots/`，iPhone 与 Android 各 10 状态 ×
深浅两套；原型通过项按票 06 的尺寸执行：

1. 空态：问候语居中、无 logo、输入卡圆角 28 / 1px 描边 / 无阴影。
2. 有文本：`+`、发送；麦克风隐藏。
3. 草稿：图片 64、文件卡 210×64、卡片内 20 徽标、36 色块、上传 / 失败覆盖。
4. 面板：照片格 80×80 / 间距 8、横条区 96、三宫格 88 / 圆角 16、面板间距 8。
5. 面板权限：拒绝、受限「管理」、空图库、读取失败原位提示。
6. 录音：蓝色漂移团块 + pointer 高光、文案「松手发送，上滑取消」、32 根波形。
7. 取消：同一蓝色效果 + 「松开取消」，不变红。
8. 识别中：浮层保留、低幅波形、「识别中」、无取消入口。
9. 生成中：`+` 禁用、发送变停止、无麦克风。
10. 深 / 浅色、iPhone 17 Pro 402pt 与 Android 411pt 无溢出。

另需人工确认：Android 预测性返回下「先收面板、再退页面」的顺序；输入法与面板
同时收起的空窗；iOS 受限授权后「管理」返回重载；HEIC 照片转码成功率与方向。

## 8. 回滚点

- 无数据库迁移、无持久化字段新增：草稿与 `sourceAssetId` 只在内存，
  回滚不丢用户数据；已发送附件与消息不受影响。
- Android 横条：构建开关 `SEEK_CHAT_PHOTO_STRIP=false` 即可关闭，无需回滚代码。
- 代码回滚：按 §3 的文件分组 revert；`recording_status.dart` 的删除与
  `voice_overlay.dart` 的加入同组回滚，ARB 与生成物一起回滚。
- 语音回归：若新状态机阻塞发布，可先回滚 `speech_controller.dart` /
  `voice_button.dart` / `voice_overlay.dart` 并恢复旧 `recording_status.dart`，
  输入区其余改动可独立保留（面板、草稿行、空态互不依赖）。

## 9. 风险与已知限制

1. Google Play `READ_MEDIA_IMAGES` broad-access 审核可能被拒；被拒走 §2 构建开关。
2. Android HEIC 解码不一致；转码失败按 `photoUnreadable` 拒绝，成功率需真机验证。
3. 首次授权 pointer cancel 行为需 iOS / Android 真机各验一次。
4. `Listener` 不参与 gesture arena；输入区若将来进入滚动父级需改 `RawGestureDetector`。
5. 进程被回收时不恢复草稿、勾选与系统选择器状态（`retrieveLostData` 不做）。
6. 面板 / 输入法 / 预测性返回的收起顺序列为实现期验收项，不阻塞规格。
7. 录音与朗读的音频会话切换仍需真机验证（`speech.md` §12）。
