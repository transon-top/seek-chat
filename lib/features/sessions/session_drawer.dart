import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

/// 左侧会话抽屉：分组列表、当前会话高亮、新建、重命名、删除与设置入口。
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
    final colors = ShadTheme.of(context).colorScheme;
    final sessions = ref.watch(sessionsProvider);
    final width = math.min(320.0, MediaQuery.sizeOf(context).width * 0.82);
    return Drawer(
      width: width,
      elevation: 0,
      backgroundColor: colors.background,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    Text(
                      'Fleepseek',
                      style: TextStyle(
                        fontSize: 22,
                        height: 28 / 22,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: l10n.close,
                      child: ShadIconButton.ghost(
                        key: const Key('drawer-close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.panelLeftClose),
                        iconSize: 18,
                        width: 44,
                        height: 44,
                        padding: EdgeInsets.zero,
                        foregroundColor: colors.foreground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _NewChatButton(onPressed: onNewChat),
              Expanded(
                child: sessions.when(
                  data: (items) => items.isEmpty
                      ? Center(
                          child: Text(
                            l10n.noSessions,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.mutedForeground,
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
                          onDelete: (session) => _delete(context, ref, session),
                        ),
                  loading: () => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 80,
                          child: ShadProgress(
                            minHeight: 2,
                            backgroundColor: colors.muted,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
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
                  error: (error, stackTrace) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.sessionsLoadFailed,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.mutedForeground,
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
              InkWell(
                key: const Key('drawer-settings'),
                onTap: () {
                  Navigator.of(context).pop();
                  onOpenSettings();
                },
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.settings,
                        size: 18,
                        color: colors.foreground,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.settingsEntry,
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.foreground,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: colors.mutedForeground,
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
    final title = session.title.isEmpty ? l10n.untitledChat : session.title;
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: Text(l10n.deleteSession),
        description: Text(l10n.deleteSessionConfirm(title)),
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
    final colors = ShadTheme.of(context).colorScheme;
    return InkWell(
      key: const Key('drawer-new-chat'),
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        Navigator.of(context).pop();
        onPressed();
      },
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: colors.card,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circlePlus, size: 18, color: colors.foreground),
            const SizedBox(width: 8),
            Text(
              l10n.newChat,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: colors.foreground,
              ),
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
    final colors = ShadTheme.of(context).colorScheme;
    final groups = groupSessions(sessions, DateTime.now());
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final (group, items) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(switch (group) {
              SessionGroup.today => l10n.sessionGroupToday,
              SessionGroup.yesterday => l10n.sessionGroupYesterday,
              SessionGroup.last7Days => l10n.sessionGroupLast7Days,
              SessionGroup.earlier => l10n.sessionGroupEarlier,
            }, style: TextStyle(fontSize: 13, color: colors.mutedForeground)),
          ),
          for (final session in items)
            _SessionRow(
              session: session,
              current: session.id == currentSessionId,
              onOpen: () {
                Navigator.of(context).pop();
                onOpen(session.id);
              },
              onRename: (title) => onRename(session, title),
              onDelete: () => onDelete(session),
            ),
        ],
      ],
    );
  }
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

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    _menu.hide();
    final l10n = AppLocalizations.of(context)!;
    final input = TextEditingController(text: widget.session.title);
    final title = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(l10n.renameSession),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: Text(l10n.save),
          ),
        ],
        child: ShadInput(
          key: const Key('rename-input'),
          controller: input,
          autofocus: true,
        ),
      ),
    );
    input.dispose();
    if (title == null) return;
    widget.onRename(title);
  }

  Future<void> _delete() async {
    _menu.hide();
    await widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.session.title.isEmpty
        ? l10n.untitledChat
        : widget.session.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        key: ValueKey('session-row-${widget.session.id}'),
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onOpen,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.current
                ? colors.primary.withValues(alpha: dark ? 0.18 : 0.10)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 20 / 15,
                    fontWeight: widget.current
                        ? FontWeight.w500
                        : FontWeight.w400,
                    color: widget.current ? colors.primary : colors.foreground,
                  ),
                ),
              ),
              ShadPopover(
                controller: _menu,
                popover: (context) => SizedBox(
                  width: 140,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShadButton.ghost(
                        width: double.infinity,
                        onPressed: _rename,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(l10n.rename),
                        ),
                      ),
                      ShadButton.ghost(
                        key: ValueKey('session-delete-${widget.session.id}'),
                        width: double.infinity,
                        onPressed: _delete,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            l10n.delete,
                            style: TextStyle(color: colors.destructive),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                child: Semantics(
                  button: true,
                  label: l10n.sessionActions,
                  child: ShadIconButton.ghost(
                    key: ValueKey('session-menu-${widget.session.id}'),
                    onPressed: _menu.toggle,
                    icon: const Icon(LucideIcons.ellipsis),
                    iconSize: 20,
                    width: 44,
                    height: 44,
                    padding: EdgeInsets.zero,
                    foregroundColor: colors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
