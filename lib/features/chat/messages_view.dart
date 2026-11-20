import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/markdown_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/error_text.dart';
import '../../shared/models/reply_rules.dart';
import '../../shared/models/types.dart';
import '../../shared/widgets/scroll_edge_fade.dart';
import 'attachments_view.dart';
import 'markdown_view.dart';
import 'reply_view.dart';
import 'speech/read_aloud_button.dart';
import 'speech/speech_controller.dart';

/// 消息区需要的语音状态切片：阶段、语音占用与正在朗读的消息。
typedef SpeechView = ({
  SpeechPhase phase,
  bool voiceBusy,
  String? readingMessageId,
});

/// 消息区：用户气泡、助手正文、思考 / 工具时间线、来源与操作条
/// （ui.md §9 第 4 步、§5.3–§5.6）。
///
/// 列表水平内边距 16、消息间距 16，宽屏内容最大 760 并居中（§1.3、§4）。
/// 列表正序排列：内容不足一屏时提问从视口顶部开始，超过一屏后跟随底部，
/// 用户上滑离开底部则停止跟随（与 chat-demo 一致）。
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.versions,
    required this.busy,
    required this.speech,
    required this.onReadAloud,
    this.onEdit,
    this.onSelectVersion,
    this.onRegenerate,
    this.onContinue,
    this.onRetryUpload,
  });

  final List<Message> messages;
  final Map<String, MessageVersions> versions;
  final bool busy;
  final SpeechView speech;
  final void Function(AssistantMessage reply, String text) onReadAloud;
  final Future<bool> Function(UserMessage message, String text)? onEdit;
  final ValueChanged<String>? onSelectVersion;
  final ValueChanged<AssistantMessage>? onRegenerate;
  final ValueChanged<AssistantMessage>? onContinue;
  final ValueChanged<AssistantMessage>? onRetryUpload;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  /// 距底部小于该值时视为在底部，流式内容增长时继续跟随（chat-demo 同值）。
  static const double _stickyThreshold = 40;

  final ScrollController _controller = ScrollController();
  bool _sticky = true;
  double _lastOffset = 0;
  bool _followScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // 首次布局后落到最新消息（打开历史会话时从底部开始）。
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新请求（发送、编辑、重新生成、续写）一律重新跟随底部。
    if (!oldWidget.busy && widget.busy) _sticky = true;
    _scheduleFollow();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _controller.position;
    final offset = position.pixels;
    if (position.maxScrollExtent - offset - position.viewportDimension <
        _stickyThreshold) {
      _sticky = true;
    } else if (offset < _lastOffset) {
      _sticky = false;
    }
    _lastOffset = offset;
  }

  /// 布局后若仍在跟随状态就跳到最新内容。懒加载下列表的
  /// `maxScrollExtent` 可能仍是估算值，跳转后继续调度直到稳定。
  void _scheduleFollow() {
    if (_followScheduled) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted || !_sticky || !_controller.hasClients) return;
      final target = _controller.position.maxScrollExtent;
      if (_controller.position.pixels != target) {
        _controller.jumpTo(target);
        _scheduleFollow();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    return ScrollEdgeFade(
      controller: _controller,
      color: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          return Padding(
            // 顶部留白只加在第一行之前，其余消息间距 16。
            padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _MessageView(
                  key: ValueKey(message.id),
                  message: message,
                  versions: widget.versions[message.id],
                  isLast: index == messages.length - 1,
                  busy: widget.busy,
                  speech: widget.speech,
                  onReadAloud: widget.onReadAloud,
                  onEdit: widget.onEdit,
                  onSelectVersion: widget.onSelectVersion,
                  onRegenerate: widget.onRegenerate,
                  onContinue: widget.onContinue,
                  onRetryUpload: widget.onRetryUpload,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.message,
    required this.versions,
    required this.isLast,
    required this.busy,
    required this.speech,
    required this.onReadAloud,
    required this.onEdit,
    required this.onSelectVersion,
    required this.onRegenerate,
    required this.onContinue,
    required this.onRetryUpload,
  });

  final Message message;
  final MessageVersions? versions;
  final bool isLast;
  final bool busy;
  final SpeechView speech;
  final void Function(AssistantMessage reply, String text) onReadAloud;
  final Future<bool> Function(UserMessage message, String text)? onEdit;
  final ValueChanged<String>? onSelectVersion;
  final ValueChanged<AssistantMessage>? onRegenerate;
  final ValueChanged<AssistantMessage>? onContinue;
  final ValueChanged<AssistantMessage>? onRetryUpload;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message is UserMessage) {
      return _UserMessageView(
        message: message,
        versions: versions,
        onEdit: busy ? null : onEdit,
        onSelectVersion: busy ? null : onSelectVersion,
      );
    }
    if (message is! AssistantMessage) return const SizedBox.shrink();
    return _AssistantMessageView(
      reply: message,
      versions: versions,
      isLast: isLast,
      busy: busy,
      speech: speech,
      onReadAloud: onReadAloud,
      onSelectVersion: onSelectVersion,
      onRegenerate: onRegenerate,
      onContinue: onContinue,
      onRetryUpload: onRetryUpload,
    );
  }
}

/// 用户提问：右对齐灰色气泡、附件、编辑入口与版本切换（§5.5）。
class _UserMessageView extends StatefulWidget {
  const _UserMessageView({
    required this.message,
    required this.versions,
    required this.onEdit,
    required this.onSelectVersion,
  });

  final UserMessage message;
  final MessageVersions? versions;
  final Future<bool> Function(UserMessage message, String text)? onEdit;
  final ValueChanged<String>? onSelectVersion;

  @override
  State<_UserMessageView> createState() => _UserMessageViewState();
}

class _UserMessageViewState extends State<_UserMessageView> {
  late final TextEditingController _draft = TextEditingController(
    text: widget.message.text,
  );
  bool _editing = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _startEditing() {
    _draft.text = widget.message.text;
    setState(() => _editing = true);
  }

  Future<void> _submit() async {
    final onEdit = widget.onEdit;
    if (onEdit == null) return;
    final text = _draft.text;
    if (text.trim().isEmpty && widget.message.attachments.isEmpty) return;
    if (await onEdit(widget.message, text) && mounted) {
      setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final message = widget.message;
    final versions = widget.versions;
    return Semantics(
      label: strings.userMessage,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (message.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: MessageAttachments(attachments: message.attachments),
            ),
          if (_editing)
            _EditBox(
              draft: _draft,
              hint: strings.composerHint,
              enabled: widget.onEdit != null,
              hasAttachments: message.attachments.isNotEmpty,
              onCancel: () => setState(() => _editing = false),
              onSubmit: _submit,
            )
          else ...[
            if (message.text.isNotEmpty)
              Container(
                key: Key('user-bubble-${message.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.muted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SelectableText(
                  message.text,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: colors.foreground,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (versions != null && versions.hasMultiple)
                  _VersionSwitcher(
                    versions: versions,
                    onSelect: widget.onSelectVersion,
                  ),
                if (message.text.isNotEmpty)
                  _IconAction(
                    key: ValueKey('copy-message-${message.id}'),
                    tooltip: strings.copy,
                    icon: LucideIcons.copy,
                    size: 16,
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: message.text)),
                  ),
                _IconAction(
                  key: ValueKey('edit-message-${message.id}'),
                  tooltip: strings.edit,
                  icon: LucideIcons.pencil,
                  size: 16,
                  onPressed: widget.onEdit == null ? null : _startEditing,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EditBox extends StatelessWidget {
  const _EditBox({
    required this.draft,
    required this.hint,
    required this.enabled,
    required this.hasAttachments,
    required this.onCancel,
    required this.onSubmit,
  });

  final TextEditingController draft;
  final String hint;
  final bool enabled;
  final bool hasAttachments;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ShadInput(
            key: const Key('edit-input'),
            controller: draft,
            autofocus: true,
            enabled: enabled,
            minLines: 1,
            maxLines: 6,
            placeholder: Text(hint),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ShadButton.outline(
                key: const Key('edit-cancel'),
                onPressed: onCancel,
                child: Text(strings.cancel),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: draft,
                builder: (context, value, _) {
                  final ready =
                      enabled &&
                      (value.text.trim().isNotEmpty || hasAttachments);
                  return ShadButton(
                    key: const Key('edit-send'),
                    onPressed: ready ? onSubmit : null,
                    child: Text(strings.send),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 兄弟版本切换：`当前 / 总数`，左右各切一条（§5.5）。
class _VersionSwitcher extends StatelessWidget {
  const _VersionSwitcher({required this.versions, required this.onSelect});

  final MessageVersions versions;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final previous = versions.previousId;
    final next = versions.nextId;
    final current = versions.index + 1;
    final total = versions.ids.length;
    return Semantics(
      label: strings.messageVersions,
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconAction(
            key: const Key('previous-version'),
            tooltip: strings.previousVersion,
            icon: LucideIcons.chevronLeft,
            size: 16,
            onPressed: onSelect != null && previous != null
                ? () => onSelect!(previous)
                : null,
          ),
          Semantics(
            label: strings.versionPosition(current, total),
            child: Text(
              '$current / $total',
              style: TextStyle(fontSize: 12, color: colors.mutedForeground),
            ),
          ),
          _IconAction(
            key: const Key('next-version'),
            tooltip: strings.nextVersion,
            icon: LucideIcons.chevronRight,
            size: 16,
            onPressed: onSelect != null && next != null
                ? () => onSelect!(next)
                : null,
          ),
        ],
      ),
    );
  }
}

/// 操作条与切换器共用的图标按钮：视觉 36，点击区 44（§6.1）。
class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 18,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: ShadIconButton.ghost(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: size,
        width: 44,
        height: 44,
        padding: EdgeInsets.zero,
        foregroundColor: colors.mutedForeground,
        hoverForegroundColor: colors.foreground,
      ),
    );
  }
}

/// 助手回复：思考 / 工具时间线、正文、来源胶囊与操作条（§5.3–§5.6）。
class _AssistantMessageView extends StatelessWidget {
  const _AssistantMessageView({
    required this.reply,
    required this.versions,
    required this.isLast,
    required this.busy,
    required this.speech,
    required this.onReadAloud,
    required this.onSelectVersion,
    required this.onRegenerate,
    required this.onContinue,
    required this.onRetryUpload,
  });

  final AssistantMessage reply;
  final MessageVersions? versions;
  final bool isLast;
  final bool busy;
  final SpeechView speech;
  final void Function(AssistantMessage reply, String text) onReadAloud;
  final ValueChanged<String>? onSelectVersion;
  final ValueChanged<AssistantMessage>? onRegenerate;
  final ValueChanged<AssistantMessage>? onContinue;
  final ValueChanged<AssistantMessage>? onRetryUpload;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final view = buildReplyView(reply, streaming: reply.isInFlight);
    final refused = reply.stopReason == StopReason.refusal;
    final refusal = refusalText(strings, reply);
    final answerText = view.answer?.text.trim() ?? '';
    final canReadAloud = !reply.isInFlight && !refused && answerText.isNotEmpty;
    final copyText = refused ? (refusal ?? '') : answerText;
    final canCopy =
        copyText.isNotEmpty && reply.status != ReplyStatus.streaming;
    final continuing = canContinueReply(reply) && isLast;
    return Semantics(
      label: strings.assistantReply,
      container: true,
      child: SizedBox(
        key: Key('assistant-body-${reply.id}'),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!refused && (view.steps.isNotEmpty || reply.thinking == true))
              _ThinkingArea(reply: reply, view: view),
            if (!refused && view.answer != null)
              MarkdownView(
                text: view.answer!.markdown,
                streaming: reply.isInFlight,
                sources: view.sources,
                textStyle: markdownBodyStyle(context),
              ),
            if (reply.status == ReplyStatus.error)
              _ReplyError(
                reply: reply,
                busy: busy,
                onRetryUpload: onRetryUpload,
              ),
            if (refusal != null && reply.status != ReplyStatus.error)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: MarkdownView(
                  text: refusal,
                  textStyle: markdownBodyStyle(context),
                ),
              ),
            if (reply.isInFlight && !refused) const _StreamingCursor(),
            if (!refused && !reply.isInFlight && view.searchResults.isNotEmpty)
              _SourcePill(sources: view.searchResults),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _ActionBar(
                reply: reply,
                versions: versions,
                busy: busy,
                refused: refused,
                canCopy: canCopy,
                copyText: copyText,
                canReadAloud: canReadAloud,
                speech: speech,
                onReadAloud: () => onReadAloud(reply, answerText),
                onSelectVersion: onSelectVersion,
                onRegenerate: onRegenerate,
                onContinue: onContinue,
                continuing: continuing,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.reply,
    required this.versions,
    required this.busy,
    required this.refused,
    required this.canCopy,
    required this.copyText,
    required this.canReadAloud,
    required this.speech,
    required this.onReadAloud,
    required this.onSelectVersion,
    required this.onRegenerate,
    required this.onContinue,
    required this.continuing,
  });

  final AssistantMessage reply;
  final MessageVersions? versions;
  final bool busy;
  final bool refused;
  final bool canCopy;
  final String copyText;
  final bool canReadAloud;
  final SpeechView speech;
  final VoidCallback onReadAloud;
  final ValueChanged<String>? onSelectVersion;
  final ValueChanged<AssistantMessage>? onRegenerate;
  final ValueChanged<AssistantMessage>? onContinue;
  final bool continuing;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    // 生成中不显示操作条；停止入口只在输入区（与 chat-demo 一致，§5.3）。
    if (reply.isInFlight) return const SizedBox.shrink();
    return Semantics(
      label: strings.messageActions,
      container: true,
      // 图标操作靠左，继续生成靠右（同 chat-demo）；窄屏或放大字号时图标换行。
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (versions != null && versions!.hasMultiple)
                  _VersionSwitcher(
                    versions: versions!,
                    onSelect: onSelectVersion,
                  ),
                if (canCopy)
                  _IconAction(
                    key: Key('copy-${reply.id}'),
                    tooltip: strings.copy,
                    icon: LucideIcons.copy,
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: copyText)),
                  ),
                if (!refused) ...[
                  if (canReadAloud)
                    ReadAloudButton(
                      phase: speech.phase,
                      active: speech.readingMessageId == reply.id,
                      enabled: !speech.voiceBusy,
                      onPressed: onReadAloud,
                    ),
                  _IconAction(
                    key: Key('regenerate-${reply.id}'),
                    tooltip: strings.regenerate,
                    icon: LucideIcons.refreshCw,
                    onPressed: busy || onRegenerate == null
                        ? null
                        : () => onRegenerate!(reply),
                  ),
                ],
              ],
            ),
          ),
          if (continuing) ...[
            const SizedBox(width: 10),
            _ContinueButton(onPressed: busy ? null : () => onContinue!(reply)),
          ],
        ],
      ),
    );
  }
}

/// 「继续生成」描边按钮；停止提示与操作条共用（§5.3、§5.5）。
class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    // chat-demo outlined：透明底、前景随正文（深色白 / 浅色黑）、常规字重。
    return ShadButton.outline(
      key: const Key('continue-reply'),
      onPressed: onPressed,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      foregroundColor: colors.foreground,
      hoverForegroundColor: colors.foreground,
      child: Text(
        strings.continueGeneration,
        style: const TextStyle(fontSize: 14, height: 22 / 14),
      ),
    );
  }
}

class _ReplyError extends StatelessWidget {
  const _ReplyError({
    required this.reply,
    required this.busy,
    required this.onRetryUpload,
  });

  final AssistantMessage reply;
  final bool busy;
  final ValueChanged<AssistantMessage>? onRetryUpload;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final color = ShadTheme.of(context).colorScheme.destructive;
    final error = reply.error == null
        ? apiErrorText(strings, ApiErrorCondition.other)
        : replyErrorText(strings, reply.error!);
    final canRetry =
        reply.error?.kind == ApiErrorKind.upload &&
        reply.error?.retryable == true &&
        onRetryUpload != null;
    // 对齐 chat-demo 的 notice：14/22 红字行，图标与首行顶端对齐。
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 6),
            child: Icon(LucideIcons.circleAlert, size: 14, color: color),
          ),
          Expanded(
            child: Text(
              error,
              style: TextStyle(fontSize: 14, height: 22 / 14, color: color),
            ),
          ),
          if (canRetry)
            ShadButton.link(
              onPressed: busy ? null : () => onRetryUpload!(reply),
              child: Text(strings.retry),
            ),
        ],
      ),
    );
  }
}

/// 流式光标：2×16 主色竖条，650 ms 往返；减少动画时静止（§3.8）。
class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor({this.height = 16});

  final double height;

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool _animate = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (_animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!_animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Opacity(
          opacity: _animate ? 0.2 + _controller.value * 0.8 : 1,
          child: child,
        ),
        child: Container(
          width: 2,
          height: widget.height,
          color: colors.primary,
        ),
      ),
    );
  }
}

/// 思考与工具步骤的时间线；开启深度思考时带可折叠标题（§5.4）。
class _ThinkingArea extends StatefulWidget {
  const _ThinkingArea({required this.reply, required this.view});

  final AssistantMessage reply;
  final ReplyView view;

  @override
  State<_ThinkingArea> createState() => _ThinkingAreaState();
}

class _ThinkingAreaState extends State<_ThinkingArea> {
  bool _open = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_ThinkingArea oldWidget) {
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
    final active = widget.reply.isInFlight && widget.view.answer == null;
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
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final reply = widget.reply;
    final view = widget.view;
    final thinking =
        reply.thinking ?? view.steps.any((step) => step is ThinkingStep);
    final title = thinking ? _title(l10n) : null;
    if (view.steps.isEmpty && title == null) return const SizedBox.shrink();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Semantics(
            button: true,
            expanded: _open,
            label: title,
            child: GestureDetector(
              key: const Key('thinking-header'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.brain,
                      size: 14,
                      color: colors.mutedForeground,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 18 / 12.5,
                          color: colors.mutedForeground,
                        ),
                      ),
                    ),
                    if (reply.isInFlight) ...[
                      const SizedBox(width: 4),
                      const _StreamingCursor(height: 12),
                    ],
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _open ? 0 : -0.5,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 14,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (title == null || _open)
          for (var index = 0; index < view.steps.length; index++)
            _StepItem(
              step: view.steps[index],
              sources: view.sources,
              searchResults: view.searchResults,
              streaming: reply.isInFlight,
              replyStatus: reply.status,
              isLast: index == view.steps.length - 1,
            ),
      ],
    );
  }

  String _title(AppLocalizations l10n) {
    final view = widget.view;
    final reply = widget.reply;
    if (view.answer != null) {
      final seconds = replyThinkingSeconds(reply);
      return seconds == null
          ? l10n.deepThinking
          : l10n.thoughtForSeconds(seconds);
    }
    if (!reply.isInFlight) return l10n.stopped;
    final last = view.steps.isEmpty ? null : view.steps.last;
    if (last is SearchStep && last.status == ToolStatus.wip) {
      return isImageSearchKind(last.kind)
          ? l10n.imageSearching
          : l10n.searching;
    }
    if ((last is OpenStep &&
            last.pages.any((page) => page.status == ToolStatus.wip)) ||
        (last is FindStep &&
            last.patterns.any((item) => item.status == ToolStatus.wip))) {
      return l10n.browsingWeb;
    }
    if (last is ReadLinkStep &&
        last.links.any((link) => link.status == ToolStatus.wip)) {
      return l10n.reading;
    }
    final seconds = _streamingSeconds();
    return seconds == null ? l10n.thinking : l10n.thinkingForSeconds(seconds);
  }

  /// 流式期间思考块的累计用时；没有计时数据时返回 null。
  int? _streamingSeconds() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var millis = 0;
    var timed = false;
    for (final block in widget.reply.blocks.whereType<ThinkingBlock>()) {
      final start = block.startedAt;
      if (start == null) continue;
      timed = true;
      millis += (block.endedAt ?? now) - start;
    }
    return timed ? max(1, (millis / 1000).round()) : null;
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
      final colors = ShadTheme.of(context).colorScheme;
      return Container(
        key: const Key('thinking-body'),
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colors.border, width: 2)),
        ),
        child: MarkdownView(
          text: step.blocks.map((block) => block.thinking).join(),
          streaming: streaming && isLast,
          dense: true,
          disableLinks: true,
          textStyle: markdownSmallStyle(context),
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
          textStyle: markdownSmallStyle(context),
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

TextStyle _toolTextStyle(BuildContext context) => TextStyle(
  fontSize: 13,
  height: 18 / 13,
  color: ShadTheme.of(context).colorScheme.mutedForeground,
);

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.icon, required this.child, this.onTap});

  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: colors.mutedForeground),
            const SizedBox(width: 6),
            Expanded(child: child),
          ],
        ),
      ),
    );
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
    final l10n = AppLocalizations.of(context)!;
    final step = widget.step;
    final failed = step.status == ToolStatus.failed;
    final interrupted =
        failed &&
        !widget.streaming &&
        widget.replyStatus == ReplyStatus.stopped;
    final clickable = step.status != ToolStatus.wip && step.results.isNotEmpty;
    final style = _toolTextStyle(context);
    final Widget text;
    if (step.status == ToolStatus.wip) {
      if (step.queries.isNotEmpty) {
        text = Text(
          l10n.searchingQuery(step.queries[_tick % step.queries.length]),
          style: style,
        );
      } else {
        text = Text(
          isImageSearchKind(step.kind)
              ? l10n.imageSearching
              : l10n.searchingDots,
          style: style,
        );
      }
    } else if (interrupted) {
      text = Text(l10n.searchStopped, style: style);
    } else if (failed) {
      text = Text(l10n.searchUnavailable, style: style);
    } else if (step.results.isEmpty) {
      text = Text(
        isDeepSearchKind(step.kind)
            ? l10n.noSuitableResults
            : l10n.noRelevantResults,
        style: style,
      );
    } else if (isDeepSearchKind(step.kind)) {
      text = Text(l10n.searchedPages(step.results.length), style: style);
    } else {
      text = Text(l10n.readPages(step.results.length), style: style);
    }

    return _ToolRow(
      icon: LucideIcons.globe,
      onTap: clickable
          ? () => _showSourcesSheet(context, widget.searchResults)
          : null,
      child: Row(
        children: [
          Expanded(child: text),
          if (step.status != ToolStatus.wip && step.results.isNotEmpty)
            _SiteIcons(sources: step.results, size: 16, overlap: 4),
        ],
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
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final allFailed = step.pages.every(
      (page) => page.status == ToolStatus.failed,
    );
    final wip = step.pages.any((page) => page.status == ToolStatus.wip);
    return _ToolRow(
      icon: LucideIcons.globe,
      child: allFailed
          ? Text(l10n.browsePageFailed, style: _toolTextStyle(context))
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  wip
                      ? l10n.browsingWeb
                      : l10n.browsingPages(step.pages.length),
                  style: _toolTextStyle(context),
                ),
                for (final page in step.pages.take(5))
                  _PageLink(page: page, failedTip: l10n.browseFailed),
                if (step.pages.length > 5)
                  GestureDetector(
                    onTap: () => _showSourcesSheet(context, searchResults),
                    child: Text(
                      l10n.viewAll,
                      style: TextStyle(color: colors.primary, fontSize: 13),
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
    final l10n = AppLocalizations.of(context)!;
    final allFailed = step.patterns.every(
      (item) => item.status == ToolStatus.failed,
    );
    return _ToolRow(
      icon: LucideIcons.globe,
      child: allFailed
          ? Text(l10n.findFailed, style: _toolTextStyle(context))
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.findKeywords, style: _toolTextStyle(context)),
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
    final l10n = AppLocalizations.of(context)!;
    return _ToolRow(
      icon: LucideIcons.link,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.reading, style: _toolTextStyle(context)),
          for (final link in step.links) _PageLink(page: link),
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
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    if (page.status == ToolStatus.failed) {
      return Tooltip(
        message: failedTip ?? l10n.browseFailed,
        child: Text(
          page.title,
          style: TextStyle(fontSize: 13, color: colors.mutedForeground),
        ),
      );
    }
    return GestureDetector(
      onTap: () => openExternalLink(page.url, page.title),
      child: Text(
        page.title,
        style: TextStyle(fontSize: 13, color: colors.primary),
      ),
    );
  }
}

class _FindChip extends StatelessWidget {
  const _FindChip({required this.item});

  final FindItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final failed = item.status == ToolStatus.failed;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.status == ToolStatus.done)
            Icon(LucideIcons.check, size: 12, color: colors.mutedForeground)
          else if (failed)
            Icon(LucideIcons.x, size: 12, color: colors.mutedForeground),
          if (item.status != ToolStatus.wip) const SizedBox(width: 2),
          Text(
            item.pattern,
            style: TextStyle(fontSize: 12, color: colors.foreground),
          ),
        ],
      ),
    );
    if (!failed) return chip;
    return Tooltip(message: l10n.noMatchingContent, child: chip);
  }
}

/// 「N 个网页」胶囊：站点图标叠加 + 数量，点击打开来源抽屉（§5.6）。
class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.sources});

  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: '${l10n.pagesCount(sources.length)}, ${l10n.openSource}',
          child: GestureDetector(
            key: const Key('source-pill'),
            onTap: () => _showSourcesSheet(context, sources),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SiteIcons(sources: sources, size: 20, overlap: 6),
                  const SizedBox(width: 8),
                  Text(
                    l10n.pagesCount(sources.length),
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      fontWeight: FontWeight.w500,
                      color: colors.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 站点图标叠加；最多 4 个，缺图用 `link` 占位（§5.6）。
class _SiteIcons extends StatelessWidget {
  const _SiteIcons({
    required this.sources,
    required this.size,
    required this.overlap,
  });

  final List<Source> sources;
  final double size;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    final shown = sources.take(4).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final step = size - overlap;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var index = 0; index < shown.length; index++)
            Positioned(
              left: step * index,
              child: _SiteIcon(
                url: shown[index].siteIcon,
                size: size,
                bordered: index > 0,
              ),
            ),
        ],
      ),
    );
  }
}

class _SiteIcon extends StatelessWidget {
  const _SiteIcon({
    required this.url,
    required this.size,
    this.bordered = false,
  });

  final String? url;
  final double size;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final icon = Icon(
      LucideIcons.link,
      size: size * 0.6,
      color: colors.mutedForeground,
    );
    final uri = url == null ? null : webUri(url!);
    final image = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: uri == null
            ? ColoredBox(
                color: colors.muted,
                child: Center(child: icon),
              )
            : Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : ColoredBox(color: colors.muted),
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: colors.muted,
                  child: Center(child: icon),
                ),
              ),
      ),
    );
    if (!bordered) return image;
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(color: colors.card, shape: BoxShape.circle),
      child: image,
    );
  }
}

Future<void> _showSourcesSheet(BuildContext context, List<Source> sources) {
  final l10n = AppLocalizations.of(context)!;
  return showShadSheet<void>(
    context: context,
    builder: (context) => ShadSheet(
      title: Text(l10n.searchResults),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: sources.length,
          itemBuilder: (context, index) => _SourceCard(source: sources[index]),
          separatorBuilder: (context, index) => const SizedBox(height: 8),
        ),
      ),
    ),
  );
}

/// 来源卡片：序号、站点、日期、标题、摘要与 URL（§8.3）。
class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final date = _displayDate(source.publishedAt);
    final metaStyle = TextStyle(
      fontSize: 12,
      height: 16 / 12,
      color: colors.mutedForeground,
    );
    return GestureDetector(
      key: Key('source-card-${source.index}'),
      onTap: () => openExternalLink(source.url, source.title),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.muted,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${source.index}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.mutedForeground,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _SiteIcon(url: source.siteIcon, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            source.siteName,
                            if (date.isNotEmpty) date,
                          ].where((part) => part.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Semantics(
                    label: l10n.sourceNumber(source.index),
                    child: Text(
                      source.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 19 / 13.5,
                        fontWeight: FontWeight.w500,
                        color: colors.foreground,
                      ),
                    ),
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
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      source.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 14 / 10,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
                ],
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
