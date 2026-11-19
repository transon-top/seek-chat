import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 没有可用的输入设备；与启动失败区分文案（`speech.md` §6.1）。
final class NoInputDeviceException implements Exception {
  const NoInputDeviceException();
}

/// 录音器抽象：一次录音一个会话，会话结束后释放原生录音器。
abstract interface class SpeechRecorder {
  Future<RecordingSession> start();
}

abstract interface class RecordingSession {
  /// 电平 0..1，由 dBFS 映射（§7）。
  Stream<double> get levels;

  /// 系统中断：来电、其他应用占用音频、路由变化（§3.2）。
  Stream<void> get interruptions;

  /// 结束录音并保留临时文件；无样本时返回 null。
  Future<String?> stop();

  /// 结束录音并丢弃临时文件。
  Future<void> cancel();
}

/// `record` 封装：16-bit PCM WAV、16 kHz、单声道，写入临时目录。
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

  /// 启动时清理上次残留的录音文件（§3.2）。
  Future<void> _removeStaleFiles(Directory directory) async {
    await for (final entry in directory.list()) {
      if (entry is! File) continue;
      try {
        await entry.delete();
      } on FileSystemException {
        // 清理失败不阻塞录音。
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

  /// 用户主动停止时 `_closing` 已为 true，不计为中断。
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
        // 文件可能已被平台删除。
      }
      await _recorder.dispose();
    }
  }
}
