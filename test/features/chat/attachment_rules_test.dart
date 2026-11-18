import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/features/chat/attachment_rules.dart';
import 'package:open_chat/shared/models/types.dart';

void main() {
  group('扩展名', () {
    test('大小写不敏感，白名单外拒绝，无扩展名拒绝', () {
      expect(isAcceptedFileName('photo.PNG'), isTrue);
      expect(isAcceptedFileName('report.pdf'), isTrue);
      expect(isAcceptedFileName('archive.zip'), isFalse);
      expect(isAcceptedFileName('README'), isFalse);
      expect(isAcceptedFileName('.gitignore'), isFalse);
    });

    test('heic 不在白名单', () {
      expect(isAcceptedFileName('IMG_0001.HEIC'), isFalse);
    });
  });

  group('图片判定', () {
    test('按扩展名识别常见图片', () {
      for (final name in ['a.png', 'a.JPG', 'a.jpeg', 'a.gif', 'a.webp', 'a.svg']) {
        expect(isImageFileName(name), isTrue, reason: name);
      }
      expect(isImageFileName('a.pdf'), isFalse);
      expect(isImageFileName('a.txt'), isFalse);
    });
  });

  group('上传 purpose', () {
    test('图片不传 purpose，版面解析与 user_data 分开', () {
      expect(uploadPurposeFor('a.png', isImage: true), isNull);
      expect(
        uploadPurposeFor('a.pdf', isImage: false),
        UploadPurpose.richLayoutRecognition,
      );
      expect(
        uploadPurposeFor('a.DOCX', isImage: false),
        UploadPurpose.richLayoutRecognition,
      );
      expect(uploadPurposeFor('a.xlsx', isImage: false), UploadPurpose.userData);
      expect(uploadPurposeFor('a.dart', isImage: false), UploadPurpose.userData);
    });
  });

  group('大小限制', () {
    test('user_data 32 MB，其余 64 MB', () {
      expect(maxSizeMbFor('a.txt', isImage: false), 32);
      expect(maxSizeMbFor('a.xlsx', isImage: false), 32);
      expect(maxSizeMbFor('a.pdf', isImage: false), 64);
      expect(maxSizeMbFor('a.png', isImage: true), 64);
    });
  });

  group('批次校验', () {
    LocalMessage? validate(
      List<(String, int)> files, {
      int current = 0,
    }) =>
        validateAttachmentSelection(
          files: [
            for (final (name, size) in files)
              SelectedFile(name: name, size: size),
          ],
          currentCount: current,
        );

    test('任一格式不支持则整批拒绝', () {
      final error = validate([('a.png', 10), ('b.zip', 10)]);
      expect(error?.key, LocalMessageKeys.uploadUnsupportedFormat);
    });

    test('按单个文件的 purpose 取上限', () {
      final error = validate([('a.txt', 33 * 1024 * 1024)]);
      expect(error?.key, LocalMessageKeys.uploadMaxMBSize);
      expect(error?.params['size'], 32);

      expect(validate([('a.pdf', 33 * 1024 * 1024)]), isNull);
      expect(validate([('a.txt', 33 * 1024 * 1024)]), isNotNull);
    });

    test('数量超过 50 拒绝，包含已有数量', () {
      final files = [
        for (var i = 0; i < 50; i++) ('f$i.txt', 1),
      ];
      expect(validate(files), isNull);
      expect(
        validate(files, current: 1)?.key,
        LocalMessageKeys.uploadMaxFiles,
      );
    });
  });

  group('展示辅助', () {
    test('大小格式与扩展名', () {
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(1536), '1.5 KB');
      expect(formatFileSize(20 * 1024 * 1024), '20 MB');
      expect(fileExtensionUpper('report.final.PDF'), 'PDF');
      expect(fileExtensionUpper('README'), '');
    });
  });
}
