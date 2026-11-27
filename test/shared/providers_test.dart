import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seek_chat/shared/providers.dart';
import 'package:seek_chat/shared/security/api_key_store.dart';

import '../support/fake_api_key_store.dart';

class _ThrowingStore extends FakeApiKeyStore {
  @override
  Future<String?> read() => Future.error(StateError('keychain unavailable'));
}

void main() {
  Future<bool> hasKey(ApiKeyStore store) async {
    final container = ProviderContainer(
      overrides: [apiKeyStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container.read(hasApiKeyProvider.future);
  }

  test('a stored key counts, blank counts as none', () async {
    expect(await hasKey(FakeApiKeyStore('sk-good')), isTrue);
    expect(await hasKey(FakeApiKeyStore('   ')), isFalse);
    expect(await hasKey(FakeApiKeyStore()), isFalse);
  });

  test('a storage read failure counts as no key', () async {
    expect(await hasKey(_ThrowingStore()), isFalse);
  });
}
