/// 票 09 / 20 原型共用的 shadcn 主题。
///
/// 仅用于原型；生产主题由 `lib/app/theme.dart` 用种子 `#4D6BFE` 生成。
library;

import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

ShadThemeData prototypeShadTheme(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return ShadThemeData(
      brightness: Brightness.dark,
      colorScheme: const ShadNeutralColorScheme.dark(
        background: Color(0xFF1B1B1D),
        card: Color(0xFF232326),
        foreground: Color(0xFFF2F2F3),
        muted: Color(0xFF2C2C30),
        mutedForeground: Color(0xFF939399),
        secondary: Color(0xFF2C2C30),
        secondaryForeground: Color(0xFFF2F2F3),
        accent: Color(0xFF2C2C30),
        accentForeground: Color(0xFFF2F2F3),
        border: Color(0xFF34343A),
        input: Color(0xFF34343A),
        primary: Color(0xFF6B7CFF),
        primaryForeground: Color(0xFFFFFFFF),
        destructive: Color(0xFFF16A6A),
      ),
    );
  }
  return ShadThemeData(
    brightness: Brightness.light,
    colorScheme: const ShadNeutralColorScheme.light(
      foreground: Color(0xFF111113),
      muted: Color(0xFFF4F5F7),
      mutedForeground: Color(0xFF8A8F98),
      secondary: Color(0xFFF4F5F7),
      secondaryForeground: Color(0xFF111113),
      accent: Color(0xFFF4F5F7),
      accentForeground: Color(0xFF111113),
      border: Color(0xFFE8EAED),
      input: Color(0xFFE8EAED),
      primary: Color(0xFF5B6CFF),
      primaryForeground: Color(0xFFFFFFFF),
      destructive: Color(0xFFE5484D),
    ),
  );
}
