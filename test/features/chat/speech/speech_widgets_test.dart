import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/chat/speech/read_aloud_button.dart';
import 'package:open_chat/features/chat/speech/recording_status.dart';
import 'package:open_chat/features/chat/speech/speech_controller.dart';
import 'package:open_chat/features/chat/speech/voice_button.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';

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

  testWidgets('voice button shows idle, recording and transcribing states', (
    tester,
  ) async {
    var taps = 0;
    await pumpHost(
      tester,
      VoiceButton(phase: SpeechPhase.idle, onPressed: () => taps++),
    );
    expect(find.byTooltip('语音输入'), findsOneWidget);
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice-button')));
    expect(taps, 1);

    await pumpHost(
      tester,
      VoiceButton(phase: SpeechPhase.recording, onPressed: () {}),
    );
    expect(find.byTooltip('结束录音并转写'), findsOneWidget);
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);

    await pumpHost(
      tester,
      VoiceButton(phase: SpeechPhase.transcribing, onPressed: () {}),
    );
    expect(find.byTooltip('正在转写，点击取消'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('voice button uses English copy', (tester) async {
    await pumpHost(
      tester,
      VoiceButton(phase: SpeechPhase.idle, onPressed: () {}),
      locale: const Locale('en'),
    );
    expect(find.byTooltip('Voice input'), findsOneWidget);
  });

  testWidgets('voice button is disabled while generating or reading aloud', (
    tester,
  ) async {
    await pumpHost(
      tester,
      const VoiceButton(phase: SpeechPhase.idle, onPressed: null),
    );
    final button = tester.widget<ShadIconButton>(
      find.byKey(const Key('voice-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('recording status shows seconds and level bars', (tester) async {
    await pumpHost(
      tester,
      const RecordingStatus(
        phase: SpeechPhase.recording,
        seconds: 3,
        level: 0.5,
      ),
    );
    expect(find.text('录音中 3 秒'), findsOneWidget);
    expect(find.byKey(const Key('level-bars')), findsOneWidget);

    await pumpHost(
      tester,
      const RecordingStatus(
        phase: SpeechPhase.transcribing,
        seconds: 0,
        level: 0,
      ),
    );
    expect(find.text('正在转写…'), findsOneWidget);
    expect(find.byKey(const Key('level-bars')), findsNothing);
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
    final button = tester.widget<IconButton>(
      find.byKey(const Key('read-aloud-button')),
    );
    expect(button.onPressed, isNull);
  });
}
