import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:seek_chat/app/localization.dart';
import 'package:seek_chat/app/theme.dart';
import 'package:seek_chat/features/chat/attachment_panel.dart';
import 'package:seek_chat/l10n/generated/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('renders three actions and guards the attachment limit', (
    tester,
  ) async {
    final events = <String>[];
    Widget host(int count) => ShadApp(
      theme: buildShadTheme(brightness: Brightness.light, chinese: true),
      locale: const Locale('zh'),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AttachmentPanel(
          attachmentCount: count,
          onTakePhoto: () => events.add('take-photo'),
          onPickPhotos: () => events.add('photos'),
          onPickFiles: () => events.add('files'),
          onLimitReached: () => events.add('limit'),
        ),
      ),
    );

    await tester.pumpWidget(host(0));
    await tester.pumpAndSettle();
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选择'), findsOneWidget);
    expect(find.text('选择文件'), findsOneWidget);
    await tester.tap(find.byKey(const Key('panel-take-photo')));
    await tester.tap(find.byKey(const Key('panel-photos')));
    await tester.tap(find.byKey(const Key('panel-files')));
    expect(events, ['take-photo', 'photos', 'files']);

    events.clear();
    await tester.pumpWidget(host(50));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('panel-take-photo')));
    await tester.tap(find.byKey(const Key('panel-photos')));
    await tester.tap(find.byKey(const Key('panel-files')));
    expect(events, ['limit', 'limit', 'files']);
  });

  testWidgets(
    'photo strip slot stacks above the grid and shrinks when absent',
    (tester) async {
      Widget host({Widget? photoStrip}) => ShadApp(
        theme: buildShadTheme(brightness: Brightness.light, chinese: true),
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AttachmentPanel(
            attachmentCount: 0,
            photoStrip: photoStrip,
            onTakePhoto: () {},
            onPickPhotos: () {},
            onPickFiles: () {},
            onLimitReached: () {},
          ),
        ),
      );

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AttachmentPanel)).height, 96);

      await tester.pumpWidget(
        host(photoStrip: const SizedBox(height: 96, width: 400)),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AttachmentPanel)).height, 192);
      expect(find.byKey(const Key('panel-take-photo')), findsOneWidget);
    },
  );
}
