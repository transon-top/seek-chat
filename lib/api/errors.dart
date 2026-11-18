import '../models/types.dart';

/// `api.md` §5 的传输层错误分类。
///
/// [ApiErrorKind.upload] 是回复级取值：附件在消息请求发出前上传失败。
class ApiException implements Exception {
  ApiException(this.kind, this.message, {this.status});

  final ApiErrorKind kind;
  final String message;
  final int? status;

  @override
  String toString() => 'ApiException(${kind.name}, $message, status: $status)';

  ApiErrorCondition get condition {
    if (status == null) {
      return kind == ApiErrorKind.network
          ? ApiErrorCondition.network
          : ApiErrorCondition.other;
    }
    if (status == 401) return ApiErrorCondition.unauthorized;
    if (status == 402) return ApiErrorCondition.insufficientBalance;
    if (status == 413) return ApiErrorCondition.tooLarge;
    if (status == 429) return ApiErrorCondition.rateLimited;
    if (status! >= 500) return ApiErrorCondition.serverBusy;
    return ApiErrorCondition.other;
  }

  bool get retryable =>
      condition == ApiErrorCondition.network ||
      condition == ApiErrorCondition.rateLimited ||
      condition == ApiErrorCondition.serverBusy;
}

/// 与 chat-demo 一致：非 [ApiException] 的未知错误按可重试处理。
bool isRetryable(Object error) => error is! ApiException || error.retryable;
