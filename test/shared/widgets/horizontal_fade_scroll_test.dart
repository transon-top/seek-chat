import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/shared/widgets/horizontal_fade_scroll.dart';

void main() {
  Widget build({double itemWidth = 60, int itemCount = 5}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 200,
          height: 40,
          child: HorizontalFadeScroll(
            child: Row(
              children: [
                for (var index = 0; index < itemCount; index++)
                  SizedBox(width: itemWidth),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// 单侧渐隐的目标展开进度；`tween.end` 与 `ScrollEdgeFade` 测试里读
  /// `AnimatedOpacity.opacity` 同理，反映目标状态而非过渡中的当前值。
  double fadeTarget(WidgetTester tester, String side) {
    final tween = tester.widget<TweenAnimationBuilder<double>>(
      find
          .descendant(
            of: find.byKey(Key('fade-$side')),
            matching: find.byType(TweenAnimationBuilder<double>),
          )
          .first,
    );
    return tween.tween.end!;
  }

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position;

  testWidgets('内容不足一屏时不挂渐隐遮罩', (tester) async {
    await tester.pumpWidget(build(itemWidth: 30));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fade-left')), findsNothing);
    expect(find.byKey(const Key('fade-right')), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('按剩余可滚动距离显示渐隐', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(fadeTarget(tester, 'left'), 0);
    expect(fadeTarget(tester, 'right'), 1);

    position(tester).jumpTo(50);
    await tester.pumpAndSettle();
    expect(fadeTarget(tester, 'left'), 1);
    expect(fadeTarget(tester, 'right'), 1);

    position(tester).jumpTo(position(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expect(fadeTarget(tester, 'left'), 1);
    expect(fadeTarget(tester, 'right'), 0);
  });

  group('horizontalFadeGradient', () {
    test('渐隐带为 24 像素宽', () {
      final gradient = horizontalFadeGradient(
        left: true,
        width: 480,
        amount: 1,
      );

      expect(gradient.begin, Alignment.centerLeft);
      expect(gradient.end, Alignment.centerRight);
      expect(gradient.colors, [Colors.transparent, Colors.white]);
      expect(gradient.stops, [0, horizontalFadeExtent / 480]);
    });

    test('展开进度为 0 时没有遮罩', () {
      final gradient = horizontalFadeGradient(
        left: true,
        width: 480,
        amount: 0,
      );

      expect(gradient.stops, [0, 0]);
    });

    test('渐隐带不超过可视宽度一半', () {
      final gradient = horizontalFadeGradient(
        left: false,
        width: 20,
        amount: 1,
      );

      expect(gradient.stops, [0, 0.5]);
    });

    test('右侧渐隐从右向左展开', () {
      final gradient = horizontalFadeGradient(
        left: false,
        width: 480,
        amount: 1,
      );

      expect(gradient.begin, Alignment.centerRight);
      expect(gradient.end, Alignment.centerLeft);
    });

    test('宽度为 0 时退化为无遮罩', () {
      final gradient = horizontalFadeGradient(left: true, width: 0, amount: 1);

      expect(gradient.stops, [0, 0]);
    });
  });
}
