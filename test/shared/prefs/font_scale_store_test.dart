import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:seek_chat/shared/prefs/font_scale_store.dart';
import 'package:seek_chat/shared/prefs/preferences_provider.dart';
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

  test('defaults to following the system at the standard level', () async {
    final container = containerWith(await prefsWith({}));
    final settings = container.read(fontScaleProvider);

    expect(settings.followSystem, isTrue);
    expect(settings.level, FontScaleLevels.standard);
    expect(settings.scale, 1);
  });

  test('selecting a level turns off follow and persists it', () async {
    final prefs = await prefsWith({});
    final container = containerWith(prefs);

    await container.read(fontScaleProvider.notifier).selectLevel(5);

    expect(prefs.getBool(FontScaleStore.followKey), isFalse);
    expect(prefs.getInt(FontScaleStore.levelKey), 5);
    final reloaded = containerWith(prefs).read(fontScaleProvider);
    expect(reloaded.followSystem, isFalse);
    expect(reloaded.level, 5);
    expect(reloaded.scale, 1.24);
  });

  test('turning follow back on keeps the selected level', () async {
    final prefs = await prefsWith({});
    final notifier = containerWith(prefs).read(fontScaleProvider.notifier);

    await notifier.selectLevel(1);
    await notifier.setFollowSystem(true);

    final reloaded = containerWith(prefs).read(fontScaleProvider);
    expect(reloaded.followSystem, isTrue);
    expect(reloaded.level, 1);
  });

  test('falls back to standard for an out-of-range stored level', () async {
    final prefs = await prefsWith({FontScaleStore.levelKey: 99});

    expect(
      containerWith(prefs).read(fontScaleProvider).level,
      FontScaleLevels.standard,
    );
  });

  test('follow mode clamps the system scaler to the supported range', () {
    const settings = FontScaleSettings.defaults;

    expect(settings.textScaler(const TextScaler.linear(0.5)).scale(16), 12.8);
    expect(settings.textScaler(const TextScaler.linear(2.5)).scale(16), 32);
  });

  test('manual levels ignore the system scaler', () {
    const settings = FontScaleSettings(followSystem: false, level: 4);

    expect(
      settings.textScaler(const TextScaler.linear(2)).scale(10),
      closeTo(11.2, 1e-10),
    );
  });

  test('nearest maps a system scale to the closest level', () {
    expect(FontScaleLevels.nearest(1), FontScaleLevels.standard);
    expect(FontScaleLevels.nearest(1.05), FontScaleLevels.standard);
    expect(FontScaleLevels.nearest(1.08), 4);
    expect(FontScaleLevels.nearest(0.9), 1);
    expect(FontScaleLevels.nearest(3), 6);
  });
}
