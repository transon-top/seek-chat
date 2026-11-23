import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// ZH
/// 没有可用的输入设备；与启动失败区分文案（`speech.md` §6.1）。
///
/// EN
/// No input device is available; the copy differs from a start failure (`speech.md` §6.1).
final class NoInputDeviceException implements Exception {
  const NoInputDeviceException();
}

/// ZH
/// 录音器抽象：一次录音一个会话，会话结束后释放原生录音器。
///
/// EN
/// Recorder abstraction: one Session per recording, releasing the native recorder when it ends.
abstract interface class SpeechRecorder {
  Future<RecordingSession> start();
}

abstract interface class RecordingSession {
  /// ZH
  /// 电平 0..1，由 dBFS 映射（§7）。
  ///
  /// EN
  /// Level 0..1, mapped from dBFS (§7).
  Stream<double> get levels;

  /// ZH
  /// 系统中断：来电、其他应用占用音频、路由变化（§3.2）。
  ///
  /// EN
  /// System interruptions: incoming calls, audio taken by other apps, route changes (§3.2).
  Stream<void> get interruptions;

  /// ZH
  /// 结束录音并保留临时文件；无样本时返回 null。
  ///
  /// EN
  /// End the recording and keep the temporary file; returns null when there are no samples.
  Future<String?> stop();

  /// ZH
  /// 结束录音并丢弃临时文件。
  ///
  /// EN
  /// End the recording and discard the temporary file.
  Future<void> cancel();
}

/// ZH
/// `record` 封装：16-bit PCM WAV、16 kHz、单声道，写入临时目录。
///
/// EN
/// `record` wrapper: 16-bit PCM WAV, 16 kHz, mono, written to the temporary directory.
class DeviceSpeechRecorder implements SpeechRecorder {
  @override
  Future<RecordingSession> start() async {
    final recorder = AudioRecorder();
    try {
      final devices = await recorder.listInputDevices();
      if (devices.isEmpty) throw const NoInputDeviceException();
      final directory = Directory(
        '${(await getTemporaryDirectory()).path}/open_chat_voice',
      );
      await directory.create(recursive: true);
      await _removeStaleFiles(directory);
      final path = '${directory.path}/recording.wav';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: false,
          audioInterruption: AudioInterruptionMode.pause,
          audioRouteChange: AudioRouteChangeMode.pause,
        ),
        path: path,
      );
      return _RecordSession(recorder, path);
    } on Object {
      await recorder.dispose();
      rethrow;
    }
  }

  /// ZH
  /// 启动时清理上次残留的录音文件（§3.2）。
  ///
  /// EN
  /// Remove recording files left over from the previous run at startup (§3.2).
  Future<void> _removeStaleFiles(Directory directory) async {
    await for (final entry in directory.list()) {
      if (entry is! File) continue;
      try {
        await entry.delete();
      } on FileSystemException {
        // ZH
        // 清理失败不阻塞录音。
        //
        // EN
        // Cleanup failures do not block recording.
      }
    }
  }
}

class _RecordSession implements RecordingSession {
  _RecordSession(this._recorder, this._path);

  final AudioRecorder _recorder;
  final String _path;
  bool _closing = false;

  @override
  Stream<double> get levels => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((amplitude) => ((amplitude.current + 50) / 50).clamp(0.0, 1.0));

  /// ZH
  /// 用户主动停止时 `_closing` 已为 true，不计为中断。
  ///
  /// EN
  /// On user stop `_closing` is already true, so it is not counted as an interruption.
  @override
  Stream<void> get interruptions => _recorder
      .onStateChanged()
      .where(
        (state) =>
            !_closing &&
            (state == RecordState.pause || state == RecordState.stop),
      )
      .map((_) {});

  @override
  Future<String?> stop() async {
    if (_closing) return null;
    _closing = true;
    try {
      return await _recorder.stop();
    } finally {
      await _recorder.dispose();
    }
  }

  @override
  Future<void> cancel() async {
    if (_closing) return;
    _closing = true;
    try {
      await _recorder.cancel();
    } finally {
      try {
        final file = File(_path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // ZH
        // 文件可能已被平台删除。
        //
        // EN
        // The file may already be deleted by the platform.
      }
      await _recorder.dispose();
    }
  }
}
