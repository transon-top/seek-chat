import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/api/errors.dart';
import '../../../shared/error_text.dart';
import '../../../shared/logging.dart';
import '../../../shared/prefs/speech_store.dart';
import '../../../shared/providers.dart';
import '../../../shared/security/api_key_store.dart';
import '../../../shared/speech/permissions.dart';
import 'player.dart';
import 'recorder.dart';
import 'speech_api.dart';

/// 全局音频状态机的可见阶段（`speech.md` §3、§4）。
enum SpeechPhase { idle, recording, transcribing, loading, playing }

/// 语音与朗读的共享状态；失败字段只用于提示，不改变按钮外观。
class SpeechState {
  const SpeechState({
    this.phase = SpeechPhase.idle,
    this.recordingSeconds = 0,
    this.level = 0,
    this.readingMessageId,
    this.voiceFailure,
    this.ttsFailure,
    this.noticeId = 0,
  });

  static const Object _keep = Object();

  final SpeechPhase phase;

  /// 录音整秒数，界面每 500 ms 刷新。
  final int recordingSeconds;

  /// 最近一次电平 0..1。
  final double level;

  /// 正在加载 / 播放的回复；其余时间 null。
  final String? readingMessageId;

  final VoiceInputFailure? voiceFailure;
  final TtsFailure? ttsFailure;

  /// 每次新提示递增；界面据此只展示一次 SnackBar。
  final int noticeId;

  bool get voiceBusy =>
      phase == SpeechPhase.recording || phase == SpeechPhase.transcribing;

  bool get reading =>
      phase == SpeechPhase.loading || phase == SpeechPhase.playing;

  SpeechState copyWith({
    SpeechPhase? phase,
    int? recordingSeconds,
    double? level,
    Object? readingMessageId = _keep,
    Object? voiceFailure = _keep,
    Object? ttsFailure = _keep,
    int? noticeId,
  }) => SpeechState(
    phase: phase ?? this.phase,
    recordingSeconds: recordingSeconds ?? this.recordingSeconds,
    level: level ?? this.level,
    readingMessageId: identical(readingMessageId, _keep)
        ? this.readingMessageId
        : readingMessageId as String?,
    voiceFailure: identical(voiceFailure, _keep)
        ? this.voiceFailure
        : voiceFailure as VoiceInputFailure?,
    ttsFailure: identical(ttsFailure, _keep)
        ? this.ttsFailure
        : ttsFailure as TtsFailure?,
    noticeId: noticeId ?? this.noticeId,
  );
}

/// 把转写文本替换进当前选区；无效选区回退到末尾，光标落在插入内容之后
/// （`speech.md` §3.4）。
TextEditingValue insertTranscript(TextEditingValue value, String transcript) {
  final text = transcript.trim();
  final selection = value.selection;
  final start = selection.isValid ? selection.start : value.text.length;
  final end = selection.isValid ? selection.end : value.text.length;
  final inserted = value.text.replaceRange(start, end, text);
  return TextEditingValue(
    text: inserted,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

final speechApiProvider = Provider<SpeechApi>((ref) {
  final api = DeepSeekSpeechApi();
  ref.onDispose(api.close);
  return api;
});

final speechRecorderProvider = Provider<SpeechRecorder>(
  (ref) => DeviceSpeechRecorder(),
);

final speechPlayerProvider = Provider<SpeechPlayer>(
  (ref) => SoLoudSpeechPlayer(),
);

/// 单次录音上限；测试注入短时长。到达后只触发一次自动转写。
final speechMaxRecordingProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 120),
);

final speechControllerProvider =
    NotifierProvider<SpeechController, SpeechState>(SpeechController.new);

/// 录音与朗读共用一个音频通道：任一时刻只有一个分支在活动（§4.3）。
class SpeechController extends Notifier<SpeechState> {
  late SpeechRecorder _recorder;
  late SpeechPlayer _player;
  late SpeechApi _api;
  late MicrophonePermissions _permissions;
  late SpeechStore _store;
  late ApiKeyStore _keys;
  late Duration _maxRecording;

  int _token = 0;
  RecordingSession? _recording;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<void>? _interruptionSub;
  Timer? _secondsTimer;
  Timer? _capTimer;
  DateTime? _recordStartedAt;
  void Function(String text)? _onTranscript;

  Completer<void>? _asrAbort;

  Completer<void>? _ttsAbort;
  PlaybackSession? _playback;
  StreamSubscription<Uint8List>? _ttsSub;
  StreamSubscription<void>? _playbackDoneSub;
  Completer<void>? _playbackDone;

  bool _disposed = false;

  @override
  SpeechState build() {
    _recorder = ref.read(speechRecorderProvider);
    _player = ref.read(speechPlayerProvider);
    _api = ref.read(speechApiProvider);
    _permissions = ref.read(microphonePermissionsProvider);
    _store = ref.read(speechStoreProvider);
    _keys = ref.read(apiKeyStoreProvider);
    _maxRecording = ref.read(speechMaxRecordingProvider);
    ref.onDispose(() {
      _disposed = true;
      _cancelRecordingResources();
      _asrAbort?.complete();
      _asrAbort = null;
      _ttsAbort?.complete();
      _ttsAbort = null;
      unawaited(_releasePlayback());
    });
    return const SpeechState();
  }

  /// 语音按钮的唯一入口：空闲开始、录音结束并转写、转写中取消。
  Future<void> toggleVoiceInput({
    required void Function(String text) onTranscript,
  }) async {
    if (_disposed) return;
    if (state.phase == SpeechPhase.recording) {
      _onTranscript = onTranscript;
      await _stopRecordingAndTranscribe();
      return;
    }
    if (state.phase == SpeechPhase.transcribing) {
      _cancelTranscription();
      return;
    }
    await _startRecording(onTranscript);
  }

  /// 朗读按钮的唯一入口：同一条再次点击停止，切换条先停后播。
  Future<void> toggleReadAloud({
    required String messageId,
    required String text,
  }) async {
    if (_disposed) return;
    if (state.voiceBusy) return;
    if (state.reading) {
      if (state.readingMessageId == messageId) {
        await stopReadAloud();
        return;
      }
      await stopReadAloud();
    }
    await _startReading(messageId: messageId, text: text);
  }

  /// 发送、停止生成、继续、重新生成与页面销毁时调用（§10）。
  Future<void> stopReadAloud() async {
    if (!state.reading) return;
    _token++;
    _ttsAbort?.complete();
    _ttsAbort = null;
    final done = _playbackDone;
    _playbackDone = null;
    await _releasePlayback();
    if (done != null && !done.isCompleted) done.complete();
    if (!_disposed) {
      state = state.copyWith(phase: SpeechPhase.idle, readingMessageId: null);
    }
  }

  /// 进入后台、切会话、离开页面：取消录音 / 转写并停止朗读，不提示。
  Future<void> handleLifecycle() async {
    if (_disposed) return;
    switch (state.phase) {
      case SpeechPhase.recording:
        await _discardRecording();
      case SpeechPhase.transcribing:
        _cancelTranscription();
      case SpeechPhase.loading:
      case SpeechPhase.playing:
        await stopReadAloud();
      case SpeechPhase.idle:
        break;
    }
  }

  Future<void> stopAll() => handleLifecycle();

  // ------------------------------------------------------------------ 录音

  Future<void> _startRecording(void Function(String text) onTranscript) async {
    final key = await _readKey();
    if (key == null) {
      _noticeVoice(VoiceInputFailure.noApiKey);
      return;
    }
    var granted = await _permissions.isGranted();
    if (!granted) granted = await _permissions.request();
    if (!granted) {
      _noticeVoice(VoiceInputFailure.permissionDenied);
      return;
    }
    // 权限被拒绝时保持原朗读；确认可录音后才停播放（§4.3）。
    if (state.reading) await stopReadAloud();
    if (_disposed) return;

    final RecordingSession session;
    try {
      session = await _recorder.start();
    } on NoInputDeviceException {
      _noticeVoice(VoiceInputFailure.noDevice);
      return;
    } on Object {
      _noticeVoice(VoiceInputFailure.failed);
      return;
    }
    if (_disposed) {
      unawaited(session.cancel());
      return;
    }

    _recording = session;
    _onTranscript = onTranscript;
    final token = ++_token;
    _recordStartedAt = DateTime.now();
    state = state.copyWith(
      phase: SpeechPhase.recording,
      recordingSeconds: 0,
      level: 0,
      readingMessageId: null,
      voiceFailure: null,
      ttsFailure: null,
    );

    _levelSub = session.levels.listen((level) {
      if (token != _token || state.phase != SpeechPhase.recording) return;
      state = state.copyWith(level: level);
    });
    _interruptionSub = session.interruptions.listen((_) {
      if (token != _token || state.phase != SpeechPhase.recording) return;
      unawaited(_discardRecording(notice: VoiceInputFailure.interrupted));
    });
    _secondsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (token != _token || state.phase != SpeechPhase.recording) return;
      final started = _recordStartedAt;
      if (started == null) return;
      final seconds = DateTime.now().difference(started).inSeconds;
      if (seconds != state.recordingSeconds) {
        state = state.copyWith(recordingSeconds: seconds);
      }
    });
    _capTimer = Timer(_maxRecording, () {
      if (token != _token || state.phase != SpeechPhase.recording) return;
      _noticeVoice(VoiceInputFailure.limitReached);
      unawaited(_stopRecordingAndTranscribe());
    });
  }

  Future<void> _stopRecordingAndTranscribe() async {
    final session = _recording;
    if (session == null) return;
    _recording = null;
    final token = ++_token;
    final callback = _onTranscript;
    _onTranscript = null;
    _cancelRecordingResources();
    state = state.copyWith(phase: SpeechPhase.transcribing, level: 0);

    String? path;
    try {
      path = await session.stop();
    } on Object {
      path = null;
    }
    // 停止录音期间用户取消 / 页面销毁：丢弃文件，不上传、不插入（§3.1）。
    if (_disposed || token != _token) {
      if (path != null && path.isNotEmpty) _deleteQuietly(path);
      return;
    }
    if (path == null || path.isEmpty) {
      state = state.copyWith(phase: SpeechPhase.idle);
      _noticeVoice(VoiceInputFailure.empty);
      return;
    }

    final key = await _readKey();
    if (_disposed || token != _token) {
      _deleteQuietly(path);
      return;
    }
    if (key == null) {
      _deleteQuietly(path);
      state = state.copyWith(phase: SpeechPhase.idle);
      _noticeVoice(VoiceInputFailure.noApiKey);
      return;
    }

    final abort = Completer<void>();
    _asrAbort = abort;
    try {
      final text = await _api.transcribe(
        path: path,
        apiKey: key,
        abortTrigger: abort.future,
      );
      if (abort.isCompleted || _disposed || token != _token) return;
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        state = state.copyWith(phase: SpeechPhase.idle);
        _noticeVoice(VoiceInputFailure.empty);
        return;
      }
      callback?.call(trimmed);
      state = state.copyWith(phase: SpeechPhase.idle);
    } on EmptyRecordingException {
      if (abort.isCompleted || _disposed || token != _token) return;
      state = state.copyWith(phase: SpeechPhase.idle);
      _noticeVoice(VoiceInputFailure.empty);
    } on Object catch (error) {
      if (abort.isCompleted || _disposed || token != _token) return;
      debugLog('speech transcription failed', error);
      state = state.copyWith(phase: SpeechPhase.idle);
      _noticeVoice(VoiceInputFailure.failed);
    } finally {
      if (identical(_asrAbort, abort)) _asrAbort = null;
    }
  }

  void _cancelTranscription() {
    _token++;
    final abort = _asrAbort;
    _asrAbort = null;
    abort?.complete();
    if (!_disposed && state.phase == SpeechPhase.transcribing) {
      state = state.copyWith(phase: SpeechPhase.idle);
    }
  }

  /// 中断、切页、后台：丢弃录音，不上传。
  Future<void> _discardRecording({VoiceInputFailure? notice}) async {
    final session = _recording;
    if (session == null) return;
    _recording = null;
    _token++;
    _onTranscript = null;
    _cancelRecordingResources();
    if (!_disposed) {
      state = state.copyWith(phase: SpeechPhase.idle, level: 0);
      if (notice != null) _noticeVoice(notice);
    }
    await session.cancel();
  }

  void _cancelRecordingResources() {
    _levelSub?.cancel();
    _levelSub = null;
    _interruptionSub?.cancel();
    _interruptionSub = null;
    _secondsTimer?.cancel();
    _secondsTimer = null;
    _capTimer?.cancel();
    _capTimer = null;
    _recordStartedAt = null;
  }

  // ------------------------------------------------------------------ 朗读

  Future<void> _startReading({
    required String messageId,
    required String text,
  }) async {
    final key = await _readKey();
    if (key == null) {
      _noticeTts(TtsFailure.noApiKey);
      return;
    }
    final voice = _store.ttsVoice;
    final token = ++_token;
    final abort = Completer<void>();
    _ttsAbort = abort;
    final done = Completer<void>();
    _playbackDone = done;
    state = state.copyWith(
      phase: SpeechPhase.loading,
      readingMessageId: messageId,
      voiceFailure: null,
      ttsFailure: null,
    );

    PlaybackSession? playback;
    var received = false;
    final streamDone = Completer<void>();
    try {
      playback = await _player.start();
      if (token != _token || _disposed) {
        await playback.stop();
        return;
      }
      _playback = playback;
      _playbackDoneSub = playback.completed.listen((_) {
        if (!done.isCompleted) done.complete();
      });

      final stream = _api.synthesize(
        text: text,
        voice: voice,
        apiKey: key,
        abortTrigger: abort.future,
      );
      _ttsSub = stream.listen(
        (chunk) {
          if (token != _token || chunk.isEmpty) return;
          if (!received) {
            received = true;
            state = state.copyWith(phase: SpeechPhase.playing);
          }
          try {
            playback!.add(chunk);
          } on Object catch (error, stack) {
            if (!streamDone.isCompleted) streamDone.completeError(error, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!streamDone.isCompleted) streamDone.completeError(error, stack);
        },
        onDone: () {
          if (!streamDone.isCompleted) streamDone.complete();
        },
        cancelOnError: true,
      );

      // 用户停止或播放器提前结束都会完成 done；两者都按调用方已收尾处理。
      await Future.any([streamDone.future, done.future]);
      if (token != _token || _disposed) return;
      if (!streamDone.isCompleted) {
        await _releasePlayback();
        return;
      }
      await streamDone.future;
      if (!received) throw const _EmptyTtsException();
      await playback.end();
      await done.future;
      if (token != _token || _disposed) return;
      await _releasePlayback();
      state = state.copyWith(phase: SpeechPhase.idle, readingMessageId: null);
    } on Object catch (error) {
      if (token != _token || _disposed || abort.isCompleted) return;
      await _releasePlayback();
      if (_disposed) return;
      state = state.copyWith(phase: SpeechPhase.idle, readingMessageId: null);
      _noticeTts(_ttsFailure(error));
    } finally {
      if (identical(_ttsAbort, abort)) _ttsAbort = null;
    }
  }

  TtsFailure _ttsFailure(Object error) => error is ApiException
      ? ttsFailureFromStatus(error.status)
      : TtsFailure.failed;

  Future<void> _releasePlayback() async {
    final playback = _playback;
    _playback = null;
    await _ttsSub?.cancel();
    _ttsSub = null;
    await _playbackDoneSub?.cancel();
    _playbackDoneSub = null;
    _playbackDone = null;
    if (playback != null) {
      try {
        await playback.stop();
      } on Object {
        // 已停止或引擎关闭时释放失败无需上抛。
      }
    }
  }

  // ------------------------------------------------------------------ 辅助

  void _noticeVoice(VoiceInputFailure failure) {
    if (_disposed) return;
    state = state.copyWith(
      voiceFailure: failure,
      ttsFailure: null,
      noticeId: state.noticeId + 1,
    );
  }

  void _noticeTts(TtsFailure failure) {
    if (_disposed) return;
    state = state.copyWith(
      ttsFailure: failure,
      voiceFailure: null,
      noticeId: state.noticeId + 1,
    );
  }

  Future<String?> _readKey() async {
    final key = (await _keys.read())?.trim();
    return key == null || key.isEmpty ? null : key;
  }

  void _deleteQuietly(String path) {
    unawaited(() async {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 临时文件可能已被平台清理。
      }
    }());
  }
}

final class _EmptyTtsException implements Exception {
  const _EmptyTtsException();
}
