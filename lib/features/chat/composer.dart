import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/types.dart';
import '../../shared/widgets/horizontal_fade_scroll.dart';
import 'attachments_view.dart';
import 'speech/speech_controller.dart';
import 'speech/voice_button.dart';
import 'upload_tasks.dart';

/// ZH
/// 输入区：大圆角容器、开关胶囊、附件条、语音与发送 / 停止（ui.md §1.3、§5.2）。
///
/// 容器圆角 28、1px 描边、无阴影；内部左 16 / 上 12 / 右 12 / 下 10。
///
/// EN
/// Composer: large rounded container, toggle pills, attachment strip, voice, send / stop (ui.md §1.3, §5.2).
///
/// Container radius 28, 1px border, no shadow; inner padding left 16 / top 12 / right 12 / bottom 10.
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
    required this.panelOpen,
    required this.attachmentPanel,
    required this.onThinkingChanged,
    required this.onSearchChanged,
    required this.onTogglePanel,
    required this.onRetryAttachment,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onStop,
    required this.onVoiceStart,
    required this.onVoiceEnd,
    required this.onVoicePointerCancel,
    required this.onVoiceCancelArmed,
    required this.onVoiceCancel,
  });

  final TextEditingController input;
  final FocusNode inputFocus;
  final bool busy;
  final SpeechPhase phase;
  final bool thinking;
  final bool search;
  final List<DraftAttachment> attachments;
  final Map<String, UploadTask> tasks;
  final bool panelOpen;
  final Widget attachmentPanel;
  final ValueChanged<bool> onThinkingChanged;
  final ValueChanged<bool> onSearchChanged;
  final VoidCallback onTogglePanel;
  final ValueChanged<String> onRetryAttachment;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;
  final VoidCallback onVoicePointerCancel;
  final ValueChanged<bool> onVoiceCancelArmed;
  final VoidCallback onVoiceCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final voiceBusy = phase.voiceBusy;
    final reading = phase.reading;
    final ready = allUploadsDone(attachments, tasks);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              // ZH
              // 下 5：按钮行 40 命中区比 29 胶囊高 5.5，胶囊下缘到卡片边
              // 才是官方 app 的约 10。
              //
              // EN
              // Bottom 5: the 40 button-row hit area is 5.5 taller than the 29 pill, so the
              // pill's lower edge sits about 10 from the card edge, matching the official app.
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 5),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IgnorePointer(
                    ignoring: voiceBusy,
                    child: DraftAttachmentStrip(
                      attachments: attachments,
                      tasks: tasks,
                      onRetry: onRetryAttachment,
                      onRemove: onRemoveAttachment,
                    ),
                  ),
                  IgnorePointer(
                    ignoring: voiceBusy,
                    child: ShadInput(
                      key: const Key('composer-input'),
                      controller: input,
                      focusNode: inputFocus,
                      readOnly: voiceBusy,
                      // ZH
                      // 官方 app 窄屏输入区约 1.25 行高；单行起步，随内容增高。
                      //
                      // EN
                      // Official app narrow composer is about 1.25 lines; start at one line and grow.
                      minLines: 1,
                      maxLines: 5,
                      padding: EdgeInsets.zero,
                      decoration: ShadDecoration.none,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: colors.foreground,
                      ),
                      placeholder: Text(
                        attachments.isEmpty
                            ? l10n.composerHint
                            : l10n.composerHintWithAttachments,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.6,
                          color: colors.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                  // ZH
                  // 官方 app：输入框下缘到按钮行 = 4 外边距 + 12 行内边距。
                  //
                  // EN
                  // Official app: input bottom to button row = 4 outer margin + 12 inner padding.
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // ZH
                      // 左侧开关可横向滚动，右侧按钮定宽不动，避免窄屏溢出。
                      //
                      // EN
                      // Left toggles scroll horizontally; fixed right buttons avoid narrow-screen overflow.
                      Expanded(
                        child: HorizontalFadeScroll(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ComposerToggle(
                                key: const Key('thinking-toggle'),
                                icon: LucideIcons.atom,
                                label: l10n.deepThinking,
                                selected: thinking,
                                enabled: !voiceBusy,
                                onChanged: onThinkingChanged,
                              ),
                              const SizedBox(width: 6),
                              ComposerToggle(
                                key: const Key('search-toggle'),
                                icon: LucideIcons.globe,
                                label: l10n.smartSearch,
                                selected: search,
                                enabled: !voiceBusy,
                                onChanged: onSearchChanged,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: input,
                        builder: (context, value, _) {
                          final hasText = value.text.trim().isNotEmpty;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PlusButton(
                                open: panelOpen,
                                onPressed: busy || voiceBusy
                                    ? null
                                    : onTogglePanel,
                              ),
                              if (!hasText && !busy) ...[
                                VoiceButton(
                                  phase: phase,
                                  enabled: !reading,
                                  onStart: onVoiceStart,
                                  onEnd: onVoiceEnd,
                                  onGestureCancel: onVoicePointerCancel,
                                  onCancelArmedChanged: onVoiceCancelArmed,
                                  onCancelRecording: onVoiceCancel,
                                ),
                              ],
                              // ZH
                              // 无可发送内容（空文本且无附件）时不渲染发送按钮。
                              //
                              // EN
                              // No send button when there is nothing to send (no text and no attachments).
                              if (busy ||
                                  hasText ||
                                  attachments.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                SendButton(
                                  busy: busy,
                                  enabled:
                                      !busy &&
                                      !voiceBusy &&
                                      ready &&
                                      (hasText || attachments.isNotEmpty),
                                  onSend: onSend,
                                  onStop: onStop,
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: reduceMotion
                  ? Duration.zero
                  : Duration(milliseconds: panelOpen ? 220 : 180),
              curve: panelOpen ? Curves.easeOutCubic : Curves.easeOut,
              alignment: Alignment.topCenter,
              child: panelOpen
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                      ),
                      child: SingleChildScrollView(child: attachmentPanel),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

const _lightToggleIdleBorder = Color(0xFFEDEDED);
const _lightToggleFill = Color(0xFFEDF3FE);
const _lightToggleBorder = Color(0xFFD3E1FF);
const _darkToggleFill = Color(0xFF283142);
const _darkToggleBorder = Color(0xFF4868B2);
const _darkToggleForeground = Color(0xFF679EFE);
const _darkToggleIdleForeground = Color(0xFFF9FAFB);

/// ZH
/// 深度思考 / 智能搜索胶囊；照搬官方 app：高 29、未激活近黑字、激活浅蓝底 +
/// 蓝描边 + 蓝图标文字。深色取值照搬 chat-demo（blue-900 / blue-600 / blue-400）。
///
/// EN
/// Deep Search / Web Search pills; mirror the official app: height 29, near-black
/// idle text, light blue fill + blue border + blue icon and text. Dark values
/// mirror chat-demo (blue-900 / blue-600 / blue-400).
class ComposerToggle extends StatelessWidget {
  const ComposerToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final foreground = selected
        ? (dark ? _darkToggleForeground : colors.primary)
        : (dark ? _darkToggleIdleForeground : colors.foreground);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? () => onChanged(!selected) : null,
        behavior: HitTestBehavior.opaque,
        // ZH
        // 官方 app 点击后底色 / 描边 / 文字同帧切换，不做渐变。
        //
        // EN
        // The official app switches fill / border / text in the same frame on tap, with no fade.
        child: Container(
          constraints: const BoxConstraints(minHeight: 29),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? (dark ? _darkToggleFill : _lightToggleFill)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? (dark ? _darkToggleBorder : _lightToggleBorder)
                  : (dark ? colors.border : _lightToggleIdleBorder),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  height: 18 / 13,
                  color: foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ZH
/// `+` / `×`：展开与收起附件面板，180ms 交叉淡入 + 90° 旋转（ui.md §3.8）。
///
/// EN
/// `+` / `×`: expand / collapse the Attachment Panel with 180ms cross-fade + 90° rotation (ui.md §3.8).
class _PlusButton extends StatelessWidget {
  const _PlusButton({required this.open, required this.onPressed});

  final bool open;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Tooltip(
      message: open ? l10n.closeAttachmentPanel : l10n.addAttachment,
      child: Opacity(
        opacity: onPressed == null ? 0.4 : 1,
        // ZH
        // 视觉 20 描边圆，点击区保持 40（参照官方 app）。
        //
        // EN
        // Visual 20 outlined circle; hit area stays 40 (per official app).
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.foreground, width: 1.2),
                ),
              ),
              ShadIconButton.ghost(
                key: const Key('attach-button'),
                onPressed: onPressed,
                enabled: onPressed != null,
                icon: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: RotationTransition(
                      turns: Tween<double>(
                        begin: 0,
                        end: 0.25,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Icon(
                    open ? LucideIcons.x : LucideIcons.plus,
                    key: ValueKey(open),
                    size: 11,
                  ),
                ),
                iconSize: 11,
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                foregroundColor: colors.foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 发送 / 停止圆形按钮：视觉 28 实心圆（点击区 40），可用为主色，禁用为主色 35%，
/// 生成中同底换成实心方块停止图标（参照 DeepSeek 官方输入区，ui.md §5.2）。
///
/// EN
/// Send / stop round button: visual 28 filled circle (hit area 40), primary when
/// enabled, 35% when disabled, and a filled square stop icon on the same fill while
/// generating (per DeepSeek composer, ui.md §5.2).
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
        message: l10n.stopGeneration,
        child: Semantics(
          button: true,
          label: l10n.stopGeneration,
          child: GestureDetector(
            key: const Key('stop-button'),
            onTap: onStop,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  // ZH
                  // 实心圆角方块，按官方比例收在 28 圆内。
                  //
                  // EN
                  // Filled rounded square scaled into the 28 circle as in the official app.
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors.primaryForeground,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
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
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: enabled
                      ? colors.primary
                      : colors.primary.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.arrowUp,
                  size: 20,
                  color: colors.primaryForeground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
