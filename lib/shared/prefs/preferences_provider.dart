import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机设置存储。`SharedPreferences.getInstance()` 是异步的，main() 在启动时
/// 覆盖本 Provider；测试也可用内存实现覆盖。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider 必须在启动或测试时覆盖'),
);
