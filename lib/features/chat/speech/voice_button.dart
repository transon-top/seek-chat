import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';

/// ZH
/// 取消阈值：以按下瞬间的全局 Y 为基准，上滑 ≥80dp 进入取消态
/// （`speech.md` §3.2）。纯函数，便于单测。
///
/// EN
/// Cancel threshold: global Y at press time is the baseline; slide up ≥80dp to enter
/// the cancel state (`speech.md` §3.2). Pure function, easy to unit test.
bool shouldCancelVoice({
  required double startY,
  required double currentY,
  double threshold = 80,
}) => startY - currentY >= threshold;

/// ZH
/// 输入区的语音按钮：`Listener` 按住说话 + 语义 tap 切换与「取消录音」动作
/// （`speech.md` §2.1、§3.2；ui.md §5.8）。
///
/// 录音与识别期间按钮被浮层覆盖，但保留在语义树里，读屏用户可结束或取消。
///
/// EN
/// Composer voice button: `Listener` hold-to-talk, semantic tap toggle, and "cancel
/// recording" action (`speech.md` §2.1, §3.2; ui.md §5.8).
///
/// Covered by the overlay while recording; it stays in semantics so screen readers can end or cancel.
class VoiceButton extends StatefulWidget {
  const VoiceButton({
    super.key,
    required this.phase,
    required this.enabled,
    required this.onStart,
    required this.onEnd,
    required this.onGestureCancel,
    required this.onCancelArmedChanged,
    required this.onCancelRecording,
  });

  final SpeechPhase phase;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onGestureCancel;
  final ValueChanged<bool> onCancelArmedChanged;
  final VoidCallback onCancelRecording;

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton> {
  int? _pointer;
  double _startY = 0;
  bool _armed = false;

  bool get _cancelable => widget.phase.voiceCancelable;

  String _label(AppLocalizations l10n) => switch (widget.phase) {
    SpeechPhase.starting ||
    SpeechPhase.recording ||
    SpeechPhase.cancelling => l10n.voiceRecordSemantics,
    SpeechPhase.transcribing => l10n.voiceRecognizingSemantics,
    SpeechPhase.idle ||
    SpeechPhase.loading ||
    SpeechPhase.playing => l10n.holdToTalk,
  };

  void _handleSemanticTap() {
    if (widget.phase == SpeechPhase.idle) {
      if (widget.enabled) widget.onStart();
      return;
    }
    if (_cancelable) widget.onEnd();
  }

  void _handleDown(PointerDownEvent event) {
    if (_pointer != null ||
        widget.phase != SpeechPhase.idle ||
        !widget.enabled) {
      return;
    }
    _pointer = event.pointer;
    _startY = event.position.dy;
    _armed = false;
    widget.onStart();
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final armed = shouldCancelVoice(
      startY: _startY,
      currentY: event.position.dy,
    );
    if (armed == _armed) return;
    _armed = armed;
    unawaited(
      armed ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact(),
    );
    widget.onCancelArmedChanged(armed);
  }

  void _handleUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _armed = false;
    widget.onEnd();
  }

  void _handleCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _armed = false;
    widget.onGestureCancel();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final label = _label(l10n);
    final interactive = widget.enabled || _cancelable;
    return Semantics(
      key: const Key('voice-button'),
      button: true,
      enabled: interactive,
      label: label,
      onTap: interactive ? _handleSemanticTap : null,
      customSemanticsActions: _cancelable
          ? {
              CustomSemanticsAction(label: l10n.voiceCancelRecording):
                  widget.onCancelRecording,
            }
          : null,
      child: Tooltip(
        message: label,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handleDown,
          onPointerMove: _handleMove,
          onPointerUp: _handleUp,
          onPointerCancel: _handleCancel,
          // ZH
          // 视觉 20 描边圆，点击区保持 40（参照官方 app）。
          //
          // EN
          // 20dp outline circle visually, 40dp tap target (matching the official app).
          child: SizedBox(
            width: 40,
            height: 40,
            child: Opacity(
              opacity: interactive ? 1 : 0.4,
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
                  _VoiceWaveIcon(color: colors.foreground),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 官方 app 的语音图标：左侧圆点 + 右侧两道声波弧。
///
/// EN
/// Official app voice icon: a dot on the left plus two sound-wave arcs on the right.
class _VoiceWaveIcon extends StatelessWidget {
  const _VoiceWaveIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(12, 12), painter: _VoiceWavePainter(color));
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.30, size.height / 2);
    canvas.drawCircle(center, 1.4, Paint()..color = color);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final radius in const [3.4, 6.4]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -0.9,
        1.8,
        false,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_VoiceWavePainter oldDelegate) =>
      oldDelegate.color != color;
}
