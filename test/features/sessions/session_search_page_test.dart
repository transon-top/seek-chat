import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/sessions/session_search_page.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:open_chat/shared/data/chat_repository.dart';
import 'package:open_chat/shared/data/database.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  Future<(AppDatabase, ChatRepository)> pumpPage(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final repository = ChatRepository(db);
    final alpha = await repository.createSession();
    await repository.renameSession(alpha.id, 'Alpha');
    await repository.addUserMessage(
      sessionId: alpha.id,
      text: 'the quick brown fox',
    );
    final other = await repository.createSession();
    await repository.renameSession(other.id, 'Other');
    await repository.addUserMessage(
      sessionId: other.id,
      text: 'nothing to see here',
    );

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
          home: SessionSearchPage(
            focusNode: FocusNode(),
            onBack: () {},
            onOpen: (_) {},
          ),
        ),
      ),
    );
    // ZH
    // 本地化解析是异步的；解析完成前 home 是 SizedBox.shrink。
    //
    // EN
    // Localization resolves asynchronously; until then home is SizedBox.shrink.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (db, repository);
  }

  Future<void> settleSearch(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('searches titles and message text and shows a snippet', (
    tester,
  ) async {
    final (db, _) = await pumpPage(tester);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search-field')), 'quick');
    await tester.pump();
    expect(find.byKey(const Key('search-skeleton')), findsOneWidget);

    await settleSearch(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('the quick brown fox'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
    expect(find.byKey(const Key('search-clear')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-clear')));
    await tester.pump();
    expect(find.text('Alpha'), findsNothing);
    expect(find.byKey(const Key('search-skeleton')), findsNothing);
    await db.close();
  });

  testWidgets('shows the empty result state', (tester) async {
    final (db, _) = await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('search-field')),
      'no such text',
    );
    await tester.pump();
    await settleSearch(tester);

    expect(find.text('暂无相关结果'), findsOneWidget);
    await db.close();
  });
}
