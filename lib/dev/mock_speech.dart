import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../features/chat/speech/recorder.dart';
import '../features/chat/speech/speech_api.dart';
import '../shared/prefs/speech_store.dart';
import '../shared/security/api_key_store.dart';

/// ZH
/// 语音调试替身：转写延迟后返回固定文本，朗读返回空流。
///
/// 开启：`flutter run --dart-define=SEEK_CHAT_MOCK_SPEECH=true`
/// 调整识别耗时：`--dart-define=SEEK_CHAT_MOCK_SPEECH_DELAY_MS=800`
///
/// 只用于观察浮层与自动发送的时序，不读录音文件、不发网络请求。
///
/// EN
/// Voice debug stand-in: transcription returns fixed text after a delay; synthesis is an empty stream.
///
/// Enable: `flutter run --dart-define=SEEK_CHAT_MOCK_SPEECH=true`
/// Adjust the recognition delay: `--dart-define=SEEK_CHAT_MOCK_SPEECH_DELAY_MS=800`
///
/// Only for watching overlay and auto-send timing; reads no recording file and makes no request.
class MockSpeechApi implements SpeechApi {
  MockSpeechApi({
    this.text = '这是一段语音转写示例，用来观察浮层是否在发送之前消失。',
    this.delay = const Duration(milliseconds: 800),
  });

  final String text;
  final Duration delay;

  @override
  Future<String> transcribe({
    required String path,
    required String apiKey,
    Future<void>? abortTrigger,
  }) async {
    var aborted = false;
    if (abortTrigger != null) {
      await Future.any<void>([
        Future<void>.delayed(delay),
        abortTrigger.then((_) {
          aborted = true;
        }),
      ]);
      if (aborted) throw const _Aborted();
    } else {
      await Future<void>.delayed(delay);
    }
    return text;
  }

  @override
  Stream<Uint8List> synthesize({
    required String text,
    required TtsVoice voice,
    required String apiKey,
    Future<void>? abortTrigger,
  }) => const Stream<Uint8List>.empty();

  @override
  void close() {}
}

final class _Aborted implements Exception {
  const _Aborted();
}

/// ZH
/// 语音调试替身用的假录音器：不碰麦克风，返回一个占位路径。
///
/// EN
/// Fake recorder for the voice stand-in: touches no microphone and returns a placeholder path.
class MockSpeechRecorder implements SpeechRecorder {
  @override
  Future<RecordingSession> start() async => const _MockRecordingSession();
}

class _MockRecordingSession implements RecordingSession {
  const _MockRecordingSession();

  @override
  Stream<double> get levels =>
      Stream<double>.periodic(const Duration(milliseconds: 120), (i) {
        return 0.25 + 0.5 * (0.5 + 0.5 * math.sin(i * 0.6));
      });

  @override
  Stream<void> get interruptions => const Stream<void>.empty();

  @override
  Future<String?> stop() async => '/tmp/mock-recording.wav';

  @override
  Future<void> cancel() async {}
}

/// ZH
/// 语音调试替身用的固定 Key：转写闸门要求设置里存在 API Key。
///
/// EN
/// Fixed key for the voice stand-in: the transcription gate requires an API key in settings.
class MockApiKeyStore extends ApiKeyStore {
  @override
  Future<String?> read() async => 'mock-key';

  @override
  Future<void> write(String apiKey) async {}

  @override
  Future<void> clear() async {}
}
