import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_chat/api/client.dart';
import 'package:open_chat/chat/chat_controller.dart';
import 'package:open_chat/chat/reply_rules.dart';
import 'package:open_chat/data/chat_repository.dart';
import 'package:open_chat/data/database.dart';
import 'package:open_chat/models/types.dart';

const origin = 'https://api.test';

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

String textStop(int index) => frame('content_block_stop', {
      'type': 'content_block_stop',
      'index': index,
    });

String messageDelta({
  String stopReason = 'end_turn',
  String? title,
}) =>
    frame('message_delta', {
      'type': 'message_delta',
      'delta': {
        'stop_reason': stopReason,
        'title': ?title,
      },
    });

final messageStop = frame('message_stop', {'type': 'message_stop'});

/// 一段完整的 SSE 回复：一个文本块，随后正常结束。
String simpleReply(String text, {String? title}) =>
    messageStart +
    textStart(0) +
    textDelta(0, text) +
    textStop(0) +
    messageDelta(title: title) +
    messageStop;

http.StreamedResponse sseResponse(Stream<List<int>> body) =>
    http.StreamedResponse(body, 200, headers: {'content-type': 'text/event-stream'});

http.StreamedResponse streamOf(String body) =>
    sseResponse(Stream.value(utf8.encode(body)));

void main() {
  late AppDatabase db;
  late ChatRepository repository;
  var tick = 1000;

  setUp(() {
    tick = 1000;
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db, clock: () => tick++);
  });

  tearDown(() => db.close());

  Future<Session> newSession() => repository.createSession();

  test('send streams the reply into the visible path and persists it', () async {
    final session = await newSession();
    late http.Request captured;
    final controller = ChatController(
      repository: repository,
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          captured = request as http.Request;
          return streamOf(simpleReply('Hi there', title: 'Greeting'));
        }),
      ),
      sessionId: session.id,
      readApiKey: () async => 'secret',
    );
    await controller.load();

    await controller.send(text: 'Hello', thinking: false, search: false);

    final messages = controller.messages;
    expect(messages, hasLength(2));
    expect((messages.first as UserMessage).text, 'Hello');
    final live = messages.last as AssistantMessage;
    expect(live.status, ReplyStatus.done);
    expect((live.blocks.single as TextBlock).text, 'Hi there');

    final persisted = await repository.visiblePath(session.id);
    final stored = persisted.last as AssistantMessage;
    expect(stored.status, ReplyStatus.done);
    expect((stored.blocks.single as TextBlock).text, 'Hi there');

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.headers['x-api-key'], 'secret');
    expect(body['messages'], [
      {'role': 'user', 'content': 'Hello'},
    ]);
    expect(body['title'], {'enabled': true});

    expect((await repository.getSession(session.id))!.title, 'Greeting');
    expect(controller.title, 'Greeting');
  });

  test('stop keeps the partial text and persists a stopped reply', () async {
    final session = await newSession();
    final body = StreamController<List<int>>();
    final controller = ChatController(
      repository: repository,
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming(
          (request, _) async => sseResponse(body.stream),
        ),
      ),
      sessionId: session.id,
      readApiKey: () async => 'secret',
    );
    await controller.load();

    final pending = controller.send(text: 'Hello', thinking: false, search: false);
    body.add(utf8.encode(
      messageStart + textStart(0) + textDelta(0, 'partial'),
    ));
    await pumpEventQueue();

    controller.stop();
    await body.close();
    await pending;

    final live = controller.messages.last as AssistantMessage;
    expect(live.status, ReplyStatus.stopped);
    expect((live.blocks.single as TextBlock).text, 'partial');

    final stored = (await repository.visiblePath(session.id)).last
        as AssistantMessage;
    expect(stored.status, ReplyStatus.stopped);
    expect((stored.blocks.single as TextBlock).text, 'partial');
  });

  test('stream errors settle the reply as error with a persisted reason',
      () async {
    final session = await newSession();
    final controller = ChatController(
      repository: repository,
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          return streamOf(
            messageStart +
                textStart(0) +
                textDelta(0, 'half') +
                frame('error', {
                  'type': 'error',
                  'error': {'message': 'boom'},
                }),
          );
        }),
      ),
      sessionId: session.id,
      readApiKey: () async => 'secret',
    );
    await controller.load();

    await controller.send(text: 'Hello', thinking: false, search: false);

    final live = controller.messages.last as AssistantMessage;
    expect(live.status, ReplyStatus.error);
    expect(live.error?.kind, ApiErrorKind.stream);
    expect(live.error?.message, 'boom');

    final stored = (await repository.visiblePath(session.id)).last
        as AssistantMessage;
    expect(stored.status, ReplyStatus.error);
    expect(stored.error?.message, 'boom');
  });

  test('regenerate adds a sibling version and keeps the old reply', () async {
    final session = await newSession();
    var call = 0;
    final controller = ChatController(
      repository: repository,
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          call++;
          return streamOf(simpleReply(call == 1 ? 'first' : 'second'));
        }),
      ),
      sessionId: session.id,
      readApiKey: () async => 'secret',
    );
    await controller.load();
    await controller.send(text: 'Hello', thinking: false, search: false);

    final firstReply = controller.messages.last as AssistantMessage;
    await controller.regenerate(firstReply, thinking: false, search: false);

    final visible = controller.messages;
    expect(visible, hasLength(2));
    expect(((visible.last as AssistantMessage).blocks.single as TextBlock).text,
        'second');

    final siblings = await repository.siblings(
      session.id,
      (visible.last as AssistantMessage).parentId,
    );
    expect(siblings, hasLength(2));
    expect(
      ((siblings.first as AssistantMessage).blocks.single as TextBlock).text,
      'first',
    );
  });

  test('continue appends to the same reply and reuses it', () async {
    final session = await newSession();
    final body = StreamController<List<int>>();
    var call = 0;
    final controller = ChatController(
      repository: repository,
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          call++;
          if (call == 1) return sseResponse(body.stream);
          if (call == 2) return streamOf(simpleReply(' more'));
          return streamOf(simpleReply(''));
        }),
      ),
      sessionId: session.id,
      readApiKey: () async => 'secret',
    );
    await controller.load();

    final pending = controller.send(text: 'Hello', thinking: true, search: false);
    body.add(utf8.encode(
      messageStart + textStart(0) + textDelta(0, 'partial'),
    ));
    await pumpEventQueue();
    controller.stop();
    await body.close();
    await pending;

    final stopped = controller.messages.last as AssistantMessage;
    expect(canContinueReply(stopped), isTrue);

    await controller.continueReply(stopped, thinking: true, search: false);

    final continued = controller.messages.last as AssistantMessage;
    expect(continued.id, stopped.id);
    expect(continued.status, ReplyStatus.done);
    expect(
      continued.blocks.whereType<TextBlock>().map((b) => b.text).join(),
      'partial more',
    );

    final stored = (await repository.visiblePath(session.id)).last
        as AssistantMessage;
    expect(stored.id, stopped.id);
    expect(
      stored.blocks.whereType<TextBlock>().map((b) => b.text).join(),
      'partial more',
    );
  });

  test('stop before the request starts prevents sending', () async {
    final session = await newSession();
    final key = Completer<String?>();
    var requests = 0;
    final controller = ChatController(
      repository: repository,
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          requests++;
          return streamOf(simpleReply('nope'));
        }),
      ),
      sessionId: session.id,
      readApiKey: () => key.future,
    );
    await controller.load();

    final pending =
        controller.send(text: 'Hello', thinking: false, search: false);
    controller.stop();
    key.complete('secret');
    await pending;

    expect(requests, 0);
    expect(controller.messages, isEmpty);
  });

  test('flush persists the in-memory reply while streaming', () async {
    final session = await newSession();
    final body = StreamController<List<int>>();
    final controller = ChatController(
      repository: repository,
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming(
          (request, _) async => sseResponse(body.stream),
        ),
      ),
      sessionId: session.id,
      readApiKey: () async => 'secret',
    );
    await controller.load();

    final pending = controller.send(text: 'Hello', thinking: false, search: false);
    body.add(utf8.encode(
      messageStart + textStart(0) + textDelta(0, 'partial'),
    ));
    await pumpEventQueue();

    await controller.flush();

    final stored = (await repository.visiblePath(session.id)).last
        as AssistantMessage;
    expect(stored.status, ReplyStatus.streaming);
    expect((stored.blocks.single as TextBlock).text, 'partial');

    controller.stop();
    await body.close();
    await pending;
  });

  test('send without an API key fails locally and sends nothing', () async {
    final session = await newSession();
    var requests = 0;
    final controller = ChatController(
      repository: repository,
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          requests++;
          return streamOf(simpleReply('nope'));
        }),
      ),
      sessionId: session.id,
      readApiKey: () async => null,
    );
    await controller.load();

    await controller.send(text: 'Hello', thinking: false, search: false);

    expect(requests, 0);
    expect(controller.messages, isEmpty);
    expect(controller.error, isNotNull);
  });
}
