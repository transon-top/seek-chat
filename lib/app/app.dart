import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/chat/chat_controller.dart';
import '../features/chat/chat_page.dart';
import '../features/chat/speech/speech_controller.dart';
import '../features/history/history_section.dart';
import '../features/sessions/session_drawer.dart';
import '../features/settings/settings_page.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/models/types.dart';
import '../shared/prefs/theme_store.dart';
import '../shared/prefs/user_metadata_store.dart';
import 'localization.dart';
import 'theme.dart';

/// 应用壳：主题、双语、路由与生命周期接线。
///
/// 语言与主题由设置驱动（票 18）；偏好同步读取，首帧即为最终样式。
class OpenChatApp extends ConsumerStatefulWidget {
  const OpenChatApp({super.key});

  @override
  ConsumerState<OpenChatApp> createState() => _OpenChatAppState();
}

class _OpenChatAppState extends ConsumerState<OpenChatApp>
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

  /// 进入后台时把各控制器内存中的流式回复补写一次（architecture.md §3）；
  /// 语音同一时刻只在 `resumed` 下工作（`speech.md` §5.2）。
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
    return ShadApp(
      title: 'Open Chat',
      theme: buildShadTheme(brightness: Brightness.light, chinese: chinese),
      darkTheme: buildShadTheme(brightness: Brightness.dark, chinese: chinese),
      themeMode: ref.watch(themeModeProvider),
      locale: Locale(locale),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      materialThemeBuilder: (context, theme) =>
          buildAppTheme(brightness: theme.brightness, chinese: chinese),
      home: const ChatHome(),
    );
  }
}

/// 根页面：打开最近会话（没有则为空对话），并接线会话抽屉与设置。
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

  /// 已创建但首条消息尚未落库的会话；此间列表还没有它，不能回退到旧会话。
  String? _pendingCreatedId;

  /// 冷启动打开最近会话；空列表保持空对话。
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

  void _cancelSession(String sessionId) {
    for (final controller in ref.read(activeChatControllersProvider)) {
      if (controller.sessionId == sessionId) controller.stop();
    }
  }

  Future<void> _openSettings() => showSettingsSheet(
    context,
    dataManagement: HistorySection(stopGeneration: _stopAllGenerations),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(sessionsProvider);
    return sessions.when(
      data: (items) {
        final current = _current(items);
        return ChatPage(
          sessionId: current,
          focusRequest: _focusRequests,
          onNewChat: _newChat,
          onSessionCreated: _created,
          onSessionDiscarded: _discarded,
          drawer: SessionDrawer(
            currentSessionId: current,
            onOpen: _open,
            onNewChat: _newChat,
            onOpenSettings: () => unawaited(_openSettings()),
            cancelSession: _cancelSession,
            onDeleted: _deleted,
          ),
        );
      },
      loading: () => const _ChatLoading(),
      error: (error, stackTrace) => Scaffold(
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
      ),
    );
  }
}

/// 会话列表首帧：不确定进度条、3 条骨架与加载文案（ui.md §1.3）。
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
