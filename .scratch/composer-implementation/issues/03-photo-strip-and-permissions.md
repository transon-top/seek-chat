# 03: 照片横条与权限降级

**What to build:** 面板顶部加入设备最近照片横条。用户可直接点照片选中并上传，
再点取消；权限未决定、拒绝、受限、空图库与读取失败都在横条原位降级，三宫格始终
可用。Android 可用构建开关关闭横条。

**Blocked by:** 01, 02
**Status:** ready-for-agent

- [ ] 每次展开面板重新查询最近 30 张图片，`createDate` 倒序、排除视频，按 200×200
      解码；面板展开期间不自动刷新；首次加载显示 6 个等高铁灰骨架。
- [ ] 照片格 80×80、圆角 12、间距 8；选中显示主色圆底白勾并压暗图片；选中态由
      草稿附件的 `sourceAssetId` 派生，同一资产不可重复加入。
- [ ] 选中即转码为 JPEG（质量 90、长边 ≤2560）、追加到草稿行末尾并上传；再次点
      缩略图或点草稿卡移除徽标即取消，上传中则取消排队 / 在途任务并丢弃迟到结果；
      上传失败不回退勾选，失败只在草稿卡表达。
- [ ] 草稿已有 50 个时，未选照片格降为 50% 不透明度，点击提示 `uploadMaxFiles`；
      已选中的仍可取消。
- [ ] 权限每次展开检查，仅未决定时请求；面板立即展开，结果回来前显示骨架。
      拒绝：横条原位「无法访问照片」+「去设置」；受限：最左插入等高「管理」格，
      点击 `presentLimited` 返回后重载，可访问资产为 0 时只显示「管理」；
      空图库：「没有最近照片」；读取失败：「无法读取照片」+「重试」。
- [ ] 从后台、系统设置或「管理」选择器返回时重新检查并重载，草稿行与勾选不变。
- [ ] HEIC / 非 JPEG 资产一律转 JPEG：iOS 优先 `.file`，非 JPEG 回退
      `thumbnailDataWithSize`；Android 直接 `thumbnailDataWithSize`。输出仍非 JPEG
      提示 `photoUnreadable`，超过 64 MB 提示 `uploadMaxMBSize`，均不入草稿；
      草稿文件名 `.jpg`、mime `image/jpeg`。
- [ ] `--dart-define=OPEN_CHAT_PHOTO_STRIP=false` 在 Android 上不查询、不申请照片
      权限，面板只剩三宫格并按内容收缩；iOS 不受影响。
- [ ] 新增 ARB：`photoPermissionDenied`、`photoLimitedManage`、
      `photoLimitedManageSemantics`、`photoStripEmpty`、`photoStripLoadFailed`。
- [ ] 测试覆盖：30 张顺序、骨架、勾选与 `sourceAssetId` 派生、50 上限、权限四态、
      空图库与失败重试、转码单测（JPEG 直通、HEIC 转换、非 JPEG 拒绝、64 MB 上限、
      文件名与 mime）、取消选中丢弃迟到上传结果。
