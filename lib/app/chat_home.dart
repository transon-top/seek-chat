import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../features/chat/chat_controller.dart';
import '../features/chat/chat_page.dart';
import '../features/chat/upload_tasks.dart';
import '../features/sessions/session_drawer.dart';
import '../features/settings/settings_page.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/models/types.dart';
import '../shared/providers.dart';

/// ZH
/// 根页面：打开最近会话（没有则为空对话），并接线会话抽屉与设置路由。
///
/// EN
/// Root page: open the latest session (or an empty chat) and wire the Session Drawer
/// and settings routes.
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

  void _openSettings({bool focusApiKey = false}) {
    context.push(
      focusApiKey ? SettingsRoutes.accountFocus : SettingsRoutes.root,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // ZH
    // 数据管理页完成导入后递增计数；聊天页据此回到新对话。
    //
    // EN
    // The Data page bumps this after an import; the chat page returns to a new chat.
    ref.listen(historyReloadProvider, (_, _) => _historyImported());
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
          onOpenKeySettings: () => _openSettings(focusApiKey: true),
          drawer: SessionDrawer(
            currentSessionId: current,
            onOpen: _open,
            onOpenSettings: _openSettings,
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
