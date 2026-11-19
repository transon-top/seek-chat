import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';

/// 录音状态行与 5 根电平条；转写中显示状态文字（`speech.md` §2.1、§7）。
///
/// 输入区上方胶囊：高 36、`muted` 底、红色 8×8 状态点（ui.md §5.8）。
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
    final colors = ShadTheme.of(context).colorScheme;
    if (phase == SpeechPhase.recording) {
      return _Capsule(
        child: Row(
          children: [
            _Dot(color: colors.destructive),
            const SizedBox(width: 8),
            Text(l10n.voiceInputRecording(seconds), style: _textStyle(colors)),
            const SizedBox(width: 8),
            _LevelBars(level: level),
          ],
        ),
      );
    }
    if (phase == SpeechPhase.transcribing) {
      return _Capsule(
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.mutedForeground,
              ),
            ),
            const SizedBox(width: 8),
            Text(l10n.voiceInputTranscribing, style: _textStyle(colors)),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  TextStyle _textStyle(ShadColorScheme colors) =>
      TextStyle(fontSize: 12.5, color: colors.foreground);
}

class _Capsule extends StatelessWidget {
  const _Capsule({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Padding(
      key: const Key('speech-status'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(999),
        ),
        child: child,
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 五根电平条：0..1 映射到高度，最低保留 2 dp，不做动画（减少动画安全）。
class _LevelBars extends StatelessWidget {
  const _LevelBars({required this.level});

  static const _weights = [0.6, 0.8, 1.0, 0.8, 0.6];

  final double level;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
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
