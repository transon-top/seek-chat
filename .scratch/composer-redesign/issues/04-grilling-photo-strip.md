# 照片横条数据、选择与权限降级

Type: grilling
Status: resolved
Blocked by: 01

## Question

依据《照片横条与相机/相册依赖调研》的技术事实，锁定照片横条的产品行为：

1. 数据：读取数量（建议 30）、分页/刷新时机、排序、排除视频、缩略图尺寸；进入面板时加载与骨架。
2. 选择模型：点击选中/取消、选中勾样式、与草稿附件行的一一对应与去重；取消选中是否取消进行中的上传。
3. 权限：首次请求时机；拒绝（denied）与 iOS 受限（limited）的降级 UI；「管理可访问照片」/「去设置」入口；无照片或读取失败时的文案。
4. HEIC：转码失败、超大图片、方向问题的用户可见结果；与 50 个上限、32/64 MB、白名单的交互。
5. 拍照：拍完直接加入草稿并上传还是先确认；相册按钮与横条的关系（系统多选 vs 自定义多选）。
6. 从系统相册/文件选择器返回后的面板状态与焦点。
7. Android 分发：`READ_MEDIA_IMAGES` 属 Google Play 受限权限，聊天 App 需 broad-access 审核。定 Android 横条策略：提交声明并接受审核风险、Android 不显示横条只保留拍照/系统相册/文件、或其他；以及被拒后的构建/运行时降级方式。

## Deliverable

票内 Answer；新增文案的 key 与中英文案列出，票 07 汇总。

## Answer

以下为与用户逐条确认的最终决议。选中态为「主色圆底白勾 + 图片压暗」，勾尺寸与遮罩透明度由票 06 原型收敛。

### 1. 数据与刷新

- 固定读取最近 30 张，不翻页；只取图片，排除视频。
- 排序显式使用 `createDate` 倒序（`OrderOption`），不依赖默认排序。
- 每次展开面板重新查询第一页；面板保持展开期间不自动刷新，避免勾选位置跳动。
- 缩略图按 200×200 解码，`isOriginal: false`。
- 首次加载显示 6 个与照片格等高的静态灰块骨架，无动画。
- 读取失败在横条区原位显示「无法读取照片」+「重试」。
- Android 构建关闭横条时（见 §7），不查询、不申请照片权限，面板只剩三宫格。

### 2. 选择模型

- 点击缩略图切换选中；选中态为主色圆底白勾，图片叠加压暗遮罩。
- 选中即转码、追加到草稿附件行末尾并开始上传，保持现有「选中即上传」语义。
- 取消选中：再次点击缩略图，或点草稿行的 `×`。两者都从草稿移除；上传中则取消排队/在途任务，迟到的成功结果丢弃（沿用现有移除语义）。
- 选中态不单独存储，由草稿附件的 `sourceAssetId`（仅内存字段）派生；同一资产不能重复加入。
- 上传失败不回退勾选；失败只在草稿卡表达，重试走草稿卡。
- 草稿已有 50 个时，未选中的照片格降为 50% 不透明度，点击弹既有 `uploadMaxFiles`；已选中的仍可取消。

### 3. 权限

- 每次展开面板都检查照片权限；仅当状态为未决定时弹系统请求，不在启动或进聊天页时预请求。
- 面板立即展开，横条区先显示骨架，权限与数据结果回来后替换。
- 已授权：加载最近 30 张。
- 受限（limited，含 Android 14 部分访问）：只加载可访问资产；横条最左端插入与照片格等高的「管理」格，点击 `PhotoManager.presentLimited(type: RequestType.image)`，返回后重载。该调用在 iOS 与 Android 14 部分访问下都会重新拉起系统选择器。
- 受限且可访问资产为 0：横条只显示「管理」格，不显示权限拒绝空态。
- 拒绝（denied/restricted）：横条区原位显示「无法访问照片」+「去设置」（复用 `settingsOpenSystemSettings`）；三宫格仍可用，因为拍照、系统相册、文件均不需要照片权限。
- 已授权但图库为空：「没有最近照片」。
- 读取失败：「无法读取照片」+「重试」。
- 面板展开期间从后台恢复、或从系统设置/「管理」选择器返回：重新检查权限并重载横条；草稿行与勾选不受影响。
- 权限全部交给 `photo_manager`；相机权限由 `image_picker` 自理。
- Android Manifest：`READ_MEDIA_IMAGES`、`READ_MEDIA_VISUAL_USER_SELECTED`、`READ_EXTERNAL_STORAGE maxSdkVersion=32`；iOS Info.plist：`NSPhotoLibraryUsageDescription`、`NSCameraUsageDescription`、`PHPhotoLibraryPreventAutomaticLimitedAccessAlert=true`。

### 4. HEIC 与限制

- 横条资产一律转成 JPEG 再入草稿：iOS 优先 `.file`，嗅探不是 JPEG 时回退 `thumbnailDataWithSize`；Android 直接用 `thumbnailDataWithSize`。质量 90，长边不超过 2560，按目标尺寸解码以避免全尺寸 OOM。
- 草稿文件名为 `.jpg`，mime 为 `image/jpeg`。
- 转码异常或输出仍非 JPEG：Toast「无法读取这张照片」，不入草稿，勾选保持未选。
- 转码后超过 64 MB：既有 `uploadMaxMBSize` 提示，不入草稿。
- 白名单不改，`heic`/`heif` 仍不接受。
- 方向由平台解码归一；个别机型方向异常列入真机验收，不另做产品行为。
- 照片计入单次草稿 50 个上限。

### 5. 拍照与系统相册

- 拍照：`image_picker.pickImage(source: camera, imageQuality: 90, maxWidth: 2560, maxHeight: 2560)`；返回后直接加入草稿并上传，无二次确认。取消则无变化。
- 系统相册：`pickMultiImage(imageQuality: 90, maxWidth: 2560, maxHeight: 2560)`；iOS 走 PHPicker，Android 13–15 显式开启系统 Photo Picker（`useAndroidPhotoPicker = true`，需直接依赖 `image_picker_android` 与 `image_picker_platform_interface`），返回后逐个加入并上传。
- 相机与相册产物同样做 JPEG 嗅探；非 JPEG 按 §4 拒绝。
- 系统相册/拍照不回写横条勾选，也无法与横条资产去重（`image_picker` 只返回路径，无资产身份）。
- 草稿已满 50 时，「拍照」「相册」两格点击弹 `uploadMaxFiles`，不打开系统界面。
- 相册调用传 `limit: 50 - 当前草稿数`；平台不遵守 limit 时，沿用现有「任一文件不合法则整批不加入」的校验。

### 6. 从系统界面返回

- 从相机、系统相册、文件选择器返回后：面板保持展开，键盘保持收起，焦点不移动，横条不刷新、不重排；新附件追加到草稿行。
- 用户取消则一切不变。
- 外部界面期间进程被系统回收：v1 不恢复草稿与勾选，不做 `retrieveLostData`；列为已知限制。

### 7. Android 分发

- 默认构建保留照片横条，侧载 APK 全功能。
- 构建开关：`--dart-define=OPEN_CHAT_PHOTO_STRIP=false` 仅关闭 Android 横条；面板只保留三宫格，高度随内容收缩；iOS 不受影响。
- 上 Google Play 时先提交 `READ_MEDIA_IMAGES` broad-access 声明；被拒则以该开关关闭的构建发布，不临时改代码。
- 若确定永不上 Play，可省去该开关，保持横条常开。

### 新增文案

| key | zh | en |
| --- | --- | --- |
| photoPermissionDenied | 无法访问照片 | Can't access photos |
| photoLimitedManage | 管理 | Manage |
| photoLimitedManageSemantics | 管理可访问照片 | Manage accessible photos |
| photoStripEmpty | 没有最近照片 | No recent photos |
| photoStripLoadFailed | 无法读取照片 | Couldn't load photos |
| photoUnreadable | 无法读取这张照片 | Couldn't read this photo |
| photoTileSelected | 照片，第 {index} 张，已选 | Photo {index}, selected |
| photoTileUnselected | 照片，第 {index} 张，未选 | Photo {index}, not selected |

`{index}` 从 1 起。复用：`settingsOpenSystemSettings`（去设置）、`retry`（重试）、`uploadMaxFiles`（50 上限）、`uploadMaxMBSize`（64 MB）。
