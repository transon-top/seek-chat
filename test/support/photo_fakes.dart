import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_chat/features/chat/photo_import.dart';

/// 1×1 PNG，供照片格缩略图测试解码。
final Uint8List testPhotoThumbnail = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 可配置的横条照片：只在内存，不触达 `photo_manager`。
class FakePhotoAsset implements PhotoAsset {
  FakePhotoAsset({
    required this.id,
    this.original,
    this.transcoded,
    Uint8List? thumbnail,
  }) : thumbnailBytes = thumbnail ?? testPhotoThumbnail;

  @override
  final String id;
  File? original;
  Uint8List? transcoded;
  Uint8List? thumbnailBytes;
  int originalCalls = 0;
  int transcodedCalls = 0;

  @override
  Future<File?> originalFile() async {
    originalCalls++;
    return original;
  }

  @override
  Future<Uint8List?> thumbnail() async => thumbnailBytes;

  @override
  Future<Uint8List?> transcodedJpeg() async {
    transcodedCalls++;
    return transcoded;
  }
}
