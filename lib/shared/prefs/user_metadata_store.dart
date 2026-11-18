import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/json.dart';
import '../models/location.dart';
import 'preferences_provider.dart';

/// 作为用户元信息传给模型的语言与所在地（`user-metadata.md`）。
final class UserMetadata {
  const UserMetadata({
    required this.locale,
    required this.location,
    required this.systemChinese,
  });

  /// 生效中的界面语言代码：`zh` 或 `en`。
  final String locale;

  /// 未选择时为 null；元信息里对应字段留空。
  final UserLocation? location;

  /// 系统语言是否中文；只决定所在地选择器的形态，不随应用语言变化。
  final bool systemChinese;
}

/// 语言与所在地的本地持久化。缺省时语言跟随系统。
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

  Future<void> setLocale(String value) =>
      _preferences.setString(localeKey, value);

  Future<void> setLocation(UserLocation? value) => value == null
      ? _preferences.remove(locationKey)
      : _preferences.setString(locationKey, jsonEncode(value.toJson()));
}

final userMetadataStoreProvider = Provider<UserMetadataStore>(
  (ref) => UserMetadataStore(ref.watch(sharedPreferencesProvider)),
);

/// 系统首选语言；所在地的存留规则与选择器形态都由它决定。
final systemLanguageCodeProvider = Provider<String>((ref) {
  final locales = WidgetsBinding.instance.platformDispatcher.locales;
  return locales.isEmpty ? 'en' : locales.first.languageCode;
});

/// 设置页与聊天请求共用的用户元信息；切换后只影响之后创建的回复。
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
    // chat-demo `initialLocation`：按系统语言裁剪存量；非中文系统只保留国家。
    final location = stored == null
        ? null
        : systemChinese
        ? (stored.region == 'CN' ? stored : null)
        : UserLocation(region: stored.region);
    return UserMetadata(
      locale: _store.locale ?? (systemChinese ? 'zh' : 'en'),
      location: location,
      systemChinese: systemChinese,
    );
  }

  Future<void> setLocale(String locale) async {
    await _store.setLocale(locale);
    state = UserMetadata(
      locale: locale,
      location: state.location,
      systemChinese: state.systemChinese,
    );
  }

  Future<void> setLocation(UserLocation? location) async {
    await _store.setLocation(location);
    state = UserMetadata(
      locale: state.locale,
      location: location,
      systemChinese: state.systemChinese,
    );
  }
}
