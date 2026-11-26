import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'settings_widgets.dart';

/// ZH
/// 数据管理：导入、导出与删除全部历史对话；内容由 `app/` 注入。
///
/// EN
/// Data: import, export and delete all chats; the content is injected by `app/`.
class DataSettingsPage extends StatelessWidget {
  const DataSettingsPage({super.key, this.dataManagement});

  /// ZH
  /// 历史导入导出区，由 `app/router.dart` 注入，设置功能不直接 import 其他功能目录。
  ///
  /// EN
  /// History import/export section injected by `app/router.dart`; settings never imports other features.
  final Widget? dataManagement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = SettingsPalette.of(context);
    final dataManagement = this.dataManagement;
    return SettingsScaffold(
      title: l10n.settingsData,
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
            child: dataManagement == null
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: palette.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: dataManagement,
                  ),
          ),
        ),
      ),
    );
  }
}
