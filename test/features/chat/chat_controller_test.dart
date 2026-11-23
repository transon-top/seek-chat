import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:open_chat/features/chat/chat_controller.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/api/errors.dart';
import 'package:open_chat/shared/data/attachment_store.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/models/location.dart';
import 'package:open_chat/shared/models/reply_rules.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:open_chat/shared/prefs/preferences_provider.dart';
import 'package:open_chat/shared/prefs/user_metadata_store.dart';
import 'package:open_chat/shared/security/api_key_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api_key_store.dart';
import '../../support/sse_fixtures.dart';

const origin = 'https://api.test';

String messageDelta({String stopReason = 'end_turn', String? title}) =>
    frame('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': stopReason, 'title': ?title},
    });

/// ZH
/// 一段完整的 SSE 回复：一个文本块，随后正常结束。
///
/// EN
/// A complete SSE reply: one text block followed by a normal end.
String simpleReply(String text, {String? title}) =>
    messageStart +
    textStart(0) +
    textDelta(0, text) +
    textStop(0) +
    messageDelta(title: title) +
    messageStop;

http.StreamedResponse streamOf(String body) =>
    sseResponse(Stream.value(utf8.encode(body)));

/// ZH
/// 读取延迟到测试显式完成的密钥存储，用于“请求发出前停止”的用例。
///
/// EN
/// Key store whose read waits for the test to finish it, for the 'stop before request' case.
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

/// ZH
/// 读取即失败的密钥存储，用于请求发出前的错误映射用例。
///
/// EN
/// Key store that fails on read, for error mapping before the request is sent.
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
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ChatRepository repository;
  late Directory support;
  late SharedPreferences prefs;
  var tick = 1000;

  setUp(() async {
    tick = 1000;
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db, clock: () => tick++);
    support = await Directory.systemTemp.createTemp('chat-attachments-test');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
    await support.delete(recursive: true);
  });

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
      attachmentStoreProvider.overrideWithValue(
        AttachmentStore(supportDirectory: () async => support),
      ),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );

  http.StreamedResponse jsonResponse(Object body, {int status = 200}) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );

  File pickedFile(String name, {String content = 'data'}) {
    final file = File(p.join(support.path, name))..writeAsStringSync(content);
    return file;
  }

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
      final wireMessages = body['messages'] as List<dynamic>;
      expect(wireMessages.first['role'], 'latest_reminder');
      expect(wireMessages.last, {'role': 'user', 'content': 'Hello'});
      expect(wireMessages, hasLength(2));
      expect(body['title'], {'enabled': true});

      expect((await repository.getSession(session.id))!.title, 'Greeting');
      expect(controller.state.title, 'Greeting');
    },
  );

  test(
    'send injects the metadata snapshot and stores it on the reply',
    () async {
      final session = await newSession();
      late http.Request captured;
      final container = makeContainer(
        client: DeepSeekApiClient(
          origin: Uri.parse(origin),
          httpClient: MockClient.streaming((request, body) async {
            captured = request as http.Request;
            return streamOf(simpleReply('ok'));
          }),
        ),
      );
      final metadata = container.read(userMetadataProvider.notifier);
      await metadata.setLocale('zh');
      await metadata.setLocation(
        const UserLocation(region: 'CN', province: '330000', city: '330100'),
      );
      final controller = controllerFor(container, session.id);
      await controller.load();

      await controller.send(text: 'Hello', thinking: false, search: false);

      final stored =
          (await repository.visiblePath(session.id)).last as AssistantMessage;
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      expect(messages.first, {
        'role': 'latest_reminder',
        'content': stored.latestReminder,
      });
      expect(stored.latestReminder, contains(',杭州市,'));
      expect(stored.latestReminder, endsWith(',App,中文'));
      expect(controller.state.messages.last, isA<AssistantMessage>());
      expect(
        (controller.state.messages.last as AssistantMessage).latestReminder,
        stored.latestReminder,
      );

      // ZH
      // 切换语言不改写已生成回复的快照。
      //
      // EN
      // Switching the language does not rewrite the snapshot of generated replies.
      final original = stored.latestReminder;
      await metadata.setLocale('en');
      final reloaded =
          (await repository.visiblePath(session.id)).last as AssistantMessage;
      expect(reloaded.latestReminder, original);
    },
  );

  test('continuation keeps the original metadata snapshot', () async {
    final session = await newSession();
    final bodies = <Map<String, dynamic>>[];
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          bodies.add(
            jsonDecode((request as http.Request).body) as Map<String, dynamic>,
          );
          return streamOf(simpleReply(' more'));
        }),
      ),
    );
    final metadata = container.read(userMetadataProvider.notifier);
    await metadata.setLocale('zh');
    await metadata.setLocation(
      const UserLocation(region: 'CN', province: '330000', city: '330100'),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    await controller.send(text: 'Hello', thinking: false, search: false);
    final sent = controller.state.messages.last as AssistantMessage;
    final original = sent.latestReminder;
    expect(original, isNotNull);

    await metadata.setLocation(
      const UserLocation(region: 'CN', province: '110000', city: '110100'),
    );
    await controller.continueReply(sent, thinking: false, search: false);

    final messages = bodies.last['messages'] as List<dynamic>;
    expect(messages.first, {'role': 'latest_reminder', 'content': original});
    expect(
      messages.where((item) => (item as Map)['role'] == 'latest_reminder'),
      hasLength(1),
    );
    final stored =
        (await repository.visiblePath(session.id)).last as AssistantMessage;
    expect(stored.latestReminder, original);
  });

  test(
    'regenerate saves a fresh snapshot without touching the old reply',
    () async {
      final session = await newSession();
      final container = makeContainer(
        client: DeepSeekApiClient(
          origin: Uri.parse(origin),
          httpClient: MockClient.streaming(
            (request, body) async => streamOf(simpleReply('ok')),
          ),
        ),
      );
      final metadata = container.read(userMetadataProvider.notifier);
      await metadata.setLocale('zh');
      await metadata.setLocation(
        const UserLocation(region: 'CN', province: '330000', city: '330100'),
      );
      final controller = controllerFor(container, session.id);
      await controller.load();

      await controller.send(text: 'Hello', thinking: false, search: false);
      final first = controller.state.messages.last as AssistantMessage;
      final original = first.latestReminder;

      await metadata.setLocation(
        const UserLocation(region: 'CN', province: '110000', city: '110100'),
      );
      await controller.regenerate(first, thinking: false, search: false);

      final fresh = controller.state.messages.last as AssistantMessage;
      expect(fresh.id, isNot(first.id));
      expect(fresh.latestReminder, contains(',北京市,'));
      expect(fresh.latestReminder, isNot(original));
      final all = await repository.loadMessages(session.id);
      final old = all.whereType<AssistantMessage>().firstWhere(
        (message) => message.id == first.id,
      );
      expect(old.latestReminder, original);
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

  test('edit creates a sibling question and streams the new reply', () async {
    final session = await newSession();
    var call = 0;
    final bodies = <Map<String, dynamic>>[];
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          bodies.add(
            jsonDecode((request as http.Request).body) as Map<String, dynamic>,
          );
          call++;
          return streamOf(simpleReply(call == 1 ? 'first' : 'edited reply'));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();
    await controller.send(text: 'Hello', thinking: false, search: false);

    final original = controller.state.messages.first as UserMessage;
    final edited = await controller.editMessage(
      original,
      text: '  Hello edited  ',
      thinking: false,
      search: false,
    );
    expect(edited, isTrue);

    final visible = controller.state.messages;
    expect(visible, hasLength(2));
    final question = visible.first as UserMessage;
    expect(question.id, isNot(original.id));
    expect(question.text, 'Hello edited');
    expect(
      ((visible.last as AssistantMessage).blocks.single as TextBlock).text,
      'edited reply',
    );

    expect(controller.state.versions[original.id]?.ids, [
      original.id,
      question.id,
    ]);
    expect(controller.state.versions[original.id]?.index, 0);
    expect(controller.state.versions[question.id]?.index, 1);

    // ZH
    // 编辑请求只带编辑前的问题作为上下文，旧回答不进入请求。
    //
    // EN
    // The edit request carries only the pre-edit question as context; the old answer is not sent.
    final wireMessages = bodies.last['messages'] as List<dynamic>;
    expect(wireMessages.last, {'role': 'user', 'content': 'Hello edited'});
    expect(wireMessages, hasLength(2));
    expect(
      (await repository.siblings(session.id, null)).map((m) => m.id),
      [original.id, question.id],
    );
  });

  test('edit with blank text keeps the original attachments', () async {
    final session = await newSession();
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, _) async {
          return streamOf(simpleReply('ok'));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();
    final user = await repository.addUserMessage(
      sessionId: session.id,
      text: 'with file',
      attachments: [
        Attachment(
          id: 'att-1',
          name: 'photo.jpg',
          size: 10,
          isImage: true,
          localPath: 'attachments/att-1',
          serverId: 'file-1',
        ),
      ],
    );
    await controller.load();

    expect(
      await controller.editMessage(
        user,
        text: '   ',
        thinking: false,
        search: false,
      ),
      isTrue,
    );
    final question = controller.state.messages.first as UserMessage;
    expect(question.text, '');
    expect(question.attachments.single.id, 'att-1');
  });

  test('selectVersion switches the visible path without losing versions', () async {
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

    final first = controller.state.messages.last as AssistantMessage;
    await controller.regenerate(first, thinking: false, search: false);
    final second = controller.state.messages.last as AssistantMessage;
    expect(controller.state.versions[first.id]?.ids, [first.id, second.id]);

    await controller.selectVersion(first.id);

    expect(controller.state.messages.last.id, first.id);
    expect(controller.state.versions[first.id]?.index, 0);
    expect(controller.state.versions[second.id]?.index, 1);
    expect(
      (await repository.visiblePath(session.id)).last.id,
      first.id,
    );
  });

  test('switching to a leftover branch settles its pending reply', () async {
    final session = await newSession();
    final question = await repository.addUserMessage(
      sessionId: session.id,
      text: 'Hello',
    );
    final leftover = await repository.createReply(
      sessionId: session.id,
      userMessageId: question.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    final selected = await repository.createReply(
      sessionId: session.id,
      userMessageId: question.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );

    final container = makeContainer(
      client: DeepSeekApiClient(origin: Uri.parse(origin)),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();
    expect(
      (controller.state.messages.last as AssistantMessage).id,
      selected.id,
    );
    expect(
      (controller.state.messages.last as AssistantMessage).status,
      ReplyStatus.stopped,
    );

    await controller.selectVersion(leftover.id);

    final shown = controller.state.messages.last as AssistantMessage;
    expect(shown.id, leftover.id);
    expect(shown.status, ReplyStatus.stopped);
  });

  test('selectVersion ignores ids outside this conversation', () async {
    final session = await newSession();
    final container = makeContainer(
      client: DeepSeekApiClient(origin: Uri.parse(origin)),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    await controller.selectVersion('missing-message');

    expect(controller.state.messages, isEmpty);
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

  test('send with an attachment stores the original and file block', () async {
    final session = await newSession();
    final photo = pickedFile('photo.png', content: 'png');
    late http.Request captured;
    var uploads = 0;
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          if (request.url.path.endsWith('/files')) {
            uploads++;
            return jsonResponse({'id': 'file-1'});
          }
          captured = request as http.Request;
          return streamOf(simpleReply('ok'));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    await controller.send(
      text: '看看',
      thinking: false,
      search: false,
      attachments: [
        DraftAttachment(
          id: 'att-1',
          path: photo.path,
          name: 'photo.png',
          size: 3,
          isImage: true,
          mimeType: 'image/png',
        ),
      ],
    );

    expect(uploads, 1);
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final messages = body['messages'] as List<dynamic>;
    expect(messages, hasLength(2));
    expect(messages.first['role'], 'latest_reminder');
    expect(messages.last, {
      'role': 'user',
      'content': [
        {
          'type': 'image',
          'source': {'type': 'file', 'file_id': 'file-1'},
        },
        {'type': 'text', 'text': '看看'},
      ],
    });
    expect(captured.headers['anthropic-beta'], DeepSeekApiClient.filesApiBeta);

    final saved = File(p.join(support.path, 'attachments', 'att-1'));
    expect(saved.readAsStringSync(), 'png');

    final stored =
        (await repository.visiblePath(session.id)).first as UserMessage;
    expect(stored.attachments.single.serverId, 'file-1');
    expect(stored.attachments.single.localPath, 'attachments/att-1');
    expect(
      (controller.state.messages.first as UserMessage)
          .attachments
          .single
          .serverId,
      'file-1',
    );
  });

  test('upload failure marks the reply as retryable upload error', () async {
    final session = await newSession();
    final doc = pickedFile('notes.txt', content: 'hello');
    var uploadOk = false;
    var messageRequests = 0;
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          if (request.url.path.endsWith('/files')) {
            if (!uploadOk) {
              return jsonResponse({
                'error': {'message': 'server exploded'},
              }, status: 500);
            }
            return jsonResponse({'id': 'file-1'});
          }
          messageRequests++;
          return streamOf(simpleReply('ok'));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    await controller.send(
      text: '读一下',
      thinking: false,
      search: false,
      attachments: [
        DraftAttachment(
          id: 'att-1',
          path: doc.path,
          name: 'notes.txt',
          size: 5,
          isImage: false,
          mimeType: 'text/plain',
        ),
      ],
    );

    expect(messageRequests, 0);
    final failed = controller.state.messages.last as AssistantMessage;
    expect(failed.status, ReplyStatus.error);
    expect(failed.error?.kind, ApiErrorKind.upload);
    expect(failed.error?.retryable, isTrue);
    expect(failed.error?.localMessage?.key, LocalMessageKeys.uploadServerBusy);

    uploadOk = true;
    await controller.retryUpload(failed, thinking: false, search: false);

    expect(messageRequests, 1);
    final retried = controller.state.messages.last as AssistantMessage;
    expect(retried.status, ReplyStatus.done);
    expect(retried.error, isNull);
  });

  test('invalid file id is cleared, reuploaded and retried', () async {
    final session = await newSession();
    final photo = pickedFile('photo.png', content: 'png');
    var uploads = 0;
    var messageRequests = 0;
    late http.Request lastRequest;
    final container = makeContainer(
      client: DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          if (request.url.path.endsWith('/files')) {
            uploads++;
            return jsonResponse({'id': 'file-$uploads'});
          }
          messageRequests++;
          lastRequest = request as http.Request;
          if (messageRequests == 2) {
            return jsonResponse({
              'error': {'message': 'file data not found for file_id file-1'},
            }, status: 400);
          }
          return streamOf(simpleReply('ok'));
        }),
      ),
    );
    final controller = controllerFor(container, session.id);
    await controller.load();

    await controller.send(
      text: '看看',
      thinking: false,
      search: false,
      attachments: [
        DraftAttachment(
          id: 'att-1',
          path: photo.path,
          name: 'photo.png',
          size: 3,
          isImage: true,
          mimeType: 'image/png',
        ),
      ],
    );
    final first = controller.state.messages.last as AssistantMessage;
    expect(first.status, ReplyStatus.done);
    expect(uploads, 1);

    await controller.regenerate(first, thinking: false, search: false);

    expect(uploads, 2);
    expect(messageRequests, 3);
    final body = jsonDecode(lastRequest.body) as Map<String, dynamic>;
    final content =
        (body['messages'] as List<dynamic>).last['content'] as List<dynamic>;
    expect((content.first as Map<String, dynamic>)['source'], {
      'type': 'file',
      'file_id': 'file-2',
    });
    expect(
      (controller.state.messages.last as AssistantMessage).status,
      ReplyStatus.done,
    );
    final stored = await repository.visiblePath(session.id);
    expect((stored.first as UserMessage).attachments.single.serverId, 'file-2');
  });

  test(
    'history attachments without server id are backfilled silently',
    () async {
      final session = await newSession();
      final attachments = Directory(p.join(support.path, 'attachments'))
        ..createSync(recursive: true);
      File(p.join(attachments.path, 'att-old')).writeAsStringSync('old');
      final oldQuestion = await repository.addUserMessage(
        sessionId: session.id,
        text: '旧问题',
        attachments: const [
          Attachment(
            id: 'att-old',
            name: 'old.png',
            size: 3,
            isImage: true,
            mimeType: 'image/png',
            localPath: 'attachments/att-old',
          ),
        ],
      );
      final oldReply = await repository.createReply(
        sessionId: session.id,
        userMessageId: oldQuestion.id,
        model: ChatModel.deepseekFlash,
        thinking: false,
        search: false,
      );
      await repository.updateReply(
        messageId: oldReply.id,
        status: ReplyStatus.done,
        blocks: const [TextBlock(text: '旧回答')],
      );

      late http.Request captured;
      final container = makeContainer(
        client: DeepSeekApiClient(
          origin: Uri.parse(origin),
          httpClient: MockClient.streaming((request, body) async {
            if (request.url.path.endsWith('/files')) {
              return jsonResponse({'id': 'file-old'});
            }
            captured = request as http.Request;
            return streamOf(simpleReply('新回答'));
          }),
        ),
      );
      final controller = controllerFor(container, session.id);
      await controller.load();

      await controller.send(text: '新问题', thinking: false, search: false);

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(4));
      // ZH
      // 旧回复没有快照，历史轮次不插；本轮快照插在新提问之前。
      //
      // EN
      // Old reply lacks a snapshot, so no history turn; the new snapshot precedes the new question.
      expect(messages[0]['role'], 'user');
      expect(messages[2]['role'], 'latest_reminder');
      expect((messages[0]['content'] as List<dynamic>).first, {
        'type': 'image',
        'source': {'type': 'file', 'file_id': 'file-old'},
      });

      final stored = await repository.visiblePath(session.id);
      expect(
        (stored.first as UserMessage).attachments.single.serverId,
        'file-old',
      );
    },
  );
}
