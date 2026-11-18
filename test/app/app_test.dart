import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/app.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/data/attachment_store.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:open_chat/shared/providers.dart';

import '../support/fake_api_key_store.dart';
import '../support/sse_fixtures.dart';

const origin = 'https://api.test';

final replyFixture =
    messageStart +
    textStart(0) +
    textDelta(0, 'Hi there') +
    textStop(0) +
    frame('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn', 'title': 'Greeting'},
    }) +
    messageStop;

Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ChatRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db);
    // 现有界面文案仍为中文（票 18 再全量本地化），固定 locale 后错误文案也走中文。
    binding.platformDispatcher.localesTestValue = const [Locale('zh')];
  });

  tearDown(() {
    db.close();
    binding.platformDispatcher.clearLocalesTestValue();
  });

  Widget appWith({required String? apiKey, DeepSeekApiClient? client}) =>
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          chatRepositoryProvider.overrideWithValue(repository),
          apiClientProvider.overrideWithValue(
            client ??
                DeepSeekApiClient(
                  origin: Uri.parse(origin),
                  httpClient: MockClient.streaming(
                    (request, _) async =>
                        sseResponse(Stream.value(utf8.encode(replyFixture))),
                  ),
                ),
          ),
          apiKeyStoreProvider.overrideWithValue(FakeApiKeyStore(apiKey)),
          attachmentStoreProvider.overrideWithValue(AttachmentStore()),
        ],
        child: const OpenChatApp(),
      );

  testWidgets('creates a session and streams a reply into it', (tester) async {
    await tester.pumpWidget(appWith(apiKey: 'sk-good'));
    await tester.pumpAndSettle();
    expect(find.text('Open Chat'), findsOneWidget);

    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    expect(find.text('新对话'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Hi there'), findsOneWidget);
    expect(find.text('Greeting'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Greeting'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('tells the user to set a key when none is saved', (tester) async {
    await tester.pumpWidget(appWith(apiKey: null));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未设置 API Key'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('keeps streaming after leaving the chat page', (tester) async {
    final body = StreamController<List<int>>();
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming((_, _) async => sseResponse(body.stream)),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump();

    body.add(utf8.encode(messageStart + textStart(0) + textDelta(0, 'partial')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open Chat'), findsOneWidget);

    body.add(utf8.encode(messageStop));
    await body.close();
    await tester.pumpAndSettle();

    final session = (await repository.listSessions()).single;
    final stored = (await repository.visiblePath(session.id)).last
        as AssistantMessage;
    expect(stored.status, ReplyStatus.done);
    expect(
      stored.blocks.whereType<TextBlock>().map((block) => block.text).join(),
      'partial',
    );

    await unmountApp(tester);
  });

  testWidgets('flushes the in-flight reply when the app is paused', (
    tester,
  ) async {
    final body = StreamController<List<int>>();
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming(
        (_, _) async => sseResponse(body.stream),
      ),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump();

    body.add(
      utf8.encode(messageStart + textStart(0) + textDelta(0, 'partial')),
    );
    await tester.pump();
    await tester.pump();

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();

    final session = (await repository.listSessions()).single;
    final stored =
        (await repository.visiblePath(session.id)).last as AssistantMessage;
    expect(stored.status, ReplyStatus.streaming);
    expect(
      stored.blocks.whereType<TextBlock>().map((block) => block.text).join(),
      'partial',
    );

    body.add(utf8.encode(messageStop));
    await body.close();
    await tester.pumpAndSettle();
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }

    await unmountApp(tester);
  });
}
