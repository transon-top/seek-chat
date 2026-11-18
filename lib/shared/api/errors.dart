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

  ApiErrorCondition get condition => classifyApiError(kind, status);

  bool get retryable =>
      condition == ApiErrorCondition.network ||
      condition == ApiErrorCondition.rateLimited ||
      condition == ApiErrorCondition.serverBusy;
}

/// 状态码归类（`api.md` §5）；从已持久化的 [ReplyError] 复原条件时也用它。
ApiErrorCondition classifyApiError(ApiErrorKind kind, int? status) {
  if (status == null) {
    return kind == ApiErrorKind.network
        ? ApiErrorCondition.network
        : ApiErrorCondition.other;
  }
  if (status == 401) return ApiErrorCondition.unauthorized;
  if (status == 402) return ApiErrorCondition.insufficientBalance;
  if (status == 413) return ApiErrorCondition.tooLarge;
  if (status == 429) return ApiErrorCondition.rateLimited;
  if (status >= 500) return ApiErrorCondition.serverBusy;
  return ApiErrorCondition.other;
}

/// 条件到本地化键的映射，键名与 ARB 条目一致；控制器存状态时使用。
String localMessageKeyFor(ApiErrorCondition condition) => switch (condition) {
      ApiErrorCondition.unauthorized => LocalMessageKeys.apiErrorUnauthorized,
      ApiErrorCondition.insufficientBalance =>
        LocalMessageKeys.apiErrorInsufficientBalance,
      ApiErrorCondition.tooLarge => LocalMessageKeys.apiErrorTooLarge,
      ApiErrorCondition.rateLimited => LocalMessageKeys.apiErrorRateLimited,
      ApiErrorCondition.serverBusy => LocalMessageKeys.apiErrorServerBusy,
      ApiErrorCondition.network => LocalMessageKeys.apiErrorNetwork,
      ApiErrorCondition.other => LocalMessageKeys.apiErrorOther,
    };

/// 与 chat-demo 一致：非 [ApiException] 的未知错误按可重试处理。
bool isRetryable(Object error) => error is! ApiException || error.retryable;
