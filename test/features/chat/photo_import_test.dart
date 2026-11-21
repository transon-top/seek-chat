import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_chat/features/chat/photo_import.dart';

void main() {
  test('accepts JPEG bytes and rejects other formats', () {
    final dir = Directory.systemTemp.createTempSync('photo_import_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final jpeg = File('${dir.path}/photo.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 0x00]);
    final png = File('${dir.path}/photo.png')
      ..writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    final missing = File('${dir.path}/missing.jpg');

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
}
