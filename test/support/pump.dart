import 'package:flutter_test/flutter_test.dart';

/// ZH
/// 以 16ms 步进泵帧，持续约 [duration]；集成测试里避免 `pumpAndSettle`
/// 被浮层 ticker 或平台动画卡住。
///
/// EN
/// Pumps frames in 16ms steps for about [duration]; integration tests avoid
/// `pumpAndSettle` getting stuck on overlay tickers or platform animations.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < duration) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// ZH
/// 泵到 [done] 为真或超时，返回耗时毫秒（性能基线需要）。
///
/// EN
/// Pumps until [done] is true or timeout; returns elapsed milliseconds (for perf baselines).
Future<int> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final watch = Stopwatch()..start();
  while (!done() && watch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return watch.elapsedMilliseconds;
}
