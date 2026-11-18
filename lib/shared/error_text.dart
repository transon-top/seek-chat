import 'package:flutter/foundation.dart';

import '../l10n/generated/app_localizations.dart';
import '../shared/api/errors.dart';
import '../shared/models/types.dart';

/// 错误文案的唯一映射点（architecture.md §5）。服务端原文只在 debug 构建、
/// 且可映射条件为 `other` 时附在本地化文案后；release 不展示原文。
String apiErrorText(
  AppLocalizations l10n,
  ApiErrorCondition condition, {
  String? detail,
}) {
  final text = switch (condition) {
    ApiErrorCondition.unauthorized => l10n.apiErrorUnauthorized,
    ApiErrorCondition.insufficientBalance => l10n.apiErrorInsufficientBalance,
    ApiErrorCondition.tooLarge => l10n.apiErrorTooLarge,
    ApiErrorCondition.rateLimited => l10n.apiErrorRateLimited,
    ApiErrorCondition.serverBusy => l10n.apiErrorServerBusy,
    ApiErrorCondition.network => l10n.apiErrorNetwork,
    ApiErrorCondition.other => l10n.apiErrorOther,
  };
  if (condition != ApiErrorCondition.other || !kDebugMode) return text;
  final raw = detail?.trim() ?? '';
  return raw.isEmpty ? text : '$text\n$raw';
}

/// 回复级错误优先 `localMessage`，否则按 `kind`/`status` 归类到通用文案。
String replyErrorText(AppLocalizations l10n, ReplyError error) {
  final local = error.localMessage;
  if (local != null) return localMessageText(l10n, local);
  return apiErrorText(
    l10n,
    classifyApiError(error.kind, error.status),
    detail: error.message,
  );
}

String localMessageText(AppLocalizations l10n, LocalMessage message) {
  switch (message.key) {
    case LocalMessageKeys.errorNoApiKey:
      return l10n.errorNoApiKey;
    case LocalMessageKeys.errorSaveReplyFailed:
      return l10n.errorSaveReplyFailed('${message.params['error'] ?? ''}');
    case LocalMessageKeys.apiErrorUnauthorized:
      return l10n.apiErrorUnauthorized;
    case LocalMessageKeys.apiErrorInsufficientBalance:
      return l10n.apiErrorInsufficientBalance;
    case LocalMessageKeys.apiErrorTooLarge:
      return l10n.apiErrorTooLarge;
    case LocalMessageKeys.apiErrorRateLimited:
      return l10n.apiErrorRateLimited;
    case LocalMessageKeys.apiErrorServerBusy:
      return l10n.apiErrorServerBusy;
    case LocalMessageKeys.apiErrorNetwork:
      return l10n.apiErrorNetwork;
    default:
      return apiErrorText(
        l10n,
        ApiErrorCondition.other,
        detail: message.params['detail']?.toString(),
      );
  }
}
