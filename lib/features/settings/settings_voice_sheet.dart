import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/prefs/speech_store.dart';
import 'settings_widgets.dart';

/// ZH
/// 打开朗读音色底部 Sheet：点选只改待提交值，「确认」才写入。
///
/// EN
/// Open the read-aloud voice sheet: tapping only changes the pending value; Confirm writes it.
Future<void> showSettingsVoiceSheet(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final palette = SettingsPalette.of(context);
  return showShadSheet<void>(
    context: context,
    builder: (_) => ShadSheet(
      constraints: BoxConstraints.tightFor(
        width: size.width,
        height: size.height * 0.6,
      ),
      backgroundColor: palette.background,
      padding: EdgeInsets.zero,
      radius: const BorderRadius.vertical(top: Radius.circular(24)),
      removeBorderRadiusWhenTiny: false,
      closeIcon: const SizedBox.shrink(),
      scrollable: false,
      child: const _VoiceSheet(),
    ),
  );
}

class _VoiceSheet extends ConsumerStatefulWidget {
  const _VoiceSheet();

  @override
  ConsumerState<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends ConsumerState<_VoiceSheet> {
  late TtsVoice _pending = ref.read(ttsVoiceProvider);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Stack(
              children: [
                Center(
                  child: Text(
                    l10n.settingsTtsVoice,
                    style: TextStyle(
                      fontSize: 17,
                      height: 24 / 17,
                      fontWeight: FontWeight.w600,
                      color: colors.foreground,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Material(
                      color: colors.muted,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const Key('settings-voice-close'),
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            LucideIcons.x,
                            size: 18,
                            color: colors.foreground,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _VoiceCard(
                    key: const Key('settings-voice-stella'),
                    label: l10n.settingsTtsVoiceStella,
                    selected: _pending == TtsVoice.stella,
                    onTap: () => setState(() => _pending = TtsVoice.stella),
                  ),
                  const SizedBox(height: 12),
                  _VoiceCard(
                    key: const Key('settings-voice-tide'),
                    label: l10n.settingsTtsVoiceTide,
                    selected: _pending == TtsVoice.tide,
                    onTap: () => setState(() => _pending = TtsVoice.tide),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
            child: SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                label: l10n.confirm,
                child: InkWell(
                  key: const Key('settings-voice-confirm'),
                  borderRadius: BorderRadius.circular(26),
                  onTap: () {
                    ref.read(ttsVoiceProvider.notifier).setVoice(_pending);
                    Navigator.of(context).maybePop();
                  },
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Text(
                      l10n.confirm,
                      style: TextStyle(
                        fontSize: 17,
                        height: 24 / 17,
                        fontWeight: FontWeight.w500,
                        color: colors.primaryForeground,
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

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
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
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final palette = SettingsPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 88,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            // ZH
            // 选中态用底色区分，不描边。
            //
            // EN
            // Selection is shown by fill color, not an outline.
            color: selected
                ? colors.primary.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.24 : 0.1,
                  )
                : palette.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: palette.background,
                child: Icon(
                  LucideIcons.audioLines,
                  size: 20,
                  color: colors.foreground,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    height: 22 / 16,
                    fontWeight: FontWeight.w500,
                    color: colors.foreground,
                  ),
                ),
              ),
              if (selected)
                Icon(LucideIcons.check, size: 20, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
