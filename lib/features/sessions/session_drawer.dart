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

/// 会话列表的响应式来源：drift 在会话增删改后推送新列表。
final sessionsProvider = StreamProvider.autoDispose<List<SessionSummary>>(
  (ref) => ref.watch(chatRepositoryProvider).watchSessions(),
);

/// 会话分组（ui.md §1.4），保留列表原有顺序。
enum SessionGroup { today, yesterday, last7Days, earlier }

List<(SessionGroup, List<SessionSummary>)> groupSessions(
  List<SessionSummary> sessions,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(const Duration(days: 7));
  final groups = <SessionGroup, List<SessionSummary>>{};
  for (final session in sessions) {
    final updated = session.updatedAt.toLocal();
    final day = DateTime(updated.year, updated.month, updated.day);
    final group = day == today
        ? SessionGroup.today
        : day == yesterday
        ? SessionGroup.yesterday
        : !day.isBefore(weekStart) && day.isBefore(today)
        ? SessionGroup.last7Days
        : SessionGroup.earlier;
    groups.putIfAbsent(group, () => []).add(session);
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

const _newChatLightShadows = [
  BoxShadow(color: Color(0x0A4868B2), offset: Offset(0, -2), blurRadius: 2),
  BoxShadow(color: Color(0x176A6F75), offset: Offset(0, 2), blurRadius: 2),
  BoxShadow(color: Color(0x144868B2), offset: Offset(0, 1), blurRadius: 2),
];

const _newChatDarkShadows = [
  BoxShadow(color: Color(0x146A6F75), offset: Offset(0, 2), blurRadius: 4),
];

const _menuShadows = [
  BoxShadow(color: Color(0x33000000), blurRadius: 1),
  BoxShadow(color: Color(0x05000000), blurRadius: 4),
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 12), blurRadius: 32),
];

/// 左侧会话抽屉：分组列表、当前会话高亮、新建、重命名、删除与设置入口。
///
/// 外观照搬 chat-demo 侧边栏的移动端形态（ui.md §1.4）。
class SessionDrawer extends ConsumerWidget {
  const SessionDrawer({
    super.key,
    required this.currentSessionId,
    required this.onOpen,
    required this.onNewChat,
    required this.onOpenSettings,
    required this.cancelSession,
    required this.onDeleted,
  });

  final String? currentSessionId;
  final ValueChanged<String> onOpen;
  final VoidCallback onNewChat;
  final VoidCallback onOpenSettings;

  /// 删除会话前取消其进行中的流（api.md §9.1）。
  final ValueChanged<String> cancelSession;
  final ValueChanged<String> onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    final sessions = ref.watch(sessionsProvider);
    final width = math.min(300.0, MediaQuery.sizeOf(context).width - 48);
    return Drawer(
      width: width,
      elevation: 0,
      backgroundColor: colors.fill,
      shape: const RoundedRectangleBorder(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Text(
                        'Fleepseek',
                        style: TextStyle(
                          fontSize: 20,
                          height: 22 / 20,
                          fontWeight: FontWeight.w600,
                          color: colors.brand,
                        ),
                      ),
                      const Spacer(),
                      Semantics(
                        button: true,
                        label: l10n.close,
                        child: ShadIconButton.ghost(
                          key: const Key('drawer-close'),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(LucideIcons.panelLeft),
                          iconSize: 16,
                          width: 44,
                          height: 44,
                          padding: EdgeInsets.zero,
                          foregroundColor: colors.labelPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _NewChatButton(onPressed: onNewChat),
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
                            currentSessionId: currentSessionId,
                            onOpen: onOpen,
                            onRename: (session, title) => ref
                                .read(chatRepositoryProvider)
                                .renameSession(session.id, title.trim()),
                            onDelete: (session) =>
                                _delete(context, ref, session),
                          ),
                    loading: () => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 80,
                            child: ShadProgress(
                              minHeight: 2,
                              backgroundColor: colors.border,
                              color: colors.brand,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.sessionLoading,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.labelTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const Key('drawer-settings'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(context).pop();
                        onOpenSettings();
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
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SessionSummary session,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: Text(l10n.deleteSession),
        description: Text(l10n.deleteSessionDescription),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.delete,
              style: TextStyle(color: colors.destructiveForeground),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    cancelSession(session.id);
    final orphaned = await ref
        .read(chatRepositoryProvider)
        .deleteSession(session.id);
    onDeleted(session.id);
    try {
      await ref.read(attachmentStoreProvider).deleteAttachments(orphaned);
    } on Object catch (error) {
      // 原件删除失败不阻塞界面切换；启动时的孤儿清理会兜底。
      debugLog('deleting attachments failed', error);
    }
  }
}

class _NewChatButton extends StatelessWidget {
  const _NewChatButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      key: const Key('drawer-new-chat'),
      borderRadius: BorderRadius.circular(100),
      onTap: () {
        Navigator.of(context).pop();
        onPressed();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: Stack(
          children: [
            Container(
              height: 40,
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.elevatedFill,
                borderRadius: BorderRadius.circular(100),
                border: dark
                    ? null
                    : Border.all(color: const Color(0x00679EFE)),
                boxShadow: dark ? _newChatDarkShadows : _newChatLightShadows,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.messageCirclePlus,
                    size: 16,
                    color: colors.labelPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.newChat,
                    style: TextStyle(
                      fontSize: 14,
                      height: 22 / 14,
                      fontWeight: FontWeight.w500,
                      color: colors.labelPrimary,
                    ),
                  ),
                ],
              ),
            ),
            // 深色的 inset 顶部高光：Flutter 无 inset 阴影，用 1px 高亮条近似。
            if (dark)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(height: 1, color: const Color(0x1AFFFFFF)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({
    required this.sessions,
    required this.currentSessionId,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<SessionSummary> sessions;
  final String? currentSessionId;
  final ValueChanged<String> onOpen;
  final Future<void> Function(SessionSummary session, String title) onRename;
  final Future<void> Function(SessionSummary session) onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _sidebarColorsOf(context);
    final groups = groupSessions(sessions, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: CustomScrollView(
        slivers: [
          for (final (index, (group, items)) in groups.indexed) ...[
            if (index > 0)
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            // 与 chat-demo 一致：每个分组标题上方留 4。
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _GroupHeaderDelegate(
                colors: colors,
                label: switch (group) {
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
                  current: session.id == currentSessionId,
                  onOpen: () {
                    Navigator.of(context).pop();
                    onOpen(session.id);
                  },
                  onRename: (title) => onRename(session, title),
                  onDelete: () => onDelete(session),
                );
              },
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
    );
  }
}

/// 分组标题吸顶；高度 = 上 4 + 行高 22 + 下 3。
class _GroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _GroupHeaderDelegate({required this.colors, required this.label});

  static const _extent = 29.0;

  final AppSidebarColors colors;
  final String label;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
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
    );
  }

  @override
  bool shouldRebuild(covariant _GroupHeaderDelegate oldDelegate) =>
      oldDelegate.label != label || oldDelegate.colors != colors;
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required this.session,
    required this.current,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final SessionSummary session;
  final bool current;
  final VoidCallback onOpen;
  final ValueChanged<String> onRename;
  final Future<void> Function() onDelete;

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
    return InkWell(
      key: ValueKey('session-row-${widget.session.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: widget.onOpen,
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(
          color: widget.current ? colors.activeItemFill : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  height: 22 / 16,
                  color: widget.current
                      ? colors.activeItemForeground
                      : colors.labelPrimary,
                ),
              ),
            ),
            ShadPopover(
              controller: _menu,
              padding: EdgeInsets.zero,
              decoration: ShadDecoration(
                color: colors.menuFill,
                shadows: _menuShadows,
                border: ShadBorder.fromBorderSide(
                  const ShadBorderSide(),
                  radius: BorderRadius.circular(12),
                ),
                focusedBorder: ShadBorder.fromBorderSide(
                  const ShadBorderSide(),
                  radius: BorderRadius.circular(12),
                ),
                secondaryBorder: ShadBorder.none,
                secondaryFocusedBorder: ShadBorder.none,
              ),
              popover: (context) => SizedBox(
                width: 124,
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MenuOption(
                          icon: LucideIcons.pencil,
                          label: l10n.rename,
                          onPressed: _startEditing,
                        ),
                        _MenuOption(
                          key: ValueKey('session-delete-${widget.session.id}'),
                          icon: LucideIcons.trash2,
                          label: l10n.delete,
                          color: colors.danger,
                          onPressed: _delete,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: Semantics(
                button: true,
                label: l10n.sessionActions,
                child: ShadIconButton.ghost(
                  key: ValueKey('session-menu-${widget.session.id}'),
                  onPressed: _menu.toggle,
                  icon: const Icon(LucideIcons.ellipsis),
                  iconSize: 16,
                  width: 44,
                  height: 44,
                  padding: EdgeInsets.zero,
                  foregroundColor: colors.labelPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 菜单项：图标 16 + 文案 14，危险项整体变红（chat-demo Menu）。
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
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                height: 24 / 14,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
