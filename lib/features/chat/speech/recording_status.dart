import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';

/// 录音状态行与 5 根电平条；转写中显示状态文字（`speech.md` §2.1、§7）。
class RecordingStatus extends StatelessWidget {
  const RecordingStatus({
    super.key,
    required this.phase,
    required this.seconds,
    required this.level,
  });

  final SpeechPhase phase;
  final int seconds;
  final double level;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    if (phase == SpeechPhase.recording) {
      return Padding(
        key: const Key('speech-status'),
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text(
              l10n.voiceInputRecording(seconds),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            _LevelBars(level: level),
          ],
        ),
      );
    }
    if (phase == SpeechPhase.transcribing) {
      return Padding(
        key: const Key('speech-status'),
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.voiceInputTranscribing,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 五根电平条：0..1 映射到高度，最低保留 2 dp，不做动画（减少动画安全）。
class _LevelBars extends StatelessWidget {
  const _LevelBars({required this.level});

  static const _weights = [0.6, 0.8, 1.0, 0.8, 0.6];

  final double level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const Key('level-bars'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final weight in _weights)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: 3,
              height: (level * weight * 20).clamp(2.0, 20.0),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}
