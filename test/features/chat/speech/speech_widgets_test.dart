import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/chat/speech/read_aloud_button.dart';
import 'package:open_chat/features/chat/speech/speech_controller.dart';
import 'package:open_chat/features/chat/speech/voice_button.dart';
import 'package:open_chat/features/chat/speech/recording_overlay.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester,
    Widget child, {
    Locale locale = const Locale('zh'),
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShadTheme(
            data: buildShadTheme(
              brightness: Brightness.light,
              chinese: locale.languageCode == 'zh',
            ),
            child: MediaQuery(
              data: MediaQueryData(disableAnimations: disableAnimations),
              child: Scaffold(body: Center(child: child)),
            ),
          ),
        ),
      ),
    );
  }

  VoiceButton voiceButton({
    SpeechPhase phase = SpeechPhase.idle,
    bool enabled = true,
    VoidCallback? onStart,
    VoidCallback? onEnd,
    VoidCallback? onGestureCancel,
    ValueChanged<bool>? onCancelArmedChanged,
    VoidCallback? onCancelRecording,
  }) => VoiceButton(
    phase: phase,
    enabled: enabled,
    onStart: onStart ?? () {},
    onEnd: onEnd ?? () {},
    onGestureCancel: onGestureCancel ?? () {},
    onCancelArmedChanged: onCancelArmedChanged ?? (_) {},
    onCancelRecording: onCancelRecording ?? () {},
  );

  test('the cancel threshold is measured from the press Y in 80dp steps', () {
    expect(shouldCancelVoice(startY: 500, currentY: 420), isTrue);
    expect(shouldCancelVoice(startY: 500, currentY: 421), isFalse);
    expect(shouldCancelVoice(startY: 500, currentY: 500), isFalse);
    expect(shouldCancelVoice(startY: 300, currentY: 260), isFalse);
    expect(shouldCancelVoice(startY: 300, currentY: 220), isTrue);
    expect(
      shouldCancelVoice(startY: 300, currentY: 100, threshold: 200),
      isTrue,
    );
  });

  testWidgets('semantics tap toggles start and end without holding', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var starts = 0;
    var ends = 0;
    await pumpHost(
      tester,
      voiceButton(onStart: () => starts++, onEnd: () => ends++),
    );

    var node = tester.getSemantics(find.byKey(const Key('voice-button')));
    expect(node.label, '按住说话');
    tester.semantics.tap(find.semantics.byLabel('按住说话'));
    await tester.pump();
    expect(starts, 1);

    await pumpHost(
      tester,
      voiceButton(
        phase: SpeechPhase.recording,
        onStart: () => starts++,
        onEnd: () => ends++,
      ),
    );
    node = tester.getSemantics(find.byKey(const Key('voice-button')));
    expect(node.label, '录音中，双击结束并发送');
    tester.semantics.tap(find.semantics.byLabel('录音中，双击结束并发送'));
    await tester.pump();
    expect(ends, 1);
    semantics.dispose();
  });

  testWidgets('recording exposes a cancel-recording semantics action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var cancelled = 0;
    await pumpHost(
      tester,
      voiceButton(
        phase: SpeechPhase.recording,
        onCancelRecording: () => cancelled++,
      ),
    );

    final node = tester.getSemantics(find.byKey(const Key('voice-button')));
    final actionId = node.getSemanticsData().customSemanticsActionIds!.single;
    tester.semantics.performAction(
      find.semantics.byLabel('录音中，双击结束并发送'),
      SemanticsAction.customAction,
      args: actionId,
    );
    await tester.pump();
    expect(cancelled, 1);

    await pumpHost(tester, voiceButton(phase: SpeechPhase.idle));
    final idle = tester.getSemantics(find.byKey(const Key('voice-button')));
    expect(idle.getSemanticsData().customSemanticsActionIds, isEmpty);
    semantics.dispose();
  });

  testWidgets('holding tracks one pointer and arms cancel on an 80dp slide', (
    tester,
  ) async {
    var starts = 0;
    var ends = 0;
    final armed = <bool>[];
    await pumpHost(
      tester,
      voiceButton(
        onStart: () => starts++,
        onEnd: () => ends++,
        onCancelArmedChanged: armed.add,
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('voice-button'))),
    );
    await tester.pump();
    expect(starts, 1);
    expect(ends, 0);

    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(armed, [true]);

    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(armed, [true, false]);

    await gesture.up();
    await tester.pump();
    expect(ends, 1);
  });

  testWidgets('a pointer cancel reports a gesture cancel', (tester) async {
    var cancelled = 0;
    var ends = 0;
    await pumpHost(
      tester,
      voiceButton(onEnd: () => ends++, onGestureCancel: () => cancelled++),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('voice-button'))),
    );
    await tester.pump();
    await gesture.cancel();
    await tester.pump();

    expect(cancelled, 1);
    expect(ends, 0);
  });

  testWidgets('a disabled microphone ignores presses', (tester) async {
    var starts = 0;
    await pumpHost(
      tester,
      voiceButton(enabled: false, onStart: () => starts++),
    );
    await tester.tap(find.byKey(const Key('voice-button')));
    await tester.pump();
    expect(starts, 0);
  });

  testWidgets('the voice button uses English copy', (tester) async {
    await pumpHost(tester, voiceButton(), locale: const Locale('en'));
    expect(find.byTooltip('Hold to talk'), findsOneWidget);
  });

  testWidgets('the overlay shows the three hold-to-talk copies', (
    tester,
  ) async {
    await pumpHost(
      tester,
      const RecordingOverlay(phase: SpeechPhase.recording),
    );
    expect(find.text('松手发送，上滑取消'), findsOneWidget);

    await pumpHost(
      tester,
      const RecordingOverlay(phase: SpeechPhase.cancelling),
    );
    expect(find.text('松开取消'), findsOneWidget);

    await pumpHost(
      tester,
      const RecordingOverlay(phase: SpeechPhase.transcribing),
    );
    expect(find.text('识别中'), findsOneWidget);

    await pumpHost(tester, const RecordingOverlay(phase: SpeechPhase.idle));
    expect(find.byKey(const Key('recording-overlay')), findsNothing);
  });

  testWidgets(
    'the overlay announces recording and recognizing as live regions',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await pumpHost(
        tester,
        const RecordingOverlay(phase: SpeechPhase.recording),
      );
      var node = tester.getSemantics(
        find.byKey(const Key('recording-overlay')),
      );
      expect(node.label, '录音中，双击结束并发送');
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);

      await pumpHost(
        tester,
        const RecordingOverlay(phase: SpeechPhase.transcribing),
      );
      node = tester.getSemantics(find.byKey(const Key('recording-overlay')));
      expect(node.label, '正在识别');
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    },
  );

  testWidgets('the overlay never intercepts taps', (tester) async {
    var taps = 0;
    await pumpHost(
      tester,
      Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => taps++,
              behavior: HitTestBehavior.opaque,
            ),
          ),
          const RecordingOverlay(phase: SpeechPhase.recording),
        ],
      ),
    );

    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('recording-overlay'))),
    );
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('read-aloud button shows idle, loading and playing states', (
    tester,
  ) async {
    var taps = 0;
    await pumpHost(
      tester,
      ReadAloudButton(
        phase: SpeechPhase.idle,
        active: false,
        enabled: true,
        onPressed: () => taps++,
      ),
    );
    expect(find.byTooltip('朗读'), findsOneWidget);
    await tester.tap(find.byKey(const Key('read-aloud-button')));
    expect(taps, 1);

    await pumpHost(
      tester,
      ReadAloudButton(
        phase: SpeechPhase.loading,
        active: true,
        enabled: true,
        onPressed: () {},
      ),
    );
    expect(find.byTooltip('停止朗读'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));

    await pumpHost(
      tester,
      ReadAloudButton(
        phase: SpeechPhase.playing,
        active: true,
        enabled: true,
        onPressed: () {},
      ),
    );
    expect(find.byTooltip('停止朗读'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read-aloud keeps a static frame when animations are reduced', (
    tester,
  ) async {
    await pumpHost(
      tester,
      ReadAloudButton(
        phase: SpeechPhase.playing,
        active: true,
        enabled: true,
        onPressed: () {},
      ),
      disableAnimations: true,
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('停止朗读'), findsOneWidget);
  });

  testWidgets('read-aloud is disabled with voice input active', (tester) async {
    await pumpHost(
      tester,
      ReadAloudButton(
        phase: SpeechPhase.recording,
        active: false,
        enabled: false,
        onPressed: () {},
      ),
    );
    final button = tester.widget<ShadIconButton>(
      find.byKey(const Key('read-aloud-button')),
    );
    expect(button.onPressed, isNull);
  });
}
