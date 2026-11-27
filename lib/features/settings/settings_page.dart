import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/prefs/speech_store.dart';
import '../../shared/prefs/theme_store.dart';
import '../../shared/prefs/user_metadata_store.dart';
import '../../shared/speech/permissions.dart';
import 'settings_voice_sheet.dart';
import 'settings_widgets.dart';

/// ZH
/// 设置路由地址；`app/router.dart` 按同一组路径注册。
///
/// EN
/// Settings route paths; `app/router.dart` registers the same tree.
class SettingsRoutes {
  const SettingsRoutes._();

  static const root = '/settings';
  static const account = '$root/account';
  static const data = '$root/data';
  static const fontSize = '$root/font-size';
  static const location = '$root/location';

  /// ZH
  /// 无 Key 直达账户页并聚焦输入框的地址。
  ///
  /// EN
  /// Deep link to the account page with the key field focused.
  static const accountFocus = '$account?focus=1';
}

/// ZH
/// 设置根页：账户 / 应用 / 语音三组导航列表（官方布局）。
///
/// EN
/// Settings root: Account / App / Voice groups (official layout).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final metadata = ref.watch(userMetadataProvider);
    final themeMode = ref.watch(themeModeProvider);
    final voice = ref.watch(ttsVoiceProvider);
    return SettingsScaffold(
      title: l10n.settingsTitle,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          48 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: settingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsSection(
                  title: l10n.settingsSectionAccount,
                  children: [
                    SettingsRow(
                      key: const Key('settings-account'),
                      icon: LucideIcons.user,
                      label: l10n.settingsAccount,
                      onTap: () => context.push(SettingsRoutes.account),
                    ),
                    SettingsRow(
                      key: const Key('settings-data'),
                      icon: LucideIcons.database,
                      label: l10n.settingsData,
                      onTap: () => context.push(SettingsRoutes.data),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: l10n.settingsSectionApp,
                  children: [
                    SettingsRow(
                      key: const Key('settings-language'),
                      icon: LucideIcons.globe,
                      label: l10n.settingsLanguage,
                      value: _languageShort(l10n, metadata),
                      onTap: () => _pickLanguage(context, ref),
                    ),
                    SettingsRow(
                      key: const Key('settings-appearance'),
                      icon: LucideIcons.moonStar,
                      label: l10n.settingsAppearance,
                      value: _appearanceShort(l10n, themeMode),
                      onTap: () => _pickAppearance(context, ref),
                    ),
                    SettingsRow(
                      key: const Key('settings-font-size'),
                      icon: LucideIcons.aLargeSmall,
                      label: l10n.settingsFontSize,
                      onTap: () => context.push(SettingsRoutes.fontSize),
                    ),
                    SettingsRow(
                      key: const Key('settings-location'),
                      icon: LucideIcons.mapPin,
                      label: l10n.settingsLocation,
                      onTap: () => context.push(SettingsRoutes.location),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _VoiceSection(
                  voiceLabel: _voiceLabel(l10n, voice),
                  onPickVoice: () => showSettingsVoiceSheet(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _languageShort(AppLocalizations l10n, UserMetadata metadata) =>
      switch (metadata.languageChoice) {
        'zh' => l10n.settingsLanguageZh,
        'en' => l10n.settingsLanguageEn,
        _ => l10n.settingsLanguageSystem,
      };

  String _appearanceShort(AppLocalizations l10n, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.light => l10n.settingsThemeLight,
        ThemeMode.dark => l10n.settingsThemeDark,
        ThemeMode.system => l10n.settingsSystemShort,
      };

  String _voiceLabel(AppLocalizations l10n, TtsVoice voice) => switch (voice) {
    TtsVoice.stella => l10n.settingsTtsVoiceStella,
    TtsVoice.tide => l10n.settingsTtsVoiceTide,
  };

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.read(userMetadataProvider).languageChoice ?? 'system';
    final picked = await showSettingsChoiceDialog<String>(
      context,
      title: l10n.settingsLanguage,
      icon: LucideIcons.globe,
      selected: current,
      choices: [
        SettingsChoice('system', l10n.settingsLanguageSystem),
        SettingsChoice('zh', l10n.settingsLanguageZh),
        SettingsChoice('en', l10n.settingsLanguageEn),
      ],
    );
    if (picked == null) return;
    ref
        .read(userMetadataProvider.notifier)
        .setLocale(picked == 'system' ? null : picked);
  }

  Future<void> _pickAppearance(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showSettingsChoiceDialog<ThemeMode>(
      context,
      title: l10n.settingsAppearance,
      selected: ref.read(themeModeProvider),
      choices: [
        SettingsChoice(
          ThemeMode.system,
          l10n.settingsThemeSystem,
          key: const Key('settings-theme-system'),
        ),
        SettingsChoice(
          ThemeMode.light,
          l10n.settingsThemeLight,
          key: const Key('settings-theme-light'),
        ),
        SettingsChoice(
          ThemeMode.dark,
          l10n.settingsThemeDark,
          key: const Key('settings-theme-dark'),
        ),
      ],
    );
    if (picked == null) return;
    ref.read(themeModeProvider.notifier).setThemeMode(picked);
  }
}

/// ZH
/// 语音组：朗读音色与麦克风权限；从系统设置返回时刷新权限状态。
///
/// EN
/// Voice group: read-aloud voice and mic permission; refresh when returning from system settings.
class _VoiceSection extends ConsumerStatefulWidget {
  const _VoiceSection({required this.voiceLabel, required this.onPickVoice});

  final String voiceLabel;
  final VoidCallback onPickVoice;

  @override
  ConsumerState<_VoiceSection> createState() => _VoiceSectionState();
}

class _VoiceSectionState extends ConsumerState<_VoiceSection>
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
    final denied = status == MicrophoneStatus.denied;
    return SettingsSection(
      title: l10n.settingsSpeech,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (denied) ...[
            Material(
              color: SettingsPalette.of(context).button,
              borderRadius: BorderRadius.circular(999),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('settings-open-settings'),
                onTap: () =>
                    ref.read(microphonePermissionsProvider).openSettings(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 9,
                  ),
                  child: Text(
                    l10n.settingsOpenSystemSettings,
                    style: TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      color: colors.foreground,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            l10n.settingsSpeechDescription,
            style: TextStyle(
              fontSize: 13,
              height: 18 / 13,
              color: colors.mutedForeground,
            ),
          ),
        ],
      ),
      children: [
        SettingsRow(
          key: const Key('settings-tts-voice'),
          icon: LucideIcons.volume2,
          label: l10n.settingsTtsVoice,
          value: widget.voiceLabel,
          onTap: widget.onPickVoice,
        ),
        SettingsRow(
          key: const Key('settings-mic-permission'),
          icon: LucideIcons.mic,
          label: l10n.settingsMicPermission,
          value: switch (status) {
            MicrophoneStatus.granted => l10n.settingsMicGranted,
            MicrophoneStatus.denied => l10n.settingsMicDenied,
            MicrophoneStatus.notRequested ||
            null => l10n.settingsMicNotRequested,
          },
          valueKey: const Key('settings-mic-status'),
          onTap: denied
              ? () => ref.read(microphonePermissionsProvider).openSettings()
              : null,
        ),
      ],
    );
  }
}
