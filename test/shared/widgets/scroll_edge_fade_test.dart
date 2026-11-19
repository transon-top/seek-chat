import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/shared/widgets/scroll_edge_fade.dart';

void main() {
  Widget build(
    ScrollController controller, {
    double topInset = 0,
    int count = 100,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ScrollEdgeFade(
          controller: controller,
          color: Colors.black,
          topInset: topInset,
          child: ListView.builder(
            controller: controller,
            itemCount: count,
            itemBuilder: (context, index) => const SizedBox(height: 50),
          ),
        ),
      ),
    );
  }

  List<double> opacities(WidgetTester tester) => tester
      .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
      .map((widget) => widget.opacity)
      .toList();

  testWidgets('内容不足一屏时两侧渐隐都隐藏', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(build(controller, count: 2));
    await tester.pumpAndSettle();
    expect(opacities(tester), [0, 0]);
  });

  testWidgets('按可滚动方向显示渐隐带', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(build(controller));
    await tester.pumpAndSettle();
    expect(opacities(tester), [0, 1]);

    controller.jumpTo(200);
    await tester.pumpAndSettle();
    expect(opacities(tester), [1, 1]);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(opacities(tester), [1, 0]);
  });

  testWidgets('顶部渐隐带从 topInset 开始', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(build(controller, topInset: 29));
    await tester.pumpAndSettle();
    final top = tester.widgetList<Positioned>(find.byType(Positioned)).first;
    expect(top.top, 29);
  });
}
