import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';

/// 输入区的语音按钮：空闲、录音中、转写中三态（`speech.md` §2.1）。
class VoiceButton extends StatelessWidget {
  const VoiceButton({super.key, required this.phase, required this.onPressed});

  final SpeechPhase phase;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final Widget icon;
    final String tooltip;
    switch (phase) {
      case SpeechPhase.recording:
        icon = Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.mic),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        );
        tooltip = l10n.voiceInputStop;
      case SpeechPhase.transcribing:
        icon = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        tooltip = l10n.voiceInputCancel;
      case SpeechPhase.idle:
      case SpeechPhase.loading:
      case SpeechPhase.playing:
        icon = const Icon(Icons.mic_none);
        tooltip = l10n.voiceInput;
    }
    return IconButton(
      key: const Key('voice-button'),
      onPressed: onPressed,
      icon: icon,
      tooltip: tooltip,
    );
  }
}
