import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'dev/mock_seed.dart';
import 'dev/mock_stream_client.dart';
import 'shared/api/client.dart';
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
  // ZH
  // 应用被杀后残留的 pending/streaming 回复在启动时统一置为 stopped。
  //
  // EN
  // On startup, set leftover pending/streaming replies from a killed app to stopped.
  await repository.resetInterruptedReplies();
  final preferences = await SharedPreferences.getInstance();
  if (kDebugMode) {
    try {
      // ZH
      // 压测样本只在显式开启时写入，默认不污染日常开发数据。
      //
      // EN
      // Stress samples are written only when explicitly enabled, keeping daily dev data clean.
      if (const bool.fromEnvironment('SEEK_CHAT_STRESS_SEED')) {
        await seedStressSamples(database, preferences);
      }
      // ZH
      // 历史样本先写，Markdown 样本保持最新，冷启动仍打开主样本会话。
      //
      // EN
      // Write history samples first; Markdown samples stay newest so cold start opens the main one.
      await seedHistorySamples(database, preferences);
      await seedMarkdownSamples(repository, preferences);
    } on Object catch (error) {
      // ZH
      // 样本写入失败不阻塞启动。
      //
      // EN
      // A sample seed failure does not block startup.
      debugLog('dev sample seed failed', error);
    }
  }
  try {
    await attachmentStore.cleanupOrphans(repository);
  } on FileSystemException catch (error) {
    // ZH
    // 启动清理失败不阻塞应用，下次启动再试。
    //
    // EN
    // Startup cleanup failure does not block the app; retry on next launch.
    debugLog('attachment cleanup failed', error);
  }
  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        chatRepositoryProvider.overrideWithValue(repository),
        attachmentStoreProvider.overrideWithValue(attachmentStore),
        sharedPreferencesProvider.overrideWithValue(preferences),
        // ZH
        // 弱网流式样本：传输层换成按节奏吐 SSE 的 mock，不影响其他逻辑。
        //
        // EN
        // Slow-network streaming sample: replace the transport with a paced SSE mock, nothing else.
        if (kDebugMode && const bool.fromEnvironment('SEEK_CHAT_MOCK_STREAM'))
          apiClientProvider.overrideWith((ref) {
            final client = DeepSeekApiClient(
              httpClient: MockStreamClient(
                chunkDelay: Duration(
                  milliseconds: const int.fromEnvironment(
                    'SEEK_CHAT_MOCK_STREAM_DELAY_MS',
                    defaultValue: 150,
                  ),
                ),
              ),
            );
            ref.onDispose(client.close);
            return client;
          }),
      ],
      child: const SeekChatApp(),
    ),
  );
}
