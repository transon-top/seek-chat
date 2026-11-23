import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/json.dart';
import '../models/location.dart';
import 'preferences_provider.dart';

/// ZH
/// 作为用户元信息传给模型的语言与所在地（`user-metadata.md`）。
///
/// EN
/// Language and location passed to the model as User Metadata (`user-metadata.md`).
final class UserMetadata {
  const UserMetadata({
    required this.locale,
    required this.languageChoice,
    required this.location,
    required this.systemChinese,
  });

  /// ZH
  /// 生效中的界面语言代码：`zh` 或 `en`。
  ///
  /// EN
  /// Active UI language code: `zh` or `en`.
  final String locale;

  /// ZH
  /// 显式选择的语言；null 表示跟随系统。
  ///
  /// EN
  /// Explicitly chosen language; null means follow the system.
  final String? languageChoice;

  /// ZH
  /// 未选择时为 null；元信息里对应字段留空。
  ///
  /// EN
  /// Null when not chosen; the corresponding field is left empty in User Metadata.
  final UserLocation? location;

  /// ZH
  /// 系统语言是否中文；只决定所在地选择器的形态，不随应用语言变化。
  ///
  /// EN
  /// Whether the system language is Chinese; only shapes the location picker, not the app language.
  final bool systemChinese;
}

/// ZH
/// 语言与所在地的本地持久化。缺省时语言跟随系统。
///
/// EN
/// Local persistence for language and location. Language follows the system by default.
class UserMetadataStore {
  UserMetadataStore(this._preferences);

  static const localeKey = 'user.locale';
  static const locationKey = 'user.location';

  final SharedPreferences _preferences;

  String? get locale {
    final value = _preferences.getString(localeKey);
    return value == 'zh' || value == 'en' ? value : null;
  }

  UserLocation? get location =>
      normalizeLocation(decodeJsonSource(_preferences.getString(locationKey)));

  Future<void> setLocale(String? value) => value == null
      ? _preferences.remove(localeKey)
      : _preferences.setString(localeKey, value);

  Future<void> setLocation(UserLocation? value) => value == null
      ? _preferences.remove(locationKey)
      : _preferences.setString(locationKey, jsonEncode(value.toJson()));
}

final userMetadataStoreProvider = Provider<UserMetadataStore>(
  (ref) => UserMetadataStore(ref.watch(sharedPreferencesProvider)),
);

/// ZH
/// 系统首选语言；所在地的存留规则与选择器形态都由它决定。
///
/// EN
/// System preferred language; it decides location retention rules and picker shape.
final systemLanguageCodeProvider = Provider<String>((ref) {
  final locales = WidgetsBinding.instance.platformDispatcher.locales;
  return locales.isEmpty ? 'en' : locales.first.languageCode;
});

/// ZH
/// 设置页与聊天请求共用的用户元信息；切换后只影响之后创建的回复。
///
/// EN
/// User Metadata shared by settings and chat requests; affects only later replies.
final userMetadataProvider =
    NotifierProvider<UserMetadataNotifier, UserMetadata>(
      UserMetadataNotifier.new,
    );

class UserMetadataNotifier extends Notifier<UserMetadata> {
  late final UserMetadataStore _store;

  @override
  UserMetadata build() {
    _store = ref.read(userMetadataStoreProvider);
    final systemChinese = isChineseLanguage(
      ref.read(systemLanguageCodeProvider),
    );
    final stored = _store.location;
    // ZH
    // chat-demo `initialLocation`：按系统语言裁剪存量；非中文系统只保留国家。
    //
    // EN
    // Trim location by system language (chat-demo `initialLocation`); non-Chinese: country only.
    final location = stored == null
        ? null
        : systemChinese
        ? (stored.region == 'CN' ? stored : null)
        : UserLocation(region: stored.region);
    final choice = _store.locale;
    return UserMetadata(
      locale: choice ?? (systemChinese ? 'zh' : 'en'),
      languageChoice: choice,
      location: location,
      systemChinese: systemChinese,
    );
  }

  /// ZH
  /// 传 null 表示跟随系统。
  ///
  /// EN
  /// Passing null means follow the system.
  Future<void> setLocale(String? locale) async {
    await _store.setLocale(locale);
    state = UserMetadata(
      locale: locale ?? (state.systemChinese ? 'zh' : 'en'),
      languageChoice: locale,
      location: state.location,
      systemChinese: state.systemChinese,
    );
  }

  Future<void> setLocation(UserLocation? location) async {
    await _store.setLocation(location);
    state = UserMetadata(
      locale: state.locale,
      languageChoice: state.languageChoice,
      location: location,
      systemChinese: state.systemChinese,
    );
  }
}
