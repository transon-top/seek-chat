import '../models/types.dart';

/// ZH
/// `api.md` §5 的传输层错误分类。
///
/// [ApiErrorKind.upload] 是回复级取值：附件在消息请求发出前上传失败。
///
/// EN
/// Transport-layer error classification from `api.md` §5.
///
/// [ApiErrorKind.upload] is reply-level: an attachment upload failed before the message request.
class ApiException implements Exception {
  ApiException(this.kind, this.message, {this.status});

  final ApiErrorKind kind;
  final String message;
  final int? status;

  @override
  String toString() => 'ApiException(${kind.name}, $message, status: $status)';

  ApiErrorCondition get condition =>
      classifyApiError(kind, status, message: message);

  bool get retryable =>
      condition == ApiErrorCondition.network ||
      condition == ApiErrorCondition.rateLimited ||
      condition == ApiErrorCondition.serverBusy;
}

/// ZH
/// 状态码归类（`api.md` §5）；从已持久化的 [ReplyError] 复原条件时也用它。
///
/// 内容审核拒绝是唯一按错误文案识别的 400（`safety.md` §5），其余错因不能
/// 因为同为 400 被误判成审核。
///
/// EN
/// Status-code classification (`api.md` §5); also restores conditions from persisted [ReplyError].
///
/// A content-moderation refusal is the only 400 identified by message text (`safety.md` §5);
/// other causes must not be misread as moderation just because they are also 400.
ApiErrorCondition classifyApiError(
  ApiErrorKind kind,
  int? status, {
  String? message,
}) {
  if (status == null) {
    return kind == ApiErrorKind.network
        ? ApiErrorCondition.network
        : ApiErrorCondition.other;
  }
  if (status == 400 &&
      _contentRejectedPattern.hasMatch(message ?? '')) {
    return ApiErrorCondition.contentRejected;
  }
  if (status == 401) return ApiErrorCondition.unauthorized;
  if (status == 402) return ApiErrorCondition.insufficientBalance;
  if (status == 413) return ApiErrorCondition.tooLarge;
  if (status == 429) return ApiErrorCondition.rateLimited;
  if (status >= 500) return ApiErrorCondition.serverBusy;
  return ApiErrorCondition.other;
}

final RegExp _contentRejectedPattern = RegExp(
  r'Content Exists Risk',
  caseSensitive: false,
);

/// ZH
/// 条件到本地化键的映射，键名与 ARB 条目一致；控制器存状态时使用。
///
/// EN
/// Condition-to-key mapping with ARB-matching names, used when controllers store state.
String localMessageKeyFor(ApiErrorCondition condition) => switch (condition) {
      ApiErrorCondition.unauthorized => LocalMessageKeys.apiErrorUnauthorized,
      ApiErrorCondition.insufficientBalance =>
        LocalMessageKeys.apiErrorInsufficientBalance,
      ApiErrorCondition.tooLarge => LocalMessageKeys.apiErrorTooLarge,
      ApiErrorCondition.rateLimited => LocalMessageKeys.apiErrorRateLimited,
      ApiErrorCondition.serverBusy => LocalMessageKeys.apiErrorServerBusy,
      ApiErrorCondition.network => LocalMessageKeys.apiErrorNetwork,
      ApiErrorCondition.contentRejected =>
        LocalMessageKeys.apiErrorContentRejected,
      ApiErrorCondition.other => LocalMessageKeys.apiErrorOther,
    };

/// ZH
/// 与 chat-demo 一致：非 [ApiException] 的未知错误按可重试处理。
///
/// EN
/// Like chat-demo: unknown non-[ApiException] errors are treated as retryable.
bool isRetryable(Object error) => error is! ApiException || error.retryable;

/// ZH
/// 附件上传失败显示在卡片上的文案（`attachments.md` §6）。
/// 服务端原文多为英文且较长，不直接展示。
///
/// EN
/// Text shown on the card when an attachment upload fails (`attachments.md` §6).
/// Server messages are mostly long English text, so they are not shown directly.
LocalMessage uploadErrorMessage(Object error) {
  if (error is ApiException && error.condition == ApiErrorCondition.serverBusy) {
    return const LocalMessage(key: LocalMessageKeys.uploadServerBusy);
  }
  if (uploadErrorInfo(error)?.code == UploadErrorCode.parseFailed) {
    return const LocalMessage(key: LocalMessageKeys.uploadParseFailed);
  }
  return const LocalMessage(key: LocalMessageKeys.uploadFileStatusFailed);
}

/// ZH
/// 配额类上传失败的额外提示：附件上只放「上传失败」，原因用 Toast 说明。
///
/// EN
/// Extra hint for quota failures: the attachment shows "Upload failed"; a toast explains why.
LocalMessage? uploadQuotaMessage(Object error) {
  final info = uploadErrorInfo(error);
  return switch (info?.code) {
    UploadErrorCode.fileCountLimit => LocalMessage(
        key: LocalMessageKeys.uploadFileCountLimit,
        params: {'limit': info?.limit ?? ''},
      ),
    UploadErrorCode.storageLimit => LocalMessage(
        key: LocalMessageKeys.uploadStorageLimit,
        params: {'limit': info?.limit ?? ''},
      ),
    _ => null,
  };
}

enum UploadErrorCode { fileCountLimit, storageLimit, parseFailed }

final class UploadErrorInfo {
  const UploadErrorInfo(this.code, {this.limit});

  final UploadErrorCode code;
  final String? limit;
}

/// ZH
/// 服务端无法解析文件内容：图片损坏或尺寸过大、格式不受支持、加密、文档解析失败。
///
/// EN
/// Unparsable file: corrupt or oversized image, unsupported format, encryption, or parse failure.
final List<RegExp> _parseFailedPatterns = [
  RegExp(r'You have uploaded an (unsupported|invalid) (file|image)',
      caseSensitive: false),
  RegExp(r'The image is too large to process', caseSensitive: false),
  RegExp(r'password-protected', caseSensitive: false),
  RegExp(r'Failed to recognize the file', caseSensitive: false),
];

/// ZH
/// 识别 Files API 上传的 400；配额类文案带上限数值。
///
/// EN
/// Recognize Files API upload 400s; quota messages include the limit value.
UploadErrorInfo? uploadErrorInfo(Object error) {
  if (error is! ApiException ||
      error.kind != ApiErrorKind.http ||
      error.status != 400) {
    return null;
  }
  final message = error.message;
  final count = RegExp(
    r'User file count limit exceeded.*?limit (\d+)',
    caseSensitive: false,
  ).firstMatch(message);
  if (count != null) {
    return UploadErrorInfo(
      UploadErrorCode.fileCountLimit,
      limit: count.group(1),
    );
  }
  final storage = RegExp(
    r'User storage quota exceeded.*?limit ([\d.]+) GB',
    caseSensitive: false,
  ).firstMatch(message);
  if (storage != null) {
    return UploadErrorInfo(
      UploadErrorCode.storageLimit,
      limit: storage.group(1),
    );
  }
  if (_parseFailedPatterns.any((pattern) => pattern.hasMatch(message))) {
    return const UploadErrorInfo(UploadErrorCode.parseFailed);
  }
  return null;
}

/// ZH
/// 服务端判定附件失效的情况：本地有原件时重新上传即可自愈。
///
/// EN
/// Server-side attachment invalidation; with a local original, re-uploading heals it.
enum FileErrorCode { fileIdMissing, fileDataMissing, invalidFileId }

final List<(FileErrorCode, RegExp)> _fileErrorPatterns = [
  (
    FileErrorCode.fileIdMissing,
    RegExp(
      r'file_ids do not exist or are not created under your account',
      caseSensitive: false,
    ),
  ),
  (
    FileErrorCode.fileDataMissing,
    RegExp(r'file data not found for file_id', caseSensitive: false),
  ),
  (
    FileErrorCode.invalidFileId,
    RegExp(r'\.source\.file_id: invalid file_id', caseSensitive: false),
  ),
];

/// ZH
/// 只识别「附件 file_id 失效」这一类 400，其他错误保持原有失败提示。
///
/// EN
/// Recognize only "attachment file_id invalid" 400s; other errors keep the existing failure text.
FileErrorCode? fileErrorCode(Object error) {
  if (error is! ApiException ||
      error.kind != ApiErrorKind.http ||
      error.status != 400) {
    return null;
  }
  for (final (code, pattern) in _fileErrorPatterns) {
    if (pattern.hasMatch(error.message)) return code;
  }
  return null;
}

/// ZH
/// 从报错文案里取出服务端 file_id，用于只重置真正失效的附件。
///
/// EN
/// Extract server file_ids from error text to reset only the attachments that truly failed.
List<String> extractFileIds(String message) => {
      ...RegExp(r'file-api-[\w-]+').allMatches(message).map((m) => m[0]!),
    }.toList();
