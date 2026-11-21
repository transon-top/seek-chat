import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';
import 'voice_hotspot.dart';

/// 录音浮层（GLOSSARY: Recording Overlay）：贴底蓝色动态区域。
///
/// 蓝色上缘由 6 枚缓慢漂移、互相重叠的径向椭圆构成；高光锚定按住位置并随
/// 电平脉动；32 根波形随电平起伏（`ui.md` §5.8、`speech.md` §7）。
/// 录音、取消与识别共用同一效果，取消态只换文案不变色。
///
/// 不响应点击，文案为 liveRegion，只播报开始、取消与识别（`speech.md` §8）。
class RecordingOverlay extends ConsumerStatefulWidget {
  const RecordingOverlay({super.key, required this.phase, this.level = 0});

  final SpeechPhase phase;

  /// 最近一次电平 0..1；浮层内按约 30fps 平滑。
  final double level;

  @override
  ConsumerState<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends ConsumerState<RecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final GlobalKey _boxKey = GlobalKey();

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

  /// pointer 的全局坐标换算到浮层本地；首帧尚未布局时用默认位置。
  Offset? _localHotspot(Offset? global) {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (global == null || box == null || !box.hasSize) return null;
    return box.globalToLocal(global);
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
    final base = colors.primary;
    // 聊天专用色全部由 token 派生，不新增色表（ui.md §3.1）。
    final deep = Color.lerp(base, Colors.black, 0.16)!;
    final bright = Color.lerp(base, Colors.white, 0.45)!;
    final glow = Color.lerp(Colors.white, base, 0.3)!;
    final globalHotspot = ref.watch(voiceHotspotProvider);

    return SafeArea(
      top: false,
      child: IgnorePointer(
        child: Semantics(
          key: const Key('recording-overlay'),
          liveRegion: true,
          label: semanticsLabel,
          child: ExcludeSemantics(
            child: SizedBox.expand(
              key: _boxKey,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AuraPainter(
                        t: seconds,
                        level: level,
                        hotspot: _localHotspot(globalHotspot),
                        base: base,
                        deep: deep,
                        bright: bright,
                        glow: glow,
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
                          color: colors.primaryForeground,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _Waveform(
                        seconds: waveSeconds,
                        level: level,
                        skeleton: _skeleton,
                        color: colors.primaryForeground,
                      ),
                      const SizedBox(height: 44),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部蓝色团块：顶部全透明的长距离底色 + 漂移椭圆的并集 + 按住位置高光。
class _AuraPainter extends CustomPainter {
  const _AuraPainter({
    required this.t,
    required this.level,
    required this.hotspot,
    required this.base,
    required this.deep,
    required this.bright,
    required this.glow,
  });

  final double t;
  final double level;
  final Offset? hotspot;
  final Color base;
  final Color deep;
  final Color bright;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final volume = level.clamp(0.0, 1.0);
    // 团块漂移周期约 4–6s（ui.md §5.8）。
    final drift = t * 2.2;

    // 长距离底色：顶部全透明，避免出现水平分界线。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            base.withValues(alpha: 0),
            base.withValues(alpha: 0),
            base.withValues(alpha: 0.06),
            base.withValues(alpha: 0.16),
            base.withValues(alpha: 0.36),
            base.withValues(alpha: 0.62),
          ],
          stops: const [0, 0.16, 0.34, 0.52, 0.70, 0.88],
        ).createShader(rect),
    );

    // 按住位置归一化；读屏语义 tap 没有 pointer 时落在底部中间。
    final hot = hotspot == null
        ? const Offset(0.5, 0.78)
        : Offset(
            (hotspot!.dx / size.width).clamp(0.0, 1.0),
            (hotspot!.dy / size.height).clamp(0.0, 1.0),
          );

    // 漂移的团块：互相重叠形成不规则的蓝色上边缘与流动感。
    final blobs = [
      (
        0.18 + 0.03 * math.sin(drift * 0.53),
        0.56 + 0.03 * math.cos(drift * 0.41),
        0.86,
        0.40,
        0.50,
      ),
      (
        0.50 + 0.04 * math.sin(drift * 0.37 + 1.2),
        0.58 + 0.02 * math.cos(drift * 0.61),
        1.02,
        0.46,
        0.55,
      ),
      (
        0.82 + 0.03 * math.cos(drift * 0.47 + 0.4),
        0.56 + 0.03 * math.sin(drift * 0.33),
        0.84,
        0.40,
        0.50,
      ),
      (0.26 + 0.03 * math.sin(drift * 0.71 + 2.0), 0.78, 1.04, 0.56, 0.76),
      (0.76 + 0.03 * math.cos(drift * 0.59 + 1.7), 0.80, 0.98, 0.54, 0.72),
      (hot.dx, hot.dy, 0.70, 0.46, 0.36 + 0.30 * volume),
    ];
    for (final (x, y, w, h, alpha) in blobs) {
      final blob = Rect.fromCenter(
        center: Offset(size.width * x, size.height * y),
        width: size.width * w * (1 + 0.04 * math.sin(t * 0.9 + x * 9)),
        height: size.height * h * (1 + 0.04 * math.cos(t * 0.8 + y * 9)),
      );
      canvas.drawOval(
        blob,
        Paint()
          ..shader = RadialGradient(
            colors: [
              bright.withValues(alpha: alpha),
              base.withValues(alpha: alpha * 0.66),
              base.withValues(alpha: 0),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(blob),
      );
    }

    // 底部实心：从透明缓慢过渡到实色，确保输入卡被完全盖住且没有接缝。
    final solid = Rect.fromLTRB(0, size.height * 0.66, size.width, size.height);
    canvas.drawRect(
      solid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            deep.withValues(alpha: 0),
            deep.withValues(alpha: 0.92),
            deep,
            base,
          ],
          stops: const [0, 0.45, 0.7, 1],
        ).createShader(solid),
    );

    // 按住位置的高光，随音量脉动。
    final center = Offset(size.width * hot.dx, size.height * hot.dy);
    final radius = size.width * (0.34 + 0.03 * math.sin(t * 1.7));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glow.withValues(alpha: 0.10 + 0.30 * volume),
            bright.withValues(alpha: 0.06 + 0.16 * volume),
            base.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_AuraPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.level != level ||
      oldDelegate.hotspot != hotspot ||
      oldDelegate.base != base ||
      oldDelegate.deep != deep ||
      oldDelegate.bright != bright ||
      oldDelegate.glow != glow;
}

/// 32 根波形条：高 28、宽 2.4、左右各留 1.6；骨架态为低幅，冻结时不再起伏。
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
          for (var i = 0; i < 32; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.6),
              child: SizedBox(
                key: ValueKey('voice-wave-bar-$i'),
                width: 2.4,
                height: _height(i),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(2),
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
