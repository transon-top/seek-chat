import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/chat/chat_controller.dart';
import '../features/chat/speech/speech_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/prefs/font_scale_store.dart';
import '../shared/prefs/theme_store.dart';
import '../shared/prefs/user_metadata_store.dart';
import 'localization.dart';
import 'router.dart';
import 'theme.dart';

/// ZH
/// 回弹物理：默认 `BouncingScrollPhysics` 按视口高度决定超界距离，能拉出一整屏；
/// 这里改成固定上限的小幅拉伸，起手不跟手，越拉越硬。
///
/// EN
/// Bounce physics: default `BouncingScrollPhysics` scales overscroll by viewport height,
/// which can pull a full screen; this uses a fixed small cap that resists early and stiffens.
class AppBounceScrollPhysics extends BouncingScrollPhysics {
  const AppBounceScrollPhysics({super.parent});

  /// ZH
  /// 单向最大超界距离（逻辑像素）。
  ///
  /// EN
  /// Maximum one-way overscroll distance in logical pixels.
  static const double maxOverscroll = 48;

  /// ZH
  /// 起手跟手比例；随已拉伸距离平方递减，到 [maxOverscroll] 归零。
  ///
  /// EN
  /// Initial follow ratio; decays with the square of stretch and reaches zero at [maxOverscroll].
  static const double _startFactor = 0.3;

  @override
  AppBounceScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      AppBounceScrollPhysics(parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // ZH
    // 手指想去的位置；offset 与手指方向相反。
    //
    // EN
    // Where the finger wants to go; offset points opposite to the finger.
    final target = position.pixels - offset;
    final lower = position.minScrollExtent;
    final upper = position.maxScrollExtent;
    final pastEnd = target > upper;
    final pastStart = target < lower;
    if (!pastEnd && !pastStart) return offset;

    final past = pastEnd
        ? (position.pixels > upper ? position.pixels - upper : 0.0)
        : (position.pixels < lower ? lower - position.pixels : 0.0);
    // ZH
    // 从当前位置到边界的部分保持 1:1，越界部分才受阻力。
    //
    // EN
    // Travel from the current position to the edge stays 1:1; only overscroll is damped.
    final toEdge = pastEnd
        ? (position.pixels < upper ? upper - position.pixels : 0.0)
        : (position.pixels > lower ? position.pixels - lower : 0.0);
    final outTravel = pastEnd
        ? (position.pixels < upper ? target - upper : target - position.pixels)
        : (position.pixels > lower ? lower - target : position.pixels - target);

    final allowed = maxOverscroll - past;
    if (allowed <= 0) return offset.sign * toEdge;
    final remaining = 1 - past / maxOverscroll;
    final damped = outTravel * _startFactor * remaining * remaining;
    return offset.sign * (toEdge + (damped < allowed ? damped : allowed));
  }
}

/// ZH
/// 全局滚动行为：去掉 Android 默认的白色光晕，所有可滚动区域统一橡皮筋回弹。
///
/// EN
/// Global scroll behavior: drop Android's white glow and use rubber-band bounce everywhere.
final appScrollBehavior = const ShadScrollBehavior().copyWith(
  overscroll: false,
  physics: const AppBounceScrollPhysics(
    parent: RangeMaintainingScrollPhysics(),
  ),
);

/// ZH
/// 应用壳：主题、双语、路由与生命周期接线。
///
/// 语言与主题由设置驱动（票 18）；偏好同步读取，首帧即为最终样式。
///
/// EN
/// App shell: theme, bilingual localization, routing and lifecycle wiring.
///
/// Settings drive language and theme (ticket 18); prefs load synchronously, so frame one is final.
class SeekChatApp extends ConsumerStatefulWidget {
  const SeekChatApp({super.key});

  @override
  ConsumerState<SeekChatApp> createState() => _SeekChatAppState();
}

class _SeekChatAppState extends ConsumerState<SeekChatApp>
    with WidgetsBindingObserver {
  /// ZH
  /// 路由在应用生命周期内只建一次，主题与语言重建不重置页面栈。
  ///
  /// EN
  /// The router is built once per app; theme and locale rebuilds keep the page stack.
  late final GoRouter _router = buildAppRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// ZH
  /// 进入后台时把各控制器内存中的流式回复补写一次（architecture.md §3）；
  /// 语音同一时刻只在 `resumed` 下工作（`speech.md` §5.2）。
  ///
  /// EN
  /// On backgrounding, flush each controller's in-memory streaming reply once (architecture.md §3);
  /// voice only works while `resumed` (`speech.md` §5.2).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(ref.read(speechControllerProvider.notifier).handleLifecycle());
    }
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    for (final controller in ref.read(activeChatControllersProvider)) {
      unawaited(controller.flush());
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(userMetadataProvider).locale;
    final chinese = locale == 'zh';
    final fontScale = ref.watch(fontScaleProvider);
    return ShadApp.router(
      title: 'SeekChat',
      routerConfig: _router,
      scrollBehavior: appScrollBehavior,
      theme: buildShadTheme(brightness: Brightness.light, chinese: chinese),
      darkTheme: buildShadTheme(brightness: Brightness.dark, chinese: chinese),
      themeMode: ref.watch(themeModeProvider),
      locale: Locale(locale),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      materialThemeBuilder: (context, theme) =>
          buildAppTheme(brightness: theme.brightness, chinese: chinese),
      // ZH
      // 字号设置位于 Navigator 之上，覆盖所有路由、Sheet 与弹窗。
      //
      // EN
      // Font scale sits above the Navigator, covering all routes, sheets and dialogs.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: fontScale.textScaler(media.textScaler),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
