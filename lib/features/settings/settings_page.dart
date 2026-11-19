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
import '../../shared/prefs/speech_store.dart';
import '../../shared/prefs/theme_store.dart';
import '../../shared/prefs/user_metadata_store.dart';
import '../../shared/speech/permissions.dart';

/// 打开系统设置底部 Sheet（`ui.md` §1.5）。
Future<void> showSettingsSheet(BuildContext context, {Widget? dataManagement}) {
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
      child: SettingsSheet(dataManagement: dataManagement),
    ),
  );
}

/// 设置内容：通用设置 / 数据管理两个视图，切换不离开 Sheet。
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, this.dataManagement});

  /// 数据管理层由 `app/` 注入，设置页不直接 import 其他功能目录。
  final Widget? dataManagement;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

enum _SettingsView { general, data }

class _SettingsSheetState extends State<SettingsSheet> {
  _SettingsView _view = _SettingsView.general;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    // Sheet 弹层不在 Material 路由内；透明 Material 供 InkWell / Divider 使用。
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
                    selected: _view == _SettingsView.general,
                    onTap: () => setState(() => _view = _SettingsView.general),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NavTab(
                    key: const Key('settings-nav-data'),
                    icon: LucideIcons.database,
                    label: l10n.settingsData,
                    selected: _view == _SettingsView.data,
                    onTap: () => setState(() => _view = _SettingsView.data),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                24,
                20,
                48 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _view == _SettingsView.general
                      ? const _GeneralSettings()
                      : _DataSettings(dataManagement: widget.dataManagement),
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

/// 通用设置：主题卡片、语言、朗读音色、位置信息（`ui.md` §1.5）。
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
        _LanguageRow(),
        const _RowDivider(),
        _TtsVoiceRow(),
        const _RowDivider(),
        const SizedBox(height: 32),
        _LocationSection(),
        const SizedBox(height: 24),
        const _SpeechSection(),
      ],
    );
  }
}

/// 语音：麦克风权限三态；从系统设置返回时刷新权限状态。
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

/// 主题：浅色 / 深色 两列，跟随系统整行（参考图）。
class _ThemeSection extends ConsumerWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final mode = ref.watch(themeModeProvider);
    void select(ThemeMode value) =>
        ref.read(themeModeProvider.notifier).setThemeMode(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
          ],
        ),
        const SizedBox(height: 8),
        _ThemeCard(
          key: const Key('settings-theme-system'),
          icon: LucideIcons.monitor,
          label: l10n.settingsThemeSystem,
          selected: mode == ThemeMode.system,
          onTap: () => select(ThemeMode.system),
        ),
      ],
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
          height: 88,
          decoration: BoxDecoration(
            color: selected ? colors.muted : colors.card,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
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

/// 语言行：右侧下拉胶囊，选项含「跟随系统」。
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

class _LocationSection extends ConsumerWidget {
  const _LocationSection();

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
        _SectionTitle(l10n.settingsLocation),
        const SizedBox(height: 20),
        if (metadata.systemChinese)
          Row(
            children: [
              Expanded(
                child: _SettingsSelect<String>(
                  key: const Key('settings-province'),
                  value: selected?.province ?? '',
                  displayText: province?.name,
                  placeholder: l10n.settingsProvincePlaceholder,
                  align: Alignment.bottomLeft,
                  fill: true,
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
              const SizedBox(width: 16),
              Expanded(
                child: _SettingsSelect<String>(
                  key: const Key('settings-city'),
                  value: selected?.city ?? '',
                  placeholder: l10n.settingsCityPlaceholder,
                  align: Alignment.bottomRight,
                  fill: true,
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
            ],
          )
        else
          _SettingsSelect<String>(
            key: const Key('settings-region'),
            value: location?.region ?? '',
            placeholder: l10n.settingsLocationNone,
            align: Alignment.bottomLeft,
            fill: true,
            options: _regionOptions(metadata.locale, l10n),
            onChanged: (value) => notifier.setLocation(
              value.isEmpty ? null : UserLocation(region: value),
            ),
          ),
        const SizedBox(height: 12),
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

/// 一行设置：左侧标签，右侧控件，行高 52。
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

/// 下拉胶囊 + 锚定弹层：选中项打勾，长列表在弹层内滚动。
class _SettingsSelect<T> extends StatefulWidget {
  const _SettingsSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.displayText,
    this.placeholder,
    this.align = Alignment.bottomRight,
    this.fill = false,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final String? displayText;
  final String? placeholder;
  final Alignment align;

  /// 铺满可用宽度并把箭头推到右端（位置信息胶囊）。
  final bool fill;

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
      style: TextStyle(
        fontSize: 13,
        height: 18 / 13,
        color: colors.foreground,
      ),
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
              mainAxisSize:
                  widget.fill ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (widget.fill)
                  Expanded(child: labelWidget)
                else
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

/// 数据管理：API Key 输入 + 导入 / 导出 / 删除全部（参考图）。
class _DataSettings extends StatelessWidget {
  const _DataSettings({required this.dataManagement});

  final Widget? dataManagement;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ApiKeyField(),
        if (dataManagement != null) ...[
          const SizedBox(height: 24),
          dataManagement!,
        ],
      ],
    );
  }
}

/// API Key 内联输入：提交（键盘完成）即校验并保存（票 10 / 20）。
class _ApiKeyField extends ConsumerStatefulWidget {
  const _ApiKeyField();

  @override
  ConsumerState<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends ConsumerState<_ApiKeyField> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _saved;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedKey();
  }

  Future<void> _loadSavedKey() async {
    final saved = await ref.read(apiKeyStoreProvider).read();
    if (!mounted || saved == null) return;
    setState(() {
      _saved = saved;
      _controller.text = saved;
    });
  }

  Future<void> _save(String text) async {
    final l10n = AppLocalizations.of(context)!;
    final apiKey = text.trim();
    if (apiKey.isEmpty) {
      setState(() => _error = l10n.errorApiKeyEmpty);
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
      setState(() => _saved = apiKey);
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
    _controller.clear();
    setState(() {
      _saved = null;
      _error = null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _saved == null ? l10n.settingsApiKeyPrompt : 'DeepSeek API Key',
          style: TextStyle(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: FontWeight.w500,
            color: colors.foreground,
          ),
        ),
        const SizedBox(height: 12),
        ShadInput(
          key: const Key('settings-api-key-input'),
          controller: _controller,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          placeholder: Text(l10n.settingsApiKeyPlaceholder),
          enabled: !_loading,
          onSubmitted: _save,
        ),
        if (_saved != null)
          Row(
            children: [
              Text(
                l10n.settingsApiKeySaved,
                style: TextStyle(
                  fontSize: 13,
                  height: 18 / 13,
                  color: colors.mutedForeground,
                ),
              ),
              const Spacer(),
              ShadButton.link(
                key: const Key('settings-clear-key'),
                onPressed: _loading ? null : _clear,
                child: Text(
                  l10n.settingsClearKey,
                  style: TextStyle(fontSize: 13, color: colors.destructive),
                ),
              ),
            ],
          ),
        if (error != null)
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
        if (_loading)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: colors.primary,
              backgroundColor: colors.muted,
            ),
          ),
      ],
    );
  }
}
