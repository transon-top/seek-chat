import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// ZH
/// 推入式侧栏控制器：进度 0（关闭）到 1（打开）。
///
/// 拖动按全局坐标累加：内容层缩放后局部 delta 会被放大，不能直接用。
///
/// EN
/// Push-style sidebar controller: progress from 0 (closed) to 1 (open).
///
/// Drags use global coordinates; content scaling amplifies local deltas, so they are unusable.
class PushMenuController {
  PushMenuController({
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 300),
  }) : _animation = AnimationController(vsync: vsync, duration: duration),
       _searchAnimation = AnimationController(vsync: vsync, duration: duration);

  /// ZH
  /// 松手时直接按速度吸附的阈值，与 Material Drawer 一致。
  ///
  /// EN
  /// Velocity threshold for snapping on release, matching Material Drawer.
  static const double minFlingVelocity = 365;

  final AnimationController _animation;
  final AnimationController _searchAnimation;

  /// ZH
  /// 打开时内容层右移的距离；[PushMenu] 布局时更新。
  ///
  /// EN
  /// Distance the content layer moves right when open; updated during [PushMenu] layout.
  double travel = 0;

  /// ZH
  /// 搜索时内容层再右移的距离：刚好完全移出屏幕。
  ///
  /// EN
  /// Extra distance the content layer moves right during search: just enough to leave the screen.
  double searchTravel = 0;

  /// ZH
  /// 打开时内容层盖住的右侧宽度；侧栏内容据此留出安全区。
  ///
  /// EN
  /// Width covered by the content layer on the right; sidebar content reserves a safe area.
  double openInset = 0;

  /// ZH
  /// 侧栏内容的滑入距离；侧栏在进度 0 时整体向左让出这段距离。
  ///
  /// EN
  /// Slide-in distance for sidebar content; at progress 0 the sidebar shifts left by this amount.
  double menuSlide = 0;

  double _lastDragX = 0;
  bool _dragging = false;

  /// ZH
  /// 侧栏内容可拦截系统返回：返回 true 表示已处理，不关闭侧栏。
  ///
  /// EN
  /// Sidebar content may intercept system back: true means handled, keep the sidebar open.
  bool Function()? backHandler;

  Animation<double> get animation => _animation;

  /// ZH
  /// 菜单打开与搜索展开共用一套重绘监听。
  ///
  /// EN
  /// Menu opening and search expansion share one repaint listener.
  Listenable get repaint => Listenable.merge([_animation, _searchAnimation]);

  double get progress => _animation.value;

  /// ZH
  /// 搜索展开进度：0 为普通抽屉宽度，1 为内容层完全移出屏幕。
  ///
  /// EN
  /// Search expansion progress: 0 is normal drawer width, 1 is content fully off screen.
  double get searchProgress => _searchAnimation.value;

  Animation<double> get searchAnimation => _searchAnimation;

  bool get isOpen => progress > 0;

  Future<void> searchOpen() {
    _unfocus();
    return _searchAnimation.animateTo(
      1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> searchClose() => _searchAnimation.animateTo(
    0,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
  );

  void resetSearch() => _searchAnimation.value = 0;

  void addListener(VoidCallback listener) => _animation.addListener(listener);

  void removeListener(VoidCallback listener) =>
      _animation.removeListener(listener);

  void dispose() {
    _searchAnimation.dispose();
    _animation.dispose();
  }

  void toggle() => isOpen ? close() : open();

  /// ZH
  /// 点击开合按官方实测：40ms 内完成，几乎瞬开；拖动结束仍走缓动。
  ///
  /// EN
  /// Tap open/close: within 40ms per official measurement, near-instant; drag release eases.
  static const _snapDuration = Duration(milliseconds: 60);

  void open() {
    _unfocus();
    _settleTo(1, duration: _snapDuration);
  }

  void close() => _settleTo(0, duration: _snapDuration);

  void dragStart(double globalX) {
    // ZH
    // 官方在搜索态也允许左滑收起整个侧栏；抽屉关闭时顺带退出搜索。
    //
    // EN
    // Official: left swipe closes the sidebar in search mode; closing the drawer exits search.
    _unfocus();
    _animation.stop();
    _dragging = true;
    _lastDragX = globalX;
  }

  void dragUpdate(double globalX) {
    if (!_dragging || travel <= 0) return;
    final dx = globalX - _lastDragX;
    _lastDragX = globalX;
    _animation.value = math.min(1.0, math.max(0.0, progress + dx / travel));
  }

  void dragEnd(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final open = velocity.abs() >= minFlingVelocity
        ? velocity > 0
        : progress >= 0.5;
    _settleTo(open ? 1 : 0);
  }

  void _settleTo(double target, {Duration? duration}) {
    final remaining = (target - progress).abs();
    if (remaining < 0.001) {
      _animation.value = target;
      return;
    }
    _animation.animateTo(
      target,
      duration:
          duration ??
          Duration(milliseconds: math.max(80, (240 * remaining).round())),
      curve: Curves.easeOutCubic,
    );
  }

  static void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();
}

/// ZH
/// 让后代（含 Markdown 内的识别器）拿到同一个推入式侧栏控制器。
///
/// EN
/// Give descendants (including recognizers inside Markdown) the same push-style sidebar controller.
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

/// ZH
/// 推入式侧栏：侧栏铺在底层，内容层随进度右移、缩小并圆角裁切。
///
/// 交互约定：内层横向滚动组件（表格、代码块等）在手势竞技场里优先；
/// 打开时内容层被透明关闭层覆盖，点击或左拖都收起；侧栏上任意位置左滑也收起。
/// 侧栏背景铺满；侧栏内容按 [PushMenuController.menuSlide] 与进度自行滑入。
/// 推入过程中侧栏层整体压暗，完全打开后恢复；对话层同时淡入浅色蒙版，
/// 视觉重心留在侧栏。
///
/// EN
/// Push-style sidebar: sidebar below; content layer moves right, scales down, clips rounded.
///
/// Interaction: inner horizontal scrollers (tables, code blocks, etc.) win the gesture
/// arena first; when open, taps or left drags close via a transparent layer, and a left
/// swipe anywhere also closes. The sidebar background fills the screen; sidebar content
/// slides in by itself per [PushMenuController.menuSlide] and progress. The sidebar layer
/// dims during the push and restores when fully open, while the conversation layer fades
/// in a light veil, keeping visual focus on the sidebar.
class PushMenu extends StatefulWidget {
  const PushMenu({
    super.key,
    required this.menu,
    required this.child,
    this.openFraction = 0.8,
    this.contentScale = 0.95,
    this.cornerRadius = 32,
    this.menuSlideFraction = 1,
    this.duration = const Duration(milliseconds: 300),
  });

  final Widget menu;
  final Widget child;

  /// ZH
  /// 打开后内容层右移的距离占屏宽的比例。
  ///
  /// EN
  /// Fraction of screen width the content layer moves right when open.
  final double openFraction;

  /// ZH
  /// 打开后内容层的缩放比例。
  ///
  /// EN
  /// Scale applied to the content layer when open.
  final double contentScale;

  /// ZH
  /// 打开后内容层的圆角。
  ///
  /// EN
  /// Corner radius of the content layer when open.
  final double cornerRadius;

  /// ZH
  /// 侧栏内容从左侧滑入的距离占屏宽的比例；侧栏背景保持铺满。
  ///
  /// EN
  /// Fraction of screen width sidebar content slides from the left; background stays full-screen.
  final double menuSlideFraction;

  final Duration duration;

  @override
  State<PushMenu> createState() => _PushMenuState();
}

class _PushMenuState extends State<PushMenu> with TickerProviderStateMixin {
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
        // ZH
        // 内容层缩放后左右各留出一条空白；扣掉左留白，搜索展开到 1 时
        // 对话层恰好完全移出屏幕，不会在搜索框满宽后继续滑动。
        //
        // EN
        // Scaling leaves strips on both sides; subtracting the left strip moves the conversation
        // fully off screen at search progress 1, so it stops sliding once search is full width.
        _controller.searchTravel = math.max(
          0.0,
          constraints.maxWidth -
              _controller.travel -
              constraints.maxWidth * (1 - widget.contentScale) / 2,
        );
        // ZH
        // 侧栏内容宽度按官方实测收在可见侧栏内：右内缩 = 被内容层盖住的部分。
        //
        // EN
        // Per official measurements, sidebar content stays visible: right inset = covered part.
        _controller.openInset = math.max(
          0.0,
          constraints.maxWidth * (1 - widget.openFraction),
        );
        _controller.menuSlide = constraints.maxWidth * widget.menuSlideFraction;
        return PushMenuScope(
          controller: _controller,
          child: AnimatedBuilder(
            animation: _controller.repaint,
            builder: (context, child) {
              final progress = _controller.progress;
              return PopScope<void>(
                canPop: progress == 0,
                onPopInvokedWithResult: (didPop, _) {
                  if (didPop) return;
                  if (_controller.backHandler?.call() ?? false) return;
                  _controller.close();
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Offstage(
                        offstage: progress == 0,
                        child: ExcludeFocus(
                          excluding: progress == 0,
                          // ZH
                          // 侧栏上任意位置左滑都能收起。
                          //
                          // EN
                          // Left swiping anywhere on the sidebar closes it.
                          child: RepaintBoundary(
                            child: PushMenuSwipeDetector(child: widget.menu),
                          ),
                        ),
                      ),
                    ),
                    if (progress > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            key: const Key('push-menu-scrim'),
                            // ZH
                            // 压暗侧栏层并随打开淡出，对话层保持原亮度。
                            //
                            // EN
                            // Sidebar dims as it opens; conversation brightness unchanged.
                            color: const Color(0xFF000000)
                                .withValues(alpha: 0.17 * (1 - progress)),
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
            // ZH
            // 缩放期间复用整页的栅格缓存，避免逐帧重绘消息列表。
            //
            // EN
            // Reuse page raster cache while scaling; avoid per-frame message-list repaints.
            child: RepaintBoundary(child: child),
          ),
        ),
        if (progress > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                key: const Key('push-menu-content-veil'),
                // ZH
                // 浅色蒙版随进度淡入：全开后对话层变淡，视觉重心留在侧栏。
                // 亮色 70% 为官方逐帧实测值。
                //
                // EN
                // Light veil fades in; at full open conversation dims, focus stays on sidebar.
                // 70% in light mode is the per-frame value measured from the official app.
                color: const Color(0xFFFFFFFF).withValues(
                  alpha:
                      (Theme.of(context).brightness == Brightness.dark
                          ? 0.08
                          : 0.7) *
                      progress,
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
      offset: Offset(
        _controller.travel * progress +
            _controller.searchTravel * _controller.searchProgress,
        0,
      ),
      child: Transform.scale(
        scale: scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: progress <= 0 || _controller.searchProgress >= 1
                ? const []
                : [
                    BoxShadow(
                      // ZH
                      // 搜索展开时阴影同步淡出，避免留边。
                      //
                      // EN
                      // Shadow fades out with search expansion to avoid visible edges.
                      color: const Color(0xFF000000).withValues(
                        alpha: 0.06 * (1 - _controller.searchProgress),
                      ),
                      blurRadius: 20,
                      offset: const Offset(-4, 0),
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

/// ZH
/// 把横向拖动转给最近的 [PushMenuController]；不在侧栏内时原样返回。
///
/// 作为内容层的祖先使用时，内层横向滚动组件会先赢得手势竞技场；
/// 放进 [SelectionArea] 内层时，则先于文本选择识别器注册，避免被吞。
///
/// EN
/// Forward horizontal drags to the nearest [PushMenuController]; otherwise return the child.
///
/// As an ancestor of the content layer, inner horizontal scrollers win the gesture arena first;
/// inside [SelectionArea], it registers before text selection so drags are not swallowed.
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
