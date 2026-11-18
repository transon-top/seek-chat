import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/shared/prefs/preferences_provider.dart';
import 'package:open_chat/shared/prefs/theme_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  ProviderContainer containerWith(SharedPreferences prefs) =>
      ProviderContainer.test(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );

  test('defaults to the system theme', () async {
    final container = containerWith(await prefsWith({}));
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('persists the selected theme and reloads it', () async {
    final prefs = await prefsWith({});
    final container = containerWith(prefs);
    final notifier = container.read(themeModeProvider.notifier);

    await notifier.setThemeMode(ThemeMode.dark);
    expect(prefs.getString(ThemeStore.themeModeKey), 'dark');
    expect(containerWith(prefs).read(themeModeProvider), ThemeMode.dark);

    await notifier.setThemeMode(ThemeMode.light);
    expect(containerWith(prefs).read(themeModeProvider), ThemeMode.light);
  });

  test('ignores invalid stored values', () async {
    final prefs = await prefsWith({ThemeStore.themeModeKey: 'sepia'});
    expect(containerWith(prefs).read(themeModeProvider), ThemeMode.system);
  });
}
