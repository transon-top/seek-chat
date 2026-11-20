import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 推入式侧栏控制器：进度 0（关闭）到 1（打开）。
///
/// 拖动按全局坐标累加：内容层缩放后局部 delta 会被放大，不能直接用。
class PushMenuController {
  PushMenuController({
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 300),
  }) : _animation = AnimationController(vsync: vsync, duration: duration);

  /// 松手时直接按速度吸附的阈值，与 Material Drawer 一致。
  static const double minFlingVelocity = 365;

  final AnimationController _animation;

  /// 打开时内容层右移的距离；[PushMenu] 布局时更新。
  double travel = 0;

  /// 打开时内容层盖住的右侧宽度；侧栏内容据此留出安全区。
  double openInset = 0;

  /// 侧栏内容的滑入距离；侧栏在进度 0 时整体向左让出这段距离。
  double menuSlide = 0;

  double _lastDragX = 0;

  Animation<double> get animation => _animation;

  double get progress => _animation.value;

  bool get isOpen => progress > 0;

  void dispose() => _animation.dispose();

  void toggle() => isOpen ? close() : open();

  void open() {
    _unfocus();
    _settleTo(1);
  }

  void close() => _settleTo(0);

  void dragStart(double globalX) {
    _unfocus();
    _animation.stop();
    _lastDragX = globalX;
  }

  void dragUpdate(double globalX) {
    if (travel <= 0) return;
    final dx = globalX - _lastDragX;
    _lastDragX = globalX;
    _animation.value = math.min(1.0, math.max(0.0, progress + dx / travel));
  }

  void dragEnd(double velocity) {
    final open = velocity.abs() >= minFlingVelocity
        ? velocity > 0
        : progress >= 0.5;
    _settleTo(open ? 1 : 0);
  }

  void _settleTo(double target) {
    final remaining = (target - progress).abs();
    if (remaining < 0.001) {
      _animation.value = target;
      return;
    }
    _animation.animateTo(
      target,
      duration: Duration(
        milliseconds: math.max(120, (300 * remaining).round()),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  static void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();
}

/// 让后代（含 Markdown 内的识别器）拿到同一个推入式侧栏控制器。
class PushMenuScope extends InheritedWidget {
  const PushMenuScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final PushMenuController controller;

  static PushMenuController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PushMenuScope>()?.controller;

  @override
  bool updateShouldNotify(PushMenuScope oldWidget) =>
      oldWidget.controller != controller;
}

/// 推入式侧栏：侧栏铺在底层，内容层随进度右移、缩小并圆角裁切。
///
/// 交互约定：内层横向滚动组件（表格、代码块等）在手势竞技场里优先；
/// 打开时内容层被透明关闭层覆盖，点击或左拖都收起。
/// 侧栏背景铺满；侧栏内容按 [PushMenuController.menuSlide] 与进度自行滑入。
class PushMenu extends StatefulWidget {
  const PushMenu({
    super.key,
    required this.menu,
    required this.child,
    this.openFraction = 0.78,
    this.contentScale = 0.85,
    this.cornerRadius = 24,
    this.menuSlideFraction = 1,
    this.duration = const Duration(milliseconds: 300),
  });

  final Widget menu;
  final Widget child;

  /// 打开后内容层右移的距离占屏宽的比例。
  final double openFraction;

  /// 打开后内容层的缩放比例。
  final double contentScale;

  /// 打开后内容层的圆角。
  final double cornerRadius;

  /// 侧栏内容从左侧滑入的距离占屏宽的比例；侧栏背景保持铺满。
  final double menuSlideFraction;

  final Duration duration;

  @override
  State<PushMenu> createState() => _PushMenuState();
}

class _PushMenuState extends State<PushMenu>
    with SingleTickerProviderStateMixin {
  late final PushMenuController _controller = PushMenuController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _controller.travel = constraints.maxWidth * widget.openFraction;
        _controller.openInset = math.max(
          0.0,
          constraints.maxWidth *
              (1 - widget.openFraction - (1 - widget.contentScale) / 2),
        );
        _controller.menuSlide = constraints.maxWidth * widget.menuSlideFraction;
        return PushMenuScope(
          controller: _controller,
          child: AnimatedBuilder(
            animation: _controller.animation,
            builder: (context, child) {
              final progress = _controller.progress;
              return PopScope<void>(
                canPop: progress == 0,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _controller.close();
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Offstage(
                        offstage: progress == 0,
                        child: ExcludeFocus(
                          excluding: progress == 0,
                          child: RepaintBoundary(child: widget.menu),
                        ),
                      ),
                    ),
                    _buildContent(progress, child!),
                  ],
                ),
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }

  Widget _buildContent(double progress, Widget child) {
    final scale = 1 - (1 - widget.contentScale) * progress;
    final radius = widget.cornerRadius * progress;
    final content = Stack(
      children: [
        ExcludeFocus(
          excluding: progress > 0,
          child: ExcludeSemantics(
            excluding: progress > 0,
            // 缩放期间复用整页的栅格缓存，避免逐帧重绘消息列表。
            child: RepaintBoundary(child: child),
          ),
        ),
        if (progress > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const Key('push-menu-scrim'),
                // 蒙版随进度加深：左缘最轻，向右渐重，对话层后退。
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0.35, 1],
                    colors: [
                      const Color(0xFF000000)
                          .withValues(alpha: 0.10 * progress),
                      const Color(0xFF000000)
                          .withValues(alpha: 0.32 * progress),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (progress > 0)
          Positioned.fill(
            child: Semantics(
              button: true,
              label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
              onTap: _controller.close,
              child: GestureDetector(
                key: const Key('push-menu-dismiss'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _controller.close,
                onHorizontalDragStart: (details) =>
                    _controller.dragStart(details.globalPosition.dx),
                onHorizontalDragUpdate: (details) =>
                    _controller.dragUpdate(details.globalPosition.dx),
                onHorizontalDragEnd: (details) =>
                    _controller.dragEnd(details.primaryVelocity ?? 0.0),
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    );
    return Transform.translate(
      offset: Offset(_controller.travel * progress, 0),
      child: Transform.scale(
        scale: scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: progress <= 0
                ? const []
                : [
                    BoxShadow(
                      color: const Color(0xFF000000)
                          .withValues(alpha: 0.10 * progress),
                      blurRadius: 10,
                      offset: const Offset(-3, 0),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            clipBehavior: progress > 0 ? Clip.antiAlias : Clip.none,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 把横向拖动转给最近的 [PushMenuController]；不在侧栏内时原样返回。
///
/// 作为内容层的祖先使用时，内层横向滚动组件会先赢得手势竞技场；
/// 放进 [SelectionArea] 内层时，则先于文本选择识别器注册，避免被吞。
class PushMenuSwipeDetector extends StatelessWidget {
  const PushMenuSwipeDetector({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = PushMenuScope.maybeOf(context);
    if (controller == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onHorizontalDragStart: (details) =>
          controller.dragStart(details.globalPosition.dx),
      onHorizontalDragUpdate: (details) =>
          controller.dragUpdate(details.globalPosition.dx),
      onHorizontalDragEnd: (details) =>
          controller.dragEnd(details.primaryVelocity ?? 0.0),
      child: child,
    );
  }
}
