import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import 'speech_controller.dart';

/// 助手消息操作条里的朗读按钮：空闲、加载扫光、播放起伏（`speech.md` §2.2）。
///
/// 启用与否由聊天页按 `canReadAloud` 与语音互斥判断；减少动画时竖条静止。
class ReadAloudButton extends StatefulWidget {
  const ReadAloudButton({
    super.key,
    required this.phase,
    required this.active,
    required this.enabled,
    required this.onPressed,
  });

  /// 全局语音阶段，用于区分 `loading` 与 `playing`。
  final SpeechPhase phase;

  /// 当前朗读的是这条回复。
  final bool active;

  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<ReadAloudButton> createState() => _ReadAloudButtonState();
}

class _ReadAloudButtonState extends State<ReadAloudButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _animate = true;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    _sync();
  }

  @override
  void didUpdateWidget(ReadAloudButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final running = widget.active && _animate;
    if (running && !_animation.isAnimating) {
      _animation.repeat();
    } else if (!running && _animation.isAnimating) {
      _animation.stop();
      _animation.value = 0;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final active = widget.active;
    return IconButton(
      key: const Key('read-aloud-button'),
      onPressed: widget.enabled ? widget.onPressed : null,
      tooltip: active ? l10n.ttsStop : l10n.ttsPlay,
      icon: active
          ? _ReadingBars(
              animation: _animation,
              playing: widget.phase == SpeechPhase.playing,
              animate: _animate,
            )
          : const Icon(Icons.volume_up),
    );
  }
}

class _ReadingBars extends StatelessWidget {
  const _ReadingBars({
    required this.animation,
    required this.playing,
    required this.animate,
  });

  static const _idleHeights = [8.0, 12.0, 10.0, 8.0];

  final Animation<double> animation;
  final bool playing;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 18,
      height: 18,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var index = 0; index < 4; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    width: 2.5,
                    height: _height(index),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _height(int index) {
    if (!animate) return _idleHeights[index];
    final t = animation.value;
    if (playing) {
      final wave = math.sin(2 * math.pi * (t + index * 0.15)).abs();
      return 5 + wave * 10;
    }
    // 加载态：一道扫光依次抬升每根竖条。
    final phase = (t * 4 - index) % 4;
    return phase < 1 ? 14.0 : 6.0;
  }
}
