import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:uuid/uuid.dart';

import '../../shared/models/types.dart';

/// 相机 / 相册产物的嗅探与草稿转换（票 02；照片横条转码在票 03 加入）。
///
/// 只接受 JPEG 字节；文件名与大小沿用系统选择器返回值。
bool isJpegFile(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final header = file.readSync(3);
    return isJpegBytes(header);
  } on FileSystemException {
    return false;
  } finally {
    file?.closeSync();
  }
}

/// JPEG 以 `FF D8 FF` 开头（`attachments.md` §9.3）。
bool isJpegBytes(List<int> bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xFF &&
    bytes[1] == 0xD8 &&
    bytes[2] == 0xFF;

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

/// 横条里的一张设备照片；抽象掉 `photo_manager` 以便测试注入。
abstract interface class PhotoAsset {
  String get id;

  /// 照片格 200×200 缩略图（JPEG）。
  Future<Uint8List?> thumbnail();

  /// 原始文件；iOS 优先直接使用 JPEG 原件。
  Future<File?> originalFile();

  /// 转码后的 JPEG 字节（质量 90、长边 ≤2560）。
  Future<Uint8List?> transcodedJpeg();
}

/// 横条转码登记：同一资产再次点击返回 null 表示取消，旧结果凭令牌作废。
final class PendingPhotoImports {
  final Map<String, int> _tokens = {};
  int _sequence = 0;

  int? toggle(String assetId) {
    if (_tokens.remove(assetId) != null) return null;
    final token = ++_sequence;
    _tokens[assetId] = token;
    return token;
  }

  bool isCurrent(String assetId, int token) => _tokens[assetId] == token;

  void finish(String assetId, int token) {
    if (_tokens[assetId] == token) _tokens.remove(assetId);
  }
}

enum PhotoImportFailure { unreadable, tooLarge }

final class PhotoImportResult {
  const PhotoImportResult.ready(DraftAttachment this.draft) : failure = null;

  const PhotoImportResult.failed(PhotoImportFailure this.failure)
    : draft = null;

  final DraftAttachment? draft;
  final PhotoImportFailure? failure;
}

const int maxPhotoSizeMb = 64;

/// 横条资产转 JPEG：iOS 优先 JPEG 原件，其余一律用转码字节（`attachments.md` §9.3）。
///
/// 输出复制到应用临时目录并命名为 `<id>.jpg`；仍非 JPEG → [PhotoImportFailure.unreadable]，
/// 超过 64 MB → [PhotoImportFailure.tooLarge]。草稿不落库，`sourceAssetId` 仅内存。
Future<PhotoImportResult> draftFromPhotoAsset(
  PhotoAsset asset, {
  required bool preferOriginalFile,
  required Directory outputDir,
  String Function()? idFactory,
}) async {
  final id = (idFactory ?? const Uuid().v4)();
  const maxBytes = maxPhotoSizeMb * 1024 * 1024;
  try {
    Uint8List? bytes;
    File? source;
    if (preferOriginalFile) {
      final original = await asset.originalFile();
      if (original != null && isJpegFile(original.path)) {
        if (original.lengthSync() > maxBytes) {
          return const PhotoImportResult.failed(PhotoImportFailure.tooLarge);
        }
        source = original;
      }
    }
    if (source == null) {
      bytes = await asset.transcodedJpeg();
      if (bytes == null || !isJpegBytes(bytes)) {
        return const PhotoImportResult.failed(PhotoImportFailure.unreadable);
      }
      if (bytes.length > maxBytes) {
        return const PhotoImportResult.failed(PhotoImportFailure.tooLarge);
      }
    }
    final target = File('${outputDir.path}/$id.jpg');
    if (bytes != null) {
      await target.writeAsBytes(bytes, flush: true);
    } else {
      await source!.copy(target.path);
    }
    return PhotoImportResult.ready(
      DraftAttachment(
        id: id,
        path: target.path,
        name: '$id.jpg',
        size: await target.length(),
        isImage: true,
        mimeType: 'image/jpeg',
        sourceAssetId: asset.id,
      ),
    );
  } on Object {
    return const PhotoImportResult.failed(PhotoImportFailure.unreadable);
  }
}
