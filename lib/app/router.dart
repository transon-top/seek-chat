import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/chat/chat_controller.dart';
import '../features/history/history_section.dart';
import '../features/settings/settings_account_page.dart';
import '../features/settings/settings_data_page.dart';
import '../features/settings/settings_font_size_page.dart';
import '../features/settings/settings_location_page.dart';
import '../features/settings/settings_page.dart';
import '../shared/providers.dart';
import 'chat_home.dart';

/// ZH
/// 应用路由表：聊天根页与设置路由树（官方布局的独立页面）。
///
/// EN
/// App route table: the chat root and the settings tree (standalone pages, official layout).
GoRouter buildAppRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ChatHome()),
    GoRoute(
      path: SettingsRoutes.root,
      builder: (context, state) => const SettingsPage(),
      routes: [
        GoRoute(
          path: 'account',
          builder: (context, state) => AccountSettingsPage(
            focusApiKey: state.uri.queryParameters['focus'] == '1',
          ),
        ),
        GoRoute(
          path: 'data',
          builder: (context, state) => const _DataSettingsRoute(),
        ),
        GoRoute(
          path: 'font-size',
          builder: (context, state) => const FontSizeSettingsPage(),
        ),
        GoRoute(
          path: 'location',
          builder: (context, state) => const LocationSettingsPage(),
        ),
      ],
    ),
  ],
);

/// ZH
/// 数据管理页的历史区由 `app/` 组装，避免设置功能直接 import 历史功能。
///
/// EN
/// `app/` assembles the history section for the Data page, so settings never imports history.
class _DataSettingsRoute extends ConsumerWidget {
  const _DataSettingsRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DataSettingsPage(
      dataManagement: HistorySection(
        stopGeneration: () {
          for (final controller in ref.read(activeChatControllersProvider)) {
            controller.stop();
          }
        },
        onImported: () => ref.read(historyReloadProvider.notifier).bump(),
      ),
    );
  }
}
