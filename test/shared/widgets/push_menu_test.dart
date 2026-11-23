import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:seek_chat/app/localization.dart';
import 'package:seek_chat/app/theme.dart';
import 'package:seek_chat/l10n/generated/app_localizations.dart';
import 'package:seek_chat/shared/widgets/push_menu.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget app(Widget home) => ShadApp(
  locale: const Locale('zh'),
  theme: buildShadTheme(brightness: Brightness.light, chinese: true),
  localizationsDelegates: appLocalizationDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Widget chat({required Widget child}) => PushMenu(
  menu: const Text('MENU'),
  child: PushMenuSwipeDetector(child: child),
);

void main() {
  testWidgets('drags open and taps the content to close', (tester) async {
    await tester.pumpWidget(
      app(
        chat(
          child: const Scaffold(
            body: SizedBox.expand(child: Center(child: Text('CHAT'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('MENU'), findsNothing);
    expect(find.byKey(const Key('push-menu-scrim')), findsNothing);
    expect(find.byKey(const Key('push-menu-content-veil')), findsNothing);

    await tester.drag(find.text('CHAT'), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('MENU'), findsOneWidget);
    expect(find.byKey(const Key('push-menu-scrim')), findsOneWidget);
    expect(find.byKey(const Key('push-menu-content-veil')), findsOneWidget);

    // ZH
    // 打开后内容层只露出右侧一条，关闭层也覆盖在那条上。
    //
    // EN
    // When open, only a right-side strip of content shows; the closed layer covers that strip too.
    await tester.tapAt(const Offset(760, 300));
    await tester.pumpAndSettle();
    expect(find.text('MENU'), findsNothing);
  });

  testWidgets('drags the open content back to close', (tester) async {
    await tester.pumpWidget(
      app(
        chat(
          child: const Scaffold(
            body: SizedBox.expand(child: Center(child: Text('CHAT'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('CHAT'), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('MENU'), findsOneWidget);

    await tester.dragFrom(const Offset(760, 300), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('MENU'), findsNothing);
  });

  testWidgets('drags the open menu left to close', (tester) async {
    await tester.pumpWidget(
      app(
        chat(
          child: const Scaffold(
            body: SizedBox.expand(child: Center(child: Text('CHAT'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('CHAT'), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('MENU'), findsOneWidget);

    await tester.drag(find.text('MENU'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('MENU'), findsNothing);
  });

  testWidgets('inner horizontal scrollable keeps horizontal drags', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        chat(
          child: Scaffold(
            body: SingleChildScrollView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              child: const SizedBox(width: 2000, height: 600),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('MENU'), findsNothing);
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('detector inside SelectionArea opens on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      app(
        PushMenu(
          menu: const Text('MENU'),
          child: SelectionArea(
            child: PushMenuSwipeDetector(
              child: const Center(child: Text('TEXT')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('TEXT'), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('MENU'), findsOneWidget);
  });
}
