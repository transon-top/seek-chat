import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/chat/messages_view.dart';
import 'package:open_chat/features/chat/speech/read_aloud_button.dart';
import 'package:open_chat/features/chat/speech/speech_controller.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

AssistantMessage _reply(
  List<ReplyBlock> blocks, {
  String id = 'reply',
  ReplyStatus status = ReplyStatus.done,
  StopReason stopReason = StopReason.endTurn,
  bool thinking = true,
  bool search = true,
}) => AssistantMessage(
  id: id,
  createdAt: DateTime(2026),
  status: status,
  blocks: blocks,
  stopReason: stopReason,
  thinking: thinking,
  search: search,
);

ServerToolUseBlock _searchUse(String id, List<String> queries) =>
    ServerToolUseBlock(
      id: id,
      name: 'deepseek_web_search',
      input: SearchInput(queries: queries),
      kind: ServerToolKind.search,
    );

ServerToolUseBlock _openUse(String id, String url) => ServerToolUseBlock(
  id: id,
  name: 'deepseek_web_search',
  input: OpenPageInput(url),
  kind: ServerToolKind.deepSearch,
);

WebSearchResult _result(String url, {String? title}) => WebSearchResult(
  title: title ?? url,
  url: url,
  snippet: '',
  encryptedContent: '',
);

void main() {
  late List<String> events;

  setUp(() => events = []);

  Future<void> pumpMessages(
    WidgetTester tester,
    List<Message> messages, {
    Map<String, MessageVersions> versions = const {},
    bool busy = false,
    SpeechView speech = (
      phase: SpeechPhase.idle,
      voiceBusy: false,
      readingMessageId: null,
    ),
    double width = 800,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ShadApp(
        theme: buildShadTheme(brightness: Brightness.light, chinese: true),
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessageList(
            messages: messages,
            versions: versions,
            busy: busy,
            speech: speech,
            onReadAloud: (reply, text) => events.add('read:${reply.id}'),
            onEdit: (message, text) async {
              events.add('edit:${message.id}:$text');
              return true;
            },
            onSelectVersion: (id) => events.add('version:$id'),
            onRegenerate: (reply) => events.add('regenerate:${reply.id}'),
            onContinue: (reply) => events.add('continue:${reply.id}'),
            onRetryUpload: (reply) => events.add('retry:${reply.id}'),
            onStop: () => events.add('stop'),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('user messages sit right in a muted bubble', (tester) async {
    await pumpMessages(tester, [
      UserMessage(id: 'u1', createdAt: DateTime(2026), text: 'Hello'),
    ]);

    final bubble = find.byKey(const Key('user-bubble-u1'));
    expect(bubble, findsOneWidget);
    final container = tester.widget<Container>(bubble);
    final colors = ShadTheme.of(tester.element(bubble)).colorScheme;
    expect((container.decoration! as BoxDecoration).color, colors.muted);
    expect(tester.getCenter(bubble).dx, greaterThan(400));
    final text = tester.widget<SelectableText>(
      find.descendant(of: bubble, matching: find.byType(SelectableText)),
    );
    expect(text.style?.fontSize, 16);
  });

  testWidgets('assistant body spans the column up to 760 wide', (tester) async {
    await pumpMessages(tester, [
      _reply(const [TextBlock(text: 'Answer')]),
    ]);

    final body = find.byKey(const Key('assistant-body-reply'));
    expect(body, findsOneWidget);
    expect(tester.getSize(body).width, 760);

    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    expect(tester.getSize(body).width, 358);
  });

  testWidgets('copy puts the answer on the clipboard', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpMessages(tester, [
      _reply(const [TextBlock(text: 'Copy me')]),
    ]);
    await tester.tap(find.byTooltip('复制'));
    await tester.pump();

    final setData = calls.firstWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    expect((setData.arguments as Map)['text'], 'Copy me');
  });

  testWidgets('a stopped reply offers continue and reports the tap', (
    tester,
  ) async {
    await pumpMessages(tester, [
      _reply(const [TextBlock(text: 'Cut off')], status: ReplyStatus.stopped),
    ]);

    expect(find.text('已停止生成'), findsOneWidget);
    await tester.tap(find.text('继续生成'));
    expect(events, ['continue:reply']);
  });

  testWidgets('a streaming reply shows inline stop and no other actions', (
    tester,
  ) async {
    await pumpMessages(tester, [
      _reply(const [TextBlock(text: 'Partial')], status: ReplyStatus.streaming),
    ], settle: false);

    expect(find.byTooltip('复制'), findsNothing);
    expect(find.byTooltip('重新生成'), findsNothing);
    await tester.tap(find.text('停止生成'));
    expect(events, ['stop']);
  });

  testWidgets('regenerate disables while the session is generating', (
    tester,
  ) async {
    await pumpMessages(tester, [
      _reply(const [TextBlock(text: 'Answer')]),
    ], busy: true);

    expect(
      tester
          .widget<ShadIconButton>(
            find.descendant(
              of: find.byKey(const Key('regenerate-reply')),
              matching: find.byType(ShadIconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    // 朗读按回复自身状态判断：已完成的回复仍可朗读（§5.3）。
    expect(
      tester.widget<ReadAloudButton>(find.byType(ReadAloudButton)).enabled,
      isTrue,
    );
  });

  testWidgets('a refused reply keeps only copy and version switching', (
    tester,
  ) async {
    await pumpMessages(
      tester,
      [
        _reply(
          const [TextBlock(text: 'hidden')],
          status: ReplyStatus.done,
          stopReason: StopReason.refusal,
        ),
      ],
      versions: {
        'reply': const MessageVersions(ids: ['reply', 'other'], index: 0),
      },
    );

    expect(find.text('你好，这个问题我暂时无法回答，让我们换个话题再聊聊吧。'), findsOneWidget);
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const Key('regenerate-reply')), findsNothing);
    expect(find.byType(ReadAloudButton), findsNothing);
    expect(find.text('查看全部'), findsNothing);
  });

  testWidgets('version switching reports the selected sibling', (tester) async {
    await pumpMessages(
      tester,
      [
        _reply(const [TextBlock(text: 'Answer')]),
      ],
      versions: {
        'reply': const MessageVersions(ids: ['first', 'reply'], index: 1),
      },
    );

    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('上一个版本'));
    expect(events, ['version:first']);
  });

  testWidgets('editing a question reports the new text', (tester) async {
    await pumpMessages(tester, [
      UserMessage(id: 'u1', createdAt: DateTime(2026), text: 'Original'),
    ]);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-input')), 'Edited');
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-send')));
    await tester.pumpAndSettle();

    expect(events, ['edit:u1:Edited']);
  });

  testWidgets('a finished thinking block folds away with its timing', (
    tester,
  ) async {
    await pumpMessages(tester, [
      _reply(const [
        ThinkingBlock(thinking: 'pondering', elapsedSeconds: 2),
        TextBlock(text: 'Answer'),
      ]),
    ]);

    expect(find.text('已思考（用时 2 秒）'), findsOneWidget);
    expect(find.byKey(const Key('thinking-body')), findsOneWidget);

    await tester.tap(find.byKey(const Key('thinking-header')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('thinking-body')), findsNothing);
    expect(find.text('Answer'), findsOneWidget);
  });

  testWidgets('tool rows show the running, failed and done states', (
    tester,
  ) async {
    await pumpMessages(tester, [
      _reply(
        [
          _searchUse('s1', ['flutter']),
        ],
        id: 'wip',
        status: ReplyStatus.streaming,
      ),
    ], settle: false);
    expect(find.text('搜索 flutter'), findsOneWidget);
    expect(find.byIcon(LucideIcons.globe), findsOneWidget);

    await pumpMessages(tester, [
      _reply([
        _searchUse('s1', ['flutter']),
      ], id: 'failed'),
    ]);
    expect(find.text('联网搜索暂不可用'), findsOneWidget);

    await pumpMessages(tester, [
      _reply([
        _searchUse('s1', ['flutter']),
        WebSearchToolResultBlock(
          toolUseId: 's1',
          kind: ServerToolKind.search,
          content: [
            _result('https://a.example', title: 'A'),
            _result('https://b.example', title: 'B'),
          ],
        ),
        const TextBlock(text: 'Answer'),
      ], id: 'done'),
    ]);
    expect(find.text('已阅读 2 个网页'), findsOneWidget);
  });

  testWidgets('the source pill opens the shared source sheet', (tester) async {
    await pumpMessages(tester, [
      _reply([
        _searchUse('s1', ['flutter']),
        WebSearchToolResultBlock(
          toolUseId: 's1',
          kind: ServerToolKind.search,
          content: [
            _result('https://a.example', title: 'Page A'),
            _result('https://b.example', title: 'Page B'),
          ],
        ),
        const TextBlock(text: 'Answer'),
      ]),
    ]);

    expect(find.text('2 个网页'), findsOneWidget);
    await tester.tap(find.byKey(const Key('source-pill')));
    await tester.pumpAndSettle();

    expect(find.text('搜索结果'), findsOneWidget);
    expect(find.byKey(const Key('source-card-1')), findsOneWidget);
    expect(find.text('Page A'), findsWidgets);
    expect(find.text('https://b.example'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('搜索结果'), findsNothing);
  });

  testWidgets('citation tokens become numbered badges', (tester) async {
    await pumpMessages(tester, [
      _reply(const [
        TextBlock(
          text: 'answer',
          citations: [
            TextCitation(
              url: 'https://cite.example',
              title: 'Cited page',
              citedText: 'quoted',
              encryptedIndex: 'enc',
            ),
          ],
        ),
      ]),
    ]);

    expect(find.byKey(const Key('citation-1')), findsOneWidget);
    expect(find.textContaining('[citation:', findRichText: true), findsNothing);
  });

  testWidgets('a pending deep-thinking reply shows its running title', (
    tester,
  ) async {
    await pumpMessages(tester, [
      AssistantMessage(
        id: 'pending',
        createdAt: DateTime(2026),
        status: ReplyStatus.pending,
        blocks: const [],
        thinking: true,
      ),
    ], settle: false);

    expect(find.text('正在思考'), findsOneWidget);
    expect(find.byKey(const Key('inline-stop')), findsNothing);
  });

  testWidgets('a browsing step reads as in progress until it finishes', (
    tester,
  ) async {
    await pumpMessages(tester, [
      _reply(
        [_openUse('o1', 'https://p.example')],
        status: ReplyStatus.streaming,
        thinking: false,
      ),
    ], settle: false);

    expect(find.text('正在浏览网页'), findsOneWidget);
    expect(find.text('https://p.example'), findsOneWidget);
  });

  testWidgets('a stopped reply without continuation still reports the stop', (
    tester,
  ) async {
    await pumpMessages(tester, [
      _reply([
        _searchUse('s1', ['flutter']),
      ], status: ReplyStatus.stopped),
    ]);

    expect(find.text('已停止生成'), findsOneWidget);
    expect(find.byKey(const Key('continue-reply')), findsNothing);
  });

  testWidgets('an upload error offers retry only when retryable', (
    tester,
  ) async {
    await pumpMessages(tester, [
      AssistantMessage(
        id: 'upload-error',
        createdAt: DateTime(2026),
        status: ReplyStatus.error,
        blocks: const [],
        error: const ReplyError(
          kind: ApiErrorKind.upload,
          message: 'busy',
          retryable: true,
        ),
      ),
    ]);

    expect(find.textContaining('发生错误，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(events, ['retry:upload-error']);
  });

  testWidgets('a refused reply hides the source pill and timeline', (
    tester,
  ) async {
    await pumpMessages(tester, [
      _reply([
        _searchUse('s1', ['flutter']),
        WebSearchToolResultBlock(
          toolUseId: 's1',
          kind: ServerToolKind.search,
          content: [_result('https://a.example', title: 'Page A')],
        ),
        const TextBlock(text: 'hidden'),
      ], stopReason: StopReason.refusal),
    ]);

    expect(find.byKey(const Key('source-pill')), findsNothing);
    expect(find.byIcon(LucideIcons.globe), findsNothing);
    expect(find.text('Page A'), findsNothing);
  });
}
