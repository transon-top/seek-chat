import 'package:material_ui/material_ui.dart';

import '../l10n/generated/app_localizations.dart';

/// 应用与测试共用的本地化委托。
///
/// Material 委托必须来自 `material_ui`：`flutter_localizations` 的委托实现的
/// 是另一套 `MaterialLocalizations`，界面控件找不到它。
const appLocalizationDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];
