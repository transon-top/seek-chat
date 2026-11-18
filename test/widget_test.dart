import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/api/client.dart';
import 'package:open_chat/app.dart';
import 'package:open_chat/data/attachment_store.dart';
import 'package:open_chat/data/chat_repository.dart';
import 'package:open_chat/data/database.dart';

import 'support/fake_api_key_store.dart';

const origin = 'https://api.test';

String frame(String event, Map<String, dynamic> payload) =>
    'event: $event\ndata: ${jsonEncode(payload)}\n\n';

final replyFixture = frame('message_start', {
  'type': 'message_start',
  'message': {'id': 'm1', 'model': 'deepseek-flash'},
}) +
    frame('content_block_start', {
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    }) +
    frame('content_block_delta', {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': 'Hi there'},
    }) +
    frame('content_block_stop', {'type': 'content_block_stop', 'index': 0}) +
    frame('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn', 'title': 'Greeting'},
    }) +
    frame('message_stop', {'type': 'message_stop'});

void main() {
  late AppDatabase db;
  late ChatRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db);
  });

  tearDown(() => db.close());

  Widget appWith({required String? apiKey}) => OpenChatApp(
        repository: repository,
        client: DeepSeekApiClient(
          origin: Uri.parse(origin),
          httpClient: MockClient.streaming(
            (request, _) async => http.StreamedResponse(
              Stream.value(utf8.encode(replyFixture)),
              200,
              headers: {'content-type': 'text/event-stream'},
            ),
          ),
        ),
        apiKeyStore: FakeApiKeyStore(apiKey),
        attachmentStore: AttachmentStore(),
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

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Greeting'), findsOneWidget);
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
  });
}
