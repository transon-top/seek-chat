import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../shared/error_text.dart';
import '../../shared/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/api/errors.dart';
import '../../shared/models/location.dart';
import '../../shared/models/location_data.dart';
import '../../shared/models/types.dart';
import '../../shared/prefs/user_metadata_store.dart';

/// 最小设置页：填写并校验 DeepSeek API Key。界面规格见票 10 / 20。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedKey();
  }

  Future<void> _loadSavedKey() async {
    final saved = await ref.read(apiKeyStoreProvider).read();
    if (!mounted || saved == null) return;
    _controller.text = saved;
  }

  Future<void> _save() async {
    final strings = AppLocalizations.of(context)!;
    final apiKey = _controller.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _error = strings.errorApiKeyEmpty);
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
      Navigator.maybePop(context);
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
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _UserMetadataSection(),
          Text(
            'DeepSeek API Key',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: 'sk-...',
              border: OutlineInputBorder(),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存并校验'),
          ),
          TextButton(
            onPressed: _loading ? null : _clear,
            child: const Text('清除已保存的 Key'),
          ),
        ],
      ),
    );
  }
}

/// 语言与所在地：一起作为用户元信息写入 `latest_reminder`（`user-metadata.md`）。
///
/// 所在地选择器的形态跟随系统语言而不是应用语言；港澳台等固定名称由
/// `location_data.dart` 提供。
class _UserMetadataSection extends ConsumerWidget {
  const _UserMetadataSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final metadata = ref.watch(userMetadataProvider);
    final notifier = ref.read(userMetadataProvider.notifier);
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.settingsLanguage, style: titleStyle),
        DropdownButton<String>(
          key: const Key('settings-language'),
          isExpanded: true,
          value: metadata.locale,
          items: [
            DropdownMenuItem(value: 'zh', child: Text(l10n.settingsLanguageZh)),
            DropdownMenuItem(value: 'en', child: Text(l10n.settingsLanguageEn)),
          ],
          onChanged: (value) {
            if (value != null) notifier.setLocale(value);
          },
        ),
        const SizedBox(height: 12),
        Text(l10n.settingsLocation, style: titleStyle),
        if (metadata.systemChinese)
          _chineseLocation(l10n, metadata, notifier)
        else
          _regionSelect(l10n, metadata, notifier),
        const Divider(height: 32),
      ],
    );
  }

  /// 中文系统：省份 / 城市两级；「不指定」清空整个所在地。
  Widget _chineseLocation(
    AppLocalizations l10n,
    UserMetadata metadata,
    UserMetadataNotifier notifier,
  ) {
    final location = metadata.location;
    final selected = location?.region == 'CN' ? location : null;
    final province = provinceByCode(selected?.province);
    return Column(
      children: [
        DropdownButton<String>(
          key: const Key('settings-province'),
          isExpanded: true,
          value: selected?.province ?? '',
          items: [
            DropdownMenuItem(value: '', child: Text(l10n.settingsLocationNone)),
            for (final item in provinces)
              DropdownMenuItem(value: item.code, child: Text(item.name)),
          ],
          onChanged: (value) {
            if (value == null || value == selected?.province) return;
            notifier.setLocation(
              value.isEmpty
                  ? null
                  : UserLocation(region: 'CN', province: value),
            );
          },
        ),
        DropdownButton<String>(
          key: const Key('settings-city'),
          isExpanded: true,
          value: province == null ? '' : (selected?.city ?? ''),
          items: [
            DropdownMenuItem(value: '', child: Text(l10n.settingsLocationNone)),
            for (final city in province?.cities ?? const <City>[])
              DropdownMenuItem(value: city.code, child: Text(city.name)),
          ],
          onChanged: province == null
              ? null
              : (value) {
                  if (value == null || value == (selected?.city ?? '')) return;
                  notifier.setLocation(
                    UserLocation(
                      region: 'CN',
                      province: province.code,
                      city: value.isEmpty ? null : value,
                    ),
                  );
                },
        ),
      ],
    );
  }

  /// 非中文系统：单个国家 / 地区列表，名称按应用语言本地化。
  Widget _regionSelect(
    AppLocalizations l10n,
    UserMetadata metadata,
    UserMetadataNotifier notifier,
  ) {
    final options = [
      for (final code in regionCodes)
        (code: code, label: getRegionName(code, metadata.locale) ?? code),
    ]..sort((a, b) => a.label.compareTo(b.label));
    final current = metadata.location?.region ?? '';
    return DropdownButton<String>(
      key: const Key('settings-region'),
      isExpanded: true,
      value: current,
      items: [
        DropdownMenuItem(value: '', child: Text(l10n.settingsLocationNone)),
        for (final option in options)
          DropdownMenuItem(value: option.code, child: Text(option.label)),
      ],
      onChanged: (value) {
        if (value == null || value == current) return;
        notifier.setLocation(
          value.isEmpty ? null : UserLocation(region: value),
        );
      },
    );
  }
}
