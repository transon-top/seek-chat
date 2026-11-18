import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/api/client.dart';
import '../shared/data/attachment_store.dart';
import '../shared/data/chat_repository.dart';
import '../shared/data/database.dart';
import '../shared/security/api_key_store.dart';

/// 基础设施 Provider（architecture.md §2）。main() 与测试用 override 注入实例。
final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase.open());

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(appDatabaseProvider)),
);

final apiClientProvider = Provider<DeepSeekApiClient>((ref) {
  final client = DeepSeekApiClient();
  ref.onDispose(client.close);
  return client;
});

final apiKeyStoreProvider = Provider<ApiKeyStore>((ref) => ApiKeyStore());

final attachmentStoreProvider = Provider<AttachmentStore>(
  (ref) => AttachmentStore(),
);
