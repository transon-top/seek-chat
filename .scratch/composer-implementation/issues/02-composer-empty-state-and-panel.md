# 02: 输入卡、空态与内联附件面板

**What to build:** 聊天页底部输入区改成参考截图形态：输入卡常驻底部，空态问候语
在剩余区域居中；占位文案随附件与文本切换；右侧按钮按状态矩阵显示 `+`、麦克风、
发送 / 停止；`+` 展开输入卡下方的内联面板，面板含拍照 / 相册 / 文件三宫格，选择
结果进入草稿附件行并开始上传。没有照片横条（下一票补）。

**Blocked by:** 01
**Status:** resolved
**Type:** task

- [x] 空态与有消息状态共用同一输入卡实例，输入卡始终贴底；问候语「嗨! 今天想聊些什么?」
      在顶部栏底部到输入卡顶部的剩余区域内垂直居中，键盘弹出后在缩小区域继续居中，
      剩余高度小于 96 时隐藏，首条消息发出后 150ms 淡出。
- [x] 占位两态：无附件且文本为空显示「发消息或按住说话」；有附件且文本为空显示
      「发消息」；文本非空不显示。
- [x] 按钮顺序固定为 `+` → 麦克风 → 发送 / 停止；有文本时麦克风隐藏；无文本有附件
      时三者共存；生成中 `+` 禁用、发送变停止、无麦克风；朗读中麦克风显示但禁用；
      无 API Key 时麦克风与发送可点并提示 `errorNoApiKey`。
- [x] 点 `+` 输入框失焦、键盘收起、面板展开，`+` 以 180ms 交叉淡入 + 90° 旋转变 `×`；
      点 `×`、点输入框、Android 返回键收起；面板展开 220ms、收起 180ms；展开时点
      麦克风先收面板；发送后收起面板，无文本时保持展开。
- [x] 面板挂在输入卡下方、不覆盖消息区；高度由内容决定，横屏或屏高不足时最大
      45% 屏高并内部滚动。
- [x] 三宫格：拍照（相机单张）、从相册选择（多选，`limit = 50 - 当前草稿数`）、
      选择文件（任意类型多选）。Android 13–15 使用系统 Photo Picker。
- [x] 相机 / 相册产物嗅探 JPEG，非 JPEG 提示 `photoUnreadable` 且不加入草稿；
      文件沿用既有白名单、数量与大小校验。取消选择不产生变化；返回后面板保持展开、
      键盘保持收起、焦点不移动；成功结果追加到草稿行并开始上传。
- [x] 草稿已有 50 个时，拍照与相册入口点击提示 `uploadMaxFiles`，不打开系统界面。
- [x] 新增 / 改值 ARB：`composerHint`、`composerHintWithAttachments`、
      `addAttachment`、`closeAttachmentPanel`、`takePhoto`、`photoUnreadable`；
      重跑 `flutter gen-l10n`。
- [x] 测试覆盖：占位两态、按钮矩阵逐行、`+` / `×`、面板开合与返回键、三宫格数量
      上限、非 JPEG 拒绝；更新既有输入区与 App 测试。

## Answer

- 输入卡改为单实例贴底：`chat_page.dart` 的 `composer` 移出空态 Column，空态用
  `_EmptyGreeting`（`LayoutBuilder` 中 `<96` 隐藏）+ `AnimatedSwitcher` 150ms。
- 占位两态接在 `composerHint` / 新增 `composerHintWithAttachments`；编辑框改用
  `composerPlaceholder`，避免"按住说话"文案进编辑态。
- 按钮矩阵：`_PlusButton` 在生成中 / 语音忙碌时禁用；有文本隐藏麦克风；发送条件
  保持 `内容 + 全部 done + 非语音忙碌`。无 Key 时 `+`、麦克风、发送仍可点，提示沿用
  既有 `errorNoApiKey`。
- 面板：`attachment_panel.dart` 三宫格（88 高 / 圆角 16 / 间距 8），`AnimatedSize`
  展开 220ms、收起 180ms，最大 45% 屏高内部滚动；`+` / `×` 180ms 交叉淡入 + 90° 旋转。
  入口在面板层拦截 50 个上限，提示 `uploadMaxFiles`。
- 相机 / 相册走 `image_picker`（Android 13–15 显式开系统 Photo Picker），产物由
  `photo_import.dart` 嗅探 JPEG；非 JPEG 提示 `photoUnreadable` 且不入草稿。文件沿用
  `file_picker` 多选与既有白名单 / 大小 / 数量校验。
- 焦点与返回：`+` 失焦并收键盘；输入框获得焦点收面板；`PopScope` 在面板展开时
  先收面板。
- 验证：`flutter analyze` 无问题；`flutter test` 426 通过；
  `flutter build apk --debug` 与 `flutter build ios --debug --no-codesign` 均成功。
- 备注：相机 / 相册产物暂保留系统文件名与 `image/jpeg`；票 03 统一 `.jpg` 命名与
  HEIC 转码。`image_picker_android`、`image_picker_platform_interface` 已显式声明。
