import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/api/client.dart';
import 'package:open_chat/settings/api_key_store.dart';
import 'package:open_chat/settings/settings_page.dart';

import '../support/fake_api_key_store.dart';

const origin = 'https://api.test';

void main() {
  DeepSeekApiClient clientResponding(int status) => DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient((request) async => http.Response(
              status == 200 ? '{}' : '{"error":{"message":"bad key"}}',
              status,
            )),
      );

  Future<void> pumpSettings(
    WidgetTester tester, {
    required DeepSeekApiClient client,
    required ApiKeyStore store,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(client: client, apiKeyStore: store),
    ));
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
    expect(find.text('API Key 无效'), findsOneWidget);
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
    expect(find.text('网络错误，请检查连接'), findsOneWidget);
  });
}
