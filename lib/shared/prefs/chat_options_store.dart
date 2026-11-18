import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'preferences_provider.dart';

/// 输入区的深度思考 / 智能搜索开关（`search.md` §2）。
///
/// 默认关闭，按回复创建时快照；开关状态不进数据库。
class ChatOptionsStore {
  ChatOptionsStore(this._preferences);

  static const thinkingKey = 'chat.thinking';
  static const searchKey = 'chat.search';

  final SharedPreferences _preferences;

  bool get thinking => _preferences.getBool(thinkingKey) ?? false;
  bool get search => _preferences.getBool(searchKey) ?? false;

  Future<void> setThinking(bool value) =>
      _preferences.setBool(thinkingKey, value);

  Future<void> setSearch(bool value) => _preferences.setBool(searchKey, value);
}

final chatOptionsStoreProvider = Provider<ChatOptionsStore>(
  (ref) => ChatOptionsStore(ref.watch(sharedPreferencesProvider)),
);
