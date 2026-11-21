# Map: 输入区改版（底部布局、按住说话、内联附件面板）

## Destination

一张决策完备、可直接交给实现会话的输入区改版规格：空态布局与问候语、占位文案、右侧按钮状态矩阵、按住说话（松手发送、上滑取消、录音浮层）、`+`/`×` 内联附件面板（设备最近照片横条 + 拍照/相册/文件）、草稿附件行样式；含照片库依赖与权限降级、HEIC 兼容、录音状态机、动画、测试与真机视觉验收口径。实现不在本图内，另开执行图。

## Notes

- 参考截图（微信临时目录已拷贝进本图 `evidence/`）：
  - `evidence/01-empty.jpg` 空态：占位「发消息或按住说话」，右侧 `+` 与麦克风；问候语居中，无 logo。
  - `evidence/02-typed.jpg` 有文本：右侧 `+` 与蓝色发送，麦克风隐藏。
  - `evidence/03-panel.jpg` 面板展开：`+` 变 `×`，输入卡下方是设备照片横条 + 拍照/相册/文件三宫格。
  - `evidence/04-voice-overlay.jpg` 按住说话：屏幕下方蓝色渐变浮层、「松手发送，上滑取消」、波形条。
  - `evidence/05-drafts.jpg` 草稿附件行：图片缩略图与文件卡单行横滑，右上角白色圆形 `×`；有附件时占位变「发消息」；`×`/麦克风/发送三按钮共存。
- 已确认的行为决议（本图第一、二轮 grilling）：
  - 终点 = 决策与规格；实施另开执行图。
  - 输入卡常驻底部；空态问候语在剩余区域垂直居中；不加 logo；保留现有问候文案「嗨! 今天想聊些什么?」，不做时段问候。
  - 按钮矩阵：无文本无附件 → `+`、麦克风；有文本 → `+`、发送（附件不影响）；无文本有附件 → `+`、麦克风、发送；生成中 → `+`、停止；转写中 → 发送槽加载圈（点击取消）；面板展开时 `+` 变 `×`；录音中浮层覆盖按钮。
  - 占位文案：无附件「发消息或按住说话」；有附件「发消息」；文本非空时不显示。
  - 按住说话：按下即录；松手 → 停止 → 转写 → 成功后自动发送；上滑超过 80dp 取消并丢弃录音；转写失败/空结果不发送；120 秒上限自动转写并发送；权限、无设备、Key 缺失沿用现有 Toast。
  - 附件面板：`+` → `×`、收起键盘，面板在输入卡下方展开；最近照片横条约 30 张、最新优先、不含视频、横向滚动；照片点击选中即加入草稿附件行并上传，再点取消选中并移除草稿（取消排队中的上传）；面板选完保持展开；`×` 或点输入框收起。
  - 草稿附件行：单行横滑（图片 64、文件卡 210）；移除徽标移入卡片内右上角；文件图标改为带扩展名配色的色块；保留上传中/失败/重试覆盖层。
- 2026-11-21 票 06 原型确认：录音、识别、取消共用同一套蓝色动态浮层；蓝区由漂移团块构成动态不规则边缘，高光跟随按住位置，取消态不变红；识别中文案「识别中」，不提供取消。不引入渐变库，改用自绘 `CustomPainter`。
- 事实基线（2026-11-20 探查）：
  - 输入区 `lib/features/chat/composer.dart`；空态组合 `lib/features/chat/chat_page.dart:446-468`。
  - 草稿附件行已单行横滑：`lib/features/chat/attachments_view.dart:41-85`。
  - 语音为「点击开始、再点结束」：`lib/features/chat/speech/speech_controller.dart:176-190`。
  - 依赖无 `image_picker` / `photo_manager`；iOS 仅声明麦克风权限，Android 无媒体权限。
  - `attachments.md` §1 明确「不引入 image_picker；不实现拍照」，本图推翻该条，由票 07 回写。
- 规格回写范围：`ui.md` §1.3/§5.2/§5.8、`speech.md` §2/§3/§7、`attachments.md` §1/§7、`GLOSSARY.md` 的 Voice Input。
- 视觉验收以截图对图为准；深/浅色都要过；iOS 与 Android 真机都看。
- 每个会话先读 `GLOSSARY.md` 与 `docs/agents/domain.md`；按需调用 grilling、domain-modeling、prototype、research。
- 执行入口：本目录 `spec.md`（决策完成后的实现规格）；回写后的权威段落见
  `ui.md` §1.3/§5.2/§5.7/§5.8、`speech.md` §3、`attachments.md` §1/§9。

## Decisions so far

<!-- 每个已关闭的票一行：票名 + 一句话结论。详细答案在票内。 -->

- [按住说话交互与 record 能力调研](issues/02-research-hold-to-talk.md): 手势用 `Listener` + pointer id + 全局 `dy ≤ -80`，不用长按手势（500 ms 延迟 + 取消后状态悬挂）；`toggleVoiceInput` 不能承接松手（转写中会误取消），需显式 `start/finish/cancel` 与 `_starting` 单飞；首次权限弹窗会让 pointer cancel 且无 PointerUp；`stop()` 返回路径不删文件、`cancel()` 尽力删除；电平约 10 Hz dBFS，浮层复用 `level` 做缓动；无障碍只能 tap 切换，长按无语义等价。
- [照片横条与相机/相册依赖调研](issues/01-research-photo-picker.md): 选 `photo_manager 3.12.0`（横条分页/缩略图/资产落地）+ `image_picker 1.2.4`（拍照/系统相册）；HEIC 一律嗅探后转 JPEG（iOS `.file` 已是 JPEG，Android 用 `thumbnailDataWithSize`）；iOS limited 用 `PhotoManager.presentLimited`；Android 13–15 用系统 Photo Picker 需显式开 `useAndroidPhotoPicker`；最大风险是 Google Play `READ_MEDIA_IMAGES` broad-access 审核，被拒则 Android 去横条。
- [空态布局、按钮矩阵与附件面板](issues/03-grilling-panel-and-states.md): 空态与有消息复用同一底部输入卡，问候语居中、剩余高度 <96 隐藏；占位只看附件与文本；按钮矩阵逐状态落表（有文本隐藏麦克风，转写槽加载圈可取消，无 Key 可点弹提示）；`+`↔`×` 180ms、面板 `AnimatedSize` 220ms、Android 返回先收面板；面板高度固定、失败只在草稿行表达；减少动画时过渡归零。票 06 后转写中改为蓝色浮层，加载圈取消。
- [照片横条数据、选择与权限降级](issues/04-grilling-photo-strip.md): 固定 30 张、每次展开刷新；勾选以草稿 `sourceAssetId` 为真相，主色圆底白勾 + 图片压暗；选中即转码上传，取消即移除并丢弃在途结果；展开时检查权限，limited 放「管理」格、denied 原位给「去设置」；横条照片统一转 JPEG、长边 2560、质量 90；拍照/相册走系统界面且不回写勾选；Android 默认保留横条，Play 被拒时用 `OPEN_CHAT_PHOTO_STRIP=false` 构建关闭。
- [按住说话状态机与浮层行为](issues/05-grilling-hold-to-talk.md): 按下即显示浮层骨架并单飞启动；首次授权不自动开录、提示再按住，短按静默取消；松手 → 转写 → 先插入输入框再尝试自动发送，不满足条件就留文本加 Toast；上滑 80dp 以按下全局坐标为基准、可回拉、仅纵向；浮层贴底蓝渐变、盖输入卡不盖顶部栏，录音中收键盘且输入卡不可编辑（覆盖票 03 同句的录音一半）；录音中返回键先取消录音；无障碍改为语义 tap 切换 + 「取消录音」自定义动作。票 06 后识别中保留浮层（「识别中」），取消态复用同一蓝色动态效果；识别中不提供取消。
- [输入区视觉对图原型](issues/06-prototype-visual.md): 原型通过；iPhone + Android 各 10 状态 × 深浅；输入卡保持两行高度；录音/识别/取消共用动态蓝色浮层（漂移团块 + 按住位置高光，取消不变红）；识别中显示「识别中」且不提供取消；不引依赖，自绘 `CustomPainter`。
- [规格回写与验收清单](issues/07-task-spec-assembly.md): 8 项回写完成——`ui.md`（结构/矩阵/面板/浮层/文案/验收）、`speech.md`（按住说话状态机/自动发送/浮层/测试）、`attachments.md`（推翻旧选型，补面板/photo_manager/image_picker/HEIC/权限）、`GLOSSARY.md`（Voice Input 改义 + 6 个新术语）；26 个新 ARB 键 + 2 个改值 + 5 个删除；测试与真机验收清单、回滚点写入 [spec.md](spec.md)。

## Not yet specified

- 无。原「Android 预测性返回下，面板与输入法的收起顺序」已转为 `spec.md`
  §7 / §9 的实现期验收项，不再是待决策问题。

## Out of scope

- 推荐问句胶囊行（截图中的「这是什么 → / 分析一下 → / 怎么办 →」）。
- logo 与时段问候。
- 图片生成、最近生成图与图片再编辑。
- 拖拽、粘贴附件。
- 桌面 / Web。
- 实施落地本身（另开执行图）。
- 流式语音识别与实时字幕。
