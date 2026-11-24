import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:seek_chat/features/chat/photo_import.dart';
import 'package:seek_chat/features/chat/photo_strip.dart';

/// ZH
/// 1×1 PNG，供照片格缩略图测试解码。
///
/// EN
/// A 1×1 PNG for photo grid thumbnail tests to decode.
final Uint8List testPhotoThumbnail = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// ZH
/// 可配置的横条照片：只在内存，不触达 `photo_manager`。
///
/// EN
/// Configurable strip photo: in memory only, never touching `photo_manager`.
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

/// ZH
/// 可配置的 `PhotoLibrary`：覆盖权限四态、空图库、读取失败与「管理」返回。
///
/// EN
/// Configurable `PhotoLibrary`: four permission states, empty library, read failure, Manage return.
class FakePhotoLibrary implements PhotoLibrary {
  FakePhotoLibrary({
    this.status = PhotoAccessStatus.authorized,
    this.statusAfterRequest,
    this.fail = false,
    List<PhotoAsset>? assets,
  }) : assets = assets ?? const [];

  PhotoAccessStatus status;
  PhotoAccessStatus? statusAfterRequest;
  List<PhotoAsset> assets;
  bool fail = false;
  Completer<void>? gate;
  int accessCalls = 0;
  int requestCalls = 0;
  int loadCalls = 0;
  int lastLimit = 0;
  int presentLimitedCalls = 0;
  int settingsCalls = 0;

  @override
  Future<PhotoAccessStatus> access({required bool request}) async {
    accessCalls++;
    if (!request) return status;
    requestCalls++;
    if (statusAfterRequest != null) status = statusAfterRequest!;
    return status;
  }

  @override
  Future<List<PhotoAsset>> recentImages({int limit = 30}) async {
    loadCalls++;
    lastLimit = limit;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('load failed');
    return assets;
  }

  @override
  Future<void> presentLimited() async {
    presentLimitedCalls++;
  }

  @override
  Future<void> openSettings() async {
    settingsCalls++;
  }
}
