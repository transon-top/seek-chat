import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'markdown_theme.dart';

/// 主题种子；只补齐未被 chat-demo 令牌显式覆盖的 Material 角色。
const appThemeSeed = Color(0xFF4D6BFE);

/// 主按钮色；浅色取 chat-demo blue-500，深色取 blue-450。
const appPrimaryColor = Color(0xFF3964FE);
const appPrimaryColorDark = Color(0xFF5686FE);

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
    // 官方侧栏与对话层同为纯白，只靠内容层阴影分隔。
    fill: Color(0xFFFFFFFF),
    border: Color(0x0A000000),
    labelPrimary: Color(0xFF0F1115),
    labelTertiary: Color(0xFF81858C),
    brand: Color(0xFF3964FE),
    activeItemFill: Color(0xFFE4EDFD),
    activeItemForeground: Color(0xFF3964FE),
    elevatedFill: Color(0xFFFFFFFF),
    inputFill: Color(0xFFF4F4F5),
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
  // 配色照搬 chat-demo 令牌：浅色白底 + 蓝色气泡，深色 #151517 底 + 中性灰层。
  final scheme = brightness == Brightness.dark
      ? base.colorScheme.copyWith(
          primary: appPrimaryColorDark,
          onPrimary: const Color(0xFFFFFFFF),
          surface: const Color(0xFF151517),
          onSurface: const Color(0xFFF9FAFB),
          surfaceContainerLowest: const Color(0xFF151517),
          surfaceContainerLow: const Color(0xFF2C2C2E),
          surfaceContainer: const Color(0xFF2C2C2E),
          surfaceContainerHigh: const Color(0xFF353638),
          surfaceContainerHighest: const Color(0xFF353638),
          onSurfaceVariant: const Color(0xFFADB2B8),
          outline: const Color(0x29FFFFFF),
          outlineVariant: const Color(0x0FFFFFFF),
          error: const Color(0xFFF25A5A),
          onError: const Color(0xFFFFFFFF),
        )
      : base.colorScheme.copyWith(
          primary: appPrimaryColor,
          onPrimary: const Color(0xFFFFFFFF),
          surface: const Color(0xFFFFFFFF),
          onSurface: const Color(0xFF0F1115),
          surfaceContainerLowest: const Color(0xFFFFFFFF),
          surfaceContainerLow: const Color(0xFFFFFFFF),
          // 用户气泡：chat-demo blue-50。
          surfaceContainer: const Color(0xFFEDF3FE),
          surfaceContainerHigh: const Color(0xFFFFFFFF),
          surfaceContainerHighest: const Color(0xFFF5F6F7),
          onSurfaceVariant: const Color(0xFF81858C),
          outline: const Color(0x1F000000),
          outlineVariant: const Color(0x1A000000),
          error: const Color(0xFFEC1313),
          onError: const Color(0xFFFFFFFF),
        );
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
      popover: c.surfaceContainerHigh,
      popoverForeground: c.onSurface,
      primary: c.primary,
      primaryForeground: c.onPrimary,
      secondary: c.surfaceContainerHighest,
      secondaryForeground: c.onSurface,
      muted: c.surfaceContainerHighest,
      mutedForeground: c.onSurfaceVariant,
      accent: c.surfaceContainerHighest,
      accentForeground: c.onSurface,
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
