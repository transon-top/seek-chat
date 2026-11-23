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

/// ZH
/// 全局音频状态机的可见阶段（`speech.md` §3、§4）。
///
/// EN
/// Visible phases of the global audio state machine (`speech.md` §3, §4).
enum SpeechPhase {
  idle,
  starting,
  recording,
  cancelling,
  transcribing,
  loading,
  playing,
}

extension SpeechPhaseFlags on SpeechPhase {
  /// ZH
  /// 浮层覆盖输入卡的全部阶段；发送、附件与开关都不可用。
  ///
  /// EN
  /// Phases where the overlay covers the composer; send, attachments and toggles are unavailable.
  bool get voiceBusy =>
      this == SpeechPhase.starting ||
      this == SpeechPhase.recording ||
      this == SpeechPhase.cancelling ||
      this == SpeechPhase.transcribing;

  /// ZH
  /// 系统返回第一次只取消录音、不离开页面。
  ///
  /// EN
  /// The first system back press only cancels the recording and stays on the page.
  bool get voiceCancelable =>
      this == SpeechPhase.starting ||
      this == SpeechPhase.recording ||
      this == SpeechPhase.cancelling;

  bool get reading =>
      this == SpeechPhase.loading || this == SpeechPhase.playing;
}

/// ZH
/// 转写插入后的自动发送结果；控制器据此只插入并提示原因（`speech.md` §3.4）。
///
/// EN
/// Auto-send outcome after insert; the controller inserts only and reports why (`speech.md` §3.4).
enum VoiceAutoSendOutcome {
  sent,
  noApiKey,
  generating,
  uploading,
  notSent,
  failed,
}

typedef VoiceTranscriptHandler = Future<VoiceAutoSendOutcome> Function(
  String text,
);

/// ZH
/// 自动发送闸门；返回非 null 表示只插入并按该原因提示（`speech.md` §3.4）。
///
/// EN
/// Auto-send gate; a non-null result means insert only and show that reason (`speech.md` §3.4).
VoiceAutoSendOutcome? voiceAutoSendBlocker({
  required String? apiKey,
  required bool generating,
  required bool uploadsDone,
  required bool typedDuring,
}) {
  if (apiKey == null || apiKey.trim().isEmpty) {
    return VoiceAutoSendOutcome.noApiKey;
  }
  if (generating) return VoiceAutoSendOutcome.generating;
  if (!uploadsDone) return VoiceAutoSendOutcome.uploading;
  if (typedDuring) return VoiceAutoSendOutcome.notSent;
  return null;
}

/// ZH
/// 语音与朗读的共享状态；失败字段只用于提示，不改变按钮外观。
///
/// EN
/// Shared voice input and read-aloud state; failure fields drive notices only, not button appearance.
class SpeechState {
  const SpeechState({
    this.phase = SpeechPhase.idle,
    this.level = 0,
    this.readingMessageId,
    this.voiceFailure,
    this.ttsFailure,
    this.noticeId = 0,
  });

  static const Object _keep = Object();

  final SpeechPhase phase;

  /// ZH
  /// 最近一次电平 0..1。
  ///
  /// EN
  /// Latest level 0..1.
  final double level;

  /// ZH
  /// 正在加载 / 播放的回复；其余时间 null。
  ///
  /// EN
  /// Reply being loaded or played; null at all other times.
  final String? readingMessageId;

  final VoiceInputFailure? voiceFailure;
  final TtsFailure? ttsFailure;

  /// ZH
  /// 每次新提示递增；界面据此只展示一次 Toast。
  ///
  /// EN
  /// Incremented for each new notice; the UI uses it to show a Toast only once.
  final int noticeId;

  bool get voiceBusy => phase.voiceBusy;

  bool get reading => phase.reading;

  SpeechState copyWith({
    SpeechPhase? phase,
    double? level,
    Object? readingMessageId = _keep,
    Object? voiceFailure = _keep,
    Object? ttsFailure = _keep,
    int? noticeId,
  }) => SpeechState(
    phase: phase ?? this.phase,
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

/// ZH
/// 把转写文本替换进当前选区；无效选区回退到末尾，光标落在插入内容之后
/// （`speech.md` §3.4）。
///
/// EN
/// Replace the selection with the transcript; invalid selection falls back to
/// the end, cursor after insert (`speech.md` §3.4).
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

/// ZH
/// 单次录音上限；测试注入短时长。到达后只触发一次自动转写。
///
/// EN
/// Per-recording limit; tests inject a shorter one. Reaching it triggers auto-transcribe once.
final speechMaxRecordingProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 120),
);

final speechControllerProvider =
    NotifierProvider<SpeechController, SpeechState>(SpeechController.new);

/// ZH
/// 录音与朗读共用一个音频通道：任一时刻只有一个分支在活动（§4.3）。
///
/// 语音输入是按住说话：`startFromPress` 只负责启动，松手与取消由按钮的
/// `Listener` 显式调用 `finishFromRelease` / `cancelFromGesture`，不再复用
/// 点击切换入口（`speech.md` §3.2）。
///
/// EN
/// Recording and read-aloud share one audio channel: only one branch is active at a time (§4.3).
///
/// Voice Input is hold-to-talk: `startFromPress` only starts it; the button's
/// `Listener` explicitly calls `finishFromRelease` / `cancelFromGesture`. The
/// tap-toggle entry point is no longer reused (`speech.md` §3.2).
class SpeechController extends Notifier<SpeechState> {
  late SpeechRecorder _recorder;
  late SpeechPlayer _player;
  late SpeechApi _api;
  late MicrophonePermissions _permissions;
  late SpeechStore _store;
  late ApiKeyStore _keys;
  late Duration _maxRecording;

  /// ZH
  /// 启动单飞：从按下到 `recorder.start()` 返回之间只允许一次启动。
  ///
  /// EN
  /// Start single-flight: only one start may run from press until `recorder.start()` returns.
  bool _starting = false;

  /// ZH
  /// 麦克风权限请求进行中；期间的手势结束属于首次授权，不开录。
  ///
  /// EN
  /// Permission request in flight; a gesture end then is first-time grant, so recording does not start.
  bool _granting = false;
  bool _cancelWhileGranting = false;

  /// ZH
  /// 启动完成前松手 / 收到 pointer cancel / 后台：启动返回后丢弃，不转写。
  ///
  /// EN
  /// Release / pointer cancel / background before start returns: discard it, no transcription.
  bool _releasePending = false;
  bool _cancelPending = false;

  /// ZH
  /// 启动期间已滑过取消阈值；录音真正开始时直接进入取消态。
  ///
  /// EN
  /// Cancel threshold crossed during start; once recording begins, enter the cancel state directly.
  bool _armedPending = false;

  /// ZH
  /// 启动前正在朗读时记下相位；若朗读未被停止就回退，恢复原相位（§4.3）。
  ///
  /// EN
  /// Saved read-aloud phase before start; restore it when the read-aloud was not stopped (§4.3).
  SpeechPhase? _resumeReadingPhase;

  int _token = 0;
  RecordingSession? _recording;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<void>? _interruptionSub;
  Timer? _capTimer;
  VoiceTranscriptHandler? _onTranscript;

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

  // ZH
  // ------------------------------------------------------------------ 语音
  //
  // EN
  // ------------------------------------------------------------------ Voice Input.

  /// ZH
  /// 按下麦克风：同步进入 `starting` 显示浮层骨架，随后单飞读 Key、查权限、
  /// 启动录音（`speech.md` §3.1、§3.2）。
  ///
  /// EN
  /// Mic press: enter `starting` at once (overlay skeleton), then single-flight
  /// read the API key, check permission and start recording
  /// (`speech.md` §3.1, §3.2).
  Future<void> startFromPress({
    required VoiceTranscriptHandler onTranscript,
  }) async {
    if (_disposed || _starting || state.voiceBusy) return;
    _starting = true;
    _releasePending = false;
    _cancelPending = false;
    _cancelWhileGranting = false;
    _armedPending = false;
    _onTranscript = onTranscript;
    final wasReading = state.reading;
    _resumeReadingPhase = wasReading ? state.phase : null;
    state = state.copyWith(
      phase: SpeechPhase.starting,
      level: 0,
      voiceFailure: null,
      ttsFailure: null,
    );
    try {
      final key = await _readKey();
      if (_disposed) return;
      if (key == null) {
        _abortStart(VoiceInputFailure.noApiKey);
        return;
      }

      var granted = await _permissions.isGranted();
      if (_disposed) return;
      if (!granted) {
        _granting = true;
        try {
          granted = await _permissions.request();
        } finally {
          _granting = false;
        }
        if (_disposed) return;
        if (!granted) {
          _abortStart(VoiceInputFailure.permissionDenied);
          return;
        }
        if (_cancelWhileGranting) {
          _abortStart(VoiceInputFailure.micGrantedRetry);
          return;
        }
      }
      if (_cancelPending || _releasePending) {
        _abortStart(null);
        return;
      }
      // ZH
      // 确认可录音后才停播放；权限被拒绝时保持原朗读（§4.3）。
      //
      // EN
      // Stop playback only after recording is confirmed; keep read-aloud if permission is denied (§4.3).
      if (wasReading) {
        _resumeReadingPhase = null;
        await stopReadAloud();
      }
      if (_disposed) return;
      if (_cancelPending || _releasePending) {
        _abortStart(null);
        return;
      }

      final RecordingSession session;
      try {
        session = await _recorder.start();
      } on NoInputDeviceException {
        _abortStart(VoiceInputFailure.noDevice);
        return;
      } on Object {
        _abortStart(VoiceInputFailure.failed);
        return;
      }
      if (_disposed || _cancelPending || _releasePending) {
        if (!_disposed) _resetToIdle();
        await session.cancel();
        return;
      }
      _beginRecording(session);
    } on Object catch (error) {
      // ZH
      // 权限通道或录音引擎抛出未分类错误时也要收起浮层、释放资源。
      //
      // EN
      // Unclassified permission or recorder errors must still dismiss the overlay and release resources.
      if (!_disposed) {
        debugLog('voice start failed', error);
        _abortStart(VoiceInputFailure.failed);
      }
    } finally {
      _starting = false;
    }
  }

  /// ZH
  /// 松手：录音停止并转写；取消态丢弃；启动中或识别中 no-op。
  ///
  /// EN
  /// Release: stop and transcribe; discard in cancel state; no-op while starting or recognizing.
  void finishFromRelease() {
    if (_disposed) return;
    if (_starting) {
      _endActiveStart();
      return;
    }
    switch (state.phase) {
      case SpeechPhase.recording:
        unawaited(_stopRecordingAndTranscribe());
      case SpeechPhase.cancelling:
        unawaited(_discardRecording());
      case SpeechPhase.idle:
      case SpeechPhase.starting:
      case SpeechPhase.transcribing:
      case SpeechPhase.loading:
      case SpeechPhase.playing:
        break;
    }
  }

  /// ZH
  /// 首个 pointer 被系统取消（如来电、权限弹窗）：录音态丢弃，启动中延后取消。
  ///
  /// EN
  /// First system pointer cancel (call, permission dialog): discard when recording, defer when starting.
  void cancelFromGesture() {
    if (_disposed) return;
    if (_starting) {
      _endActiveStart();
      return;
    }
    if (state.phase == SpeechPhase.recording ||
        state.phase == SpeechPhase.cancelling) {
      unawaited(_discardRecording());
    }
  }

  /// ZH
  /// 上滑阈值：录音 ↔ 取消态；启动中先记住，开录后直接进入取消态。
  ///
  /// EN
  /// Slide threshold: recording ↔ cancel; remember while starting, enter cancel when recording begins.
  void setCancelArmed(bool armed) {
    if (_disposed) return;
    switch (state.phase) {
      case SpeechPhase.starting:
        _armedPending = armed;
      case SpeechPhase.recording:
        if (armed) state = state.copyWith(phase: SpeechPhase.cancelling);
      case SpeechPhase.cancelling:
        if (!armed) state = state.copyWith(phase: SpeechPhase.recording);
      case SpeechPhase.idle:
      case SpeechPhase.transcribing:
      case SpeechPhase.loading:
      case SpeechPhase.playing:
        break;
    }
  }

  /// ZH
  /// 读屏「取消录音」动作：丢弃录音，不提示（播报由界面负责）。
  ///
  /// EN
  /// Screen reader "cancel recording" action: discard the recording, no notice (the UI announces it).
  void cancelFromSemantics() {
    if (_disposed) return;
    if (state.phase == SpeechPhase.recording ||
        state.phase == SpeechPhase.cancelling) {
      unawaited(_discardRecording());
      return;
    }
    if (_starting) cancelFromGesture();
  }

  /// ZH
  /// 录音中系统返回：只取消录音并留在页面，返回 true 表示已消费本次返回。
  ///
  /// EN
  /// System back while recording: cancel only and stay on the page; true means this back was consumed.
  bool cancelFromBack() {
    if (_disposed) return false;
    if (_starting) {
      _cancelPending = true;
      _resetToIdle();
      return true;
    }
    if (state.phase == SpeechPhase.recording ||
        state.phase == SpeechPhase.cancelling) {
      unawaited(_discardRecording());
      return true;
    }
    return false;
  }

  /// ZH
  /// 语音按钮的唯一朗读入口：同一条再次点击停止，切换条先停后播。
  ///
  /// EN
  /// The voice button's only read-aloud entry: tapping the same reply stops it; switching stops first.
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

  /// ZH
  /// 发送、停止生成、继续、重新生成与页面销毁时调用（§10）。
  ///
  /// 按下麦克风时相位已切到 `starting`，所以不能只看 `state.reading`；
  /// 有播放或未完成的 TTS 请求就停止，但不覆盖当前语音输入相位。
  ///
  /// EN
  /// Called on send, stop generating, continue, regenerate and page dispose (§10).
  ///
  /// Mic press already switches the phase to `starting`, so `state.reading` alone
  /// is not enough. Stop if playback or an unfinished TTS request exists, without
  /// overwriting the current Voice Input phase.
  Future<void> stopReadAloud() async {
    final readingPhase = state.reading;
    if (!readingPhase && _playback == null && _ttsAbort == null) return;
    _token++;
    _ttsAbort?.complete();
    _ttsAbort = null;
    final done = _playbackDone;
    _playbackDone = null;
    await _releasePlayback();
    if (done != null && !done.isCompleted) done.complete();
    if (!_disposed) {
      state = state.copyWith(
        phase: readingPhase ? SpeechPhase.idle : state.phase,
        readingMessageId: null,
      );
    }
  }

  /// ZH
  /// 进入后台、切会话、离开页面：取消录音 / 转写并停止朗读，不提示。
  ///
  /// EN
  /// Background, Session switch, page exit: cancel recording / transcription and stop read-aloud silently.
  Future<void> handleLifecycle() async {
    if (_disposed) return;
    switch (state.phase) {
      case SpeechPhase.starting:
        _cancelPending = true;
        _onTranscript = null;
        _resumeReadingPhase = null;
        state = state.copyWith(phase: SpeechPhase.idle, level: 0);
        await stopReadAloud();
      case SpeechPhase.recording:
      case SpeechPhase.cancelling:
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

  void _beginRecording(RecordingSession session) {
    _recording = session;
    _resumeReadingPhase = null;
    final token = ++_token;
    state = state.copyWith(
      phase: _armedPending ? SpeechPhase.cancelling : SpeechPhase.recording,
      level: 0,
    );
    _armedPending = false;
    _levelSub = session.levels.listen((level) {
      if (token != _token || !_recordingPhase) return;
      state = state.copyWith(level: level);
    });
    _interruptionSub = session.interruptions.listen((_) {
      if (token != _token || !_recordingPhase) return;
      unawaited(_discardRecording(notice: VoiceInputFailure.interrupted));
    });
    _capTimer = Timer(_maxRecording, () {
      if (token != _token || !_recordingPhase) return;
      // ZH
      // 已在取消态：上限只结束并丢弃，不违背松开取消的意图。
      //
      // EN
      // Already cancelling: the cap only ends and discards, honoring the release-to-cancel intent.
      if (state.phase == SpeechPhase.cancelling) {
        unawaited(_discardRecording());
        return;
      }
      _noticeVoice(VoiceInputFailure.limitReached);
      unawaited(_stopRecordingAndTranscribe());
    });
  }

  bool get _recordingPhase =>
      state.phase == SpeechPhase.recording ||
      state.phase == SpeechPhase.cancelling;

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
    // ZH
    // 停止录音期间用户取消 / 页面销毁：丢弃文件，不上传、不插入（§3.1）。
    //
    // EN
    // User cancel / page dispose while stopping: delete the file, upload nothing, insert nothing (§3.1).
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
      final failure = await _insertAndMaybeSend(callback, trimmed);
      if (abort.isCompleted || _disposed || token != _token) return;
      state = state.copyWith(phase: SpeechPhase.idle);
      if (failure != null) _noticeVoice(failure);
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

  /// ZH
  /// 先插入，再按闸门尝试发送；返回需要提示的失败类别（`speech.md` §3.4）。
  ///
  /// EN
  /// Insert first, then try the gate; return the failure kind to report (`speech.md` §3.4).
  Future<VoiceInputFailure?> _insertAndMaybeSend(
    VoiceTranscriptHandler? callback,
    String text,
  ) async {
    if (callback == null) return null;
    try {
      final outcome = await callback(text);
      return switch (outcome) {
        VoiceAutoSendOutcome.sent => null,
        VoiceAutoSendOutcome.noApiKey => VoiceInputFailure.noApiKey,
        VoiceAutoSendOutcome.generating => VoiceInputFailure.insertedGenerating,
        VoiceAutoSendOutcome.uploading => VoiceInputFailure.insertedUploading,
        VoiceAutoSendOutcome.notSent => VoiceInputFailure.insertedNotSent,
        VoiceAutoSendOutcome.failed => VoiceInputFailure.sendFailedInserted,
      };
    } on Object catch (error) {
      debugLog('voice auto send failed', error);
      return VoiceInputFailure.sendFailedInserted;
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

  /// ZH
  /// 中断、切页、后台：丢弃录音，不上传。
  ///
  /// EN
  /// Interruption, page switch, background: discard the recording without uploading.
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

  /// ZH
  /// 启动期间手势结束：授权弹窗内只记录（授权后提示再按住），否则静默取消。
  ///
  /// EN
  /// Gesture end at start: note it in the permission prompt (re-hold after grant), else cancel silently.
  void _endActiveStart() {
    if (_granting) {
      _cancelWhileGranting = true;
      return;
    }
    _releasePending = true;
    _resetToIdle();
  }

  /// ZH
  /// 启动被中止：`failure` 为 null 时静默取消（松手早于启动完成）。
  ///
  /// EN
  /// Start aborted: a null `failure` means a silent cancel (release before start completed).
  void _abortStart(VoiceInputFailure? failure) {
    if (_disposed) return;
    _resetToIdle();
    if (failure != null) _noticeVoice(failure);
  }

  void _resetToIdle() {
    _onTranscript = null;
    _settleAfterAbort();
  }

  /// ZH
  /// 未停止的朗读在启动失败 / 取消后恢复原相位；否则回空闲。
  ///
  /// EN
  /// On start failure / cancel, an unstopped read-aloud restores its phase; otherwise return to idle.
  void _settleAfterAbort() {
    if (_disposed) return;
    final restore = _resumeReadingPhase;
    _resumeReadingPhase = null;
    _armedPending = false;
    state = state.copyWith(phase: restore ?? SpeechPhase.idle, level: 0);
  }

  void _cancelRecordingResources() {
    _levelSub?.cancel();
    _levelSub = null;
    _interruptionSub?.cancel();
    _interruptionSub = null;
    _capTimer?.cancel();
    _capTimer = null;
  }

  // ZH
  // ------------------------------------------------------------------ 朗读
  //
  // EN
  // ------------------------------------------------------------------ Read-Aloud.

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

      // ZH
      // 用户停止或播放器提前结束都会完成 done；两者都按调用方已收尾处理。
      //
      // EN
      // User stop or early player end completes done; both are treated as the caller having finished.
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
        // ZH
        // 已停止或引擎关闭时释放失败无需上抛。
        //
        // EN
        // Release failures after stop or engine shutdown need no rethrow.
      }
    }
  }

  // ZH
  // ------------------------------------------------------------------ 辅助
  //
  // EN
  // ------------------------------------------------------------------ Helpers.

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
        // ZH
        // 临时文件可能已被平台清理。
        //
        // EN
        // The temporary file may already be cleaned up by the platform.
      }
    }());
  }
}

final class _EmptyTtsException implements Exception {
  const _EmptyTtsException();
}
