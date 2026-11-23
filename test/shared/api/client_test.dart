import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seek_chat/shared/api/client.dart';
import 'package:seek_chat/shared/api/errors.dart';
import 'package:seek_chat/shared/api/request.dart';
import 'package:seek_chat/shared/api/reply_accumulator.dart';
import 'package:seek_chat/shared/api/stream_events.dart';
import 'package:seek_chat/shared/models/types.dart';

const origin = 'https://api.test';

CreateMessageRequest basicRequest() => buildMessageRequest(
      history: const [],
      question: UserMessage(
        id: 'u1',
        createdAt: DateTime(2026, 1, 1),
        text: 'Hello',
      ),
      thinking: false,
      search: false,
    );

String frame(String event, Map<String, dynamic> payload) =>
    'event: $event\ndata: ${jsonEncode(payload)}\n\n';

final messageStart = frame('message_start', {
  'type': 'message_start',
  'message': {'id': 'm1', 'model': 'deepseek-flash'},
});
final textStart = frame('content_block_start', {
  'type': 'content_block_start',
  'index': 0,
  'content_block': {'type': 'text', 'text': ''},
});
final textDelta = frame('content_block_delta', {
  'type': 'content_block_delta',
  'index': 0,
  'delta': {'type': 'text_delta', 'text': 'Hi'},
});
final textStop = frame('content_block_stop', {
  'type': 'content_block_stop',
  'index': 0,
});
final messageDelta = frame('message_delta', {
  'type': 'message_delta',
  'delta': {'stop_reason': 'end_turn'},
});
final messageStop = frame('message_stop', {'type': 'message_stop'});

http.StreamedResponse sseResponse(
  String body, {
  int status = 200,
  String contentType = 'text/event-stream',
}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': contentType},
    );

Matcher apiError(
  ApiErrorKind kind, {
  int? status,
}) =>
    throwsA(
      isA<ApiException>()
          .having((e) => e.kind, 'kind', kind)
          .having((e) => e.status, 'status', status),
    );

void main() {
  group('streamMessage', () {
    test('sends the request and yields typed events until message_stop', () async {
      late http.BaseRequest captured;
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          captured = request;
          return sseResponse(
            messageStart + textStart + textDelta + textStop + messageDelta + messageStop,
          );
        }),
      );

      final events = await client
          .streamMessage(request: basicRequest(), apiKey: 'secret')
          .toList();

      expect(captured.method, 'POST');
      expect(captured.url.toString(), '$origin/anthropic/v1/messages');
      expect(captured.headers['x-api-key'], 'secret');
      expect(captured.headers['accept'], 'text/event-stream');
      expect(captured.headers['content-type'], 'application/json');
      expect(captured.headers.containsKey('anthropic-beta'), isFalse);

      final body = jsonDecode((captured as http.Request).body) as Map<String, dynamic>;
      expect(body['model'], 'deepseek-flash');
      expect(body['stream'], isTrue);
      expect(body['safety_check'], {'level': 'high'});
      expect(body['messages'], [
        {
          'role': 'user',
          'content': 'Hello',
        },
      ]);

      expect(events.whereType<MessageStart>().single.messageId, 'm1');
      expect(events.whereType<MessageStop>(), hasLength(1));
      final reply = ReplyAccumulator();
      for (final event in events) {
        reply.apply(event);
      }
      expect((reply.blocks.single as TextBlock).text, 'Hi');
      expect(reply.stopReason, StopReason.endTurn);
    });

    test('adds the Files API beta header when the request has file blocks', () async {
      late http.BaseRequest captured;
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          captured = request;
          return sseResponse(messageStart + messageDelta);
        }),
      );
      final request = buildMessageRequest(
        history: const [],
        question: UserMessage(
          id: 'u1',
          createdAt: DateTime(2026, 1, 1),
          text: 'look',
          attachments: const [
            Attachment(
              id: 'att-1',
              name: 'photo.png',
              size: 10,
              isImage: true,
              serverId: 'file-1',
            ),
          ],
        ),
        thinking: false,
        search: false,
      );

      await client.streamMessage(request: request, apiKey: 'secret').toList();

      expect(
        captured.headers['anthropic-beta'],
        DeepSeekApiClient.filesApiBeta,
      );
    });

    test('stops reading after message_stop', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async => sseResponse(
              messageStart + messageStop + textStart + messageStop,
            )),
      );

      final events = await client
          .streamMessage(request: basicRequest(), apiKey: 'secret')
          .toList();

      expect(events.whereType<MessageStop>(), hasLength(1));
      expect(events.whereType<ContentBlockStart>(), isEmpty);
    });

    test('maps HTTP errors to http exceptions with the server message', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async => http.StreamedResponse(
              Stream.value(utf8.encode(
                jsonEncode({
                  'error': {'type': 'authentication_error', 'message': 'bad key'},
                }),
              )),
              401,
              headers: {'content-type': 'application/json'},
            )),
      );

      await expectLater(
        client.streamMessage(request: basicRequest(), apiKey: 'secret').toList(),
        apiError(ApiErrorKind.http, status: 401),
      );
    });

    test('rejects non-SSE success responses as protocol errors', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async => sseResponse(
              '<html>nope</html>',
              contentType: 'text/html',
            )),
      );

      await expectLater(
        client.streamMessage(request: basicRequest(), apiKey: 'secret').toList(),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.protocol)
            .having((e) => e.message, 'message', '<html>nope</html>')),
      );
    });

    test('rejects an empty success body as a protocol error', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async => sseResponse('')),
      );

      await expectLater(
        client.streamMessage(request: basicRequest(), apiKey: 'secret').toList(),
        apiError(ApiErrorKind.protocol),
      );
    });

    test('completes without message_stop when a stop reason was seen', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async => sseResponse(
              messageStart + textStart + textDelta + messageDelta,
            )),
      );

      final events = await client
          .streamMessage(request: basicRequest(), apiKey: 'secret')
          .toList();

      expect(events.whereType<MessageDelta>().single.stopReason, StopReason.endTurn);
    });

    test('reports an interrupted stream when neither stop nor reason arrived', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async => sseResponse(
              messageStart + textStart + textDelta,
            )),
      );

      await expectLater(
        client.streamMessage(request: basicRequest(), apiKey: 'secret').toList(),
        apiError(ApiErrorKind.interrupted),
      );
    });

    test('propagates error frames as stream errors', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async => sseResponse(
              messageStart +
                  frame('error', {
                    'type': 'error',
                    'error': {'type': 'overloaded_error', 'message': 'busy'},
                  }),
            )),
      );

      await expectLater(
        client.streamMessage(request: basicRequest(), apiKey: 'secret').toList(),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.stream)
            .having((e) => e.message, 'message', 'busy')),
      );
    });

    test('maps connection failures to network errors', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          throw http.ClientException('offline');
        }),
      );

      await expectLater(
        client.streamMessage(request: basicRequest(), apiKey: 'secret').toList(),
        apiError(ApiErrorKind.network),
      );
    });

    test('does not wrap local aborts', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          throw http.RequestAbortedException(Uri.parse(origin));
        }),
      );

      await expectLater(
        client.streamMessage(request: basicRequest(), apiKey: 'secret').toList(),
        throwsA(isA<http.RequestAbortedException>()),
      );
    });
  });

  group('validateApiKey', () {
    test('accepts any 2xx from /models with a bearer token', () async {
      late http.BaseRequest captured;
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('{}', 200);
        }),
      );

      await client.validateApiKey('secret');

      expect(captured.method, 'GET');
      expect(captured.url.toString(), '$origin/models');
      expect(captured.headers['authorization'], 'Bearer secret');
    });

    test('maps 401 to an http error', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient((request) async => http.Response('', 401)),
      );

      await expectLater(
        client.validateApiKey('secret'),
        apiError(ApiErrorKind.http, status: 401),
      );
    });

    test('maps connection failures to network errors', () async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient((request) async {
          throw http.ClientException('dns');
        }),
      );

      await expectLater(
        client.validateApiKey('secret'),
        apiError(ApiErrorKind.network),
      );
    });
  });
}
