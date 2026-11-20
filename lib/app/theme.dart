import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'markdown_theme.dart';

/// 主题种子；浅深两套由同一个 seed 生成（票 18）。
const appThemeSeed = Color(0xFF4D6BFE);

/// 主按钮色；种子生成的主色不等于品牌色，按钮显式指定。
const appPrimaryColor = Color(0xFF3964FE);

/// 会话抽屉配色：照搬 chat-demo 侧边栏令牌，仅供抽屉使用，不并入全局色表。
class AppSidebarColors {
  const AppSidebarColors({
    required this.fill,
    required this.border,
    required this.labelPrimary,
    required this.labelTertiary,
    required this.brand,
    required this.activeItemFill,
    required this.activeItemForeground,
    required this.elevatedFill,
    required this.inputFill,
    required this.menuFill,
    required this.danger,
  });

  static const light = AppSidebarColors(
    fill: Color(0xFFF9FAFB),
    border: Color(0x0A000000),
    labelPrimary: Color(0xFF0F1115),
    labelTertiary: Color(0xFF81858C),
    brand: Color(0xFF3964FE),
    activeItemFill: Color(0xFFE4EDFD),
    activeItemForeground: Color(0xFF3964FE),
    elevatedFill: Color(0xFFFFFFFF),
    inputFill: Color(0xFFFFFFFF),
    menuFill: Color(0xFFFFFFFF),
    danger: Color(0xFFEC1313),
  );

  static const dark = AppSidebarColors(
    fill: Color(0xFF1B1B1C),
    border: Color(0x0FFFFFFF),
    labelPrimary: Color(0xFFF9FAFB),
    labelTertiary: Color(0xFFADB2B8),
    brand: Color(0xFF5686FE),
    activeItemFill: Color(0xFF353638),
    activeItemForeground: Color(0xFFFFFFFF),
    elevatedFill: Color(0xFF43454A),
    inputFill: Color(0xFF2C2C2E),
    menuFill: Color(0xFF353638),
    danger: Color(0xFFF25A5A),
  );

  final Color fill;
  final Color border;
  final Color labelPrimary;
  final Color labelTertiary;
  final Color brand;
  final Color activeItemFill;
  final Color activeItemForeground;
  final Color elevatedFill;
  final Color inputFill;
  final Color menuFill;
  final Color danger;
}

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
  // 深色参考图：中性炭灰层级，不用种子生成的蓝紫色表面。
  final scheme = brightness == Brightness.dark
      ? base.colorScheme.copyWith(
          primary: appPrimaryColor,
          onPrimary: const Color(0xFFFFFFFF),
          surface: const Color(0xFF1C1C1E),
          onSurface: const Color(0xFFEDEDEF),
          surfaceContainerLowest: const Color(0xFF171719),
          surfaceContainerLow: const Color(0xFF2B2B2D),
          surfaceContainer: const Color(0xFF313133),
          surfaceContainerHigh: const Color(0xFF363638),
          surfaceContainerHighest: const Color(0xFF3C3C3E),
          onSurfaceVariant: const Color(0xFF9E9EA3),
          outline: const Color(0xFF5A5A5E),
          outlineVariant: const Color(0xFF3D3D40),
        )
      : base.colorScheme.copyWith(primary: appPrimaryColor);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    // Markdown 样式照搬 chat-demo，见 `markdown_theme.dart`。
    extensions: [...base.extensions.values, buildMarkdownTheme(brightness)],
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
