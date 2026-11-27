import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dev/mock_seed.dart';
import '../dev/mock_speech.dart';
import '../dev/mock_stream_client.dart';
import '../dev/screenshot_samples.dart';
import '../features/chat/speech/speech_controller.dart';
import '../shared/api/client.dart';
import '../shared/data/attachment_store.dart';
import '../shared/data/chat_repository.dart';
import '../shared/data/database.dart';
import '../shared/data/local_data.dart' as local_data;
import '../shared/logging.dart';
import '../shared/prefs/preferences_provider.dart';
import '../shared/providers.dart';
import 'app.dart';
import 'startup_failure_page.dart';

/// ZH
/// 启动链成功后的真实依赖：`runApp` 前的四个基础设施实例。
///
/// EN
/// Dependencies of a successful startup: the four infrastructure instances used before `runApp`.
class BootstrapResult {
  const BootstrapResult({
    required this.database,
    required this.repository,
    required this.attachmentStore,
    required this.preferences,
  });

  final AppDatabase database;
  final ChatRepository repository;
  final AttachmentStore attachmentStore;
  final SharedPreferences preferences;
}

/// ZH
/// 阻塞启动的失败。携带已读到的偏好与已创建的数据库实例，供错误页决定主题、
/// 语言与清除数据前先关闭连接。
///
/// EN
/// A startup-blocking failure. Carries the preferences read so far and the database
/// instance created so far, so the failure page can pick theme/language and close the
/// connection before clearing data.
class StartupFailure implements Exception {
  StartupFailure(
    this.error,
    this.stackTrace, {
    required this.database,
    required this.preferences,
  });

  final Object error;
  final StackTrace stackTrace;
  final AppDatabase? database;
  final SharedPreferences? preferences;

  @override
  String toString() => 'StartupFailure: $error';
}

/// ZH
/// 启动成功后的回调：真实 `main()` 用它二次 `runApp` 应用；测试用替身记录结果。
///
/// EN
/// Called after a successful startup: real `main()` uses it to `runApp` the app a second
/// time; tests record the result with a stand-in.
typedef AppStarted = void Function(BootstrapResult result);

/// ZH
/// 启动链的可注入依赖（票 03）：数据库工厂、偏好加载、残留回复收尾、debug 样本、
/// 附件清理与支持目录。
///
/// EN
/// Injectable startup dependencies (ticket 03): database factory, preference loading,
/// interrupted-reply reset, debug samples, attachment cleanup and the support directory.
class StartupDeps {
  const StartupDeps({
    required this.loadPreferences,
    required this.openDatabase,
    required this.resetInterruptedReplies,
    required this.seedDevData,
    required this.cleanupAttachments,
    required this.supportDirectory,
    required this.clearChatsAndAttachments,
  });

  final Future<SharedPreferences> Function() loadPreferences;
  final AppDatabase Function() openDatabase;
  final Future<void> Function(ChatRepository repository) resetInterruptedReplies;
  final Future<void> Function(
    AppDatabase database,
    ChatRepository repository,
    SharedPreferences preferences,
  )
  seedDevData;
  final Future<void> Function(
    AttachmentStore store,
    ChatRepository repository,
  )
  cleanupAttachments;
  final Future<Directory> Function() supportDirectory;

  /// ZH
  /// 启动失败页的恢复操作：关闭数据库并删除本地会话与附件。
  ///
  /// EN
  /// Recovery action on the startup failure page: close the database and delete local
  /// chats and attachments.
  final Future<void> Function(AppDatabase? database) clearChatsAndAttachments;

  factory StartupDeps.real() {
    // ZH
    // 启动链与清除数据用同一个支持目录来源。
    //
    // EN
    // The startup chain and the recovery action share one support-directory source.
    Future<Directory> supportDirectory() => getApplicationSupportDirectory();
    return StartupDeps(
      loadPreferences: SharedPreferences.getInstance,
      openDatabase: AppDatabase.open,
      resetInterruptedReplies: (repository) =>
          repository.resetInterruptedReplies(),
      seedDevData: _seedDevData,
      cleanupAttachments: (store, repository) =>
          store.cleanupOrphans(repository),
      supportDirectory: supportDirectory,
      clearChatsAndAttachments: (database) =>
          local_data.clearChatsAndAttachments(
            database: database,
            supportDirectory: supportDirectory,
          ),
    );
  }
}

/// ZH
/// debug 样本：只在 debug 构建写入；压测样本需显式开启。
///
/// EN
/// Debug samples: written only in debug builds; stress samples need an explicit opt-in.
Future<void> _seedDevData(
  AppDatabase database,
  ChatRepository repository,
  SharedPreferences preferences,
) async {
  if (!kDebugMode) return;
  if (const bool.fromEnvironment('SEEK_CHAT_SCREENSHOT_SEED')) {
    await seedScreenshotSamples(database, preferences);
    return;
  }
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
}

/// ZH
/// 从头跑完整条启动链：偏好 → 数据库与残留回复收尾 → debug 样本 → 附件清理。
///
/// 偏好、数据库与收尾失败抛 [StartupFailure]；样本与附件清理失败只写 debug 日志，
/// 不阻塞启动。重试必须重新调用本函数以获得新的数据库实例。
///
/// EN
/// Run the whole startup chain from scratch: preferences → database and interrupted-reply
/// reset → debug samples → attachment cleanup.
///
/// Preference, database and reset failures throw [StartupFailure]; sample and cleanup
/// failures only log and never block startup. A retry must call this again to get a new
/// database instance.
Future<BootstrapResult> bootstrap(StartupDeps deps) async {
  final SharedPreferences preferences;
  try {
    preferences = await deps.loadPreferences();
  } on Object catch (error, stackTrace) {
    debugLog('loading preferences failed', error);
    throw StartupFailure(
      error,
      stackTrace,
      database: null,
      preferences: null,
    );
  }

  AppDatabase? database;
  try {
    database = deps.openDatabase();
    final repository = ChatRepository(database);
    await deps.resetInterruptedReplies(repository);
    try {
      await deps.seedDevData(database, repository, preferences);
    } on Object catch (error) {
      // ZH
      // 样本写入失败不阻塞启动。
      //
      // EN
      // A sample seed failure does not block startup.
      debugLog('dev sample seed failed', error);
    }
    final attachmentStore = AttachmentStore(
      supportDirectory: deps.supportDirectory,
    );
    try {
      await deps.cleanupAttachments(attachmentStore, repository);
    } on Object catch (error) {
      // ZH
      // 启动清理失败不阻塞应用，下次启动再试。
      //
      // EN
      // Startup cleanup failure does not block the app; retry on next launch.
      debugLog('attachment cleanup failed', error);
    }
    return BootstrapResult(
      database: database,
      repository: repository,
      attachmentStore: attachmentStore,
      preferences: preferences,
    );
  } on Object catch (error, stackTrace) {
    debugLog('startup failed', error);
    throw StartupFailure(
      error,
      stackTrace,
      database: database,
      preferences: preferences,
    );
  }
}

/// ZH
/// 真实应用根：注入四个基础设施实例（与调试用流式样本）。
///
/// EN
/// Root of the real app: injects the four infrastructure instances (and the debug stream sample).
Widget appRoot(BootstrapResult result) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(result.database),
    chatRepositoryProvider.overrideWithValue(result.repository),
    attachmentStoreProvider.overrideWithValue(result.attachmentStore),
    sharedPreferencesProvider.overrideWithValue(result.preferences),
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
    // ZH
    // 语音替身：固定转写文本与 Key，用来观察识别后浮层与自动发送的时序。
    //
    // EN
    // Voice stand-in: fixed transcript and key, to watch overlay and auto-send timing.
    if (kDebugMode && const bool.fromEnvironment('SEEK_CHAT_MOCK_SPEECH')) ...[
      speechApiProvider.overrideWith((ref) {
        final api = MockSpeechApi(
          delay: Duration(
            milliseconds: const int.fromEnvironment(
              'SEEK_CHAT_MOCK_SPEECH_DELAY_MS',
              defaultValue: 800,
            ),
          ),
        );
        ref.onDispose(api.close);
        return api;
      }),
      apiKeyStoreProvider.overrideWith((ref) => MockApiKeyStore()),
      speechRecorderProvider.overrideWith((ref) => MockSpeechRecorder()),
    ],
  ],
  child: const SeekChatApp(),
);

/// ZH
/// 启动入口：成功返回真实应用根，失败返回 `ProviderScope` 外的启动失败页。
///
/// 失败页重试成功后经 [onStarted] 二次 `runApp`（默认实现）。
///
/// EN
/// Startup entry: returns the real app root on success, or the failure page outside any
/// `ProviderScope` on failure.
///
/// A successful retry calls `runApp` a second time through [onStarted] (the default).
Future<Widget> startupRoot(StartupDeps deps, {AppStarted? onStarted}) async {
  try {
    return appRoot(await bootstrap(deps));
  } on StartupFailure catch (failure) {
    return StartupFailureApp(
      failure: failure,
      deps: deps,
      onStarted: onStarted ?? (result) => runApp(appRoot(result)),
    );
  }
}
