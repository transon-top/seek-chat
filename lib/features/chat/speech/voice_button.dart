import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';
import 'voice_hotspot.dart';

/// 取消阈值：以按下瞬间的全局 Y 为基准，上滑 ≥80dp 进入取消态
/// （`speech.md` §3.2）。纯函数，便于单测。
bool shouldCancelVoice({
  required double startY,
  required double currentY,
  double threshold = 80,
}) => startY - currentY >= threshold;

/// 输入区的语音按钮：`Listener` 按住说话 + 语义 tap 切换与「取消录音」动作
/// （`speech.md` §2.1、§3.2；ui.md §5.8）。
///
/// 录音与识别期间按钮被浮层覆盖，但保留在语义树里，读屏用户可结束或取消。
class VoiceButton extends ConsumerStatefulWidget {
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
  ConsumerState<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends ConsumerState<VoiceButton> {
  late final VoiceHotspot _hotspot = ref.read(voiceHotspotProvider.notifier);
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
    _hotspot.set(event.position);
    widget.onStart();
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _hotspot.set(event.position);
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

  void _releaseHotspot() => _hotspot.set(null);

  void _handleUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _armed = false;
    _releaseHotspot();
    widget.onEnd();
  }

  void _handleCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _armed = false;
    _releaseHotspot();
    widget.onGestureCancel();
  }

  @override
  void dispose() {
    if (_pointer != null) _releaseHotspot();
    super.dispose();
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
          child: SizedBox(
            width: 40,
            height: 40,
            child: Opacity(
              opacity: interactive ? 1 : 0.4,
              child: Icon(
                LucideIcons.mic,
                size: 18,
                color: colors.mutedForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
