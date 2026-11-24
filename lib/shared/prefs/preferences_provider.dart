import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ZH
/// 本机设置存储。`SharedPreferences.getInstance()` 是异步的，main() 在启动时
/// 覆盖本 Provider；测试也可用内存实现覆盖。
///
/// EN
/// Local settings storage. `SharedPreferences.getInstance()` is asynchronous, so
/// main() overrides this Provider at startup; tests can also override it with an
/// in-memory implementation.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider 必须在启动或测试时覆盖'),
);
