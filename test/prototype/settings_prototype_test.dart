import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../prototype/settings/main.dart';

void main() {
  Future<void> pumpPrototype(
    WidgetTester tester, {
    bool zh = true,
    bool systemChinese = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      SettingsPrototypeApp(
        initialLanguage: zh ? 'zh' : 'en',
        initialSystemChinese: systemChinese,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('原型：切换语言立即刷新，主题切换即时生效', (tester) async {
    await pumpPrototype(tester);
    expect(find.text('设置'), findsOneWidget);

    await tapVisible(tester, const Key('settings-language'));
    await tester.tap(find.byKey(const Key('language-en')));
    await tester.pumpAndSettle();
    expect(find.text('Language & location'), findsOneWidget);
    expect(find.text('设置'), findsNothing);

    await tapVisible(tester, const Key('theme-dark'));
    final app = tester.widget<ShadApp>(find.byType(ShadApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('原型：中文系统选择省市与清除', (tester) async {
    await pumpPrototype(tester);

    await tapVisible(tester, const Key('settings-location'));
    await tester.tap(find.byKey(const Key('province-浙江省')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('city-杭州市')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('浙江省 · 杭州市'), findsOneWidget);

    await tapVisible(tester, const Key('settings-location'));
    await tester.tap(find.byKey(const Key('province-none')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('未设置'), findsWidgets);
  });

  testWidgets('原型：其他系统选择国家 / 地区', (tester) async {
    await pumpPrototype(tester, systemChinese: false);

    await tapVisible(tester, const Key('settings-location'));
    await tester.tap(find.byKey(const Key('region-Japan')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('Japan'), findsOneWidget);
  });

  testWidgets('原型：导入成功、超大文件失败与删除确认', (tester) async {
    await pumpPrototype(tester);

    await tapVisible(tester, const Key('import-action'));
    await tester.tap(find.byKey(const Key('file-sample-normal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-confirm')));
    await tester.pump();
    expect(find.text('正在导入…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('已导入 3 个对话'), findsOneWidget);

    await tapVisible(tester, const Key('import-action'));
    await tester.tap(find.byKey(const Key('file-sample-large')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-confirm')));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('导入失败：文件过大'), findsOneWidget);

    await tapVisible(tester, const Key('delete-all-action'));
    expect(find.text('删除全部对话？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-all-confirm')));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect(find.text('已删除全部对话（原型）'), findsOneWidget);
  });

  testWidgets('原型：清除 Key 需确认', (tester) async {
    await pumpPrototype(tester);

    await tapVisible(tester, const Key('settings-clear-key'));
    expect(find.text('清除 API Key？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clear-key-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-key')),
        matching: find.text('未设置'),
      ),
      findsOneWidget,
    );
  });
}
