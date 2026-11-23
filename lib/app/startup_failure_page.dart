import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../shared/logging.dart';
import '../shared/models/location.dart';
import '../shared/prefs/theme_store.dart';
import '../shared/prefs/user_metadata_store.dart';
import 'localization.dart';
import 'startup.dart';
import 'theme.dart';

/// ZH
/// 启动失败页的根：不进入 `ProviderScope`，主题与语言取自已读到的偏好；
/// 偏好读取失败时跟随系统。
///
/// EN
/// Root of the startup failure page: rendered outside any `ProviderScope`. Theme and
/// language come from the preferences read so far; when that read failed, the system
/// decides both.
class StartupFailureApp extends StatefulWidget {
  const StartupFailureApp({
    super.key,
    required this.failure,
    required this.deps,
    required this.onStarted,
  });

  final StartupFailure failure;
  final StartupDeps deps;
  final AppStarted onStarted;

  @override
  State<StartupFailureApp> createState() => _StartupFailureAppState();
}

class _StartupFailureAppState extends State<StartupFailureApp> {
  static const _retryKey = Key('startup-retry');
  static const _clearKey = Key('startup-clear-data');

  late StartupFailure _failure = widget.failure;
  bool _busy = false;
  bool _clearFailed = false;

  /// ZH
  /// 已存语言偏好；偏好未读到时为 null。
  ///
  /// EN
  /// Stored language preference; null when preferences could not be read.
  String? get _storedLocale {
    final preferences = _failure.preferences;
    return preferences == null
        ? null
        : UserMetadataStore(preferences).locale;
  }

  /// ZH
  /// 已存主题偏好；偏好未读到时跟随系统。
  ///
  /// EN
  /// Stored theme preference; follows the system when preferences could not be read.
  ThemeMode get _themeMode {
    final preferences = _failure.preferences;
    return preferences == null
        ? ThemeMode.system
        : ThemeStore(preferences).themeMode;
  }

  /// ZH
  /// 主题里的中文行高开关：优先已存语言，其次系统语言。
  ///
  /// EN
  /// Chinese line-height switch for the theme: stored language first, system language second.
  bool get _chinese {
    final stored = _storedLocale;
    if (stored != null) return isChineseLanguage(stored);
    final locales = WidgetsBinding.instance.platformDispatcher.locales;
    return locales.isNotEmpty && isChineseLanguage(locales.first.languageCode);
  }

  /// ZH
  /// 重试 = 从头重跑启动链：先关掉失败的那次连接，再新建数据库实例、
  /// 重新读取偏好。成功后由 [StartupFailureApp.onStarted] 二次 `runApp`。
  ///
  /// EN
  /// Retry reruns the chain from scratch: close the failed connection, create a new
  /// database instance and read preferences again. On success the page hands the result
  /// to [StartupFailureApp.onStarted].
  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _clearFailed = false;
    });
    try {
      await _failure.database?.close();
    } on Object catch (error) {
      debugLog('closing failed database failed', error);
    }
    try {
      final result = await bootstrap(widget.deps);
      if (!mounted) return;
      widget.onStarted(result);
    } on StartupFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure;
        _busy = false;
      });
    }
  }

  /// ZH
  /// 二次确认后清除本地会话与附件；成功后自动重试，失败留在本页提示。
  ///
  /// EN
  /// Clear local chats and attachments after confirmation; retry automatically on success
  /// and stay on this page with a message on failure.
  Future<void> _confirmClearData(BuildContext pageContext) async {
    if (_busy) return;
    final confirmed = await showShadDialog<bool>(
      context: pageContext,
      // ZH
      // 本地化必须在 ShadApp 之下读取；State 的 context 在它之上。
      //
      // EN
      // Localizations live below ShadApp; the State's context sits above it.
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return ShadDialog.alert(
          title: Text(l10n.startupClearDataConfirmTitle),
          description: Text(l10n.startupClearDataConfirmBody),
          actions: [
            _minTapTarget(
              ShadButton.outline(
                key: const Key('startup-clear-data-cancel'),
                height: 0,
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
            ),
            _minTapTarget(
              ShadButton.destructive(
                key: const Key('startup-clear-data-confirm'),
                height: 0,
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.startupClearDataConfirm),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await _clearLocalData();
  }

  /// ZH
  /// 主按钮的点击目标至少 48×48；不固定高度（`height: 0` 让 shadcn 按内容撑开），
  /// 系统字号放大时按钮随文字长高。
  ///
  /// EN
  /// Buttons keep a tap target of at least 48×48 without a fixed height (`height: 0`
  /// makes shadcn size to the content), so they grow with the system font size.
  Widget _minTapTarget(Widget button) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: button,
  );

  Future<void> _clearLocalData() async {
    setState(() {
      _busy = true;
      _clearFailed = false;
    });
    try {
      await widget.deps.clearChatsAndAttachments(_failure.database);
    } on Object catch (error) {
      debugLog('clearing local data failed', error);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _clearFailed = true;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _retry();
  }

  @override
  Widget build(BuildContext context) {
    final storedLocale = _storedLocale;
    final chinese = _chinese;
    return ShadApp(
      title: 'SeekChat',
      theme: buildShadTheme(brightness: Brightness.light, chinese: chinese),
      darkTheme: buildShadTheme(brightness: Brightness.dark, chinese: chinese),
      themeMode: _themeMode,
      locale: storedLocale == null ? null : Locale(storedLocale),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      materialThemeBuilder: (context, theme) =>
          buildAppTheme(brightness: theme.brightness, chinese: chinese),
      // ZH
      // 页面要读 `AppLocalizations`，必须建在 ShadApp 的本地化之下。
      //
      // EN
      // The page reads `AppLocalizations`, so it must build below ShadApp's localizations.
      home: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final texts = theme.textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    LucideIcons.circleAlert,
                    size: 48,
                    color: colors.destructive,
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    key: const Key('startup-title'),
                    header: true,
                    child: Text(
                      l10n.startupFailedTitle,
                      textAlign: TextAlign.center,
                      style: texts.h3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    key: const Key('startup-body'),
                    liveRegion: true,
                    child: Text(
                      l10n.startupFailedBody,
                      textAlign: TextAlign.center,
                      style: texts.p.copyWith(color: colors.foreground),
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${_failure.error}',
                      textAlign: TextAlign.center,
                      style: texts.small.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                  ],
                  if (_clearFailed) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.startupClearDataFailed,
                        textAlign: TextAlign.center,
                        style: texts.small.copyWith(color: colors.destructive),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _minTapTarget(
                    ShadButton(
                      key: _retryKey,
                      height: 0,
                      onPressed: _busy ? null : _retry,
                      child: Flexible(child: Text(l10n.retry)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _minTapTarget(
                    ShadButton.destructive(
                      key: _clearKey,
                      height: 0,
                      onPressed: _busy
                          ? null
                          : () => _confirmClearData(context),
                      child: Flexible(
                        child: Text(
                          l10n.startupClearData,
                          textAlign: TextAlign.center,
                        ),
                      ),
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
}
