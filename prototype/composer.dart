/// 票 09 原型的输入区：大圆角容器、胶囊开关、附件、语音与发送。
library;

import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'data.dart';
import 'messages.dart';

class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.attachments,
    required this.thinking,
    required this.search,
    required this.recording,
    required this.busy,
    required this.onThinkingChanged,
    required this.onSearchChanged,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onRetryAttachment,
    required this.onVoice,
    required this.onReadAloud,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final List<FakeAttachment> attachments;
  final bool thinking;
  final bool search;
  final bool recording;
  final bool busy;
  final ValueChanged<bool> onThinkingChanged;
  final ValueChanged<bool> onSearchChanged;
  final VoidCallback onAttach;
  final ValueChanged<int> onRemoveAttachment;
  final ValueChanged<int> onRetryAttachment;
  final VoidCallback onVoice;
  final VoidCallback onReadAloud;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (recording)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: colors.muted,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.destructive,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正在聆听…',
                    style: TextStyle(fontSize: 12, color: colors.foreground),
                  ),
                ),
                const TypingCursor(height: 12),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (attachments.isNotEmpty)
                SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: attachments.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) => AttachmentChip(
                      attachment: attachments[index],
                      onRetry: () => onRetryAttachment(index),
                      onRemove: () => onRemoveAttachment(index),
                    ),
                  ),
                ),
              ShadInput(
                key: const Key('composer-input'),
                controller: controller,
                minLines: 1,
                maxLines: 5,
                padding: EdgeInsets.zero,
                decoration: ShadDecoration.none,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: colors.foreground,
                ),
                placeholder: Text(
                  '请输入消息',
                  style: TextStyle(fontSize: 16, color: colors.mutedForeground),
                ),
                onSubmitted: (_) => onSend(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Pill(
                    key: const Key('thinking-toggle'),
                    icon: LucideIcons.brain,
                    label: '深度思考',
                    selected: thinking,
                    onTap: () => onThinkingChanged(!thinking),
                  ),
                  const SizedBox(width: 6),
                  _Pill(
                    key: const Key('search-toggle'),
                    icon: LucideIcons.globe,
                    label: '智能搜索',
                    selected: search,
                    onTap: () => onSearchChanged(!search),
                  ),
                  const Spacer(),
                  _icon(
                    context,
                    key: const Key('attach-button'),
                    icon: LucideIcons.paperclip,
                    onPressed: onAttach,
                  ),
                  _icon(
                    context,
                    key: const Key('mic-button'),
                    icon: LucideIcons.mic,
                    onPressed: onVoice,
                    color: recording ? colors.destructive : null,
                  ),
                  _icon(
                    context,
                    key: const Key('audio-button'),
                    icon: LucideIcons.audioLines,
                    onPressed: onReadAloud,
                  ),
                  const SizedBox(width: 2),
                  _sendButton(context),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sendButton(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    if (busy) {
      return GestureDetector(
        key: const Key('stop-button'),
        onTap: onStop,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.foreground,
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.square, size: 14, color: colors.background),
        ),
      );
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final ready = value.text.trim().isNotEmpty;
        return GestureDetector(
          key: const Key('send-button'),
          onTap: onSend,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: ready
                  ? colors.primary
                  : colors.primary.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.arrowUp,
              size: 18,
              color: colors.primaryForeground,
            ),
          ),
        );
      },
    );
  }

  Widget _icon(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final colors = ShadTheme.of(context).colorScheme;
    return GestureDetector(
      key: key,
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 30,
        height: 34,
        child: Icon(icon, size: 18, color: color ?? colors.mutedForeground),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final foreground = selected ? colors.foreground : colors.mutedForeground;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? colors.muted : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? colors.border : colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: foreground,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
