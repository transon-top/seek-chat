# 03: 照片横条与权限降级

**What to build:** 面板顶部加入设备最近照片横条。用户可直接点照片选中并上传，
再点取消；权限未决定、拒绝、受限、空图库与读取失败都在横条原位降级，三宫格始终
可用。Android 可用构建开关关闭横条。

**Blocked by:** 01, 02
**Status:** resolved
**Type:** task

- [x] 每次展开面板重新查询最近 30 张图片，`createDate` 倒序、排除视频，按 200×200
      解码；面板展开期间不自动刷新；首次加载显示 6 个等高铁灰骨架。
- [x] 照片格 80×80、圆角 12、间距 8；选中显示主色圆底白勾并压暗图片；选中态由
      草稿附件的 `sourceAssetId` 派生，同一资产不可重复加入。
- [x] 选中即转码为 JPEG（质量 90、长边 ≤2560）、追加到草稿行末尾并上传；再次点
      缩略图或点草稿卡移除徽标即取消，上传中则取消排队 / 在途任务并丢弃迟到结果；
      上传失败不回退勾选，失败只在草稿卡表达。
- [x] 草稿已有 50 个时，未选照片格降为 50% 不透明度，点击提示 `uploadMaxFiles`；
      已选中的仍可取消。
- [x] 权限每次展开检查，仅未决定时请求；面板立即展开，结果回来前显示骨架。
      拒绝：横条原位「无法访问照片」+「去设置」；受限：最左插入等高「管理」格，
      点击 `presentLimited` 返回后重载，可访问资产为 0 时只显示「管理」；
      空图库：「没有最近照片」；读取失败：「无法读取照片」+「重试」。
- [x] 从后台、系统设置或「管理」选择器返回时重新检查并重载，草稿行与勾选不变。
- [x] HEIC / 非 JPEG 资产一律转 JPEG：iOS 优先 `.file`，非 JPEG 回退
      `thumbnailDataWithSize`；Android 直接 `thumbnailDataWithSize`。输出仍非 JPEG
      提示 `photoUnreadable`，超过 64 MB 提示 `uploadMaxMBSize`，均不入草稿；
      草稿文件名 `.jpg`、mime `image/jpeg`。
- [x] `--dart-define=OPEN_CHAT_PHOTO_STRIP=false` 在 Android 上不查询、不申请照片
      权限，面板只剩三宫格并按内容收缩；iOS 不受影响。
- [x] 新增 ARB：`photoPermissionDenied`、`photoLimitedManage`、
      `photoLimitedManageSemantics`、`photoStripEmpty`、`photoStripLoadFailed`。
- [x] 测试覆盖：30 张顺序、骨架、勾选与 `sourceAssetId` 派生、50 上限、权限四态、
      空图库与失败重试、转码单测（JPEG 直通、HEIC 转换、非 JPEG 拒绝、64 MB 上限、
      文件名与 mime）、取消选中丢弃迟到上传结果。

## Answer

- 新增 `lib/features/chat/photo_strip.dart`：`PhotoLibrary` 抽象 + `PhotoManagerLibrary`
  生产实现 + `PhotoStrip` widget。权限先 `getPermissionState`，仅未决定时
  `requestPermissionExtend`；读取 `type: image`、`onlyAll`、`createDate` 倒序、
  `getAssetListPaged(page: 0, size: 30)`。照片格 80×80 / 圆角 12 / 间距 8，
  骨架 6 个等高灰块；拒绝 / 受限「管理」格 / 空图库 / 读取失败均原位降级，
  回到前台与「管理」返回后重载。
- 选中态由草稿附件 `sourceAssetId` 派生；转码中再次点击即取消，迟到结果凭
  令牌丢弃；草稿已满 50 时未选照片格 50% 不透明度，点击提示 `uploadMaxFiles`，
  已选可取消。相机 / 相册 / 文件选择器打开期间挂起前台重载，返回后横条不刷新。
- 横条转码产生的临时文件在移除、发送、切会话与页面销毁时删除；上传失败保留
  草稿供重试。其余草稿原件沿用系统选择器临时目录，不额外清理。
- `photo_import.dart` 新增 `PhotoAsset`、`PhotoImportResult` 与
  `draftFromPhotoAsset`：iOS 优先 JPEG 原件，非 JPEG 回退
  `ThumbnailOption.ios`（`fit`，避免默认 AspectFill 裁方图）质量 90、长边
  ≤2560；Android 直接使用 `thumbnailDataWithSize` 转码字节。
  输出复制为 `<id>.jpg`、mime `image/jpeg`；非 JPEG → `photoUnreadable`，
  超过 64 MB → `uploadMaxMBSize`，均不入草稿。JPEG 原件按直通处理，不做重编码。
- `AttachmentPanel` 新增 `photoStrip` 插槽；`ChatPage` 在
  `photoStripEnabledFor(defaultTargetPlatform)` 为真时挂载。Android 以
  `--dart-define=OPEN_CHAT_PHOTO_STRIP=false` 构建时不查询、不申请照片权限，
  面板只剩三宫格并随内容收缩；iOS 不受开关影响。
- ARB 新增 `photoPermissionDenied`、`photoLimitedManage`、
  `photoLimitedManageSemantics`、`photoStripEmpty`、`photoStripLoadFailed`、
  `photoTileSelected`、`photoTileUnselected`；已重跑 `flutter gen-l10n`。
- 测试：新增 `test/features/chat/photo_strip_test.dart`（骨架、30 张顺序、
  权限四态、受限管理格与重载、空图库、失败重试、选中派生、50 上限、
  在前台重载与选择器期间挂起），扩展 `photo_import_test.dart`（JPEG 直通、
  HEIC 转码、Android 转码路径、非 JPEG 拒绝、64 MB 上限、文件名与 mime、
  转码取消令牌），扩展 `attachment_panel_test.dart`（横条插槽与收缩），并补
  上传任务「移除在途任务丢弃迟到成功」用例；共享 fake 在
  `test/support/photo_fakes.dart`。
- 验证：`flutter analyze` 无问题；`flutter test` 447 通过。
- 遗留：横条视觉、iOS fit 转码与真机权限 / HEIC 成功率按票 07 验收；
  `photo_manager` 真实排序依赖插件，单测只验证请求参数。
