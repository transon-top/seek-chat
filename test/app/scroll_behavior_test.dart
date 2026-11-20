import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_chat/app/app.dart';

void main() {
  testWidgets('全局滚动：Android 不画光晕，统一回弹物理', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      appScrollBehavior.getScrollPhysics(context),
      isA<BouncingScrollPhysics>(),
    );
    const child = SizedBox();
    expect(
      appScrollBehavior.buildOverscrollIndicator(
        context,
        child,
        const ScrollableDetails(direction: AxisDirection.down),
      ),
      same(child),
    );
  });

  group('AppBounceScrollPhysics', () {
    const physics = AppBounceScrollPhysics(
      parent: RangeMaintainingScrollPhysics(),
    );

    ScrollMetrics metrics(double pixels) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: pixels,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

    test('范围内拖动原样返回', () {
      expect(physics.applyPhysicsToUserOffset(metrics(500), 50), 50);
    });

    test('越界后拖动被衰减，且越拉越硬', () {
      final near = physics.applyPhysicsToUserOffset(metrics(1010), -50);
      final far = physics.applyPhysicsToUserOffset(metrics(1030), -50);
      expect(near.abs(), lessThan(50));
      expect(near, lessThan(0));
      expect(far.abs(), lessThan(near.abs()));
    });

    test('往回拉不衰减', () {
      expect(physics.applyPhysicsToUserOffset(metrics(1010), 50), 50);
    });

    test('到上限后不再移动', () {
      expect(
        physics.applyPhysicsToUserOffset(
          metrics(1000 + AppBounceScrollPhysics.maxOverscroll),
          -50,
        ),
        0,
      );
    });
  });

  testWidgets('按住越界拖动距离不超过上限', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: appScrollBehavior,
        home: Scaffold(
          body: ListView.builder(
            controller: controller,
            itemCount: 100,
            itemBuilder: (_, _) => const SizedBox(height: 60),
          ),
        ),
      ),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, -600));
    await tester.pump();

    final overscroll =
        controller.position.pixels - controller.position.maxScrollExtent;
    expect(overscroll, greaterThan(0));
    expect(
      overscroll,
      lessThanOrEqualTo(AppBounceScrollPhysics.maxOverscroll + 0.01),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
