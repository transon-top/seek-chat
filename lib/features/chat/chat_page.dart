import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/error_text.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/reply_rules.dart';
import '../../shared/models/types.dart';
import 'chat_controller.dart';
import 'markdown_view.dart';

/// 最小聊天页：可见路径、流式文本、停止、重新生成、续写。
///
/// 外观与完整控件由 UI 规格票 10 / 原型票 09 重做；这里只保证行为闭环。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _input = TextEditingController();
  bool _thinking = false;
  bool _search = false;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(chatControllerProvider(widget.sessionId).notifier).load(),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await _controller.send(text: text, thinking: _thinking, search: _search);
  }

  ChatController get _controller =>
      ref.read(chatControllerProvider(widget.sessionId).notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(widget.sessionId));
    final messages = state.messages;
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(state.title.isEmpty ? '新对话' : state.title)),
      body: Column(
        children: [
          if (state.error != null)
            _ErrorBanner(
              message: localMessageText(strings, state.error!),
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
                        key: ValueKey(messages[position].id),
                        message: messages[position],
                        isLast: position == messages.length - 1,
                        busy: state.busy,
                        onRegenerate: state.busy
                            ? null
                            : (reply) => _controller.regenerate(
                                reply,
                                thinking: _thinking,
                                search: _search,
                              ),
                        onContinue: state.busy
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
            busy: state.busy,
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
    super.key,
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
    final strings = AppLocalizations.of(context)!;
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
              strings.replyFailed(
                reply.error == null
                    ? apiErrorText(strings, ApiErrorCondition.other)
                    : replyErrorText(strings, reply.error!),
              ),
              style: TextStyle(color: colors.error),
            ),
          if (reply.stopReason == StopReason.refusal)
            Text(strings.replyRefused, style: TextStyle(color: colors.error)),
          if (reply.isInFlight)
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
                  onPressed: continueEnabled ? () => onContinue!(reply) : null,
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: MarkdownView(text: block.text, streaming: reply.isInFlight),
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
