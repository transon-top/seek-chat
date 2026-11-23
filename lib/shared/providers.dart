import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/api/client.dart';
import '../shared/data/attachment_store.dart';
import '../shared/data/chat_repository.dart';
import '../shared/data/database.dart';
import '../shared/logging.dart';
import '../shared/security/api_key_store.dart';

/// ZH
/// 基础设施 Provider（architecture.md §2）。main() 与测试用 override 注入实例。
///
/// EN
/// Infrastructure Providers (architecture.md §2). main() and tests inject via overrides.
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

/// ZH
/// 是否已保存非空 API Key；设置页保存或清除后需 `invalidate`。
///
/// 读取失败按「无 Key」处理；界面在首次读取完成前按「有 Key」渲染。
///
/// EN
/// Whether a non-blank API Key is saved (invalidate after saving / clearing).
///
/// A failed read counts as "no key"; the UI renders as "has key" until the first read settles.
final hasApiKeyProvider = FutureProvider<bool>((ref) async {
  try {
    final apiKey = (await ref.watch(apiKeyStoreProvider).read())?.trim();
    return apiKey != null && apiKey.isNotEmpty;
  } on Object catch (error) {
    debugLog('reading api key failed', error);
    return false;
  }
});

final attachmentStoreProvider = Provider<AttachmentStore>(
  (ref) => AttachmentStore(),
);
