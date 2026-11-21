# 01: 预置：依赖、平台权限与内存字段

**What to build:** 安装照片与相机依赖，声明 iOS / Android 权限，并给草稿附件增加
仅内存的来源资产字段。应用行为不变，但后续票可直接使用这些能力。

**Blocked by:** 无
**Status:** ready-for-agent

- [ ] `pubspec.yaml` 增加 `photo_manager ^3.12.0`、`image_picker ^1.2.4`，
      `image_picker_android` 与 `image_picker_platform_interface` 跟随
      `image_picker` 版本；`flutter pub get` 成功。
- [ ] iOS `Info.plist` 声明 `NSPhotoLibraryUsageDescription`、
      `NSCameraUsageDescription`、`PHPhotoLibraryPreventAutomaticLimitedAccessAlert = true`。
- [ ] Android Manifest 声明 `READ_MEDIA_IMAGES`、
      `READ_MEDIA_VISUAL_USER_SELECTED`、`READ_EXTERNAL_STORAGE`
      （`android:maxSdkVersion="32"`）。
- [ ] `DraftAttachment` 增加可选 `sourceAssetId`，仅存活于当前页面内存；
      不写数据库、不进导出、不新增迁移。
- [ ] `flutter analyze` 与 `flutter test` 全绿；iOS 与 Android 均可构建。
