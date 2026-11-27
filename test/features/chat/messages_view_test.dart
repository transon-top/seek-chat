import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:seek_chat/app/localization.dart';
import 'package:seek_chat/app/theme.dart';
import 'package:seek_chat/features/chat/messages_view.dart';
import 'package:seek_chat/features/chat/speech/read_aloud_button.dart';
import 'package:seek_chat/features/chat/speech/speech_controller.dart';
import 'package:seek_chat/l10n/generated/app_localizations.dart';
import 'package:seek_chat/shared/models/types.dart';
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

/// ZH
/// 消息列表自身的滚动视图（文本控件内部也有 Scrollable，取最外层）。
///
/// EN
/// The message list's scroll view (text widgets have Scrollables too; take the outermost).
final Finder _listScrollable = find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

/// ZH
/// 消息列表当前渲染窗口的条数。
///
/// EN
/// Number of items in the message list's currently rendered window.
int? _renderedCount(WidgetTester tester) =>
    (tester.widget<ListView>(find.byType(ListView)).childrenDelegate
            as SliverChildBuilderDelegate)
        .childCount;

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
    Key? key,
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
            key: key,
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
    final colors = Theme.of(tester.element(bubble)).colorScheme;
    expect(
      (container.decoration! as BoxDecoration).color,
      colors.surfaceContainer,
    );
    expect(tester.getCenter(bubble).dx, greaterThan(400));
    final text = tester.widget<Text>(
      find.descendant(of: bubble, matching: find.byType(Text)),
    );
    expect(text.style?.fontSize, 16);
  });

  testWidgets('short chats start at the top and long chats follow the bottom', (
    tester,
  ) async {
    await pumpMessages(tester, [
      UserMessage(id: 'u1', createdAt: DateTime(2026), text: 'Hello'),
      _reply(const [TextBlock(text: 'Hi')]),
    ]);

    // ZH
    // 内容不足一屏：提问从视口顶部开始。
    //
    // EN
    // Content fits one screen: the question starts at the top of the viewport.
    expect(
      tester.getTopLeft(find.byKey(const Key('user-bubble-u1'))).dy,
      lessThan(50),
    );

    final many = <Message>[
      for (var i = 0; i < 30; i++) ...[
        UserMessage(
          id: 'u${i + 1}',
          createdAt: DateTime(2026),
          text: 'Question $i',
        ),
        _reply(const [
          TextBlock(
            text: 'Answer\n\nAnswer\n\nAnswer\n\nAnswer\n\nAnswer\n\nAnswer',
          ),
        ], id: 'r$i'),
      ],
    ];
    await pumpMessages(tester, many);

    // ZH
    // 内容超过一屏：跟随底部，最新回复留在视口下沿。
    //
    // EN
    // Content exceeds one screen: follow the bottom; the latest reply stays at the viewport edge.
    final last = find.byKey(const Key('assistant-body-r29'));
    expect(last, findsOneWidget);
    expect(tester.getBottomLeft(last).dy, greaterThan(800));
  });

  testWidgets(
    'scrolling up pauses follow while streaming and returning to bottom resumes',
    (tester) async {
      String tail(int repeats) => List.filled(repeats, '段落内容').join('\n\n');
      List<Message> conversation(String text) => [
        for (var i = 0; i < 24; i++) ...[
          UserMessage(
            id: 'u$i',
            createdAt: DateTime(2026),
            text: 'Question $i',
          ),
          _reply(
            [
              TextBlock(
                text: i == 23 ? text : 'Answer\n\nAnswer\n\nAnswer\n\nAnswer',
              ),
            ],
            id: 'r$i',
            status: i == 23 ? ReplyStatus.streaming : ReplyStatus.done,
            thinking: false,
          ),
        ],
      ];

      await pumpMessages(
        tester,
        conversation(tail(20)),
        width: 390,
        settle: false,
      );
      final position = tester.state<ScrollableState>(_listScrollable).position;
      expect(position.maxScrollExtent, greaterThan(600));

      // ZH
      // 上滑离开底部：出现悬浮按钮，内容继续增长时视口保持原位。
      //
      // EN
      // Swipe up off the bottom: the floating button appears; the viewport holds as content grows.
      position.jumpTo(position.maxScrollExtent - 600);
      await tester.pump();
      await tester.pump();
      final held = position.pixels;
      expect(find.byKey(const Key('scroll-to-bottom')), findsOneWidget);

      await pumpMessages(
        tester,
        conversation(tail(40)),
        width: 390,
        settle: false,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(position.pixels, moreOrLessEquals(held, epsilon: 1));

      // ZH
      // 点悬浮按钮回到底部，随后恢复跟随。
      //
      // EN
      // Tap the floating button to return to the bottom, then follow resumes.
      await tester.tap(find.byKey(const Key('scroll-to-bottom')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        position.pixels,
        moreOrLessEquals(position.maxScrollExtent, epsilon: 1),
      );
      expect(find.byKey(const Key('scroll-to-bottom')), findsNothing);

      await pumpMessages(
        tester,
        conversation(tail(80)),
        width: 390,
        settle: false,
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        position.pixels,
        moreOrLessEquals(position.maxScrollExtent, epsilon: 1),
      );
    },
  );

  testWidgets('long conversations render only the tail window first', (
    tester,
  ) async {
    final messages = [
      for (var i = 0; i < 200; i++)
        UserMessage(id: 'u$i', createdAt: DateTime(2026), text: 'Q$i'),
    ];
    await pumpMessages(tester, messages);

    expect(_renderedCount(tester), 50);
    expect(find.byKey(const ValueKey('user-bubble-u199')), findsOneWidget);
  });

  testWidgets(
    'scrolling to the top loads older messages without moving the anchor',
    (tester) async {
      final messages = [
        for (var i = 0; i < 200; i++)
          UserMessage(id: 'u$i', createdAt: DateTime(2026), text: 'Q$i'),
      ];
      await pumpMessages(tester, messages);
      final position = tester.state<ScrollableState>(_listScrollable).position;

      // ZH
      // 先停在触发线外，记下一条已渲染消息的屏幕位置。
      //
      // EN
      // Stop outside the trigger line and record the screen position of a rendered message.
      position.jumpTo(230);
      await tester.pump();
      final anchor = find.byKey(const ValueKey('user-bubble-u152'));
      final before = tester.getTopLeft(anchor).dy;

      // ZH
      // 再向顶部走 31px：触发补历史，整块内容只应下移 31px 而不是被顶下去。
      //
      // EN
      // Move 31px toward the top: backfill triggers, so content shifts down 31px, not pushed off.
      position.jumpTo(199);
      await tester.pumpAndSettle();

      expect(_renderedCount(tester), 90);
      expect(
        tester.getTopLeft(anchor).dy,
        moreOrLessEquals(before + 31, epsilon: 0.5),
      );

      // ZH
      // 补进来的历史在锚点上方，继续滚到顶后可见。
      //
      // EN
      // Backfilled history sits above the anchor and becomes visible after scrolling to the top.
      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-bubble-u110')), findsOneWidget);
    },
  );

  testWidgets(
    'a failing mermaid block above the viewport does not shift the content',
    (tester) async {
      // ZH
      // 第 5 条回复里的 mermaid 解析失败；等错误回调再换代码块会让该条
      // 先撑高再缩回，滚动中视口上方高度突变、内容跳位。
      //
      // EN
      // The mermaid block in reply 5 fails to parse; swapping to a code block on the error
      // callback would first grow then shrink it, jumping content above the viewport mid-scroll.
      final messages = <Message>[
        for (var i = 0; i < 30; i++) ...[
          UserMessage(id: 'u$i', createdAt: DateTime(2026), text: 'Q$i'),
          AssistantMessage(
            id: 'r$i',
            createdAt: DateTime(2026),
            status: ReplyStatus.done,
            stopReason: StopReason.endTurn,
            thinking: false,
            search: false,
            blocks: [
              TextBlock(
                text: i == 5
                    ? 'Answer\n\n```mermaid\nnot a valid diagram @@\n```\n\n'
                          'Answer\n\nAnswer\n\nAnswer'
                    : 'Answer\n\nAnswer\n\nAnswer\n\nAnswer',
              ),
            ],
          ),
        ],
      ];
      await pumpMessages(tester, messages, width: 390);
      final position = tester.state<ScrollableState>(_listScrollable).position;
      double? yOf(String id) {
        final finder = find.byKey(ValueKey('user-bubble-$id'));
        return finder.evaluate().isEmpty ? null : tester.getTopLeft(finder).dy;
      }

      // ZH
      // 一边往上拖（看更早的消息），一边核对固定消息的屏幕位移与滚动位移。
      //
      // EN
      // Drag up for earlier messages while checking a fixed message moves exactly with the scroll.
      var checked = false;
      for (var step = 0; step < 20; step++) {
        final tracked = yOf('u10') != null
            ? 'u10'
            : (yOf('u9') != null ? 'u9' : null);
        final before = tracked == null ? null : yOf(tracked);
        final pixelsBefore = position.pixels;
        await tester.drag(find.byType(ListView), const Offset(0, 400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final after = tracked == null ? null : yOf(tracked);
        if (before == null || after == null) continue;
        checked = true;
        expect(
          after - before,
          moreOrLessEquals(pixelsBefore - position.pixels, epsilon: 1),
          reason: '第 $step 次拖动：内容位移必须与滚动位移一致',
        );
      }
      expect(checked, isTrue);
    },
  );

  testWidgets('reopening a conversation resets the window', (tester) async {
    final messages = [
      for (var i = 0; i < 200; i++)
        UserMessage(id: 'u$i', createdAt: DateTime(2026), text: 'Q$i'),
    ];
    await pumpMessages(tester, messages, key: const ValueKey('first'));
    tester.state<ScrollableState>(_listScrollable).position.jumpTo(100);
    await tester.pumpAndSettle();
    expect(_renderedCount(tester), 90);

    await pumpMessages(tester, messages, key: const ValueKey('second'));
    expect(_renderedCount(tester), 50);
  });

  testWidgets('switching to a shorter version keeps the window valid', (
    tester,
  ) async {
    final messages = [
      for (var i = 0; i < 200; i++)
        UserMessage(id: 'u$i', createdAt: DateTime(2026), text: 'Q$i'),
    ];
    await pumpMessages(tester, messages);
    tester.state<ScrollableState>(_listScrollable).position.jumpTo(100);
    await tester.pumpAndSettle();
    expect(_renderedCount(tester), 90);

    await pumpMessages(tester, messages.take(20).toList());

    expect(_renderedCount(tester), 20);
    expect(find.byKey(const ValueKey('user-bubble-u19')), findsOneWidget);
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

    // ZH
    // 图标顺序复制 → 朗读 → 重新生成；继续生成靠右、高约 32（同 chat-demo，
    // ShadButton 的 1px 描边占 2px，渲染为 34）。
    //
    // EN
    // Icon order: copy, read aloud, regenerate; continue is rightmost, about 32 high (as
    // chat-demo, where ShadButton's 1px border takes 2px, so it renders at 34).
    final copyX = tester.getCenter(find.byTooltip('复制')).dx;
    final readX = tester.getCenter(find.byTooltip('朗读')).dx;
    final regenerateX = tester.getCenter(find.byTooltip('重新生成')).dx;
    expect(copyX, lessThan(readX));
    expect(readX, lessThan(regenerateX));
    final continueRect = tester.getRect(
      find.byKey(const Key('continue-reply')),
    );
    expect(continueRect.height, inInclusiveRange(32, 34));
    final continueButton = tester.widget<ShadButton>(
      find.byKey(const Key('continue-reply')),
    );
    expect(
      continueButton.foregroundColor,
      ShadTheme.of(tester.element(find.byKey(const Key('continue-reply'))))
          .colorScheme
          .foreground,
    );
    expect(continueRect.right, greaterThan(regenerateX));
    final body = tester.getRect(find.byKey(const Key('assistant-body-reply')));
    expect(body.right - continueRect.right, lessThan(1));

    await tester.tap(find.text('继续生成'));
    expect(events, ['continue:reply']);
  });

  testWidgets('a streaming reply shows no actions', (tester) async {
    await pumpMessages(tester, [
      _reply(const [TextBlock(text: 'Partial')], status: ReplyStatus.streaming),
    ], settle: false);

    expect(find.byTooltip('复制'), findsNothing);
    expect(find.byTooltip('重新生成'), findsNothing);
    expect(find.text('停止生成'), findsNothing);
    expect(events, isEmpty);
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
    // ZH
    // 朗读按回复自身状态判断：已完成的回复仍可朗读（§5.3）。
    //
    // EN
    // Read-aloud follows the reply's own status: a completed reply can still be read (§5.3).
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

    await tester.tap(find.byKey(const ValueKey('edit-message-u1')));
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
    expect(find.text('停止生成'), findsNothing);
    expect(find.byKey(const Key('waiting-dots')), findsNothing);
  });

  testWidgets('waiting dots only show before any content arrives', (
    tester,
  ) async {
    await pumpMessages(tester, [
      AssistantMessage(
        id: 'pending',
        createdAt: DateTime(2026),
        status: ReplyStatus.pending,
        blocks: const [],
        thinking: false,
      ),
    ], settle: false);

    expect(find.byKey(const Key('waiting-dots')), findsOneWidget);

    await pumpMessages(tester, [
      AssistantMessage(
        id: 'pending',
        createdAt: DateTime(2026),
        status: ReplyStatus.streaming,
        blocks: const [TextBlock(text: 'partial')],
        thinking: false,
      ),
    ], settle: false);

    expect(find.byKey(const Key('waiting-dots')), findsNothing);
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

  testWidgets('a stopped reply without continuation shows no notice', (
    tester,
  ) async {
    await pumpMessages(tester, [
      _reply([
        _searchUse('s1', ['flutter']),
      ], status: ReplyStatus.stopped),
    ]);

    expect(find.text('已停止生成'), findsNothing);
    expect(find.byKey(const Key('continue-reply')), findsNothing);
    expect(find.byTooltip('重新生成'), findsOneWidget);
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

  testWidgets(
    'a small drag away from the bottom stops following immediately',
    (tester) async {
      final messages = <Message>[
        for (var i = 0; i < 24; i++) ...[
          UserMessage(id: 'u$i', createdAt: DateTime(2026), text: 'Q$i'),
          _reply(
            const [TextBlock(text: 'Answer\n\nAnswer\n\nAnswer\n\nAnswer')],
            id: 'r$i',
            thinking: false,
            search: false,
          ),
        ],
      ];
      await pumpMessages(tester, messages, width: 390);
      final position = tester.state<ScrollableState>(_listScrollable).position;
      expect(
        position.pixels,
        moreOrLessEquals(position.maxScrollExtent, epsilon: 1),
      );
      expect(find.byKey(const Key('scroll-to-bottom')), findsNothing);

      // ZH
      // 首步位移小于 40 的贴底阈值：必须立即停止跟随；否则后续的
      // 跟随跳转会把手势拉回底部，快速滑动看起来完全没反应。
      //
      // EN
      // The first step is under the 40 at-bottom threshold; following must stop
      // immediately, otherwise the follow jump pulls the drag back to the
      // bottom and a quick swipe looks dead.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ListView)),
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('scroll-to-bottom')), findsOneWidget);

      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();
      expect(position.pixels, lessThan(position.maxScrollExtent - 100));
      await gesture.up();
      await tester.pump();
    },
  );
}
