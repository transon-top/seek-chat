import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'preferences_provider.dart';

/// ZH
/// 主题偏好（票 18）：浅色 / 深色 / 跟随系统，默认跟随系统。
///
/// 与语言一样在启动时同步读取，首帧即为最终主题，不闪。
///
/// EN
/// Theme preferences (ticket 18): light / dark / follow system, following the system by default.
///
/// Like language, read synchronously at startup so the first frame has the final theme, no flash.
class ThemeStore {
  ThemeStore(this._preferences);

  static const themeModeKey = 'ui.themeMode';

  final SharedPreferences _preferences;

  ThemeMode get themeMode => switch (_preferences.getString(themeModeKey)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setThemeMode(ThemeMode mode) =>
      _preferences.setString(themeModeKey, mode.name);
}

final themeStoreProvider = Provider<ThemeStore>(
  (ref) => ThemeStore(ref.watch(sharedPreferencesProvider)),
);

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(themeStoreProvider).themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(themeStoreProvider).setThemeMode(mode);
    state = mode;
  }
}
