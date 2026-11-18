import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API Key 的系统安全存储封装（`api.md` §8）。Key 不落日志。
class ApiKeyStore {
  static const String storageKey = 'deepseek_api_key';

  /// iOS：设备首次解锁后可读，且不随备份迁移到新设备（architecture.md §7）。
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<String?> read() => _storage.read(key: storageKey);

  Future<void> write(String apiKey) =>
      _storage.write(key: storageKey, value: apiKey);

  Future<void> clear() => _storage.delete(key: storageKey);
}
