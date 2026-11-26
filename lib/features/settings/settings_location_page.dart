import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/location.dart';
import '../../shared/models/location_data.dart';
import '../../shared/prefs/user_metadata_store.dart';
import 'settings_widgets.dart';

/// ZH
/// 位置信息页：中文系统按省 / 市两级，其他系统按国家 / 地区；
/// 说明文案在卡片下方。
///
/// EN
/// Location page: province / city on Chinese systems, country / region otherwise;
/// the description sits below the card.
class LocationSettingsPage extends ConsumerWidget {
  const LocationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final metadata = ref.watch(userMetadataProvider);
    final notifier = ref.read(userMetadataProvider.notifier);
    final location = metadata.location;
    final selected = location?.region == 'CN' ? location : null;
    final province = provinceByCode(selected?.province);
    return SettingsScaffold(
      title: l10n.settingsLocation,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          48 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: settingsMaxWidth),
            child: SettingsSection(
              title: l10n.settingsLocation,
              footer: Text(
                l10n.settingsLocationDescription,
                style: TextStyle(
                  fontSize: 13,
                  height: 18 / 13,
                  color: colors.mutedForeground,
                ),
              ),
              children: metadata.systemChinese
                  ? [
                      _LocationRow(
                        label: l10n.settingsProvince,
                        child: _SettingsSelect<String>(
                          key: const Key('settings-province'),
                          value: selected?.province ?? '',
                          displayText: province?.name,
                          placeholder: l10n.settingsProvincePlaceholder,
                          align: Alignment.bottomLeft,
                          options: [
                            ('', l10n.settingsLocationNone),
                            for (final item in provinces)
                              (item.code, item.name),
                          ],
                          onChanged: (value) => notifier.setLocation(
                            value.isEmpty
                                ? null
                                : UserLocation(region: 'CN', province: value),
                          ),
                        ),
                      ),
                      _LocationRow(
                        label: l10n.settingsCity,
                        child: _SettingsSelect<String>(
                          key: const Key('settings-city'),
                          value: selected?.city ?? '',
                          placeholder: l10n.settingsCityPlaceholder,
                          align: Alignment.bottomRight,
                          options: [
                            ('', l10n.settingsLocationNone),
                            for (final city
                                in province?.cities ?? const <City>[])
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
                    ]
                  : [
                      _LocationRow(
                        label: l10n.settingsRegion,
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
        ),
      ),
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
/// 位置设置行：左侧标签，右侧省份 / 城市 / 地区胶囊。
///
/// EN
/// Location row: label left, province / city / region pill right.
class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
            const SizedBox(width: 12),
            Flexible(child: child),
          ],
        ),
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
