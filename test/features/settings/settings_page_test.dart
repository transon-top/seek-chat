import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:open_chat/features/settings/settings_page.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/prefs/preferences_provider.dart';
import 'package:open_chat/shared/security/api_key_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_api_key_store.dart';

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

  Future<void> pumpSettings(
    WidgetTester tester, {
    required DeepSeekApiClient client,
    required ApiKeyStore store,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          apiKeyStoreProvider.overrideWithValue(store),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('validates and stores a working key', (tester) async {
    final store = FakeApiKeyStore();
    await pumpSettings(tester, client: clientResponding(200), store: store);

    await tester.enterText(find.byType(TextField), 'sk-good');
    await tester.tap(find.text('保存并校验'));
    await tester.pumpAndSettle();

    expect(store.value, 'sk-good');
    expect(find.text('API Key 无效'), findsNothing);
  });

  testWidgets('shows an error and keeps the old key on 401', (tester) async {
    final store = FakeApiKeyStore()..value = 'sk-old';
    await pumpSettings(tester, client: clientResponding(401), store: store);

    await tester.enterText(find.byType(TextField), 'sk-bad');
    await tester.tap(find.text('保存并校验'));
    await tester.pumpAndSettle();

    expect(store.value, 'sk-old');
    expect(find.textContaining('API Key 无效'), findsOneWidget);
  });

  testWidgets('stores the selected language and location', (tester) async {
    final store = FakeApiKeyStore();
    await pumpSettings(tester, client: clientResponding(200), store: store);

    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(prefs.getString('user.locale'), 'en');

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

    expect(find.byKey(const Key('settings-province')), findsNothing);
    await tester.tap(find.byKey(const Key('settings-region')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Afghanistan').last);
    await tester.pumpAndSettle();
    expect(jsonDecode(prefs.getString('user.location')!), {'region': 'AF'});
  });

  testWidgets('reports a network failure without saving', (tester) async {
    final store = FakeApiKeyStore();
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient((request) async {
        throw http.ClientException('no route');
      }),
    );
    await pumpSettings(tester, client: client, store: store);

    await tester.enterText(find.byType(TextField), 'sk-good');
    await tester.tap(find.text('保存并校验'));
    await tester.pumpAndSettle();

    expect(store.value, isNull);
    expect(find.textContaining('网络错误，请检查连接'), findsOneWidget);
  });
}
