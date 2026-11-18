/// 票 20「设置、语言与数据管理界面原型」入口。
///
/// 运行：`flutter run -t prototype/settings/main.dart -d <设备>`
///
/// 一次性粗原型：数据全假，没有数据库、网络或真实权限；只回答设置页的结构、
/// 交互与四组合观感。生产实现按票 10 的界面规格另做。
///
/// 截图参数：
/// `--dart-define=PROTOTYPE_LANG=en --dart-define=PROTOTYPE_DARK=true`
/// `--dart-define=PROTOTYPE_STATE=location|import-confirm|import-failed|delete-confirm|key`
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../theme.dart';
import 'strings.dart';

const _initialLanguage = String.fromEnvironment(
  'PROTOTYPE_LANG',
  defaultValue: 'zh',
);
const _initialDark = bool.fromEnvironment('PROTOTYPE_DARK');
const _initialSystem = String.fromEnvironment(
  'PROTOTYPE_SYSTEM',
  defaultValue: 'auto',
);
const _initialState = String.fromEnvironment('PROTOTYPE_STATE');

void main() => runApp(const SettingsPrototypeApp());

class SettingsPrototypeApp extends StatefulWidget {
  const SettingsPrototypeApp({
    super.key,
    this.initialLanguage = _initialLanguage,
    this.initialDark = _initialDark,
    this.initialSystemChinese,
    this.initialState = _initialState,
  });

  final String initialLanguage;
  final bool initialDark;
  final bool? initialSystemChinese;
  final String initialState;

  @override
  State<SettingsPrototypeApp> createState() => _SettingsPrototypeAppState();
}

class _SettingsPrototypeAppState extends State<SettingsPrototypeApp> {
  late bool _zh = widget.initialLanguage != 'en';
  late ThemeMode _themeMode = widget.initialDark
      ? ThemeMode.dark
      : ThemeMode.light;
  late bool _systemChinese =
      widget.initialSystemChinese ??
      switch (_initialSystem) {
        'zh' => true,
        'other' => false,
        _ =>
          WidgetsBinding.instance.platformDispatcher.locale.languageCode ==
              'zh',
      };

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'Settings 原型',
      debugShowCheckedModeBanner: false,
      theme: prototypeShadTheme(Brightness.light),
      darkTheme: prototypeShadTheme(Brightness.dark),
      themeMode: _themeMode,
      home: _SettingsPage(
        zh: _zh,
        themeMode: _themeMode,
        systemChinese: _systemChinese,
        initialState: widget.initialState,
        onLanguageChanged: (zh) => setState(() => _zh = zh),
        onThemeChanged: (mode) => setState(() => _themeMode = mode),
        onSystemChineseChanged: (value) =>
            setState(() => _systemChinese = value),
      ),
    );
  }
}

/// shadcn 的 sheet / dialog 路由不带 Material，InkWell 需要这层。
Widget _sheetBody(Widget child) =>
    Material(type: MaterialType.transparency, child: child);

class _Note {
  const _Note(this.text, {this.error = false});

  final String text;
  final bool error;
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.zh,
    required this.themeMode,
    required this.systemChinese,
    required this.initialState,
    required this.onLanguageChanged,
    required this.onThemeChanged,
    required this.onSystemChineseChanged,
  });

  final bool zh;
  final ThemeMode themeMode;
  final bool systemChinese;
  final String initialState;
  final ValueChanged<bool> onLanguageChanged;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<bool> onSystemChineseChanged;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  final _scroll = ScrollController();

  String? _apiKey = 'sk-demo-7f3a';
  bool _thinking = false;
  bool _search = false;
  String _voice = 'stella';
  String? _province;
  String? _city;
  String? _region;
  _Note? _importNote;
  _Note? _exportNote;
  bool _exportFails = false;

  late bool _systemChinese = widget.systemChinese;

  SettingsStrings get s => SettingsStrings(zh: widget.zh);

  String? get _locationLabel {
    if (_region != null) return _region;
    if (_province != null) {
      return _city == null ? _province : '$_province · $_city';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialState());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openInitialState() {
    switch (widget.initialState) {
      case 'location':
        unawaited(_showLocationSheet());
      case 'key':
        unawaited(_showKeyDialog());
      case 'import-confirm':
        unawaited(_confirmImport(prototypeFiles.first));
      case 'import-failed':
        setState(() {
          _importNote = _Note(s.importFailed, error: true);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      case 'delete-confirm':
        unawaited(_confirmDeleteAll());
    }
  }

  // ---------------------------------------------------------------- 账户

  Future<void> _showKeyDialog() async {
    final controller = TextEditingController(
      text: _apiKey == null ? '' : 'sk-demo-7f3a',
    );
    var loading = false;
    final saved = await showShadDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ShadDialog(
          title: const Text('DeepSeek API Key'),
          description: Text(s.apiKeyDialogDescription),
          actions: [
            ShadButton.outline(
              onPressed: loading ? null : () => Navigator.of(context).pop(),
              child: Text(s.cancel),
            ),
            ShadButton(
              key: const Key('key-save'),
              onPressed: loading
                  ? null
                  : () async {
                      setDialogState(() => loading = true);
                      await Future<void>.delayed(
                        const Duration(milliseconds: 700),
                      );
                      if (context.mounted) Navigator.of(context).pop(true);
                    },
              child: Text(loading ? s.verifying : s.apiKeyVerify),
            ),
          ],
          child: _sheetBody(
            ShadInput(
              key: const Key('key-input'),
              controller: controller,
              placeholder: const Text('sk-...'),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (saved == true && mounted) {
      setState(() => _apiKey = 'sk-demo-7f3a');
      _toast(s.apiKeyVerified);
    }
  }

  Future<void> _confirmClearKey() async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(s.clearKeyTitle),
        description: Text(s.clearKeyDescription),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          ShadButton.destructive(
            key: const Key('clear-key-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _apiKey = null);
    _toast(s.apiKeyMissing);
  }

  // ---------------------------------------------------------------- 选择器

  Future<void> _showLanguageSheet() async {
    await showShadSheet<void>(
      context: context,
      builder: (context) => ShadSheet(
        title: Text(s.language),
        description: Text(s.languageNote),
        child: _sheetBody(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OptionRow(
                key: const Key('language-zh'),
                label: s.languageZh,
                selected: widget.zh,
                onTap: () {
                  widget.onLanguageChanged(true);
                  Navigator.of(context).pop();
                },
              ),
              _OptionRow(
                key: const Key('language-en'),
                label: s.languageEn,
                selected: !widget.zh,
                onTap: () {
                  widget.onLanguageChanged(false);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showVoiceSheet() async {
    await showShadSheet<void>(
      context: context,
      builder: (context) => ShadSheet(
        title: Text(s.ttsVoice),
        child: _sheetBody(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _OptionRow(
                label: s.voiceStella,
                selected: _voice == 'stella',
                onTap: () {
                  setState(() => _voice = 'stella');
                  Navigator.of(context).pop();
                },
              ),
              _OptionRow(
                label: s.voiceTide,
                selected: _voice == 'tide',
                onTap: () {
                  setState(() => _voice = 'tide');
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLocationSheet() async {
    await showShadSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void apply(VoidCallback change) {
            setSheetState(change);
            setState(change);
          }

          final colors = ShadTheme.of(context).colorScheme;
          return ShadSheet(
            title: Text(s.location),
            description: Text(s.locationNote),
            actions: [
              ShadButton.outline(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(s.done),
              ),
            ],
            child: _sheetBody(
              _systemChinese
                  ? _chineseLocationPicker(colors, apply)
                  : _regionPicker(colors, apply),
            ),
          );
        },
      ),
    );
  }

  Widget _chineseLocationPicker(
    ShadColorScheme colors,
    void Function(VoidCallback) apply,
  ) {
    final cities = prototypeProvinces
        .where((item) => item.$1 == _province)
        .expand((item) => item.$2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PickerLabel(s.locationProvince),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChoicePill(
              key: const Key('province-none'),
              label: s.locationNone,
              selected: _province == null,
              onTap: () => apply(() {
                _province = null;
                _city = null;
                _region = null;
              }),
            ),
            for (final item in prototypeProvinces)
              _ChoicePill(
                key: Key('province-${item.$1}'),
                label: item.$1,
                selected: _province == item.$1,
                onTap: () => apply(() {
                  _region = null;
                  if (_province != item.$1) {
                    _province = item.$1;
                    _city = null;
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _PickerLabel(s.locationCity),
        if (_province == null)
          Text(
            s.chooseProvinceFirst,
            style: TextStyle(fontSize: 13, color: colors.mutedForeground),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChoicePill(
                key: const Key('city-none'),
                label: s.locationNone,
                selected: _city == null,
                onTap: () => apply(() => _city = null),
              ),
              for (final city in cities)
                _ChoicePill(
                  key: Key('city-$city'),
                  label: city,
                  selected: _city == city,
                  onTap: () => apply(() => _city = city),
                ),
            ],
          ),
      ],
    );
  }

  Widget _regionPicker(
    ShadColorScheme colors,
    void Function(VoidCallback) apply,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OptionRow(
              key: const Key('region-none'),
              label: s.locationNone,
              selected: _region == null,
              onTap: () => apply(() {
                _region = null;
                _province = null;
                _city = null;
              }),
            ),
            for (final region in prototypeRegions)
              _OptionRow(
                key: Key('region-$region'),
                label: region,
                selected: _region == region,
                onTap: () => apply(() {
                  _region = region;
                  _province = null;
                  _city = null;
                }),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 数据

  Future<void> _pickImportFile() async {
    final file = await showShadSheet<PrototypeFile>(
      context: context,
      builder: (context) => ShadSheet(
        title: Text(s.importPickTitle),
        description: Text(s.importPickNote),
        child: _sheetBody(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final file in prototypeFiles)
                _OptionRow(
                  key: Key(
                    file.tooLarge ? 'file-sample-large' : 'file-sample-normal',
                  ),
                  label: file.name,
                  detail: file.size,
                  selected: false,
                  onTap: () => Navigator.of(context).pop(file),
                ),
            ],
          ),
        ),
      ),
    );
    if (file == null || !mounted) return;
    await _confirmImport(file);
  }

  Future<void> _confirmImport(PrototypeFile file) async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(s.importConfirmTitle),
        description: Text(s.importConfirmDescription),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          ShadButton.destructive(
            key: const Key('import-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.importConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runTask(s.importing, s.importingNote);
    if (!mounted) return;
    setState(() {
      _importNote = file.tooLarge
          ? _Note(s.importFailed, error: true)
          : _Note(s.imported(3));
    });
  }

  Future<void> _runExport() async {
    await _runTask(s.exporting, s.importingNote);
    if (!mounted) return;
    setState(() {
      _exportNote = _exportFails
          ? _Note(s.exportFailed, error: true)
          : _Note(s.exported);
    });
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(s.deleteAllTitle),
        description: Text(s.deleteAllConfirmDescription),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          ShadButton.destructive(
            key: const Key('delete-all-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.deleteAllButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runTask(s.deleting, s.deleteAllDescription);
    if (!mounted) return;
    _toast(s.deleted);
  }

  Future<void> _runTask(String label, String note) async {
    unawaited(
      showShadDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: ShadDialog(
            title: Text(label),
            description: Text(note),
            actions: const [],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showDevSheet() async {
    await showShadSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => ShadSheet(
          title: Text(s.prototypeBadge),
          description: Text(s.devNote),
          child: _sheetBody(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _OptionRow(
                  key: const Key('dev-system-zh'),
                  label: s.devChineseSystem,
                  selected: _systemChinese,
                  onTap: () {
                    widget.onSystemChineseChanged(true);
                    setSheetState(() => _systemChinese = true);
                    setState(() => _systemChinese = true);
                  },
                ),
                _OptionRow(
                  key: const Key('dev-system-other'),
                  label: s.devOtherSystem,
                  selected: !_systemChinese,
                  onTap: () {
                    widget.onSystemChineseChanged(false);
                    setSheetState(() => _systemChinese = false);
                    setState(() => _systemChinese = false);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      s.devExportOutcome,
                      style: TextStyle(
                        fontSize: 12,
                        color: ShadTheme.of(context).colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                ),
                _OptionRow(
                  key: const Key('dev-export-ok'),
                  label: s.devSuccess,
                  selected: !_exportFails,
                  onTap: () {
                    setSheetState(() => _exportFails = false);
                    setState(() => _exportFails = false);
                  },
                ),
                _OptionRow(
                  key: const Key('dev-export-fail'),
                  label: s.devFailure,
                  selected: _exportFails,
                  onTap: () {
                    setSheetState(() => _exportFails = true);
                    setState(() => _exportFails = true);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toast(String message) {
    ShadToaster.of(context).show(ShadToast(description: Text(message)));
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
          children: [
            _Header(
              title: s.title,
              prototypeLabel: s.prototypeBadge,
              onBack: () => _toast(s.placeholderToast),
              onPrototype: _showDevSheet,
            ),
            _Section(
              title: s.sectionAccount,
              children: [
                _ValueRow(
                  key: const Key('settings-key'),
                  label: s.apiKey,
                  value: _apiKey == null ? s.apiKeyMissing : s.apiKeySaved,
                  onTap: _showKeyDialog,
                ),
                if (_apiKey != null) ...[
                  const _CardDivider(),
                  _ActionTextRow(
                    key: const Key('settings-clear-key'),
                    label: s.clearKey,
                    destructive: true,
                    onTap: _confirmClearKey,
                  ),
                ],
              ],
            ),
            _Section(
              title: s.sectionChat,
              children: [
                _ValueRow(
                  label: s.model,
                  value: 'deepseek-flash',
                  detail: s.modelFixed,
                  onTap: null,
                ),
                const _CardDivider(),
                _SwitchRow(
                  label: s.deepThinking,
                  description: s.toggleHint,
                  value: _thinking,
                  onChanged: (value) => setState(() => _thinking = value),
                ),
                const _CardDivider(),
                _SwitchRow(
                  label: s.smartSearch,
                  value: _search,
                  onChanged: (value) => setState(() => _search = value),
                ),
                const _CardDivider(),
                _ValueRow(
                  label: s.ttsVoice,
                  value: _voice == 'stella' ? s.voiceStella : s.voiceTide,
                  onTap: _showVoiceSheet,
                ),
              ],
            ),
            _Section(
              title: s.sectionAppearance,
              children: [
                _ThemePicker(
                  strings: s,
                  value: widget.themeMode,
                  onChanged: widget.onThemeChanged,
                ),
              ],
            ),
            _Section(
              title: s.sectionLocale,
              children: [
                _ValueRow(
                  key: const Key('settings-language'),
                  label: s.language,
                  value: widget.zh ? s.languageZh : s.languageEn,
                  onTap: _showLanguageSheet,
                ),
                const _CardDivider(),
                _ValueRow(
                  key: const Key('settings-location'),
                  label: s.location,
                  value: _locationLabel ?? s.locationUnset,
                  mutedValue: _locationLabel == null,
                  detail: s.locationNote,
                  onTap: _showLocationSheet,
                ),
              ],
            ),
            _Section(
              title: s.sectionSpeech,
              children: [
                _ValueRow(
                  label: s.micPermission,
                  value: s.micNotRequested,
                  mutedValue: true,
                  detail: s.micExplanation,
                  action: ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () => _toast(s.placeholderToast),
                    child: Text(s.systemSettings),
                  ),
                ),
              ],
            ),
            _Section(
              title: s.sectionData,
              children: [
                _DataRow(
                  key: const Key('settings-import'),
                  label: s.importHistory,
                  description: s.importDescription,
                  note: _importNote,
                  action: ShadButton.outline(
                    key: const Key('import-action'),
                    size: ShadButtonSize.sm,
                    onPressed: _pickImportFile,
                    child: Text(s.importAction),
                  ),
                ),
                const _CardDivider(),
                _DataRow(
                  key: const Key('settings-export'),
                  label: s.exportHistory,
                  description: s.exportDescription,
                  note: _exportNote,
                  action: ShadButton.outline(
                    key: const Key('export-action'),
                    size: ShadButtonSize.sm,
                    onPressed: _runExport,
                    child: Text(s.exportAction),
                  ),
                ),
                const _CardDivider(),
                _DataRow(
                  key: const Key('settings-delete'),
                  label: s.deleteAll,
                  description: s.deleteAllDescription,
                  action: ShadButton.destructive(
                    key: const Key('delete-all-action'),
                    size: ShadButtonSize.sm,
                    onPressed: _confirmDeleteAll,
                    child: Text(s.delete),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                s.mockDataNote,
                style: TextStyle(fontSize: 12, color: colors.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 组件

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.prototypeLabel,
    required this.onBack,
    required this.onPrototype,
  });

  final String title;
  final String prototypeLabel;
  final VoidCallback onBack;
  final VoidCallback onPrototype;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 18),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                LucideIcons.chevronLeft,
                size: 22,
                color: colors.foreground,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
              color: colors.foreground,
            ),
          ),
          const Spacer(),
          InkWell(
            key: const Key('prototype-controls'),
            onTap: onPrototype,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colors.muted,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.slidersHorizontal,
                    size: 12,
                    color: colors.mutedForeground,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    prototypeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
                color: colors.mutedForeground,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: ShadTheme.of(context).colorScheme.border,
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.mutedValue = false,
    this.onTap,
    this.action,
  });

  final String label;
  final String value;
  final String? detail;
  final bool mutedValue;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, color: colors.foreground),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      detail!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (action != null)
              action!
            else ...[
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: mutedValue
                        ? colors.mutedForeground
                        : colors.foreground,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: colors.mutedForeground,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 15, color: colors.foreground),
                ),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ShadSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ActionTextRow extends StatelessWidget {
  const _ActionTextRow({
    super.key,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: destructive ? colors.destructive : colors.foreground,
          ),
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    super.key,
    required this.label,
    required this.description,
    required this.action,
    this.note,
  });

  final String label;
  final String description;
  final Widget action;
  final _Note? note;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 15, color: colors.foreground),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: colors.mutedForeground,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    note!.text,
                    style: TextStyle(
                      fontSize: 12,
                      color: note!.error
                          ? colors.destructive
                          : colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          action,
        ],
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({
    required this.strings,
    required this.value,
    required this.onChanged,
  });

  final SettingsStrings strings;
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final options = <(ThemeMode, String, Key)>[
      (ThemeMode.system, strings.themeSystem, const Key('theme-system')),
      (ThemeMode.light, strings.themeLight, const Key('theme-light')),
      (ThemeMode.dark, strings.themeDark, const Key('theme-dark')),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.theme,
            style: TextStyle(fontSize: 15, color: colors.foreground),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (mode, label, key) in options) ...[
                Expanded(
                  child: _ChoicePill(
                    key: key,
                    label: label,
                    selected: value == mode,
                    onTap: () => onChanged(mode),
                  ),
                ),
                if (mode != ThemeMode.dark) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.foreground : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? colors.foreground : colors.border,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: selected ? colors.background : colors.foreground,
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, color: colors.foreground),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(LucideIcons.check, size: 18, color: colors.foreground),
          ],
        ),
      ),
    );
  }
}

class _PickerLabel extends StatelessWidget {
  const _PickerLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: ShadTheme.of(context).colorScheme.mutedForeground,
        ),
      ),
    );
  }
}
