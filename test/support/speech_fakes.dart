import 'dart:async';
import 'dart:typed_data';

import 'package:seek_chat/features/chat/speech/player.dart';
import 'package:seek_chat/features/chat/speech/recorder.dart';
import 'package:seek_chat/features/chat/speech/speech_api.dart';
import 'package:seek_chat/shared/prefs/speech_store.dart';
import 'package:seek_chat/shared/speech/permissions.dart';

class FakeMicrophonePermissions implements MicrophonePermissions {
  bool granted = true;
  bool requestResult = true;
  int requests = 0;
  bool openedSettings = false;

  /// ZH
  /// 非空时请求挂起，模拟系统授权弹窗。
  ///
  /// EN
  /// When non-null, requests hang, simulating the system permission dialog.
  Completer<bool>? requestGate;

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    requests++;
    final gate = requestGate;
    if (gate != null) return gate.future;
    return requestResult;
  }

  @override
  Future<MicrophoneStatus> status() async {
    if (granted) return MicrophoneStatus.granted;
    return requestResult
        ? MicrophoneStatus.notRequested
        : MicrophoneStatus.denied;
  }

  @override
  Future<void> openSettings() async => openedSettings = true;
}

class FakeRecordingSession implements RecordingSession {
  final levelsController = StreamController<double>.broadcast();
  final interruptionsController = StreamController<void>.broadcast();

  String? path = '/tmp/seek_chat_fake_recording.wav';
  bool stopped = false;
  bool cancelled = false;
  Completer<void>? stopGate;

  @override
  Stream<double> get levels => levelsController.stream;

  @override
  Stream<void> get interruptions => interruptionsController.stream;

  @override
  Future<String?> stop() async {
    stopped = true;
    final gate = stopGate;
    if (gate != null) await gate.future;
    return path;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  void interrupt() => interruptionsController.add(null);

  void level(double value) => levelsController.add(value);

  void close() {
    levelsController.close();
    interruptionsController.close();
  }
}

class FakeRecorder implements SpeechRecorder {
  FakeRecordingSession? session;
  Object? error;
  int starts = 0;

  /// ZH
  /// 非空时启动挂起，模拟设备启动耗时。
  ///
  /// EN
  /// When non-null, start hangs, simulating device startup latency.
  Completer<void>? startGate;

  @override
  Future<RecordingSession> start() async {
    starts++;
    final gate = startGate;
    if (gate != null) await gate.future;
    final failure = error;
    if (failure != null) throw failure;
    return session = FakeRecordingSession();
  }
}

class FakePlaybackSession implements PlaybackSession {
  final chunks = <Uint8List>[];
  final completedController = StreamController<void>.broadcast();
  bool ended = false;
  bool stopped = false;

  @override
  void add(Uint8List chunk) {
    if (stopped) return;
    chunks.add(chunk);
  }

  @override
  Future<void> end() async => ended = true;

  @override
  Stream<void> get completed => completedController.stream;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!completedController.isClosed) await completedController.close();
  }

  void finish() => completedController.add(null);
}

class FakePlayer implements SpeechPlayer {
  final sessions = <FakePlaybackSession>[];
  Object? error;

  @override
  Future<PlaybackSession> start() async {
    final failure = error;
    if (failure != null) throw failure;
    final session = FakePlaybackSession();
    sessions.add(session);
    return session;
  }
}

final class FakeAborted implements Exception {
  const FakeAborted();
}

class TtsCall {
  TtsCall(this.text, this.voice, this.apiKey);

  final String text;
  final TtsVoice voice;
  final String apiKey;
}

class FakeSpeechApi implements SpeechApi {
  int asrCount = 0;
  String? asrPath;
  Completer<String>? asrCompleter;
  Object? asrError;
  Completer<void>? asrAbort;

  final ttsCalls = <TtsCall>[];
  StreamController<Uint8List>? ttsController;
  Object? ttsError;

  @override
  Future<String> transcribe({
    required String path,
    required String apiKey,
    Future<void>? abortTrigger,
  }) {
    asrCount++;
    asrPath = path;
    final completer = asrCompleter = Completer<String>();
    asrAbort = abortTrigger == null ? null : Completer<void>();
    abortTrigger?.then((_) {
      final abort = asrAbort;
      if (abort != null && !abort.isCompleted) abort.complete();
      if (!completer.isCompleted) completer.completeError(const FakeAborted());
    });
    final failure = asrError;
    if (failure != null) completer.completeError(failure);
    return completer.future;
  }

  void completeAsr(String text) => asrCompleter!.complete(text);

  @override
  Stream<Uint8List> synthesize({
    required String text,
    required TtsVoice voice,
    required String apiKey,
    Future<void>? abortTrigger,
  }) {
    ttsCalls.add(TtsCall(text, voice, apiKey));
    final failure = ttsError;
    if (failure != null) return Stream.error(failure);
    final controller = StreamController<Uint8List>();
    ttsController = controller;
    abortTrigger?.then((_) {
      if (!controller.isClosed) controller.close();
    });
    return controller.stream;
  }

  @override
  void close() {}
}
