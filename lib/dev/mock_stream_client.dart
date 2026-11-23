import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// ZH
/// 慢速流式 mock：替换传输层，让真实 DeepSeekApiClient 收到按节奏吐出的
/// Anthropic 兼容 SSE，用来观察思考块与正文的逐字渲染。
///
/// 开启：
/// `flutter run --dart-define=OPEN_CHAT_MOCK_STREAM=true`
/// 调整每块间隔：
/// `--dart-define=OPEN_CHAT_MOCK_STREAM_DELAY_MS=200`
///
/// 仍需要设置里存有任意 API Key（mock 不校验）。
///
/// EN
/// Slow streaming mock: replaces the transport so the real DeepSeekApiClient receives
/// paced Anthropic-compatible SSE, for watching per-token thinking and body rendering.
///
/// Enable:
/// `flutter run --dart-define=OPEN_CHAT_MOCK_STREAM=true`
/// Adjust the interval between chunks:
/// `--dart-define=OPEN_CHAT_MOCK_STREAM_DELAY_MS=200`
///
/// An API Key still must exist in settings (the mock does not validate it).
class MockStreamClient extends http.BaseClient {
  MockStreamClient({
    this.ttfb = const Duration(milliseconds: 900),
    this.chunkDelay = const Duration(milliseconds: 150),
  });

  /// ZH
  /// 首字节延迟，模拟弱网下的等待。
  ///
  /// EN
  /// Time to first byte, simulating a slow-network wait.
  final Duration ttfb;

  /// ZH
  /// 每个增量块之间的间隔。
  ///
  /// EN
  /// Interval between incremental chunks.
  final Duration chunkDelay;

  static const String _model = 'deepseek-flash';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/models')) {
      return _json(request, 200, {'data': []});
    }
    if (request.method != 'POST' || !request.url.path.endsWith('/messages')) {
      return _json(request, 404, {
        'error': {'message': 'mock: unsupported endpoint'},
      });
    }

    final body = _requestJson(request);
    final thinking = (body['thinking'] as Map?)?['type'] == 'enabled';
    final title = (body['title'] as Map?)?['enabled'] == true;
    return http.StreamedResponse(
      _sse(thinking: thinking, title: title),
      200,
      headers: const {'content-type': 'text/event-stream'},
      request: request,
    );
  }

  http.StreamedResponse _json(
    http.BaseRequest request,
    int status,
    Map<String, dynamic> body,
  ) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    status,
    headers: const {'content-type': 'application/json'},
    request: request,
  );

  Map<String, dynamic> _requestJson(http.BaseRequest request) {
    if (request is! http.Request || request.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(request.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  Stream<List<int>> _sse({required bool thinking, required bool title}) async* {
    await Future<void>.delayed(ttfb);

    yield _frame('message_start', {
      'type': 'message_start',
      'message': {
        'id': 'msg_mock',
        'model': _model,
        'usage': {'input_tokens': 58, 'output_tokens': 1},
      },
    });

    var index = 0;
    if (thinking) {
      yield _frame('content_block_start', {
        'type': 'content_block_start',
        'index': index,
        'content_block': {'type': 'thinking', 'thinking': ''},
      });
      for (final piece in _chunks(_thinkingText)) {
        await Future<void>.delayed(chunkDelay);
        yield _frame('content_block_delta', {
          'type': 'content_block_delta',
          'index': index,
          'delta': {'type': 'thinking_delta', 'thinking': piece},
        });
      }
      yield _frame('content_block_delta', {
        'type': 'content_block_delta',
        'index': index,
        'delta': {'type': 'signature_delta', 'signature': 'mock-signature'},
      });
      yield _frame('content_block_stop', {
        'type': 'content_block_stop',
        'index': index,
      });
      index++;
    }

    yield _frame('content_block_start', {
      'type': 'content_block_start',
      'index': index,
      'content_block': {'type': 'text', 'text': ''},
    });
    for (final piece in _chunks(_replyText)) {
      await Future<void>.delayed(chunkDelay);
      yield _frame('content_block_delta', {
        'type': 'content_block_delta',
        'index': index,
        'delta': {'type': 'text_delta', 'text': piece},
      });
    }
    yield _frame('content_block_stop', {
      'type': 'content_block_stop',
      'index': index,
    });

    yield _frame('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn', if (title) 'title': '慢速流式 Mock'},
      'usage': {'output_tokens': 142},
    });
    yield _frame('message_stop', {'type': 'message_stop'});
  }

  /// ZH
  /// 按固定字数切块；中文每块 3 字，肉眼能看清逐个落下的节奏。
  ///
  /// EN
  /// Split by fixed character count: three Chinese characters per chunk to see each drop.
  Iterable<String> _chunks(String text) sync* {
    const size = 3;
    for (var start = 0; start < text.length; start += size) {
      final end = start + size;
      yield text.substring(start, end > text.length ? text.length : end);
    }
  }

  List<int> _frame(String event, Map<String, dynamic> data) =>
      utf8.encode('event: $event\ndata: ${jsonEncode(data)}\n\n');

  static const String _thinkingText =
      '用户想观察发送消息后的慢速流式效果。\n'
      '1. 先确认 mock 会分两段推送：先思考，再正文。\n'
      '2. 每一小段之间留出延迟，模拟弱网。\n'
      '3. 正文里放少量 Markdown，顺便检查增量渲染。\n'
      '整个过程不联网，也没有真实 token 消耗。';

  /// ZH
  /// 约 14 段，手机上约为两倍视口高度，用于观察生成中的滚动行为。
  ///
  /// EN
  /// About 14 sections, roughly two viewports on mobile, for observing scroll while streaming.
  static final String _replyText = _buildReplyText();

  static String _buildReplyText() {
    final buffer = StringBuffer(
      '这是通过 mock 的 **慢速 SSE** 逐块推送的长回复，'
      '用来测试生成中内容超过视口时的滚动效果。\n\n',
    );
    for (var section = 1; section <= 14; section++) {
      buffer
        ..writeln('## 第 $section 段')
        ..writeln()
        ..writeln(
          '这一段把内容撑到两倍视口高度。段落里混入 **加粗**、`行内代码` '
          '和 [链接](https://example.com/$section)，检查流式渲染时的换行与间距。',
        )
        ..writeln()
        ..writeln('- 列表项 A：滚动时不要被拉回底部')
        ..writeln('- 列表项 B：继续生成时保持当前位置')
        ..writeln('- 列表项 C：停止后已收到的内容保留')
        ..writeln();
      if (section == 3) {
        buffer
          ..writeln('```dart')
          ..writeln("void main() => print('slow stream $section');")
          ..writeln('```')
          ..writeln();
      }
    }
    buffer.writeln('看到这里说明流已经结束。');
    return buffer.toString();
  }
}
