import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';

/// 录音浮层（GLOSSARY: Recording Overlay）的占位视觉；
/// 票 06 替换为蓝色动态团块与波形。
///
/// 不响应点击，文案为 liveRegion，只播报开始、取消与识别（`speech.md` §8）。
class RecordingOverlay extends StatelessWidget {
  const RecordingOverlay({super.key, required this.phase});

  final SpeechPhase phase;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final (text, semanticsLabel) = switch (phase) {
      SpeechPhase.starting || SpeechPhase.recording => (
        l10n.voiceHoldToSend,
        l10n.voiceRecordSemantics,
      ),
      SpeechPhase.cancelling => (
        l10n.voiceReleaseToCancel,
        l10n.voiceRecordSemantics,
      ),
      SpeechPhase.transcribing => (
        l10n.voiceRecognizing,
        l10n.voiceRecognizingSemantics,
      ),
      SpeechPhase.idle ||
      SpeechPhase.loading ||
      SpeechPhase.playing => (null, null),
    };
    if (text == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Semantics(
        key: const Key('recording-overlay'),
        liveRegion: true,
        label: semanticsLabel,
        child: ExcludeSemantics(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 44),
            color: colors.primary,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                height: 20 / 15,
                fontWeight: FontWeight.w500,
                color: colors.primaryForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
