import 'package:material_ui/material_ui.dart';

/// 在还有未露出内容的一侧叠加背景色渐隐带（Scroll Edge Fade）。
///
/// 用面板背景色到透明的叠加层实现，要求背景为实色；
/// 背景改为图片或模糊时需改用 mask 方案。
class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({
    super.key,
    required this.controller,
    required this.color,
    required this.child,
    this.topInset = 0,
  });

  /// 被包裹滚动视图的控制器，用于判断可滚动方向。
  final ScrollController controller;

  /// 面板背景色，渐隐带由它渐变到透明。
  final Color color;

  /// 顶部渐隐带的起点；侧边栏让出吸顶分组头的高度。
  final double topInset;

  final Widget child;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  static const _fadeExtent = 12.0;
  static const _fadeDuration = Duration(milliseconds: 150);

  /// 内容尺寸 / 视口变化的刷新信号：只唤醒渐隐带，不重建整块。
  final _metrics = ValueNotifier<int>(0);

  @override
  void dispose() {
    _metrics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      // 内容尺寸 / 视口变化时刷新可滚动状态。
      onNotification: (_) {
        _metrics.value++;
        return false;
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.controller, _metrics]),
        builder: (context, child) {
          final position = widget.controller.hasClients
              ? widget.controller.position
              : null;
          final showTop = position != null && position.pixels > 0.5;
          final showBottom =
              position != null &&
              position.maxScrollExtent - position.pixels > 0.5;
          return Stack(
            children: [
              child!,
              _band(show: showTop, top: widget.topInset),
              _band(show: showBottom, top: null),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }

  /// 单侧渐隐带；[top] 非空时按该偏移贴顶，否则贴底。
  Widget _band({required bool show, required double? top}) {
    final isTop = top != null;
    return Positioned(
      top: top,
      bottom: isTop ? null : 0,
      left: 0,
      right: 0,
      height: _fadeExtent,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: _fadeDuration,
          curve: Curves.easeOut,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
                end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [widget.color, widget.color.withAlpha(0)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
