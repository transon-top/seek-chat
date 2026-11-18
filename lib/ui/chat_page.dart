import 'package:material_ui/material_ui.dart';

import '../api/client.dart';
import '../chat/chat_controller.dart';
import '../chat/reply_rules.dart';
import '../data/chat_repository.dart';
import '../models/types.dart';
import '../settings/api_key_store.dart';

/// 最小聊天页：可见路径、流式文本、停止、重新生成、续写。
///
/// 外观与完整控件由 UI 规格票 10 / 原型票 09 重做；这里只保证行为闭环。
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.sessionId,
    required this.repository,
    required this.client,
    required this.apiKeyStore,
  });

  final String sessionId;
  final ChatRepository repository;
  final DeepSeekApiClient client;
  final ApiKeyStore apiKeyStore;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  late final ChatController _controller = ChatController(
    repository: widget.repository,
    client: widget.client,
    sessionId: widget.sessionId,
    readApiKey: widget.apiKeyStore.read,
  );
  final TextEditingController _input = TextEditingController();
  bool _thinking = false;
  bool _search = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _input.dispose();
    super.dispose();
  }

  /// 进入后台时补写一次内存中的回复（`data-model.md` §4）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller.flush();
    }
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await _controller.send(text: text, thinking: _thinking, search: _search);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final messages = _controller.messages;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _controller.title.isEmpty ? '新对话' : _controller.title,
            ),
          ),
          body: Column(
            children: [
              if (_controller.error != null)
                _ErrorBanner(
                  message: _controller.error!,
                  onDismiss: _controller.clearError,
                ),
              Expanded(
                child: messages.isEmpty
                    ? const Center(child: Text('发一条消息开始对话'))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final position = messages.length - 1 - index;
                          return _MessageView(
                            message: messages[position],
                            isLast: position == messages.length - 1,
                            busy: _controller.busy,
                            onRegenerate: _controller.busy
                                ? null
                                : (reply) => _controller.regenerate(
                                      reply,
                                      thinking: _thinking,
                                      search: _search,
                                    ),
                            onContinue: _controller.busy
                                ? null
                                : (reply) => _controller.continueReply(
                                      reply,
                                      thinking: _thinking,
                                      search: _search,
                                    ),
                          );
                        },
                      ),
              ),
              _Composer(
                input: _input,
                busy: _controller.busy,
                thinking: _thinking,
                search: _search,
                onThinkingChanged: (value) => setState(() => _thinking = value),
                onSearchChanged: (value) => setState(() => _search = value),
                onSend: _send,
                onStop: _controller.stop,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
              tooltip: '关闭',
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    required this.isLast,
    required this.busy,
    required this.onRegenerate,
    required this.onContinue,
  });

  final Message message;
  final bool isLast;
  final bool busy;
  final ValueChanged<AssistantMessage>? onRegenerate;
  final ValueChanged<AssistantMessage>? onContinue;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message is UserMessage) {
      final colors = Theme.of(context).colorScheme;
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            message.text,
            style: TextStyle(color: colors.onPrimaryContainer),
          ),
        ),
      );
    }
    if (message is! AssistantMessage) return const SizedBox.shrink();
    return _ReplyView(
      reply: message,
      isLast: isLast,
      busy: busy,
      onRegenerate: onRegenerate,
      onContinue: onContinue,
    );
  }
}

class _ReplyView extends StatelessWidget {
  const _ReplyView({
    required this.reply,
    required this.isLast,
    required this.busy,
    required this.onRegenerate,
    required this.onContinue,
  });

  final AssistantMessage reply;
  final bool isLast;
  final bool busy;
  final ValueChanged<AssistantMessage>? onRegenerate;
  final ValueChanged<AssistantMessage>? onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final seconds = replyThinkingSeconds(reply);
    final continueEnabled =
        isLast && !busy && canContinueReply(reply) && onContinue != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final block in reply.blocks) _block(context, block, seconds),
          if (reply.status == ReplyStatus.error)
            Text(
              '生成失败：${reply.error?.message ?? '未知错误'}',
              style: TextStyle(color: colors.error),
            ),
          if (reply.stopReason == StopReason.refusal)
            Text('内容被安全策略拒绝', style: TextStyle(color: colors.error)),
          if (reply.status == ReplyStatus.pending ||
              reply.status == ReplyStatus.streaming)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Row(
            children: [
              IconButton(
                onPressed: busy || onRegenerate == null
                    ? null
                    : () => onRegenerate!(reply),
                icon: const Icon(Icons.refresh),
                tooltip: '重新生成',
              ),
              if (isLast && canContinueReply(reply))
                IconButton(
                  onPressed:
                      continueEnabled ? () => onContinue!(reply) : null,
                  icon: const Icon(Icons.play_arrow),
                  tooltip: '继续生成',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, ReplyBlock block, int? seconds) {
    if (block is TextBlock) {
      if (block.text.isEmpty) return const SizedBox.shrink();
      // shortcut: 纯文本；Markdown、数学与 Mermaid 由票 08 / 10 接入。
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SelectableText(block.text),
      );
    }
    if (block is ThinkingBlock) {
      if (block.thinking.isEmpty) return const SizedBox.shrink();
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(seconds == null ? '思考过程' : '思考过程（$seconds 秒）'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(block.thinking),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        _toolLabel(block),
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }

  String _toolLabel(ReplyBlock block) {
    if (block is ServerToolUseBlock) {
      final input = block.input;
      if (input is SearchInput) {
        return '搜索：${input.queries.join('、')}';
      }
      if (input is OpenPageInput) return '阅读：${input.url}';
      if (input is ReadLinkInput) return '阅读：${input.url}';
      if (input is FindInPageInput) return '在页面中查找：${input.pattern}';
      return '调用工具：${block.name}';
    }
    if (block is WebSearchToolResultBlock) {
      final count = block.content.whereType<WebSearchResult>().length;
      return count == 0 ? '未找到来源' : '找到 $count 条来源';
    }
    if (block is WebFetchToolResultBlock) {
      return block.content is WebFetchResult ? '已阅读链接' : '链接阅读失败';
    }
    return '';
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.busy,
    required this.thinking,
    required this.search,
    required this.onThinkingChanged,
    required this.onSearchChanged,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController input;
  final bool busy;
  final bool thinking;
  final bool search;
  final ValueChanged<bool> onThinkingChanged;
  final ValueChanged<bool> onSearchChanged;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                FilterChip(
                  label: const Text('深度思考'),
                  selected: thinking,
                  onSelected: busy ? null : onThinkingChanged,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('联网搜索'),
                  selected: search,
                  onSelected: busy ? null : onSearchChanged,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: '输入消息',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: busy ? onStop : onSend,
                  icon: Icon(busy ? Icons.stop : Icons.send),
                  tooltip: busy ? '停止' : '发送',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
