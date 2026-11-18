import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/chat/chat_controller.dart';
import '../features/chat/chat_page.dart';
import '../features/sessions/home_page.dart';
import '../features/settings/settings_page.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/prefs/user_metadata_store.dart';
import 'localization.dart';

/// 应用壳：主题、双语、路由与生命周期接线。
///
/// 设置项接入后语言与主题由设置驱动（票 18）。
class OpenChatApp extends ConsumerStatefulWidget {
  const OpenChatApp({super.key});

  @override
  ConsumerState<OpenChatApp> createState() => _OpenChatAppState();
}

class _OpenChatAppState extends ConsumerState<OpenChatApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 进入后台时把各控制器内存中的流式回复补写一次（architecture.md §3）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    for (final controller in ref.read(activeChatControllersProvider)) {
      unawaited(controller.flush());
    }
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4D6BFE);
    final locale = ref.watch(userMetadataProvider).locale;
    return MaterialApp(
      title: 'Open Chat',
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      locale: Locale(locale),
      localizationsDelegates: appLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomePage(
        openChat: (context, sessionId) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatPage(sessionId: sessionId),
          ),
        ),
        openSettings: (context) => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
        cancelSession: (sessionId) {
          for (final controller in ref.read(activeChatControllersProvider)) {
            if (controller.sessionId == sessionId) controller.stop();
          }
        },
      ),
    );
  }
}
