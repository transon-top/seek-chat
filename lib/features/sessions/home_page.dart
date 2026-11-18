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
    final input = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(controller: input, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('保存'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('删除「${session.title.isEmpty ? '新对话' : session.title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
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
    final sessions = ref.watch(sessionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Chat'),
        actions: [
          IconButton(
            onPressed: () => openSettings(context),
            icon: const Icon(Icons.settings),
            tooltip: '设置',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _newChat(context, ref),
        tooltip: '新建会话',
        child: const Icon(Icons.add),
      ),
      body: sessions.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('还没有会话'))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final session = items[index];
                  return ListTile(
                    title: Text(session.title.isEmpty ? '新对话' : session.title),
                    onTap: () => openChat(context, session.id),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'rename') _rename(context, ref, session);
                        if (action == 'delete') _delete(context, ref, session);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text(AppLocalizations.of(context)!.apiErrorOther)),
      ),
    );
  }
}
