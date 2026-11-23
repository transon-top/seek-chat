import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:seek_chat/features/chat/speech/recorder.dart';
import 'package:seek_chat/features/chat/speech/speech_controller.dart';
import 'package:seek_chat/shared/api/errors.dart';
import 'package:seek_chat/shared/error_text.dart';
import 'package:seek_chat/shared/models/types.dart';
import 'package:seek_chat/shared/prefs/preferences_provider.dart';
import 'package:seek_chat/shared/providers.dart';
import 'package:seek_chat/shared/prefs/speech_store.dart';
import 'package:seek_chat/shared/speech/permissions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_api_key_store.dart';
import '../../../support/speech_fakes.dart';

void main() {
  late FakeRecorder recorder;
  late FakePlayer player;
  late FakeSpeechApi api;
  late FakeMicrophonePermissions permissions;
  late FakeApiKeyStore keys;
  late SharedPreferences prefs;

  setUp(() async {
    recorder = FakeRecorder();
    player = FakePlayer();
    api = FakeSpeechApi();
    permissions = FakeMicrophonePermissions();
    keys = FakeApiKeyStore('sk-test');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer({
    Duration maxRecording = const Duration(seconds: 120),
  }) => ProviderContainer.test(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      apiKeyStoreProvider.overrideWithValue(keys),
      speechRecorderProvider.overrideWithValue(recorder),
      speechPlayerProvider.overrideWithValue(player),
      speechApiProvider.overrideWithValue(api),
      microphonePermissionsProvider.overrideWithValue(permissions),
      speechMaxRecordingProvider.overrideWithValue(maxRecording),
    ],
  );

  Future<void> pump([int times = 8]) async {
    for (var index = 0; index < times; index++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  VoiceTranscriptHandler insertOnly(List<String> inserted) => (text) async {
    inserted.add(text);
    return VoiceAutoSendOutcome.sent;
  };

  test('runs idle → starting → recording → transcribing → idle', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);
    final inserted = <String>[];

    unawaitedRead(notifier.startFromPress(onTranscript: insertOnly(inserted)));
    expect(
      container.read(speechControllerProvider).phase,
      SpeechPhase.starting,
    );
    await pump();
    expect(
      container.read(speechControllerProvider).phase,
      SpeechPhase.recording,
    );

    notifier.finishFromRelease();
    await pump();
    expect(
      container.read(speechControllerProvider).phase,
      SpeechPhase.transcribing,
    );
    expect(api.asrCount, 1);
    expect(api.asrPath, recorder.session!.path);

    api.completeAsr('  hello  ');
    await pump();
    expect(inserted, ['hello']);
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);
  });

  test('repeated presses during startup open only one recording', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);
    recorder.startGate = Completer<void>();

    unawaitedRead(notifier.startFromPress(onTranscript: insertOnly([])));
    unawaitedRead(notifier.startFromPress(onTranscript: insertOnly([])));
    await pump();
    expect(recorder.starts, 1);

    recorder.startGate!.complete();
    await pump();
    expect(
      container.read(speechControllerProvider).phase,
      SpeechPhase.recording,
    );
  });

  test('releasing before startup completes cancels silently', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);
    recorder.startGate = Completer<void>();

    unawaitedRead(notifier.startFromPress(onTranscript: insertOnly([])));
    await pump();
    notifier.finishFromRelease();
    await pump();
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);

    recorder.startGate!.complete();
    await pump();
    expect(recorder.session!.cancelled, isTrue);
    expect(api.asrCount, 0);
    final state = container.read(speechControllerProvider);
    expect(state.phase, SpeechPhase.idle);
    expect(state.voiceFailure, isNull);
  });

  test(
    'a pointer cancel from the first permission prompt asks to retry',
    () async {
      permissions
        ..granted = false
        ..requestGate = Completer<bool>();
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(speechControllerProvider.notifier);

      unawaitedRead(notifier.startFromPress(onTranscript: insertOnly([])));
      await pump();
      expect(permissions.requests, 1);
      notifier.cancelFromGesture();
      permissions.requestGate!.complete(true);
      await pump();

      expect(recorder.starts, 0);
      final state = container.read(speechControllerProvider);
      expect(state.phase, SpeechPhase.idle);
      expect(state.voiceFailure, VoiceInputFailure.micGrantedRetry);
    },
  );

  test(
    'sliding up arms cancel, sliding back resumes, release discards',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(speechControllerProvider.notifier);

      await notifier.startFromPress(onTranscript: insertOnly([]));
      await pump();
      notifier.setCancelArmed(true);
      expect(
        container.read(speechControllerProvider).phase,
        SpeechPhase.cancelling,
      );
      notifier.setCancelArmed(false);
      expect(
        container.read(speechControllerProvider).phase,
        SpeechPhase.recording,
      );
      notifier.setCancelArmed(true);
      notifier.finishFromRelease();
      await pump();

      expect(recorder.session!.cancelled, isTrue);
      expect(api.asrCount, 0);
      final state = container.read(speechControllerProvider);
      expect(state.phase, SpeechPhase.idle);
      expect(state.voiceFailure, isNull);
    },
  );

  test('an armed slide during startup opens in the cancel state', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);
    recorder.startGate = Completer<void>();

    unawaitedRead(notifier.startFromPress(onTranscript: insertOnly([])));
    await pump();
    notifier.setCancelArmed(true);
    expect(
      container.read(speechControllerProvider).phase,
      SpeechPhase.starting,
    );

    recorder.startGate!.complete();
    await pump();
    expect(
      container.read(speechControllerProvider).phase,
      SpeechPhase.cancelling,
    );

    notifier.finishFromRelease();
    await pump();
    expect(recorder.session!.cancelled, isTrue);
    expect(api.asrCount, 0);
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);
  });

  test('the cap discards instead of transcribing while cancelling', () async {
    final container = makeContainer(
      maxRecording: const Duration(milliseconds: 80),
    );
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    await notifier.startFromPress(onTranscript: insertOnly([]));
    await pump();
    notifier.setCancelArmed(true);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await pump();

    expect(recorder.session!.cancelled, isTrue);
    expect(api.asrCount, 0);
    final state = container.read(speechControllerProvider);
    expect(state.phase, SpeechPhase.idle);
    expect(state.voiceFailure, isNull);
  });

  test('the auto-send gate reports the first blocking reason', () {
    VoiceAutoSendOutcome? gate({
      String? apiKey = 'sk-test',
      bool generating = false,
      bool uploadsDone = true,
      bool typedDuring = false,
    }) => voiceAutoSendBlocker(
      apiKey: apiKey,
      generating: generating,
      uploadsDone: uploadsDone,
      typedDuring: typedDuring,
    );

    expect(gate(), isNull);
    expect(gate(apiKey: null), VoiceAutoSendOutcome.noApiKey);
    expect(gate(apiKey: '  '), VoiceAutoSendOutcome.noApiKey);
    expect(gate(generating: true), VoiceAutoSendOutcome.generating);
    expect(gate(uploadsDone: false), VoiceAutoSendOutcome.uploading);
    expect(gate(typedDuring: true), VoiceAutoSendOutcome.notSent);
    expect(
      gate(apiKey: null, generating: true, uploadsDone: false),
      VoiceAutoSendOutcome.noApiKey,
    );
  });

  test('auto-stops once at the cap and a late release is a no-op', () async {
    final container = makeContainer(
      maxRecording: const Duration(milliseconds: 80),
    );
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);
    final inserted = <String>[];

    await notifier.startFromPress(onTranscript: insertOnly(inserted));
    await pump();
    expect(recorder.session!.stopped, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    await pump();
    final state = container.read(speechControllerProvider);
    expect(state.voiceFailure, VoiceInputFailure.limitReached);
    expect(recorder.session!.stopped, isTrue);
    expect(state.phase, SpeechPhase.transcribing);
    expect(api.asrCount, 1);

    notifier.finishFromRelease();
    await pump();
    expect(api.asrCount, 1);

    api.completeAsr('done');
    await pump();
    expect(inserted, ['done']);
  });

  test('auto-send gates map to their own notices', () async {
    final expected = {
      VoiceAutoSendOutcome.noApiKey: VoiceInputFailure.noApiKey,
      VoiceAutoSendOutcome.generating: VoiceInputFailure.insertedGenerating,
      VoiceAutoSendOutcome.uploading: VoiceInputFailure.insertedUploading,
      VoiceAutoSendOutcome.notSent: VoiceInputFailure.insertedNotSent,
      VoiceAutoSendOutcome.failed: VoiceInputFailure.sendFailedInserted,
    };
    for (final entry in expected.entries) {
      final container = makeContainer();
      final notifier = container.read(speechControllerProvider.notifier);

      await notifier.startFromPress(onTranscript: (_) async => entry.key);
      await pump();
      notifier.finishFromRelease();
      await pump();
      api.completeAsr('hello');
      await pump();

      final state = container.read(speechControllerProvider);
      expect(state.phase, SpeechPhase.idle, reason: '${entry.key}');
      expect(state.voiceFailure, entry.value, reason: '${entry.key}');
      container.dispose();
    }
  });

  test('a sent transcript never shows a notice', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);
    final inserted = <String>[];

    await notifier.startFromPress(onTranscript: insertOnly(inserted));
    await pump();
    notifier.finishFromRelease();
    await pump();
    api.completeAsr('hi');
    await pump();

    expect(inserted, ['hi']);
    expect(container.read(speechControllerProvider).voiceFailure, isNull);
  });

  test('insertTranscript replaces the selection and moves the caret', () {
    const value = TextEditingValue(
      text: 'hello world',
      selection: TextSelection(baseOffset: 6, extentOffset: 11),
    );

    final result = insertTranscript(value, 'there');
    expect(result.text, 'hello there');
    expect(result.selection, const TextSelection.collapsed(offset: 11));

    const invalid = TextEditingValue(text: 'hello');
    final appended = insertTranscript(invalid, ' world');
    expect(appended.text, 'helloworld');
    expect(appended.selection, const TextSelection.collapsed(offset: 10));
  });

  test('permission denial blocks recording', () async {
    permissions
      ..granted = false
      ..requestResult = false;
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    await notifier.startFromPress(onTranscript: insertOnly([]));
    await pump();

    expect(permissions.requests, 1);
    expect(recorder.starts, 0);
    expect(
      container.read(speechControllerProvider).voiceFailure,
      VoiceInputFailure.permissionDenied,
    );
  });

  test('a missing key blocks voice input and reading', () async {
    keys.value = null;
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    await notifier.startFromPress(onTranscript: insertOnly([]));
    await pump();
    expect(recorder.starts, 0);
    expect(
      container.read(speechControllerProvider).voiceFailure,
      VoiceInputFailure.noApiKey,
    );

    await notifier.toggleReadAloud(messageId: 'm1', text: 'hello');
    await pump();
    expect(api.ttsCalls, isEmpty);
    expect(
      container.read(speechControllerProvider).ttsFailure,
      TtsFailure.noApiKey,
    );
  });

  test('permission denial keeps the current read-aloud playing', () async {
    permissions
      ..granted = false
      ..requestResult = false;
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    unawaitedRead(notifier.toggleReadAloud(messageId: 'm1', text: 'hello'));
    await pump();
    api.ttsController!.add(Uint8List.fromList([1]));
    await pump();
    expect(container.read(speechControllerProvider).phase, SpeechPhase.playing);

    await notifier.startFromPress(onTranscript: insertOnly([]));
    await pump();

    expect(recorder.starts, 0);
    expect(player.sessions.single.stopped, isFalse);
    expect(container.read(speechControllerProvider).phase, SpeechPhase.playing);
    expect(
      container.read(speechControllerProvider).voiceFailure,
      VoiceInputFailure.permissionDenied,
    );
  });

  test('a missing input device maps to its own failure', () async {
    recorder.error = const NoInputDeviceException();
    final container = makeContainer();
    addTearDown(container.dispose);

    await container
        .read(speechControllerProvider.notifier)
        .startFromPress(onTranscript: insertOnly([]));
    await pump();

    expect(
      container.read(speechControllerProvider).voiceFailure,
      VoiceInputFailure.noDevice,
    );
  });

  test(
    'a system interruption cancels the recording without uploading',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(speechControllerProvider.notifier);

      await notifier.startFromPress(onTranscript: insertOnly([]));
      await pump();
      recorder.session!.interrupt();
      await pump();

      expect(recorder.session!.cancelled, isTrue);
      expect(api.asrCount, 0);
      final state = container.read(speechControllerProvider);
      expect(state.phase, SpeechPhase.idle);
      expect(state.voiceFailure, VoiceInputFailure.interrupted);
    },
  );

  test('back during recording cancels it and stays on the page', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    await notifier.startFromPress(onTranscript: insertOnly([]));
    await pump();
    expect(notifier.cancelFromBack(), isTrue);
    await pump();

    expect(recorder.session!.cancelled, isTrue);
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);
    expect(container.read(speechControllerProvider).voiceFailure, isNull);

    await notifier.startFromPress(onTranscript: insertOnly([]));
    await pump();
    notifier.finishFromRelease();
    await pump();
    expect(
      container.read(speechControllerProvider).phase,
      SpeechPhase.transcribing,
    );
    expect(notifier.cancelFromBack(), isFalse);
  });

  test('switching conversation drops an active recording silently', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    await notifier.startFromPress(onTranscript: insertOnly([]));
    await pump();
    await notifier.stopAll();
    await pump();

    expect(recorder.session!.cancelled, isTrue);
    final state = container.read(speechControllerProvider);
    expect(state.phase, SpeechPhase.idle);
    expect(state.voiceFailure, isNull);
  });

  test('the semantics cancel action drops the recording silently', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    await notifier.startFromPress(onTranscript: insertOnly([]));
    await pump();
    notifier.cancelFromSemantics();
    await pump();

    expect(recorder.session!.cancelled, isTrue);
    expect(api.asrCount, 0);
    final state = container.read(speechControllerProvider);
    expect(state.phase, SpeechPhase.idle);
    expect(state.voiceFailure, isNull);
  });

  test('reads aloud from the first chunk to playback completion', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    unawaitedRead(notifier.toggleReadAloud(messageId: 'm1', text: 'hello'));
    await pump();
    expect(container.read(speechControllerProvider).phase, SpeechPhase.loading);
    expect(container.read(speechControllerProvider).readingMessageId, 'm1');

    api.ttsController!.add(Uint8List.fromList([1, 2]));
    await pump();
    expect(container.read(speechControllerProvider).phase, SpeechPhase.playing);
    expect(player.sessions.single.chunks, [
      Uint8List.fromList([1, 2]),
    ]);

    await api.ttsController!.close();
    await pump();
    expect(player.sessions.single.ended, isTrue);

    player.sessions.single.finish();
    await pump();
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);
    expect(container.read(speechControllerProvider).readingMessageId, isNull);
    expect(player.sessions.single.stopped, isTrue);
    expect(api.ttsCalls.single.voice, TtsVoice.stella);
  });

  test('tapping the same message stops reading', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    unawaitedRead(notifier.toggleReadAloud(messageId: 'm1', text: 'hello'));
    await pump();
    api.ttsController!.add(Uint8List.fromList([1]));
    await pump();

    unawaitedRead(notifier.toggleReadAloud(messageId: 'm1', text: 'hello'));
    await pump();
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);
    expect(player.sessions.single.stopped, isTrue);
  });

  test('reading another message stops the previous one first', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    unawaitedRead(notifier.toggleReadAloud(messageId: 'm1', text: 'one'));
    await pump();
    api.ttsController!.add(Uint8List.fromList([1]));
    await pump();

    unawaitedRead(notifier.toggleReadAloud(messageId: 'm2', text: 'two'));
    await pump();

    expect(player.sessions.length, 2);
    expect(player.sessions.first.stopped, isTrue);
    expect(container.read(speechControllerProvider).readingMessageId, 'm2');
  });

  test('a 400 maps to unavailable and an empty stream fails', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    api.ttsError = ApiException(ApiErrorKind.http, 'bad', status: 400);
    await notifier.toggleReadAloud(messageId: 'm1', text: 'hello');
    await pump();
    expect(
      container.read(speechControllerProvider).ttsFailure,
      TtsFailure.unavailable,
    );
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);

    api.ttsError = null;
    unawaitedRead(notifier.toggleReadAloud(messageId: 'm2', text: 'hello'));
    await pump();
    await api.ttsController!.close();
    await pump();
    expect(
      container.read(speechControllerProvider).ttsFailure,
      TtsFailure.failed,
    );
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);
  });

  test('starting a recording stops read-aloud first', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);

    unawaitedRead(notifier.toggleReadAloud(messageId: 'm1', text: 'hello'));
    await pump();
    api.ttsController!.add(Uint8List.fromList([1]));
    await pump();
    expect(player.sessions.single.stopped, isFalse);

    unawaitedRead(notifier.startFromPress(onTranscript: insertOnly([])));
    await pump(30);
    expect(player.sessions.single.stopped, isTrue);
    expect(
      container.read(speechControllerProvider).phase,
      SpeechPhase.recording,
    );
  });

  test(
    'leaving the foreground cancels recording and reading silently',
    () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final notifier = container.read(speechControllerProvider.notifier);

      await notifier.startFromPress(onTranscript: insertOnly([]));
      await pump();
      await notifier.handleLifecycle();
      await pump();
      expect(recorder.session!.cancelled, isTrue);
      expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);
      expect(container.read(speechControllerProvider).voiceFailure, isNull);

      unawaitedRead(notifier.toggleReadAloud(messageId: 'm1', text: 'hello'));
      await pump();
      api.ttsController!.add(Uint8List.fromList([1]));
      await pump();
      await notifier.handleLifecycle();
      await pump();
      expect(player.sessions.single.stopped, isTrue);
      expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);
    },
  );

  test('backgrounding during startup prevents the recording', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final notifier = container.read(speechControllerProvider.notifier);
    recorder.startGate = Completer<void>();

    unawaitedRead(notifier.startFromPress(onTranscript: insertOnly([])));
    await pump();
    await notifier.handleLifecycle();
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);

    recorder.startGate!.complete();
    await pump();
    expect(recorder.session!.cancelled, isTrue);
    expect(api.asrCount, 0);
    expect(container.read(speechControllerProvider).phase, SpeechPhase.idle);
  });
}

void unawaitedRead(Future<void> future) {
  future.catchError((_) {});
}
