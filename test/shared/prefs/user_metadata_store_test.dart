import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/shared/models/location.dart';
import 'package:open_chat/shared/prefs/preferences_provider.dart';
import 'package:open_chat/shared/prefs/user_metadata_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  ProviderContainer containerWith(
    SharedPreferences prefs, {
    String systemLanguage = 'zh',
  }) => ProviderContainer.test(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      systemLanguageCodeProvider.overrideWithValue(systemLanguage),
    ],
  );

  test('defaults the language to the system language', () async {
    expect(
      containerWith(
        await prefsWith({}),
        systemLanguage: 'zh',
      ).read(userMetadataProvider).locale,
      'zh',
    );
    expect(
      containerWith(
        await prefsWith({}),
        systemLanguage: 'en',
      ).read(userMetadataProvider).locale,
      'en',
    );
  });

  test('persists the selected language and location', () async {
    final prefs = await prefsWith({});
    final container = containerWith(prefs);
    final notifier = container.read(userMetadataProvider.notifier);

    await notifier.setLocale('en');
    await notifier.setLocation(
      const UserLocation(region: 'CN', province: '330000', city: '330100'),
    );

    final reloaded = containerWith(prefs).read(userMetadataProvider);
    expect(reloaded.locale, 'en');
    expect(
      reloaded.location,
      const UserLocation(region: 'CN', province: '330000', city: '330100'),
    );

    await notifier.setLocation(null);
    expect(containerWith(prefs).read(userMetadataProvider).location, isNull);
  });

  test('ignores invalid stored values', () async {
    final prefs = await prefsWith({
      'user.locale': 'fr',
      'user.location': '{"region":"XX"}',
    });
    final metadata = containerWith(prefs).read(userMetadataProvider);
    expect(metadata.locale, 'zh');
    expect(metadata.location, isNull);
  });

  test('crops a stored location to the system language mode', () async {
    final foreign = await prefsWith({'user.location': '{"region":"US"}'});
    expect(
      containerWith(
        foreign,
        systemLanguage: 'zh',
      ).read(userMetadataProvider).location,
      isNull,
    );

    final chinese = await prefsWith({
      'user.location': '{"region":"CN","province":"330000","city":"330100"}',
    });
    expect(
      containerWith(
        chinese,
        systemLanguage: 'en',
      ).read(userMetadataProvider).location,
      const UserLocation(region: 'CN'),
    );
  });
}
