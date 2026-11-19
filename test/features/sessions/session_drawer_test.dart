import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/sessions/session_drawer.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/models/types.dart';
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
}
