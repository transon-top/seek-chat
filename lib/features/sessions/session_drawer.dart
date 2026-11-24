import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/logging.dart';
import '../../shared/models/types.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/app_dialogs.dart';
import '../../shared/widgets/push_menu.dart';
import '../../shared/widgets/scroll_edge_fade.dart';
import 'session_search_page.dart';
import 'session_skeleton.dart';

/// ZH
/// 会话列表的响应式来源：drift 在会话增删改后推送新列表。
///
/// EN
/// Reactive session list source: drift pushes a new list after session changes.
final sessionsProvider = StreamProvider.autoDispose<List<SessionSummary>>(
  (ref) => ref.watch(chatRepositoryProvider).watchSessions(),
);

/// ZH
/// 会话分组（ui.md §1.4），保留列表原有顺序。
///
/// EN
/// Session groups (ui.md §1.4), preserving the list's original order.
enum SessionGroup { pinned, today, yesterday, last7Days, earlier }

List<(SessionGroup, List<SessionSummary>)> groupSessions(
  List<SessionSummary> sessions,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(const Duration(days: 7));
  final groups = <SessionGroup, List<SessionSummary>>{};
  for (final session in sessions) {
    if (session.pinned) {
      (groups[SessionGroup.pinned] ??= []).add(session);
      continue;
    }
    final updated = session.updatedAt.toLocal();
    final day = DateTime(updated.year, updated.month, updated.day);
    final group = day == today
        ? SessionGroup.today
        : day == yesterday
        ? SessionGroup.yesterday
        : !day.isBefore(weekStart) && day.isBefore(today)
        ? SessionGroup.last7Days
        : SessionGroup.earlier;
    (groups[group] ??= []).add(session);
  }
  return [
    for (final group in SessionGroup.values)
      if (groups[group] != null) (group, groups[group]!),
  ];
}

AppSidebarColors _sidebarColorsOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppSidebarColors.dark
    : AppSidebarColors.light;

/// ZH
/// 收起推入式侧栏；单独挂载（测试）时无操作。
///
/// EN
/// Close the push-style sidebar; no-op when mounted standalone (tests).
void _closeMenu(BuildContext context) =>
    PushMenuScope.maybeOf(context)?.close();

/// ZH
/// 浮层阴影：会话菜单与删除确认弹窗共用，照搬 chat-demo。
///
/// EN
/// Overlay shadow shared by the session menu and delete dialog, copied from chat-demo.
const _overlayShadows = [
  BoxShadow(color: Color(0x33000000), blurRadius: 1),
  BoxShadow(color: Color(0x05000000), blurRadius: 4),
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 12), blurRadius: 32),
];

/// ZH
/// 左侧会话抽屉：搜索、分组列表、置顶与多选、设置入口。
///
/// 外观照搬 chat-demo 侧边栏的移动端形态（ui.md §1.4）。
///
/// EN
/// Left Session Drawer: search, grouped list, pin and Selection Mode, settings entry.
///
/// Looks copy the mobile shape of the chat-demo sidebar (ui.md §1.4).
class SessionDrawer extends ConsumerStatefulWidget {
  const SessionDrawer({
    super.key,
    required this.currentSessionId,
    required this.onOpen,
    required this.onOpenSettings,
    required this.cancelSession,
    required this.onDeleted,
  });

  final String? currentSessionId;
  final ValueChanged<String> onOpen;
  final VoidCallback onOpenSettings;

  /// ZH
  /// 删除会话前取消其进行中的流（api.md §9.1）。
  ///
  /// EN
  /// Cancel an in-flight stream before deleting its session (api.md §9.1).
  final ValueChanged<String> cancelSession;
  final ValueChanged<String> onDeleted;

  @override
  ConsumerState<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends ConsumerState<SessionDrawer> {
  bool _selecting = false;
  bool _searching = false;
  final Set<String> _selected = {};
  final FocusNode _searchFocus = FocusNode();
  PushMenuController? _menuController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PushMenuScope.maybeOf(context);
    if (controller == _menuController) return;
    _menuController?.removeListener(_onMenuChanged);
    _menuController = controller;
    _menuController?.addListener(_onMenuChanged);
  }

  @override
  void dispose() {
    _menuController?.removeListener(_onMenuChanged);
    _menuController?.backHandler = null;
    _searchFocus.dispose();
    super.dispose();
  }

  /// ZH
  /// 抽屉被点遮罩或左滑收起时，顺带退出多选与搜索，避免下次打开还停在
  /// 选择态或保留搜索内容。
  ///
  /// EN
  /// When the drawer closes via scrim tap or left swipe, also leave Selection Mode and
  /// search, so the next open does not stay in selection or keep the search query.
  void _onMenuChanged() {
    if (!mounted) return;
    final progress = _menuController?.progress ?? 0;
    // ZH
    // 官方从搜索态收起时先回抽屉页再滑出，而不是留搜索页到最后再跳回。
    //
    // EN
    // The official app returns from search to the drawer before sliding out, not at the very end.
    if (_searching && progress < 1) {
      _searchFocus.unfocus();
      _menuController?.resetSearch();
      _menuController?.backHandler = null;
      setState(() => _searching = false);
    }
    if (progress > 0) return;
    if (_selecting) _exitSelection();
  }

  void _enterSelection([String? sessionId]) {
    setState(() {
      _selecting = true;
      _selected.clear();
      if (sessionId != null) _selected.add(sessionId);
    });
    _menuController?.backHandler = _handleBack;
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    _menuController?.backHandler = null;
  }

  /// ZH
  /// 系统返回：搜索先收键盘再收回搜索，多选先退出选择，都不关闭抽屉。
  ///
  /// EN
  /// System back: search hides the keyboard first, then closes; selection exits; drawer stays.
  bool _handleBack() {
    if (_searching) {
      if (_searchFocus.hasFocus) {
        _searchFocus.unfocus();
      } else {
        unawaited(_closeSearch());
      }
      return true;
    }
    if (!_selecting) return false;
    _exitSelection();
    return true;
  }

  void _toggle(String sessionId) {
    setState(() {
      if (!_selected.remove(sessionId)) _selected.add(sessionId);
    });
  }

  void _openSearch() {
    setState(() => _searching = true);
    final controller = _menuController;
    if (controller == null) return;
    controller.backHandler = _handleBack;
    unawaited(controller.searchOpen());
  }

  Future<void> _closeSearch() async {
    final controller = _menuController;
    if (controller != null) await controller.searchClose();
    if (!mounted) return;
    _searchFocus.unfocus();
    controller?.backHandler = null;
    setState(() => _searching = false);
  }

  void _openSearchResult(String id) {
    _searchFocus.unfocus();
    _closeMenu(context);
    if (_menuController == null && mounted) {
      setState(() => _searching = false);
    }
    widget.onOpen(id);
  }

  Future<void> _pinSession(SessionSummary session) => ref
      .read(chatRepositoryProvider)
      .setSessionsPinned([session.id], !session.pinned);

  Future<void> _pinSelected(List<SessionSummary> selected) async {
    if (selected.isEmpty) return;
    final pin = !selected.every((session) => session.pinned);
    await ref
        .read(chatRepositoryProvider)
        .setSessionsPinned(selected.map((session) => session.id), pin);
    if (mounted) _exitSelection();
  }

  Future<void> _deleteSelected(List<SessionSummary> selected) async {
    if (selected.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await _confirmDelete(
      context,
      l10n.deleteSessionsTitle(selected.length),
    );
    if (confirmed != true || !mounted) return;
    final repository = ref.read(chatRepositoryProvider);
    final orphans = <Attachment>[];
    for (final session in selected) {
      widget.cancelSession(session.id);
      orphans.addAll(await repository.deleteSession(session.id));
      widget.onDeleted(session.id);
    }
    try {
      await ref.read(attachmentStoreProvider).deleteAttachments(orphans);
    } on Object catch (error) {
      // ZH
      // 原件删除失败不阻塞界面切换；启动时的孤儿清理会兜底。
      //
      // EN
      // Source deletion failure does not block UI changes; startup orphan cleanup covers it.
      debugLog('deleting attachments failed', error);
    }
    if (mounted) _exitSelection();
  }

  Future<void> _delete(SessionSummary session) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await _confirmDelete(context, l10n.deleteSession);
    if (confirmed != true || !mounted) return;
    widget.cancelSession(session.id);
    final orphaned = await ref
        .read(chatRepositoryProvider)
        .deleteSession(session.id);
    widget.onDeleted(session.id);
    try {
      await ref.read(attachmentStoreProvider).deleteAttachments(orphaned);
    } on Object catch (error) {
      // ZH
      // 原件删除失败不阻塞界面切换；启动时的孤儿清理会兜底。
      //
      // EN
      // Source deletion failure does not block UI changes; startup orphan cleanup covers it.
      debugLog('deleting attachments failed', error);
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, String title) {
    final l10n = AppLocalizations.of(context)!;
    return showAppConfirmDialog(
      context,
      title: title,
      description: l10n.deleteSessionDescription,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.delete,
      destructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    final sessions = ref.watch(sessionsProvider);
    final items = sessions.value ?? const <SessionSummary>[];
    final selected = [
      for (final session in items)
        if (_selected.contains(session.id)) session,
    ];
    final allPinned =
        selected.isNotEmpty && selected.every((session) => session.pinned);
    // ZH
    // 内容层打开后会盖住右侧一条；操作控件不能落到那条下面。
    //
    // EN
    // The open content layer covers a right strip; action controls must not fall under it.
    final controller = PushMenuScope.maybeOf(context);
    final openInset = controller?.openInset ?? 0;

    final drawerBody = SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 10, 14 + openInset, 0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _selecting
                    ? _SelectionHeader(
                        key: const ValueKey('selection-header'),
                        count: selected.length,
                        onClose: _exitSelection,
                      )
                    : _SearchEntry(
                        key: const ValueKey('search-entry'),
                        onTap: _openSearch,
                      ),
              ),
            ),
            Expanded(
              child: sessions.when(
                data: (items) => items.isEmpty
                    ? Center(
                        child: Text(
                          l10n.noSessions,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.labelTertiary,
                          ),
                        ),
                      )
                    : _SessionList(
                        sessions: items,
                        currentSessionId: widget.currentSessionId,
                        selecting: _selecting,
                        selected: _selected,
                        onOpen: (id) {
                          _closeMenu(context);
                          widget.onOpen(id);
                        },
                        onToggle: _toggle,
                        onSelect: () => _enterSelection(),
                        onRename: (session, title) => ref
                            .read(chatRepositoryProvider)
                            .renameSession(session.id, title.trim()),
                        onDelete: _delete,
                        onPin: _pinSession,
                        onMultiSelect: (session) => _enterSelection(session.id),
                      ),
                loading: () => const SessionListSkeleton(),
                error: (error, stackTrace) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.sessionsLoadFailed,
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.labelTertiary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ShadButton.outline(
                        onPressed: () => ref.invalidate(sessionsProvider),
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_selecting)
              _SelectionActions(
                enabled: selected.isNotEmpty,
                pinned: allPinned,
                onPin: () => _pinSelected(selected),
                onDelete: () => _deleteSelected(selected),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('drawer-settings'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      _closeMenu(context);
                      widget.onOpenSettings();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.settings,
                            size: 20,
                            color: colors.labelPrimary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n.settingsEntry,
                            style: TextStyle(
                              fontSize: 16,
                              height: 22 / 16,
                              color: colors.labelPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final searchPage = SessionSearchPage(
      focusNode: _searchFocus,
      onBack: () => unawaited(_closeSearch()),
      onOpen: _openSearchResult,
    );
    Widget content;
    if (controller == null) {
      content = _searching ? searchPage : drawerBody;
    } else {
      content = AnimatedBuilder(
        animation: controller.animation,
        builder: (context, _) => Transform.translate(
          // ZH
          // 进度 0 时整体左移一段，随打开滑回原位。
          //
          // EN
          // At progress 0 the content is shifted left and slides back as the drawer opens.
          offset: Offset((controller.progress - 1) * controller.menuSlide, 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ZH
              // 官方式：搜索页从侧栏胶囊位置展开，旧列表原地淡出。
              //
              // EN
              // Official style: search expands from the sidebar pill while the old list fades out.
              AnimatedBuilder(
                animation: controller.searchAnimation,
                child: drawerBody,
                builder: (context, child) => Opacity(
                  opacity: _searching ? 1 - controller.searchProgress : 1,
                  child: IgnorePointer(ignoring: _searching, child: child),
                ),
              ),
              if (_searching) searchPage,
            ],
          ),
        ),
      );
    }
    return Material(color: colors.fill, child: content);
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    return Semantics(
      button: true,
      label: l10n.searchChatsPlaceholder,
      child: InkWell(
        key: const Key('drawer-search'),
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.inputFill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 16, color: colors.labelTertiary),
              const SizedBox(width: 8),
              Text(
                l10n.searchChatsPlaceholder,
                style: TextStyle(
                  fontSize: 16,
                  height: 22 / 16,
                  color: colors.labelTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 叠在列表第一行分组头上的多选入口，与最近的分组标题同一行。
///
/// EN
/// Selection Mode entry overlaid on the first group header, on the latest group's row.
class _SelectButton extends StatelessWidget {
  const _SelectButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    return Semantics(
      button: true,
      label: l10n.selectChats,
      child: InkWell(
        key: const Key('drawer-select'),
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            LucideIcons.listChecks,
            size: 16,
            color: colors.labelTertiary,
          ),
        ),
      ),
    );
  }
}

class _SelectionHeader extends StatelessWidget {
  const _SelectionHeader({
    super.key,
    required this.count,
    required this.onClose,
  });

  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              // ZH
              // 与下方分组标题的左内边距 10 对齐。
              //
              // EN
              // Aligns with the 10 left padding of group headers below.
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                count == 0 ? l10n.selectionTitle : l10n.selectionCount(count),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 22 / 16,
                  fontWeight: FontWeight.w500,
                  color: colors.labelPrimary,
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('drawer-selection-close'),
              onTap: onClose,
              customBorder: const CircleBorder(),
              child: Semantics(
                button: true,
                label: l10n.exitSelection,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.menuFill,
                    shape: BoxShape.circle,
                    boxShadow: _overlayShadows,
                  ),
                  child: Icon(
                    LucideIcons.x,
                    size: 16,
                    color: colors.labelPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionActions extends StatelessWidget {
  const _SelectionActions({
    required this.enabled,
    required this.pinned,
    required this.onPin,
    required this.onDelete,
  });

  final bool enabled;
  final bool pinned;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: _SelectionAction(
                key: const Key('drawer-selection-pin'),
                icon: pinned ? LucideIcons.pinOff : LucideIcons.pin,
                label: pinned ? l10n.unpinSession : l10n.pinSession,
                color: enabled ? colors.labelPrimary : colors.labelTertiary,
                onTap: enabled ? onPin : null,
              ),
            ),
            Container(width: 1, height: 24, color: colors.border),
            Expanded(
              child: _SelectionAction(
                key: const Key('drawer-selection-delete'),
                icon: LucideIcons.trash2,
                label: l10n.delete,
                color: enabled ? colors.danger : colors.labelTertiary,
                onTap: enabled ? onDelete : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionAction extends StatelessWidget {
  const _SelectionAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            height: 22 / 16,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _SessionList extends StatefulWidget {
  const _SessionList({
    required this.sessions,
    required this.currentSessionId,
    required this.selecting,
    required this.selected,
    required this.onOpen,
    required this.onToggle,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
    required this.onPin,
    required this.onMultiSelect,
  });

  final List<SessionSummary> sessions;
  final String? currentSessionId;
  final bool selecting;
  final Set<String> selected;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelect;
  final Future<void> Function(SessionSummary session, String title) onRename;
  final Future<void> Function(SessionSummary session) onDelete;
  final ValueChanged<SessionSummary> onPin;
  final ValueChanged<SessionSummary> onMultiSelect;

  @override
  State<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<_SessionList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// ZH
  /// 会话行固定高度；吸顶标签按它推算各分组头的滚动位置。
  ///
  /// EN
  /// Fixed session row height; the sticky label uses it to compute group header offsets.
  static const _rowExtent = 44.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    final groups = groupSessions(widget.sessions, DateTime.now());
    // ZH
    // 分组头高度随字号缩放；固定值在非标准字号下会与子项实际高度不一致。
    //
    // EN
    // Header height scales with font size; a fixed value would mismatch item heights at other sizes.
    final headerExtent =
        7 + MediaQuery.textScalerOf(context).scale(14) * 22 / 14;
    final labels = [
      for (final (group, _) in groups)
        switch (group) {
          SessionGroup.pinned => l10n.sessionGroupPinned,
          SessionGroup.today => l10n.sessionGroupToday,
          SessionGroup.yesterday => l10n.sessionGroupYesterday,
          SessionGroup.last7Days => l10n.sessionGroupLast7Days,
          SessionGroup.earlier => l10n.sessionGroupEarlier,
        },
    ];
    // ZH
    // 各分组头在滚动坐标里的起点，供吸顶标签判定当前分组与顶出位移。
    //
    // EN
    // Group header offsets in scroll coordinates, for the sticky label's group and push-out shift.
    final headerOffsets = <double>[];
    var cursor = 0.0;
    for (final (index, (_, items)) in groups.indexed) {
      if (index > 0) cursor += 20; // 16 gap + 4 above title
      headerOffsets.add(cursor);
      cursor += headerExtent + items.length * _rowExtent;
    }
    final list = ScrollEdgeFade(
      controller: _controller,
      color: colors.fill,
      // ZH
      // 顶部渐隐从吸顶标签下缘开始，标签本身不参与渐隐。
      //
      // EN
      // Top fade starts below the sticky label; the label itself does not fade.
      topInset: headerExtent,
      child: CustomScrollView(
        controller: _controller,
        slivers: [
          for (final (index, (_, items)) in groups.indexed) ...[
            if (index > 0)
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            // ZH
            // 与 chat-demo 一致：分组标题上方留 4；首组不留，使搜索框下缘
            // 到首个标题的距离与 DeepSeek 一致（17）。
            //
            // EN
            // Match chat-demo: leave 4 above group headers, none for the first group, so
            // search to first title spacing matches DeepSeek (17).
            if (index > 0) const SliverToBoxAdapter(child: SizedBox(height: 4)),
            // ZH
            // 首组标签常驻吸顶行，列表里只留高度，避免同一标签出现两次。
            //
            // EN
            // First label stays sticky; the list stores only its height to avoid a duplicate.
            index == 0
                ? SliverToBoxAdapter(child: SizedBox(height: headerExtent))
                : SliverToBoxAdapter(
                    child: _GroupHeader(
                      colors: colors,
                      extent: headerExtent,
                      label: labels[index],
                    ),
                  ),
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final session = items[index];
                return _SessionRow(
                  session: session,
                  current: session.id == widget.currentSessionId,
                  selecting: widget.selecting,
                  selected: widget.selected.contains(session.id),
                  onOpen: () => widget.onOpen(session.id),
                  onToggle: () => widget.onToggle(session.id),
                  onRename: (title) => widget.onRename(session, title),
                  onDelete: () => widget.onDelete(session),
                  onPin: () => widget.onPin(session),
                  onMultiSelect: () => widget.onMultiSelect(session),
                );
              },
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
    );
    return Stack(
      children: [
        list,
        // ZH
        // 照搬真机：日期标签一次只吸一条，下一条到来时把当前条顶出；
        // 多选入口属于吸顶行，随标签一起顶出。
        //
        // EN
        // Match the real app: only one date label sticks at a time, pushed out by the next;
        // the Selection Mode entry belongs to the sticky row and is pushed out with it.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: headerExtent,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final position = _controller.hasClients
                    ? math.max(0.0, _controller.offset)
                    : 0.0;
                var active = 0;
                while (active + 1 < headerOffsets.length &&
                    headerOffsets[active + 1] <= position) {
                  active++;
                }
                final next = active + 1;
                final shift = next < headerOffsets.length
                    ? math.min(
                        0.0,
                        headerOffsets[next] - position - headerExtent,
                      )
                    : 0.0;
                return Transform.translate(
                  offset: Offset(0, shift),
                  child: _GroupHeader(
                    colors: colors,
                    extent: headerExtent,
                    label: labels[active],
                    trailing: widget.selecting
                        ? null
                        : _SelectButton(onPressed: widget.onSelect),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// ZH
/// 分组标题；高度 = 上 4 + 行高 22（随字号缩放）+ 下 3。
///
/// EN
/// Group header; height = 4 top + 22 line (scaled) + 3 bottom.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.colors,
    required this.label,
    required this.extent,
    this.trailing,
  });

  final AppSidebarColors colors;
  final String label;
  final double extent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: extent,
    child: ColoredBox(
      color: colors.fill,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  fontWeight: FontWeight.w500,
                  color: colors.labelTertiary,
                ),
              ),
            ),
          ),
          if (trailing != null)
            Positioned(right: 0, top: (extent - 44) / 2, child: trailing!),
        ],
      ),
    ),
  );
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required this.session,
    required this.current,
    required this.selecting,
    required this.selected,
    required this.onOpen,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
    required this.onPin,
    required this.onMultiSelect,
  });

  final SessionSummary session;
  final bool current;
  final bool selecting;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final ValueChanged<String> onRename;
  final Future<void> Function() onDelete;
  final VoidCallback onPin;
  final VoidCallback onMultiSelect;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  final _menu = ShadPopoverController();
  final _rename = TextEditingController();
  final _renameFocus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _renameFocus.addListener(_onRenameFocusChanged);
  }

  @override
  void dispose() {
    _menu.dispose();
    _rename.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  String get _displayTitle => widget.session.title.isEmpty
      ? AppLocalizations.of(context)!.untitledChat
      : widget.session.title;

  void _onRenameFocusChanged() {
    if (!mounted) return;
    if (!_renameFocus.hasFocus && _editing) _finishEditing();
  }

  void _startEditing() {
    _menu.hide();
    _rename.text = _displayTitle;
    _rename.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _displayTitle.length,
    );
    setState(() => _editing = true);
  }

  /// ZH
  /// 提交规则同 chat-demo：空输入或未改动不写库。
  ///
  /// EN
  /// Commit rules match chat-demo: empty or unchanged input is not persisted.
  void _finishEditing({bool commit = true}) {
    if (!_editing) return;
    final title = _rename.text.trim();
    setState(() => _editing = false);
    if (commit && title.isNotEmpty && title != _displayTitle) {
      widget.onRename(title);
    }
  }

  Future<void> _delete() async {
    _menu.hide();
    await widget.onDelete();
  }

  void _showMenu() {
    _menu.hide();
    HapticFeedback.mediumImpact();
    _menu.show();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    if (_editing) {
      return Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.inputFill,
          border: Border.all(color: colors.brand),
          borderRadius: BorderRadius.circular(16),
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _finishEditing(commit: false),
          },
          child: Center(
            child: ShadInput(
              key: ValueKey('session-rename-${widget.session.id}'),
              controller: _rename,
              focusNode: _renameFocus,
              autofocus: true,
              style: TextStyle(
                fontSize: 16,
                height: 22 / 16,
                color: colors.labelPrimary,
              ),
              cursorColor: colors.brand,
              padding: EdgeInsets.zero,
              decoration: ShadDecoration.none,
              onSubmitted: (_) => _finishEditing(),
              onPressedOutside: (_) => _finishEditing(),
            ),
          ),
        ),
      );
    }
    final row = InkWell(
      key: ValueKey('session-row-${widget.session.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: widget.selecting ? widget.onToggle : widget.onOpen,
      onLongPress: widget.selecting ? null : _showMenu,
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 12, right: 12),
        decoration: BoxDecoration(
          color: widget.current ? colors.activeItemFill : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _AnimatedSelectionSlot(
              selecting: widget.selecting,
              selected: widget.selected,
              colors: colors,
            ),
            Expanded(
              child: Text(
                _displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 22 / 16,
                  color: widget.current && !widget.selecting
                      ? colors.activeItemForeground
                      : colors.labelPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return ShadPopover(
      controller: _menu,
      padding: EdgeInsets.zero,
      decoration: ShadDecoration(
        color: colors.menuFill,
        shadows: _overlayShadows,
        border: ShadBorder.fromBorderSide(
          const ShadBorderSide(),
          radius: BorderRadius.circular(16),
        ),
        focusedBorder: ShadBorder.fromBorderSide(
          const ShadBorderSide(),
          radius: BorderRadius.circular(16),
        ),
        secondaryBorder: ShadBorder.none,
        secondaryFocusedBorder: ShadBorder.none,
      ),
      popover: (context) => SizedBox(
        width: math.min(240, MediaQuery.sizeOf(context).width - 64),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MenuOption(
                key: ValueKey('session-menu-rename-${widget.session.id}'),
                icon: LucideIcons.pencil,
                label: l10n.rename,
                onPressed: _startEditing,
              ),
              _MenuDivider(colors: colors),
              _MenuOption(
                key: ValueKey('session-menu-pin-${widget.session.id}'),
                icon: widget.session.pinned
                    ? LucideIcons.pinOff
                    : LucideIcons.pin,
                label: widget.session.pinned
                    ? l10n.unpinSession
                    : l10n.pinSession,
                onPressed: () {
                  _menu.hide();
                  widget.onPin();
                },
              ),
              _MenuDivider(colors: colors),
              _MenuOption(
                key: ValueKey('session-menu-select-${widget.session.id}'),
                icon: LucideIcons.listChecks,
                label: l10n.selectChats,
                onPressed: () {
                  _menu.hide();
                  widget.onMultiSelect();
                },
              ),
              _MenuDivider(colors: colors),
              _MenuOption(
                key: ValueKey('session-menu-delete-${widget.session.id}'),
                icon: LucideIcons.trash2,
                label: l10n.delete,
                color: colors.danger,
                onPressed: _delete,
              ),
            ],
          ),
        ),
      ),
      child: row,
    );
  }
}

/// ZH
/// 勾选圈槽位：多选时宽度 0 → 32 与透明度一起变化，带动整行文字右移。
///
/// EN
/// Check circle slot: in Selection Mode width goes 0 → 32 with opacity, shifting the row text.
class _AnimatedSelectionSlot extends StatelessWidget {
  const _AnimatedSelectionSlot({
    required this.selecting,
    required this.selected,
    required this.colors,
  });

  final bool selecting;
  final bool selected;
  final AppSidebarColors colors;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOutCubic,
    width: selecting ? 32 : 0,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: 32,
        maxWidth: 32,
        child: AnimatedOpacity(
          opacity: selecting ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: selecting ? 1 : 0.7,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ExcludeSemantics(
                excluding: !selecting,
                child: _SelectionCircle(selected: selected, colors: colors),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({required this.selected, required this.colors});

  final bool selected;
  final AppSidebarColors colors;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? colors.brand : null,
      border: Border.all(color: selected ? colors.brand : colors.labelTertiary),
    ),
    child: selected
        ? const Icon(LucideIcons.check, size: 14, color: Color(0xFFFFFFFF))
        : null,
  );
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider({required this.colors});

  final AppSidebarColors colors;

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: colors.border);
}

/// ZH
/// 菜单项：图标 18 + 文案 16，危险项整体变红。
///
/// EN
/// Menu item: 18 icon + 16 label; destructive items turn red.
class _MenuOption extends StatelessWidget {
  const _MenuOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = _sidebarColorsOf(context);
    final foreground = color ?? colors.labelPrimary;
    return InkWell(
      onTap: onPressed,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  height: 24 / 16,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
