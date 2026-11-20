# 照片横条与相机/相册依赖调研

票：`issues/01-research-photo-picker.md`
调研日期：2026-11-20
仓库环境：Flutter 3.50.0 / Dart 3.14.0；iOS 部署目标 15.0；Android `minSdk = flutter.minSdkVersion`（Flutter 3.50 默认 24）、`targetSdk = 36`、`compileSdk = 37`。
范围：只做一手来源核对（官方文档、插件源码、pub.dev 页面、Apple/Android 官方文档）。未安装依赖、未编译、未改产品代码。

## 结论表

| # | 问题 | 结论 | 依据 |
|---|------|------|------|
| 1 | 依赖组合 | `photo_manager ^3.12.0` 负责最近照片分页/缩略图/资产落地，`image_picker ^1.2.4` 负责拍照与系统相册多选。`wechat_assets_picker` 不需要；`image_picker` 单干做不了最近照片横条；`photo_manager_image_provider` 可选。 | [S1][S4][S44][S46] |
| 2 | 权限 | iOS 14+ 有 `.limited`；iOS 17/18 未发现 PhotoKit 授权 API 变更，iOS 17 起系统增加全量访问的周期性提醒（系统侧）。Android 13+ 要 `READ_MEDIA_IMAGES`，Android 14+ 部分访问要 `READ_MEDIA_VISUAL_USER_SELECTED`；系统相册走 Photo Picker 则不需要存储权限。`permission_handler` 能读 limited 状态，但不能拉起 iOS「管理可访问照片」，Android 也不会主动申请 `READ_MEDIA_VISUAL_USER_SELECTED`，因此照片权限交给 `photo_manager`。 | [S31][S33][S35][S37][S38][S41][S42][S43] |
| 3 | HEIC/HEIF | `image_picker` iOS 的相册与相机都输出 JPEG（PHPicker 结果经 `UIImage` 重编码；HEIC 首字节识别不到，回落 `.jpg` + JPEG 编码）。`photo_manager` iOS `.originFile` 保留 HEIC，`.file` 输出全尺寸 JPEG。Android `image_picker` 默认原样复制，HEIC 可能保持 `.heic`；`image_picker` 仅在 `imageQuality < 100` 或设置 `maxWidth/maxHeight` 时重编码。横条选中资产在 Android 需按魔数/扩展名识别 HEIC，再用 `thumbnailDataWithSize(format: jpeg)` 转 JPEG。失败则拒绝入草稿并 Toast。 | [S9][S10][S12][S13][S15][S23] |
| 4 | 文件落地 | Android 的 content URI 由插件复制到应用 cache/temp 后返回路径；iOS PhotoKit 资源由插件导出/缓存到 `NSTemporaryDirectory()`。插件缓存随时可能被系统清理，上传前应复制到应用自己的目录，移除/发送后删除；`PhotoManager.clearFileCache()` 不能在草稿上传中调用。 | [S13][S14][S23][S25] |
| 5 | 缩略图 | 分页 `page: 0, size: 30`；显式 `OrderOption(type: createDate, asc: false)` 保证最新优先（Android 不传 filter 时 SQL 没有 ORDER BY）。缩略图建议 `200×200`，30 张约 4.8 MB 解码内存（200×200×4 B×30），Flutter ImageCache 默认 100 MiB。禁止用 `isOriginal: true` 拉原图。 | [S18][S19][S21][S22][S26][S27][S46][S48] |
| 6 | 相机 | iOS 用 `UIImagePickerController`，输出 `NSTemporaryDirectory()/image_picker_<guid>.jpg`；Android 用 `ACTION_IMAGE_CAPTURE`，输出 `cacheDir/<uuid>.jpg`。iOS 需 `NSCameraUsageDescription`；Android 不声明 `CAMERA` 就不申请权限（由系统相机应用完成拍摄）。照片按现有规则上限 64 MB，正常相机输出远低于此。 | [S11][S13][S15][S7] |
| 7 | 版本约束 | 三包均在 Flutter 3.50.0 / Dart 3.14.0 下通过 pub 分析；`image_picker 1.2.4` 要求 Flutter >= 3.41，发布版 `image_picker_ios 0.8.13+9` 支持 iOS 13+，`photo_manager` 约束宽松；本项目 iOS 15 / Android 24 均满足。与 `file_picker 13.4.0` 无版本或 FileProvider 冲突。 | [S3][S6][S45][S47][S49] |

## 1. 依赖组合与版本

### 推荐

```yaml
dependencies:
  photo_manager: ^3.12.0      # 最近照片分页、缩略图、资产落地
  image_picker: ^1.2.4        # 拍照、系统相册多选
  # 仅在 Android 13–15 强制走系统 Photo Picker 时需要：
  image_picker_android: ^0.8.13+25
  image_picker_platform_interface: ^2.11.0
  # 可选：只想要现成缩略图 widget 时再加
  photo_manager_image_provider: ^2.2.0
```

- `photo_manager 3.12.0`：Apache-2.0，fluttercandies.com 发布，周下载 50 万；pub 分析环境正是 Flutter 3.50.0 / Dart 3.14.0；支持 Android/iOS/macOS。Android 端原生依赖 Glide 4.16.0 与 androidx.exifinterface 1.4.2。[S1][S3][S30]
- `image_picker 1.2.4`：Apache-2.0 + BSD-3-Clause，flutter.dev 发布，周下载 630 万，pub 160/160；最新版要求 Flutter >= 3.41 / Dart >= 3.11（main 分支 pubspec 标 `flutter >=3.44`，以 pub 页面与分析结果为准），Flutter 3.50 满足。[S4][S6]
- 包体积：未实测 AAB 增量。可确认的是 `photo_manager` Android 引入 Glide 与 exifinterface；iOS 为 Objective-C 源码。若体积敏感，需构建后对比测量（未验证具体 KB）。[S30]

### 对比

| 方案 | 能做什么 | 不适合本图的原因 |
|------|----------|------------------|
| `photo_manager` + `image_picker` | 自定义最近照片横条 + 系统相机 + 系统相册多选 | 无（推荐） |
| `image_picker` 单干 | 相机、系统相册多选 | 没有「不弹选择器就列出最近 N 张」的 API，做不了横条 |
| `wechat_assets_picker` | 完整仿微信媒体选择器（网格、预览、主题） | 自带整套选择 UI，与本图「输入卡下方内联面板 + 30 张横条」冲突；仍依赖 `photo_manager` 与完整相册权限 |
| `photo_manager_image_provider` | `AssetEntityImage` / `AssetEntityImageProvider`，按 `thumbnailSize` 出缩略图 | 只是缩略图 widget 适配层，不能单独取资产；最新版 2.2.0 已两年未发版，pub 140/160。可选，不是必需 |

`wechat_assets_picker 10.1.3`：Apache-2.0，周下载 5.99 万，分析环境同为 Flutter 3.50.0 / Dart 3.14.0；依赖 `photo_manager ^3.5.0`。[S44][S45]

### 最近照片分页 API

```dart
final paths = await PhotoManager.getAssetPathList(
  onlyAll: true,
  type: RequestType.image,
  filterOption: FilterOptionGroup(
    orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
  ),
);
final recent = paths.single; // 系统「最近」智能相册
final page = await recent.getAssetListPaged(page: 0, size: 30);
```

- `getAssetListPaged(page, size)`：`page` 从 0 开始，`size` 为每页数量。[S19]
- 默认不传 `filterOption` 时，Android 的排序 SQL 不生成 `ORDER BY`（`getSortOrder` 只拼 `LIMIT/OFFSET`；`AndroidQDBUtils.getSortOrder` 直接返回 `filterOption?.orderByCondString()`，为 null），所以「最新优先」不能靠默认值；iOS 在无 `sortDescriptors` 时用倒序索引，能到最新优先，但显式 `OrderOption(asc: false)` 两端一致。[S22][S26][S27][S23]
- `RequestType.image` 排除视频；`FilterOptionGroup` 默认排除隐藏资产（`includeHiddenAssets = false`）。[S20][S22]
- `onlyAll: true` 只返回系统「最近」相册，不枚举用户相簿；在 iOS limited 下也不会去碰不可用的用户相簿。[S20][S31]

### 缩略图 API

```dart
final bytes = await asset.thumbnailDataWithSize(
  const ThumbnailSize.square(200),
  format: ThumbnailFormat.jpeg,
  quality: 85,
);
```

- `thumbnailDataWithSize` 默认 `ThumbnailFormat.jpeg`、`quality: 100`；iOS 走 `PHCachingImageManager`，Android 走 Glide，返回的是缩略图字节，不是原图。[S18][S23]
- `AssetEntityImage` 的默认值是 `isOriginal: true`：对非 HEIC 图片会取 `originBytes`（原图全尺寸），对 HEIC 取 `.file`。横条必须显式 `isOriginal: false` + `thumbnailSize`，否则 30 张原图会把内存打穿。[S46]

### 相机与系统相册

```dart
// 相机
final shot = await ImagePicker().pickImage(source: ImageSource.camera);

// 系统相册多选
final picked = await ImagePicker().pickMultiImage(
  limit: remaining,            // 剩余可选数量
  imageQuality: 90,            // 让 Android 在可解码时重编码为 JPEG
  requestFullMetadata: false,  // PHPicker 路径本就不需要相册权限
);
```

- `pickMultiImage` 在 iOS 用 PHPicker；单张/多张都走 `selectionLimit`。iOS 14+ 才支持（本项目 iOS 15，满足）。[S7][S11][S8]
- Android 16+ 强制使用 Photo Picker；Android 13–15 默认仍是 `ACTION_GET_CONTENT`。要系统 Photo Picker，必须在首次调用前改**已注册的平台实例**：

  ```dart
  import 'package:image_picker_android/image_picker_android.dart';
  import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

  if (defaultTargetPlatform == TargetPlatform.android) {
    (ImagePickerPlatform.instance as ImagePickerAndroid).useAndroidPhotoPicker = true;
  }
  ```

  `image_picker` 不 re-export `ImagePickerAndroid` 也不导出 `ImagePickerPlatform`，所以需要把 `image_picker_android` 与 `image_picker_platform_interface` 都加为直接依赖（版本与传递依赖一致）。new 一个 `ImagePickerAndroid()` 再设 flag 不会影响已注册单例。若不想多两个直接依赖，可接受 Android 13–15 走 `ACTION_GET_CONTENT`：仍可多选、无需存储权限，但不是系统 Photo Picker，`limit` 也不保证。这点与 `image_picker` README「Android 13+ 自动使用 Photo Picker」的表述不一致，以 0.8.13+25 源码与 changelog 为准。[S16][S17]
- `limit` 在 Android 只有 Photo Picker 路径保证；legacy `ACTION_GET_CONTENT` 会忽略数量上限，仍需应用侧 `validateAttachmentSelection` 兜底。[S16]
- iOS PHPicker 在 limited 模式下仍显示整个图库；选择结果通过 `NSItemProvider` 返回，`assetIdentifier` 在 limited 下不能用于 `fetchAssets`（Apple 工程师回复与 WWDC20-10652 均说明）。`image_picker` 只读 item provider，因此系统相册多选不受 limited 影响。[S36][S32]

## 2. 权限与平台配置

### iOS 14+ limited

- `.limited` 表示用户只授权了部分照片；`.readWrite` 才有此状态，`.addOnly` 没有。[S34]
- limited 下 PhotoKit 只能看到被选中的资产，不能创建/获取用户相簿；系统会把 App 自己创建并保存到相册的资产自动加入可选集合。[S31]
- 系统默认每个 App 生命周期自动弹一次「更新可访问照片」；推荐在 Info.plist 设 `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = true`，由 App 自己提供「管理可访问照片」入口，调用 `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:)`。[S31][S33]
- `photo_manager` 已封装：
  - `PhotoManager.requestPermissionExtend(requestOption: PermissionRequestOption(iosAccessLevel: IosAccessLevel.readWrite, androidPermission: AndroidPermission(type: RequestType.image, mediaLocation: false)))`
  - 返回 `PermissionState.limited`
  - `PhotoManager.presentLimited(type: RequestType.image)`；iOS 14 立即完成，iOS 15+ 等弹窗关闭后完成，type 在 iOS 被忽略。[S20][S24]
- iOS 15+ 的 `presentLimitedLibraryPicker(from:completionHandler:)` 回调只返回新增选中的 local identifiers；本项目 iOS 15 可直接用。[S33]

### iOS 17/18

- iOS 17：Apple 2023-06-05 新闻稿明确，当 App 请求整个照片图库时，系统会展示更详细的信息，并「occasional reminders of their choice」；这是系统侧提醒，不是新的 PhotoKit API。未从 Apple 一手文档找到可控制该提醒的 API。[S35]
- iOS 17/18：Apple 文档仍把 `.limited` 标为 iOS 14+、`presentLimitedLibraryPicker` completion 标为 iOS 15+；未发现 iOS 17/18 对 limited 授权 API 的公开变更。[S31][S33][S34]
- iOS 18 的插件侧兼容：`photo_manager` 3.10.0 修复 iOS 18+ 主相册抓取失败；3.8.0 增加 iOS 18 智能相册；3.6.0 避免在 iOS 18+ 使用 `privateFileURL`。用 3.12.0 即包含这些修复。[S2]
- 结论：iOS 17/18 的「变化」主要是系统提示与 Photos App 形态，不是授权 API；App 必须在回到前台时重新读 `authorizationStatus`，不能缓存授权状态。[S31]
- 未验证：iOS 17 全量访问周期性提醒的确切触发频率与是否可被 MDM 关闭，Apple 未公开文档化。

### Android 13+

- 声明 `READ_MEDIA_IMAGES`；查询图片不需要 `READ_MEDIA_VIDEO`。`READ_EXTERNAL_STORAGE` 只用于 Android 12L 及以下，必须带 `android:maxSdkVersion="32"`。[S38][S39]
- `photo_manager` 自身 manifest 只声明了 `READ_EXTERNAL_STORAGE maxSdkVersion=32`；`READ_MEDIA_IMAGES` 与 `READ_MEDIA_VISUAL_USER_SELECTED` 要应用自己声明。[S28]

### Android 14+ 部分访问

- targetSdk 34+ 时，用户可选「选择照片和视频」，只授予部分媒体；不处理则进入兼容模式：权限只在当前会话临时有效，App 退到后台后系统最终收回。[S38]
- 声明 `READ_MEDIA_VISUAL_USER_SELECTED` 后由 App 控制重新选择；`photo_manager` 的 `PermissionDelegate34` 会同时申请 `READ_MEDIA_IMAGES` + `READ_MEDIA_VISUAL_USER_SELECTED`，并把「只有 VISUAL_USER_SELECTED」映射为 `PermissionState.limited`；`presentLimited(type: RequestType.image)` 重新拉起系统选择。[S29][S24]
- 部分访问下查询结果只包含用户选中的资产；Android 15 可用 `QUERY_ARG_LATEST_SELECTION_ONLY` 查询最近一次选择，但这不是「整个图库最近照片」的替代。[S38]
- Android 15/16 未改变上述权限模型；`image_picker_android 0.8.13+25` 在 API 36+ 强制 Photo Picker。[S16]

### 系统照片选择器（Photo Picker）

- Android 11+（带模块更新）可用；4.4–10 及部分 Go 设备可通过 Google Play 服务安装 backport 模块，`image_picker_android` 的 manifest 已带这个 module 依赖，App 不需要额外配置。[S37]
- 不需要任何存储/媒体权限；返回 content URI；多选上限由系统决定，`getPickImagesMaxLimit()` 可查。[S37]
- `image_picker` 在 Android 13–15 需要显式 `useAndroidPhotoPicker = true`；Android 16+ 自动。[S16][S17]

### permission_handler 是否覆盖

| 能力 | permission_handler 13.0.2 | 结论 |
|------|---------------------------|------|
| iOS 读照片状态 | `Permission.photos`，`PHAccessLevelReadWrite`，`.limited` 映射为 `PermissionStatus.limited` | 可读 |
| iOS 管理可访问照片 | 无 `presentLimitedLibraryPicker` 封装；且 `requestPermission` 在 `.limited` 时直接返回，不会重新弹选择器 | 不能替代 `photo_manager.presentLimited` |
| Android 13+ READ_MEDIA_IMAGES | `Permission.photos` 请求 READ_MEDIA_IMAGES | 可请求 |
| Android 14 partial | 状态检测会读 `READ_MEDIA_VISUAL_USER_SELECTED` 并返回 limited，但申请列表里不含 VISUAL_USER_SELECTED | 不能主动拿到 partial 授权 |
| 相机 | `Permission.camera` | 可用，但 `image_picker` 已自行处理，重复申请会多一次弹窗 |

因此：照片权限用 `photo_manager`；相机交给 `image_picker`；`permission_handler` 继续只负责麦克风（仓库现状）。[S41][S42][S43]

### 需要新增的配置

`ios/Runner/Info.plist`：

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Select photos to attach to your messages.</string>
<key>NSCameraUsageDescription</key>
<string>Take a photo to attach to your message.</string>
<key>PHPhotoLibraryPreventAutomaticLimitedAccessAlert</key>
<true/>
```

- `NSPhotoLibraryUsageDescription`：`photo_manager` 必需；`image_picker` 即使 `requestFullMetadata: false` 也因 App Store 政策要求保留。[S1][S7]
- `NSCameraUsageDescription`：`image_picker` 相机必需。[S7]
- 不需要 `NSPhotoLibraryAddUsageDescription`（不往相册写）。
- `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`：抑制系统每生命周期自动弹窗，配合自定义「管理可访问照片」入口。[S31][S33]

`android/app/src/main/AndroidManifest.xml`：

```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>
```

- 不要声明 `android.permission.CAMERA`：`image_picker` 只在 manifest 里存在 CAMERA 时才申请；不声明则直接调系统相机，不产生额外权限弹窗。[S13]
- 不声明 `READ_MEDIA_VIDEO`：横条只要图片。[S38]
- `file_picker 13.4.0` 与 `image_picker` 的 FileProvider authority 不冲突：`android_file_picker` 的 manifest 只有 `<queries>`，没有 FileProvider；`image_picker` 用 `${applicationId}.flutter.image_provider`。[S13]

### Google Play 风险（重要）

`READ_MEDIA_IMAGES` 属于 Google Play 受限权限：只有「核心功能需要广泛访问照片/视频」的 App 才能申请，且要提交 broad-access declaration 审核；聊天 App 未被列为明确允许的用例。官方建议是改用系统 Photo Picker。[S39][S40]

影响：Android 端「最近照片横条」必须依赖 `READ_MEDIA_IMAGES`，因此存在审核被拒的可能。备选：
1. 审核通过：保留横条。
2. 审核不通过：Android 去掉横条，只保留拍照/系统相册/文件三入口（iOS 不受影响）。
3. 只声明 `READ_MEDIA_VISUAL_USER_SELECTED`：横条只能显示用户选中的少量照片，不满足「最近 30 张」的产品语义，不建议。

## 3. HEIC/HEIF 路径

### 各入口实际格式

| 入口 | iOS | Android |
|------|-----|---------|
| 相机 | `UIImagePickerController` 返回 `UIImage`，`saveImage(withPickerInfo:)` 用默认 JPEG 类型与 `.jpg` 后缀，写 `NSTemporaryDirectory()/image_picker_<guid>.jpg`。[S11][S9] | `ACTION_IMAGE_CAPTURE`，`createTemporaryWritableImageFile()` 固定 `.jpg`，写 `cacheDir/<uuid>.jpg`。API 不保证相机 App 的编码器，但扩展名固定 `.jpg`；以魔数为准。[S13] |
| 系统相册多选 | PHPicker `loadDataRepresentation(UTType.image)` → `UIImage` → `saveImageWithOriginalImageData`。`getImageMIMEType` 只认 JPEG `0xFF`、PNG `0x89`、GIF `0x47`；HEIC 落到 `.other`，后缀回落 `.jpg`，`convert` 的 default 分支用 `jpegData`。**HEIC 必转 JPEG。** [S12][S10] | `getPathFromUri` 原样复制 content URI 字节到 `cacheDir/<uuid>/<fileName>`，扩展名尽量按 MIME 修正；默认不重编码。HEIC 可能保持 `.heic`。[S14][S13] |
| 最近横条 | `.file` → `fetchFullSizeImageFile`：`PHImageManagerMaximumSize` 解码后 `convertToData(... PMThumbFormatTypeJPEG quality:1.0)`，写 `NSTemporaryDirectory()/flutter-images/<sha256>_exif.jpg`。**输出全尺寸 JPEG。** `.originFile` 走 `PHAssetResource`，未编辑资产通常是 HEIC 原始字节；编辑过的资产可能拿到渲染后的格式，不能假定是 JPEG。[S23] | `.file` → `ScopedCache.getCacheFileFromEntity`：把 `MediaStore` URI 字节复制到 `cacheDir/pm_<id>_<displayName>`，插件不转码；是否被系统转码取决于 MediaProvider 的 media capabilities，不能依赖。**可能仍是 HEIC。** [S25] |
| 横条缩略图 | `thumbnailDataWithSize` 指定 `format: jpeg`，`PMImageUtil` 输出 JPEG。[S18][S23] | 同上，Glide 解码后按 `format` 输出 JPEG。[S18][S23] |

结论：不能把「插件返回的路径」直接当 JPEG。必须按内容嗅探（JPEG `FF D8`、PNG `89 50 4E 47`、HEIC 在偏移 4 的 `ftypheic/heix/hevc/mif1`），再决定扩展名与是否需要转码。

### 推荐转码路径

1. iOS 系统相册/相机：`image_picker` 已是 JPEG，直接入草稿。
2. iOS 横条：`AssetEntity.file` 已是全尺寸 JPEG，直接用；不要用 `originFile`。
3. Android 横条：先读 `asset.mimeTypeAsync` 或 `asset.title` 扩展名；非 HEIC 直接用 `.file`。HEIC/未知则：

```dart
final bytes = await asset.thumbnailDataWithSize(
  ThumbnailSize(asset.width, asset.height), // 或长边上限 2560，见成本
  format: ThumbnailFormat.jpeg,
  quality: 90,
);
```

`thumbnailDataWithSize` 在原生侧解码并输出 JPEG；尺寸越大，解码内存越高。12 MP 图完整解码约 `4000×3000×4 B ≈ 48 MB` 瞬时内存（计算值，未实测），编码耗时与设备相关。聊天附件建议长边上限 2560 px，既避开原图内存峰值，也远高于屏幕显示需要。若业务要求原图画质，再放宽到 `asset.width/height`。

4. 若 `thumbnailDataWithSize` 返回 null 或抛错：不入草稿，Toast 现有 `uploadUnsupportedFormat`；不要回退上传 HEIC。
5. 不建议把 `heic`/`heif` 加进 `attachment_rules.dart` 白名单：服务端是否接受未验证，且现有白名单来自 `chat-demo/src/services/uploadExts.ts`，改白名单等于改上传契约。

### 备选：额外转码库

`flutter_image_compress 2.5.1`（MIT）可输出 JPEG，但 Android HEIC 编码/解码依赖 API 28+ 与设备编码器，官方也建议捕获 `UnsupportedError` 回退 JPEG；对本需求没有比「原生 `thumbnailDataWithSize`」更可靠，且多一个依赖。仅当需要保留原图尺寸并精细控制质量时再评估。[S50]

## 4. 文件落地、临时文件与清理

### 路径来源

| 来源 | iOS | Android |
|------|-----|---------|
| `photo_manager` 文件 | `NSTemporaryDirectory()` 下 `.image/`、`flutter-images/`；`flutter-images/<sha256>_exif.jpg` 为 `.file` 的 JPEG 缓存。[S23] | `context.cacheDir/pm_<assetId>[_o]_<displayName>`；content URI 复制而来。[S25] |
| `image_picker` 相册 | `NSTemporaryDirectory()/image_picker_<globallyUniqueString>.<jpg|png|gif>`。[S9] | `context.cacheDir/<uuid>/<fileName>`（保留/按 MIME 修正扩展名）。[S14] |
| `image_picker` 相机 | 同上，`.jpg`。[S9] | `context.cacheDir/<uuid>.jpg`。[S13] |

- Android 的 `content://` URI 不会直接交给上传层；插件已经复制成文件路径。现有 `_startUpload` 读 `DraftAttachment.path`，与 `http.MultipartFile.fromPath` 兼容。
- iOS 的 `PHAsset` 也不保证本地有文件；`.file`/`.originFile` 会按需从 iCloud 下载，可能失败或很慢。`photo_manager` 对原图请求设置了 `networkAccessAllowed = YES`。[S23]

### 生命周期与责任

- 这些目录都是 temp/cache：iOS 系统可清理 `NSTemporaryDirectory()`；Android 系统可在存储压力下清 `cacheDir`。`image_picker` 文档明确「picked from camera 的文件只应视为临时，需要长期保存要自己移动」。[S7]
- 草稿附件目前只存在内存（`chat_page.dart` 的 `_attachments`），跨会话不恢复；但一次上传可能持续数十秒，期间缓存被清理会失败。建议选中后立即复制到 `getApplicationSupportDirectory()/attachments/<uuid>.<ext>`，上传成功/移除/发送后删除；这也是统一扩展名（HEIC→JPEG 后改名 `.jpg`）的位置。
- `PhotoManager.clearFileCache()` 会删除 `.image`、`.video`、`flutter-images` 三个目录，不能在草稿/上传进行中调用。[S23][S20]
- Android 进程被系统杀死后，`image_picker` 的相册/相机结果可能丢失；官方要求启动时调用 `retrieveLostData()` 恢复。`retrieveLostData` 只处理「Activity 被回收」这一种情况，不覆盖 cache 被清理。[S7]

## 5. 缩略图尺寸、分页与内存

- 分页：`getAssetListPaged(page: 0, size: 30)`；产品要 30 张，一次取一页即可。若未来要无限滑，再 `page + 1`。[S19]
- 排序：显式 `OrderOption(type: OrderOptionType.createDate, asc: false)`；不要依赖 Android 默认 SQL（无 ORDER BY）。[S26][S27]
- 解码尺寸：横条单元格约 64 dp，3x 屏 192 px；`ThumbnailSize.square(200)` 或 `240` 足够，和 `photo_manager` 示例的 `vDefaultGridThumbnailSize = 200` 一致。[S18]
- 内存：200×200 RGBA 约 160 KB/张，30 张约 4.8 MB；300×300 约 10.8 MB。Flutter `ImageCache` 默认 100 MiB、1000 张，横条远低于上限。[S48]
- 风险：
  - `AssetEntityImage` 默认 `isOriginal: true`，会取全尺寸 `originBytes`；30 张 12 MP 原图约 1.4 GB 解码内存，必然 OOM。必须 `isOriginal: false`。[S46]
  - `thumbnailDataWithSize` 请求的尺寸越大，原生解码/编码越慢；不要在列表里请求 1024+。
  - iOS 缩略图请求 `networkAccessAllowed = YES`，iCloud-only 照片会触发下载，首屏可能长时间空白；需要 loading 占位与超时。[S23]
  - Android Glide 有 bitmap pool，但 30 张同时请求仍有峰值；建议 `cacheWidth`/固定 `thumbnailSize`，并限制并发（`ListView` 可视区 + 预取 1 屏）。
  - 缩略图缓存不是永久缓存：iOS 侧 `photo_manager` 不给缩略图落盘缓存（README 表格），每次冷启动要重新取；不要把它当离线资源。

## 6. 相机结果：方向、命名、大小

- iOS：
  - 控制器：`UIImagePickerController(sourceType: .camera)`；先检查硬件，再检查 `AVCaptureDevice` 相机权限；未决定则请求，拒绝/受限返回错误。[S11]
  - 输出：`UIImage` → `saveImage(withPickerInfo:)`，默认 JPEG、`.jpg`，文件名 `image_picker_<globallyUniqueString>.jpg`，目录 `NSTemporaryDirectory()`。[S9][S11]
  - 方向：插件把 `UIImagePickerController` 的 `mediaMetadata` 传入 `ImagePickerMetaDataUtil.image(fromImage:withMetaData:)`，按源编码重写元数据；方向是否被烘焙取决于 UIImage/EXIF，需真机验证（未验证）。
  - 大小：默认 `imageQuality = 100`（`convert` 中 `quality ?? 1`），不做缩放；相机 JPEG 通常几 MB，低于图片 64 MB 上限。[S9][S10]
- Android：
  - 不声明 `CAMERA` 时不申请权限；声明了才走 `permissionManager.askForPermission`。[S13]
  - 输出：`ACTION_IMAGE_CAPTURE` + `FileProvider` URI，目标文件 `cacheDir/<uuid>.jpg`；相机 App 写入，插件不重编码（除非后续 `imageQuality < 100` 或 `maxWidth/maxHeight`）。[S13][S15]
  - 方向：由相机 App 写 EXIF；插件不保证旋转归一化，显示/上传前应依赖解码器或服务端 EXIF 处理（未验证具体机型）。
  - 大小：原始相机输出；若设 `maxWidth/maxHeight` 或 `imageQuality < 100`，`ImageResizer` 会 `BitmapFactory` 解码后 JPEG 重编码（有 alpha 时 PNG），输出到 `cacheDir/scaled_<原名>`，**文件名可能保留原扩展名**，需要按魔数改名。[S15]
- 与 32/64 MB 限制：图片走 `uploadPurposeFor` 的 `null` 分支，上限是 `maxRichLayoutSizeMb = 64`；文档类才可能是 32 MB。正常相机 JPEG 不会触发，48 MP 高像素模式可能 15–25 MB，仍低于 64 MB。若开启 `imageQuality: 90` + 长边 2560，通常 < 2 MB，明显降低上传失败率。[S repo: attachment_rules.dart]

## 7. 版本约束与冲突

| 项 | 要求 | 本项目 | 结论 |
|----|------|--------|------|
| Flutter | `photo_manager` 分析于 3.50.0；`image_picker 1.2.4` 要求 >= 3.41 | 3.50.0 | 满足 |
| Dart | `photo_manager` >=2.13 <4；`image_picker` >=3.11 | 3.14.0 | 满足 |
| iOS | 发布版 `image_picker_ios 0.8.13+9` 支持 iOS 13+（main 分支已抬到 15.0）；`photo_manager` pod 9.0 / SPM 13.0 | 15.0 | 满足 |
| Android minSdk | `image_picker` 24；`photo_manager` 16 | 24（Flutter 3.50 默认） | 满足 |
| Android compileSdk | `photo_manager` 36 | 37 | 满足 |
| Kotlin/Gradle/AGP | `photo_manager` Kotlin 1.7.22+、Gradle 7.5.1+、AGP 7.2.2+ | Flutter 3.50 默认更高 | 满足 |
| `file_picker` | 13.4.0，Dart >=3.10 / Flutter >=3.38 | 已依赖 | 无冲突；FileProvider authority 不重叠 |

`photo_manager` 3.12.0 有一项行为变化：Darwin 端移除 CoreLocation，带坐标保存需要额外 `photo_manager_location` 包；本需求只读不写，不受影响。[S2]

## 风险与备选

1. **Google Play 宽泛照片权限（最高风险）**：Android 横条依赖 `READ_MEDIA_IMAGES`，聊天 App 不在官方明确允许的核心用例里，需 broad-access declaration 审核。被拒则 Android 去横条，保留拍照/系统相册/文件。[S39][S40]
2. **Android HEIC**：`image_picker` 与 `photo_manager` 默认都可能返回 HEIC；设备 HEIC 解码能力不一致。必须在入草稿前嗅探并转码，失败即拒绝。不要依赖扩展名。[S13][S14][S15][S25]
3. **Android Photo Picker 默认未开启**：13–15 必须显式 `useAndroidPhotoPicker = true`；否则走 `ACTION_GET_CONTENT`。README 与源码不一致，以源码为准。[S16][S17]
4. **iOS limited 下的入口**：必须提供「管理可访问照片」；否则用户无法在 App 内扩大可见范围。`permission_handler` 不能代替，需 `photo_manager.presentLimited`。[S31][S33][S42]
5. **iOS 17/18**：授权 API 未变，但系统提示/Photos App 形态变化；不要缓存授权状态，回前台重新查。[S31][S35]
6. **缓存被清理**：插件返回的路径都在 temp/cache；上传前复制到应用目录，移除/发送后清理。[S7][S23][S25]
7. **缩略图默认拉原图**：`AssetEntityImage`/`AssetEntityImageProvider` 默认 `isOriginal: true`，横条必须显式关闭。[S46]
8. **`photo_manager_image_provider` 陈旧**：2.2.0 两年未发版，pub 140/160；若不想承担，可用 `thumbnailDataWithSize` + `Image.memory` 自绘，代码量略高。
9. **未做端到端验证**：本票未安装依赖、未编译、未真机跑。Flutter 3.50 兼容性来自 pub 分析环境与 pubspec 约束，不等于本项目构建通过。HEIC 转码耗时、相机方向、iCloud 下载超时需实现期真机验证。

## 未验证清单

- `photo_manager` + `image_picker` 在本仓库 Flutter 3.50 工程中的实际编译/运行（未安装依赖）。
- Android 各 OEM 对 HEIC content URI 的转码行为，以及 `thumbnailDataWithSize` 在 HEIC 上的实际成功率与耗时。
- iOS 相机输出的 EXIF 方向在 Flutter `Image` 与服务端预览中的最终表现。
- Google Play broad-access declaration 对本 App 的审核结论。
- 包体积精确增量。
- iOS 17 全量访问周期性提醒的触发频率、是否可配置；Apple 未公开文档。

## 来源

访问日期均为 2026-11-20。

- [S1] photo_manager — pub.dev：https://pub.dev/packages/photo_manager
- [S2] photo_manager changelog：https://pub.dev/packages/photo_manager/changelog
- [S3] photo_manager score（分析环境 Flutter 3.50.0 / Dart 3.14.0）：https://pub.dev/packages/photo_manager/score
- [S4] image_picker — pub.dev：https://pub.dev/packages/image_picker
- [S5] image_picker changelog：https://pub.dev/packages/image_picker/changelog
- [S6] image_picker score：https://pub.dev/packages/image_picker/score
- [S7] image_picker README（iOS/Android 配置、临时文件、Photo Picker）：https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker/README.md
- [S8] image_picker Dart API（pickMultiImage/limit/imageQuality）：https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker/lib/image_picker.dart
- [S9] image_picker iOS `ImagePickerPhotoAssetUtil.swift`（临时目录、文件名、JPEG/PNG/GIF 保存）：https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios/ImagePickerPhotoAssetUtil.swift
- [S10] image_picker iOS `ImagePickerMetaDataUtil.swift`（首字节识别、HEIC 回落 JPEG）：https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios/ImagePickerMetaDataUtil.swift
- [S11] image_picker iOS `ImagePickerPlugin.swift`（相机/PHPicker、权限、imageQuality）：https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios/ImagePickerPlugin.swift
- [S12] image_picker iOS `PHPickerSaveImageToPathOperation.swift`（PHPicker 读 item provider 后重编码）：https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios/PHPickerSaveImageToPathOperation.swift
- [S13] image_picker Android `ImagePickerDelegate.java`（相机 `.jpg`、Photo Picker 选择、CAMERA 权限）：https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_android/android/src/main/java/io/flutter/plugins/imagepicker/ImagePickerDelegate.java
- [S14] image_picker Android `FileUtils.java`（content URI 复制到 cache）：https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_android/android/src/main/java/io/flutter/plugins/imagepicker/FileUtils.java
- [S15] image_picker Android `ImageResizer.java`（imageQuality/max 触发 JPEG 重编码）：https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_android/android/src/main/java/io/flutter/plugins/imagepicker/ImageResizer.java
- [S16] image_picker_android — pub.dev（Photo Picker 需显式开启）：https://pub.dev/packages/image_picker_android
- [S17] image_picker_android `useAndroidPhotoPicker` 源码：https://github.com/flutter/packages/blob/image_picker_android-v0.8.13%2B25/packages/image_picker/image_picker_android/lib/image_picker_android.dart
- [S18] photo_manager `thumbnail.dart`（ThumbnailSize / ThumbnailOption / ThumbnailFormat）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/lib/src/types/thumbnail.dart
- [S19] photo_manager `entity.dart`（AssetPathEntity 分页、AssetEntity file/originFile/thumbnail）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/lib/src/types/entity.dart
- [S20] photo_manager `photo_manager.dart`（getAssetPathList、requestPermissionExtend、presentLimited）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/lib/src/managers/photo_manager.dart
- [S21] photo_manager `filter_options.dart`（OrderOption 默认 createDate desc）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/lib/src/filter/classical/filter_options.dart
- [S22] photo_manager `filter_option_group.dart`（默认 orders 为空）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/lib/src/filter/classical/filter_option_group.dart
- [S23] photo_manager Darwin `PMManager.m`（`.file` 转 JPEG、origin 保留 HEIC、缓存目录、缩略图）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/darwin/photo_manager/Sources/photo_manager/core/PMManager.m
- [S24] photo_manager Darwin `PMPlugin.m`（limited 状态、presentLimited）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/darwin/photo_manager/Sources/photo_manager/PMPlugin.m
- [S25] photo_manager Android `ScopedCache.kt`（cacheDir 复制）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/android/src/main/kotlin/com/fluttercandies/photo_manager/core/cache/ScopedCache.kt
- [S26] photo_manager Android `IDBUtils.kt`（无 filter 时排序 SQL 只有 LIMIT/OFFSET）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/android/src/main/kotlin/com/fluttercandies/photo_manager/core/utils/IDBUtils.kt
- [S27] photo_manager Android `AndroidQDBUtils.kt`（getSortOrder 返回 null）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/android/src/main/kotlin/com/fluttercandies/photo_manager/core/utils/AndroidQDBUtils.kt
- [S28] photo_manager AndroidManifest：https://github.com/fluttercandies/flutter_photo_manager/blob/main/android/src/main/AndroidManifest.xml
- [S29] photo_manager `PermissionDelegate34.kt`（Android 14 partial）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/android/src/main/kotlin/com/fluttercandies/photo_manager/permission/impl/PermissionDelegate34.kt
- [S30] photo_manager Android build.gradle（Glide / exifinterface / compileSdk 36）：https://github.com/fluttercandies/flutter_photo_manager/blob/main/android/build.gradle
- [S31] Apple — Delivering an Enhanced Privacy Experience in Your Photos App：https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app
- [S32] Apple — Selecting Photos and Videos in iOS：https://developer.apple.com/documentation/photokit/selecting-photos-and-videos-in-ios
- [S33] Apple — presentLimitedLibraryPicker(from:completionHandler:)：https://developer.apple.com/documentation/photos/phphotolibrary/presentlimitedlibrarypicker(from:completionhandler:)
- [S34] Apple — PHAuthorizationStatus.limited：https://developer.apple.com/documentation/photos/phauthorizationstatus/limited
- [S35] Apple Newsroom 2023-06-05 — Powerful new privacy and security features：https://www.apple.com/newsroom/2023/06/apple-announces-powerful-new-privacy-and-security-features/
- [S36] Apple Developer Forums — PHPickerViewController in Limited Access photos mode：https://developer.apple.com/forums/thread/759040
- [S37] Android — Photo picker：https://developer.android.com/training/data-storage/shared/photopicker
- [S38] Android 14 — Partial photo/video access：https://developer.android.com/about/versions/14/changes/partial-photo-video-access
- [S39] Android — Access media files from shared storage：https://developer.android.com/training/data-storage/shared/media
- [S40] Google Play — Photo and video permissions policy：https://support.google.com/googleplay/android-developer/answer/15800983
- [S41] permission_handler — pub.dev：https://pub.dev/packages/permission_handler
- [S42] permission_handler_apple `PhotoPermissionStrategy.m`：https://github.com/Baseflow/flutter-permission-handler/blob/main/permission_handler_apple/ios/permission_handler_apple/Sources/permission_handler_apple/strategies/PhotoPermissionStrategy.m
- [S43] permission_handler_android `PermissionManager.java`：https://github.com/Baseflow/flutter-permission-handler/blob/main/permission_handler_android/android/src/main/java/com/baseflow/permissionhandler/PermissionManager.java
- [S44] wechat_assets_picker — pub.dev：https://pub.dev/packages/wechat_assets_picker
- [S45] wechat_assets_picker score：https://pub.dev/packages/wechat_assets_picker/score
- [S46] photo_manager_image_provider — pub.dev（AssetEntityImage 默认 isOriginal: true）：https://pub.dev/packages/photo_manager_image_provider
- [S47] photo_manager_image_provider score：https://pub.dev/packages/photo_manager_image_provider/score
- [S48] Flutter `ImageCache`（默认 100 MiB / 1000 张）：https://api.flutter.dev/flutter/painting/ImageCache-class.html
- [S49] Flutter 3.50 默认 minSdk 24 / targetSdk 36 / compileSdk 36（本机 `/Users/transon/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`；对应上游：https://github.com/flutter/flutter/blob/3.50.0/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt）
- [S50] flutter_image_compress — pub.dev（HEIC 平台限制与回退建议）：https://pub.dev/packages/flutter_image_compress
