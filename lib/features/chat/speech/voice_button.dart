import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';

/// 输入区的语音按钮：空闲、录音中、转写中三态（`speech.md` §2.1）。
///
/// `onPressed` 为 null 表示禁用（生成中、朗读中）。
class VoiceButton extends StatelessWidget {
  const VoiceButton({super.key, required this.phase, required this.onPressed});

  final SpeechPhase phase;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final Widget icon;
    final String tooltip;
    switch (phase) {
      case SpeechPhase.recording:
        icon = Stack(
          alignment: Alignment.center,
          children: [
            Icon(LucideIcons.mic, size: 18, color: colors.destructive),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.destructive,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        );
        tooltip = l10n.voiceInputStop;
      case SpeechPhase.transcribing:
        icon = SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.mutedForeground,
          ),
        );
        tooltip = l10n.voiceInputCancel;
      case SpeechPhase.idle:
      case SpeechPhase.loading:
      case SpeechPhase.playing:
        icon = const Icon(LucideIcons.mic, size: 18);
        tooltip = l10n.voiceInput;
    }
    return Tooltip(
      message: tooltip,
      child: ShadIconButton.ghost(
        key: const Key('voice-button'),
        onPressed: onPressed,
        enabled: onPressed != null,
        icon: icon,
        iconSize: 18,
        width: 40,
        height: 40,
        padding: EdgeInsets.zero,
        foregroundColor: colors.mutedForeground,
      ),
    );
  }
}
