import 'package:material_ui/material_ui.dart';

import '../api/client.dart';
import '../data/attachment_store.dart';
import '../data/chat_repository.dart';
import '../models/types.dart';
import '../settings/api_key_store.dart';
import '../settings/settings_page.dart';
import 'chat_page.dart';

/// 会话列表：新建、打开、重命名、删除。完整抽屉与布局见票 09 / 10。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.client,
    required this.apiKeyStore,
    required this.attachmentStore,
  });

  final ChatRepository repository;
  final DeepSeekApiClient client;
  final ApiKeyStore apiKeyStore;
  final AttachmentStore attachmentStore;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<SessionSummary>? _sessions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await widget.repository.listSessions();
    if (!mounted) return;
    setState(() => _sessions = sessions);
  }

  Future<void> _open(String sessionId) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatPage(
        sessionId: sessionId,
        repository: widget.repository,
        client: widget.client,
        apiKeyStore: widget.apiKeyStore,
      ),
    ));
    await _load();
  }

  Future<void> _newChat() async {
    final session = await widget.repository.createSession();
    if (!mounted) return;
    await _open(session.id);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(
        client: widget.client,
        apiKeyStore: widget.apiKeyStore,
      ),
    ));
  }

  Future<void> _rename(SessionSummary session) async {
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
    if (title == null) return;
    await widget.repository.renameSession(session.id, title.trim());
    await _load();
  }

  Future<void> _delete(SessionSummary session) async {
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
    if (confirmed != true) return;
    final orphaned = await widget.repository.deleteSession(session.id);
    await widget.attachmentStore.deleteAttachments(orphaned);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Chat'),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            tooltip: '设置',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        tooltip: '新建会话',
        child: const Icon(Icons.add),
      ),
      body: sessions == null
          ? const Center(child: CircularProgressIndicator())
          : sessions.isEmpty
              ? const Center(child: Text('还没有会话'))
              : ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return ListTile(
                      title: Text(
                        session.title.isEmpty ? '新对话' : session.title,
                      ),
                      onTap: () => _open(session.id),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'rename') _rename(session);
                          if (action == 'delete') _delete(session);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
