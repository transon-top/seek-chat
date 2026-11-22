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
import '../../shared/widgets/push_menu.dart';
import '../../shared/widgets/scroll_edge_fade.dart';
import 'session_search_page.dart';
import 'session_skeleton.dart';

/// 会话列表的响应式来源：drift 在会话增删改后推送新列表。
final sessionsProvider = StreamProvider.autoDispose<List<SessionSummary>>(
  (ref) => ref.watch(chatRepositoryProvider).watchSessions(),
);

/// 会话分组（ui.md §1.4），保留列表原有顺序。
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

/// 收起推入式侧栏；单独挂载（测试）时无操作。
void _closeMenu(BuildContext context) =>
    PushMenuScope.maybeOf(context)?.close();

/// 浮层阴影：会话菜单与删除确认弹窗共用，照搬 chat-demo。
const _overlayShadows = [
  BoxShadow(color: Color(0x33000000), blurRadius: 1),
  BoxShadow(color: Color(0x05000000), blurRadius: 4),
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 12), blurRadius: 32),
];

/// 左侧会话抽屉：搜索、分组列表、置顶与多选、设置入口。
///
/// 外观照搬 chat-demo 侧边栏的移动端形态（ui.md §1.4）。
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

  /// 删除会话前取消其进行中的流（api.md §9.1）。
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

  /// 抽屉被点遮罩或左滑收起时，顺带退出多选与搜索，避免下次打开还停在
  /// 选择态或保留搜索内容。
  void _onMenuChanged() {
    if (!mounted || (_menuController?.progress ?? 0) > 0) return;
    if (_searching) {
      _searchFocus.unfocus();
      _menuController?.resetSearch();
      _menuController?.backHandler = null;
      setState(() => _searching = false);
    }
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

  /// 系统返回：搜索先收键盘再收回搜索，多选先退出选择，都不关闭抽屉。
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
      // 原件删除失败不阻塞界面切换；启动时的孤儿清理会兜底。
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
      // 原件删除失败不阻塞界面切换；启动时的孤儿清理会兜底。
      debugLog('deleting attachments failed', error);
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, String title) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final sidebar = _sidebarColorsOf(context);
    final dark = theme.brightness == Brightness.dark;
    final width = math.min(380.0, MediaQuery.sizeOf(context).width - 32);
    return showShadDialog<bool>(
      context: context,
      // 照搬 chat-demo：遮罩浅色 36%、深色 60%。
      barrierColor: dark ? const Color(0x99000000) : const Color(0x5C000000),
      builder: (context) => ShadTheme(
        // 只把弹窗内按钮改成 chat-demo 的胶囊形。
        data: ShadTheme.of(context)
            .copyWith(radius: const BorderRadius.all(Radius.circular(999))),
        child: ShadDialog.alert(
          title: Text(title),
          description: Padding(
            // chat-demo 标题与描述间距 12、描述与按钮间距 20。
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l10n.deleteSessionDescription),
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.of(context).pop(false),
              foregroundColor: colors.foreground,
              child: Text(l10n.cancel),
            ),
            ShadButton.destructive(
              onPressed: () => Navigator.of(context).pop(true),
              backgroundColor: sidebar.danger,
              foregroundColor: const Color(0xFFFFFFFF),
              child: Text(l10n.delete),
            ),
          ],
          constraints: BoxConstraints(minWidth: width, maxWidth: width),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          radius: const BorderRadius.all(Radius.circular(24)),
          removeBorderRadiusWhenTiny: false,
          backgroundColor: colors.card,
          border: Border.all(
            color: dark ? const Color(0x0FFFFFFF) : const Color(0x00000000),
          ),
          shadows: _overlayShadows,
          gap: 12,
          titleStyle: TextStyle(
            fontSize: 16,
            height: 24 / 16,
            fontWeight: FontWeight.w500,
            color: colors.foreground,
          ),
          descriptionStyle: TextStyle(
            fontSize: 14,
            height: 22 / 14,
            color: colors.mutedForeground,
          ),
          titleTextAlign: TextAlign.start,
          descriptionTextAlign: TextAlign.start,
          actionsAxis: Axis.horizontal,
          actionsMainAxisAlignment: MainAxisAlignment.end,
          actionsGap: 8,
          expandActionsWhenTiny: false,
        ),
      ),
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
    // 内容层打开后会盖住右侧一条；操作控件不能落到那条下面。
    final controller = PushMenuScope.maybeOf(context);
    final openInset = controller?.openInset ?? 0;

    Widget content = _searching
        ? SessionSearchPage(
            focusNode: _searchFocus,
            onBack: () => unawaited(_closeSearch()),
            onOpen: _openSearchResult,
          )
        : SafeArea(
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
                              onMultiSelect: (session) =>
                                  _enterSelection(session.id),
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
    if (controller != null) {
      content = AnimatedBuilder(
        animation: controller.animation,
        child: content,
        builder: (context, child) => Transform.translate(
          // 进度 0 时整体左移一段，随打开滑回原位。
          offset: Offset((controller.progress - 1) * controller.menuSlide, 0),
          child: child!,
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
            border: Border.all(color: colors.border),
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

/// 叠在列表第一行分组头上的多选入口，与最近的分组标题同一行。
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
              // 与下方分组标题的左内边距 10 对齐。
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    final groups = groupSessions(widget.sessions, DateTime.now());
    // 分组头高度随字号缩放；固定值在非标准字号下会与子项实际高度不一致。
    final headerExtent =
        7 + MediaQuery.textScalerOf(context).scale(14) * 22 / 14;
    final list = ScrollEdgeFade(
      controller: _controller,
      color: colors.fill,
      // 顶部渐隐从吸顶分组头下缘开始，分组头本身不参与渐隐。
      topInset: headerExtent,
      child: CustomScrollView(
        controller: _controller,
        slivers: [
          for (final (index, (group, items)) in groups.indexed) ...[
            if (index > 0)
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            // 与 chat-demo 一致：分组标题上方留 4；首组不留，使搜索框下缘
            // 到首个标题的距离与 DeepSeek 一致（17）。
            if (index > 0) const SliverToBoxAdapter(child: SizedBox(height: 4)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _GroupHeaderDelegate(
                colors: colors,
                extent: headerExtent,
                label: switch (group) {
                  SessionGroup.pinned => l10n.sessionGroupPinned,
                  SessionGroup.today => l10n.sessionGroupToday,
                  SessionGroup.yesterday => l10n.sessionGroupYesterday,
                  SessionGroup.last7Days => l10n.sessionGroupLast7Days,
                  SessionGroup.earlier => l10n.sessionGroupEarlier,
                },
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
        if (!widget.selecting)
          Positioned(
            // 44 高按钮中心对齐首组标题文字中心（标题区 29，文字居中后 18）。
            top: -4,
            right: 0,
            child: _SelectButton(onPressed: widget.onSelect),
          ),
      ],
    );
  }
}

/// 分组标题吸顶；高度 = 上 4 + 行高 22（随字号缩放）+ 下 3。
class _GroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _GroupHeaderDelegate({
    required this.colors,
    required this.label,
    required this.extent,
  });

  final AppSidebarColors colors;
  final String label;
  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 子项高度必须与 extent 一致，否则吸顶头的布局几何不合法。
    return SizedBox(
      height: extent,
      child: ColoredBox(
        color: colors.fill,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 3),
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
    );
  }

  @override
  bool shouldRebuild(covariant _GroupHeaderDelegate oldDelegate) =>
      oldDelegate.label != label ||
      oldDelegate.colors != colors ||
      oldDelegate.extent != extent;
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

  /// 提交规则同 chat-demo：空输入或未改动不写库。
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
      return SizedBox(
        height: 44,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _finishEditing(commit: false),
          },
          child: TextField(
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
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              filled: true,
              fillColor: colors.inputFill,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.brand),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.brand),
              ),
            ),
            onSubmitted: (_) => _finishEditing(),
            onTapOutside: (_) => _finishEditing(),
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

/// 勾选圈槽位：多选时宽度 0 → 32 与透明度一起变化，带动整行文字右移。
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

/// 菜单项：图标 18 + 文案 16，危险项整体变红。
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
