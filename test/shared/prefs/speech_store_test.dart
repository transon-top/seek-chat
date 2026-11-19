import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/shared/prefs/preferences_provider.dart';
import 'package:open_chat/shared/prefs/speech_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  ProviderContainer containerWith(SharedPreferences prefs) =>
      ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );

  test('defaults to the stella voice and an unrequested microphone', () async {
    final container = containerWith(await prefsWith({}));
    expect(container.read(ttsVoiceProvider), TtsVoice.stella);
    expect(container.read(speechStoreProvider).micRequested, isFalse);
  });

  test('persists the voice and the microphone request flag', () async {
    final prefs = await prefsWith({});
    final container = containerWith(prefs);
    await container.read(ttsVoiceProvider.notifier).setVoice(TtsVoice.tide);
    await container.read(speechStoreProvider).setMicRequested(true);

    expect(prefs.getString(SpeechStore.ttsVoiceKey), 'tide');
    expect(prefs.getBool(SpeechStore.micRequestedKey), isTrue);

    final reloaded = containerWith(prefs);
    expect(reloaded.read(ttsVoiceProvider), TtsVoice.tide);
    expect(reloaded.read(speechStoreProvider).micRequested, isTrue);
  });

  test('falls back to stella for unknown stored voices', () async {
    final prefs = await prefsWith({SpeechStore.ttsVoiceKey: 'robot'});
    expect(containerWith(prefs).read(ttsVoiceProvider), TtsVoice.stella);
  });
}
