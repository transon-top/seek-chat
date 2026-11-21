# 规格回写与验收清单

Type: task
Status: resolved
Blocked by: 01, 02, 03, 04, 05, 06

## Question

把本图所有决议落成实现会话可直接执行的规格：

1. 回写 `ui.md`：输入区结构、空态布局、按钮矩阵、附件面板、草稿附件行、录音浮层；尺寸/颜色/动画。
2. 回写 `speech.md`：按住说话状态迁移、自动发送、取消、转写与中断、无障碍。
3. 回写 `attachments.md`：推翻「不引入 image_picker、不实现拍照」，补拍照/最近照片/HEIC/权限降级。
4. 更新 `GLOSSARY.md` 的 Voice Input 定义与新增术语（如「按住说话」「设备照片横条」）；只写领域语言，不写实现。
5. l10n key 清单与中英文案。
6. 测试清单：现有 `test/features/chat/composer_test.dart`、`speech_controller_test.dart`、`speech_widgets_test.dart` 的改动；新增手势、面板、草稿行、权限降级测试。
7. 真机视觉验收清单（iOS + Android，深/浅色）与回滚点。
8. 输出本图 `spec.md` 供执行图使用。

## Deliverable

更新后的规格文件 + 本图 `spec.md`；票内 Answer 摘要。

## Answer

2026-11-21 完成。只改文档，未改产品代码。

1. `ui.md`：§1.3 输入区结构与空态问候语；§3.4 尺寸、§3.8 动效；§5.2 按钮矩阵
   与两态占位（`minLines: 2`）；§5.7 草稿行与附件面板、照片横条、权限降级、
   HEIC、Android 构建开关；§5.8 按住说话与浮层；§6.2 语义、§6.4 减少动画；
   §7 文案；§8.1/§8.2 呈现；§9 现状差距；§10 验收。
2. `speech.md`：§1 决策摘要、§2.1 入口、§3 状态机与转移表（新增 `starting` /
   `cancelling`，先插入再尝试发送）、§5.1 首次授权、§6.1 错误、§7 浮层与波形、
   §8 文案、§10 落点、§11 测试、§12 风险。
3. `attachments.md`：§1 推翻「不引入 `image_picker`、不实现拍照」，补面板入口、
   依赖、拍照 / 相册 / 文件、权限与平台配置、HEIC、Android 分发；§3/§4/§7 同步；
   新增 §9 照片横条（数据、勾选、权限降级、缓存）与 §10 文案。
4. `GLOSSARY.md`：改 `Voice Input` 与 `Transcription`；新增 `Hold to Talk`、
   `Recording Overlay`、`Attachment Panel`、`Device Photo Strip`、
   `Draft Attachment Row`、`Photo Access`。
5. 文案：26 个新增键 + `composerHint` / `chatEmptyTitle` 改值；删除 5 个旧
   `voiceInput*` 键；中英表见 `ui.md` §7.2 与 `spec.md` §5。
6. 测试：现有 4 个测试文件的改动点 + 新增横条 / 转码 / 面板 / 真机集成测试，
   见 `spec.md` §6。
7. 真机视觉验收（iOS + Android × 深浅）：`spec.md` §7，对照
   `prototype/composer_redesign/screenshots/`；回滚点见 §8。
8. 执行图入口：`.scratch/composer-redesign/spec.md`。

覆盖关系按票 06 落定：录音 / 识别 / 取消共用蓝色浮层，识别中无取消；
录音期间浮层覆盖输入卡；取消态不变色。原「Not yet specified」的 Android
预测性返回收起顺序，转为 `spec.md` §7/§9 的实现期验收项。
