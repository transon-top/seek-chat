import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/chat/composer.dart';
import 'package:open_chat/features/chat/speech/speech_controller.dart';
import 'package:open_chat/features/chat/upload_tasks.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 输入区状态行只读语音状态；测试固定为空闲，避免启动真实录音 / 播放依赖。
class _IdleSpeech extends SpeechController {
  @override
  SpeechState build() => const SpeechState();
}

void main() {
  late TextEditingController input;
  late FocusNode focus;
  late List<String> events;

  setUp(() {
    input = TextEditingController();
    focus = FocusNode();
    events = [];
  });

  tearDown(() {
    input.dispose();
    focus.dispose();
  });

  Widget host({
    bool busy = false,
    SpeechPhase phase = SpeechPhase.idle,
    bool thinking = false,
    bool search = false,
    bool panelOpen = false,
    List<DraftAttachment> attachments = const [],
    Map<String, UploadTask> tasks = const {},
    Widget? attachmentPanel,
    ValueChanged<bool>? onThinkingChanged,
    ValueChanged<bool>? onSearchChanged,
  }) => ProviderScope(
    overrides: [speechControllerProvider.overrideWith(_IdleSpeech.new)],
    child: ShadApp(
      theme: buildShadTheme(brightness: Brightness.light, chinese: true),
      locale: const Locale('zh'),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Composer(
          input: input,
          inputFocus: focus,
          busy: busy,
          phase: phase,
          thinking: thinking,
          search: search,
          attachments: attachments,
          tasks: tasks,
          panelOpen: panelOpen,
          attachmentPanel: attachmentPanel ?? const SizedBox.shrink(),
          onThinkingChanged: onThinkingChanged ?? (_) {},
          onSearchChanged: onSearchChanged ?? (_) {},
          onTogglePanel: () => events.add('toggle-panel'),
          onRetryAttachment: (id) => events.add('retry:$id'),
          onRemoveAttachment: (id) => events.add('remove:$id'),
          onSend: () => events.add('send'),
          onStop: () => events.add('stop'),
          onVoiceStart: () => events.add('voice-start'),
          onVoiceEnd: () => events.add('voice-end'),
          onVoicePointerCancel: () => events.add('voice-cancel'),
          onVoiceCancelArmed: (armed) => events.add('voice-armed:$armed'),
          onVoiceCancel: () => events.add('voice-cancel-recording'),
        ),
      ),
    ),
  );

  BoxDecoration decorationOf(WidgetTester tester, Key key) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('toggles show the blue active style and report taps', (
    tester,
  ) async {
    var changed = <bool>[];
    await tester.pumpWidget(
      host(
        thinking: true,
        onThinkingChanged: changed.add,
        onSearchChanged: changed.add,
      ),
    );
    await tester.pumpAndSettle();

    final colors = ShadTheme.of(
      tester.element(find.byKey(const Key('thinking-toggle'))),
    ).colorScheme;
    final active = decorationOf(tester, const Key('thinking-toggle'));
    expect(active.color, colors.primary.withValues(alpha: 0.10));
    expect(
      (active.border! as Border).top.color,
      colors.primary.withValues(alpha: 0.45),
    );
    final label = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('thinking-toggle')),
        matching: find.text('深度思考'),
      ),
    );
    expect(label.style?.color, colors.primary);

    final idle = decorationOf(tester, const Key('search-toggle'));
    expect(idle.color, Colors.transparent);
    expect((idle.border! as Border).top.color, colors.border);

    await tester.tap(find.byKey(const Key('thinking-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('search-toggle')));
    await tester.pump();
    expect(changed, [false, true]);
  });

  testWidgets('send enables with content and switches to stop while busy', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(tester.widget<SendButton>(find.byType(SendButton)).enabled, isFalse);
    await tester.tap(find.byKey(const Key('send-button')));
    expect(events, isEmpty);

    input.text = 'Hello';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(tester.widget<SendButton>(find.byType(SendButton)).enabled, isTrue);
    await tester.tap(find.byKey(const Key('send-button')));
    expect(events, ['send']);

    await tester.pumpWidget(host(busy: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stop-button')), findsOneWidget);
    expect(find.byKey(const Key('send-button')), findsNothing);
    // 停止与发送同底：主色圆 + 实心方块图标（照搬 chat-demo）。
    final colors = ShadTheme.of(
      tester.element(find.byKey(const Key('stop-button'))),
    ).colorScheme;
    final stopCircle = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const Key('stop-button')),
            matching: find.byType(Container),
          ),
        )
        .first;
    expect((stopCircle.decoration! as BoxDecoration).color, colors.primary);
    expect(find.byTooltip('停止生成'), findsOneWidget);
    final attach = tester.widget<ShadIconButton>(
      find.byKey(const Key('attach-button')),
    );
    expect(attach.onPressed, isNull);
    expect(find.byKey(const Key('voice-button')), findsNothing);
    await tester.tap(find.byKey(const Key('stop-button')));
    expect(events, ['send', 'stop']);
  });

  testWidgets('uploads must finish before sending', (tester) async {
    const attachment = DraftAttachment(
      id: 'a',
      path: '/tmp/a.txt',
      name: 'a.txt',
      size: 1,
      isImage: false,
      mimeType: 'text/plain',
    );
    await tester.pumpWidget(
      host(
        attachments: const [attachment],
        tasks: const {'a': UploadTask.uploading()},
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SendButton>(find.byType(SendButton)).enabled, isFalse);

    await tester.pumpWidget(
      host(
        attachments: const [attachment],
        tasks: const {'a': UploadTask.done('file_1')},
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SendButton>(find.byType(SendButton)).enabled, isTrue);
  });

  testWidgets('a failed attachment is retried from the strip', (tester) async {
    const attachment = DraftAttachment(
      id: 'a',
      path: '/tmp/a.txt',
      name: 'a.txt',
      size: 1,
      isImage: false,
      mimeType: 'text/plain',
    );
    await tester.pumpWidget(
      host(
        attachments: const [attachment],
        tasks: const {
          'a': UploadTask.failed(
            error: LocalMessage(key: LocalMessageKeys.uploadServerBusy),
            retryable: true,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('服务器繁忙'), findsOneWidget);
    expect(tester.widget<SendButton>(find.byType(SendButton)).enabled, isFalse);

    await tester.tap(find.byIcon(LucideIcons.refreshCw));
    expect(events, ['retry:a']);
  });

  testWidgets('voice button starts on press and ends on release', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byTooltip('按住说话'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('voice-button'))),
    );
    await tester.pump();
    expect(events, ['voice-start']);
    await gesture.up();
    await tester.pump();
    expect(events, ['voice-start', 'voice-end']);
  });

  testWidgets('voice overlay states keep the send slot disabled', (
    tester,
  ) async {
    input.text = 'Hello';
    await tester.pumpWidget(host(phase: SpeechPhase.transcribing));
    await tester.pumpAndSettle();
    expect(tester.widget<SendButton>(find.byType(SendButton)).enabled, isFalse);
    expect(
      tester
          .widget<ShadIconButton>(find.byKey(const Key('attach-button')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ComposerToggle>(find.byKey(const Key('thinking-toggle')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<ComposerToggle>(find.byKey(const Key('search-toggle')))
          .enabled,
      isFalse,
    );
  });

  testWidgets('voice input is disabled while a reply is being read aloud', (
    tester,
  ) async {
    await tester.pumpWidget(host(phase: SpeechPhase.playing));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voice-button')));
    await tester.pump();
    expect(events, isEmpty);
  });

  testWidgets('composer hint follows attachments and hides with text', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('发消息或按住说话'), findsOneWidget);

    const attachment = DraftAttachment(
      id: 'a',
      path: '/tmp/a.txt',
      name: 'a.txt',
      size: 1,
      isImage: false,
      mimeType: 'text/plain',
    );
    await tester.pumpWidget(host(attachments: const [attachment]));
    await tester.pumpAndSettle();
    expect(find.text('发消息'), findsOneWidget);
    expect(find.text('发消息或按住说话'), findsNothing);

    input.text = 'Hello';
    await tester.pumpWidget(host(attachments: const [attachment]));
    await tester.pumpAndSettle();
    expect(find.text('发消息'), findsNothing);
  });

  testWidgets('button matrix covers empty, text and reading states', (
    tester,
  ) async {
    // 无文本无附件：+ 可用、麦克风显示、发送禁用。
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ShadIconButton>(find.byKey(const Key('attach-button')))
          .onPressed,
      isNotNull,
    );
    expect(find.byKey(const Key('voice-button')), findsOneWidget);
    expect(tester.widget<SendButton>(find.byType(SendButton)).enabled, isFalse);

    // 有文本：麦克风隐藏、发送可用。
    input.text = 'Hello';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-button')), findsNothing);
    expect(tester.widget<SendButton>(find.byType(SendButton)).enabled, isTrue);

    // 朗读中：麦克风显示但禁用。
    input.clear();
    await tester.pumpWidget(host(phase: SpeechPhase.playing));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-button')));
    await tester.pump();
    expect(events, isEmpty);
  });

  testWidgets('plus toggles to close and renders the panel', (tester) async {
    await tester.pumpWidget(
      host(attachmentPanel: const SizedBox(key: Key('fake-panel'))),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.plus), findsOneWidget);
    expect(find.byKey(const Key('fake-panel')), findsNothing);
    await tester.tap(find.byKey(const Key('attach-button')));
    expect(events, ['toggle-panel']);

    await tester.pumpWidget(
      host(
        panelOpen: true,
        attachmentPanel: const SizedBox(key: Key('fake-panel')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    expect(find.byKey(const Key('fake-panel')), findsOneWidget);
    expect(find.byTooltip('收起附件面板'), findsOneWidget);
  });
}
