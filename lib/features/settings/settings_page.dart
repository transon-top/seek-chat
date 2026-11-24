import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../shared/error_text.dart';
import '../../shared/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/api/errors.dart';
import '../../shared/models/location.dart';
import '../../shared/models/location_data.dart';
import '../../shared/models/types.dart';
import '../../shared/prefs/font_scale_store.dart';
import '../../shared/prefs/speech_store.dart';
import '../../shared/prefs/theme_store.dart';
import '../../shared/prefs/user_metadata_store.dart';
import '../../shared/speech/permissions.dart';
import '../../shared/widgets/scroll_edge_fade.dart';

/// ZH
/// 打开系统设置底部 Sheet（`ui.md` §1.5）。
///
/// EN
/// Open the settings bottom sheet (`ui.md` §1.5).
Future<void> showSettingsSheet(
  BuildContext context, {
  Widget? dataManagement,
  SettingsView initialView = SettingsView.general,
  bool focusApiKey = false,
}) {
  final size = MediaQuery.sizeOf(context);
  return showShadSheet<void>(
    context: context,
    builder: (_) => ShadSheet(
      constraints: BoxConstraints.tightFor(
        width: size.width,
        height: size.height * 0.92,
      ),
      padding: EdgeInsets.zero,
      radius: const BorderRadius.vertical(top: Radius.circular(24)),
      removeBorderRadiusWhenTiny: false,
      closeIcon: const SizedBox.shrink(),
      scrollable: false,
      child: SettingsSheet(
        dataManagement: dataManagement,
        initialView: initialView,
        focusApiKey: focusApiKey,
      ),
    ),
  );
}

/// ZH
/// 设置内容：通用设置 / 数据管理两个视图，切换不离开 Sheet。
///
/// EN
/// Settings content: General and Data views, switching without leaving the sheet.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    this.dataManagement,
    this.initialView = SettingsView.general,
    this.focusApiKey = false,
  });

  /// ZH
  /// 数据管理层由 `app/` 注入，设置页不直接 import 其他功能目录。
  ///
  /// EN
  /// `app/` injects the data management layer; settings never imports other feature folders.
  final Widget? dataManagement;

  /// ZH
  /// 打开时停留的视图；Key Prompt 与「无 Key 点发送」直达数据管理。
  ///
  /// EN
  /// View shown on open; the Key Prompt and "send without a key" land on Data.
  final SettingsView initialView;

  /// ZH
  /// 首次挂载时聚焦 API Key 输入框。
  ///
  /// EN
  /// Focus the API Key field when first mounted.
  final bool focusApiKey;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

enum SettingsView { general, data }

class _SettingsSheetState extends State<SettingsSheet> {
  late SettingsView _view = widget.initialView;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    // ZH
    // Sheet 弹层不在 Material 路由内；透明 Material 供 InkWell / Divider 使用。
    //
    // EN
    // Sheets live outside Material routes; a transparent Material serves InkWell / Divider.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settingsTitle,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 26 / 20,
                      color: colors.foreground,
                    ),
                  ),
                ),
                ShadIconButton.ghost(
                  key: const Key('settings-close'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(LucideIcons.x, color: colors.foreground),
                  iconSize: 20,
                  width: 40,
                  height: 40,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _NavTab(
                    key: const Key('settings-nav-general'),
                    icon: LucideIcons.settings2,
                    label: l10n.settingsGeneral,
                    selected: _view == SettingsView.general,
                    onTap: () => setState(() => _view = SettingsView.general),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NavTab(
                    key: const Key('settings-nav-data'),
                    icon: LucideIcons.database,
                    label: l10n.settingsData,
                    selected: _view == SettingsView.data,
                    onTap: () => setState(() => _view = SettingsView.data),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ScrollEdgeFade(
              controller: _scroll,
              color: colors.background,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  20,
                  24,
                  20,
                  48 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: _view == SettingsView.general
                        ? const _GeneralSettings()
                        : _DataSettings(
                            dataManagement: widget.dataManagement,
                            focusApiKey: widget.focusApiKey,
                          ),
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

class _NavTab extends StatelessWidget {
  const _NavTab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: selected ? colors.muted : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? colors.foreground : colors.mutedForeground,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 20 / 15,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected
                        ? colors.foreground
                        : colors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 通用设置：主题卡片、语言、朗读音色、位置信息（`ui.md` §1.5）。
///
/// EN
/// General settings: theme cards, language, TTS voice, location (`ui.md` §1.5).
class _GeneralSettings extends ConsumerWidget {
  const _GeneralSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(l10n.settingsTheme),
        const SizedBox(height: 12),
        const _ThemeSection(),
        const SizedBox(height: 24),
        const _FontSizeSection(),
        const SizedBox(height: 24),
        _LanguageRow(),
        const _RowDivider(),
        _TtsVoiceRow(),
        const _RowDivider(),
        const _LocationRow(),
        const SizedBox(height: 24),
        const _SpeechSection(),
      ],
    );
  }
}

/// ZH
/// 语音：麦克风权限三态；从系统设置返回时刷新权限状态。
///
/// EN
/// Voice Input: three mic permission states; refresh when returning from system settings.
class _SpeechSection extends ConsumerStatefulWidget {
  const _SpeechSection();

  @override
  ConsumerState<_SpeechSection> createState() => _SpeechSectionState();
}

class _SpeechSectionState extends ConsumerState<_SpeechSection>
    with WidgetsBindingObserver {
  MicrophoneStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await ref.read(microphonePermissionsProvider).status();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final status = _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(l10n.settingsSpeech),
        _SettingRow(
          label: l10n.settingsMicPermission,
          trailing: Text(
            switch (status) {
              MicrophoneStatus.granted => l10n.settingsMicGranted,
              MicrophoneStatus.denied => l10n.settingsMicDenied,
              MicrophoneStatus.notRequested ||
              null => l10n.settingsMicNotRequested,
            },
            key: const Key('settings-mic-status'),
            style: TextStyle(
              fontSize: 13,
              height: 18 / 13,
              color: colors.mutedForeground,
            ),
          ),
        ),
        if (status == MicrophoneStatus.denied)
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              key: const Key('settings-open-settings'),
              onPressed: () =>
                  ref.read(microphonePermissionsProvider).openSettings(),
              child: Text(l10n.settingsOpenSystemSettings),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          l10n.settingsSpeechDescription,
          style: TextStyle(
            fontSize: 13,
            height: 18 / 13,
            color: colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        height: 20 / 15,
        fontWeight: FontWeight.w500,
        color: colors.foreground,
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Divider(height: 1, thickness: 1, color: colors.border);
  }
}

/// ZH
/// 主题：浅色 / 深色 / 跟随系统 三张等宽卡片一行，高度随内容撑开。
///
/// EN
/// Theme: three equal-width cards in a row (light / dark / system), height fits content.
class _ThemeSection extends ConsumerWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final mode = ref.watch(themeModeProvider);
    void select(ThemeMode value) =>
        ref.read(themeModeProvider.notifier).setThemeMode(value);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ThemeCard(
              key: const Key('settings-theme-light'),
              icon: LucideIcons.sun,
              label: l10n.settingsThemeLight,
              selected: mode == ThemeMode.light,
              onTap: () => select(ThemeMode.light),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ThemeCard(
              key: const Key('settings-theme-dark'),
              icon: LucideIcons.moon,
              label: l10n.settingsThemeDark,
              selected: mode == ThemeMode.dark,
              onTap: () => select(ThemeMode.dark),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ThemeCard(
              key: const Key('settings-theme-system'),
              icon: LucideIcons.monitor,
              label: l10n.settingsThemeSystem,
              selected: mode == ThemeMode.system,
              onTap: () => select(ThemeMode.system),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? colors.muted : colors.card,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: colors.foreground),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  height: 18 / 13,
                  color: colors.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 字体大小：跟随系统开关 + 七档滑杆（`ui.md` §3.5）。
///
/// EN
/// Font size: follow-system switch plus a seven-step slider (`ui.md` §3.5).
class _FontSizeSection extends ConsumerWidget {
  const _FontSizeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(l10n.settingsFontSize),
        const SizedBox(height: 12),
        _SettingRow(
          label: l10n.settingsFontSizeSystem,
          trailing: ShadSwitch(
            key: const Key('settings-font-follow'),
            value: settings.followSystem,
            onChanged: notifier.setFollowSystem,
            width: 51,
            height: 31,
            margin: 3,
          ),
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
          increasedValue: level < FontScaleLevels.values.length - 1
              ? _fontLevelName(l10n, level + 1)
              : null,
          decreasedValue: level > 0 ? _fontLevelName(l10n, level - 1) : null,
          onChanged: notifier.selectLevel,
        ),
      ],
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

/// ZH
/// 语言行：右侧下拉胶囊，选项含「跟随系统」。
///
/// EN
/// Language row: dropdown pill on the right, including "System default".
class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final metadata = ref.watch(userMetadataProvider);
    return _SettingRow(
      label: l10n.settingsLanguage,
      trailing: _SettingsSelect<String>(
        key: const Key('settings-language'),
        value: metadata.languageChoice ?? 'system',
        options: [
          ('system', l10n.settingsLanguageSystem),
          ('zh', l10n.settingsLanguageZh),
          ('en', l10n.settingsLanguageEn),
        ],
        onChanged: (value) => ref
            .read(userMetadataProvider.notifier)
            .setLocale(value == 'system' ? null : value),
      ),
    );
  }
}

class _TtsVoiceRow extends ConsumerWidget {
  const _TtsVoiceRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _SettingRow(
      label: l10n.settingsTtsVoice,
      trailing: _SettingsSelect<TtsVoice>(
        key: const Key('settings-tts-voice'),
        value: ref.watch(ttsVoiceProvider),
        options: [
          (TtsVoice.stella, l10n.settingsTtsVoiceStella),
          (TtsVoice.tide, l10n.settingsTtsVoiceTide),
        ],
        onChanged: (value) =>
            ref.read(ttsVoiceProvider.notifier).setVoice(value),
      ),
    );
  }
}

/// ZH
/// 位置信息：与语言 / 朗读音色同版式，左侧标签 + 右侧省份 / 城市胶囊；
/// 行下说明与语音区间距一致。
///
/// EN
/// Location: same layout as language / TTS voice, label left and province / city pills right;
/// the description below matches the Voice Input section spacing.
class _LocationRow extends ConsumerWidget {
  const _LocationRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final metadata = ref.watch(userMetadataProvider);
    final notifier = ref.read(userMetadataProvider.notifier);
    final location = metadata.location;
    final selected = location?.region == 'CN' ? location : null;
    final province = provinceByCode(selected?.province);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingRow(
          label: l10n.settingsLocation,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (metadata.systemChinese) ...[
                Flexible(
                  child: _SettingsSelect<String>(
                    key: const Key('settings-province'),
                    value: selected?.province ?? '',
                    displayText: province?.name,
                    placeholder: l10n.settingsProvincePlaceholder,
                    align: Alignment.bottomLeft,
                    options: [
                      ('', l10n.settingsLocationNone),
                      for (final item in provinces) (item.code, item.name),
                    ],
                    onChanged: (value) => notifier.setLocation(
                      value.isEmpty
                          ? null
                          : UserLocation(region: 'CN', province: value),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: _SettingsSelect<String>(
                    key: const Key('settings-city'),
                    value: selected?.city ?? '',
                    placeholder: l10n.settingsCityPlaceholder,
                    align: Alignment.bottomRight,
                    options: [
                      ('', l10n.settingsLocationNone),
                      for (final city in province?.cities ?? const <City>[])
                        (city.code, city.name),
                    ],
                    onChanged: province == null
                        ? (_) {}
                        : (value) => notifier.setLocation(
                            UserLocation(
                              region: 'CN',
                              province: province.code,
                              city: value.isEmpty ? null : value,
                            ),
                          ),
                  ),
                ),
              ] else
                Flexible(
                  child: _SettingsSelect<String>(
                    key: const Key('settings-region'),
                    value: location?.region ?? '',
                    placeholder: l10n.settingsLocationNone,
                    align: Alignment.bottomLeft,
                    options: _regionOptions(metadata.locale, l10n),
                    onChanged: (value) => notifier.setLocation(
                      value.isEmpty ? null : UserLocation(region: value),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.settingsLocationDescription,
          style: TextStyle(
            fontSize: 13,
            height: 18 / 13,
            color: colors.mutedForeground,
          ),
        ),
      ],
    );
  }

  List<(String, String)> _regionOptions(String locale, AppLocalizations l10n) {
    final options = [
      for (final code in regionCodes)
        (code, getRegionName(code, locale) ?? code),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [('', l10n.settingsLocationNone), ...options];
  }
}

/// ZH
/// 一行设置：左侧标签，右侧控件，行高 52。
///
/// EN
/// One settings row: label on the left, control on the right, height 52.
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                height: 20 / 15,
                color: colors.foreground,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// ZH
/// 下拉胶囊 + 锚定弹层：选中项打勾，长列表在弹层内滚动。
///
/// EN
/// Dropdown pill plus anchored popover: the selected item is checked; long lists scroll inside.
class _SettingsSelect<T> extends StatefulWidget {
  const _SettingsSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.displayText,
    this.placeholder,
    this.align = Alignment.bottomRight,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final String? displayText;
  final String? placeholder;
  final Alignment align;

  @override
  State<_SettingsSelect<T>> createState() => _SettingsSelectState<T>();
}

class _SettingsSelectState<T> extends State<_SettingsSelect<T>> {
  final _controller = ShadPopoverController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final matches = widget.options.where((option) => option.$1 == widget.value);
    final label = matches.isEmpty ? null : matches.first.$2;
    final text = widget.displayText ?? label ?? widget.placeholder ?? '';
    final labelWidget = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, height: 18 / 13, color: colors.foreground),
    );
    return ShadPopover(
      controller: _controller,
      anchor: ShadAnchorAuto(
        offset: const Offset(0, 6),
        targetAnchor: widget.align,
        followerAnchor: widget.align,
        fallback: ShadAnchorAuto(
          offset: const Offset(0, -6),
          targetAnchor: widget.align == Alignment.bottomLeft
              ? Alignment.topLeft
              : Alignment.topRight,
          followerAnchor: widget.align == Alignment.bottomLeft
              ? Alignment.bottomLeft
              : Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(6),
      decoration: ShadDecoration(
        border: ShadBorder.all(
          color: colors.border,
          radius: BorderRadius.circular(16),
        ),
      ),
      popover: (_) => SizedBox(
        width: 200,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: Scrollbar(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final option in widget.options)
                  _SelectOption(
                    label: option.$2,
                    selected: option.$1 == widget.value,
                    onTap: () {
                      _controller.hide();
                      widget.onChanged(option.$1);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      child: Semantics(
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _controller.toggle,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: colors.muted,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: labelWidget),
                const SizedBox(width: 6),
                Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectOption extends StatelessWidget {
  const _SelectOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 15,
                    height: 20 / 15,
                    color: colors.foreground,
                  ),
                ),
              ),
              if (selected)
                Icon(LucideIcons.check, size: 18, color: colors.foreground),
            ],
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 数据管理：API Key 输入 + 导入 / 导出 / 删除全部（参考图）。
///
/// API Key 表单状态由本组件持有：输入框与输入后出现的整行「确定」按钮共用
/// （参考 chat-demo 的 useApiKeyEditor）。
///
/// EN
/// Data management: API Key input plus import / export / delete all (reference layout).
///
/// This widget owns the API Key form state: the field and the full-width confirm button
/// that appears after typing share it (like chat-demo's useApiKeyEditor).
class _DataSettings extends ConsumerStatefulWidget {
  const _DataSettings({required this.dataManagement, this.focusApiKey = false});

  final Widget? dataManagement;
  final bool focusApiKey;

  @override
  ConsumerState<_DataSettings> createState() => _DataSettingsState();
}

/// ZH
/// API Key 输入：提交（键盘完成）或底部「确定」校验并保存（票 10 / 20）。
///
/// EN
/// API Key input: keyboard done or bottom confirm validates and saves (tickets 10 / 20).
class _DataSettingsState extends ConsumerState<_DataSettings> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  bool _editing = false;
  String? _saved;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    _loadSavedKey();
  }

  Future<void> _loadSavedKey() async {
    final saved = await ref.read(apiKeyStoreProvider).read();
    if (!mounted || saved == null) return;
    setState(() => _saved = saved);
  }

  /// ZH
  /// 修改时没输入就离开，回到已保存的掩码状态（参考 chat-demo）。
  ///
  /// EN
  /// Leaving editing with no input returns to the saved masked state (like chat-demo).
  void _handleFocusChange() {
    if (!mounted) return;
    final cancel =
        !_focusNode.hasFocus &&
        _saved != null &&
        _editing &&
        _controller.text.trim().isEmpty &&
        !_loading;
    setState(() => _editing = _editing && !cancel);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final apiKey = _controller.text.trim();
    if (apiKey.isEmpty || _loading) {
      if (apiKey.isEmpty) setState(() => _error = l10n.errorApiKeyEmpty);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).validateApiKey(apiKey);
      await ref.read(apiKeyStoreProvider).write(apiKey);
      if (!mounted) return;
      ref.invalidate(hasApiKeyProvider);
      _controller.clear();
      _focusNode.unfocus();
      setState(() {
        _saved = apiKey;
        _editing = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorText(
          AppLocalizations.of(context)!,
          error.condition,
          detail: error.message,
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorText(
          AppLocalizations.of(context)!,
          ApiErrorCondition.other,
          detail: error.toString(),
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    await ref.read(apiKeyStoreProvider).clear();
    if (!mounted) return;
    ref.invalidate(hasApiKeyProvider);
    _controller.clear();
    setState(() {
      _saved = null;
      _editing = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showInput = _saved == null || _editing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildApiKeyField(context),
        if (widget.dataManagement != null) ...[
          const SizedBox(height: 24),
          widget.dataManagement!,
        ],
        // ZH
        // 移动端：输入 Key 后在数据区下方显示整行「确定」（参考 chat-demo）。
        //
        // EN
        // Mobile: after typing a key, show a full-width confirm below the data section (like chat-demo).
        if (showInput)
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => value.text.trim().isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _buildConfirm(context),
                  ),
          ),
      ],
    );
  }

  Widget _buildApiKeyField(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final saved = _saved;
    final showInput = saved == null || _editing;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          saved == null ? l10n.settingsApiKeyPrompt : 'DeepSeek API Key',
          style: TextStyle(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: FontWeight.w500,
            color: colors.foreground,
          ),
        ),
        const SizedBox(height: 12),
        if (showInput)
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: _focusNode.hasFocus ? colors.primary : colors.border,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ShadInput(
                    key: const Key('settings-api-key-input'),
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: widget.focusApiKey || saved != null,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    style: TextStyle(
                      fontSize: 14,
                      height: 22 / 14,
                      color: colors.foreground,
                    ),
                    cursorColor: colors.primary,
                    onSubmitted: (_) => _save(),
                    padding: EdgeInsets.zero,
                    decoration: ShadDecoration.none,
                    placeholder: Text(
                      l10n.settingsApiKeyPlaceholder,
                      style: TextStyle(
                        fontSize: 14,
                        height: 22 / 14,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            height: 44,
            padding: const EdgeInsets.only(left: 16, right: 6),
            decoration: BoxDecoration(
              color: colors.muted,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '*' * saved.length,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 22 / 14,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
                _PillIconButton(
                  key: const Key('settings-edit-key'),
                  icon: LucideIcons.penLine,
                  color: colors.primary,
                  tooltip: l10n.edit,
                  onPressed: () => setState(() => _editing = true),
                ),
                _PillIconButton(
                  key: const Key('settings-clear-key'),
                  icon: LucideIcons.trash2,
                  color: colors.destructive,
                  tooltip: l10n.settingsClearKey,
                  onPressed: _loading ? null : _clear,
                ),
              ],
            ),
          ),
        if (showInput && error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              style: TextStyle(
                fontSize: 13,
                height: 18 / 13,
                color: colors.destructive,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildConfirm(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: l10n.settingsApiKeyConfirm,
      child: InkWell(
        key: const Key('settings-save-key'),
        borderRadius: BorderRadius.circular(26),
        onTap: _loading ? null : _save,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _loading
                ? colors.primary.withValues(alpha: 0.45)
                : colors.primary,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Text(
            _loading
                ? l10n.settingsApiKeyVerifying
                : l10n.settingsApiKeyConfirm,
            style: TextStyle(
              fontSize: 17,
              height: 24 / 17,
              fontWeight: FontWeight.w500,
              color: colors.primaryForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 已保存 Key 胶囊内的图标按钮。
///
/// EN
/// Icon button inside the saved-key pill.
class _PillIconButton extends StatelessWidget {
  const _PillIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
