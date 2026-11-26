import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/app_dialogs.dart';

/// ZH
/// 设置页内容最大宽度；宽屏居中，与旧设置 Sheet 一致。
///
/// EN
/// Max content width for settings pages; centered on wide screens, as before.
const settingsMaxWidth = 640.0;

/// ZH
/// 设置卡片的圆角；卡片内的行按下时水波纹沿用同一圆角。
///
/// EN
/// Corner radius of settings cards; rows reuse it for their press ink.
const settingsCardRadius = 14.0;

/// ZH
/// 设置页的三层颜色：偏灰背景、更亮的卡片、再亮一档的按钮；不使用描边。
///
/// EN
/// Three settings layers: gray background, brighter cards, brighter still buttons; no outlines.
class SettingsPalette {
  const SettingsPalette._({
    required this.background,
    required this.card,
    required this.button,
  });

  factory SettingsPalette.of(BuildContext context) {
    final dark = ShadTheme.of(context).brightness == Brightness.dark;
    return dark
        ? const SettingsPalette._(
            background: Color(0xFF0D0D0E),
            card: Color(0xFF242426),
            button: Color(0xFF38383A),
          )
        : const SettingsPalette._(
            background: Color(0xFFF2F3F5),
            card: Color(0xFFFFFFFF),
            button: Color(0xFFFFFFFF),
          );
  }

  final Color background;
  final Color card;
  final Color button;
}

/// ZH
/// 设置页外壳：圆形返回按钮、居中标题，内容区由页面自行滚动。
///
/// EN
/// Settings shell: circular back button and centered title; the page scrolls its own body.
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final palette = SettingsPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SettingsHeader(title: title),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                height: 24 / 17,
                fontWeight: FontWeight.w600,
                color: colors.foreground,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Semantics(
                button: true,
                label: MaterialLocalizations.of(context).backButtonTooltip,
                child: Material(
                  color: colors.muted,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const Key('settings-back'),
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        LucideIcons.chevronLeft,
                        size: 20,
                        color: colors.foreground,
                      ),
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

/// ZH
/// 分组：灰色小标题 + 圆角卡片；行之间不画分隔线。
///
/// EN
/// Group: muted caption above a rounded card; rows have no separators.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final palette = SettingsPalette.of(context);
    final footer = this.footer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              height: 18 / 13,
              color: colors.mutedForeground,
            ),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(settingsCardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: footer,
          ),
      ],
    );
  }
}

/// ZH
/// 一行设置：图标、标签、右侧当前值与箭头；有 [onTap] 才可点。
///
/// EN
/// One settings row: icon, label, current value and chevron; tappable only with [onTap].
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    required this.label,
    this.value,
    this.valueKey,
    this.onTap,
  });

  final IconData? icon;
  final String label;
  final String? value;

  /// ZH
  /// 右侧值文字的 key；测试用它读取状态文案。
  ///
  /// EN
  /// Key for the trailing value text; tests read the status copy through it.
  final Key? valueKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final icon = this.icon;
    final value = this.value;
    // ZH
    // 水波纹跟随卡片圆角，否则按下时在卡片四角露出直角。
    //
    // EN
    // The ink follows the card's corner radius; otherwise the press shows square corners.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(settingsCardRadius),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: colors.foreground),
                const SizedBox(width: 12),
              ],
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
              if (value != null) ...[
                const SizedBox(width: 12),
                // ZH
                // 固定上限而不是 Flexible：右侧值与箭头贴齐右边缘。
                //
                // EN
                // A fixed cap instead of Flexible: the value and chevron pin to the right edge.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    value,
                    key: valueKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      color: colors.mutedForeground,
                    ),
                  ),
                ),
              ],
              // ZH
              // 箭头槽位固定保留：无箭头时右侧值仍与其它行对齐。
              //
              // EN
              // The chevron slot is always reserved so trailing values align across rows.
              if (value != null || onTap != null) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 16,
                  child: onTap == null
                      ? null
                      : Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: colors.mutedForeground,
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 单选项：值、显示文案与可选控件 key（测试用）。
///
/// EN
/// One choice: value, label and an optional widget key for tests.
class SettingsChoice<T> {
  const SettingsChoice(this.value, this.label, {this.key});

  final T value;
  final String label;
  final Key? key;
}

/// ZH
/// 居中单选弹窗：点「确认」才提交，点遮罩或返回键取消。
///
/// EN
/// Centered radio dialog: only Confirm commits; tapping the barrier or back cancels.
Future<T?> showSettingsChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<SettingsChoice<T>> choices,
  required T selected,
  IconData? icon,
}) {
  final theme = ShadTheme.of(context);
  final palette = SettingsPalette.of(context);
  final width = math.min(360.0, MediaQuery.sizeOf(context).width - 48);
  return showShadDialog<T>(
    context: context,
    barrierColor: appDialogBarrierColor(context),
    builder: (context) => ShadTheme(
      data: theme,
      child: _SettingsChoiceDialog<T>(
        title: title,
        icon: icon,
        choices: choices,
        selected: selected,
        width: width,
        backgroundColor: palette.card,
        borderColor: const Color(0x00000000),
      ),
    ),
  );
}

class _SettingsChoiceDialog<T> extends StatefulWidget {
  const _SettingsChoiceDialog({
    required this.title,
    required this.icon,
    required this.choices,
    required this.selected,
    required this.width,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String title;
  final IconData? icon;
  final List<SettingsChoice<T>> choices;
  final T selected;
  final double width;
  final Color backgroundColor;
  final Color borderColor;

  @override
  State<_SettingsChoiceDialog<T>> createState() =>
      _SettingsChoiceDialogState<T>();
}

class _SettingsChoiceDialogState<T> extends State<_SettingsChoiceDialog<T>> {
  late T _pending = widget.selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final icon = widget.icon;
    final divider = Divider(height: 1, thickness: 1, color: colors.border);
    return ShadDialog(
      constraints: BoxConstraints(
        minWidth: widget.width,
        maxWidth: widget.width,
      ),
      padding: EdgeInsets.zero,
      radius: BorderRadius.circular(24),
      removeBorderRadiusWhenTiny: false,
      backgroundColor: widget.backgroundColor,
      border: Border.all(color: widget.borderColor),
      shadows: appOverlayShadows,
      closeIcon: const SizedBox.shrink(),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Icon(icon, size: 26, color: colors.foreground),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, icon == null ? 20 : 12, 20, 20),
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 16,
                  height: 22 / 16,
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                ),
              ),
            ),
            divider,
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final choice in widget.choices)
                    _ChoiceRow(
                      key: choice.key,
                      label: choice.label,
                      selected: choice.value == _pending,
                      onTap: () => setState(() => _pending = choice.value),
                    ),
                ],
              ),
            ),
            divider,
            InkWell(
              key: const Key('settings-choice-confirm'),
              onTap: () => Navigator.of(context).pop(_pending),
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    l10n.confirm,
                    style: TextStyle(
                      fontSize: 16,
                      height: 22 / 16,
                      fontWeight: FontWeight.w500,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
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
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _RadioDot(selected: selected),
                const SizedBox(width: 14),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 单选圆点：细外环加大实心圆，对齐官方弹窗的比例。
///
/// EN
/// Radio dot: thin outer ring with a larger filled center, matching the official dialog.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          width: 1.5,
          color: selected ? colors.foreground : colors.mutedForeground,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.foreground,
                ),
              ),
            )
          : null,
    );
  }
}
