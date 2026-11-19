import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 主题种子；浅深两套由同一个 seed 生成（票 18）。
const appThemeSeed = Color(0xFF4D6BFE);

/// Material 主题：供 Markdown / Mermaid / 原生控件使用。
///
/// 中文正文用稍高行高，英文保持 Material 默认。
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

/// shadcn 主题：颜色全部由 Material 种子映射，不维护第二套色表（ui.md §3.1）。
ShadThemeData buildShadTheme({
  required Brightness brightness,
  required bool chinese,
}) {
  final material = buildAppTheme(brightness: brightness, chinese: chinese);
  final c = material.colorScheme;
  return ShadThemeData(
    brightness: brightness,
    colorScheme: ShadColorScheme(
      background: c.surface,
      foreground: c.onSurface,
      card: c.surfaceContainerLow,
      cardForeground: c.onSurface,
      popover: c.surfaceContainerLow,
      popoverForeground: c.onSurface,
      primary: c.primary,
      primaryForeground: c.onPrimary,
      secondary: c.secondaryContainer,
      secondaryForeground: c.onSecondaryContainer,
      muted: c.surfaceContainerHighest,
      mutedForeground: c.onSurfaceVariant,
      accent: c.secondaryContainer,
      accentForeground: c.onSecondaryContainer,
      destructive: c.error,
      destructiveForeground: c.onError,
      border: c.outlineVariant,
      input: c.outlineVariant,
      ring: c.primary,
      selection: c.primary.withValues(alpha: 0.24),
    ),
    radius: const BorderRadius.all(Radius.circular(10)),
    textTheme: buildShadTextTheme(chinese: chinese),
  );
}

/// 显式覆盖全部 13 个样式，字体留空使用系统字体。
///
/// 未覆盖的样式会回退 shadcn 自带的 Geist 字体，违反票 18 的系统字体约束。
ShadTextTheme buildShadTextTheme({required bool chinese}) {
  TextStyle system(TextStyle style, {double? height}) => TextStyle(
    fontSize: style.fontSize,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    letterSpacing: style.letterSpacing,
    wordSpacing: style.wordSpacing,
    height: height ?? style.height,
    decoration: style.decoration,
    textBaseline: style.textBaseline,
    leadingDistribution: style.leadingDistribution,
  );

  TextStyle build(TextStyle Function({required String family}) template) =>
      system(template(family: ''));

  final bodyHeight = chinese ? 1.6 : null;
  return ShadTextTheme.custom(
    canMerge: false,
    h1Large: build(ShadTextDefaultTheme.h1Large),
    h1: build(ShadTextDefaultTheme.h1),
    h2: build(ShadTextDefaultTheme.h2),
    h3: build(ShadTextDefaultTheme.h3),
    h4: build(ShadTextDefaultTheme.h4),
    p: system(ShadTextDefaultTheme.p(family: ''), height: bodyHeight),
    blockquote: system(
      ShadTextDefaultTheme.blockquote(family: ''),
      height: bodyHeight,
    ),
    table: build(ShadTextDefaultTheme.table),
    list: system(ShadTextDefaultTheme.list(family: ''), height: bodyHeight),
    lead: build(ShadTextDefaultTheme.lead),
    large: build(ShadTextDefaultTheme.large),
    small: build(ShadTextDefaultTheme.small),
    muted: build(ShadTextDefaultTheme.muted),
    family: '',
  );
}
