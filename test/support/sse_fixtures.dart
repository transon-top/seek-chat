import 'dart:convert';

import 'package:http/http.dart' as http;

/// ZH
/// SSE 帧与响应构造器，供 API、控制器与界面测试共用。
///
/// EN
/// SSE frame and response builders shared by API, controller, and UI tests.
String frame(String event, Map<String, dynamic> payload) =>
    'event: $event\ndata: ${jsonEncode(payload)}\n\n';

final messageStart = frame('message_start', {
  'type': 'message_start',
  'message': {'id': 'm1', 'model': 'deepseek-flash'},
});

String textStart(int index) => frame('content_block_start', {
  'type': 'content_block_start',
  'index': index,
  'content_block': {'type': 'text', 'text': ''},
});

String textDelta(int index, String text) => frame('content_block_delta', {
  'type': 'content_block_delta',
  'index': index,
  'delta': {'type': 'text_delta', 'text': text},
});

String textStop(int index) =>
    frame('content_block_stop', {'type': 'content_block_stop', 'index': index});

final messageStop = frame('message_stop', {'type': 'message_stop'});

http.StreamedResponse sseResponse(Stream<List<int>> body) =>
    http.StreamedResponse(
      body,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
