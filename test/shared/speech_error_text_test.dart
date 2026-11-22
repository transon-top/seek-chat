import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/error_text.dart';

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('maps every voice input failure to the current locale', () {
    expect(
      voiceInputErrorText(zh, VoiceInputFailure.permissionDenied),
      '无法使用麦克风，请在系统设置中允许访问',
    );
    expect(voiceInputErrorText(zh, VoiceInputFailure.noDevice), '未检测到麦克风');
    expect(
      voiceInputErrorText(en, VoiceInputFailure.failed),
      'Speech recognition failed. Please try again later.',
    );
    expect(voiceInputErrorText(zh, VoiceInputFailure.empty), '未识别到内容');
    expect(
      voiceInputErrorText(zh, VoiceInputFailure.limitReached),
      '已达到单次录音时长上限',
    );
    expect(voiceInputErrorText(zh, VoiceInputFailure.interrupted), '录音已中断');
    expect(
      voiceInputErrorText(zh, VoiceInputFailure.noApiKey),
      '未设置 API Key，请先在设置中填写。',
    );
  });

  test('maps TTS status codes, folding everything else into one failure', () {
    expect(ttsFailureFromStatus(400), TtsFailure.unavailable);
    expect(ttsFailureFromStatus(401), TtsFailure.unauthorized);
    expect(ttsFailureFromStatus(402), TtsFailure.insufficientBalance);
    expect(ttsFailureFromStatus(429), TtsFailure.rateLimited);
    expect(ttsFailureFromStatus(500), TtsFailure.failed);
    expect(ttsFailureFromStatus(503), TtsFailure.failed);
    expect(ttsFailureFromStatus(null), TtsFailure.failed);

    expect(ttsErrorText(zh, TtsFailure.unavailable), '这条回答暂时无法朗读');
    expect(ttsErrorText(zh, TtsFailure.unauthorized), 'API Key 无效');
    expect(ttsErrorText(zh, TtsFailure.insufficientBalance), '余额不足');
    expect(ttsErrorText(zh, TtsFailure.rateLimited), '请求过于频繁，请稍后再试');
    expect(
      ttsErrorText(en, TtsFailure.failed),
      'Read-aloud failed. Please try again later.',
    );
  });
}
