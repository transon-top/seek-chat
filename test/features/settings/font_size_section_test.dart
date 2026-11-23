import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:seek_chat/app/localization.dart';
import 'package:seek_chat/app/theme.dart';
import 'package:seek_chat/features/settings/settings_page.dart';
import 'package:seek_chat/l10n/generated/app_localizations.dart';
import 'package:seek_chat/shared/prefs/font_scale_store.dart';
import 'package:seek_chat/shared/prefs/preferences_provider.dart';
import 'package:seek_chat/shared/speech/permissions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/speech_fakes.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    binding.platformDispatcher.localesTestValue = const [Locale('zh')];
  });

  tearDown(() => binding.platformDispatcher.clearLocalesTestValue());

  Future<void> pumpSettings(
    WidgetTester tester, {
    TextScaler? systemScaler,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microphonePermissionsProvider.overrideWithValue(
            FakeMicrophonePermissions(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: systemScaler == null
                    ? media
                    : media.copyWith(textScaler: systemScaler),
                child: ShadTheme(
                  data: buildShadTheme(
                    brightness: Brightness.light,
                    chinese: true,
                  ),
                  child: ShadToaster(
                    child: Scaffold(body: const SettingsSheet()),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ShadSwitch followSwitch(WidgetTester tester) =>
      tester.widget<ShadSwitch>(find.byKey(const Key('settings-font-follow')));

  String sliderValue(WidgetTester tester) =>
      tester.getSemantics(find.byKey(const Key('settings-font-slider'))).value;

  Future<void> tapTick(WidgetTester tester, int index) async {
    final tick = find.byKey(Key('settings-font-tick-$index'));
    await tester.ensureVisible(tick);
    await tester.pumpAndSettle();
    await tester.tap(tick);
    await tester.pumpAndSettle();
  }

  testWidgets('defaults to following the system at the standard level', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSettings(tester);

    expect(followSwitch(tester).value, isTrue);
    expect(sliderValue(tester), '标准');
    semantics.dispose();
  });

  testWidgets('tapping a tick turns follow off and persists the level', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSettings(tester);

    await tapTick(tester, 6);

    expect(followSwitch(tester).value, isFalse);
    expect(prefs.getBool(FontScaleStore.followKey), isFalse);
    expect(prefs.getInt(FontScaleStore.levelKey), 6);
    expect(sliderValue(tester), '最大');
    semantics.dispose();
  });

  testWidgets('turning follow on again shows the system level', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpSettings(tester);

    await tapTick(tester, 1);
    final follow = find.byKey(const Key('settings-font-follow'));
    await tester.ensureVisible(follow);
    await tester.pumpAndSettle();
    await tester.tap(follow);
    await tester.pumpAndSettle();

    expect(followSwitch(tester).value, isTrue);
    expect(prefs.getBool(FontScaleStore.followKey), isTrue);
    expect(prefs.getInt(FontScaleStore.levelKey), 1);
    expect(sliderValue(tester), '标准');
    semantics.dispose();
  });

  testWidgets('follow mode maps the system scale to the nearest level', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSettings(tester, systemScaler: const TextScaler.linear(1.2));

    expect(followSwitch(tester).value, isTrue);
    expect(sliderValue(tester), '大');
    semantics.dispose();
  });
}
