import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/app.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/data/attachment_store.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:open_chat/shared/prefs/chat_options_store.dart';
import 'package:open_chat/shared/prefs/preferences_provider.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

String searchToolStart({
  int index = 0,
  List<String> queries = const ['flutter'],
}) =>
    frame('content_block_start', {
      'type': 'content_block_start',
      'index': index,
      'content_block': {
        'type': 'server_tool_use',
        'id': 'toolu_1',
        'name': 'deepseek_web_search',
        'input': {
          'action': 'search',
          'queries': queries,
        },
        'kind': 'search',
      },
    });

String searchResultStart({
  int index = 1,
  List<Map<String, dynamic>> content = const [],
}) =>
    frame('content_block_start', {
      'type': 'content_block_start',
      'index': index,
      'content_block': {
        'type': 'web_search_tool_result',
        'tool_use_id': 'toolu_1',
        'kind': 'search',
        'content': content,
      },
    });

String blockStop(int index) =>
    frame('content_block_stop', {'type': 'content_block_stop', 'index': index});

String toolUseStart({
  required int index,
  required String id,
  required Map<String, dynamic> input,
}) =>
    frame('content_block_start', {
      'type': 'content_block_start',
      'index': index,
      'content_block': {
        'type': 'server_tool_use',
        'id': id,
        'name': 'deepseek_web_search',
        'input': input,
        'kind': 'deep_search',
      },
    });

String fetchResultStart({
  required int index,
  required String toolUseId,
  required String url,
  String? title,
}) =>
    frame('content_block_start', {
      'type': 'content_block_start',
      'index': index,
      'content_block': {
        'type': 'web_fetch_tool_result',
        'tool_use_id': toolUseId,
        'kind': 'deep_search',
        'content': {
          'type': 'web_fetch_result',
          'url': url,
          'content': {'title': ?title},
        },
      },
    });

/// 一次深度搜索浏览：6 个打开的页面与 2 个页内查找。
String pagesReplyFixture() {
  final frames = StringBuffer(messageStart);
  var index = 0;
  for (var page = 0; page < 6; page++) {
    frames.write(
      toolUseStart(
        index: index,
        id: 'open-$page',
        input: {'action': 'open_page', 'url': 'https://p$page.example'},
      ),
    );
    frames.write(blockStop(index));
    index++;
    frames.write(
      fetchResultStart(
        index: index,
        toolUseId: 'open-$page',
        url: 'https://p$page.example',
        title: 'Page $page',
      ),
    );
    frames.write(blockStop(index));
    index++;
  }
  for (final pattern in const ['alpha', 'beta']) {
    frames.write(
      toolUseStart(
        index: index,
        id: 'find-$pattern',
        input: {
          'action': 'find_in_page',
          'url': 'https://p0.example',
          'pattern': pattern,
        },
      ),
    );
    frames.write(blockStop(index));
    index++;
    frames.write(
      fetchResultStart(
        index: index,
        toolUseId: 'find-$pattern',
        url: 'https://p0.example',
        title: 'Found $pattern',
      ),
    );
    frames.write(blockStop(index));
    index++;
  }
  frames.write(textStart(index));
  frames.write(textDelta(index, 'Answer'));
  frames.write(textStop(index));
  frames.write(
    frame('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn'},
    }),
  );
  frames.write(messageStop);
  return frames.toString();
}

/// 一次普通搜索：工具调用、两个结果、带引用的正文。
final searchReplyFixture =
    messageStart +
    frame('content_block_start', {
      'type': 'content_block_start',
      'index': 0,
      'content_block': {
        'type': 'server_tool_use',
        'id': 'toolu_1',
        'name': 'deepseek_web_search',
        'input': {
          'action': 'search',
          'queries': ['flutter'],
        },
        'kind': 'search',
      },
    }) +
    frame('content_block_stop', {'type': 'content_block_stop', 'index': 0}) +
    frame('content_block_start', {
      'type': 'content_block_start',
      'index': 1,
      'content_block': {
        'type': 'web_search_tool_result',
        'tool_use_id': 'toolu_1',
        'kind': 'search',
        'content': [
          {
            'type': 'web_search_result',
            'title': 'Page One',
            'url': 'https://one.example',
            'snippet': 'First page',
            'encrypted_content': '',
            'page_age': '2026-01-02',
          },
          {
            'type': 'web_search_result',
            'title': 'Page Two',
            'url': 'https://two.example',
            'snippet': 'Second page',
            'encrypted_content': '',
          },
        ],
      },
    }) +
    frame('content_block_stop', {'type': 'content_block_stop', 'index': 1}) +
    textStart(2) +
    textDelta(2, 'See this') +
    frame('content_block_delta', {
      'type': 'content_block_delta',
      'index': 2,
      'delta': {
        'type': 'citations_delta',
        'citation': {
          'url': 'https://one.example',
          'title': 'Page One',
          'cited_text': 'quoted',
          'encrypted_index': 'enc',
        },
      },
    }) +
    textStop(2) +
    frame('message_delta', {
      'type': 'message_delta',
      'delta': {'stop_reason': 'end_turn'},
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
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
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
          sharedPreferencesProvider.overrideWithValue(prefs),
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

  testWidgets('persists chat switches and sends them with the next request', (
    tester,
  ) async {
    String? requestBody;
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming((request, _) async {
        requestBody = (request as http.Request).body;
        return sseResponse(Stream.value(utf8.encode(replyFixture)));
      }),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();

    final thinkingChip = find.widgetWithText(FilterChip, '深度思考');
    final searchChip = find.widgetWithText(FilterChip, '智能搜索');
    expect(tester.widget<FilterChip>(thinkingChip).selected, isFalse);
    expect(tester.widget<FilterChip>(searchChip).selected, isFalse);

    await tester.tap(thinkingChip);
    await tester.tap(searchChip);
    await tester.pumpAndSettle();
    expect(prefs.getBool(ChatOptionsStore.thinkingKey), isTrue);
    expect(prefs.getBool(ChatOptionsStore.searchKey), isTrue);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    final body = jsonDecode(requestBody!) as Map<String, dynamic>;
    expect(body['thinking'], {'type': 'enabled'});
    expect(
      (body['tools'] as List).map((tool) => (tool as Map)['type']),
      contains('deepseek_web_search'),
    );

    await unmountApp(tester);
    await tester.pumpWidget(appWith(apiKey: 'sk-good'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '深度思考'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '智能搜索'))
          .selected,
      isTrue,
    );

    await unmountApp(tester);
  });

  testWidgets('shows the web summary and opens one source drawer from it', (
    tester,
  ) async {
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming(
        (_, _) async =>
            sseResponse(Stream.value(utf8.encode(searchReplyFixture))),
      ),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('已阅读 2 个网页'), findsOneWidget);
    expect(find.text('2 个网页'), findsOneWidget);
    expect(
      find.textContaining('[citation:', findRichText: true),
      findsNothing,
    );

    await tester.tap(find.text('2 个网页'));
    await tester.pumpAndSettle();
    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('Page One'), findsWidgets);
    expect(find.text('Page Two'), findsWidgets);
    expect(find.text('2026/01/02'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('搜索结果'), findsNothing);

    await tester.tap(find.text('已阅读 2 个网页'));
    await tester.pumpAndSettle();
    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('Page Two'), findsWidgets);

    await unmountApp(tester);
  });

  testWidgets('shows a stopped search instead of a failure', (tester) async {
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

    body.add(utf8.encode(messageStart + searchToolStart()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    await tester.tap(find.byTooltip('停止'));
    await body.close();
    await tester.pumpAndSettle();

    expect(find.text('搜索已停止'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('reports an empty search result', (tester) async {
    final fixture =
        messageStart +
        searchToolStart() +
        blockStop(0) +
        searchResultStart() +
        blockStop(1) +
        textStart(2) +
        textDelta(2, 'No hits') +
        textStop(2) +
        frame('message_delta', {
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn'},
        }) +
        messageStop;
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming(
        (_, _) async => sseResponse(Stream.value(utf8.encode(fixture))),
      ),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('未搜索到相关内容'), findsOneWidget);
    expect(find.textContaining('No hits', findRichText: true), findsWidgets);
    expect(find.textContaining('个网页'), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('shows five pages, view-all and find chips for deep search', (
    tester,
  ) async {
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming(
        (_, _) async =>
            sseResponse(Stream.value(utf8.encode(pagesReplyFixture()))),
      ),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('浏览 6 个页面'), findsOneWidget);
    expect(find.text('Page 0'), findsOneWidget);
    expect(find.text('Page 4'), findsOneWidget);
    expect(find.text('Page 5'), findsNothing);
    expect(find.text('查看全部'), findsOneWidget);
    expect(find.text('查找关键词'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text('搜索结果'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('a refused reply hides the timeline, body and summary', (
    tester,
  ) async {
    final fixture =
        messageStart +
        searchToolStart() +
        blockStop(0) +
        searchResultStart(
          content: [
            {
              'type': 'web_search_result',
              'title': 'Page Refused',
              'url': 'https://refused.example',
              'snippet': '',
              'encrypted_content': '',
            },
          ],
        ) +
        blockStop(1) +
        textStart(2) +
        textDelta(2, 'must not appear') +
        textStop(2) +
        frame('message_delta', {
          'type': 'message_delta',
          'delta': {'stop_reason': 'refusal'},
        }) +
        messageStop;
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming(
        (_, _) async => sseResponse(Stream.value(utf8.encode(fixture))),
      ),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('内容被安全策略拒绝'), findsOneWidget);
    expect(
      find.textContaining('must not appear', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('Page Refused', findRichText: true),
      findsNothing,
    );
    expect(find.textContaining('个网页'), findsNothing);

    await unmountApp(tester);
  });
}
