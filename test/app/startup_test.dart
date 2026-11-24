import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:seek_chat/app/startup.dart';
import 'package:seek_chat/app/startup_failure_page.dart';
import 'package:seek_chat/features/chat/chat_page.dart';
import 'package:seek_chat/shared/data/attachment_store.dart';
import 'package:seek_chat/shared/data/chat_repository.dart';
import 'package:seek_chat/shared/data/database.dart';
import 'package:seek_chat/shared/data/local_data.dart';
import 'package:seek_chat/shared/prefs/theme_store.dart';
import 'package:seek_chat/shared/prefs/user_metadata_store.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/pump.dart';

/// ZH
/// 清除本地数据要覆盖的库文件：主库与旧库各带 `-journal` / `-wal` / `-shm`。
///
/// EN
/// Database files cleared by the recovery entry: main and legacy, each with sidecars.
const _databaseFiles = [
  databaseFileName,
  '$databaseFileName-journal',
  '$databaseFileName-wal',
  '$databaseFileName-shm',
  legacyDatabaseFileName,
  '$legacyDatabaseFileName-journal',
  '$legacyDatabaseFileName-wal',
  '$legacyDatabaseFileName-shm',
];

/// ZH
/// 记录 `close()` 时库文件是否还在，用于验证「先关连接再删文件」。
///
/// EN
/// Records whether the database file still existed at `close()`, proving the connection
/// closes before deletion.
class _RecordingDatabase extends AppDatabase {
  _RecordingDatabase(super.e, this.log, this.databaseFile);

  final List<String> log;
  final File databaseFile;

  @override
  Future<void> close() async {
    log.add('close:${databaseFile.existsSync()}');
    await super.close();
  }
}

void main() {
  final opened = <AppDatabase>[];
  late TestWidgetsFlutterBinding binding;
  late SharedPreferences preferences;
  late Directory supportDir;

  AppDatabase memoryDatabase() {
    final database = AppDatabase(NativeDatabase.memory());
    opened.add(database);
    return database;
  }

  StartupDeps deps({
    Future<SharedPreferences> Function()? loadPreferences,
    AppDatabase Function()? openDatabase,
    Future<void> Function(ChatRepository repository)? resetInterruptedReplies,
    Future<void> Function(
      AppDatabase database,
      ChatRepository repository,
      SharedPreferences preferences,
    )?
    seedDevData,
    Future<void> Function(
      AttachmentStore store,
      ChatRepository repository,
    )?
    cleanupAttachments,
    Future<Directory> Function()? supportDirectory,
    Future<void> Function(AppDatabase? database)? clearChatsAndAttachments,
  }) => StartupDeps(
    loadPreferences: loadPreferences ?? () async => preferences,
    openDatabase: openDatabase ?? memoryDatabase,
    resetInterruptedReplies:
        resetInterruptedReplies ?? (_) async {},
    seedDevData: seedDevData ?? (_, _, _) async {},
    cleanupAttachments: cleanupAttachments ?? (_, _) async {},
    supportDirectory: supportDirectory ?? () async => supportDir,
    clearChatsAndAttachments: clearChatsAndAttachments ?? (_) async {},
  );

  /// ZH
  /// 卸载应用根并泵一帧：drift 流在 `ProviderScope` 销毁时用零延时 Timer 收尾，
  /// 不泵这一帧测试框架会报「Timer is still pending」。
  ///
  /// EN
  /// Unmount the app root and pump once: drift streams finish with a zero-duration timer
  /// when the `ProviderScope` is disposed, and without this pump the test harness reports
  /// "Timer is still pending".
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  setUp(() async {
    binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.localesTestValue = const [Locale('zh')];
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    supportDir = await Directory.systemTemp.createTemp(
      'seek_chat_startup',
    );
  });

  tearDown(() async {
    for (final database in opened) {
      try {
        await database.close();
      } on Object {
        // ZH 迁移失败的实例可能已关闭。 / EN Already closed after a failed migration.
      }
    }
    opened.clear();
    binding.platformDispatcher.clearLocalesTestValue();
    binding.platformDispatcher.clearTextScaleFactorTestValue();
    await supportDir.delete(recursive: true);
  });

  group('bootstrap', () {
    test('reads preferences before opening the database', () async {
      final order = <String>[];
      final result = await bootstrap(
        deps(
          loadPreferences: () async {
            order.add('preferences');
            return preferences;
          },
          openDatabase: () {
            order.add('database');
            return memoryDatabase();
          },
        ),
      );
      expect(order, ['preferences', 'database']);
      expect(result.preferences, same(preferences));
    });

    test('blocking failures carry the database and preferences', () async {
      final database = memoryDatabase();
      StartupFailure? captured;
      try {
        await bootstrap(
          deps(
            openDatabase: () => database,
            resetInterruptedReplies: (_) async =>
                throw StateError('reset failed'),
          ),
        );
      } on StartupFailure catch (failure) {
        captured = failure;
      }
      expect(captured, isNotNull);
      expect(captured!.database, same(database));
      expect(captured.preferences, same(preferences));
    });

    test('a failing database factory leaves no database to close', () async {
      StartupFailure? captured;
      try {
        await bootstrap(
          deps(openDatabase: () => throw StateError('cannot open')),
        );
      } on StartupFailure catch (failure) {
        captured = failure;
      }
      expect(captured, isNotNull);
      expect(captured!.database, isNull);
    });

    test('preference failure is blocking and reads nothing', () async {
      StartupFailure? captured;
      try {
        await bootstrap(
          deps(loadPreferences: () async => throw StateError('no prefs')),
        );
      } on StartupFailure catch (failure) {
        captured = failure;
      }
      expect(captured, isNotNull);
      expect(captured!.preferences, isNull);
      expect(captured.database, isNull);
    });

    test('debug sample failure does not block startup', () async {
      final result = await bootstrap(
        deps(seedDevData: (_, _, _) async => throw StateError('seed failed')),
      );
      expect(result.database, isNotNull);
    });

    test('attachment cleanup failure does not block startup', () async {
      final result = await bootstrap(
        deps(
          cleanupAttachments: (_, _) async =>
              throw const FileSystemException('cleanup failed'),
        ),
      );
      expect(result.database, isNotNull);
    });
  });

  group('startup failure page', () {
    testWidgets('database failure shows the page with both actions', (
      tester,
    ) async {
      final root = await startupRoot(
        deps(openDatabase: () => throw StateError('db broken')),
        onStarted: (_) {},
      );
      await tester.pumpWidget(root);
      await tester.pumpAndSettle();

      expect(find.byType(StartupFailureApp), findsOneWidget);
      expect(find.text('无法打开 SeekChat'), findsOneWidget);
      expect(find.textContaining('本地数据读取失败'), findsOneWidget);
      expect(find.byKey(const Key('startup-retry')), findsOneWidget);
      expect(find.byKey(const Key('startup-clear-data')), findsOneWidget);
      // ZH debug 构建附原始异常。 / EN Debug builds show the raw error.
      expect(find.textContaining('db broken'), findsOneWidget);
    });

    testWidgets('retry reruns the chain and starts the app', (tester) async {
      var databases = 0;
      var resets = 0;
      BootstrapResult? started;
      final root = await startupRoot(
        deps(
          openDatabase: () {
            databases++;
            return memoryDatabase();
          },
          resetInterruptedReplies: (_) async {
            resets++;
            if (resets == 1) throw StateError('reset failed');
          },
        ),
        onStarted: (result) => started = result,
      );
      await tester.pumpWidget(root);
      await tester.pumpAndSettle();
      expect(find.byType(StartupFailureApp), findsOneWidget);

      await tester.tap(find.byKey(const Key('startup-retry')));
      await tester.pumpAndSettle();

      expect(databases, 2);
      expect(started, isNotNull);

      await tester.pumpWidget(appRoot(started!));
      await pumpUntil(
        tester,
        () => find.byType(ChatPage).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 5),
      );
      expect(find.byType(ChatPage), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('failed preferences fall back to system theme and language', (
      tester,
    ) async {
      final root = await startupRoot(
        deps(loadPreferences: () async => throw StateError('no prefs')),
        onStarted: (_) {},
      );
      await tester.pumpWidget(root);
      await tester.pumpAndSettle();

      final app = tester.widget<ShadApp>(find.byType(ShadApp));
      expect(app.themeMode, ThemeMode.system);
      expect(app.locale, isNull);
      expect(find.text('无法打开 SeekChat'), findsOneWidget);
    });

    testWidgets('stored preferences shape the failure page', (tester) async {
      SharedPreferences.setMockInitialValues({
        ThemeStore.themeModeKey: 'dark',
        UserMetadataStore.localeKey: 'en',
      });
      preferences = await SharedPreferences.getInstance();
      final root = await startupRoot(
        deps(openDatabase: () => throw StateError('db broken')),
        onStarted: (_) {},
      );
      await tester.pumpWidget(root);
      await tester.pumpAndSettle();

      final app = tester.widget<ShadApp>(find.byType(ShadApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.locale, const Locale('en'));
      expect(find.text('Cannot open SeekChat'), findsOneWidget);
    });

    testWidgets('attachment cleanup failure still opens the app', (
      tester,
    ) async {
      final root = await startupRoot(
        deps(
          cleanupAttachments: (_, _) async =>
              throw const FileSystemException('cleanup failed'),
        ),
        onStarted: (_) {},
      );
      await tester.pumpWidget(root);
      await pumpUntil(
        tester,
        () => find.byType(ChatPage).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 5),
      );
      expect(find.byType(StartupFailureApp), findsNothing);
      expect(find.byType(ChatPage), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('debug sample failure still opens the app', (tester) async {
      final root = await startupRoot(
        deps(seedDevData: (_, _, _) async => throw StateError('seed failed')),
        onStarted: (_) {},
      );
      await tester.pumpWidget(root);
      await pumpUntil(
        tester,
        () => find.byType(ChatPage).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 5),
      );
      expect(find.byType(StartupFailureApp), findsNothing);
      expect(find.byType(ChatPage), findsOneWidget);
      await unmount(tester);
    });
  });

  group('clear local data', () {
    Future<void> pumpFailurePage(
      WidgetTester tester, {
      required StartupDeps dependencies,
      AppStarted? onStarted,
    }) async {
      final root = await startupRoot(
        dependencies,
        onStarted: onStarted ?? (_) {},
      );
      await tester.pumpWidget(root);
      await tester.pumpAndSettle();
      expect(find.byType(StartupFailureApp), findsOneWidget);
    }

    testWidgets('confirm clears data and retries automatically', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        ThemeStore.themeModeKey: 'dark',
        'keep.me': 'yes',
      });
      preferences = await SharedPreferences.getInstance();

      var resets = 0;
      final cleared = <AppDatabase?>[];
      BootstrapResult? started;
      await pumpFailurePage(
        tester,
        dependencies: deps(
          resetInterruptedReplies: (_) async {
            resets++;
            if (resets == 1) throw StateError('reset failed');
          },
          clearChatsAndAttachments: (database) async => cleared.add(database),
        ),
        onStarted: (result) => started = result,
      );

      await tester.tap(find.byKey(const Key('startup-clear-data')));
      await tester.pumpAndSettle();
      expect(find.text('清除本地会话与附件？'), findsOneWidget);
      expect(find.textContaining('设置与 API Key 保留'), findsOneWidget);

      await tester.tap(find.byKey(const Key('startup-clear-data-confirm')));
      await pumpUntil(
        tester,
        () => started != null,
        timeout: const Duration(seconds: 5),
      );

      expect(cleared.single, isNotNull);
      expect(started, isNotNull);
      // ZH 设置保留。 / EN Settings are kept.
      expect(preferences.getString(ThemeStore.themeModeKey), 'dark');
      expect(preferences.getString('keep.me'), 'yes');
    });

    testWidgets('cancelling clears nothing', (tester) async {
      var clears = 0;
      await pumpFailurePage(
        tester,
        dependencies: deps(
          openDatabase: () => throw StateError('db broken'),
          clearChatsAndAttachments: (_) async => clears++,
        ),
      );

      await tester.tap(find.byKey(const Key('startup-clear-data')));
      await tester.pumpAndSettle();
      expect(find.text('清除本地会话与附件？'), findsOneWidget);
      for (final key in const [
        'startup-clear-data-cancel',
        'startup-clear-data-confirm',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }

      await tester.tap(find.byKey(const Key('startup-clear-data-cancel')));
      await tester.pumpAndSettle();

      expect(clears, 0);
      expect(find.byType(StartupFailureApp), findsOneWidget);
    });

    testWidgets('a failed clear stays on the page and does not retry', (
      tester,
    ) async {
      var databases = 0;
      await pumpFailurePage(
        tester,
        dependencies: deps(
          openDatabase: () {
            databases++;
            if (databases == 1) throw StateError('db broken');
            return memoryDatabase();
          },
          clearChatsAndAttachments: (_) async =>
              throw const FileSystemException('no access'),
        ),
      );

      await tester.tap(find.byKey(const Key('startup-clear-data')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startup-clear-data-confirm')));
      await pumpUntil(
        tester,
        () => find.text('清除失败，请重试。').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 5),
      );

      expect(find.text('清除失败，请重试。'), findsOneWidget);
      expect(find.byType(StartupFailureApp), findsOneWidget);
      // ZH 失败后不自动重试。 / EN No automatic retry after a failed clear.
      expect(databases, 1);
    });

    test(
      'closes the database, deletes files and keeps settings',
      () async {
        SharedPreferences.setMockInitialValues({
          ThemeStore.themeModeKey: 'dark',
          'keep.me': 'yes',
        });
        preferences = await SharedPreferences.getInstance();
        final attachments = Directory(
          p.join(supportDir.path, AttachmentStore.directoryName),
        );
        await attachments.create();
        await File(p.join(attachments.path, 'a1')).writeAsString('x');
        for (final name in _databaseFiles) {
          await File(p.join(supportDir.path, name)).writeAsString('x');
        }
        final databaseFile = File(
          p.join(supportDir.path, databaseFileName),
        );
        final log = <String>[];
        final database = _RecordingDatabase(
          NativeDatabase.memory(),
          log,
          databaseFile,
        );
        opened.add(database);

        await clearChatsAndAttachments(
          database: database,
          supportDirectory: () async => supportDir,
        );

        expect(log.first, 'close:true');
        for (final name in _databaseFiles) {
          expect(
            File(p.join(supportDir.path, name)).existsSync(),
            isFalse,
            reason: name,
          );
        }
        expect(attachments.existsSync(), isFalse);
        expect(preferences.getString(ThemeStore.themeModeKey), 'dark');
        expect(preferences.getString('keep.me'), 'yes');
      },
    );
  });

  group('accessibility', () {
    testWidgets('title is a header, body is a live region, targets are 48', (
      tester,
    ) async {
      final root = await startupRoot(
        deps(openDatabase: () => throw StateError('db broken')),
        onStarted: (_) {},
      );
      await tester.pumpWidget(root);
      await tester.pumpAndSettle();

      final title = tester.getSemantics(
        find.byKey(const Key('startup-title')),
      );
      expect(title.getSemanticsData().flagsCollection.isHeader, isTrue);
      final body = tester.getSemantics(find.byKey(const Key('startup-body')));
      expect(body.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      for (final key in const ['startup-retry', 'startup-clear-data']) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
      }
    });

    testWidgets('grows with 200% text scale and does not disappear', (
      tester,
    ) async {
      binding.platformDispatcher.textScaleFactorTestValue = 2;
      final root = await startupRoot(
        deps(openDatabase: () => throw StateError('db broken')),
        onStarted: (_) {},
      );
      await tester.pumpWidget(root);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('无法打开 SeekChat'), findsOneWidget);
      for (final key in const ['startup-retry', 'startup-clear-data']) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }

      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(StartupFailureApp), findsOneWidget);
    });
  });

  test('a failed migration rolls back and the next open completes it', () async {
    final file = File(p.join(supportDir.path, databaseFileName));
    final raw = sqlite.sqlite3.open(file.path);
    // ZH 视图让 `ALTER TABLE` 失败，模拟迁移中途失败。
    // EN A view makes `ALTER TABLE` fail, simulating a mid-migration failure.
    raw.execute('CREATE VIEW sessions AS SELECT 1 AS id');
    raw.userVersion = 1;
    raw.close();

    final first = AppDatabase(NativeDatabase(file));
    await expectLater(first.select(first.sessions).get(), throwsA(anything));
    await first.close();

    final check = sqlite.sqlite3.open(file.path);
    expect(check.userVersion, 1);
    check.execute('DROP VIEW sessions');
    check.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        root_message_id TEXT
      )
    ''');
    check.close();

    final second = AppDatabase(NativeDatabase(file));
    await second.select(second.sessions).get();
    final version = await second.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 2);
    final columns = await second
        .customSelect('PRAGMA table_info(sessions)')
        .get();
    expect(columns.map((row) => row.data['name']), contains('pinned'));
    await second.close();
  });
}
