# 01: 预置：依赖、平台权限与内存字段

**What to build:** 安装照片与相机依赖，声明 iOS / Android 权限，并给草稿附件增加
仅内存的来源资产字段。应用行为不变，但后续票可直接使用这些能力。

**Blocked by:** 无
**Status:** resolved
**Type:** task

- [x] `pubspec.yaml` 增加 `photo_manager ^3.12.0`、`image_picker ^1.2.4`，
      `image_picker_android` 与 `image_picker_platform_interface` 跟随
      `image_picker` 版本；`flutter pub get` 成功。
- [x] iOS `Info.plist` 声明 `NSPhotoLibraryUsageDescription`、
      `NSCameraUsageDescription`、`PHPhotoLibraryPreventAutomaticLimitedAccessAlert = true`。
- [x] Android Manifest 声明 `READ_MEDIA_IMAGES`、
      `READ_MEDIA_VISUAL_USER_SELECTED`、`READ_EXTERNAL_STORAGE`
      （`android:maxSdkVersion="32"`）。
- [x] `DraftAttachment` 增加可选 `sourceAssetId`，仅存活于当前页面内存；
      不写数据库、不进导出、不新增迁移。
- [x] `flutter analyze` 与 `flutter test` 全绿；iOS 与 Android 均可构建。

## Answer

- 依赖：`photo_manager 3.12.0`、`image_picker 1.2.4`；解析带入
  `image_picker_android 0.8.13+25`、`image_picker_platform_interface 2.11.2`。
- iOS `Info.plist`：新增相册 / 相机用途说明与
  `PHPhotoLibraryPreventAutomaticLimitedAccessAlert = true`。
- Android `AndroidManifest.xml`：新增 `READ_MEDIA_IMAGES`、
  `READ_MEDIA_VISUAL_USER_SELECTED`、`READ_EXTERNAL_STORAGE`（`maxSdkVersion=32`）。
- `DraftAttachment` 新增可选 `sourceAssetId`；无序列化路径，未改表、未加迁移。
- 验证：`flutter analyze` 无问题；`flutter test` 420 通过；
  `flutter build apk --debug` 与 `flutter build ios --debug --no-codesign` 均成功。
- 备注：Android 构建出现 photo_manager 的 KGP 弃用警告，当前 Flutter 版本仅警告，
  不影响本票；升级 Flutter 前需跟进插件版本。
