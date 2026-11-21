import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:open_chat/app/app.dart';
import 'package:open_chat/features/chat/chat_page.dart';
import 'package:open_chat/features/chat/composer.dart';
import 'package:open_chat/features/chat/speech/player.dart';
import 'package:open_chat/features/chat/speech/read_aloud_button.dart';
import 'package:open_chat/features/chat/speech/speech_api.dart';
import 'package:open_chat/features/chat/speech/speech_controller.dart';
import 'package:open_chat/features/sessions/session_drawer.dart';
import 'package:open_chat/features/settings/settings_page.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/data/attachment_store.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:open_chat/shared/prefs/chat_options_store.dart';
import 'package:open_chat/shared/prefs/font_scale_store.dart';
import 'package:open_chat/shared/prefs/preferences_provider.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/chat/speech/speech_fakes.dart';
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
}) => frame('content_block_start', {
  'type': 'content_block_start',
  'index': index,
  'content_block': {
    'type': 'server_tool_use',
    'id': 'toolu_1',
    'name': 'deepseek_web_search',
    'input': {'action': 'search', 'queries': queries},
    'kind': 'search',
  },
});

String searchResultStart({
  int index = 1,
  List<Map<String, dynamic>> content = const [],
}) => frame('content_block_start', {
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
}) => frame('content_block_start', {
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
}) => frame('content_block_start', {
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

Future<void> openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('chat-open-drawer')));
  await tester.pumpAndSettle();
}

/// 抽屉打开后点右侧对话区收起；遮罩层中心被内容层推出屏幕，只能按坐标点。
Future<void> closeDrawer(WidgetTester tester) async {
  await tester.tapAt(const Offset(760, 300));
  await tester.pumpAndSettle();
}

Future<void> openSettings(WidgetTester tester) async {
  await openDrawer(tester);
  await tester.tap(find.byKey(const Key('drawer-settings')));
  await tester.pumpAndSettle();
}

Future<void> startNewChat(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('chat-new')));
  await tester.pumpAndSettle();
}

/// 首条消息落库可被卡住的仓储，覆盖“新会话已创建、历史列表还没它”的窗口。
class _GatedRepository extends ChatRepository {
  _GatedRepository(super.db);

  final gate = Completer<void>();

  @override
  Future<UserMessage> addUserMessage({
    required String sessionId,
    required String text,
    List<Attachment> attachments = const [],
  }) async {
    await gate.future;
    return super.addUserMessage(
      sessionId: sessionId,
      text: text,
      attachments: attachments,
    );
  }
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

  Widget appWith({
    required String? apiKey,
    DeepSeekApiClient? client,
    SpeechApi? speechApi,
    SpeechPlayer? speechPlayer,
    ChatRepository? chatRepository,
  }) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      chatRepositoryProvider.overrideWithValue(chatRepository ?? repository),
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
      if (speechApi != null) speechApiProvider.overrideWithValue(speechApi),
      if (speechPlayer != null)
        speechPlayerProvider.overrideWithValue(speechPlayer),
    ],
    child: const OpenChatApp(),
  );

  testWidgets('creates a session and streams a reply into it', (tester) async {
    await tester.pumpWidget(appWith(apiKey: 'sk-good'));
    await tester.pumpAndSettle();
    // 首屏不展示标题与新建按钮，进入对话后才有。
    expect(find.text('新对话'), findsNothing);
    expect(find.byKey(const Key('chat-new')), findsNothing);

    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Hi there'), findsOneWidget);
    expect(find.text('Greeting'), findsOneWidget);

    await openDrawer(tester);
    expect(
      find.descendant(
        of: find.byType(SessionDrawer),
        matching: find.text('Greeting'),
      ),
      findsOneWidget,
    );

    await unmountApp(tester);
  });

  testWidgets('attachment panel opens, closes with input tap and back', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(apiKey: 'sk-good'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('attach-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel-take-photo')), findsOneWidget);
    expect(find.byKey(const Key('panel-photos')), findsOneWidget);
    expect(find.byKey(const Key('panel-files')), findsOneWidget);

    // 点输入框收起面板。
    await tester.tap(find.byKey(const Key('composer-input')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel-take-photo')), findsNothing);

    // 再次展开后用系统返回收起面板，页面不退出。
    await tester.tap(find.byKey(const Key('attach-button')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel-take-photo')), findsNothing);
    expect(find.byKey(const Key('composer-input')), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('swiping right on the chat opens the session drawer', (
    tester,
  ) async {
    final session = await repository.createSession();
    await repository.renameSession(session.id, 'Swipe target');
    await repository.addUserMessage(sessionId: session.id, text: 'hello');

    await tester.pumpWidget(appWith(apiKey: 'sk-good'));
    await tester.pumpAndSettle();

    await tester.drag(find.text('hello'), const Offset(400, 0));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SessionDrawer),
        matching: find.text('Swipe target'),
      ),
      findsOneWidget,
    );

    await unmountApp(tester);
  });

  testWidgets('a new chat stays selected until its first message lands', (
    tester,
  ) async {
    final old = await repository.createSession();
    await repository.renameSession(old.id, 'Old');
    await repository.addUserMessage(sessionId: old.id, text: 'old question');

    final gated = _GatedRepository(db);
    await tester.pumpWidget(appWith(apiKey: 'sk-good', chatRepository: gated));
    await tester.pumpAndSettle();
    expect(find.text('Old'), findsOneWidget);

    await startNewChat(tester);
    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump();

    // 消息尚未落库：列表里还没有新会话，页面不能跳回旧会话。
    expect(find.text('嗨! 今天想聊些什么?'), findsOneWidget);
    expect(find.text('Old'), findsNothing);

    gated.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Hi there'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('renders the chat UI in English', (tester) async {
    await prefs.setString('user.locale', 'en');
    await tester.pumpWidget(appWith(apiKey: null));
    await tester.pumpAndSettle();

    expect(find.text('New chat'), findsNothing);
    expect(find.text('How can I help you?'), findsOneWidget);
    expect(find.text('DeepThink'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);

    await openDrawer(tester);
    expect(find.text('No chats yet'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('applies the saved theme mode on the first frame', (
    tester,
  ) async {
    await prefs.setString('ui.themeMode', 'dark');
    await tester.pumpWidget(appWith(apiKey: null));
    // 中文 Material 委托异步加载；首帧内容出现时主题必须已是深色。
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold));
    expect(Theme.of(context).brightness, Brightness.dark);

    await tester.pumpAndSettle();
    await unmountApp(tester);
  });

  testWidgets('applies a theme change immediately', (tester) async {
    await tester.pumpWidget(appWith(apiKey: null));
    await tester.pumpAndSettle();

    await openSettings(tester);
    await tester.tap(find.byKey(const Key('settings-theme-dark')));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('设置'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(prefs.getString('ui.themeMode'), 'dark');

    await unmountApp(tester);
  });

  testWidgets('applies a language change immediately', (tester) async {
    await tester.pumpWidget(appWith(apiKey: null));
    await tester.pumpAndSettle();

    await openSettings(tester);
    final language = find.byKey(const Key('settings-language'));
    await tester.ensureVisible(language);
    await tester.pumpAndSettle();
    await tester.tap(language);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-close')));
    await tester.pumpAndSettle();
    expect(find.text('How can I help you?'), findsOneWidget);
    expect(prefs.getString('user.locale'), 'en');

    await unmountApp(tester);
  });

  testWidgets('renders the chat UI in English dark mode', (tester) async {
    await prefs.setString('user.locale', 'en');
    await prefs.setString('ui.themeMode', 'dark');
    await tester.pumpWidget(appWith(apiKey: null));
    await tester.pumpAndSettle();

    expect(find.text('How can I help you?'), findsOneWidget);
    final context = tester.element(find.text('How can I help you?'));
    expect(Theme.of(context).brightness, Brightness.dark);

    await unmountApp(tester);
  });

  testWidgets('tells the user to set a key when none is saved', (tester) async {
    await tester.pumpWidget(appWith(apiKey: null));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未设置 API Key'), findsOneWidget);
    // 发送失败时保留输入内容，与 chat-demo 一致。
    expect(find.text('Hello'), findsOneWidget);
    // 首条消息未发出，不留下空会话。
    expect(await repository.listSessions(), isEmpty);

    await unmountApp(tester);
  });

  testWidgets('keeps streaming after leaving the chat page', (tester) async {
    final body = StreamController<List<int>>();
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming(
        (_, _) async => sseResponse(body.stream),
      ),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump();

    body.add(
      utf8.encode(messageStart + textStart(0) + textDelta(0, 'partial')),
    );
    await tester.pump();
    await tester.pump();

    // 流式中的进度指示器持续动画，不能用 pumpAndSettle。
    await tester.tap(find.byKey(const Key('chat-open-drawer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(760, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('chat-new')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('嗨! 今天想聊些什么?'), findsOneWidget);

    body.add(utf8.encode(messageStop));
    await body.close();
    await tester.pumpAndSettle();

    final session = (await repository.listSessions()).single;
    final stored =
        (await repository.visiblePath(session.id)).last as AssistantMessage;
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

    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
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

    final thinkingChip = find.byKey(const Key('thinking-toggle'));
    final searchChip = find.byKey(const Key('search-toggle'));
    expect(tester.widget<ComposerToggle>(thinkingChip).selected, isFalse);
    expect(tester.widget<ComposerToggle>(searchChip).selected, isFalse);

    await tester.tap(thinkingChip);
    await tester.tap(searchChip);
    await tester.pumpAndSettle();
    expect(prefs.getBool(ChatOptionsStore.thinkingKey), isTrue);
    expect(prefs.getBool(ChatOptionsStore.searchKey), isTrue);

    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
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

    expect(
      tester
          .widget<ComposerToggle>(find.byKey(const Key('thinking-toggle')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ComposerToggle>(find.byKey(const Key('search-toggle')))
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
    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('已阅读 2 个网页'), findsOneWidget);
    expect(find.text('2 个网页'), findsOneWidget);
    expect(find.textContaining('[citation:', findRichText: true), findsNothing);

    await tester.tap(find.text('2 个网页'));
    await tester.pumpAndSettle();
    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.text('Page One'), findsWidgets);
    expect(find.text('Page Two'), findsWidgets);
    expect(find.textContaining('2026/01/02'), findsOneWidget);

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
    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await tester.pump();

    body.add(utf8.encode(messageStart + searchToolStart()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    await tester.tap(find.byTooltip('停止生成'));
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
    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
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
    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
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
    expect(find.byIcon(LucideIcons.check), findsNWidgets(2));

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
    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('你好，这个问题我暂时无法回答，让我们换个话题再聊聊吧。', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('must not appear', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('Page Refused', findRichText: true),
      findsNothing,
    );
    expect(find.textContaining('个网页'), findsNothing);
    expect(find.byIcon(LucideIcons.refreshCw), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('a blocked image shows the image review copy', (tester) async {
    const explanation =
        'The following images were blocked by content moderation: '
        'messages.1.content.0';
    final fixture =
        messageStart +
        textStart(0) +
        textDelta(0, 'must not appear') +
        textStop(0) +
        frame('message_delta', {
          'type': 'message_delta',
          'delta': {
            'stop_reason': 'refusal',
            'stop_details': {
              'type': 'refusal',
              'category': null,
              'explanation': explanation,
            },
          },
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
    await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('图片未通过内容安全审核，请移除后重试。', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('must not appear', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('messages.1.content.0', findRichText: true),
      findsNothing,
    );

    await unmountApp(tester);
  });

  testWidgets(
    'a content-review 400 shows localized copy without the raw error',
    (tester) async {
      final client = DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream.value(
              utf8.encode(
                '{"type":"error","error":{"type":"invalid_request_error",'
                '"message":"Content Exists Risk"}}',
              ),
            ),
            400,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('composer-input')), 'Hello');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();

      expect(find.textContaining('内容未通过安全审核'), findsOneWidget);
      expect(find.textContaining('Content Exists Risk'), findsNothing);

      await unmountApp(tester);
    },
  );

  testWidgets('reopens the selected branch and switches versions', (
    tester,
  ) async {
    final session = await repository.createSession();
    final question = await repository.addUserMessage(
      sessionId: session.id,
      text: 'Hello',
    );
    final first = await repository.createReply(
      sessionId: session.id,
      userMessageId: question.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    await repository.updateReply(
      messageId: first.id,
      status: ReplyStatus.done,
      blocks: const [TextBlock(text: 'first answer')],
    );
    final second = await repository.createReply(
      sessionId: session.id,
      userMessageId: question.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    await repository.updateReply(
      messageId: second.id,
      status: ReplyStatus.done,
      blocks: const [TextBlock(text: 'second answer')],
    );

    await tester.pumpWidget(appWith(apiKey: 'sk-good'));
    await tester.pumpAndSettle();

    // 打开会话只显示选中分支，不把旧版本拼进消息流。
    expect(find.text('second answer'), findsOneWidget);
    expect(find.text('first answer'), findsNothing);
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('上一个版本'));
    await tester.pumpAndSettle();

    expect(find.text('first answer'), findsOneWidget);
    expect(find.text('second answer'), findsNothing);
    expect(find.text('1 / 2'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('editing a question creates a sibling version', (tester) async {
    final session = await repository.createSession();
    final question = await repository.addUserMessage(
      sessionId: session.id,
      text: 'Original',
    );
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: question.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: const [TextBlock(text: 'first answer')],
    );

    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming(
        (_, _) async => sseResponse(
          Stream.value(
            utf8.encode(
              messageStart +
                  textStart(0) +
                  textDelta(0, 'edited answer') +
                  textStop(0) +
                  frame('message_delta', {
                    'type': 'message_delta',
                    'delta': {'stop_reason': 'end_turn'},
                  }) +
                  messageStop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-input')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('edit-input')), 'Edited');
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-send')));
    await tester.pumpAndSettle();

    expect(find.text('Edited'), findsOneWidget);
    expect(find.text('Original'), findsNothing);
    expect(find.text('edited answer'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(await repository.siblings(session.id, null), hasLength(2));

    await unmountApp(tester);
  });

  testWidgets('disables version switching while the edited reply streams', (
    tester,
  ) async {
    final session = await repository.createSession();
    final question = await repository.addUserMessage(
      sessionId: session.id,
      text: 'Original',
    );
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: question.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: const [TextBlock(text: 'first answer')],
    );

    final body = StreamController<List<int>>();
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming(
        (_, _) async => sseResponse(body.stream),
      ),
    );
    await tester.pumpWidget(appWith(apiKey: 'sk-good', client: client));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-input')), 'Edited');
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-send')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 流式期间新提问已有两个版本；切换器必须禁用而不是空指针。
    expect(tester.takeException(), isNull);
    expect(find.text('Edited'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    final previous = tester.widget<ShadIconButton>(
      find.descendant(
        of: find.byKey(const Key('previous-version')),
        matching: find.byType(ShadIconButton),
      ),
    );
    expect(previous.onPressed, isNull);

    body.add(
      utf8.encode(
        messageStart +
            textStart(0) +
            textDelta(0, 'edited answer') +
            textStop(0) +
            frame('message_delta', {
              'type': 'message_delta',
              'delta': {'stop_reason': 'end_turn'},
            }) +
            messageStop,
      ),
    );
    await body.close();
    await tester.pumpAndSettle();

    expect(find.text('edited answer'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('roots on the latest chat and manages sessions from the drawer', (
    tester,
  ) async {
    final first = await repository.createSession();
    await repository.renameSession(first.id, 'First');
    await repository.addUserMessage(sessionId: first.id, text: 'a');
    // 列表按 updatedAt 排序；同一毫秒创建的两个会话顺序不稳定。
    // testWidgets 的假时钟不会推进真实 Timer，必须走 runAsync。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    final second = await repository.createSession();
    await repository.renameSession(second.id, 'Second');
    await repository.addUserMessage(sessionId: second.id, text: 'b');

    await tester.pumpWidget(appWith(apiKey: 'sk-good'));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);

    await openDrawer(tester);
    final currentRow = find.byKey(ValueKey('session-row-${second.id}'));
    final currentTitle = tester.widget<Text>(
      find.descendant(of: currentRow, matching: find.text('Second')),
    );
    expect(
      currentTitle.style?.color,
      Theme.of(tester.element(currentRow)).colorScheme.primary,
    );

    await tester.tap(find.byKey(ValueKey('session-row-${first.id}')));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    await openDrawer(tester);
    await tester.longPress(find.byKey(ValueKey('session-row-${first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('session-menu-rename-${first.id}')),
    );
    // 行内输入框自动聚焦后光标定时闪烁，pumpAndSettle 永不结束。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(ValueKey('session-rename-${first.id}')),
      'Renamed',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.descendant(
        of: find.byType(SessionDrawer),
        matching: find.text('Renamed'),
      ),
      findsOneWidget,
    );

    await tester.longPress(find.byKey(ValueKey('session-row-${first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('session-menu-delete-${first.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.text('Renamed'), findsNothing);
    expect(await repository.listSessions(), hasLength(1));

    await closeDrawer(tester);
    expect(find.text('Second'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-new')), findsNothing);
    expect(find.text('嗨! 今天想聊些什么?'), findsOneWidget);
    expect(
      tester
          .widget<ShadInput>(find.byKey(const Key('composer-input')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );

    await unmountApp(tester);
  });

  testWidgets('session data changes do not rebuild the page while the '
      'current session is stable', (tester) async {
    final first = await repository.createSession();
    await repository.renameSession(first.id, 'First');
    await repository.addUserMessage(sessionId: first.id, text: 'a');

    await tester.pumpWidget(appWith(apiKey: 'sk-good'));
    await tester.pumpAndSettle();
    final before = tester.widget<ChatPage>(find.byType(ChatPage));
    expect(before.sessionId, first.id);

    // 标题变化只更新列表数据，当前会话不变：页面 widget 实例保持不变。
    await repository.renameSession(first.id, 'Renamed');
    await tester.pumpAndSettle();
    expect(
      identical(tester.widget<ChatPage>(find.byType(ChatPage)), before),
      isTrue,
    );

    // 当前会话被删除：当前 id 变化，页面重建并回到空对话。
    await repository.deleteSession(first.id);
    await tester.pumpAndSettle();
    final after = tester.widget<ChatPage>(find.byType(ChatPage));
    expect(identical(after, before), isFalse);
    expect(after.sessionId, isNull);

    await unmountApp(tester);
  });

  testWidgets('switching sessions stops read-aloud', (tester) async {
    final first = await repository.createSession();
    await repository.renameSession(first.id, 'First');
    final question = await repository.addUserMessage(
      sessionId: first.id,
      text: 'Hello',
    );
    final reply = await repository.createReply(
      sessionId: first.id,
      userMessageId: question.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: const [TextBlock(text: 'first answer')],
    );
    final second = await repository.createSession();
    await repository.renameSession(second.id, 'Second');
    await repository.addUserMessage(sessionId: second.id, text: 'Hi');

    final api = FakeSpeechApi();
    final player = FakePlayer();
    await tester.pumpWidget(
      appWith(apiKey: 'sk-good', speechApi: api, speechPlayer: player),
    );
    await tester.pumpAndSettle();
    await openDrawer(tester);
    await tester.tap(find.byKey(ValueKey('session-row-${first.id}')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('朗读'));
    await tester.pump();
    await tester.pump();
    api.ttsController!.add(Uint8List.fromList([1, 2, 3, 4]));
    await tester.pump();
    expect(player.sessions, hasLength(1));
    expect(find.byTooltip('停止朗读'), findsOneWidget);

    // 朗读动画持续刷新，不能用 pumpAndSettle。
    await tester.tap(find.byKey(const Key('chat-open-drawer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(ValueKey('session-row-${second.id}')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(player.sessions.single.stopped, isTrue);
    expect(find.byTooltip('停止朗读'), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('switching versions stops read-aloud', (tester) async {
    final session = await repository.createSession();
    final question = await repository.addUserMessage(
      sessionId: session.id,
      text: 'Hello',
    );
    final first = await repository.createReply(
      sessionId: session.id,
      userMessageId: question.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    await repository.updateReply(
      messageId: first.id,
      status: ReplyStatus.done,
      blocks: const [TextBlock(text: 'first answer')],
    );
    final second = await repository.createReply(
      sessionId: session.id,
      userMessageId: question.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    await repository.updateReply(
      messageId: second.id,
      status: ReplyStatus.done,
      blocks: const [TextBlock(text: 'second answer')],
    );

    final api = FakeSpeechApi();
    final player = FakePlayer();
    await tester.pumpWidget(
      appWith(apiKey: 'sk-good', speechApi: api, speechPlayer: player),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('朗读'));
    await tester.pump();
    await tester.pump();
    expect(api.ttsCalls, hasLength(1));
    api.ttsController!.add(Uint8List.fromList([1, 2, 3, 4]));
    await tester.pump();
    expect(player.sessions, hasLength(1));
    expect(find.byTooltip('停止朗读'), findsOneWidget);

    await tester.tap(find.byTooltip('上一个版本'));
    await tester.pump();
    // 停止朗读要等流取消在真实事件循环上完成。
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('first answer'), findsOneWidget);
    final button = tester.widget<ReadAloudButton>(find.byType(ReadAloudButton));
    expect(button.phase, SpeechPhase.idle);
    expect(player.sessions.single.stopped, isTrue);
    expect(find.byTooltip('朗读'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('font size setting scales the whole app immediately', (
    tester,
  ) async {
    await tester.pumpWidget(appWith(apiKey: null));
    await tester.pumpAndSettle();
    await openSettings(tester);

    final tick = find.byKey(const Key('settings-font-tick-6'));
    await tester.ensureVisible(tick);
    await tester.pumpAndSettle();
    await tester.tap(tick);
    await tester.pumpAndSettle();

    expect(prefs.getBool(FontScaleStore.followKey), isFalse);
    expect(prefs.getInt(FontScaleStore.levelKey), 6);
    final sheet = tester.element(find.byType(SettingsSheet));
    expect(MediaQuery.textScalerOf(sheet).scale(16), 21.6);

    await tester.tap(find.byKey(const Key('settings-close')));
    await tester.pumpAndSettle();
    await unmountApp(tester);
  });
}
