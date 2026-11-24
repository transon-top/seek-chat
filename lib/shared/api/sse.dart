import 'dart:convert';

/// ZH
/// 一条已派发的 Server-Sent Events 帧。
///
/// [event] 缺省为 `message`；[data] 是多行 payload 以 `\n` 连接后的结果，
/// 不含末尾换行。
///
/// EN
/// One dispatched Server-Sent Events frame.
///
/// [event] defaults to `message`. [data] is a multi-line payload joined with `\n`;
/// it has no trailing newline.
class SseEvent {
  const SseEvent({required this.event, required this.data});

  final String event;
  final String data;
}

/// ZH
/// 由调用方驱动响应字节流时使用的同步适配器。
///
/// EN
/// Synchronous adapter for caller-driven response byte streams.
class SseDecoder {
  final List<SseEvent> _events = <SseEvent>[];
  late final SseParser _parser = SseParser(_events.add);

  /// ZH
  /// 喂入一个分片，取走它补齐的全部帧。
  ///
  /// EN
  /// Feed one chunk and take all frames it completes.
  List<SseEvent> add(List<int> bytes) {
    _parser.add(bytes);
    return _drain();
  }

  void close() {
    _parser.close();
    _events.clear();
  }

  List<SseEvent> _drain() {
    final events = List<SseEvent>.of(_events);
    _events.clear();
    return events;
  }
}

/// ZH
/// WHATWG Server-Sent Events 解析器。
///
/// 用 [add] 喂入原始响应字节。只有以空行结束的完整帧才会派发；流结束时
/// 未完结的尾部帧按规范丢弃（见 [close]）。
///
/// EN
/// WHATWG Server-Sent Events parser.
///
/// Feed raw response bytes with [add]. Only complete frames ending in a blank line are
/// dispatched; at end of stream, incomplete trailing frames are dropped per spec (see [close]).
class SseParser {
  SseParser(this._onEvent);

  final void Function(SseEvent event) _onEvent;

  final List<int> _line = <int>[];
  final List<int> _bomBuffer = <int>[];
  final StringBuffer _data = StringBuffer();
  String? _eventName;
  bool _started = false;
  bool _expectLf = false;

  void add(List<int> bytes) {
    for (final byte in bytes) {
      if (!_started) {
        _bomBuffer.add(byte);
        if (_bomBuffer.length >= 3) _startStream();
        continue;
      }
      _processByte(byte);
    }
  }

  void close() {
    _startStream();
    // ZH
    // 未以空行结束的帧永远不派发。
    //
    // EN
    // Frames not terminated by a blank line are never dispatched.
    _line.clear();
    _data.clear();
    _eventName = null;
  }

  void _startStream() {
    if (_started) return;
    _started = true;
    final hasBom = _bomBuffer.length >= 3 &&
        _bomBuffer[0] == 0xEF &&
        _bomBuffer[1] == 0xBB &&
        _bomBuffer[2] == 0xBF;
    for (var i = hasBom ? 3 : 0; i < _bomBuffer.length; i++) {
      _processByte(_bomBuffer[i]);
    }
    _bomBuffer.clear();
  }

  void _processByte(int byte) {
    if (_expectLf) {
      _expectLf = false;
      if (byte == 0x0A) return;
    }
    if (byte == 0x0D) {
      _dispatchLine();
      _expectLf = true;
    } else if (byte == 0x0A) {
      _dispatchLine();
    } else {
      _line.add(byte);
    }
  }

  void _dispatchLine() {
    final line = utf8.decode(_line, allowMalformed: true);
    _line.clear();
    if (line.isEmpty) {
      _dispatchEvent();
      return;
    }
    if (line.startsWith(':')) return;

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'data':
        _data
          ..write(value)
          ..write('\n');
      case 'event':
        _eventName = value;
      // ZH
      // `id` 与 `retry` 不影响本客户端：不自动重连、不续传。
      //
      // EN
      // `id` and `retry` do not affect this client: no auto-reconnect and no resume.
    }
  }

  void _dispatchEvent() {
    if (_data.isEmpty) {
      _eventName = null;
      return;
    }
    final data = _data.toString();
    _data.clear();
    final name = _eventName?.isNotEmpty == true ? _eventName! : 'message';
    _eventName = null;
    _onEvent(SseEvent(event: name, data: data.substring(0, data.length - 1)));
  }
}
