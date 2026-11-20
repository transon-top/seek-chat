# 照片横条与相机/相册依赖调研

Type: research
Status: resolved
Blocked by:

## Question

为「设备最近照片横条 + 拍照 + 系统相册多选 + 文件」选定并验证技术组合。只用一手来源（插件官方文档/源码、Apple/Android 官方文档、pub.dev 页面）回答：

1. 依赖组合：`photo_manager`（最近资产分页、缩略图、原图路径）+ `image_picker`（相机、系统相册）是否最优；对比 `wechat_assets_picker`、`photo_manager_image_provider`、`image_picker` 单干等。维护活跃度、许可证、包体积、Flutter 3.50 兼容。
2. 权限：iOS 14+ 受限照片访问（`.limited`）如何表现与请求；iOS 17/18 的变更；Android 13+ `READ_MEDIA_IMAGES`、Android 14 部分访问、Android 系统照片选择器；`permission_handler` 是否覆盖照片权限；项目需要新增的 `Info.plist` / `AndroidManifest.xml` 条目。
3. HEIC/HEIF：iPhone 相册原图常见格式；现有附件白名单不含 heic/heif；插件能否返回 JPEG（转码时机、质量、成本），相机输出什么格式，失败如何降级。
4. 文件落地：选中资产如何得到可上传的本地路径（Android content URI / iOS PhotoKit 资源）；临时文件生命周期与清理责任。
5. 缩略图：分页大小、建议解码尺寸、内存与滚动性能风险。
6. 相机：权限、拍摄结果方向/命名/大小，与现有 32/64 MB 限制的关系。
7. 版本约束与冲突：`file_picker` 13.4.0、iOS 15 部署目标、Android minSdk、Flutter 3.50。

## Deliverable

`evidence/photo-picker.md`：结论表、依赖与版本、平台配置清单、HEIC 处理路径、风险与备选；票内 Answer 摘要 + 逐条来源链接。不改产品代码。

## Answer

推荐组合：`photo_manager ^3.12.0` + `image_picker ^1.2.4`；`photo_manager` 只做最近照片分页/缩略图/横条选中资产落地，`image_picker` 做拍照与系统相册多选。`wechat_assets_picker` 不需要；`photo_manager_image_provider ^2.2.0` 可选（只提供缩略图 widget，两年未发版）。两包在 Flutter 3.50.0 / Dart 3.14.0 下均通过 pub 分析；与 `file_picker 13.4.0`、iOS 15、Android minSdk 24 无冲突。完整证据、代码路径与来源见 `evidence/photo-picker.md`。

1. 依赖：`photo_manager` 3.12.0（Apache-2.0，周下载 50 万）；`image_picker` 1.2.4（Apache-2.0/BSD-3，周下载 630 万）。`image_picker` 单干无法实现「最近照片横条」；`wechat_assets_picker` 自带整套选择 UI，与本图内联面板冲突。[photo_manager](https://pub.dev/packages/photo_manager)、[image_picker](https://pub.dev/packages/image_picker)、[wechat_assets_picker](https://pub.dev/packages/wechat_assets_picker)

2. 权限：iOS 用 `photo_manager.requestPermissionExtend`；`.limited` 时只显示已授权资产，用 `PhotoManager.presentLimited(type: RequestType.image)` 提供「管理可访问照片」入口。iOS 17/18 未发现 PhotoKit 授权 API 变更；iOS 17 起系统增加全量访问的周期性提醒（系统侧，不可由 App 控制）。Android 13+ 要 `READ_MEDIA_IMAGES`；Android 14+ 部分访问要 `READ_MEDIA_VISUAL_USER_SELECTED`，`photo_manager` 会申请并映射为 limited。`permission_handler` 能读 limited 状态，但不能拉起 iOS 的 limited 选择器，Android 也不会主动申请 `READ_MEDIA_VISUAL_USER_SELECTED`，所以照片权限交给 `photo_manager`；相机由 `image_picker` 自理。系统相册（PHPicker / Android Photo Picker）不需要存储权限。[Apple limited 文档](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app)、[Apple 2023-06-05 隐私公告](https://www.apple.com/newsroom/2023/06/apple-announces-powerful-new-privacy-and-security-features/)、[Android 14 partial access](https://developer.android.com/about/versions/14/changes/partial-photo-video-access)、[Android photo picker](https://developer.android.com/training/data-storage/shared/photopicker)

3. HEIC：`image_picker` iOS 的相册与相机都输出 JPEG（PHPicker 结果经 `UIImage` 重编码；HEIC 首字节识别不到，回落 `.jpg` + JPEG）。`photo_manager` iOS `.file` 输出全尺寸 JPEG；`.originFile` 走 PHAssetResource，未编辑资产通常是 HEIC，不能假定是 JPEG。Android `image_picker` 默认原样复制，HEIC 可能仍是 `.heic`；`photo_manager` Android `.file` 也不保证转码。横条选中资产需按魔数/扩展名识别 HEIC，Android 用 `thumbnailDataWithSize(ThumbnailSize(asset.width, asset.height), format: ThumbnailFormat.jpeg, quality: 90)` 转 JPEG；失败拒绝入草稿并 Toast。不要把 heic/heif 加进白名单。[image_picker iOS 源码](https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios/ImagePickerMetaDataUtil.swift)、[photo_manager PMManager.m](https://github.com/fluttercandies/flutter_photo_manager/blob/main/darwin/photo_manager/Sources/photo_manager/core/PMManager.m)

4. 文件落地：Android 的 content URI 由插件复制到 cache 后返回路径；iOS PhotoKit 资源由插件导出/缓存到 `NSTemporaryDirectory()`。`image_picker` 的相机/相册产物同样在 temp/cache。上传前应复制到应用自己的目录，移除/发送后删除；`PhotoManager.clearFileCache()` 不能在草稿上传中调用。Android 进程被回收时用 `retrieveLostData()` 恢复。[image_picker README](https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker/README.md)

5. 缩略图：`getAssetListPaged(page: 0, size: 30)`，显式 `OrderOption(type: createDate, asc: false)`（Android 不传 filter 时 SQL 没有 ORDER BY）。缩略图建议 `200×200`；30 张约 4.8 MB 解码内存（200×200×4 B×30），Flutter ImageCache 默认 100 MiB。`AssetEntityImage` 默认 `isOriginal: true` 会拉原图，横条必须设 `isOriginal: false` + `thumbnailSize`。[photo_manager 缩略图](https://github.com/fluttercandies/flutter_photo_manager/blob/main/lib/src/types/thumbnail.dart)、[ImageCache](https://api.flutter.dev/flutter/painting/ImageCache-class.html)

6. 相机：iOS `UIImagePickerController` 输出 `NSTemporaryDirectory()/image_picker_<guid>.jpg`；Android `ACTION_IMAGE_CAPTURE` 输出 `cacheDir/<uuid>.jpg`。iOS 需 `NSCameraUsageDescription`；Android 不声明 `CAMERA` 就不会额外申请权限。照片上限 64 MB，正常相机输出远低于此；建议 `imageQuality: 90` + 长边 2560 降低上传失败率。[image_picker iOS 源码](https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios/ImagePickerPhotoAssetUtil.swift)、[Android 相机源码](https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_android/android/src/main/java/io/flutter/plugins/imagepicker/ImagePickerDelegate.java)

7. 配置：iOS 新增 `NSPhotoLibraryUsageDescription`、`NSCameraUsageDescription`、`PHPhotoLibraryPreventAutomaticLimitedAccessAlert=true`；Android 新增 `READ_MEDIA_IMAGES`、`READ_MEDIA_VISUAL_USER_SELECTED`、`READ_EXTERNAL_STORAGE maxSdkVersion=32`。Android 13–15 要用系统 Photo Picker，需在首次调用前把已注册实例的 flag 打开：`(ImagePickerPlatform.instance as ImagePickerAndroid).useAndroidPhotoPicker = true`（Android 16+ 自动）；这需要直接依赖 `image_picker_android` 与 `image_picker_platform_interface`，因为 `image_picker` 不导出它们。不想加两个直接依赖时可接受 13–15 走 `ACTION_GET_CONTENT`（仍可多选、无需权限，但不是 Photo Picker，`limit` 不保证）。README 说 13+ 自动，与 0.8.13+25 源码不一致。

最大风险：Google Play 的 `READ_MEDIA_IMAGES` 属受限权限，聊天 App 未在官方明确允许的核心用例中，需 broad-access 审核；被拒则 Android 去掉照片横条，只保留拍照/系统相册/文件。其余风险：Android HEIC 解码不一致、iOS limited 无管理入口、插件缓存被系统清理、`AssetEntityImage` 默认拉原图、`photo_manager_image_provider` 陈旧。本票未安装依赖、未编译、未真机验证；HEIC 转码成功率与相机方向需实现期验证。
