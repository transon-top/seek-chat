import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'api/client.dart';
import 'app.dart';
import 'data/attachment_store.dart';
import 'data/chat_repository.dart';
import 'data/database.dart';
import 'settings/api_key_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase.open();
  final repository = ChatRepository(database);
  final attachmentStore = AttachmentStore();
  // 应用被杀后残留的 pending/streaming 回复在启动时统一置为 stopped。
  await repository.resetInterruptedReplies();
  try {
    await attachmentStore.cleanupOrphans(repository);
  } on FileSystemException {
    // 启动清理失败不阻塞应用，下次启动再试。
  }
  runApp(OpenChatApp(
    repository: repository,
    client: DeepSeekApiClient(),
    apiKeyStore: ApiKeyStore(),
    attachmentStore: attachmentStore,
  ));
}
