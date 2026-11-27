import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:seek_chat/features/chat/photo_import.dart';

import '../../support/photo_fakes.dart';

void main() {
  late Directory temp;
  late Directory output;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('photo_import_test');
    output = Directory('${temp.path}/out')..createSync();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  File write(String name, List<int> bytes) =>
      File('${temp.path}/$name')..writeAsBytesSync(bytes);

  test('accepts JPEG bytes and rejects other formats', () {
    final jpeg = write('photo.jpg', [0xFF, 0xD8, 0xFF, 0xE0, 0x00]);
    final png = write('photo.png', [0x89, 0x50, 0x4E, 0x47]);
    final missing = File('${temp.path}/missing.jpg');

    expect(isJpegFile(jpeg.path), isTrue);
    expect(isJpegFile(png.path), isFalse);
    expect(isJpegFile(missing.path), isFalse);

    final draft = draftFromPickedPhoto(XFile(jpeg.path));
    expect(draft, isNotNull);
    expect(draft!.name, 'photo.jpg');
    expect(draft.size, 5);
    expect(draft.isImage, isTrue);
    expect(draft.mimeType, 'image/jpeg');
    expect(draftFromPickedPhoto(XFile(png.path)), isNull);
  });

  test('keeps JPEG originals on iOS without transcoding', () async {
    final jpeg = write('IMG_1.jpg', [0xFF, 0xD8, 0xFF, 0xE1, 1, 2, 3]);
    final asset = FakePhotoAsset(id: 'asset-1', original: jpeg);

    final result = await draftFromPhotoAsset(
      asset,
      preferOriginalFile: true,
      outputDir: output,
      idFactory: () => 'draft-1',
    );

    final draft = result.draft!;
    expect(result.failure, isNull);
    expect(draft.path, '${output.path}/draft-1.jpg');
    expect(draft.name, 'draft-1.jpg');
    expect(draft.mimeType, 'image/jpeg');
    expect(draft.isImage, isTrue);
    expect(draft.sourceAssetId, 'asset-1');
    expect(draft.size, 7);
    expect(File(draft.path).readAsBytesSync(), [
      0xFF,
      0xD8,
      0xFF,
      0xE1,
      1,
      2,
      3,
    ]);
    expect(asset.transcodedCalls, 0);
  });

  test('transcodes non-JPEG originals to JPEG on iOS', () async {
    final heic = write('IMG_2.heic', [0x00, 0x00, 0x00, 0x18]);
    final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9]);
    final asset = FakePhotoAsset(
      id: 'asset-2',
      original: heic,
      transcoded: jpegBytes,
    );

    final result = await draftFromPhotoAsset(
      asset,
      preferOriginalFile: true,
      outputDir: output,
      idFactory: () => 'draft-2',
    );

    expect(result.draft, isNotNull);
    expect(File(result.draft!.path).readAsBytesSync(), jpegBytes);
    expect(result.draft!.name, 'draft-2.jpg');
    expect(result.draft!.mimeType, 'image/jpeg');
    expect(asset.originalCalls, 1);
    expect(asset.transcodedCalls, 1);
  });

  test('uses transcoded bytes on Android without touching originals', () async {
    final jpeg = write('IMG_3.jpg', [0xFF, 0xD8, 0xFF, 0xE0, 1]);
    final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 7]);
    final asset = FakePhotoAsset(
      id: 'asset-3',
      original: jpeg,
      transcoded: jpegBytes,
    );

    final result = await draftFromPhotoAsset(
      asset,
      preferOriginalFile: false,
      outputDir: output,
      idFactory: () => 'draft-3',
    );

    expect(File(result.draft!.path).readAsBytesSync(), jpegBytes);
    expect(asset.originalCalls, 0);
    expect(asset.transcodedCalls, 1);
  });

  test('rejects outputs that are still not JPEG', () async {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
    final asset = FakePhotoAsset(id: 'asset-4', transcoded: png);

    final result = await draftFromPhotoAsset(
      asset,
      preferOriginalFile: true,
      outputDir: output,
      idFactory: () => 'draft-4',
    );

    expect(result.draft, isNull);
    expect(result.failure, PhotoImportFailure.unreadable);
    expect(output.listSync(), isEmpty);
  });

  test('rejects photos above 64 MB', () async {
    final huge = write('IMG_5.jpg', [0xFF, 0xD8, 0xFF, 0xE0]);
    huge.openSync(mode: FileMode.append)
      ..truncateSync(maxPhotoSizeMb * 1024 * 1024 + 1)
      ..closeSync();
    final asset = FakePhotoAsset(id: 'asset-5', original: huge);

    final result = await draftFromPhotoAsset(
      asset,
      preferOriginalFile: true,
      outputDir: output,
      idFactory: () => 'draft-5',
    );

    expect(result.draft, isNull);
    expect(result.failure, PhotoImportFailure.tooLarge);
    expect(output.listSync(), isEmpty);
  });

  test('missing transcode bytes are unreadable', () async {
    final asset = FakePhotoAsset(id: 'asset-6');

    final result = await draftFromPhotoAsset(
      asset,
      preferOriginalFile: true,
      outputDir: output,
      idFactory: () => 'draft-6',
    );

    expect(result.draft, isNull);
    expect(result.failure, PhotoImportFailure.unreadable);
  });

  test('toggling a pending asset cancels its late result', () {
    final pending = PendingPhotoImports();

    final token = pending.toggle('asset-1')!;
    expect(pending.isCurrent('asset-1', token), isTrue);
    expect(pending.toggle('asset-1'), isNull);
    expect(pending.isCurrent('asset-1', token), isFalse);

    final again = pending.toggle('asset-1')!;
    expect(again, isNot(token));
    expect(pending.isCurrent('asset-1', again), isTrue);
    pending.finish('asset-1', again);
    expect(pending.isCurrent('asset-1', again), isFalse);
  });
}
