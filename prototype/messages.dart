/// 票 09 原型的消息区组件：气泡、思考块、引用、来源卡、分支与各状态。
library;

import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'data.dart';

ShadColorScheme _colors(BuildContext context) =>
    ShadTheme.of(context).colorScheme;

/// 流式光标。单独抽出来，停止生成后直接不再渲染。
class TypingCursor extends StatefulWidget {
  const TypingCursor({super.key, this.height = 16});

  final double height;

  @override
  State<TypingCursor> createState() => _TypingCursorState();
}

class _TypingCursorState extends State<TypingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: widget.height,
        margin: const EdgeInsets.only(left: 2),
        color: _colors(context).primary,
      ),
    );
  }
}

/// 可折叠的思考块。展开状态由调用方持有，方便同一回复里多个块各自独立。
class ThinkingBlock extends StatelessWidget {
  const ThinkingBlock({
    super.key,
    required this.text,
    required this.expanded,
    required this.onToggle,
    this.seconds,
    this.streaming = false,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;
  final int? seconds;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    final label = streaming
        ? seconds == null || seconds == 0
              ? '思考中…'
              : '思考中… $seconds 秒'
        : seconds == null
        ? '已深度思考'
        : '已深度思考（用时 $seconds 秒）';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            key: const Key('thinking-header'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.brain,
                    size: 14,
                    color: colors.mutedForeground,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.mutedForeground,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (streaming) const TypingCursor(height: 12),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
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
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: colors.mutedForeground.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: colors.mutedForeground,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 带行内引用角标的助手文本。角标只是视觉占位，点按行为不在原型内。
class AnswerText extends StatelessWidget {
  const AnswerText({
    super.key,
    required this.text,
    this.citationCount = 0,
    this.streaming = false,
    this.maxLines,
  });

  final String text;
  final int citationCount;
  final bool streaming;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: text,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.7,
              color: colors.foreground,
            ),
          ),
          if (streaming)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: TypingCursor(),
            ),
          for (var index = 1; index <= citationCount; index++)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.muted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: maxLines == null ? TextOverflow.clip : TextOverflow.fade,
    );
  }
}

class SearchProgressCard extends StatelessWidget {
  const SearchProgressCard({super.key, this.progress = 0.66});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.globe, size: 16, color: colors.mutedForeground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '正在联网搜索…',
                  style: TextStyle(fontSize: 13, color: colors.foreground),
                ),
              ),
              Text(
                '2 / 3',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.mutedForeground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ShadProgress(
            value: progress,
            minHeight: 3,
            color: colors.foreground,
            backgroundColor: colors.mutedForeground.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 6),
          Text(
            '已找到 2 个来源，正在阅读第 3 篇',
            style: TextStyle(fontSize: 11, color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class SourceCards extends StatelessWidget {
  const SourceCards({super.key, required this.sources});

  final List<FakeSource> sources;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(top: 10),
        itemCount: sources.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final source = sources[index];
          return GestureDetector(
            onTap: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('打开来源链接（原型占位）'))),
            child: Container(
              width: 224,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                            color: colors.mutedForeground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          source.site,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.mutedForeground,
                          ),
                        ),
                      ),
                      Icon(
                        LucideIcons.externalLink,
                        size: 12,
                        color: colors.mutedForeground,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    source.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: colors.foreground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    source.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class BranchSwitcher extends StatelessWidget {
  const BranchSwitcher({
    super.key,
    required this.branch,
    required this.count,
    required this.onPrev,
    required this.onNext,
  });

  final int branch;
  final int count;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShadIconButton.ghost(
          key: const Key('branch-prev'),
          onPressed: branch > 1 ? onPrev : null,
          icon: const Icon(LucideIcons.chevronLeft),
          width: 26,
          height: 26,
          iconSize: 14,
        ),
        Text(
          '$branch / $count',
          style: TextStyle(fontSize: 11, color: colors.mutedForeground),
        ),
        ShadIconButton.ghost(
          key: const Key('branch-next'),
          onPressed: branch < count ? onNext : null,
          icon: const Icon(LucideIcons.chevronRight),
          width: 26,
          height: 26,
          iconSize: 14,
        ),
      ],
    );
  }
}

class MessageActions extends StatelessWidget {
  const MessageActions({
    super.key,
    this.onCopy,
    this.onRegenerate,
    this.onReadAloud,
  });

  final VoidCallback? onCopy;
  final VoidCallback? onRegenerate;
  final VoidCallback? onReadAloud;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _action(context, LucideIcons.copy, '复制', onCopy),
        _action(context, LucideIcons.refreshCw, '重新生成', onRegenerate),
        _action(context, LucideIcons.volume2, '朗读', onReadAloud),
      ],
    );
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? onPressed,
  ) {
    final colors = _colors(context);
    return ShadTooltip(
      builder: (context) => Text(label),
      child: ShadIconButton.ghost(
        onPressed: onPressed ?? () {},
        icon: Icon(icon),
        width: 28,
        height: 28,
        iconSize: 14,
        foregroundColor: colors.mutedForeground,
      ),
    );
  }
}

class UserBubble extends StatelessWidget {
  const UserBubble({
    super.key,
    required this.text,
    this.attachments = const [],
    this.onEdit,
  });

  final String text;
  final List<FakeAttachment> attachments;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final attachment in attachments)
                  AttachmentChip(attachment: attachment, compact: true),
              ],
            ),
          ),
        Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.5,
              color: colors.foreground,
            ),
          ),
        ),
        if (onEdit != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ShadButton.link(
              onPressed: onEdit,
              foregroundColor: colors.mutedForeground,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              height: 22,
              child: const Text('编辑', style: TextStyle(fontSize: 11)),
            ),
          ),
      ],
    );
  }
}

/// 附件缩略图 / 文档条。上传进度与失败态都可以在同一组件里看到。
class AttachmentChip extends StatelessWidget {
  const AttachmentChip({
    super.key,
    required this.attachment,
    this.compact = false,
    this.onRetry,
    this.onRemove,
  });

  final FakeAttachment attachment;
  final bool compact;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    if (attachment.isImage) {
      return SizedBox(
        width: compact ? 54 : 64,
        height: compact ? 54 : 64,
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: colors.muted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: attachment.failed ? colors.destructive : colors.border,
                ),
              ),
              child: Icon(
                LucideIcons.image,
                size: 20,
                color: colors.mutedForeground,
              ),
            ),
            if (attachment.uploadProgress != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: attachment.uploadProgress,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            if (onRemove != null && attachment.uploadProgress == null)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.x,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      constraints: BoxConstraints(maxWidth: compact ? 190 : 210),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: attachment.failed ? colors.destructive : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.fileText,
            size: 16,
            color: attachment.failed
                ? colors.destructive
                : colors.mutedForeground,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.foreground),
            ),
          ),
          if (attachment.failed && onRetry != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRetry,
              child: Icon(
                LucideIcons.refreshCw,
                size: 14,
                color: colors.destructive,
              ),
            ),
          ],
          if (onRemove != null && !attachment.failed) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: Icon(
                LucideIcons.x,
                size: 12,
                color: colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AssistantView extends StatelessWidget {
  const AssistantView({
    super.key,
    required this.text,
    this.thinking,
    this.thinkingSeconds,
    this.thinkingExpanded = false,
    this.onThinkingToggle,
    this.streaming = false,
    this.citationCount = 0,
    this.sources = const [],
    this.showSearchProgress = false,
    this.showActions = true,
    this.onRegenerate,
    this.onCopy,
    this.onReadAloud,
    this.branchSwitcher,
    this.onStop,
  });

  final String text;
  final String? thinking;
  final int? thinkingSeconds;
  final bool thinkingExpanded;
  final VoidCallback? onThinkingToggle;
  final bool streaming;
  final int citationCount;
  final List<FakeSource> sources;
  final bool showSearchProgress;
  final bool showActions;
  final VoidCallback? onRegenerate;
  final VoidCallback? onCopy;
  final VoidCallback? onReadAloud;
  final Widget? branchSwitcher;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thinking != null)
          ThinkingBlock(
            text: thinking!,
            expanded: thinkingExpanded,
            onToggle: onThinkingToggle ?? () {},
            seconds: thinkingSeconds,
            streaming: streaming,
          ),
        if (showSearchProgress) const SearchProgressCard(),
        AnswerText(
          text: text,
          citationCount: citationCount,
          streaming: streaming,
        ),
        if (sources.isNotEmpty && !streaming) SourceCards(sources: sources),
        if (streaming && onStop != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ShadButton.outline(
              key: const Key('inline-stop-button'),
              onPressed: onStop,
              foregroundColor: colors.foreground,
              size: ShadButtonSize.sm,
              height: 30,
              leading: const Icon(LucideIcons.square, size: 11),
              child: const Text('停止生成'),
            ),
          ),
        if (!streaming)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                if (branchSwitcher != null) ...[
                  branchSwitcher!,
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: showActions
                      ? MessageActions(
                          onCopy: onCopy,
                          onRegenerate: onRegenerate,
                          onReadAloud: onReadAloud,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        if (!streaming) Divider(height: 24, thickness: 1, color: colors.border),
      ],
    );
  }
}

class StoppedNotice extends StatelessWidget {
  const StoppedNotice({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(LucideIcons.stopCircle, size: 14, color: colors.mutedForeground),
          const SizedBox(width: 6),
          Text(
            '已停止生成',
            style: TextStyle(fontSize: 12, color: colors.mutedForeground),
          ),
          const SizedBox(width: 12),
          ShadButton.outline(
            key: const Key('continue-button'),
            onPressed: onContinue,
            foregroundColor: colors.foreground,
            size: ShadButtonSize.sm,
            height: 28,
            child: const Text('继续生成'),
          ),
        ],
      ),
    );
  }
}

class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.onRetry, this.description});

  final VoidCallback onRetry;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadAlert.destructive(
          icon: const Icon(LucideIcons.circleAlert),
          title: const Text('连接失败'),
          description: Text(description ?? errorDescription),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: ShadButton.outline(
            key: const Key('retry-button'),
            onPressed: onRetry,
            foregroundColor: colors.foreground,
            child: const Text('重试'),
          ),
        ),
      ],
    );
  }
}

class RefusalCard extends StatelessWidget {
  const RefusalCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadAlert(
      icon: const Icon(LucideIcons.circleAlert),
      title: const Text('无法回答'),
      description: const Text(refusalDescription),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    Widget bar(double widthFactor) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 12,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShadProgress(
            value: null,
            minHeight: 3,
            color: colors.foreground,
            backgroundColor: colors.muted,
          ),
          const SizedBox(height: 24),
          bar(0.5),
          bar(0.9),
          bar(0.75),
          const SizedBox(height: 8),
          Text(
            '正在加载会话…',
            style: TextStyle(fontSize: 12, color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// 超长消息：默认 8 行，展开后完整显示。
class LongAnswerView extends StatelessWidget {
  const LongAnswerView({
    super.key,
    required this.text,
    required this.expanded,
    required this.onToggle,
  });

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = _colors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: Stack(
            children: [
              Text(
                text,
                maxLines: expanded ? null : 8,
                overflow: expanded ? TextOverflow.clip : TextOverflow.fade,
                style: TextStyle(
                  fontSize: 15.5,
                  height: 1.65,
                  color: colors.foreground,
                ),
              ),
              if (!expanded)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.background.withValues(alpha: 0),
                            colors.background,
                          ],
                          stops: const [0.7, 1],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        ShadButton.link(
          key: const Key('long-toggle'),
          onPressed: onToggle,
          foregroundColor: colors.foreground,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            expanded ? '收起' : '展开全文',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
