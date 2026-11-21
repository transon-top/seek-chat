# 图片与文档上传

票 13 的决策。行为契约以 `https://github.com/deepseek-ai/chat-demo` 为准；本文只记录与移动端相关的取舍。
术语见根目录 `GLOSSARY.md`，数据表见 [`data-model.md`](data-model.md)，接口前缀见 [`api.md`](api.md)。

## 1. 选型与入口

> 2026-11-21 输入区改版推翻了本文旧决议「不引入 `image_picker`、不实现拍照」。
> 新入口为 `+` / `×` 内联附件面板：设备照片横条 + 拍照 / 相册 / 文件三宫格，
> 不再是回形针 + 底部 Sheet。`file_picker` 只保留「选择文件」一项。

### 1.1 入口与面板

- 入口：输入区操作行最左的 `+` 按钮；面板展开时变 `×`。
- 面板挂在输入卡下方、与输入卡同列，不覆盖消息区；内容决定高度，横屏或屏高
  不足时最大 45% 屏高并内部滚动。
- 面板内容（自上而下）：
  1. 设备照片横条（最近 30 张，见 §9）。
  2. 三宫格：拍照 / 从相册选择 / 选择文件。
- 点 `+` 立即让输入框失焦并收起键盘，面板以 `AnimatedSize` 220ms 展开；
  `×`、点输入框、Android 返回键收起；点麦克风先收面板再开始按住说话；
  点发送后收起面板；无文本时面板保持展开。
- 面板展开时 `+` 显示为 `×`；生成中禁用；录音 / 识别浮层覆盖期间不可见。

### 1.2 依赖

| 依赖 | 版本 | 用途 |
| --- | --- | --- |
| `photo_manager` | `^3.12.0` | 最近照片分页、缩略图、选中资产落地 |
| `image_picker` | `^1.2.4` | 拍照、系统相册多选 |
| `image_picker_android` | 跟随 `image_picker` | Android 13–15 显式开启系统 Photo Picker |
| `image_picker_platform_interface` | 跟随 `image_picker` | 访问 `ImagePickerAndroid.useAndroidPhotoPicker` |
| `file_picker` | `13.4.0`（既有） | 仅「选择文件」 |

- 不引入 `wechat_assets_picker`（自带整套选择 UI，与内联面板冲突）；
  `photo_manager_image_provider` 可选，本规格不依赖。
- 组合已在 Flutter 3.50.0 / Dart 3.14.0 下通过 pub 分析，与 `file_picker 13.4.0`、
  iOS 15、Android minSdk 24 无冲突；选型证据见 `composer-redesign/evidence/photo-picker.md`。
- 不新增动效 / 渐变依赖：浮层由 `CustomPainter` 自绘。

### 1.3 拍照、系统相册与文件

- 拍照：`image_picker.pickImage(source: ImageSource.camera, imageQuality: 90,
  maxWidth: 2560, maxHeight: 2560)`；返回后直接加入草稿并上传，无二次确认；
  取消则无变化。
- 系统相册：`pickMultiImage(imageQuality: 90, maxWidth: 2560, maxHeight: 2560)`，
  `limit: 50 - 当前草稿数`；iOS 走 PHPicker；Android 13–15 在首次调用前设置
  `(ImagePickerPlatform.instance as ImagePickerAndroid).useAndroidPhotoPicker = true`
  （Android 16+ 自动）。平台不遵守 `limit` 时沿用「任一文件不合法则整批不加入」。
- 文件：`file_picker` `FileType.any` 多选，选中后按扩展名白名单校验（§3 不变）。
- 相机与相册产物同样做 JPEG 嗅探；非 JPEG 按 §1.5 拒绝。系统相册 / 拍照
  不回写横条勾选，也无法与横条资产去重（`image_picker` 只返回路径）。
- 草稿已满 50 时，「拍照」「相册」两格点击弹 `uploadMaxFiles`，不打开系统界面。
- 从相机 / 相册 / 文件选择器返回后：面板保持展开、键盘保持收起、焦点不移动、
  横条不刷新；新附件追加到草稿行；用户取消则一切不变。
- 外部界面期间进程被系统回收：v1 不恢复草稿与勾选，不做 `retrieveLostData`；
  列为已知限制。

### 1.4 权限与平台配置

- 照片权限全部交给 `photo_manager`（`requestPermissionExtend`）；相机权限由
  `image_picker` 自理；`permission_handler` 只用于麦克风。
- iOS `Info.plist` 新增：
  - `NSPhotoLibraryUsageDescription`
  - `NSCameraUsageDescription`
  - `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = true`
- Android `AndroidManifest.xml` 新增：
  - `READ_MEDIA_IMAGES`
  - `READ_MEDIA_VISUAL_USER_SELECTED`
  - `READ_EXTERNAL_STORAGE`（`android:maxSdkVersion="32"`）
- 系统相册（PHPicker / Android Photo Picker）与文件选择器不需要存储权限。
- `--dart-define=OPEN_CHAT_PHOTO_STRIP=false` 只关闭 Android 照片横条及其权限申请；
  iOS 不受影响（§1.6）。

### 1.5 HEIC 与转码

- 横条资产一律转 JPEG 再入草稿：iOS 优先 `.file`，嗅探不是 JPEG 时回退
  `thumbnailDataWithSize`；Android 直接
  `thumbnailDataWithSize(ThumbnailSize(asset.width, asset.height),
  format: ThumbnailFormat.jpeg, quality: 90)`。质量 90、长边 ≤2560，按目标尺寸
  解码避免全尺寸 OOM。
- 草稿文件名为 `.jpg`、mime `image/jpeg`；照片计入 50 个上限。
- 转码异常或输出仍非 JPEG：Toast `photoUnreadable`，不入草稿、勾选保持未选。
- 转码后超过 64 MB：既有 `uploadMaxMBSize` 提示，不入草稿。
- 白名单不改：`heic` / `heif` 仍不接受；方向由平台解码归一，个别机型方向异常
  列入真机验收，不另做产品行为。

### 1.6 Android 分发

- 默认构建保留照片横条，侧载 APK 全功能。
- 上 Google Play 时先提交 `READ_MEDIA_IMAGES` broad-access 声明；被拒则以
  `--dart-define=OPEN_CHAT_PHOTO_STRIP=false` 构建发布，不临时改代码。
  关闭后不查询、不申请照片权限，面板只剩三宫格。
- 若确定永不上 Play，可省去该开关，保持横条常开。

## 2. Files API 与请求块

- 上传：`POST {origin}/anthropic/v1/files`，`multipart/form-data`。
  - 头：`x-api-key`、`anthropic-beta: files-api-2025-04-14`。
  - 字段顺序：`purpose`（可为空则不传）在前，`file` 在后。
  - `purpose` 取值：图片不传；`pdf`、`doc`、`docx`、`ppt`、`pptx` 传 `rich_layout_recognition`；其余传 `user_data`。
  - 响应 `{ "id": ... }` 即 `serverId`。不设过期；v1 不调用 `DELETE /files/{id}`（`chat-demo` 也不调用）。
- 请求块：`serverId` 非空的附件按顺序放在文本块之前；图片用
  `{type: image, source: {type: file, file_id}}`，其余用 `document`。
  `serverId` 为空的附件不进入请求。含文件块的请求追加 beta 头（已由传输层按 `hasFileBlocks` 实现）。
- 搜索扩展下 `document` 会被服务端以 400 拒绝：不在客户端预先拦截，按普通 HTTP 错误展示，与 `chat-demo` 一致。

## 3. 校验与限制

| 项 | 规则 |
| --- | --- |
| 扩展名 | 白名单逐项复制 `chat-demo/src/services/uploadExts.ts`（约 950 个，小写比较；无扩展名不支持）。`heic`/`heif` 不在白名单 |
| 大小 | `user_data` 32 MB；图片与版面解析（pdf/doc/docx/ppt/pptx）64 MB |
| 数量 | 单次草稿最多 50 个 |
| 批次 | 任一文件不合法则整批不加入；错误文案见 §6 |
| 图片判定 | 按扩展名：png/jpg/jpeg/gif/webp/svg/svgz/bmp/ico/tif/tiff/avif/apng/jfif/xbm/dib/pjp/pjpeg |

`chat-demo` 用浏览器 MIME 判定图片；移动端拿不到可靠 MIME，按扩展名判定，并写入 `attachments.is_image`。
横条照片、拍照、系统相册的产物都先转 JPEG（§1.5）再走白名单；
源文件为 `heic` / `heif` 的附件不会进入请求。

## 4. 本地存储

- 选中文件后原件来自系统选择器的临时路径；**发送时**复制到
  `<应用支持目录>/attachments/<attachment.id>`，数据库存相对路径
  `attachments/<id>`。先写文件再写数据库行，文件写失败则整次发送失败。
- 未发送的草稿只在聊天页内存中；离开页面即丢弃（草稿不在 v1 范围，见地图 Out of scope）。
  横条来源的草稿额外带仅内存的 `sourceAssetId`，用于派生勾选与去重；不写数据库、
  不进归档。
- 删除会话：删除消息与附件行，事务提交后删除不再被任何附件行引用的文件；远端 Files API 文件不删除。
- 原件缺失（`local_path` 为 NULL 或文件不存在）：只展示元数据，不进入请求，不提供补传入口。
- 附件 id 为 UUID v4；一个原件可被多条消息引用（编辑与重新生成沿用）。

## 5. 上传状态机

```text
选中 ──→ uploading ──→ done(serverId)
              │
              └──→ error(retryable) ──重试──→ uploading
              │
              └──→ error(not retryable)（过大、格式、解析失败；只能移除）
移除 → 丢弃任务结果（迟到的成功只更新任务表，不再展示）
```

- 选中即上传；单附件同一时刻只允许一个任务在跑。
- 并发上限 3，其余排队；排队中被移除的任务不发出请求。
- 发送闸门：文本 trim 非空或附件非空，且所有附件 `done`；否则发送按钮禁用。
- 发送前补传：本轮提问与进入上下文的历史轮次中 `serverId` 为空的附件。
  - 本轮：并行补传，任一失败则请求不发出，回复记 `upload` 错误并保留可重试标记。
  - 历史：从最新往前逐张补传，失败静默跳过（本次请求不带该附件）。
  - 补传成功把 `serverId` 写回所有引用同一附件的消息。
- `serverId` 被服务端判定失效（400 文案含 `file_ids do not exist`、
  `file data not found`、`invalid file_id`）：清空对应附件的 `serverId`，重新上传后重发；
  退避 1 s、2 s，最多重试 2 次，已收到内容块则不重发。

## 6. 失败文案与重试

| 情况 | 附件上显示 | 可重试 |
| --- | --- | --- |
| 上传中 | 上传中... | — |
| 服务端繁忙（5xx） | 服务器繁忙 | 是 |
| 网络、429 | 上传失败 | 是 |
| 解析失败（图片损坏/过大、加密、无法识别） | 解析失败 | 否 |
| 文件数 / 存储配额上限 | 上传失败 + 底部提示（含上限数值与「删除文件」链接） | 否 |
| 其他 400 | 上传失败 | 否 |

- 可重试的失败在卡片或缩略图上显示刷新图标；不可重试的失败显示红色描边与原因。
- 配额提示用 SnackBar，动作「删除文件」外部打开
  `https://api-docs.deepseek.com/api/delete-file`。
- 回复级 `upload` 错误在回复下方展示原因与「重试」入口；重试重新补传并请求。

## 7. UI

- 草稿附件行在输入框上方、输入卡内：
  - 单行横滑、永不换行；图片 64×64，文件卡 210×64。
  - 图片缩略图，上传中蒙层转圈，失败红描边 + 中心刷新图标。
  - 文件卡片：36×36 扩展名配色色块图标、文件名、`扩展名 + 大小`；
    上传中/失败时第二行换成状态文案。
  - 移除徽标为卡片内右上角 20 白色圆，不再占用卡片外空间。
- 附件面板：照片横条 + 三宫格，见 §1.1、§9；上传中与失败只在草稿行表达，
  面板内不加额外横幅；存在未完成附件时发送保持禁用。
- 消息里的附件：图片缩略图（纯图片 120×120，与文档混排 64×64），点击全屏查看；
  文档卡片只展示文件名、扩展名与大小，不做应用内预览（外部打开需平台共享配置，v1 不做）。
  原件缺失的图片显示占位图标，文档卡片显示「原件已丢失」。
- 发送按钮：有内容且附件全部 `done` 时可用；无文字、仅有附件也可以发送。
- 界面文案新增中英文 ARB 条目；服务端原文不直接展示。

## 8. 与其它票的边界

- 导出导入（票 17）：只导出有原件的图片，文档只导出元数据（`data-model.md` §6）。
- 内容安全与图片审核（票 14）：在服务端错误与拒答层面处理，不在本票范围。
- 全量双语与主题（票 18）：本票只新增附件相关文案，其余界面文案仍由票 18 收口。
- 界面规格（`ui.md` §1.3、§5.2、§5.7、§8.1）：输入区改版后的面板、草稿行、
  照片格尺寸与动效以 `ui.md` 为准；本票只定数据、依赖与降级语义。

## 9. 设备照片横条

### 9.1 数据与刷新

- 固定读取最近 30 张，不翻页；只取图片，排除视频。
- 排序显式使用 `createDate` 倒序（`OrderOption`），不依赖默认排序
  （Android 不传 filter 时 SQL 没有 ORDER BY）。
- 每次展开面板重新查询第一页；面板保持展开期间不自动刷新，避免勾选位置跳动。
- 缩略图按 200×200 解码，`isOriginal: false` + `thumbnailSize`；
  `AssetEntityImage` 禁止默认 `isOriginal: true`（会拉原图）。
- 首次加载显示 6 个与照片格等高的静态灰块骨架，无动画。
- 读取失败在横条区原位显示「无法读取照片」+「重试」。
- Android 构建关闭横条时（§1.6），不查询、不申请照片权限，面板只剩三宫格。

### 9.2 选择模型

- 点击缩略图切换选中；选中态为主色圆底白勾 + 图片压暗。
- 选中即转码、追加到草稿附件行末尾并开始上传，保持「选中即上传」语义。
- 取消选中：再次点击缩略图，或点草稿行的移除徽标。两者都从草稿移除；
  上传中则取消排队 / 在途任务，迟到的成功结果丢弃。
- 选中态不单独存储，由草稿附件的 `sourceAssetId`（仅内存字段）派生；
  同一资产不能重复加入。
- 上传失败不回退勾选；失败只在草稿卡表达，重试走草稿卡。
- 草稿已有 50 个时，未选中的照片格降为 50% 不透明度，点击弹
  `uploadMaxFiles`；已选中的仍可取消。

### 9.3 权限降级

- 每次展开面板都检查照片权限；仅当状态为未决定时弹系统请求，不在启动或
  进聊天页时预请求。
- 面板立即展开，横条区先显示骨架，权限与数据结果回来后替换。
- 已授权：加载最近 30 张。
- 受限（iOS limited，含 Android 14 部分访问）：只加载可访问资产；横条最左端
  插入与照片格等高的「管理」格，点击
  `PhotoManager.presentLimited(type: RequestType.image)`，返回后重载。
  可访问资产为 0 时只显示「管理」格，不显示权限拒绝空态。
- 拒绝（denied / restricted）：横条区原位显示「无法访问照片」+「去设置」
  （复用 `settingsOpenSystemSettings`）；三宫格仍可用，因为拍照、系统相册、
  文件均不需要照片权限。
- 已授权但图库为空：「没有最近照片」。
- 读取失败：「无法读取照片」+「重试」。
- 面板展开期间从后台恢复、或从系统设置 /「管理」选择器返回：重新检查权限并
  重载横条；草稿行与勾选不受影响。

### 9.4 缓存与文件生命周期

- Android content URI 由插件复制到 cache 后返回路径；iOS PhotoKit 资源由插件
  导出 / 缓存到 `NSTemporaryDirectory()`。上传前复制到应用自己的目录，
  移除 / 发送后删除。
- 草稿上传进行中禁止调用 `PhotoManager.clearFileCache()`。
- 横条勾选只存活于当前页面内存；离开页面即丢弃，与草稿附件一致。

## 10. 新增文案

| key | zh | en |
| --- | --- | --- |
| `addAttachment` | 添加附件 | Add attachment |
| `closeAttachmentPanel` | 收起附件面板 | Close attachment panel |
| `takePhoto` | 拍照 | Take photo |
| `photoPermissionDenied` | 无法访问照片 | Can't access photos |
| `photoLimitedManage` | 管理 | Manage |
| `photoLimitedManageSemantics` | 管理可访问照片 | Manage accessible photos |
| `photoStripEmpty` | 没有最近照片 | No recent photos |
| `photoStripLoadFailed` | 无法读取照片 | Couldn't load photos |
| `photoUnreadable` | 无法读取这张照片 | Couldn't read this photo |
| `photoTileSelected` | 照片，第 {index} 张，已选 | Photo {index}, selected |
| `photoTileUnselected` | 照片，第 {index} 张，未选 | Photo {index}, not selected |

`{index}` 从 1 起。复用：`settingsOpenSystemSettings`（去设置）、`retry`（重试）、
`uploadMaxFiles`（50 上限）、`uploadMaxMBSize`（64 MB）、`uploadFromPhotos`
（从相册选择）、`uploadFromFiles`（选择文件）、`removeAttachment`（移除附件）。
面板与草稿行的完整文案表见 `ui.md` §7.2。
