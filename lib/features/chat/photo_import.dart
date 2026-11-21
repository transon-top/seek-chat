import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:uuid/uuid.dart';

import '../../shared/models/types.dart';

/// 相机 / 相册产物的嗅探与草稿转换（票 02；HEIC 转码在票 03 加入）。
///
/// 只接受 JPEG 字节；文件名与大小沿用系统选择器返回值。
bool isJpegFile(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final header = file.readSync(3);
    return header.length == 3 &&
        header[0] == 0xFF &&
        header[1] == 0xD8 &&
        header[2] == 0xFF;
  } on FileSystemException {
    return false;
  } finally {
    file?.closeSync();
  }
}

/// 非 JPEG 或读取失败返回 null；调用方据此提示 `photoUnreadable`。
DraftAttachment? draftFromPickedPhoto(XFile file) {
  if (!isJpegFile(file.path)) return null;
  return DraftAttachment(
    id: const Uuid().v4(),
    path: file.path,
    name: file.name,
    size: File(file.path).lengthSync(),
    isImage: true,
    mimeType: 'image/jpeg',
  );
}

/// Android 13–15 显式启用系统 Photo Picker；Android 16+ 由插件强制使用。
ImagePicker createImagePicker() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final platform = ImagePickerPlatform.instance;
    if (platform is ImagePickerAndroid) {
      platform.useAndroidPhotoPicker = true;
    }
  }
  return ImagePicker();
}
