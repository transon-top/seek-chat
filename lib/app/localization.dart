import 'package:material_ui/material_ui.dart';

import '../l10n/generated/app_localizations.dart';

/// ZH
/// 应用与测试共用的本地化委托。
///
/// Material 委托必须来自 `material_ui`：`flutter_localizations` 的委托实现的
/// 是另一套 `MaterialLocalizations`，界面控件找不到它。
///
/// EN
/// Localization delegates shared by the app and tests.
///
/// Material delegates must come from `material_ui`: the `flutter_localizations`
/// delegates implement a different `MaterialLocalizations` that UI widgets cannot find.
const appLocalizationDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];
