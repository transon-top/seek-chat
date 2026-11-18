import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/error_text.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/reply_rules.dart';
import '../../shared/models/types.dart';
import '../../shared/prefs/chat_options_store.dart';
import 'chat_controller.dart';
import 'markdown_view.dart';
import 'reply_view.dart';

/// 最小聊天页：可见路径、流式文本、停止、重新生成、续写、搜索时间线与引用。
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
  late final ChatOptionsStore _options;
  late bool _thinking;
  late bool _search;

  @override
  void initState() {
    super.initState();
    _options = ref.read(chatOptionsStoreProvider);
    _thinking = _options.thinking;
    _search = _options.search;
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

  void _setThinking(bool value) {
    setState(() => _thinking = value);
    unawaited(_options.setThinking(value));
  }

  void _setSearch(bool value) {
    setState(() => _search = value);
    unawaited(_options.setSearch(value));
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
            onThinkingChanged: _setThinking,
            onSearchChanged: _setSearch,
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
    final view = buildReplyView(reply, streaming: reply.isInFlight);
    final refused = reply.stopReason == StopReason.refusal;
    final continueEnabled =
        isLast && !busy && canContinueReply(reply) && onContinue != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!refused) _ReplyArea(reply: reply, view: view),
          if (!refused && view.answer != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: MarkdownView(
                text: view.answer!.markdown,
                streaming: reply.isInFlight,
                sources: view.sources,
              ),
            ),
          if (reply.status == ReplyStatus.error)
            Text(
              strings.replyFailed(
                reply.error == null
                    ? apiErrorText(strings, ApiErrorCondition.other)
                    : replyErrorText(strings, reply.error!),
              ),
              style: TextStyle(color: colors.error),
            ),
          if (refused)
            Text(strings.replyRefused, style: TextStyle(color: colors.error)),
          if (!refused &&
              !reply.isInFlight &&
              view.searchResults.isNotEmpty)
            _SearchSummary(sources: view.searchResults),
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
}

/// 思考与工具步骤的时间线；开启深度思考时带可折叠标题。
class _ReplyArea extends StatefulWidget {
  const _ReplyArea({required this.reply, required this.view});

  final AssistantMessage reply;
  final ReplyView view;

  @override
  State<_ReplyArea> createState() => _ReplyAreaState();
}

class _ReplyAreaState extends State<_ReplyArea> {
  bool _open = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_ReplyArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 标题与思考用时每秒刷新；有正文后不再计时。
  void _syncTicker() {
    final active =
        widget.reply.isInFlight && widget.view.answer == null;
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.reply;
    final view = widget.view;
    final streaming = reply.isInFlight;
    final thinking =
        reply.thinking ?? view.steps.any((step) => step is ThinkingStep);
    final title = thinking ? _areaTitle() : null;
    if (view.steps.isEmpty && title == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(title)),
                  Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        if (title == null || _open)
          for (var index = 0; index < view.steps.length; index++)
            _StepItem(
              step: view.steps[index],
              sources: view.sources,
              searchResults: view.searchResults,
              streaming: streaming,
              replyStatus: reply.status,
              isLast: index == view.steps.length - 1,
            ),
      ],
    );
  }

  String _areaTitle() {
    final view = widget.view;
    if (view.answer != null) {
      final seconds = replyThinkingSeconds(widget.reply);
      return seconds == null ? '深度思考' : '已思考（用时 $seconds 秒）';
    }
    if (!widget.reply.isInFlight) return '已停止';
    final last = view.steps.isEmpty ? null : view.steps.last;
    if (last is SearchStep && last.status == ToolStatus.wip) {
      return isImageSearchKind(last.kind) ? '图像搜索中...' : '正在搜索';
    }
    if ((last is OpenStep &&
            last.pages.any((page) => page.status == ToolStatus.wip)) ||
        (last is FindStep &&
            last.patterns.any((item) => item.status == ToolStatus.wip))) {
      return '正在浏览网页';
    }
    if (last is ReadLinkStep &&
        last.links.any((link) => link.status == ToolStatus.wip)) {
      return '正在阅读';
    }
    return '正在思考';
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.step,
    required this.sources,
    required this.searchResults,
    required this.streaming,
    required this.replyStatus,
    required this.isLast,
  });

  final ReplyStep step;
  final List<Source> sources;
  final List<Source> searchResults;
  final bool streaming;
  final ReplyStatus replyStatus;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final step = this.step;
    if (step is ThinkingStep) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: MarkdownView(
          text: step.blocks.map((block) => block.thinking).join(),
          streaming: streaming && isLast,
          dense: true,
          disableLinks: true,
        ),
      );
    }
    if (step is PreambleStep) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: MarkdownView(
          text: step.markdown,
          streaming: streaming && isLast,
          sources: sources,
          dense: true,
        ),
      );
    }
    if (step is SearchStep) {
      return _SearchRow(
        step: step,
        searchResults: searchResults,
        streaming: streaming,
        replyStatus: replyStatus,
      );
    }
    if (step is OpenStep) {
      return _OpenRow(step: step, searchResults: searchResults);
    }
    if (step is FindStep) {
      return _FindRow(step: step);
    }
    if (step is ReadLinkStep) {
      return _ReadLinkRow(step: step);
    }
    return const SizedBox.shrink();
  }
}

class _SearchRow extends StatefulWidget {
  const _SearchRow({
    required this.step,
    required this.searchResults,
    required this.streaming,
    required this.replyStatus,
  });

  final SearchStep step;
  final List<Source> searchResults;
  final bool streaming;
  final ReplyStatus replyStatus;

  @override
  State<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends State<_SearchRow> {
  Timer? _ticker;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_SearchRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 进行中且有多条查询词时每 2 秒轮播一条。
  void _syncTicker() {
    final active =
        widget.step.status == ToolStatus.wip && widget.step.queries.length > 1;
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) setState(() => _tick++);
      });
    } else if (!active) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final step = widget.step;
    final failed = step.status == ToolStatus.failed;
    final interrupted =
        failed && !widget.streaming && widget.replyStatus == ReplyStatus.stopped;
    final clickable = step.status != ToolStatus.wip && step.results.isNotEmpty;
    final style = TextStyle(color: colors.onSurfaceVariant);
    final Widget text;
    if (step.status == ToolStatus.wip) {
      if (step.queries.isNotEmpty) {
        text = Text(
          '搜索 ${step.queries[_tick % step.queries.length]}',
          style: style,
        );
      } else {
        text = Text(
          isImageSearchKind(step.kind) ? '图像搜索中...' : '搜索中...',
          style: style,
        );
      }
    } else if (interrupted) {
      text = Text('搜索已停止', style: style);
    } else if (failed) {
      text = Text('联网搜索暂不可用', style: style);
    } else if (step.results.isEmpty) {
      text = Text(
        isDeepSearchKind(step.kind) ? '未搜索到合适内容' : '未搜索到相关内容',
        style: style,
      );
    } else if (isDeepSearchKind(step.kind)) {
      text = Text('搜索到 ${step.results.length} 个网页', style: style);
    } else {
      text = Text('已阅读 ${step.results.length} 个网页', style: style);
    }

    return InkWell(
      onTap: clickable
          ? () => _showSourcesSheet(context, widget.searchResults)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              failed ? Icons.search_off : Icons.search,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: text),
            if (step.status != ToolStatus.wip && step.results.isNotEmpty)
              _SiteThumbnails(sources: step.results),
          ],
        ),
      ),
    );
  }
}

class _OpenRow extends StatelessWidget {
  const _OpenRow({required this.step, required this.searchResults});

  final OpenStep step;
  final List<Source> searchResults;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final allFailed =
        step.pages.every((page) => page.status == ToolStatus.failed);
    return _ToolRow(
      icon: Icons.public,
      child: allFailed
          ? Text('浏览页面失败', style: TextStyle(color: colors.onSurfaceVariant))
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '浏览 ${step.pages.length} 个页面',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                for (final page in step.pages.take(5))
                  _PageLink(page: page, failedTip: '浏览失败'),
                if (step.pages.length > 5)
                  InkWell(
                    onTap: () =>
                        _showSourcesSheet(context, searchResults),
                    child: Text(
                      '查看全部',
                      style: TextStyle(color: colors.primary),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _FindRow extends StatelessWidget {
  const _FindRow({required this.step});

  final FindStep step;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final allFailed =
        step.patterns.every((item) => item.status == ToolStatus.failed);
    return _ToolRow(
      icon: Icons.public,
      child: allFailed
          ? Text('查找失败', style: TextStyle(color: colors.onSurfaceVariant))
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '查找关键词',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                for (final item in step.patterns) _FindChip(item: item),
              ],
            ),
    );
  }
}

class _ReadLinkRow extends StatelessWidget {
  const _ReadLinkRow({required this.step});

  final ReadLinkStep step;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ToolRow(
      icon: Icons.link,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('正在阅读', style: TextStyle(color: colors.onSurfaceVariant)),
          for (final link in step.links) _PageLink(page: link),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PageLink extends StatelessWidget {
  const _PageLink({required this.page, this.failedTip});

  final PageItem page;
  final String? failedTip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (page.status == ToolStatus.failed) {
      return Tooltip(
        message: failedTip ?? '浏览失败',
        child: Text(page.title, style: TextStyle(color: colors.outline)),
      );
    }
    return InkWell(
      onTap: () => openExternalLink(page.url, page.title),
      child: Text(page.title, style: TextStyle(color: colors.primary)),
    );
  }
}

class _FindChip extends StatelessWidget {
  const _FindChip({required this.item});

  final FindItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final failed = item.status == ToolStatus.failed;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.status == ToolStatus.done)
            Icon(Icons.check, size: 12, color: colors.onSurfaceVariant)
          else if (failed)
            Icon(Icons.close, size: 12, color: colors.onSurfaceVariant),
          if (item.status != ToolStatus.wip) const SizedBox(width: 2),
          Text(item.pattern, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
    if (!failed) return chip;
    return Tooltip(message: '未查找到相关内容', child: chip);
  }
}

/// 「N 个网页」胶囊：回复完成后显示，点击打开同一个抽屉。
class _SearchSummary extends StatelessWidget {
  const _SearchSummary({required this.sources});

  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showSourcesSheet(context, sources),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SiteThumbnails(sources: sources),
              const SizedBox(width: 6),
              Text(
                '${sources.length} 个网页',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteThumbnails extends StatelessWidget {
  const _SiteThumbnails({required this.sources});

  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final source in sources.take(4))
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: _SiteIcon(url: source.siteIcon),
          ),
      ],
    );
  }
}

class _SiteIcon extends StatelessWidget {
  const _SiteIcon({required this.url, this.size = 16});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = Icon(
      Icons.link,
      size: size * 0.75,
      color: colors.onSurfaceVariant,
    );
    final uri = url == null ? null : webUri(url!);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: uri == null
            ? ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Center(child: icon),
              )
            : Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null
                        ? child
                        : ColoredBox(color: colors.surfaceContainerHighest),
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: Center(child: icon),
                ),
              ),
      ),
    );
  }
}

Future<void> _showSourcesSheet(
  BuildContext context,
  List<Source> sources,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '搜索结果',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sources.length,
                itemBuilder: (context, index) =>
                    _SourceCard(source: sources[index]),
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 来源卡片：站点图标与名称、日期、标题、摘要（`search.md` §6.1）。
class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = _displayDate(source.publishedAt);
    final metaStyle = TextStyle(color: colors.onSurfaceVariant, fontSize: 12);
    return InkWell(
      onTap: () => openExternalLink(source.url, source.title),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SiteIcon(url: source.siteIcon, size: 14),
                const SizedBox(width: 4),
                if (source.siteName.isNotEmpty)
                  Text(source.siteName, style: metaStyle),
                if (source.siteName.isNotEmpty && date.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('·', style: metaStyle),
                  ),
                if (date.isNotEmpty) Text(date, style: metaStyle),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              source.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (source.snippet != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  source.snippet!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _displayDate(String? value) {
  if (value == null || value.isEmpty) return '';
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)}';
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
                  onSelected: onThinkingChanged,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('智能搜索'),
                  selected: search,
                  onSelected: onSearchChanged,
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
