import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/localization.dart';
import 'package:open_chat/app/theme.dart';
import 'package:open_chat/features/chat/photo_import.dart';
import 'package:open_chat/features/chat/photo_strip.dart';
import 'package:open_chat/l10n/generated/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../support/photo_fakes.dart';

class _FakeLibrary implements PhotoLibrary {
  _FakeLibrary({
    this.status = PhotoAccessStatus.authorized,
    this.statusAfterRequest,
    List<PhotoAsset>? assets,
  }) : assets = assets ?? const [];

  PhotoAccessStatus status;
  PhotoAccessStatus? statusAfterRequest;
  List<PhotoAsset> assets;
  bool fail = false;
  Completer<void>? gate;
  int accessCalls = 0;
  int requestCalls = 0;
  int loadCalls = 0;
  int lastLimit = 0;
  int presentLimitedCalls = 0;
  int settingsCalls = 0;

  @override
  Future<PhotoAccessStatus> access({required bool request}) async {
    accessCalls++;
    if (!request) return status;
    requestCalls++;
    if (statusAfterRequest != null) status = statusAfterRequest!;
    return status;
  }

  @override
  Future<List<PhotoAsset>> recentImages({int limit = 30}) async {
    loadCalls++;
    lastLimit = limit;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('load failed');
    return assets;
  }

  @override
  Future<void> presentLimited() async {
    presentLimitedCalls++;
  }

  @override
  Future<void> openSettings() async {
    settingsCalls++;
  }
}

void main() {
  test('photo strip is enabled on both platforms by default', () {
    expect(photoStripEnabledFor(TargetPlatform.android), isTrue);
    expect(photoStripEnabledFor(TargetPlatform.iOS), isTrue);
  });

  Widget host(PhotoStrip strip) => ShadApp(
    theme: buildShadTheme(brightness: Brightness.light, chinese: true),
    locale: const Locale('zh'),
    localizationsDelegates: appLocalizationDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: strip),
    ),
  );

  List<PhotoAsset> assets(int count) => [
    for (var i = 0; i < count; i++) FakePhotoAsset(id: 'a$i'),
  ];

  testWidgets('shows six skeletons, queries 30 assets, and keeps order', (
    tester,
  ) async {
    final library = _FakeLibrary(assets: assets(5))..gate = Completer<void>();
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {},
          full: false,
          onToggle: (_) {},
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-strip-skeleton')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('photo-strip-skeleton')),
        matching: find.byType(Container),
      ),
      findsNWidgets(6),
    );
    expect(find.byKey(const Key('photo-tile-a0')), findsNothing);

    library.gate!.complete();
    await tester.pumpAndSettle();

    expect(library.lastLimit, 30);
    expect(find.byKey(const Key('photo-strip-skeleton')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('photo-tile-a0'))),
      const Size(80, 80),
    );
    expect(tester.getSize(find.byType(PhotoStrip)), const Size(800, 96));
    for (var i = 1; i < 5; i++) {
      expect(
        tester.getTopLeft(find.byKey(Key('photo-tile-a$i'))).dx,
        greaterThan(
          tester.getTopLeft(find.byKey(Key('photo-tile-a${i - 1}'))).dx,
        ),
      );
    }
  });

  testWidgets('requests permission only when not determined', (tester) async {
    final library = _FakeLibrary(
      status: PhotoAccessStatus.notDetermined,
      statusAfterRequest: PhotoAccessStatus.authorized,
      assets: assets(1),
    );
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {},
          full: false,
          onToggle: (_) {},
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(library.requestCalls, 1);
    expect(find.byKey(const Key('photo-tile-a0')), findsOneWidget);
  });

  testWidgets('authorized access never prompts', (tester) async {
    final library = _FakeLibrary(assets: assets(1));
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {},
          full: false,
          onToggle: (_) {},
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(library.requestCalls, 0);
    expect(library.accessCalls, 1);
  });

  testWidgets('denied shows settings without loading assets', (tester) async {
    final library = _FakeLibrary(status: PhotoAccessStatus.denied);
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {},
          full: false,
          onToggle: (_) {},
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法访问照片'), findsOneWidget);
    expect(library.loadCalls, 0);
    await tester.tap(find.byKey(const Key('photo-strip-settings')));
    await tester.pump();
    expect(library.settingsCalls, 1);
  });

  testWidgets('limited puts a manage tile first and reloads after it', (
    tester,
  ) async {
    final library = _FakeLibrary(
      status: PhotoAccessStatus.limited,
      assets: assets(2),
    );
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {},
          full: false,
          onToggle: (_) {},
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-strip-manage')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('photo-strip-manage'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('photo-tile-a0'))).dx),
    );

    await tester.tap(find.byKey(const Key('photo-strip-manage')));
    await tester.pumpAndSettle();
    expect(library.presentLimitedCalls, 1);
    expect(library.loadCalls, 2);

    final empty = _FakeLibrary(status: PhotoAccessStatus.limited);
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: empty,
          selectedAssetIds: const {},
          full: false,
          onToggle: (_) {},
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-strip-manage')), findsOneWidget);
    expect(find.text('没有最近照片'), findsNothing);
  });

  testWidgets('empty library shows the empty message', (tester) async {
    final library = _FakeLibrary();
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {},
          full: false,
          onToggle: (_) {},
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有最近照片'), findsOneWidget);
  });

  testWidgets('load failure retries in place', (tester) async {
    final library = _FakeLibrary(assets: assets(1))..fail = true;
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {},
          full: false,
          onToggle: (_) {},
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法读取照片'), findsOneWidget);
    library.fail = false;
    await tester.tap(find.byKey(const Key('photo-strip-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-tile-a0')), findsOneWidget);
    expect(library.loadCalls, 2);
  });

  testWidgets('selection derives from sourceAssetId and toggles', (
    tester,
  ) async {
    final toggled = <String>[];
    final library = _FakeLibrary(assets: assets(2));
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {'a0'},
          full: false,
          onToggle: (asset) => toggled.add(asset.id),
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('photo-check-a0')), findsOneWidget);
    expect(find.byKey(const Key('photo-check-a1')), findsNothing);
    await tester.tap(find.byKey(const Key('photo-tile-a0')));
    await tester.tap(find.byKey(const Key('photo-tile-a1')));
    expect(toggled, ['a0', 'a1']);
  });

  testWidgets('full draft dims unselected tiles but keeps selected removable', (
    tester,
  ) async {
    final toggled = <String>[];
    var limits = 0;
    final library = _FakeLibrary(assets: assets(2));
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {'a0'},
          full: true,
          onToggle: (asset) => toggled.add(asset.id),
          onLimitReached: () => limits++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    double opacityOf(String id) => tester
        .widget<Opacity>(
          find.ancestor(
            of: find.byKey(Key('photo-tile-$id')),
            matching: find.byType(Opacity),
          ),
        )
        .opacity;
    expect(opacityOf('a0'), 1);
    expect(opacityOf('a1'), 0.5);

    await tester.tap(find.byKey(const Key('photo-tile-a1')));
    expect(limits, 1);
    expect(toggled, isEmpty);
    await tester.tap(find.byKey(const Key('photo-tile-a0')));
    expect(toggled, ['a0']);
  });

  testWidgets('resuming the app reloads the strip', (tester) async {
    final library = _FakeLibrary(assets: assets(1));
    await tester.pumpWidget(
      host(
        PhotoStrip(
          library: library,
          selectedAssetIds: const {},
          full: false,
          onToggle: (_) {},
          onLimitReached: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(library.loadCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(library.loadCalls, 2);
  });

  testWidgets('picker resume does not reload the strip', (tester) async {
    final library = _FakeLibrary(assets: assets(1));
    PhotoStrip strip({required bool reloadOnResume}) => PhotoStrip(
      library: library,
      selectedAssetIds: const {},
      full: false,
      reloadOnResume: reloadOnResume,
      onToggle: (_) {},
      onLimitReached: () {},
    );

    await tester.pumpWidget(host(strip(reloadOnResume: true)));
    await tester.pumpAndSettle();
    expect(library.loadCalls, 1);

    await tester.pumpWidget(host(strip(reloadOnResume: false)));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(library.loadCalls, 1);
  });
}
