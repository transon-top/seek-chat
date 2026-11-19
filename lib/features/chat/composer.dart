import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/types.dart';
import 'attachments_view.dart';
import 'speech/recording_status.dart';
import 'speech/speech_controller.dart';
import 'speech/voice_button.dart';
import 'upload_tasks.dart';

/// 输入区：大圆角容器、开关胶囊、附件条、语音与发送 / 停止（ui.md §1.3、§5.2）。
///
/// 容器圆角 28、1px 描边、无阴影；内部左 16 / 上 12 / 右 12 / 下 10。
class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.input,
    required this.inputFocus,
    required this.busy,
    required this.phase,
    required this.thinking,
    required this.search,
    required this.attachments,
    required this.tasks,
    required this.onThinkingChanged,
    required this.onSearchChanged,
    required this.onAddAttachment,
    required this.onRetryAttachment,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onStop,
    required this.onVoice,
  });

  final TextEditingController input;
  final FocusNode inputFocus;
  final bool busy;
  final SpeechPhase phase;
  final bool thinking;
  final bool search;
  final List<DraftAttachment> attachments;
  final Map<String, UploadTask> tasks;
  final ValueChanged<bool> onThinkingChanged;
  final ValueChanged<bool> onSearchChanged;
  final VoidCallback onAddAttachment;
  final ValueChanged<String> onRetryAttachment;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final voiceBusy = phase.voiceBusy;
    final reading = phase.reading;
    final ready = allUploadsDone(attachments, tasks);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SpeechStatus(),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DraftAttachmentStrip(
                    attachments: attachments,
                    tasks: tasks,
                    onRetry: onRetryAttachment,
                    onRemove: onRemoveAttachment,
                  ),
                  ShadInput(
                    key: const Key('composer-input'),
                    controller: input,
                    focusNode: inputFocus,
                    minLines: 2,
                    maxLines: 5,
                    padding: EdgeInsets.zero,
                    decoration: ShadDecoration.none,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.6,
                      color: colors.foreground,
                    ),
                    placeholder: Text(
                      l10n.composerPlaceholder,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // 左侧开关可横向滚动，右侧按钮定宽不动，避免窄屏溢出。
                      Expanded(
                        child: _FadingScroll(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ComposerToggle(
                                key: const Key('thinking-toggle'),
                                icon: LucideIcons.brain,
                                label: l10n.deepThinking,
                                selected: thinking,
                                onChanged: onThinkingChanged,
                              ),
                              const SizedBox(width: 6),
                              ComposerToggle(
                                key: const Key('search-toggle'),
                                icon: LucideIcons.globe,
                                label: l10n.smartSearch,
                                selected: search,
                                onChanged: onSearchChanged,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: l10n.uploadFile,
                        child: ShadIconButton.ghost(
                          key: const Key('attach-button'),
                          onPressed: busy || voiceBusy ? null : onAddAttachment,
                          enabled: !busy && !voiceBusy,
                          icon: const Icon(LucideIcons.paperclip),
                          iconSize: 18,
                          width: 40,
                          height: 40,
                          padding: EdgeInsets.zero,
                          foregroundColor: colors.mutedForeground,
                        ),
                      ),
                      VoiceButton(
                        phase: phase,
                        onPressed: busy || reading ? null : onVoice,
                      ),
                      const SizedBox(width: 2),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: input,
                        builder: (context, value, child) {
                          final hasContent =
                              value.text.trim().isNotEmpty ||
                              attachments.isNotEmpty;
                          return SendButton(
                            busy: busy,
                            enabled: !busy && !voiceBusy && ready && hasContent,
                            onSend: onSend,
                            onStop: onStop,
                          );
                        },
                      ),
                    ],
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

/// 横向滚动 + 边缘渐隐：只有被遮挡的一侧淡出，内容完整展示时不加遮罩。
class _FadingScroll extends StatefulWidget {
  const _FadingScroll({required this.child});

  final Widget child;

  @override
  State<_FadingScroll> createState() => _FadingScrollState();
}

class _FadingScrollState extends State<_FadingScroll> {
  static const _fadeExtent = 24.0;
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      // 内容尺寸 / 视口变化时刷新可滚动状态。
      onNotification: (_) {
        setState(() {});
        return false;
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final metrics = _controller.hasClients ? _controller.position : null;
          final leftFade = metrics != null && metrics.pixels > 0.5;
          final rightFade =
              metrics != null && metrics.pixels < metrics.maxScrollExtent - 0.5;
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => _gradient(
              leftFade,
              rightFade,
              bounds.width,
            ).createShader(bounds),
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }

  LinearGradient _gradient(bool left, bool right, double width) {
    final fade = (_fadeExtent / width).clamp(0.0, 0.5);
    final colors = <Color>[];
    final stops = <double>[];
    if (left) {
      colors.addAll([Colors.transparent, Colors.white]);
      stops.addAll([0, fade]);
    } else {
      colors.add(Colors.white);
      stops.add(0);
    }
    if (right) {
      colors.addAll([Colors.white, Colors.transparent]);
      stops.addAll([1 - fade, 1]);
    } else {
      colors.add(Colors.white);
      stops.add(1);
    }
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: colors,
      stops: stops,
    );
  }
}

const _darkToggleFill = Color(0xFF283142);
const _darkToggleBorder = Color(0xFF4868B2);
const _darkToggleForeground = Color(0xFF679EFE);
const _darkToggleIdleForeground = Color(0xFFF9FAFB);

/// 深度思考 / 智能搜索胶囊；激活为浅蓝底 + 蓝描边 + 蓝色图标文字（ui.md §5.2）。
/// 深色取值照搬 chat-demo（blue-900 填充 / blue-600 描边 / blue-400 前景）。
class ComposerToggle extends StatelessWidget {
  const ComposerToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final foreground = selected
        ? (dark ? _darkToggleForeground : colors.primary)
        : (dark ? _darkToggleIdleForeground : colors.mutedForeground);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: () => onChanged(!selected),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 150),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? (dark
                      ? _darkToggleFill
                      : colors.primary.withValues(alpha: 0.10))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? (dark
                        ? _darkToggleBorder
                        : colors.primary.withValues(alpha: 0.45))
                  : colors.border,
            ),
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
                  height: 16 / 12.5,
                  color: foreground,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 发送 / 停止圆形按钮：可用为主色，禁用为主色 35%，生成中换成停止（ui.md §5.2）。
class SendButton extends StatelessWidget {
  const SendButton({
    super.key,
    required this.busy,
    required this.enabled,
    required this.onSend,
    required this.onStop,
  });

  final bool busy;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    if (busy) {
      return Tooltip(
        message: l10n.stop,
        child: Semantics(
          button: true,
          label: l10n.stop,
          child: GestureDetector(
            key: const Key('stop-button'),
            onTap: onStop,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.foreground,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.square,
                size: 14,
                color: colors.background,
              ),
            ),
          ),
        ),
      );
    }
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Tooltip(
      message: l10n.send,
      child: Semantics(
        button: true,
        label: l10n.send,
        child: GestureDetector(
          key: const Key('send-button'),
          onTap: enabled ? onSend : null,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 150),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: enabled
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
        ),
      ),
    );
  }
}

/// 录音计时与电平只重建这一行，不触发整页重建（`speech.md` §7）。
class _SpeechStatus extends ConsumerWidget {
  const _SpeechStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      speechControllerProvider.select(
        (state) => (
          phase: state.phase,
          seconds: state.recordingSeconds,
          level: state.level,
        ),
      ),
    );
    return RecordingStatus(
      phase: status.phase,
      seconds: status.seconds,
      level: status.level,
    );
  }
}
