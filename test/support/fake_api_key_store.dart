import 'package:seek_chat/shared/security/api_key_store.dart';

class FakeApiKeyStore implements ApiKeyStore {
  FakeApiKeyStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String apiKey) async => value = apiKey;

  @override
  Future<void> clear() async => value = null;
}
