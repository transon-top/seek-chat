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
    List<DraftAttachment> attachments = const [],
    Map<String, UploadTask> tasks = const {},
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
          onThinkingChanged: onThinkingChanged ?? (_) {},
          onSearchChanged: onSearchChanged ?? (_) {},
          onAddAttachment: () => events.add('attach'),
          onRetryAttachment: (id) => events.add('retry:$id'),
          onRemoveAttachment: (id) => events.add('remove:$id'),
          onSend: () => events.add('send'),
          onStop: () => events.add('stop'),
          onVoice: () => events.add('voice'),
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
    final attach = tester.widget<ShadIconButton>(
      find.byKey(const Key('attach-button')),
    );
    expect(attach.onPressed, isNull);
    expect(
      tester
          .widget<ShadIconButton>(find.byKey(const Key('voice-button')))
          .onPressed,
      isNull,
    );
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

  testWidgets('voice button shows recording and transcribing states', (
    tester,
  ) async {
    await tester.pumpWidget(host(phase: SpeechPhase.recording));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    expect(find.byTooltip('结束录音并转写'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-button')));
    expect(events, ['voice']);

    await tester.pumpWidget(host(phase: SpeechPhase.transcribing));
    await tester.pump();
    expect(find.byTooltip('正在转写，点击取消'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('voice input is disabled while a reply is being read aloud', (
    tester,
  ) async {
    await tester.pumpWidget(host(phase: SpeechPhase.playing));
    await tester.pumpAndSettle();
    final button = tester.widget<ShadIconButton>(
      find.byKey(const Key('voice-button')),
    );
    expect(button.onPressed, isNull);
  });
}
