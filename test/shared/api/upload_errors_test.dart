import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/shared/api/errors.dart';
import 'package:open_chat/shared/models/types.dart';

ApiException httpError(int status, String message) =>
    ApiException(ApiErrorKind.http, message, status: status);

void main() {
  group('uploadErrorMessage', () {
    test('服务端繁忙与解析失败使用具体文案', () {
      expect(
        uploadErrorMessage(httpError(503, 'busy')).key,
        LocalMessageKeys.uploadServerBusy,
      );
      expect(
        uploadErrorMessage(
          httpError(400, 'Failed to recognize the file content'),
        ).key,
        LocalMessageKeys.uploadParseFailed,
      );
      expect(
        uploadErrorMessage(httpError(400, 'The image is too large to process'))
            .key,
        LocalMessageKeys.uploadParseFailed,
      );
    });

    test('其余失败统一上传失败', () {
      expect(
        uploadErrorMessage(httpError(401, 'bad key')).key,
        LocalMessageKeys.uploadFileStatusFailed,
      );
      expect(
        uploadErrorMessage(ApiException(ApiErrorKind.network, 'offline')).key,
        LocalMessageKeys.uploadFileStatusFailed,
      );
    });

    test('可重试性与错误分类一致', () {
      expect(httpError(503, 'busy').retryable, isTrue);
      expect(httpError(429, 'limited').retryable, isTrue);
      expect(
        ApiException(ApiErrorKind.network, 'offline').retryable,
        isTrue,
      );
      expect(httpError(400, 'The image is too large to process').retryable,
          isFalse);
      expect(httpError(401, 'bad key').retryable, isFalse);
    });
  });

  group('uploadQuotaMessage', () {
    test('文件数与存储配额提取上限', () {
      final count = uploadQuotaMessage(
        httpError(400, 'User file count limit exceeded, limit 100'),
      );
      expect(count?.key, LocalMessageKeys.uploadFileCountLimit);
      expect(count?.params['limit'], '100');

      final storage = uploadQuotaMessage(
        httpError(400, 'User storage quota exceeded, limit 50.5 GB'),
      );
      expect(storage?.key, LocalMessageKeys.uploadStorageLimit);
      expect(storage?.params['limit'], '50.5');
    });

    test('其他 400 与 5xx 不产生配额提示', () {
      expect(uploadQuotaMessage(httpError(500, 'limit 100')), isNull);
      expect(uploadQuotaMessage(httpError(400, 'other')), isNull);
    });
  });

  group('fileErrorCode', () {
    test('识别 file_id 失效的三类 400', () {
      expect(
        fileErrorCode(
          httpError(
            400,
            'file_ids do not exist or are not created under your account',
          ),
        ),
        FileErrorCode.fileIdMissing,
      );
      expect(
        fileErrorCode(httpError(400, 'file data not found for file_id x')),
        FileErrorCode.fileDataMissing,
      );
      expect(
        fileErrorCode(httpError(400, '...source.file_id: invalid file_id')),
        FileErrorCode.invalidFileId,
      );
    });

    test('非 400 与其他 400 不识别', () {
      expect(fileErrorCode(httpError(500, 'file data not found for file_id')),
          isNull);
      expect(fileErrorCode(httpError(400, 'bad purpose')), isNull);
      expect(fileErrorCode(ApiException(ApiErrorKind.network, '')), isNull);
    });
  });

  test('extractFileIds 去重保序', () {
    expect(
      extractFileIds(
        'file-api-abc is missing; file-api-def invalid; file-api-abc again',
      ),
      ['file-api-abc', 'file-api-def'],
    );
    expect(extractFileIds('no ids here'), isEmpty);
  });
}
