import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'preferences_provider.dart';

/// ZH
/// 朗读音色（`speech.md` §9）；非法存储值回退默认女声。
///
/// EN
/// Read-aloud voice (`speech.md` §9); invalid stored values fall back to the default female voice.
enum TtsVoice { stella, tide }

/// ZH
/// 语音偏好：朗读音色与「是否请求过麦克风权限」。
///
/// `permission_handler` 不暴露「未请求」状态，用 [micRequested] 区分
/// 未请求与已拒绝（`speech.md` §5.1）。
///
/// EN
/// Speech preferences: read-aloud voice and whether microphone permission was requested.
///
/// `permission_handler` does not expose a "not requested" state, so [micRequested]
/// distinguishes not requested from denied (`speech.md` §5.1).
class SpeechStore {
  SpeechStore(this._preferences);

  static const ttsVoiceKey = 'tts.voice';
  static const micRequestedKey = 'speech.micRequested';

  final SharedPreferences _preferences;

  TtsVoice get ttsVoice => switch (_preferences.getString(ttsVoiceKey)) {
    'tide' => TtsVoice.tide,
    _ => TtsVoice.stella,
  };

  Future<void> setTtsVoice(TtsVoice voice) =>
      _preferences.setString(ttsVoiceKey, voice.name);

  bool get micRequested => _preferences.getBool(micRequestedKey) ?? false;

  Future<void> setMicRequested(bool value) =>
      _preferences.setBool(micRequestedKey, value);
}

final speechStoreProvider = Provider<SpeechStore>(
  (ref) => SpeechStore(ref.watch(sharedPreferencesProvider)),
);

final ttsVoiceProvider = NotifierProvider<TtsVoiceNotifier, TtsVoice>(
  TtsVoiceNotifier.new,
);

class TtsVoiceNotifier extends Notifier<TtsVoice> {
  @override
  TtsVoice build() => ref.read(speechStoreProvider).ttsVoice;

  Future<void> setVoice(TtsVoice voice) async {
    await ref.read(speechStoreProvider).setTtsVoice(voice);
    state = voice;
  }
}
