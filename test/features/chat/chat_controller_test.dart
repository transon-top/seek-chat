import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:open_chat/features/chat/chat_controller.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/api/errors.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/models/reply_rules.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:open_chat/shared/security/api_key_store.dart';

import '../../support/fake_api_key_store.dart';
import '../../support/sse_fixtures.dart';

const origin = 'https://api.test';

String messageDelta({String stopReason = 'end_turn', String? title}) =>
    frame('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': stopReason, 'title': ?title},
    });

/// 一段完整的 SSE 回复：一个文本块，随后正常结束。
String simpleReply(String text, {String? title}) =>
    messageStart +
    textStart(0) +
    textDelta(0, text) +
    textStop(0) +
    messageDelta(title: title) +
    messageStop;

http.StreamedResponse streamOf(String body) =>
    sseResponse(Stream.value(utf8.encode(body)));

/// 读取延迟到测试显式完成的密钥存储，用于“请求发出前停止”的用例。
final class _DeferredApiKeyStore implements ApiKeyStore {
  final Completer<String?> _key = Completer<String?>();

  void complete(String? value) => _key.complete(value);

  @override
  Future<String?> read() => _key.future;

  @override
  Future<void> write(String apiKey) async {}

  @override
  Future<void> clear() async {}
}

/// 读取即失败的密钥存储，用于请求发出前的错误映射用例。
final class _ThrowingApiKeyStore implements ApiKeyStore {
  _ThrowingApiKeyStore(this.error);

  final Object error;

  @override
  Future<String?> read() async => throw error;

  @override
  Future<void> write(String apiKey) async {}

  @override
  Future<void> clear() async {}
}

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

  ProviderContainer makeContainer({
    required DeepSeekApiClient client,
    ApiKeyStore? apiKeyStore,
  }) => ProviderContainer.test(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repository),
      apiClientProvider.overrideWithValue(client),
      apiKeyStoreProvider.overrideWithValue(
        apiKeyStore ?? FakeApiKeyStore('secret'),
      ),
    ],
  );

  ChatController controllerFor(ProviderContainer container, String sessionId) {
    container.listen(chatControllerProvider(sessionId), (_, _) {});
    return container.read(chatControllerProvider(sessionId).notifier);
  }

  Future<Session> newSession() => repository.createSession();

  test(
    'send streams the reply into the visible path and persists it',
    () async {
      final session = await newSession();
      late http.Request captured;
      final container = makeContainer(
        client: DeepSeekApiClient(
          origin: Uri.parse(origin),
          httpClient: MockClient.streaming((request, body) async {
            captured = request as http.Request;
            return streamOf(simpleReply('Hi there', title: 'Greeting'));
          }),
        ),
      );
      final controller = controllerFor(container, session.id);
      await controller.load();

      await controller.send(text: 'Hello', thinking: false, search: false);

      final messages = controller.state.messages;
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
      expect(controller.state.title, 'Greeting');
    },
  );

  test('stop keeps the partial text and persists a stopped reply', () async {
    final session = await newSession();
    final body = StreamController<List<int>>();
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming(
          (request, _) async => sseResponse(body.stream),
        ),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    final pending = controller.send(
      text: 'Hello',
      thinking: false,
      search: false,
    );
    body.add(
      utf8.encode(messageStart + textStart(0) + textDelta(0, 'partial')),
    );
    await pumpEventQueue();

    controller.stop();
    await body.close();
    await pending;

    final live = controller.state.messages.last as AssistantMessage;
    expect(live.status, ReplyStatus.stopped);
    expect((live.blocks.single as TextBlock).text, 'partial');

    final stored =
        (await repository.visiblePath(session.id)).last as AssistantMessage;
    expect(stored.status, ReplyStatus.stopped);
    expect((stored.blocks.single as TextBlock).text, 'partial');
  });

  test(
    'stream errors settle the reply as error with a persisted reason',
    () async {
      final session = await newSession();
      final container = makeContainer(
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
      );
      final controller = controllerFor(container, session.id);
      await controller.load();

      await controller.send(text: 'Hello', thinking: false, search: false);

      final live = controller.state.messages.last as AssistantMessage;
      expect(live.status, ReplyStatus.error);
      expect(live.error?.kind, ApiErrorKind.stream);
      expect(live.error?.message, 'boom');

      final stored =
          (await repository.visiblePath(session.id)).last as AssistantMessage;
      expect(stored.status, ReplyStatus.error);
      expect(stored.error?.message, 'boom');
    },
  );

  test('regenerate adds a sibling version and keeps the old reply', () async {
    final session = await newSession();
    var call = 0;
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          call++;
          return streamOf(simpleReply(call == 1 ? 'first' : 'second'));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();
    await controller.send(text: 'Hello', thinking: false, search: false);

    final firstReply = controller.state.messages.last as AssistantMessage;
    await controller.regenerate(firstReply, thinking: false, search: false);

    final visible = controller.state.messages;
    expect(visible, hasLength(2));
    expect(
      ((visible.last as AssistantMessage).blocks.single as TextBlock).text,
      'second',
    );

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
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          call++;
          if (call == 1) return sseResponse(body.stream);
          if (call == 2) return streamOf(simpleReply(' more'));
          return streamOf(simpleReply(''));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    final pending = controller.send(
      text: 'Hello',
      thinking: true,
      search: false,
    );
    body.add(
      utf8.encode(messageStart + textStart(0) + textDelta(0, 'partial')),
    );
    await pumpEventQueue();
    controller.stop();
    await body.close();
    await pending;

    final stopped = controller.state.messages.last as AssistantMessage;
    expect(canContinueReply(stopped), isTrue);

    await controller.continueReply(stopped, thinking: true, search: false);

    final continued = controller.state.messages.last as AssistantMessage;
    expect(continued.id, stopped.id);
    expect(continued.status, ReplyStatus.done);
    expect(
      continued.blocks.whereType<TextBlock>().map((b) => b.text).join(),
      'partial more',
    );

    final stored =
        (await repository.visiblePath(session.id)).last as AssistantMessage;
    expect(stored.id, stopped.id);
    expect(
      stored.blocks.whereType<TextBlock>().map((b) => b.text).join(),
      'partial more',
    );
  });

  test('stop before the request starts prevents sending', () async {
    final session = await newSession();
    final store = _DeferredApiKeyStore();
    var requests = 0;
    final container = makeContainer(
      apiKeyStore: store,
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          requests++;
          return streamOf(simpleReply('nope'));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    final pending = controller.send(
      text: 'Hello',
      thinking: false,
      search: false,
    );
    controller.stop();
    store.complete('secret');
    await pending;

    expect(requests, 0);
    expect(controller.state.messages, isEmpty);
  });

  test('flush persists the in-memory reply while streaming', () async {
    final session = await newSession();
    final body = StreamController<List<int>>();
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming(
          (request, _) async => sseResponse(body.stream),
        ),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    final pending = controller.send(
      text: 'Hello',
      thinking: false,
      search: false,
    );
    body.add(
      utf8.encode(messageStart + textStart(0) + textDelta(0, 'partial')),
    );
    await pumpEventQueue();

    await controller.flush();

    final stored =
        (await repository.visiblePath(session.id)).last as AssistantMessage;
    expect(stored.status, ReplyStatus.streaming);
    expect((stored.blocks.single as TextBlock).text, 'partial');

    controller.stop();
    await body.close();
    await pending;
  });

  test('send without an API key fails locally and sends nothing', () async {
    final session = await newSession();
    var requests = 0;
    final container = makeContainer(
      apiKeyStore: FakeApiKeyStore(),
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          requests++;
          return streamOf(simpleReply('nope'));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    await controller.send(text: 'Hello', thinking: false, search: false);

    expect(requests, 0);
    expect(controller.state.messages, isEmpty);
    expect(controller.state.error?.key, LocalMessageKeys.errorNoApiKey);
  });

  test('maps a pre-stream API failure into a local message key', () async {
    final session = await newSession();
    var requests = 0;
    final container = makeContainer(
      apiKeyStore: _ThrowingApiKeyStore(
        ApiException(ApiErrorKind.network, 'offline'),
      ),
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          requests++;
          return streamOf(simpleReply('nope'));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    await controller.send(text: 'Hello', thinking: false, search: false);

    expect(requests, 0);
    expect(controller.state.messages, isEmpty);
    expect(controller.state.busy, isFalse);
    expect(controller.state.error?.key, LocalMessageKeys.apiErrorNetwork);
  });
}
