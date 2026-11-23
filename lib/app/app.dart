import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/chat/chat_controller.dart';
import '../features/chat/chat_page.dart';
import '../features/chat/speech/speech_controller.dart';
import '../features/chat/upload_tasks.dart';
import '../features/history/history_section.dart';
import '../features/sessions/session_drawer.dart';
import '../features/settings/settings_page.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/models/types.dart';
import '../shared/prefs/font_scale_store.dart';
import '../shared/prefs/theme_store.dart';
import '../shared/prefs/user_metadata_store.dart';
import 'localization.dart';
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
    return ShadApp(
      title: 'SeekChat',
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
      home: const ChatHome(),
    );
  }
}

/// ZH
/// 根页面：打开最近会话（没有则为空对话），并接线会话抽屉与设置。
///
/// EN
/// Root page: open the latest session (or an empty chat) and wire the Session Drawer and settings.
class ChatHome extends ConsumerStatefulWidget {
  const ChatHome({super.key});

  @override
  ConsumerState<ChatHome> createState() => _ChatHomeState();
}

class _ChatHomeState extends ConsumerState<ChatHome> {
  String? _selectedId;
  bool _draft = false;
  bool _openedLatest = false;
  int _focusRequests = 0;

  /// ZH
  /// 导入替换数据后递增，强制重建聊天页，丢弃旧会话的界面状态。
  ///
  /// EN
  /// Incremented after import replaces data, forcing a chat page rebuild and dropping old UI state.
  int _historyEpoch = 0;

  /// ZH
  /// 最近一次构建出的当前会话 id；列表数据变化时与它比较，
  /// 只有当前会话变了才重建整页（列表性能 P2）。
  ///
  /// EN
  /// Current session id from the last build; compared when the list data changes,
  /// so the whole page rebuilds only when the current session changes (list perf P2).
  String? _currentId;

  /// ZH
  /// 已创建但首条消息尚未落库的会话；此间列表还没有它，不能回退到旧会话。
  ///
  /// EN
  /// Session created but first message not stored; unlisted, so do not fall back to an old one.
  String? _pendingCreatedId;

  /// ZH
  /// 冷启动打开最近会话；空列表保持空对话。
  ///
  /// EN
  /// Cold start opens the latest session; an empty list keeps an empty chat.
  String? _current(List<SessionSummary> sessions) {
    if (_draft) return null;
    if (!_openedLatest) {
      _openedLatest = true;
      if (sessions.isNotEmpty) _selectedId = sessions.first.id;
    }
    final selected = _selectedId;
    if (selected != null) {
      final listed = sessions.any((item) => item.id == selected);
      if (listed && selected == _pendingCreatedId) _pendingCreatedId = null;
      if (listed || selected == _pendingCreatedId) return selected;
    }
    return sessions.isEmpty ? null : sessions.first.id;
  }

  void _newChat() {
    setState(() {
      _draft = true;
      _focusRequests++;
    });
  }

  void _open(String sessionId) {
    setState(() {
      _draft = false;
      _selectedId = sessionId;
      _pendingCreatedId = null;
    });
  }

  void _created(String sessionId) {
    setState(() {
      _draft = false;
      _selectedId = sessionId;
      _pendingCreatedId = sessionId;
    });
  }

  void _deleted(String sessionId) {
    if (_selectedId != sessionId) return;
    setState(() {
      _selectedId = null;
      _pendingCreatedId = null;
    });
  }

  void _discarded() {
    setState(() {
      _selectedId = null;
      _pendingCreatedId = null;
      _draft = true;
    });
  }

  void _stopAllGenerations() {
    for (final controller in ref.read(activeChatControllersProvider)) {
      controller.stop();
    }
  }

  /// ZH
  /// 导入成功后回到新对话：旧消息、草稿与上传任务都不能跨数据替换保留。
  ///
  /// EN
  /// After a successful import, start a new chat: old messages, drafts and uploads must not survive.
  void _historyImported() {
    ref.read(uploadTasksProvider.notifier).clear();
    setState(() {
      _historyEpoch++;
      _selectedId = null;
      _pendingCreatedId = null;
      _draft = true;
    });
  }

  void _cancelSession(String sessionId) {
    for (final controller in ref.read(activeChatControllersProvider)) {
      if (controller.sessionId == sessionId) controller.stop();
    }
  }

  Future<void> _openSettings() => showSettingsSheet(
    context,
    dataManagement: HistorySection(
      stopGeneration: _stopAllGenerations,
      onImported: _historyImported,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // ZH
    // 只订阅加载阶段：会话数据变化（标题、时间、排序）由监听消化，
    // 当前会话不变时不重建整页。
    //
    // EN
    // Watch only the load phase: changes to session data (title, time, order) go through
    // the listener, so the page does not rebuild while the current session stays the same.
    final phase = ref.watch(
      sessionsProvider.select(
        (value) => value.when(
          data: (_) => _SessionsPhase.data,
          loading: () => _SessionsPhase.loading,
          error: (_, _) => _SessionsPhase.error,
        ),
      ),
    );
    ref.listen<AsyncValue<List<SessionSummary>>>(sessionsProvider, (_, next) {
      final sessions = next.value;
      if (sessions == null) return;
      final current = _current(sessions);
      if (current != _currentId) setState(() => _currentId = current);
    });
    switch (phase) {
      case _SessionsPhase.data:
        final current = _current(ref.read(sessionsProvider).requireValue);
        _currentId = current;
        return ChatPage(
          key: ValueKey(_historyEpoch),
          sessionId: current,
          focusRequest: _focusRequests,
          onNewChat: _newChat,
          onSessionCreated: _created,
          onSessionDiscarded: _discarded,
          drawer: SessionDrawer(
            currentSessionId: current,
            onOpen: _open,
            onOpenSettings: () => unawaited(_openSettings()),
            cancelSession: _cancelSession,
            onDeleted: _deleted,
          ),
        );
      case _SessionsPhase.loading:
        return const _ChatLoading();
      case _SessionsPhase.error:
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.sessionsLoadFailed),
                const SizedBox(height: 8),
                ShadButton.outline(
                  onPressed: () => ref.invalidate(sessionsProvider),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// ZH
/// 会话来源的加载阶段；数据变化不切换阶段，不触发重建。
///
/// EN
/// Load phase of the session source; data changes do not switch phases or trigger rebuilds.
enum _SessionsPhase { loading, error, data }

/// ZH
/// 会话列表首帧：不确定进度条、3 条骨架与加载文案（ui.md §1.3）。
///
/// EN
/// Session list first frame: progress bar, three skeletons and a loading label (ui.md §1.3).
class _ChatLoading extends StatelessWidget {
  const _ChatLoading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    Widget skeleton(double width) => Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: width,
        child: Container(
          height: 14,
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(7),
          ),
        ),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ShadProgress(
              minHeight: 2,
              backgroundColor: colors.muted,
              color: colors.primary,
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  skeleton(0.7),
                  const SizedBox(height: 12),
                  skeleton(0.85),
                  const SizedBox(height: 12),
                  skeleton(0.55),
                  const SizedBox(height: 24),
                  Text(
                    l10n.sessionLoading,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
