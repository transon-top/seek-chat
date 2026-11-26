import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/prefs/font_scale_store.dart';
import 'settings_widgets.dart';

/// ZH
/// 字体大小页：预览、说明与底部固定卡片（跟随系统开关 + 七档滑杆，`ui.md` §3.5）。
///
/// EN
/// Text size page: preview, description and a pinned card (follow-system switch plus
/// a seven-step slider, `ui.md` §3.5).
class FontSizeSettingsPage extends ConsumerWidget {
  const FontSizeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final palette = SettingsPalette.of(context);
    final settings = ref.watch(fontScaleProvider);
    // ZH
    // 跟随时 thumb 停在系统字号最近的档位；手动档位直接使用所选档位。
    //
    // EN
    // In follow mode the thumb snaps to the nearest system scale; manual mode uses the chosen step.
    final scaler = MediaQuery.textScalerOf(context);
    final level = settings.followSystem
        ? FontScaleLevels.nearest(
            scaler.scale(_referenceFontSize) / _referenceFontSize,
          )
        : settings.level;
    final notifier = ref.read(fontScaleProvider.notifier);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SettingsScaffold(
      title: l10n.settingsFontSize,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: settingsMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: palette.button,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            l10n.settingsFontSizePreview,
                            style: TextStyle(
                              fontSize: 17,
                              height: 24 / 17,
                              color: colors.foreground,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Text(
                        l10n.settingsFontSizeDescription,
                        style: TextStyle(
                          fontSize: 16,
                          height: 26 / 16,
                          color: colors.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: settingsMaxWidth),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.settingsFontSizeSystem,
                              style: TextStyle(
                                fontSize: 15,
                                height: 20 / 15,
                                color: colors.foreground,
                              ),
                            ),
                          ),
                          ShadSwitch(
                            key: const Key('settings-font-follow'),
                            value: settings.followSystem,
                            onChanged: notifier.setFollowSystem,
                            width: 51,
                            height: 31,
                            margin: 3,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ExcludeSemantics(
                        child: Row(
                          children: [
                            Text(
                              'A',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1,
                                color: colors.foreground,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              l10n.settingsFontSizeStandard,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1,
                                fontWeight: FontWeight.w500,
                                color: colors.foreground,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'A',
                              style: TextStyle(
                                fontSize: 21,
                                height: 1,
                                color: colors.foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FontScaleSlider(
                        key: const Key('settings-font-slider'),
                        level: level,
                        valueLabel: _fontLevelName(l10n, level),
                        increasedValue:
                            level < FontScaleLevels.values.length - 1
                            ? _fontLevelName(l10n, level + 1)
                            : null,
                        decreasedValue: level > 0
                            ? _fontLevelName(l10n, level - 1)
                            : null,
                        onChanged: notifier.selectLevel,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ZH
/// 以正文 16px 为参照换算系统字号倍率，非线性缩放也能映射到最近档位。
///
/// EN
/// Map the system scale against a 16px body reference, even non-linear scales snap to a step.
const _referenceFontSize = 16.0;

String _fontLevelName(AppLocalizations l10n, int level) => switch (level) {
  0 => l10n.settingsFontSizeSmallest,
  1 => l10n.settingsFontSizeSmall,
  2 => l10n.settingsFontSizeMedium,
  3 => l10n.settingsFontSizeStandard,
  4 => l10n.settingsFontSizeLarge,
  5 => l10n.settingsFontSizeLarger,
  _ => l10n.settingsFontSizeLargest,
};

/// ZH
/// 七档滑杆：点击/拖动吸附到最近刻度，跨档触发一次触觉反馈。
///
/// 轨道两端各内缩半个 thumb，使 7 个刻度都落在 thumb 圆心可到达的位置。
///
/// EN
/// Seven-step slider: taps and drags snap to the nearest tick; crossing a step gives haptics.
///
/// The track insets half a thumb on both ends so all seven ticks reach the thumb center.
class _FontScaleSlider extends StatefulWidget {
  const _FontScaleSlider({
    super.key,
    required this.level,
    required this.valueLabel,
    required this.increasedValue,
    required this.decreasedValue,
    required this.onChanged,
  });

  final int level;
  final String valueLabel;
  final String? increasedValue;
  final String? decreasedValue;
  final ValueChanged<int> onChanged;

  @override
  State<_FontScaleSlider> createState() => _FontScaleSliderState();
}

class _FontScaleSliderState extends State<_FontScaleSlider> {
  static const _thumbSize = 26.0;

  /// ZH
  /// 触摸区保持 44；thumb 视觉上小于触摸区。
  ///
  /// EN
  /// The touch target stays 44; the thumb is visually smaller than the touch area.
  static const _touchHeight = 44.0;
  static const _trackHeight = 2.0;
  static const _tickHeight = 12.0;

  int _levelAt(double dx, double width) {
    final span = width - _thumbSize;
    if (span <= 0) return widget.level;
    final ratio = ((dx - _thumbSize / 2) / span).clamp(0.0, 1.0);
    return (ratio * (FontScaleLevels.values.length - 1)).round();
  }

  void _select(int level) {
    if (level == widget.level) return;
    HapticFeedback.selectionClick();
    widget.onChanged(level);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final last = FontScaleLevels.values.length - 1;
    return Semantics(
      slider: true,
      label: l10n.settingsFontSize,
      value: widget.valueLabel,
      increasedValue: widget.increasedValue,
      decreasedValue: widget.decreasedValue,
      onIncrease: widget.level < last ? () => _select(widget.level + 1) : null,
      onDecrease: widget.level > 0 ? () => _select(widget.level - 1) : null,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final span = width - _thumbSize;
            final ratio = widget.level / last;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _select(_levelAt(details.localPosition.dx, width)),
              onHorizontalDragStart: (details) =>
                  _select(_levelAt(details.localPosition.dx, width)),
              onHorizontalDragUpdate: (details) =>
                  _select(_levelAt(details.localPosition.dx, width)),
              child: SizedBox(
                height: _touchHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: _thumbSize / 2,
                      right: _thumbSize / 2,
                      top: (_touchHeight - _trackHeight) / 2,
                      child: Container(
                        height: _trackHeight,
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(_trackHeight / 2),
                        ),
                      ),
                    ),
                    for (var i = 0; i <= last; i++)
                      Positioned(
                        left: _thumbSize / 2 + span * i / last - 1,
                        top: (_touchHeight - _tickHeight) / 2,
                        child: Container(
                          key: Key('settings-font-tick-$i'),
                          width: 2,
                          height: _tickHeight,
                          color: colors.border,
                        ),
                      ),
                    Positioned(
                      left: span * ratio,
                      top: (_touchHeight - _thumbSize) / 2,
                      child: IgnorePointer(
                        child: Container(
                          width: _thumbSize,
                          height: _thumbSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // ZH
                            // 亮色白滑块靠阴影浮起；深色沿用高对比前景色。
                            //
                            // EN
                            // White thumb on shadow in light; high-contrast foreground in dark.
                            color: theme.brightness == Brightness.light
                                ? const Color(0xFFFFFFFF)
                                : colors.foreground,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
