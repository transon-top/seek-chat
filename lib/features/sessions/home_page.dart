import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/types.dart';
import '../../shared/providers.dart';

/// 会话列表的响应式来源：drift 在会话增删改后推送新列表。
final sessionsProvider = StreamProvider.autoDispose<List<SessionSummary>>(
  (ref) => ref.watch(chatRepositoryProvider).watchSessions(),
);

/// 会话列表：新建、打开、重命名、删除。完整抽屉与布局见票 09 / 10。
class HomePage extends ConsumerWidget {
  const HomePage({
    super.key,
    required this.openChat,
    required this.openSettings,
    required this.cancelSession,
  });

  /// 路由与跨功能动作由 `app/` 接线；功能之间不直接 import。
  final Future<void> Function(BuildContext context, String sessionId) openChat;
  final Future<void> Function(BuildContext context) openSettings;

  /// 删除会话前取消其进行中的流（api.md §9.1）。
  final void Function(String sessionId) cancelSession;

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final session = await ref.read(chatRepositoryProvider).createSession();
    if (!context.mounted) return;
    await openChat(context, session.id);
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    SessionSummary session,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final input = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameSession),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    input.dispose();
    if (title == null || !context.mounted) return;
    await ref
        .read(chatRepositoryProvider)
        .renameSession(session.id, title.trim());
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SessionSummary session,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteSession),
        content: Text(
          l10n.deleteSessionConfirm(
            session.title.isEmpty ? l10n.untitledChat : session.title,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    cancelSession(session.id);
    final orphaned = await ref
        .read(chatRepositoryProvider)
        .deleteSession(session.id);
    await ref.read(attachmentStoreProvider).deleteAttachments(orphaned);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(sessionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Chat'),
        actions: [
          IconButton(
            onPressed: () => openSettings(context),
            icon: const Icon(Icons.settings),
            tooltip: l10n.settingsTitle,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _newChat(context, ref),
        tooltip: l10n.newChat,
        child: const Icon(Icons.add),
      ),
      body: sessions.when(
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.noSessions))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final session = items[index];
                  return ListTile(
                    title: Text(
                      session.title.isEmpty
                          ? l10n.untitledChat
                          : session.title,
                    ),
                    onTap: () => openChat(context, session.id),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'rename') _rename(context, ref, session);
                        if (action == 'delete') _delete(context, ref, session);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text(l10n.rename),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(l10n.delete),
                        ),
                      ],
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(l10n.apiErrorOther)),
      ),
    );
  }
}
