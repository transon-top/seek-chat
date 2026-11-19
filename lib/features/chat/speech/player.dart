import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// 播放器抽象：一次朗读一条 PCM 流。
abstract interface class SpeechPlayer {
  Future<PlaybackSession> start();
}

abstract interface class PlaybackSession {
  /// 追加 PCM 数据块；奇数字节留到下一块拼接（`speech.md` §4.2）。
  void add(Uint8List chunk);

  /// 标记传输结束，播放器排空后触发 [completed]。
  Future<void> end();

  Stream<void> get completed;

  /// 停止并释放音频源；重复调用无副作用。
  Future<void> stop();
}

/// `flutter_soloud` 封装：裸 PCM（s16le、24 kHz、单声道），首帧 100 ms 缓冲。
class SoLoudSpeechPlayer implements SpeechPlayer {
  @override
  Future<PlaybackSession> start() async {
    if (!SoLoud.instance.isInitialized) await SoLoud.instance.init();
    final source = SoLoud.instance.setBufferStream(
      maxBufferSizeBytes: 8 * 1024 * 1024,
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.1,
      sampleRate: 24000,
      channels: Channels.mono,
      format: BufferType.s16le,
    );
    return _SoLoudPlayback(source);
  }
}

class _SoLoudPlayback implements PlaybackSession {
  _SoLoudPlayback(this._source) {
    _events = _source.soundEvents.listen((event) {
      if (event.event == SoundEventType.handleIsNoMoreValid && !_closed) {
        _completed.add(null);
      }
    });
  }

  final AudioSource _source;
  final StreamController<void> _completed = StreamController<void>.broadcast();
  late final StreamSubscription<StreamSoundEvent> _events;
  SoundHandle? _handle;
  Uint8List? _oddByte;
  bool _closed = false;
  bool _ended = false;

  @override
  void add(Uint8List chunk) {
    if (_closed || chunk.isEmpty) return;
    var bytes = chunk;
    final odd = _oddByte;
    if (odd != null) {
      bytes = Uint8List.fromList([...odd, ...chunk]);
      _oddByte = null;
    }
    if (bytes.length.isOdd) {
      _oddByte = Uint8List.fromList([bytes.last]);
      bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
    }
    if (bytes.isEmpty) return;
    SoLoud.instance.addAudioDataStream(_source, bytes);
    _handle ??= SoLoud.instance.play(_source);
  }

  @override
  Future<void> end() async {
    if (_closed || _ended) return;
    _ended = true;
    _oddByte = null;
    SoLoud.instance.setDataIsEnded(_source);
  }

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    await _events.cancel();
    try {
      final handle = _handle;
      if (handle != null) await SoLoud.instance.stop(handle);
      await SoLoud.instance.disposeSource(_source);
    } on Object {
      // 引擎关闭或音频已结束时释放失败无需上抛。
    }
    await _completed.close();
  }
}
