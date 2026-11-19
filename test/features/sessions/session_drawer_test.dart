import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/sessions/session_drawer.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

SessionSummary session(String id, DateTime updatedAt) => SessionSummary(
  id: id,
  title: id,
  createdAt: updatedAt,
  updatedAt: updatedAt,
);

void main() {
  test('groups sessions into today, yesterday, last 7 days and earlier', () {
    final now = DateTime(2026, 11, 19, 12);
    final sessions = [
      session('today', DateTime(2026, 11, 19, 9)),
      session('yesterday', DateTime(2026, 11, 18, 23)),
      session('threeDays', DateTime(2026, 11, 16, 8)),
      session('sevenDays', DateTime(2026, 11, 12, 8)),
      session('older', DateTime(2026, 11, 11, 8)),
    ];

    final groups = groupSessions(sessions, now);

    expect(groups.map((group) => group.$1), [
      SessionGroup.today,
      SessionGroup.yesterday,
      SessionGroup.last7Days,
      SessionGroup.earlier,
    ]);
    expect(groups[2].$2.map((item) => item.id), ['threeDays', 'sevenDays']);
    expect(groups[3].$2.single.id, 'older');
  });

  test('keeps input order inside a group and skips empty groups', () {
    final now = DateTime(2026, 11, 19, 12);
    final sessions = [
      session('newer', DateTime(2026, 11, 19, 11)),
      session('older', DateTime(2026, 11, 19, 8)),
    ];

    final groups = groupSessions(sessions, now);

    expect(groups, hasLength(1));
    expect(groups.single.$2.map((item) => item.id), ['newer', 'older']);
  });

  testWidgets('shows the load failure with a retry action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionsProvider.overrideWith(
            (ref) => Stream<List<SessionSummary>>.error(
              StateError('session list failed'),
            ),
          ),
        ],
        child: ShadApp(
          locale: const Locale('zh'),
          theme: buildShadTheme(brightness: Brightness.light, chinese: true),
          localizationsDelegates: appLocalizationDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SessionDrawer(
              currentSessionId: null,
              onOpen: (_) {},
              onNewChat: () {},
              onOpenSettings: () {},
              cancelSession: (_) {},
              onDeleted: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法加载会话'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('无法加载会话'), findsOneWidget);
  });

  testWidgets(
    'inline rename trims, ignores empty input and cancels on escape',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final repository = ChatRepository(db);
      final session = await repository.createSession();
      await repository.addUserMessage(sessionId: session.id, text: 'question');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            chatRepositoryProvider.overrideWithValue(repository),
          ],
          child: ShadApp(
            locale: const Locale('zh'),
            theme: buildShadTheme(brightness: Brightness.light, chinese: true),
            localizationsDelegates: appLocalizationDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SessionDrawer(
                currentSessionId: session.id,
                onOpen: (_) {},
                onNewChat: () {},
                onOpenSettings: () {},
                cancelSession: (_) {},
                onDeleted: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final renameField = find.byKey(ValueKey('session-rename-${session.id}'));
      Future<void> openRename() async {
        await tester.tap(find.byKey(ValueKey('session-menu-${session.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('重命名'));
        // 输入框自动聚焦后光标定时闪烁，pumpAndSettle 永不结束。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }

      Future<String?> storedTitle() async =>
          (await repository.getSession(session.id))?.title;

      await openRename();
      await tester.enterText(renameField, '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(await storedTitle(), '');

      await openRename();
      await tester.enterText(renameField, 'abc');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(await storedTitle(), '');

      await openRename();
      await tester.enterText(renameField, '  abc  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(await storedTitle(), 'abc');

      // 在测试体内关库（探针验证：放进 addTearDown 或先卸载都会让 close 一直等）。
      await db.close();
    },
  );
}
