import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:seek_chat/app/localization.dart';
import 'package:seek_chat/app/theme.dart';
import 'package:seek_chat/features/settings/settings_account_page.dart';
import 'package:seek_chat/features/settings/settings_data_page.dart';
import 'package:seek_chat/features/settings/settings_font_size_page.dart';
import 'package:seek_chat/features/settings/settings_location_page.dart';
import 'package:seek_chat/features/settings/settings_page.dart';
import 'package:seek_chat/shared/api/client.dart';
import 'package:seek_chat/shared/prefs/preferences_provider.dart';
import 'package:seek_chat/shared/providers.dart';
import 'package:seek_chat/shared/security/api_key_store.dart';
import 'package:seek_chat/shared/speech/permissions.dart';
import 'package:seek_chat/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api_key_store.dart';
import '../../support/speech_fakes.dart';

const origin = 'https://api.test';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    binding.platformDispatcher.localesTestValue = const [Locale('zh')];
  });

  tearDown(() => binding.platformDispatcher.clearLocalesTestValue());

  DeepSeekApiClient clientResponding(int status) => DeepSeekApiClient(
    origin: Uri.parse(origin),
    httpClient: MockClient(
      (request) async => http.Response(
        status == 200 ? '{}' : '{"error":{"message":"bad key"}}',
        status,
      ),
    ),
  );

  GoRouter testRouter(String initialLocation) => GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
      GoRoute(
        path: SettingsRoutes.root,
        builder: (_, _) => const SettingsPage(),
        routes: [
          GoRoute(
            path: 'account',
            builder: (_, state) => AccountSettingsPage(
              focusApiKey: state.uri.queryParameters['focus'] == '1',
            ),
          ),
          GoRoute(path: 'data', builder: (_, _) => const DataSettingsPage()),
          GoRoute(
            path: 'font-size',
            builder: (_, _) => const FontSizeSettingsPage(),
          ),
          GoRoute(
            path: 'location',
            builder: (_, _) => const LocationSettingsPage(),
          ),
        ],
      ),
    ],
  );

  Future<void> pumpSettings(
    WidgetTester tester, {
    required DeepSeekApiClient client,
    required ApiKeyStore store,
    Locale locale = const Locale('zh'),
    FakeMicrophonePermissions? permissions,
    String initialLocation = SettingsRoutes.root,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          apiKeyStoreProvider.overrideWithValue(store),
          sharedPreferencesProvider.overrideWithValue(prefs),
          microphonePermissionsProvider.overrideWithValue(
            permissions ?? FakeMicrophonePermissions(),
          ),
        ],
        child: ShadTheme(
          data: buildShadTheme(
            brightness: Brightness.light,
            chinese: locale.languageCode == 'zh',
          ),
          child: MaterialApp.router(
            routerConfig: testRouter(initialLocation),
            locale: locale,
            localizationsDelegates: appLocalizationDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submitKey(WidgetTester tester, String key) async {
    await tester.enterText(
      find.byKey(const Key('settings-api-key-input')),
      key,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets('opens the account page with the key field focused', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
      initialLocation: SettingsRoutes.accountFocus,
    );

    final input = find.byKey(const Key('settings-api-key-input'));
    expect(input, findsOneWidget);
    expect(tester.widget<ShadInput>(input).focusNode!.hasFocus, isTrue);
  });

  testWidgets('validates and stores a working key', (tester) async {
    final store = FakeApiKeyStore();
    await pumpSettings(tester, client: clientResponding(200), store: store);
    await tester.tap(find.byKey(const Key('settings-account')));
    await tester.pumpAndSettle();

    await submitKey(tester, 'sk-good');

    expect(store.value, 'sk-good');
    expect(find.text('API Key 无效'), findsNothing);
    // ZH
    // 保存后只显示掩码，点编辑按钮才能重新输入
    //
    // EN
    // After saving only the mask shows; tapping edit enables input again.
    expect(find.byKey(const Key('settings-edit-key')), findsOneWidget);
    expect(find.byKey(const Key('settings-api-key-input')), findsNothing);
  });

  testWidgets('shows an error and keeps the old key on 401', (tester) async {
    final store = FakeApiKeyStore()..value = 'sk-old';
    await pumpSettings(
      tester,
      client: clientResponding(401),
      store: store,
      initialLocation: SettingsRoutes.account,
    );

    await tester.tap(find.byKey(const Key('settings-edit-key')));
    await tester.pumpAndSettle();
    await submitKey(tester, 'sk-bad');

    expect(store.value, 'sk-old');
    expect(find.textContaining('API Key 无效'), findsOneWidget);
  });

  testWidgets('leaves edit mode when the input is empty', (tester) async {
    final store = FakeApiKeyStore()..value = 'sk-old';
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: store,
      initialLocation: SettingsRoutes.account,
    );

    await tester.tap(find.byKey(const Key('settings-edit-key')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-api-key-input')), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-edit-key')), findsOneWidget);
    expect(find.byKey(const Key('settings-api-key-input')), findsNothing);
  });

  testWidgets('clears the saved key', (tester) async {
    final store = FakeApiKeyStore()..value = 'sk-old';
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: store,
      initialLocation: SettingsRoutes.account,
    );

    await tester.tap(find.byKey(const Key('settings-clear-key')));
    await tester.pumpAndSettle();

    expect(store.value, isNull);
    expect(find.text('输入 API Key 开始使用'), findsOneWidget);
  });

  testWidgets('stores the selected language after confirmation', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
    );

    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(prefs.getString('user.locale'), isNull);

    await tester.tap(find.byKey(const Key('settings-choice-confirm')));
    await tester.pumpAndSettle();
    expect(prefs.getString('user.locale'), 'en');
  });

  testWidgets('tapping the barrier cancels the language dialog', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
    );

    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(prefs.getString('user.locale'), isNull);
  });

  testWidgets('follows the system language when selected', (tester) async {
    prefs.setString('user.locale', 'en');
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
    );

    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随系统').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-choice-confirm')));
    await tester.pumpAndSettle();

    expect(prefs.getString('user.locale'), isNull);
  });

  testWidgets('stores the selected theme after confirmation', (tester) async {
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
    );

    await tester.tap(find.byKey(const Key('settings-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-theme-dark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-choice-confirm')));
    await tester.pumpAndSettle();

    expect(prefs.getString('ui.themeMode'), 'dark');
  });

  testWidgets('renders the settings pages in English', (tester) async {
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
      locale: const Locale('en'),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Account'), findsWidgets);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-account')));
    await tester.pumpAndSettle();
    expect(find.text('Enter an API key to get started'), findsOneWidget);
  });

  testWidgets('stores the selected province and city', (tester) async {
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
    );

    await tester.tap(find.byKey(const Key('settings-location')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-province')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('北京市').last);
    await tester.pumpAndSettle();
    expect(jsonDecode(prefs.getString('user.location')!), {
      'region': 'CN',
      'province': '110000',
    });

    await tester.tap(find.byKey(const Key('settings-city')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('北京市').last);
    await tester.pumpAndSettle();
    expect(jsonDecode(prefs.getString('user.location')!), {
      'region': 'CN',
      'province': '110000',
      'city': '110100',
    });

    await tester.tap(find.byKey(const Key('settings-province')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不指定').last);
    await tester.pumpAndSettle();
    expect(prefs.getString('user.location'), isNull);
  });

  testWidgets('uses a country list when the system language is not Chinese', (
    tester,
  ) async {
    binding.platformDispatcher.localesTestValue = const [Locale('en')];
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
    );

    await tester.tap(find.byKey(const Key('settings-location')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-province')), findsNothing);
    await tester.tap(find.byKey(const Key('settings-region')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Afghanistan').last);
    await tester.pumpAndSettle();
    expect(jsonDecode(prefs.getString('user.location')!), {'region': 'AF'});
  });

  testWidgets('shows the microphone permission states', (tester) async {
    final permissions = FakeMicrophonePermissions()
      ..granted = false
      ..requestResult = false;
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
      permissions: permissions,
    );

    expect(find.text('已拒绝'), findsOneWidget);
    final openSettings = find.byKey(const Key('settings-open-settings'));
    await tester.ensureVisible(openSettings);
    await tester.pumpAndSettle();
    await tester.tap(openSettings);
    await tester.pumpAndSettle();
    expect(permissions.openedSettings, isTrue);
  });

  testWidgets('persists the read-aloud voice after confirmation', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      client: clientResponding(200),
      store: FakeApiKeyStore(),
    );

    await tester.tap(find.byKey(const Key('settings-tts-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-voice-tide')));
    await tester.pumpAndSettle();
    expect(prefs.getString('tts.voice'), isNull);

    await tester.tap(find.byKey(const Key('settings-voice-confirm')));
    await tester.pumpAndSettle();

    expect(prefs.getString('tts.voice'), 'tide');
  });

  testWidgets('reports a network failure without saving', (tester) async {
    final store = FakeApiKeyStore();
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient((request) async {
        throw http.ClientException('no route');
      }),
    );
    await pumpSettings(
      tester,
      client: client,
      store: store,
      initialLocation: SettingsRoutes.account,
    );

    await submitKey(tester, 'sk-good');

    expect(store.value, isNull);
    expect(find.textContaining('网络错误，请检查连接'), findsOneWidget);
  });
}
