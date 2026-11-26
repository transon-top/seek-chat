import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/api/errors.dart';
import '../../shared/error_text.dart';
import '../../shared/models/types.dart';
import '../../shared/providers.dart';
import 'settings_widgets.dart';

/// ZH
/// 账户管理：API Key 的录入、校验、保存与清除（原「数据管理」上半部分）。
///
/// EN
/// Account: enter, validate, save and clear the API Key (formerly the top of Data).
class AccountSettingsPage extends ConsumerStatefulWidget {
  const AccountSettingsPage({super.key, this.focusApiKey = false});

  /// ZH
  /// 首次挂载时聚焦 API Key 输入框；无 Key 提示条直达时使用。
  ///
  /// EN
  /// Focus the API Key field on first mount; used by the Key Prompt deep link.
  final bool focusApiKey;

  @override
  ConsumerState<AccountSettingsPage> createState() =>
      _AccountSettingsPageState();
}

class _AccountSettingsPageState extends ConsumerState<AccountSettingsPage> {
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
    final l10n = AppLocalizations.of(context)!;
    final palette = SettingsPalette.of(context);
    final showInput = _saved == null || _editing;
    return SettingsScaffold(
      title: l10n.settingsAccount,
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
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildApiKeyField(context),
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
              ),
            ),
          ),
        ),
      ),
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
