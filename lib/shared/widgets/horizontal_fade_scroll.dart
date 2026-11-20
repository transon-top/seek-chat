import 'package:material_ui/material_ui.dart';

/// 横向滚动 + 两侧边缘渐隐（Scroll Edge Fade 横向变体）。
///
/// 用 `ShaderMask` 的 alpha 遮罩实现，不依赖背景色；左右两侧各自按剩余
/// 可滚动距离显隐，出现与消失都有 150ms 过渡。滚动控制器自持。
class HorizontalFadeScroll extends StatefulWidget {
  const HorizontalFadeScroll({super.key, required this.child});

  final Widget child;

  @override
  State<HorizontalFadeScroll> createState() => _HorizontalFadeScrollState();
}

class _HorizontalFadeScrollState extends State<HorizontalFadeScroll> {
  static const _threshold = 0.5;
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      // 内容尺寸 / 视口变化时刷新可滚动状态。
      onNotification: (_) {
        setState(() {});
        return false;
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final position = _controller.hasClients ? _controller.position : null;
          // 没有横向溢出时不挂遮罩：省掉两层 ShaderMask 的光栅化成本
          // （表格滚动逐帧重绘时最明显）。此时偏移必为 0，重建滚动视图无副作用。
          if (position == null || position.maxScrollExtent <= _threshold) {
            return child!;
          }
          final left = position.pixels > _threshold;
          final right = position.maxScrollExtent - position.pixels > _threshold;
          return _EdgeFadeMask(
            key: const Key('fade-right'),
            left: false,
            active: right,
            child: _EdgeFadeMask(
              key: const Key('fade-left'),
              left: true,
              active: left,
              child: child!,
            ),
          );
        },
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 单侧渐隐遮罩；[active] 变化时用 150ms 过渡。
///
/// 可滚动期间遮罩常驻（无渐隐时是全白渐变），避免淡入瞬间切换控件类型重建
/// `Scrollable`、丢失滚动位置；不可滚动时外层不挂遮罩（见 `build`）。
class _EdgeFadeMask extends StatelessWidget {
  const _EdgeFadeMask({
    super.key,
    required this.left,
    required this.active,
    required this.child,
  });

  final bool left;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: active ? 1 : 0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      builder: (context, amount, child) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => horizontalFadeGradient(
          left: left,
          width: bounds.width,
          amount: amount,
        ).createShader(bounds),
        child: child,
      ),
      child: child,
    );
  }
}

/// 单侧渐隐渐变色：边缘透明、到 [fadeExtent] 处不透明。
///
/// [amount] 为展开进度 0...1（0 时全不透明，等于没有遮罩）；
/// 渐隐带不超过可视宽度一半。
LinearGradient horizontalFadeGradient({
  required bool left,
  required double width,
  required double amount,
}) {
  final fade = width <= 0
      ? 0.0
      : (horizontalFadeExtent * amount / width).clamp(0.0, 0.5);
  return LinearGradient(
    begin: left ? Alignment.centerLeft : Alignment.centerRight,
    end: left ? Alignment.centerRight : Alignment.centerLeft,
    colors: const [Colors.transparent, Colors.white],
    stops: [0, fade],
  );
}

/// 渐隐带宽度，与纵向 `ScrollEdgeFade` 一致。
const horizontalFadeExtent = 24.0;
