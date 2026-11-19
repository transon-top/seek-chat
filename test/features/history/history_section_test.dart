import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/history/history_files.dart';
import 'package:open_chat/features/history/history_section.dart';
import 'package:open_chat/features/history/history_service.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/data/attachment_store.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/models/types.dart';

void main() {
  late Directory support;
  late AppDatabase db;
  late ChatRepository repository;
  late AttachmentStore store;
  late HistoryService service;
  late _FakeFiles files;
  var stopped = 0;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('open_chat_history_ui_');
    db = AppDatabase(NativeDatabase.memory());
    repository = ChatRepository(db);
    store = AttachmentStore(supportDirectory: () async => support);
    service = HistoryService(repository, store);
    files = _FakeFiles();
    stopped = 0;
  });

  tearDown(() async {
    await db.close();
    await support.delete(recursive: true);
  });

  Future<Session> seed() async {
    final session = await repository.createSession();
    await repository.renameSession(session.id, 'Seeded');
    final user = await repository.addUserMessage(
      sessionId: session.id,
      text: 'question',
    );
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: user.id,
      model: ChatModel.deepseekFlash,
      thinking: false,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: const [TextBlock(text: 'answer')],
    );
    return session;
  }

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyServiceProvider.overrideWithValue(service),
          historyFilesProvider.overrideWithValue(files),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShadTheme(
            data: buildShadTheme(brightness: Brightness.light, chinese: true),
            child: ShadToaster(
              child: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: HistorySection(stopGeneration: () => stopped++),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('exports the current history to the picked save target', (
    tester,
  ) async {
    await seed();
    await pumpSection(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, '导出'));
    await tester.pumpAndSettle();

    expect(files.savedName, endsWith('.zip'));
    expect(files.savedBytes, isNotNull);
    expect(files.savedBytes, isNotEmpty);
    expect(find.text('导出文件已保存'), findsOneWidget);
  });

  testWidgets('confirms an import, replaces data and reports the count', (
    tester,
  ) async {
    final seeded = await seed();
    final exported = await service.exportArchive(notice: (_) => null);
    files.pickBytes = exported.bytes;
    final other = await repository.createSession();

    await pumpSection(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '选择文件'));
    await tester.pumpAndSettle();
    expect(find.text('确认导入历史对话？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '确认导入'));
    await tester.pumpAndSettle();

    expect(stopped, 1);
    expect((await repository.listSessions()).single.id, seeded.id);
    expect(await repository.getSession(other.id), isNull);
    expect(find.text('已导入 1 个对话'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation leaves data and generation alone', (
    tester,
  ) async {
    final seeded = await seed();
    final exported = await service.exportArchive(notice: (_) => null);
    files.pickBytes = exported.bytes;

    await pumpSection(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '选择文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(stopped, 0);
    expect((await repository.listSessions()).single.id, seeded.id);
  });

  testWidgets('reports a picker failure without touching history', (
    tester,
  ) async {
    await seed();
    files.throwPick = true;

    await pumpSection(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '选择文件'));
    await tester.pumpAndSettle();

    expect(find.text('文件导入失败，可能是格式错误或使用了旧版导出文件。'), findsOneWidget);
    expect((await repository.listSessions()), hasLength(1));
  });

  testWidgets('a cancelled save target is silent', (tester) async {
    await seed();
    files.saveResult = false;

    await pumpSection(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '导出'));
    await tester.pumpAndSettle();

    expect(find.text('导出文件已保存'), findsNothing);
    expect(find.text('导出失败，请重试'), findsNothing);
    expect(files.savedBytes, isNotEmpty);
  });

  testWidgets('reports an export failure', (tester) async {
    await seed();
    files.throwSave = true;

    await pumpSection(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '导出'));
    await tester.pumpAndSettle();

    expect(find.text('导出失败，请重试'), findsOneWidget);
  });

  testWidgets('shows the specific import error and keeps the old history', (
    tester,
  ) async {
    final seeded = await seed();
    files.pickBytes = Uint8List.fromList([1, 2, 3, 4]);

    await pumpSection(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, '选择文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认导入'));
    await tester.pumpAndSettle();

    expect(stopped, 0);
    expect((await repository.listSessions()).single.id, seeded.id);
    expect(find.text('无法识别该文件，请选择 DeepSeek 导出的历史对话 ZIP 文件'), findsOneWidget);
  });
}

final class _FakeFiles implements HistoryFiles {
  Uint8List? pickBytes;
  String? savedName;
  Uint8List? savedBytes;
  bool throwPick = false;
  bool throwSave = false;
  bool saveResult = true;

  @override
  Future<Uint8List?> pickZip() async {
    if (throwPick) throw StateError('picker failed');
    return pickBytes;
  }

  @override
  Future<bool> saveZip({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (throwSave) throw StateError('save failed');
    savedName = fileName;
    savedBytes = bytes;
    return saveResult;
  }
}
