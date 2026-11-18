import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../prototype/main.dart';

void main() {
  testWidgets('原型：发送追加消息、停止生成、切换场景与展开长消息', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pickScenario(String name) async {
      await tester.tap(find.byKey(const Key('menu-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final pill = find.byKey(Key('scenario-$name'));
      await tester.ensureVisible(pill);
      await tester.tap(pill);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    await tester.pumpWidget(const PrototypeApp());
    await tester.pump();

    expect(find.text('对比三款降噪耳机'), findsOneWidget);

    await pickScenario('empty');
    expect(find.text('今天有什么可以帮到你？'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('composer-input')), '你好');
    await tester.tap(find.byKey(const Key('send-button')));
    await tester.pump();

    expect(find.text('你好'), findsOneWidget);
    expect(find.byKey(const Key('stop-button')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('会尽量保留人声'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stop-button')));
    await tester.pump();
    expect(find.text('已停止生成'), findsOneWidget);
    expect(find.byKey(const Key('continue-button')), findsOneWidget);

    await pickScenario('long');
    expect(find.text('展开全文'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('long-toggle')));
    await tester.tap(find.byKey(const Key('long-toggle')));
    await tester.pump();
    expect(find.text('收起'), findsOneWidget);
  });
}
