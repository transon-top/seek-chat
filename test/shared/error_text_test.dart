import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/shared/error_text.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/api/errors.dart';
import 'package:open_chat/shared/models/types.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('maps API conditions to the current locale', () {
    expect(apiErrorText(zh, ApiErrorCondition.unauthorized), 'API Key 无效');
    expect(apiErrorText(en, ApiErrorCondition.unauthorized), 'Invalid API key');
    expect(apiErrorText(zh, ApiErrorCondition.network), '网络错误，请检查连接');
    expect(
      apiErrorText(en, ApiErrorCondition.rateLimited),
      'Too many requests. Try again later.',
    );
    expect(apiErrorText(zh, ApiErrorCondition.other), '发生错误，请重试');
  });

  test('classifies a persisted reply error by kind and status', () {
    expect(
      classifyApiError(ApiErrorKind.http, 402),
      ApiErrorCondition.insufficientBalance,
    );
    expect(
      classifyApiError(ApiErrorKind.http, 429),
      ApiErrorCondition.rateLimited,
    );
    expect(
      classifyApiError(ApiErrorKind.http, 503),
      ApiErrorCondition.serverBusy,
    );
    expect(
      classifyApiError(ApiErrorKind.network, null),
      ApiErrorCondition.network,
    );
    expect(
      classifyApiError(ApiErrorKind.stream, null),
      ApiErrorCondition.other,
    );

    expect(
      replyErrorText(
        zh,
        const ReplyError(kind: ApiErrorKind.http, message: 'raw', status: 429),
      ),
      '请求过于频繁，请稍后再试',
    );
    expect(
      replyErrorText(
        zh,
        const ReplyError(
          kind: ApiErrorKind.upload,
          message: 'raw',
          localMessage: LocalMessage(key: LocalMessageKeys.errorNoApiKey),
        ),
      ),
      '未设置 API Key，请先在设置中填写。',
    );
  });

  test('maps every API condition to its ARB key', () {
    expect(
      {
        for (final condition in ApiErrorCondition.values)
          condition: localMessageKeyFor(condition),
      },
      {
        ApiErrorCondition.unauthorized: LocalMessageKeys.apiErrorUnauthorized,
        ApiErrorCondition.insufficientBalance:
            LocalMessageKeys.apiErrorInsufficientBalance,
        ApiErrorCondition.tooLarge: LocalMessageKeys.apiErrorTooLarge,
        ApiErrorCondition.rateLimited: LocalMessageKeys.apiErrorRateLimited,
        ApiErrorCondition.serverBusy: LocalMessageKeys.apiErrorServerBusy,
        ApiErrorCondition.network: LocalMessageKeys.apiErrorNetwork,
        ApiErrorCondition.other: LocalMessageKeys.apiErrorOther,
      },
    );
  });

  test('translates local message keys', () {
    expect(
      localMessageText(
        zh,
        const LocalMessage(key: LocalMessageKeys.errorNoApiKey),
      ),
      '未设置 API Key，请先在设置中填写。',
    );
    expect(
      localMessageText(
        zh,
        const LocalMessage(
          key: LocalMessageKeys.errorSaveReplyFailed,
          params: {'error': 'disk full'},
        ),
      ),
      '保存回复失败：disk full',
    );
    expect(
      localMessageText(
        zh,
        const LocalMessage(key: LocalMessageKeys.apiErrorUnauthorized),
      ),
      'API Key 无效',
    );
    expect(
      localMessageText(
        en,
        const LocalMessage(key: LocalMessageKeys.apiErrorNetwork),
      ),
      'Network error. Check your connection.',
    );
  });
}
