import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';

/// 录音浮层（GLOSSARY: Recording Overlay）：贴底渐变 + 文案 + 波形。
///
/// 参照 DeepSeek 官方输入区：蓝色渐变自屏高约 62% 起淡入、底部为主色；
/// 取消态整片转红，文案与波形同步变红。32 → 40 根细波形随电平起伏
/// （`ui.md` §5.8、`speech.md` §7）。
///
/// 不响应点击，文案为 liveRegion，只播报开始、取消与识别（`speech.md` §8）。
class RecordingOverlay extends StatefulWidget {
  const RecordingOverlay({super.key, required this.phase, this.level = 0});

  final SpeechPhase phase;

  /// 最近一次电平 0..1；浮层内按约 30fps 平滑。
  final double level;

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  double _seconds = 0;
  double _shownLevel = 0;
  double _lastFrame = 0;
  bool? _reducedMotion;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    if (reduced) {
      _ticker.stop();
    } else {
      // 重启后 Ticker 的 elapsed 归零，帧闸门也随之重置。
      _lastFrame = 0;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    // 约 30fps 刷新；阈值略小于 1/30，避免 60Hz 下隔帧被浮点误差吞掉。
    if (seconds - _lastFrame < 0.03) return;
    _lastFrame = seconds;
    setState(() {
      _seconds = seconds;
      _shownLevel += (_targetLevel - _shownLevel) * 0.35;
    });
  }

  /// 启动与识别中没有电平输入，波形退回低幅骨架。
  bool get _skeleton =>
      widget.phase == SpeechPhase.starting ||
      widget.phase == SpeechPhase.transcribing;

  double get _targetLevel => switch (widget.phase) {
    SpeechPhase.recording ||
    SpeechPhase.cancelling => widget.level.clamp(0.0, 1.0),
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (text, semanticsLabel) = switch (widget.phase) {
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

    final reduced = MediaQuery.of(context).disableAnimations;
    final seconds = reduced ? 0.0 : _seconds;
    // 减少动画时冻结为有代表性的静态帧。
    final level = reduced ? (_skeleton ? 0.16 : 0.4) : _shownLevel;
    // 录音尚未开始时骨架不随 ticker 起伏。
    final waveSeconds = widget.phase == SpeechPhase.starting ? 0.0 : seconds;
    final colors = ShadTheme.of(context).colorScheme;
    final cancelling = widget.phase == SpeechPhase.cancelling;
    final base = cancelling ? colors.destructive : colors.primary;
    // 官方取消态文案为珊瑚红；把错误色提亮，深浅主题都保持可读。
    final foreground = cancelling
        ? Color.lerp(colors.destructive, Colors.white, 0.35)!
        : colors.primaryForeground;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return IgnorePointer(
      child: Semantics(
        key: const Key('recording-overlay'),
        liveRegion: true,
        label: semanticsLabel,
        child: ExcludeSemantics(
          child: SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OverlayGradientPainter(
                      base: base,
                      cancelling: cancelling,
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 20 / 15,
                        fontWeight: FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 42),
                    _Waveform(
                      seconds: waveSeconds,
                      level: level,
                      skeleton: _skeleton,
                      color: foreground,
                    ),
                    SizedBox(height: 72 + safeBottom),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 官方同款贴底渐变：顶部全透明，平滑过渡到底部主色 / 取消红。
///
/// 浮层槽高约 60% 屏高，stops 以槽高为分母；取消态透明度约为录音态一半。
class _OverlayGradientPainter extends CustomPainter {
  const _OverlayGradientPainter({
    required this.base,
    required this.cancelling,
  });

  final Color base;
  final bool cancelling;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final alphas = cancelling
        ? const [0.0, 0.0, 0.03, 0.15, 0.27, 0.32]
        : const [0.0, 0.0, 0.10, 0.39, 0.56, 0.64];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [for (final alpha in alphas) base.withValues(alpha: alpha)],
          stops: const [0, 0.36, 0.52, 0.65, 0.78, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_OverlayGradientPainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.cancelling != cancelling;
}

/// 40 根波形条：高 28、宽 2、左右各留 1.8；骨架态为低幅，冻结时不再起伏。
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.seconds,
    required this.level,
    required this.skeleton,
    required this.color,
  });

  final double seconds;
  final double level;
  final bool skeleton;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 40; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.8),
              child: SizedBox(
                key: ValueKey('voice-wave-bar-$i'),
                width: 2,
                height: _height(i),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _height(int i) {
    if (skeleton) {
      return 3 + 2.5 * (0.5 + 0.5 * math.sin(seconds * 2.2 + i * 0.5));
    }
    final flutter = 0.5 + 0.5 * math.sin(seconds * 6.1 + i * 0.55);
    final pulse = 0.5 + 0.5 * math.sin(seconds * 2.3 + i * 0.55 * 1.7);
    final drift = 0.5 + 0.5 * math.sin(seconds * 0.9 + i * 0.21);
    final mix = flutter * pulse * 0.78 + drift * 0.22;
    return 4 + 24 * (mix * level).clamp(0.0, 1.0);
  }
}
