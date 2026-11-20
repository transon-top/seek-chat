import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'dev/mock_seed.dart';
import 'shared/providers.dart';
import 'shared/data/attachment_store.dart';
import 'shared/data/chat_repository.dart';
import 'shared/data/database.dart';
import 'shared/logging.dart';
import 'shared/prefs/preferences_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase.open();
  final repository = ChatRepository(database);
  final attachmentStore = AttachmentStore();
  // 应用被杀后残留的 pending/streaming 回复在启动时统一置为 stopped。
  await repository.resetInterruptedReplies();
  final preferences = await SharedPreferences.getInstance();
  if (kDebugMode) {
    try {
      // 历史样本先写，Markdown 样本保持最新，冷启动仍打开主样本会话。
      await seedHistorySamples(database, preferences);
      await seedMarkdownSamples(repository, preferences);
    } on Object catch (error) {
      // 样本写入失败不阻塞启动。
      debugLog('dev sample seed failed', error);
    }
  }
  try {
    await attachmentStore.cleanupOrphans(repository);
  } on FileSystemException catch (error) {
    // 启动清理失败不阻塞应用，下次启动再试。
    debugLog('attachment cleanup failed', error);
  }
  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        chatRepositoryProvider.overrideWithValue(repository),
        attachmentStoreProvider.overrideWithValue(attachmentStore),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const OpenChatApp(),
    ),
  );
}
