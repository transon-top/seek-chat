import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// 主题种子；浅深两套由同一个 seed 生成（票 18）。
const appThemeSeed = Color(0xFF4D6BFE);

/// 应用主题：中文正文用稍高行高，英文保持 Material 默认。
///
/// 状态栏图标亮度由 AppBar 底色推导；导航栏沿用系统默认。
ThemeData buildAppTheme({
  required Brightness brightness,
  required bool chinese,
}) {
  final base = ThemeData(colorSchemeSeed: appThemeSeed, brightness: brightness);
  final text = base.textTheme;
  return base.copyWith(
    textTheme: chinese
        ? text.copyWith(
            bodyLarge: text.bodyLarge?.copyWith(height: 1.6),
            bodyMedium: text.bodyMedium?.copyWith(height: 1.6),
            bodySmall: text.bodySmall?.copyWith(height: 1.6),
          )
        : text,
    appBarTheme: base.appBarTheme.copyWith(
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
  );
}
